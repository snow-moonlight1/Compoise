import 'package:flutter/foundation.dart';

import 'desktop_shell_windows.dart';

/// Service managing Windows desktop shell integration, tray actions,
/// window close-to-tray policy, and global shortcut coordination.
class DesktopShellService {
  static final DesktopShellService instance = DesktopShellService._internal();

  DesktopShellService._internal();

  /// Allows unit tests to simulate running on desktop platforms.
  @visibleForTesting
  static bool? debugIsDesktopOverride;

  /// Whether current environment supports desktop shell capabilities.
  bool get isDesktopSupported {
    if (debugIsDesktopOverride != null) return debugIsDesktopOverride!;
    return !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
  }

  bool _isTrayInitialized = false;
  bool get isTrayInitialized => _isTrayInitialized;

  bool _isWindowVisible = true;
  bool get isWindowVisible => _isWindowVisible;

  String? _registeredGlobalShortcut;
  String? get registeredGlobalShortcut => _registeredGlobalShortcut;

  bool _hasHotkeyConflict = false;
  bool get hasHotkeyConflict => _hasHotkeyConflict;

  VoidCallback? onShowWindow;
  VoidCallback? onQuickAddTask;
  VoidCallback? onSearch;
  VoidCallback? onExit;
  VoidCallback? _hotkeyTrigger;
  WindowsDesktopShellHost? _host;
  bool _closeToTray = false;

  bool get closeToTrayPolicy => _closeToTray;

  /// Initializes desktop shell features if supported on current platform.
  Future<void> init({
    VoidCallback? onShowWindow,
    VoidCallback? onQuickAddTask,
    VoidCallback? onSearch,
    VoidCallback? onExit,
    bool closeToTray = false,
    String? globalShortcut,
  }) async {
    this.onShowWindow = onShowWindow ?? this.onShowWindow;
    this.onQuickAddTask = onQuickAddTask ?? this.onQuickAddTask;
    this.onSearch = onSearch ?? this.onSearch;
    this.onExit = onExit ?? this.onExit;
    _closeToTray = closeToTray;

    if (!isDesktopSupported) {
      return;
    }

    _isTrayInitialized = true;
    _isWindowVisible = true;

    if (shouldUseRealWindowsShell()) {
      _host ??= WindowsDesktopShellHost();
      await _host!.start(
        onRestore: restoreWindow,
        onQuickAdd: () {
          restoreWindow();
          this.onQuickAddTask?.call();
        },
        onSearch: () {
          restoreWindow();
          this.onSearch?.call();
        },
        onExitRequested: exitApplication,
        closeToTray: closeToTray,
      );
    }

    if (globalShortcut != null && globalShortcut.trim().isNotEmpty) {
      registerGlobalHotkey(globalShortcut, () {
        restoreWindow();
        this.onShowWindow?.call();
      });
    }
  }

  void applyCloseToTray(bool enabled) {
    _closeToTray = enabled;
    _host?.closeToTray = enabled;
  }

  /// Handles a window close event based on user preference.
  /// Returns `true` if application should proceed to exit;
  /// returns `false` if window was minimized/hidden to system tray.
  bool handleWindowCloseRequest({required bool closeToTray}) {
    if (!isDesktopSupported) {
      return true;
    }

    if (closeToTray) {
      hideWindowToTray();
      return false;
    }
    exitApplication();
    return true;
  }

  /// Hides the main window to the system tray.
  void hideWindowToTray() {
    _isWindowVisible = false;
    _host?.hide();
  }

  /// Restores the main window from the system tray and brings it to focus.
  void restoreWindow() {
    _isWindowVisible = true;
    onShowWindow?.call();
    _host?.show();
  }

  /// Registers a global hotkey with conflict handling.
  /// If [shortcut] conflicts or cannot be registered, marks [hasHotkeyConflict]
  /// without throwing exceptions or preventing application startup.
  bool registerGlobalHotkey(String shortcut, VoidCallback onTrigger) {
    if (!isDesktopSupported) return false;

    if (shortcut.trim().isEmpty) {
      _hasHotkeyConflict = false;
      _registeredGlobalShortcut = null;
      _hotkeyTrigger = null;
      return false;
    }

    if (shortcut.toLowerCase() == 'ctrl+alt+del') {
      _hasHotkeyConflict = true;
      _registeredGlobalShortcut = null;
      _hotkeyTrigger = null;
      return false;
    }

    _hotkeyTrigger = onTrigger;
    _hasHotkeyConflict = false;
    _registeredGlobalShortcut = shortcut;
    if (_host != null) {
      _host!.registerHotkey(shortcut, onTrigger).then((ok) {
        if (!ok) {
          _hasHotkeyConflict = true;
          _registeredGlobalShortcut = null;
        }
      });
    }
    return true;
  }

  /// Unregisters the current global hotkey.
  void unregisterGlobalHotkey() {
    _registeredGlobalShortcut = null;
    _hasHotkeyConflict = false;
    _hotkeyTrigger = null;
    _host?.unregisterHotkey();
  }

  /// Safely exits the application.
  void exitApplication() {
    unregisterGlobalHotkey();
    _isTrayInitialized = false;
    onExit?.call();
    _host?.destroy();
    _host = null;
  }

  /// Test helper: invoke the callback stored for the current global hotkey.
  @visibleForTesting
  void debugInvokeRegisteredHotkey() {
    _hotkeyTrigger?.call();
  }

  /// Cleans up service state (useful for tests).
  @visibleForTesting
  void resetForTest() {
    _isTrayInitialized = false;
    _isWindowVisible = true;
    _registeredGlobalShortcut = null;
    _hasHotkeyConflict = false;
    _hotkeyTrigger = null;
    _closeToTray = false;
    onShowWindow = null;
    onQuickAddTask = null;
    onSearch = null;
    onExit = null;
    _host = null;
    debugIsDesktopOverride = null;
  }
}
