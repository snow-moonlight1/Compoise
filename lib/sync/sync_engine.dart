/// Runs sync rounds against one [SyncRemote] for one library host.
///
/// A round: capture the library, list the folder, download the device files
/// that changed, compute the merge on a background isolate, commit the result
/// through the host (which refuses if the user edited meanwhile), persist the
/// merged state, and upload this device's file when its content changed.
/// Every step can fail without touching the task library: the host commit is
/// the only write to it, and it validates every record and commits atomically.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../diagnostics/app_log.dart';

import 'sync_crypto.dart';
import 'sync_files.dart';
import 'sync_library.dart';
import 'sync_local.dart';
import 'sync_remote.dart';
import 'sync_round.dart';
import 'sync_state.dart';

export 'sync_local.dart' show SyncJoinMode;

class SyncSnapshot {
  const SyncSnapshot({required this.revision, required this.library});

  /// Changes with every accepted edit; [SyncHost.apply] compares it.
  final int revision;
  final SyncLibrary library;
}

enum SyncApplyOutcome { applied, stale, failed }

/// The task library as the engine sees it. The store implements this.
abstract class SyncHost {
  SyncSnapshot capture();

  /// Replaces the synced part of the library with [library] in one commit,
  /// unless anything was accepted after [baseRevision].
  Future<SyncApplyOutcome> apply(int baseRevision, SyncLibrary library);
}

/// Secure storage for the derived vault key. Never the password.
abstract class SyncKeyStore {
  Future<Uint8List?> read();
  Future<void> write(Uint8List key);
  Future<void> delete();
}

class MemorySyncKeyStore implements SyncKeyStore {
  Uint8List? key;

  @override
  Future<Uint8List?> read() async => key;

  @override
  Future<void> write(Uint8List value) async => key = Uint8List.fromList(value);

  @override
  Future<void> delete() async => key = null;
}

/// Runs [job] somewhere. Production uses a background isolate.
typedef SyncRunner = Future<T> Function<T>(FutureOr<T> Function() job);

Future<T> isolateSyncRunner<T>(FutureOr<T> Function() job) => Isolate.run(job);

Future<T> inlineSyncRunner<T>(FutureOr<T> Function() job) async => job();

enum SyncPhase {
  /// Not joined to any vault.
  off,
  idle,
  syncing,

  /// The vault is encrypted and this device has no (valid) key.
  needsPassword,

  /// Something only the user can decide; see [SyncStatus.issue].
  needsAttention,

  /// The last round failed; the scheduler will try again.
  error,
}

enum SyncIssue {
  /// `vault.json` is gone from the folder.
  vaultMissing,

  /// The folder now holds a different vault.
  vaultReplaced,

  /// Another device set or changed the password.
  passwordChanged,

  /// Another device removed the password; continuing uploads plain files.
  encryptionRemoved,

  /// The vault file cannot be read.
  vaultUnreadable,

  /// A newer app version wrote the vault.
  newerFormat,

  /// Startup recovery is still waiting for the user; syncing would spread
  /// partially restored text.
  pendingRestore,

  /// The library kept changing during the round; it runs again later.
  busy,

  /// The library commit failed.
  localWrite,

  network,
  auth,
  forbidden,
  quota,
  rateLimited,
  server,
  protocol,
}

class SyncStatus {
  const SyncStatus(
    this.phase, {
    this.issue,
    this.lastSuccessAt,
    this.retryAfter,
    this.unreadablePeers = 0,
  });

  final SyncPhase phase;
  final SyncIssue? issue;
  final int? lastSuccessAt;
  final Duration? retryAfter;

  /// Device files skipped because they could not be read.
  final int unreadablePeers;

  @override
  String toString() => 'SyncStatus(${phase.name}, ${issue?.name})';
}

class SyncReport {
  const SyncReport({
    required this.downloaded,
    required this.applied,
    required this.uploaded,
    required this.unreadablePeers,
  });

  final int downloaded;
  final bool applied;
  final bool uploaded;
  final int unreadablePeers;
}

