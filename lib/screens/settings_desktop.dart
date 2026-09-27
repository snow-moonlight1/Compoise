import '../services/desktop_shell_host.dart';
import '../services/desktop_shell_service.dart';
import '../storage.dart';

/// Applies the Windows desktop settings the user just changed. Shared by the
/// settings section that edits them and the import that can replace them.
Future<DesktopShellSettingsResult> applyDesktopSettings(Store store) =>
    DesktopShellService.instance.applySettings(
      closeToTray: store.settings.closeToTray,
      globalShortcut: store.settings.globalShortcut,
      language: store.settings.language,
    );

/// One human-readable line about the desktop shell: what is being applied, what
/// failed, and what the user can still expect.
String desktopStatusText(Map<String, String> t, DesktopShellService shell) {
  if (shell.isApplyingSettings) {
    return t['desktopShellApplying'] ?? 'Applying Windows desktop settings…';
  }
  final result = shell.lastSettingsResult;
  if (result == null) {
    return t['desktopShellNotApplied'] ??
        'Desktop settings have not been applied yet.';
  }
  if (result.tray.isFailure) {
    return t['desktopTrayUnavailable'] ??
        'System tray is unavailable. Closing to tray is disabled.';
  }
  return switch (result.hotkey.kind) {
    DesktopShellResultKind.conflict =>
      t['desktopHotkeyConflict'] ??
          'Global shortcut conflicts with another application.',
    DesktopShellResultKind.invalid =>
      t['desktopHotkeyInvalid'] ?? 'Global shortcut format is invalid.',
    DesktopShellResultKind.unavailable =>
      t['desktopHotkeyUnavailable'] ??
          'Global shortcut could not be registered.',
    DesktopShellResultKind.disabled =>
      t['desktopHotkeyDisabled'] ?? 'Global shortcut is disabled.',
    _ => t['desktopShellReady'] ?? 'Windows desktop features are active.',
  };
}
