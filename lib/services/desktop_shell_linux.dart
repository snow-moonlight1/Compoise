import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';
import '../l10n.dart';
import '../diagnostics/app_log.dart';
import 'desktop_shell_host.dart';

/// Linux shell support deliberately leaves global shortcuts unsupported.
class LinuxDesktopShellHost
    with WindowListener, TrayListener
    implements DesktopShellHost {
  DesktopShellHostCallbacks? _callbacks;
  bool _bound = false;
  @override
  String? get registeredShortcut => null;

  @override
  Future<DesktopShellResult> start(DesktopShellHostCallbacks callbacks) async {
    _callbacks = callbacks;
    if (!_bound) {
      windowManager.addListener(this);
      trayManager.addListener(this);
      _bound = true;
    }
    final t = dictOf(callbacks.language);
    try {
      await trayManager.setIcon('assets/branding/rounded_rectangle_logo.png');
      await trayManager.setTitle(t['appTitle']!);
      await trayManager.setContextMenu(
        Menu(
          items: [
            MenuItem(key: 'show', label: t['trayShowWindow']!),
            MenuItem(key: 'quick-add', label: t['trayQuickAdd']!),
            MenuItem(key: 'search', label: t['traySearch']!),
            MenuItem.separator(),
            MenuItem(key: 'exit', label: t['trayExit']!),
          ],
        ),
      );
      await windowManager.setPreventClose(true);
      return const DesktopShellResult.success();
    } catch (error) {
      AppLog.warn(
        'desktop',
        'Linux tray initialization failed: ${error.runtimeType}',
      );
      // A missing tray must never hide the only reachable application window.
      await windowManager.setPreventClose(true);
      return const DesktopShellResult(DesktopShellResultKind.unavailable);
    }
  }

  @override
  Future<DesktopShellResult> show() async {
    try {
      await windowManager.show();
      await windowManager.restore();
      await windowManager.focus();
      return const DesktopShellResult.success();
    } catch (_) {
      return const DesktopShellResult(DesktopShellResultKind.unavailable);
    }
  }

  @override
  Future<DesktopShellResult> hide() async {
    try {
      await windowManager.hide();
      return const DesktopShellResult.success();
    } catch (_) {
      return const DesktopShellResult(DesktopShellResultKind.unavailable);
    }
  }

  @override
  Future<DesktopShellResult> registerHotkey(
    String shortcut,
    VoidCallback onTrigger,
  ) async => const DesktopShellResult.unsupported();
  @override
  Future<DesktopShellResult> unregisterHotkey() async =>
      const DesktopShellResult.disabled();
  @override
  Future<void> destroy() async {
    if (_bound) {
      windowManager.removeListener(this);
      trayManager.removeListener(this);
      _bound = false;
    }
    await trayManager.destroy();
    await windowManager.setPreventClose(false);
  }

  @override
  void onWindowClose() => _callbacks?.onWindowCloseRequested();
  @override
  void onTrayIconMouseDown() => _callbacks?.onRestoreRequested();
  // Linux AppIndicator opens its menu natively; popUpContextMenu is not supported.
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