enum SyncSetupError {
  alreadyJoined,
  notJoined,
  vaultExists,
  vaultMissing,
  vaultUnreadable,
  newerFormat,
  passwordRequired,
  wrongPassword,
  syncFailed,
}

class SyncSetupException implements Exception {
  const SyncSetupException(this.kind, [this.cause]);

  final SyncSetupError kind;
  final Object? cause;

  @override
  String toString() => 'SyncSetupException(${kind.name}): $cause';
}

/// What a folder holds, shown before joining it.
class RemoteVaultInfo {
  const RemoteVaultInfo({required this.vault, required this.deviceFiles});

  final SyncVault? vault;
  final int deviceFiles;

  bool get exists => vault != null;
  bool get encrypted => vault?.encrypted ?? false;
}

class SyncDeviceView {
  const SyncDeviceView({
    required this.id,
    required this.isThisDevice,
    this.info,
    this.writtenAt,
    this.unreadable = false,
  });

  final String id;
  final bool isThisDevice;
  final SyncDeviceInfo? info;
  final int? writtenAt;
  final bool unreadable;
}

class SyncEngine extends ChangeNotifier {
  SyncEngine({
    required this.host,
    required this.localStore,
    required this.keyStore,
    required this.deviceName,
    required this.platform,
    required this.appVersion,
    SyncRunner? runner,
    int Function()? nowMs,
    this.inlineKdf = false,
    Random? random,
  }) : _runner = runner ?? isolateSyncRunner,
       _nowMs = nowMs ?? _wallMs,
       _random = random ?? Random.secure();

  final SyncHost host;
  final SyncLocalStore localStore;
  final SyncKeyStore keyStore;
  String deviceName;
  final String platform;
  final String appVersion;
  final SyncRunner _runner;
  final int Function() _nowMs;
  final Random _random;

  /// Tests derive keys on the calling isolate.
  final bool inlineKdf;

  static int _wallMs() => DateTime.now().millisecondsSinceEpoch;

  SyncRemote? _remote;
  SyncLocalMeta? _meta;
  Uint8List? _key;
  String? _verifiedVaultVersion;
  (String, SyncVault)? _vaultCache;
  Future<void> _serial = Future.value();
  Future<SyncReport?>? _inFlight;
  bool _again = false;

  SyncStatus _status = const SyncStatus(SyncPhase.off);
  SyncStatus get status => _status;

  bool get loaded => _meta != null;
  bool get joined => _meta?.joined ?? false;
  String? get provider => _meta?.provider;
  bool get encrypted => _meta?.encrypted ?? false;
  String get deviceId => _meta!.deviceId;
  SyncRemote? get remote => _remote;

  SyncDeviceInfo get _device => SyncDeviceInfo(
    id: _meta!.deviceId,
    name: deviceName,
    platform: platform,
    appVersion: appVersion,
  );

  String get _ownFile => deviceFileName(_meta!.deviceId);

  void _setStatus(SyncStatus next) {
    _status = next;
    notifyListeners();
  }

  SyncStatus _with(SyncPhase phase, {SyncIssue? issue, Duration? retryAfter}) =>
      SyncStatus(
        phase,
        issue: issue,
        lastSuccessAt: _meta?.lastSuccessAt,
        retryAfter: retryAfter,
        unreadablePeers: _unreadablePeers,
      );

  int get _unreadablePeers =>
      _meta?.peers.values.where((peer) => peer.problem != null).length ?? 0;

  /// Devices known from the last rounds, this device first.
  List<SyncDeviceView> get devices {
    final meta = _meta;
    if (meta == null || !meta.joined) return const [];
    final views = <SyncDeviceView>[
      SyncDeviceView(
        id: meta.deviceId,
        isThisDevice: true,
        info: _device,
        writtenAt: meta.lastSuccessAt,
      ),
    ];
    final peers = meta.peers.entries.toList()
      ..sort(
        (a, b) => (b.value.writtenAt ?? 0).compareTo(a.value.writtenAt ?? 0),
      );
    for (final entry in peers) {
      final id = deviceIdOfFile(entry.key);
      if (id == null || id == meta.deviceId) continue;
      views.add(
        SyncDeviceView(
          id: id,
          isThisDevice: false,
          info: entry.value.device,
          writtenAt: entry.value.writtenAt,
          unreadable: entry.value.problem != null,
        ),
      );
    }
    return views;
  }

