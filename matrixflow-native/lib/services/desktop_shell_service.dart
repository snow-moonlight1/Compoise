import 'dart:async';

import 'package:flutter/foundation.dart';

import 'desktop_shell_host.dart';
import 'desktop_shell_windows.dart';

@immutable
class DesktopShellSettingsResult {
  final int generation;
  final DesktopShellResult tray;
  final DesktopShellResult hotkey;
  final bool requestedCloseToTray;
  final bool closeToTrayEffective;
  final String requestedShortcut;
  final String? registeredShortcut;
  final bool superseded;

  const DesktopShellSettingsResult({
    required this.generation,
    required this.tray,
    required this.hotkey,
    required this.requestedCloseToTray,
    required this.closeToTrayEffective,
    required this.requestedShortcut,
    required this.registeredShortcut,
    this.superseded = false,
  });

  bool get hasFailure => tray.isFailure || hotkey.isFailure;
}

enum DesktopExitResult { completed, cancelled, failed }

typedef DesktopExitGuard = FutureOr<bool> Function();

/// Coordinates Windows desktop shell state with the settings currently loaded
/// by the app. Only the latest settings generation is published, so delayed
/// host results cannot make stale settings look active.
class DesktopShellService extends ChangeNotifier {
  static final DesktopShellService instance = DesktopShellService._internal();

  DesktopShellService._internal()
    : _hostFactory = _defaultHostFactory,
      _desktopSupportOverride = null;

  DesktopShellService.forTest(DesktopShellHost host)
    : _hostFactory = (() => host),
      _desktopSupportOverride = true,
      _host = host;

  /// Allows older tests to simulate desktop support without touching real OS
  /// integration. OS14 tests inject a fake host instead.
  @visibleForTesting
  static bool? debugIsDesktopOverride;

  final DesktopShellHost Function() _hostFactory;
  final bool? _desktopSupportOverride;
  DesktopShellHost? _host;

  bool get isDesktopSupported {
    if (_desktopSupportOverride != null) return _desktopSupportOverride;
    if (debugIsDesktopOverride != null) return debugIsDesktopOverride!;
    return !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
  }

  DesktopShellResult _trayResult = const DesktopShellResult.disabled();
  DesktopShellResult get trayResult => _trayResult;
  bool get isTrayInitialized => _trayResult.succeeded;

  DesktopShellResult _hotkeyResult = const DesktopShellResult.disabled();
  DesktopShellResult get hotkeyResult => _hotkeyResult;

  bool _isWindowVisible = true;
  bool get isWindowVisible => _isWindowVisible;

  String? _registeredGlobalShortcut;
  String? get registeredGlobalShortcut => _registeredGlobalShortcut;

  bool get hasHotkeyConflict =>
      _hotkeyResult.kind == DesktopShellResultKind.conflict;

  bool _desiredCloseToTray = false;
  bool get closeToTrayPolicy => _desiredCloseToTray;

  bool _effectiveCloseToTray = false;
  bool get effectiveCloseToTray => _effectiveCloseToTray;

  String _desiredGlobalShortcut = '';
  String get desiredGlobalShortcut => _desiredGlobalShortcut;

  bool _isApplyingSettings = false;
  bool get isApplyingSettings => _isApplyingSettings;

  DesktopShellSettingsResult? _lastSettingsResult;
  DesktopShellSettingsResult? get lastSettingsResult => _lastSettingsResult;

  int _latestGeneration = 0;
  Future<void>? _applyTail;
  Future<DesktopExitResult>? _exitInFlight;
  bool _hasExited = false;

  bool get isExitInProgress => _exitInFlight != null;

  VoidCallback? onShowWindow;
  VoidCallback? onQuickAddTask;
  VoidCallback? onSearch;
  DesktopExitGuard? onExit;
  VoidCallback? _hotkeyTrigger;

  void configureCallbacks({
    VoidCallback? onShowWindow,
    VoidCallback? onQuickAddTask,
    VoidCallback? onSearch,
    DesktopExitGuard? onExit,
  }) {
    this.onShowWindow = onShowWindow ?? this.onShowWindow;
    this.onQuickAddTask = onQuickAddTask ?? this.onQuickAddTask;
    this.onSearch = onSearch ?? this.onSearch;
    this.onExit = onExit ?? this.onExit;
  }

