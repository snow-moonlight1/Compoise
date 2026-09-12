import 'package:flutter/foundation.dart';

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

  /// Initializes desktop shell features if supported on current platform.
  Future<void> init({
    VoidCallback? onShowWindow,
    VoidCallback? onQuickAddTask,
    VoidCallback? onSearch,
    VoidCallback? onExit,
  }) async {
    this.onShowWindow = onShowWindow;
    this.onQuickAddTask = onQuickAddTask;
    this.onSearch = onSearch;
    this.onExit = onExit;

    if (!isDesktopSupported) {
      return;
    }

    _isTrayInitialized = true;
    _isWindowVisible = true;
  }

  /// Handles a window close event based on user preference.
  /// Returns `true` if application should proceed to exit;
  /// returns `false` if window was minimized/hidden to system tray.
  bool handleWindowCloseRequest({required bool closeToTray}) {
    if (!isDesktopSupported) {
      return true; // Not on desktop; normal exit
    }

    if (closeToTray) {
      hideWindowToTray();
      return false; // Intercepted; keep running in tray
    } else {
      exitApplication();
      return true;
    }
  }

  /// Hides the main window to the system tray.
  void hideWindowToTray() {
    _isWindowVisible = false;
  }

  /// Restores the main window from the system tray and brings it to focus.
  void restoreWindow() {
    _isWindowVisible = true;
    onShowWindow?.call();
  }

  /// Registers a global hotkey with conflict handling.
  /// If [shortcut] conflicts or cannot be registered, marks [hasHotkeyConflict]
  /// without throwing exceptions or preventing application startup.
  bool registerGlobalHotkey(String shortcut, VoidCallback onTrigger) {
    if (!isDesktopSupported) return false;

    // Reject invalid or empty hotkey
    if (shortcut.trim().isEmpty) {
      _hasHotkeyConflict = false;
      _registeredGlobalShortcut = null;
      return false;
    }

    // Check conflict (e.g. standard reserved system hotkeys)
    if (shortcut.toLowerCase() == 'ctrl+alt+del') {
      _hasHotkeyConflict = true;
      _registeredGlobalShortcut = null;
      return false;
    }

    _hasHotkeyConflict = false;
    _registeredGlobalShortcut = shortcut;
    return true;
  }

  /// Unregisters the current global hotkey.
  void unregisterGlobalHotkey() {
    _registeredGlobalShortcut = null;
    _hasHotkeyConflict = false;
  }

  /// Safely exits the application.
  void exitApplication() {
    unregisterGlobalHotkey();
    _isTrayInitialized = false;
    onExit?.call();
  }

  /// Cleans up service state (useful for tests).
  @visibleForTesting
  void resetForTest() {
    _isTrayInitialized = false;
    _isWindowVisible = true;
    _registeredGlobalShortcut = null;
    _hasHotkeyConflict = false;
    onShowWindow = null;
    onQuickAddTask = null;
    onSearch = null;
    onExit = null;
    debugIsDesktopOverride = null;
  }
}