  Future<T> _exclusive<T>(Future<T> Function() body) {
    final previous = _serial;
    final done = Completer<T>();
    _serial = () async {
      await previous;
      try {
        done.complete(await body());
      } catch (error, stack) {
        done.completeError(error, stack);
      }
    }();
    return done.future;
  }

  /// Loads what this device remembers. Call once before anything else.
  Future<void> load() => _exclusive(() async {
    _meta = await localStore.loadMeta();
    if (_meta == null) {
      _meta = SyncLocalMeta(
        deviceId: SyncLocalMeta.newDeviceId(random: _random),
      );
      await localStore.saveMeta(_meta!);
    }
    _setStatus(_with(joined ? SyncPhase.idle : SyncPhase.off));
  });

  /// Connects the transport for the joined vault, for example after the app
  /// rebuilt it from saved settings.
  void attach(SyncRemote remote) {
    _remote = remote;
    _vaultCache = null;
    _verifiedVaultVersion = null;
  }

  Future<RemoteVaultInfo> inspect(SyncRemote remote) async {
    final entries = await remote.list();
    final deviceFiles = entries.where((e) => deviceIdOfFile(e.name) != null);
    if (!entries.any((entry) => entry.name == vaultFileName)) {
      return RemoteVaultInfo(vault: null, deviceFiles: deviceFiles.length);
    }
    return RemoteVaultInfo(
      vault: _decodeVault(await remote.read(vaultFileName)),
      deviceFiles: deviceFiles.length,
    );
  }

  SyncVault _decodeVault(List<int> bytes) {
    try {
      return SyncVault.decode(bytes);
    } on SyncFileException catch (error) {
      throw SyncSetupException(
        error.newerFormat
            ? SyncSetupError.newerFormat
            : SyncSetupError.vaultUnreadable,
        error,
      );
    }
  }

  String _newId() => SyncLocalMeta.newDeviceId(random: _random);

  Future<(KdfParams, Uint8List, String)> _newKey(
    String password,
    String vaultId,
  ) async {
    final params = KdfParams.random(random: _random);
    final key = await deriveVaultKey(password, params, inline: inlineKdf);
    return (params, key, await sealKeyCheck(key, vaultId));
  }

  /// Creates a vault in an empty folder and uploads this device's library.
  /// With no [password] the files are compressed but not encrypted.
  Future<SyncReport?> createVault(
    SyncRemote remote, {
    required String provider,
    String? password,
  }) async {
    await _exclusive(() async {
      final meta = _requireLoaded();
      if (meta.joined) {
        throw const SyncSetupException(SyncSetupError.alreadyJoined);
      }
      final entries = await remote.list();
      if (entries.any((entry) => entry.name == vaultFileName)) {
        throw const SyncSetupException(SyncSetupError.vaultExists);
      }
      final vaultId = _newId();
      KdfParams? kdf;
      Uint8List? key;
      String? check;
      if (password != null) {
        (kdf, key, check) = await _newKey(password, vaultId);
      }
      final vault = SyncVault(
        vaultId: vaultId,
        createdAt: _nowMs(),
        kdf: kdf,
        check: check,
      );
      try {
        await remote.create(vaultFileName, vault.encode());
      } on SyncRemoteException catch (error) {
        if (error.kind == SyncRemoteFailure.conflict) {
          throw const SyncSetupException(SyncSetupError.vaultExists);
        }
        rethrow;
      }
      // Device files without a vault belong to nobody any more.
      for (final entry in entries) {
        if (deviceIdOfFile(entry.name) != null) await remote.delete(entry.name);
      }
      await _adopt(
        remote,
        provider: provider,
        vault: vault,
        key: key,
        joinMode: SyncJoinMode.create,
      );
    });
    return sync();
  }