  /// Compatibility entry point. Startup, settings edits, and imported settings
  /// should all converge on [applySettings].
  Future<DesktopShellSettingsResult> init({
    VoidCallback? onShowWindow,
    VoidCallback? onQuickAddTask,
    VoidCallback? onSearch,
    DesktopExitGuard? onExit,
    bool closeToTray = false,
    String? globalShortcut,
  }) {
    configureCallbacks(
      onShowWindow: onShowWindow,
      onQuickAddTask: onQuickAddTask,
      onSearch: onSearch,
      onExit: onExit,
    );
    return applySettings(
      closeToTray: closeToTray,
      globalShortcut: globalShortcut ?? _desiredGlobalShortcut,
    );
  }

  Future<DesktopShellSettingsResult> applySettings({
    required bool closeToTray,
    required String globalShortcut,
  }) {
    final generation = ++_latestGeneration;
    final normalizedShortcut = globalShortcut.trim();
    _desiredCloseToTray = closeToTray;
    _desiredGlobalShortcut = normalizedShortcut;
    _isApplyingSettings = true;
    notifyListeners();

    final previous = _applyTail;
    final run =
        previous == null
            ? _applySettingsNow(
              generation: generation,
              closeToTray: closeToTray,
              globalShortcut: normalizedShortcut,
            )
            : previous.then(
              (_) => _applySettingsNow(
                generation: generation,
                closeToTray: closeToTray,
                globalShortcut: normalizedShortcut,
              ),
            );
    final tail = run.then<void>((_) {}, onError: (_, _) {});
    _applyTail = tail;
    unawaited(
      tail.whenComplete(() {
        if (identical(_applyTail, tail)) _applyTail = null;
      }),
    );
    return run;
  }

  Future<DesktopShellSettingsResult> retrySettings() => applySettings(
    closeToTray: _desiredCloseToTray,
    globalShortcut: _desiredGlobalShortcut,
  );

  Future<DesktopShellSettingsResult> _applySettingsNow({
    required int generation,
    required bool closeToTray,
    required String globalShortcut,
  }) async {
    if (generation != _latestGeneration) {
      return _supersededResult(generation, closeToTray, globalShortcut);
    }

    if (!isDesktopSupported) {
      final result = DesktopShellSettingsResult(
        generation: generation,
        tray: const DesktopShellResult.unsupported(),
        hotkey: const DesktopShellResult.unsupported(),
        requestedCloseToTray: closeToTray,
        closeToTrayEffective: false,
        requestedShortcut: globalShortcut,
        registeredShortcut: null,
      );
      _publish(result);
      return result;
    }

    final host = _host ??= _hostFactory();
    var tray = _trayResult;
    if (!tray.succeeded) {
      try {
        tray = await host.start(
          DesktopShellHostCallbacks(
            onWindowCloseRequested: handleWindowCloseRequest,
            onRestoreRequested: restoreWindow,
            onQuickAddRequested: () {
              restoreWindow();
              onQuickAddTask?.call();
            },
            onSearchRequested: () {
              restoreWindow();
              onSearch?.call();
            },
            onExitRequested: exitApplication,
          ),
        );
      } catch (error) {
        tray = DesktopShellResult(
          DesktopShellResultKind.unavailable,
          detail: error.toString(),
        );
      }
    }
    if (generation != _latestGeneration) {
      return _supersededResult(generation, closeToTray, globalShortcut);
    }

    DesktopShellResult hotkey;
    if (globalShortcut.isEmpty) {
      try {
        final removed = await host.unregisterHotkey();
        hotkey =
            removed.succeeded ? const DesktopShellResult.disabled() : removed;
      } catch (error) {
        hotkey = DesktopShellResult(
          DesktopShellResultKind.unavailable,
          detail: error.toString(),
        );
      }
    } else if (_registeredGlobalShortcut == globalShortcut &&
        _hotkeyResult.succeeded) {
      hotkey = _hotkeyResult;
    } else {
      _hotkeyTrigger = restoreWindow;
      try {
        hotkey = await host.registerHotkey(globalShortcut, _hotkeyTrigger!);
      } catch (error) {
        hotkey = DesktopShellResult(
          DesktopShellResultKind.unavailable,
          detail: error.toString(),
        );
      }
    }
    if (generation != _latestGeneration) {
      return _supersededResult(generation, closeToTray, globalShortcut);
    }

    _trayResult = tray;
    _hotkeyResult = hotkey;
    _registeredGlobalShortcut = host.registeredShortcut;
    if (_registeredGlobalShortcut == null) _hotkeyTrigger = null;
    _effectiveCloseToTray = closeToTray && tray.succeeded;

    final result = DesktopShellSettingsResult(
      generation: generation,
      tray: tray,
      hotkey: hotkey,
      requestedCloseToTray: closeToTray,
      closeToTrayEffective: _effectiveCloseToTray,
      requestedShortcut: globalShortcut,
      registeredShortcut: _registeredGlobalShortcut,
    );
    _publish(result);
    return result;
  }

