import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'desktop_shell_service.dart';

/// True when the current isolate should talk to real Windows shell APIs.
bool shouldUseRealWindowsShell() {
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
}

class WindowsDesktopShellHost with WindowListener, TrayListener {
  VoidCallback? onRestore;
  VoidCallback? onQuickAdd;
  VoidCallback? onSearch;
  VoidCallback? onExitRequested;
  bool closeToTray = false;
  HotKey? _hotKey;
  bool _bound = false;

  Future<void> start({
    required VoidCallback onRestore,
    VoidCallback? onQuickAdd,
    VoidCallback? onSearch,
    VoidCallback? onExitRequested,
    required bool closeToTray,
  }) async {
    this.onRestore = onRestore;
    this.onQuickAdd = onQuickAdd;
    this.onSearch = onSearch;
    this.onExitRequested = onExitRequested;
    this.closeToTray = closeToTray;
    if (!shouldUseRealWindowsShell()) return;

    if (!_bound) {
      windowManager.addListener(this);
      trayManager.addListener(this);
      _bound = true;
    }

    await windowManager.setPreventClose(true);
    try {
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
    } catch (e) {
      debugPrint('Failed to initialize Windows tray: $e');
    }
  }

  Future<void> hide() async {
    if (!shouldUseRealWindowsShell()) return;
    await windowManager.hide();
    await windowManager.setSkipTaskbar(true);
  }

  Future<void> show() async {
    if (!shouldUseRealWindowsShell()) return;
    await windowManager.setSkipTaskbar(false);
    await windowManager.show();
    await windowManager.focus();
  }

  Future<bool> registerHotkey(String shortcut, VoidCallback onTrigger) async {
    if (!shouldUseRealWindowsShell()) return true;
    await unregisterHotkey();
    final hotKey = parseWindowsHotkey(shortcut);
    if (hotKey == null) return false;
    try {
      await hotKeyManager.register(
        hotKey,
        keyDownHandler: (_) => onTrigger(),
      );
      _hotKey = hotKey;
      return true;
    } catch (e) {
      debugPrint('Failed to register global hotkey: $e');
      return false;
    }
  }

  Future<void> unregisterHotkey() async {
    final current = _hotKey;
    _hotKey = null;
    if (current == null || !shouldUseRealWindowsShell()) return;
    try {
      await hotKeyManager.unregister(current);
    } catch (_) {}
  }

  Future<void> destroy() async {
    await unregisterHotkey();
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
    DesktopShellService.instance.handleWindowCloseRequest(
      closeToTray: closeToTray,
    );
  }

  @override
  void onTrayIconMouseDown() {
    onRestore?.call();
    show();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        onRestore?.call();
        show();
      case 'quick-add':
        onRestore?.call();
        show();
        onQuickAdd?.call();
      case 'search':
        onRestore?.call();
        show();
        onSearch?.call();
      case 'exit':
        onExitRequested?.call();
        destroy();
    }
  }
}

HotKey? parseWindowsHotkey(String shortcut) {
  final parts =
      shortcut
          .split('+')
          .map((part) => part.trim())
          .where((part) => part.isNotEmpty)
          .toList();
  if (parts.isEmpty) return null;
  final keyToken = parts.last.toLowerCase();
  final modifiers = <HotKeyModifier>[];
  for (final part in parts.take(parts.length - 1)) {
    switch (part.toLowerCase()) {
      case 'ctrl':
      case 'control':
        modifiers.add(HotKeyModifier.control);
      case 'alt':
        modifiers.add(HotKeyModifier.alt);
      case 'shift':
        modifiers.add(HotKeyModifier.shift);
      case 'win':
      case 'meta':
      case 'cmd':
        modifiers.add(HotKeyModifier.meta);
      default:
        return null;
    }
  }
  final key = _physicalKey(keyToken);
  if (key == null) return null;
  return HotKey(
    key: key,
    modifiers: modifiers,
    scope: HotKeyScope.system,
  );
}

PhysicalKeyboardKey? _physicalKey(String token) {
  if (token.length == 1) {
    final code = token.toUpperCase().codeUnitAt(0);
    if (code >= 65 && code <= 90) {
      const letters = [
        PhysicalKeyboardKey.keyA,
        PhysicalKeyboardKey.keyB,
        PhysicalKeyboardKey.keyC,
        PhysicalKeyboardKey.keyD,
        PhysicalKeyboardKey.keyE,
        PhysicalKeyboardKey.keyF,
        PhysicalKeyboardKey.keyG,
        PhysicalKeyboardKey.keyH,
        PhysicalKeyboardKey.keyI,
        PhysicalKeyboardKey.keyJ,
        PhysicalKeyboardKey.keyK,
        PhysicalKeyboardKey.keyL,
        PhysicalKeyboardKey.keyM,
        PhysicalKeyboardKey.keyN,
        PhysicalKeyboardKey.keyO,
        PhysicalKeyboardKey.keyP,
        PhysicalKeyboardKey.keyQ,
        PhysicalKeyboardKey.keyR,
        PhysicalKeyboardKey.keyS,
        PhysicalKeyboardKey.keyT,
        PhysicalKeyboardKey.keyU,
        PhysicalKeyboardKey.keyV,
        PhysicalKeyboardKey.keyW,
        PhysicalKeyboardKey.keyX,
        PhysicalKeyboardKey.keyY,
        PhysicalKeyboardKey.keyZ,
      ];
      return letters[code - 65];
    }
    if (code >= 48 && code <= 57) {
      const digits = [
        PhysicalKeyboardKey.digit0,
        PhysicalKeyboardKey.digit1,
        PhysicalKeyboardKey.digit2,
        PhysicalKeyboardKey.digit3,
        PhysicalKeyboardKey.digit4,
        PhysicalKeyboardKey.digit5,
        PhysicalKeyboardKey.digit6,
        PhysicalKeyboardKey.digit7,
        PhysicalKeyboardKey.digit8,
        PhysicalKeyboardKey.digit9,
      ];
      return digits[code - 48];
    }
  }
  return switch (token) {
    'space' => PhysicalKeyboardKey.space,
    'enter' => PhysicalKeyboardKey.enter,
    'tab' => PhysicalKeyboardKey.tab,
    'esc' || 'escape' => PhysicalKeyboardKey.escape,
    _ => null,
  };
}