  /// Joins the vault already in [remote]. [mode] null picks
  /// [SyncJoinMode.replaceLocal] when this device holds nothing but the empty
  /// starter board, and [SyncJoinMode.merge] otherwise.
  Future<SyncReport?> joinVault(
    SyncRemote remote, {
    required String provider,
    String? password,
    SyncJoinMode? mode,
  }) async {
    await _exclusive(() async {
      final meta = _requireLoaded();
      if (meta.joined) {
        throw const SyncSetupException(SyncSetupError.alreadyJoined);
      }
      final info = await inspect(remote);
      final vault = info.vault;
      if (vault == null) {
        throw const SyncSetupException(SyncSetupError.vaultMissing);
      }
      final key = await _unlockKey(vault, password);
      final joinMode =
          mode ??
          (isPristine(host.capture().library)
              ? SyncJoinMode.replaceLocal
              : SyncJoinMode.merge);
      if (joinMode == SyncJoinMode.create) throw ArgumentError('mode');
      await _adopt(
        remote,
        provider: provider,
        vault: vault,
        key: key,
        joinMode: joinMode,
      );
    });
    return sync();
  }

  Future<Uint8List?> _unlockKey(SyncVault vault, String? password) async {
    if (!vault.encrypted) return null;
    if (password == null || password.isEmpty) {
      throw const SyncSetupException(SyncSetupError.passwordRequired);
    }
    final key = await deriveVaultKey(password, vault.kdf!, inline: inlineKdf);
    final bool ok;
    try {
      ok = await verifyKeyCheck(key, vault.vaultId, vault.check!);
    } on SyncCryptoException catch (error) {
      throw SyncSetupException(SyncSetupError.vaultUnreadable, error);
    }
    if (!ok) throw const SyncSetupException(SyncSetupError.wrongPassword);
    return key;
  }

  Future<void> _adopt(
    SyncRemote remote, {
    required String provider,
    required SyncVault vault,
    required Uint8List? key,
    required SyncJoinMode joinMode,
  }) async {
    final meta = _meta!;
    if (key == null) {
      await keyStore.delete();
    } else {
      await keyStore.write(key);
    }
    await localStore.saveState(null);
    await localStore.savePending(null);
    meta
      ..provider = provider
      ..vaultId = vault.vaultId
      ..encrypted = vault.encrypted
      ..joinMode = joinMode
      ..uploadedDigest = null
      ..lastSuccessAt = null
      ..peers.clear();
    await localStore.saveMeta(meta);
    _key = key;
    _remote = remote;
    _vaultCache = null;
    _verifiedVaultVersion = null;
  }

  /// Unlocks an encrypted vault on this device, including one whose password
  /// another device changed. Local history is kept.
  Future<SyncReport?> unlock(String password) async {
    await _exclusive(() async {
      final meta = _requireJoined();
      final remote = _remote!;
      final info = await inspect(remote);
      final vault = info.vault;
      if (vault == null) {
        throw const SyncSetupException(SyncSetupError.vaultMissing);
      }
      if (vault.vaultId != meta.vaultId &&
          !vault.lineage.contains(meta.vaultId)) {
        throw const SyncSetupException(SyncSetupError.vaultMissing);
      }
      final key = await _unlockKey(vault, password);
      if (key == null) {
        throw const SyncSetupException(SyncSetupError.vaultUnreadable);
      }
      await keyStore.write(key);
      _key = key;
      if (vault.vaultId != meta.vaultId) {
        _continueAs(meta, vault);
      }
      meta.encrypted = true;
      await localStore.saveMeta(meta);
      _vaultCache = null;
      _verifiedVaultVersion = null;
    });
    return sync();
  }