  DesktopShellSettingsResult _supersededResult(
    int generation,
    bool closeToTray,
    String globalShortcut,
  ) => DesktopShellSettingsResult(
    generation: generation,
    tray: const DesktopShellResult.superseded(),
    hotkey: const DesktopShellResult.superseded(),
    requestedCloseToTray: closeToTray,
    closeToTrayEffective: false,
    requestedShortcut: globalShortcut,
    registeredShortcut: null,
    superseded: true,
  );

  void _publish(DesktopShellSettingsResult result) {
    if (result.generation != _latestGeneration || result.superseded) return;
    _lastSettingsResult = result;
    _isApplyingSettings = false;
    notifyListeners();
  }

  /// The host asks this service for the current close behavior. Hiding is only
  /// allowed after a successful tray initialization and never interrupts a
  /// true exit already in progress.
  bool handleWindowCloseRequest({bool? closeToTray}) {
    if (!isDesktopSupported) return true;
    if (_exitInFlight != null || _hasExited) {
      unawaited(exitApplication());
      return true;
    }
    final wantsTray = closeToTray ?? _desiredCloseToTray;
    if (wantsTray && isTrayInitialized) {
      unawaited(hideWindowToTray());
      return false;
    }
    unawaited(exitApplication());
    return true;
  }

  Future<DesktopShellResult> hideWindowToTray() async {
    if (!isDesktopSupported) return const DesktopShellResult.unsupported();
    if (!isTrayInitialized || _host == null) {
      return const DesktopShellResult(DesktopShellResultKind.unavailable);
    }
    final result = await _host!.hide();
    if (result.succeeded) {
      _isWindowVisible = false;
      notifyListeners();
    }
    return result;
  }

  void restoreWindow() {
    _isWindowVisible = true;
    onShowWindow?.call();
    final host = _host;
    if (host != null) unawaited(host.show());
    notifyListeners();
  }

  /// Direct API retained for focused callers/tests. It now waits for the host
  /// and returns the host's typed result instead of reporting success early.
  Future<DesktopShellResult> registerGlobalHotkey(
    String shortcut,
    VoidCallback onTrigger,
  ) async {
    if (!isDesktopSupported) return const DesktopShellResult.unsupported();
    final host = _host ??= _hostFactory();
    _hotkeyTrigger = onTrigger;
    DesktopShellResult result;
    try {
      result = await host.registerHotkey(shortcut.trim(), onTrigger);
    } catch (error) {
      result = DesktopShellResult(
        DesktopShellResultKind.unavailable,
        detail: error.toString(),
      );
    }
    _hotkeyResult = result;
    _registeredGlobalShortcut = host.registeredShortcut;
    if (_registeredGlobalShortcut == null) _hotkeyTrigger = null;
    notifyListeners();
    return result;
  }

  Future<DesktopShellResult> unregisterGlobalHotkey() async {
    final host = _host;
    if (host == null) return const DesktopShellResult.disabled();
    DesktopShellResult result;
    try {
      result = await host.unregisterHotkey();
    } catch (error) {
      result = DesktopShellResult(
        DesktopShellResultKind.unavailable,
        detail: error.toString(),
      );
    }
    _hotkeyResult =
        result.succeeded ? const DesktopShellResult.disabled() : result;
    _registeredGlobalShortcut = host.registeredShortcut;
    if (_registeredGlobalShortcut == null) _hotkeyTrigger = null;
    notifyListeners();
    return _hotkeyResult;
  }

