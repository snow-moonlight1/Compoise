import 'dart:io';

/// Owns only our XDG autostart entry. Nothing is written before opting in.
class LinuxAutostart {
  LinuxAutostart({Directory? config, String? executable})
    : _config =
          config ??
          Directory(
            Platform.environment['XDG_CONFIG_HOME'] ??
                '${Platform.environment['HOME']}/.config',
          ),
      _executable =
          executable ??
          Platform.environment['APPIMAGE'] ??
          Platform.resolvedExecutable;
  final Directory _config;
  final String _executable;
  File get file => File('${_config.path}/autostart/compoise.desktop');
  Future<bool> isEnabled() async => await file.exists();

  Future<void> setEnabled(bool enabled) async {
    if (!enabled) {
      if (await file.exists()) await file.delete();
      return;
    }
    if (_executable.contains('\n') ||
        _executable.contains('\r') ||
        _executable.isEmpty) {
      throw const FormatException('Invalid executable path');
    }
    final exec = _executable
        .replaceAll('\\', '\\\\')
        .replaceAll('"', '\\"')
        .replaceAll('`', '\\`')
        .replaceAll(r'$', r'\$')
        .replaceAll('%', '%%');
    await file.parent.create(recursive: true);
    await file.writeAsString(
      '[Desktop Entry]\nType=Application\nName=Compoise\nExec="$exec"\nTerminal=false\nX-GNOME-Autostart-enabled=true\n',
    );
  }
}