  /// Continues after another device removed the password.
  Future<SyncReport?> acceptPlainVault() async {
    await _exclusive(() async {
      final meta = _requireJoined();
      final info = await inspect(_remote!);
      final vault = info.vault;
      if (vault == null ||
          vault.encrypted ||
          !vault.lineage.contains(meta.vaultId)) {
        throw const SyncSetupException(SyncSetupError.vaultUnreadable);
      }
      _continueAs(meta, vault);
      meta.encrypted = false;
      await keyStore.delete();
      _key = null;
      await localStore.saveMeta(meta);
    });
    return sync();
  }

  void _continueAs(SyncLocalMeta meta, SyncVault vault) {
    meta
      ..vaultId = vault.vaultId
      ..uploadedDigest = null
      ..peers.clear();
  }

  /// Sets, changes or removes the password. The vault gets a new id that
  /// lists the old one, so the other devices carry on after unlocking.
  Future<SyncReport?> changePassword(String? password) async {
    final before = await sync();
    if (before == null || _status.phase != SyncPhase.idle) {
      throw SyncSetupException(SyncSetupError.syncFailed, _status.issue);
    }
    await _exclusive(() async {
      final meta = _requireJoined();
      final remote = _remote!;
      final current = (await inspect(remote)).vault;
      if (current == null || current.vaultId != meta.vaultId) {
        throw const SyncSetupException(SyncSetupError.vaultMissing);
      }
      final vaultId = _newId();
      KdfParams? kdf;
      Uint8List? key;
      String? check;
      if (password != null) {
        (kdf, key, check) = await _newKey(password, vaultId);
      }
      final vault = SyncVault(
        vaultId: vaultId,
        createdAt: _nowMs(),
        lineage: [
          current.vaultId,
          ...current.lineage,
        ].take(maxLineage).toList(),
        kdf: kdf,
        check: check,
      );
      await remote.write(vaultFileName, vault.encode());
      for (final entry in await remote.list()) {
        if (deviceIdOfFile(entry.name) != null && entry.name != _ownFile) {
          await remote.delete(entry.name);
        }
      }
      if (key == null) {
        await keyStore.delete();
      } else {
        await keyStore.write(key);
      }
      _key = key;
      _continueAs(meta, vault);
      meta.encrypted = vault.encrypted;
      await localStore.saveMeta(meta);
      _vaultCache = null;
      _verifiedVaultVersion = null;
    });
    return sync();
  }

  /// Deletes another device's file. Its changes that were already merged
  /// stay; if the device is still in use it uploads again on its next round.
  Future<void> removeDevice(String deviceId) => _exclusive(() async {
    final meta = _requireJoined();
    if (deviceId == meta.deviceId) throw ArgumentError('deviceId');
    final name = deviceFileName(deviceId);
    await _remote!.delete(name);
    meta.peers.remove(name);
    await localStore.saveMeta(meta);
    notifyListeners();
  });

  /// Leaves the vault. The library stays as it is. With [deleteOwnFile] this
  /// device's file is removed from the folder first (best effort).
  Future<void> disconnect({bool deleteOwnFile = false}) => _exclusive(() async {
    final meta = _requireLoaded();
    if (deleteOwnFile && meta.joined && _remote != null) {
      try {
        await _remote!.delete(_ownFile);
      } on SyncRemoteException {
        // Leaving must work offline; the file is only a copy.
      }
    }
    await keyStore.delete();
    await localStore.saveState(null);
    await localStore.savePending(null);
    _meta = SyncLocalMeta(deviceId: meta.deviceId);
    await localStore.saveMeta(_meta!);
    _key = null;
    _remote = null;
    _vaultCache = null;
    _verifiedVaultVersion = null;
    _setStatus(_with(SyncPhase.off));
  });

  SyncLocalMeta _requireLoaded() {
    final meta = _meta;
    if (meta == null) throw StateError('SyncEngine.load() first');
    return meta;
  }

