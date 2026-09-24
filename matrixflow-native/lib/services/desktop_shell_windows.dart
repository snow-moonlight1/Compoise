import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'desktop_shell_host.dart';

@visibleForTesting
bool? debugUseRealWindowsShellOverride;

bool _windowsWindowManagerPrepared = false;

bool get isWindowsWindowManagerPrepared => _windowsWindowManagerPrepared;

/// True when the current isolate should talk to real Windows shell APIs.
bool shouldUseRealWindowsShell() {
  if (debugUseRealWindowsShellOverride != null) {
    return debugUseRealWindowsShellOverride!;
  }
  if (kIsWeb) return false;
  if (defaultTargetPlatform != TargetPlatform.windows) return false;
  try {
    if (Platform.environment.containsKey('FLUTTER_TEST')) return false;
  } catch (_) {}
  return true;
}

Future<void> ensureWindowsWindowManager() async {
  if (!shouldUseRealWindowsShell()) return;
  await windowManager.ensureInitialized();
  await windowManager.setPreventClose(true);
  _windowsWindowManagerPrepared = true;
}

class WindowsDesktopShellHost
    with WindowListener, TrayListener
    implements DesktopShellHost {
  static const _hotkeyChannel = MethodChannel('matrixflow/os14_hotkey');

  DesktopShellHostCallbacks? _callbacks;
  VoidCallback? _hotkeyTrigger;
  String? _registeredShortcut;
  @override
  String? get registeredShortcut => _registeredShortcut;
  bool _bound = false;
  Future<void>? _destroyFuture;

  @override
  Future<DesktopShellResult> start(DesktopShellHostCallbacks callbacks) async {
    _callbacks = callbacks;
    if (!shouldUseRealWindowsShell()) {
      return const DesktopShellResult.unsupported();
    }

    if (!_bound) {
      windowManager.addListener(this);
      trayManager.addListener(this);
      _bound = true;
    }

    try {
      await windowManager.setPreventClose(true);
      await trayManager.setIcon('assets/tray_icon.ico');
      await trayManager.setToolTip('MatrixFlow AI');
      await trayManager.setContextMenu(
        Menu(
          items: [
            MenuItem(key: 'show', label: 'Show MatrixFlow'),
            MenuItem(key: 'quick-add', label: 'Quick Add'),
            MenuItem(key: 'search', label: 'Search'),
            MenuItem.separator(),
            MenuItem(key: 'exit', label: 'Exit'),
          ],
        ),
      );
      return const DesktopShellResult.success();
    } catch (e) {
      debugPrint('Failed to initialize Windows tray: $e');
      return DesktopShellResult(
        DesktopShellResultKind.unavailable,
        detail: e.toString(),
      );
    }
  }

  @override
  Future<DesktopShellResult> hide() async {
    if (!shouldUseRealWindowsShell()) {
      return const DesktopShellResult.unsupported();
    }
    try {
      final hidden = await _hotkeyChannel.invokeMethod<bool>('hide');
      if (hidden == true) return const DesktopShellResult.success();
      return const DesktopShellResult(DesktopShellResultKind.unavailable);
    } catch (e) {
      await show();
      return DesktopShellResult(
        DesktopShellResultKind.unavailable,
        detail: e.toString(),
      );
    }
  }

  @override
  Future<DesktopShellResult> show() async {
    if (!shouldUseRealWindowsShell()) {
      return const DesktopShellResult.unsupported();
    }
    try {
      final visible = await _hotkeyChannel.invokeMethod<bool>('show');
      if (visible == true) return const DesktopShellResult.success();
      return const DesktopShellResult(DesktopShellResultKind.unavailable);
    } catch (e) {
      return DesktopShellResult(
        DesktopShellResultKind.unavailable,
        detail: e.toString(),
      );
    }
  }

  Future<bool> isWindowActuallyVisible() async =>
      await _hotkeyChannel.invokeMethod<bool>('isVisible') ?? false;

  @override
  Future<DesktopShellResult> registerHotkey(
    String shortcut,
    VoidCallback onTrigger,
  ) async {
    if (!shouldUseRealWindowsShell()) {
      return const DesktopShellResult.unsupported();
    }
    final hotkey = parseWindowsHotkey(shortcut);
    if (hotkey == null) {
      return const DesktopShellResult(DesktopShellResultKind.invalid);
    }
    final removed = await unregisterHotkey();
    if (!removed.succeeded) return removed;
    try {
      final registered = await _hotkeyChannel.invokeMethod<bool>('register', {
        'keyCode': hotkey.keyCode,
        'modifiers': hotkey.modifiers,
      });
      if (registered != true) {
        return const DesktopShellResult(DesktopShellResultKind.conflict);
      }
      _hotkeyTrigger = onTrigger;
      _registeredShortcut = shortcut;
      _hotkeyChannel.setMethodCallHandler((call) async {
        if (call.method == 'onHotkey') _hotkeyTrigger?.call();
      });
      return const DesktopShellResult.success();
    } catch (e) {
      debugPrint('Failed to register global hotkey: $e');
      return DesktopShellResult(
        DesktopShellResultKind.unavailable,
        detail: e.toString(),
      );
    }
  }

  @override
  Future<DesktopShellResult> unregisterHotkey() async {
    if (!shouldUseRealWindowsShell()) {
      return const DesktopShellResult.unsupported();
    }
    try {
      final removed = await _hotkeyChannel.invokeMethod<bool>('unregister');
      if (removed != true) {
        return const DesktopShellResult(DesktopShellResultKind.unavailable);
      }
      _hotkeyTrigger = null;
      _registeredShortcut = null;
      return const DesktopShellResult.success();
    } catch (error) {
      return DesktopShellResult(
        DesktopShellResultKind.unavailable,
        detail: error.toString(),
      );
    }
  }

  @override
  Future<void> destroy() => _destroyFuture ??= _destroyOnce();

  Future<void> _destroyOnce() async {
    await unregisterHotkey();
    _callbacks = null;
    if (!shouldUseRealWindowsShell()) return;
    try {
      await trayManager.destroy();
    } catch (_) {}
    if (_bound) {
      windowManager.removeListener(this);
      trayManager.removeListener(this);
      _bound = false;
    }
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }

  @override
  void onWindowClose() {
    _callbacks?.onWindowCloseRequested();
  }

  @override
  void onTrayIconMouseDown() {
    _callbacks?.onRestoreRequested();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        _callbacks?.onRestoreRequested();
      case 'quick-add':
        _callbacks?.onQuickAddRequested?.call();
      case 'search':
        _callbacks?.onSearchRequested?.call();
      case 'exit':
        _callbacks?.onExitRequested?.call();
    }
  }
}