  /// Runs the true-exit path once. Concurrent window-close and tray-exit
  /// requests join the same future; a cancelled or failed attempt may retry.
  Future<DesktopExitResult> exitApplication() {
    if (_hasExited) {
      return Future.value(DesktopExitResult.completed);
    }
    final pending = _exitInFlight;
    if (pending != null) return pending;

    final completer = Completer<DesktopExitResult>();
    _exitInFlight = completer.future;
    notifyListeners();
    unawaited(() async {
      final result = await _performExit();
      _exitInFlight = null;
      notifyListeners();
      completer.complete(result);
    }());
    return completer.future;
  }

  Future<DesktopExitResult> _performExit() async {
    try {
      final guard = onExit;
      if (guard != null) {
        final decision = guard();
        final approved = decision is Future<bool> ? await decision : decision;
        if (!approved) return DesktopExitResult.cancelled;
      }

      _trayResult = const DesktopShellResult.disabled();
      _hotkeyResult = const DesktopShellResult.disabled();
      _effectiveCloseToTray = false;
      _registeredGlobalShortcut = null;
      _hotkeyTrigger = null;
      final host = _host;
      _host = null;
      notifyListeners();
      if (host != null) {
        try {
          await host.destroy();
        } catch (_) {
          _host = host;
          return DesktopExitResult.failed;
        }
      }
      _hasExited = true;
      return DesktopExitResult.completed;
    } catch (_) {
      return DesktopExitResult.cancelled;
    }
  }

  @visibleForTesting
  void debugInvokeRegisteredHotkey() {
    _hotkeyTrigger?.call();
  }

  @visibleForTesting
  void resetForTest() {
    _latestGeneration++;
    final host = _host;
    _host = null;
    if (host != null) unawaited(host.destroy());
    _applyTail = null;
    _exitInFlight = null;
    _hasExited = false;
    _trayResult = const DesktopShellResult.disabled();
    _hotkeyResult = const DesktopShellResult.disabled();
    _isWindowVisible = true;
    _registeredGlobalShortcut = null;
    _desiredCloseToTray = false;
    _effectiveCloseToTray = false;
    _desiredGlobalShortcut = '';
    _isApplyingSettings = false;
    _lastSettingsResult = null;
    _hotkeyTrigger = null;
    onShowWindow = null;
    onQuickAddTask = null;
    onSearch = null;
    onExit = null;
    debugIsDesktopOverride = null;
  }

  static DesktopShellHost _defaultHostFactory() {
    if (debugIsDesktopOverride != null) return _NoopDesktopShellHost();
    return isWindowsWindowManagerPrepared && shouldUseRealWindowsShell()
        ? WindowsDesktopShellHost()
        : _NoopDesktopShellHost();
  }
}

class _NoopDesktopShellHost implements DesktopShellHost {
  String? _registeredShortcut;

  @override
  String? get registeredShortcut => _registeredShortcut;

  @override
  Future<DesktopShellResult> start(DesktopShellHostCallbacks callbacks) async =>
      const DesktopShellResult.success();

  @override
  Future<DesktopShellResult> registerHotkey(
    String shortcut,
    VoidCallback onTrigger,
  ) async {
    if (shortcut.toLowerCase() == 'ctrl+alt+del') {
      _registeredShortcut = null;
      return const DesktopShellResult(DesktopShellResultKind.conflict);
    }
    _registeredShortcut = shortcut;
    return const DesktopShellResult.success();
  }

  @override
  Future<DesktopShellResult> unregisterHotkey() async {
    _registeredShortcut = null;
    return const DesktopShellResult.success();
  }

  @override
  Future<DesktopShellResult> hide() async => const DesktopShellResult.success();

  @override
  Future<DesktopShellResult> show() async => const DesktopShellResult.success();

  @override
  Future<void> destroy() async {}
}