  SyncLocalMeta _requireJoined() {
    final meta = _requireLoaded();
    if (!meta.joined || _remote == null) {
      throw const SyncSetupException(SyncSetupError.notJoined);
    }
    return meta;
  }

  /// Runs a round now, or joins the one already running and runs once more
  /// after it so edits made meanwhile are included. Returns null when the
  /// round could not complete; [status] says why.
  Future<SyncReport?> sync() {
    final running = _inFlight;
    if (running != null) {
      _again = true;
      return running;
    }
    final future = _exclusive(() async {
      SyncReport? report;
      do {
        _again = false;
        report = await _guardedRound();
      } while (_again && report != null);
      return report;
    });
    _inFlight = future;
    future.whenComplete(() {
      if (identical(_inFlight, future)) _inFlight = null;
    }).ignore();
    return future;
  }

  Future<SyncReport?> _guardedRound() async {
    final meta = _meta;
    if (meta == null || !meta.joined || _remote == null) return null;
    _setStatus(_with(SyncPhase.syncing));
    try {
      return await _round(meta, _remote!);
    } on SyncRemoteException catch (error) {
      // The status only says what kind; this says which request and why.
      AppLog.warn('sync', 'Round failed (${error.kind.name}) ${error.message}');
      _setStatus(
        _with(
          error.kind == SyncRemoteFailure.auth ||
                  error.kind == SyncRemoteFailure.forbidden
              ? SyncPhase.needsAttention
              : SyncPhase.error,
          issue: _issueOf(error.kind),
          retryAfter: error.retryAfter,
        ),
      );
      return null;
    } on SyncSetupException catch (error) {
      _setStatus(
        _with(
          SyncPhase.needsAttention,
          issue: error.kind == SyncSetupError.newerFormat
              ? SyncIssue.newerFormat
              : SyncIssue.vaultUnreadable,
        ),
      );
      return null;
    } catch (error) {
      // Local files or secure storage failed. The library itself is only
      // written through the host, which has its own rollback.
      debugPrint('Sync round failed: ${error.runtimeType}');
      _setStatus(_with(SyncPhase.error, issue: SyncIssue.localWrite));
      return null;
    }
  }

  static SyncIssue _issueOf(SyncRemoteFailure kind) => switch (kind) {
    SyncRemoteFailure.network => SyncIssue.network,
    SyncRemoteFailure.auth => SyncIssue.auth,
    SyncRemoteFailure.forbidden => SyncIssue.forbidden,
    SyncRemoteFailure.notFound => SyncIssue.protocol,
    SyncRemoteFailure.conflict => SyncIssue.protocol,
    SyncRemoteFailure.quota => SyncIssue.quota,
    SyncRemoteFailure.rateLimited => SyncIssue.rateLimited,
    SyncRemoteFailure.server => SyncIssue.server,
    SyncRemoteFailure.protocol => SyncIssue.protocol,
  };

  Future<SyncVault> _readVault(SyncRemote remote, RemoteEntry entry) async {
    final cached = _vaultCache;
    if (cached != null && cached.$1 == entry.version) return cached.$2;
    final vault = _decodeVault(await remote.read(vaultFileName));
    _vaultCache = (entry.version, vault);
    return vault;
  }

