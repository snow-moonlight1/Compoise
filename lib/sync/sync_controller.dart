/// Decides when the app syncs and keeps the connection settings.
///
/// The engine runs one round when asked. This controller asks: a few seconds
/// after an edit is saved it stamps the edit locally, a little later it goes
/// online, and it also syncs on start, on resume and every few minutes while
/// the app is open. Failures back off; anything only the user can fix stops
/// the automatic rounds until the user acts.
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'sync_engine.dart';
import 'sync_local.dart';
import 'sync_provider.dart';
import 'sync_remote.dart';
import 'sync_store_host.dart';

typedef SyncTimerFactory =
    Timer Function(Duration delay, void Function() callback);

Timer _realTimer(Duration delay, void Function() callback) =>
    Timer(delay, callback);

/// Why the controller cannot reach the vault without the user.
enum SyncConnectionProblem {
  /// The connection settings are gone or unreadable.
  missingSettings,

  /// Secure storage has no provider secret; sign in again.
  missingSecret,

  /// Secure storage itself failed, for example a locked Linux keyring.
  secureStorage,

  /// This build cannot talk to the provider the vault was set up with.
  unsupportedProvider,
}

/// Secure storage refused the provider secret.
class SyncSecureStorageException implements Exception {
  const SyncSecureStorageException(this.cause);

  final Object cause;

  @override
  String toString() => 'SyncSecureStorageException: $cause';
}

class SyncController extends ChangeNotifier {
  SyncController({
    required this.engine,
    required this.source,
    required this.localStore,
    required this.secrets,
    this.remoteFactory = defaultSyncRemoteFactory,
    SyncTimerFactory? timer,
    DateTime Function()? now,
    this.absorbDelay = const Duration(seconds: 4),
    this.editSyncDelay = const Duration(seconds: 20),
    this.startDelay = const Duration(seconds: 3),
    this.periodicInterval = const Duration(minutes: 10),
    this.resumeInterval = const Duration(minutes: 1),
    this.firstRetry = const Duration(seconds: 30),
    this.maxRetry = const Duration(minutes: 15),
  }) : _timer = timer ?? _realTimer,
       _now = now ?? DateTime.now;

  final SyncEngine engine;
  final SyncLibrarySource source;
  final SyncLocalStore localStore;
  final SyncSecrets secrets;
  final SyncRemoteFactory remoteFactory;
  final SyncTimerFactory _timer;
  final DateTime Function() _now;

  final Duration absorbDelay;
  final Duration editSyncDelay;
  final Duration startDelay;
  final Duration periodicInterval;
  final Duration resumeInterval;
  final Duration firstRetry;
  final Duration maxRetry;

  SyncProviderConfig? _config;
  SyncConnectionProblem? _problem;
  bool _started = false;
  bool _disposed = false;
  bool _foreground = true;
  int _seenRevision = -1;
  int _failures = 0;
  DateTime? _lastAttempt;
  DateTime? _nextRetryAt;
  Timer? _absorbTimer;
  Timer? _syncTimer;
  Timer? _retryTimer;
  Timer? _periodicTimer;
  Future<void> _absorbing = Future.value();
  final List<VoidCallback> _disposeHooks = [];

  /// Runs [hook] when the controller is disposed, for listeners the app
  /// attached to it.
  void onDispose(VoidCallback hook) => _disposeHooks.add(hook);

  SyncProviderConfig? get config => _config;
  SyncConnectionProblem? get problem => _problem;
  SyncStatus get status => engine.status;
  bool get joined => engine.joined;
  bool get connected => engine.joined && _problem == null;
  DateTime? get nextRetryAt => _nextRetryAt;
  List<SyncDeviceView> get devices => engine.devices;