/// Virtual-key code and MOD_* flags consumed by the Windows runner channel.
@immutable
class WindowsHotkeySpec {
  final int keyCode;
  final int modifiers;

  const WindowsHotkeySpec(this.keyCode, this.modifiers);
}

WindowsHotkeySpec? parseWindowsHotkey(String shortcut) {
  final parts =
      shortcut
          .split('+')
          .map((part) => part.trim().toLowerCase())
          .where((part) => part.isNotEmpty)
          .toList();
  if (parts.isEmpty) return null;

  final key = parts.last;
  int? keyCode;
  if (key.length == 1) {
    final code = key.toUpperCase().codeUnitAt(0);
    if ((code >= 0x41 && code <= 0x5A) || (code >= 0x30 && code <= 0x39)) {
      keyCode = code;
    }
  }
  keyCode ??= switch (key) {
    'space' => 0x20,
    'enter' => 0x0D,
    'tab' => 0x09,
    'esc' || 'escape' => 0x1B,
    _ => null,
  };
  if (keyCode == null) return null;

  var modifiers = 0;
  for (final part in parts.take(parts.length - 1)) {
    final flag = switch (part) {
      'alt' => 0x0001,
      'ctrl' || 'control' => 0x0002,
      'shift' => 0x0004,
      'win' || 'meta' || 'cmd' => 0x0008,
      _ => 0,
    };
    if (flag == 0 || modifiers & flag != 0) return null;
    modifiers |= flag;
  }
  // Avoid intercepting an ordinary key with no modifiers.
  if (modifiers == 0) return null;
  return WindowsHotkeySpec(keyCode, modifiers);
}