  Future<SyncReport?> _round(SyncLocalMeta meta, SyncRemote remote) async {
    await _recoverPending();
    final blobs = <String, PeerBlob>{};
    for (var attempt = 0; attempt < 3; attempt++) {
      final snapshot = host.capture();
      if (snapshot.library.hasPendingRestore) {
        _setStatus(_with(SyncPhase.idle, issue: SyncIssue.pendingRestore));
        return null;
      }
      final entries = await remote.list();
      final byName = {for (final entry in entries) entry.name: entry};
      final vaultEntry = byName[vaultFileName];
      if (vaultEntry == null) {
        _setStatus(
          _with(SyncPhase.needsAttention, issue: SyncIssue.vaultMissing),
        );
        return null;
      }
      final vault = await _readVault(remote, vaultEntry);
      if (vault.vaultId != meta.vaultId) {
        if (!vault.lineage.contains(meta.vaultId)) {
          _setStatus(
            _with(SyncPhase.needsAttention, issue: SyncIssue.vaultReplaced),
          );
          return null;
        }
        if (vault.encrypted) {
          _setStatus(
            _with(SyncPhase.needsPassword, issue: SyncIssue.passwordChanged),
          );
          return null;
        }
        if (meta.encrypted) {
          _setStatus(
            _with(SyncPhase.needsAttention, issue: SyncIssue.encryptionRemoved),
          );
          return null;
        }
        // Plain to plain: nothing to unlock, carry on under the new id.
        _continueAs(meta, vault);
        await localStore.saveMeta(meta);
        blobs.clear();
      }
      if (vault.encrypted != meta.encrypted) {
        _setStatus(
          _with(SyncPhase.needsAttention, issue: SyncIssue.vaultReplaced),
        );
        return null;
      }
      if (vault.encrypted) {
        _key ??= await keyStore.read();
        final key = _key;
        if (key == null) {
          _setStatus(_with(SyncPhase.needsPassword));
          return null;
        }
        if (_verifiedVaultVersion != vaultEntry.version) {
          final bool ok;
          try {
            ok = await verifyKeyCheck(key, vault.vaultId, vault.check!);
          } on SyncCryptoException {
            _setStatus(
              _with(SyncPhase.needsAttention, issue: SyncIssue.vaultUnreadable),
            );
            return null;
          }
          if (!ok) {
            _key = null;
            _setStatus(
              _with(SyncPhase.needsPassword, issue: SyncIssue.passwordChanged),
            );
            return null;
          }
          _verifiedVaultVersion = vaultEntry.version;
        }
      }

      final own = _ownFile;
      // Right after joining, a file under this device's name is a copy from
      // an earlier membership: the local state that matched it was cleared.
      // Merge it like any other device's, or the first upload would replace
      // what may be the only copy of this library.
      final mergeOwn = meta.joinMode != null;
      for (final entry in entries) {
        if (deviceIdOfFile(entry.name) == null) continue;
        if (entry.name == own && !mergeOwn) continue;
        if (meta.peers[entry.name]?.version == entry.version) continue;
        if (blobs[entry.name]?.version == entry.version) continue;
        try {
          blobs[entry.name] = PeerBlob(
            name: entry.name,
            version: entry.version,
            bytes: await remote.read(entry.name),
          );
        } on SyncRemoteException catch (error) {
          // Removed between list and read: it is simply gone.
          if (error.kind != SyncRemoteFailure.notFound) rethrow;
        }
      }
      blobs.removeWhere((name, _) => !byName.containsKey(name));

      final joinMode = meta.joinMode;
      final input = SyncRoundInput(
        localState: await localStore.loadState(),
        live: snapshot.library,
        absorb: switch (joinMode) {
          SyncJoinMode.replaceLocal => AbsorbMode.none,
          SyncJoinMode.merge => AbsorbMode.baseline,
          _ => AbsorbMode.edits,
        },
        nowMs: _nowMs(),
        peers: blobs.values.toList(),
        key: _key,
        encrypted: meta.encrypted,
        vaultId: meta.vaultId!,
        device: _device,
        uploadedDigest: meta.uploadedDigest,
        forceUpload: !byName.containsKey(own),
      );
      final SyncRoundOutput output;
      try {
        output = await _compute(_runner, input);
      } on SyncFormatException {
        // The local state file is damaged. Rebuild it from the library and
        // the vault; the vault wins wherever it knows a record.
        await localStore.saveState(null);
        meta
          ..joinMode = SyncJoinMode.merge
          ..uploadedDigest = null
          ..peers.clear();
        await localStore.saveMeta(meta);
        blobs.clear();
        continue;
      }

      if (output.derived != null) {
        await localStore.savePending(output.state);
        final outcome = await host.apply(snapshot.revision, output.derived!);
        if (outcome != SyncApplyOutcome.applied) {
          await localStore.savePending(null);
          if (outcome == SyncApplyOutcome.failed) {
            _setStatus(_with(SyncPhase.error, issue: SyncIssue.localWrite));
            return null;
          }
          continue;
        }
      }
      await localStore.saveState(output.state);
      await localStore.savePending(null);
      for (final peer in output.peers) {
        if (peer.name == own) continue;
        meta.peers[peer.name] = SyncPeerRecord(
          // An unreadable file may have been caught mid-upload; an empty
          // version makes the next round download it again.
          version: peer.ok ? peer.version : '',
          device: peer.device ?? meta.peers[peer.name]?.device,
          writtenAt: peer.writtenAt ?? meta.peers[peer.name]?.writtenAt,
          problem: peer.problem?.name,
        );
      }
      meta.peers.removeWhere((name, _) => !byName.containsKey(name));
      meta.joinMode = null;
      await localStore.saveMeta(meta);

      var uploaded = false;
      if (output.upload != null) {
        await remote.write(own, output.upload!);
        meta.uploadedDigest = output.digest;
        uploaded = true;
      }
      meta.lastSuccessAt = _nowMs();
      await localStore.saveMeta(meta);
      _setStatus(_with(SyncPhase.idle));
      return SyncReport(
        downloaded: output.peers.length,
        applied: output.derived != null,
        uploaded: uploaded,
        unreadablePeers: _unreadablePeers,
      );
    }
    _setStatus(_with(SyncPhase.idle, issue: SyncIssue.busy));
    return null;
  }