  /// Loads the saved connection and schedules the first round.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    await engine.load();
    _config = SyncProviderConfig.decode(await localStore.loadProvider());
    engine.addListener(_relay);
    source.addListener(_onLibraryChanged);
    _seenRevision = source.syncRevision;
    if (engine.joined) {
      await _attach();
      _schedule(startDelay);
    }
    _armPeriodic();
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelTimers();
    for (final hook in _disposeHooks) {
      hook();
    }
    if (_started) {
      engine.removeListener(_relay);
      source.removeListener(_onLibraryChanged);
    }
    super.dispose();
  }

  void _relay() => _notify();

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _cancelTimers() {
    _absorbTimer?.cancel();
    _syncTimer?.cancel();
    _retryTimer?.cancel();
    _periodicTimer?.cancel();
    _absorbTimer = _syncTimer = _retryTimer = _periodicTimer = null;
  }

  Future<bool> _attach() async {
    final config = _config;
    if (config == null) {
      _problem = SyncConnectionProblem.missingSettings;
      return false;
    }
    engine.deviceName = config.deviceName;
    final String? secret;
    try {
      secret = await secrets.provider.read();
    } catch (_) {
      _problem = SyncConnectionProblem.secureStorage;
      return false;
    }
    if (secret == null || secret.isEmpty) {
      _problem = SyncConnectionProblem.missingSecret;
      return false;
    }
    try {
      engine.attach(remoteFactory(config, secret));
    } on UnsupportedError {
      _problem = SyncConnectionProblem.unsupportedProvider;
      return false;
    }
    _problem = null;
    return true;
  }

  // --- setup ---

  /// Checks the connection and reports what the folder holds. Throws
  /// [SyncRemoteException] when the provider refuses.
  Future<RemoteVaultInfo> probe(SyncProviderConfig config, String secret) =>
      engine.inspect(remoteFactory(config, secret));

  /// Creates a vault in an empty folder or joins the one there, then runs
  /// the first round. Setup errors are rethrown with nothing saved.
  Future<SyncReport?> connect(
    SyncProviderConfig config,
    String secret, {
    String? password,
    SyncJoinMode? mode,
  }) async {
    if (engine.joined) {
      throw const SyncSetupException(SyncSetupError.alreadyJoined);
    }
    final remote = remoteFactory(config, secret);
    final previousConfig = _config;
    await _writeSecret(secret);
    await localStore.saveProvider(config.encode());
    _config = config;
    engine.deviceName = config.deviceName;
    try {
      final info = await engine.inspect(remote);
      final pending = info.vault == null
          ? engine.createVault(
              remote,
              provider: config.kind.name,
              password: password,
            )
          : engine.joinVault(
              remote,
              provider: config.kind.name,
              password: password,
              mode: mode,
            );
      _problem = null;
      _resetBackoff();
      _seenRevision = source.syncRevision;
      _lastAttempt = _now();
      final report = await pending;
      _afterRound();
      return report;
    } catch (_) {
      if (!engine.joined) {
        _config = previousConfig;
        await _forget();
      }
      _notify();
      rethrow;
    }
  }

  /// Replaces the provider secret after the provider rejected it, for
  /// example a changed WebDAV password.
  Future<SyncReport?> updateSecret(String secret) async {
    await _writeSecret(secret);
    if (!await _attach()) {
      _notify();
      return null;
    }
    return syncNow();
  }

  Future<void> _writeSecret(String secret) async {
    try {
      await secrets.provider.write(secret);
    } catch (error) {
      throw SyncSecureStorageException(error);
    }
  }

  Future<void> renameDevice(String name) async {
    final config = _config;
    if (config == null) return;
    _config = config.copyWith(deviceName: name);
    engine.deviceName = name;
    await localStore.saveProvider(_config!.encode());
    _notify();
    _schedule(Duration.zero);
  }

  Future<SyncReport?> unlock(String password) async {
    _resetBackoff();
    final report = await engine.unlock(password);
    _afterRound();
    return report;
  }

  Future<SyncReport?> acceptPlainVault() async {
    _resetBackoff();
    final report = await engine.acceptPlainVault();
    _afterRound();
    return report;
  }

  Future<SyncReport?> changePassword(String? password) async {
    _resetBackoff();
    final report = await engine.changePassword(password);
    _afterRound();
    return report;
  }

  Future<void> removeDevice(String deviceId) => engine.removeDevice(deviceId);

  /// Stops syncing on this device. The library stays.
  Future<void> disconnect({bool deleteOwnFile = false}) async {
    _cancelTimers();
    await engine.disconnect(deleteOwnFile: deleteOwnFile);
    await _forget();
    _config = null;
    _problem = null;
    _resetBackoff();
    _armPeriodic();
    _notify();
  }

  Future<void> _forget() async {
    await localStore.saveProvider(null);
    try {
      await secrets.provider.delete();
    } catch (_) {
      // A stale secret without settings is never read again.
    }
  }

  // --- scheduling ---

  /// The app moved to or from the foreground. Going to the background stamps
  /// and uploads pending edits at once: the system may stop the app soon.
  void setForeground(bool foreground) {
    if (_foreground == foreground) return;
    _foreground = foreground;
    if (!foreground) {
      _periodicTimer?.cancel();
      _periodicTimer = null;
      if (_absorbTimer != null || _syncTimer != null) _schedule(Duration.zero);
      return;
    }
    _armPeriodic();
    final last = _lastAttempt;
    if (last == null || _now().difference(last) >= resumeInterval) {
      _schedule(Duration.zero);
    }
  }

  /// Runs a round now, ignoring backoff.
  Future<SyncReport?> syncNow() {
    _resetBackoff();
    return _runRound(manual: true);
  }

  void _armPeriodic() {
    _periodicTimer?.cancel();
    _periodicTimer = null;
    if (!_foreground || _disposed) return;
    _periodicTimer = _timer(periodicInterval, () {
      _periodicTimer = null;
      _armPeriodic();
      if (_retryTimer == null) _runRound();
    });
  }

  void _onLibraryChanged() {
    final revision = source.syncRevision;
    if (revision == _seenRevision) return;
    _seenRevision = revision;
    // The engine's own download is already in the sync state.
    if (revision == source.syncAppliedRevision) return;
    if (!engine.joined) return;
    _absorbTimer?.cancel();
    _absorbTimer = _timer(absorbDelay, () {
      _absorbTimer = null;
      _absorbing = _absorbNow();
    });
    _syncTimer ??= _timer(editSyncDelay, () {
      _syncTimer = null;
      _runRound();
    });
  }

  void _schedule(Duration delay) {
    _syncTimer?.cancel();
    _syncTimer = _timer(delay, () {
      _syncTimer = null;
      _runRound();
    });
  }

  bool get _blocked =>
      _problem != null ||
      engine.status.phase == SyncPhase.needsAttention ||
      engine.status.phase == SyncPhase.needsPassword;

  /// Stamps saved edits without going online.
  Future<void> _absorbNow() async {
    if (!engine.joined || _disposed) return;
    await source.settle();
    if (!source.syncLibraryDurable) {
      // Saving failed or recovery is open; try again once it settles.
      _absorbTimer ??= _timer(absorbDelay, () {
        _absorbTimer = null;
        _absorbing = _absorbNow();
      });
      return;
    }
    try {
      await engine.absorbLocalEdits();
    } catch (error) {
      debugPrint('Sync absorb failed: ${error.runtimeType}');
    }
  }

  Future<SyncReport?> _runRound({bool manual = false}) async {
    if (_disposed || !engine.joined || _problem != null) return null;
    if (!manual && _blocked) return null;
    _absorbTimer?.cancel();
    _absorbTimer = null;
    _syncTimer?.cancel();
    _syncTimer = null;
    await _absorbing;
    await source.settle();
    if (!source.syncLibraryDurable) {
      _scheduleRetry(null);
      return null;
    }
    _lastAttempt = _now();
    final report = await engine.sync();
    _afterRound();
    return report;
  }

  void _afterRound() {
    if (_disposed) return;
    final status = engine.status;
    switch (status.phase) {
      case SyncPhase.idle:
        if (status.issue == SyncIssue.busy) {
          _scheduleRetry(firstRetry);
        } else {
          _resetBackoff();
        }
      case SyncPhase.error:
        _scheduleRetry(status.retryAfter);
      case SyncPhase.off:
      case SyncPhase.syncing:
      case SyncPhase.needsAttention:
      case SyncPhase.needsPassword:
        _retryTimer?.cancel();
        _retryTimer = null;
        _nextRetryAt = null;
    }
    _notify();
  }

  void _resetBackoff() {
    _failures = 0;
    _retryTimer?.cancel();
    _retryTimer = null;
    _nextRetryAt = null;
  }

  /// Backs off 30 s, 1, 2, 4, 8 then 15 minutes; a provider's Retry-After
  /// wins when it is longer.
  void _scheduleRetry(Duration? requested) {
    _failures++;
    final exponent = min(_failures - 1, 10);
    var delay = firstRetry * pow(2, exponent).toInt();
    if (delay > maxRetry) delay = maxRetry;
    if (requested != null && requested > delay) delay = requested;
    _retryTimer?.cancel();
    _nextRetryAt = _now().add(delay);
    _retryTimer = _timer(delay, () {
      _retryTimer = null;
      _nextRetryAt = null;
      _runRound();
    });
  }
}