  /// Stamps local edits into the sync state without going online. The app
  /// calls this shortly after each library commit; a network round would
  /// otherwise date every offline edit to the moment the device reconnects,
  /// and it would win over newer edits made elsewhere in the meantime.
  Future<void> absorbLocalEdits() => _exclusive(() async {
    final meta = _meta;
    if (meta == null || !meta.joined || meta.joinMode != null) return;
    final snapshot = host.capture();
    if (snapshot.library.hasPendingRestore) return;
    try {
      await _recoverPending();
      final next = await _absorb(
        _runner,
        await localStore.loadState(),
        snapshot.library,
        _nowMs(),
      );
      if (next != null) await localStore.saveState(next);
    } catch (error) {
      // The next network round absorbs the same edits.
      debugPrint('Sync absorb failed: ${error.runtimeType}');
    }
  });

  static Future<String?> _absorb(
    SyncRunner runner,
    String? state,
    SyncLibrary live,
    int nowMs,
  ) => runner(() => computeAbsorb(state, live, nowMs));

  /// Kept static so the isolate closure captures nothing but [input].
  static Future<SyncRoundOutput> _compute(
    SyncRunner runner,
    SyncRoundInput input,
  ) => runner(() => computeSyncRound(input));

  static Future<bool> _pendingMatches(
    SyncRunner runner,
    String pending,
    SyncLibrary live,
  ) => runner(
    () => libraryMatches(
      deriveLibrary(SyncState.fromJson(jsonDecode(pending))),
      live,
    ),
  );

  /// A previous round wrote its state as pending, then stopped before
  /// confirming. If the library holds exactly that result, the commit
  /// happened and the state is adopted; otherwise it is dropped.
  Future<void> _recoverPending() async {
    final pending = await localStore.loadPending();
    if (pending == null) return;
    var matches = false;
    try {
      matches = await _pendingMatches(_runner, pending, host.capture().library);
    } catch (_) {
      matches = false;
    }
    if (matches) {
      await localStore.saveState(pending);
      final meta = _meta!;
      if (meta.joinMode != null) {
        meta.joinMode = null;
        await localStore.saveMeta(meta);
      }
    }
    await localStore.savePending(null);
  }
}

/// True when [library] is what a fresh install starts with: one board and
/// nothing on it.
bool isPristine(SyncLibrary library) =>
    library.boards.length <= 1 &&
    library.tasks.isEmpty &&
    library.scheduleItems.isEmpty;
