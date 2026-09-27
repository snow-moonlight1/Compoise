import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:matrixflow_native/services/desktop_shell_service.dart';
import 'package:matrixflow_native/services/desktop_shell_windows.dart';
import 'package:tray_manager/tray_manager.dart';

String? _smokeReportPath;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _smokeReportPath = Platform.environment['MATRIXFLOW_OS14_SMOKE_RESULT'];
  _record('before ensureWindowsWindowManager');
  await ensureWindowsWindowManager();
  _record('after ensureWindowsWindowManager');
  runApp(const MaterialApp(home: _SmokeWindow()));
}

void _record(String message) {
  final path = _smokeReportPath;
  if (path == null || path.isEmpty) return;
  File(path).writeAsStringSync('$message\n', mode: FileMode.append);
}

class _SmokeWindow extends StatefulWidget {
  const _SmokeWindow();

  @override
  State<_SmokeWindow> createState() => _SmokeWindowState();
}

class _SmokeWindowState extends State<_SmokeWindow> {
  String _status = 'Starting OS14 Windows shell smoke test…';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_run());
    });
  }

  Future<void> _run() async {
    final resultPath = Platform.environment['MATRIXFLOW_OS14_SMOKE_RESULT'];
    final host = WindowsDesktopShellHost();
    final service = DesktopShellService.forTest(host);
    var exitCode = 1;
    var report = 'OS14 Windows shell smoke failed before completion.';

    try {
      _setStatus('Initializing tray and safe global shortcut…');
      final ready = await service.applySettings(
        closeToTray: true,
        globalShortcut: 'Ctrl+Alt+Shift+9',
      );
      _require(ready.tray.succeeded, 'tray initialization failed');
      _require(ready.hotkey.succeeded, 'safe hotkey registration failed');
      _require(
        ready.closeToTrayEffective,
        'close-to-tray did not become effective',
      );

      _setStatus('Hiding the independent test window…');
      final hidden = await service.hideWindowToTray();
      _require(hidden.succeeded, 'window hide call failed');
      await Future<void>.delayed(const Duration(milliseconds: 300));
      _require(
        !(await host.isWindowActuallyVisible()),
        'window remained visible',
      );

      host.onTrayIconMouseDown();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      _require(
        await host.isWindowActuallyVisible(),
        'tray recall did not show window',
      );
      _require(service.isWindowVisible, 'service did not observe tray recall');

      _setStatus('Verifying reserved shortcut conflict and retry…');
      final reserved = await service.registerGlobalHotkey('Win+L', () {});
      _require(!reserved.succeeded, 'reserved Win+L unexpectedly registered');
      final recovered = await service.registerGlobalHotkey(
        'Ctrl+Alt+Shift+9',
        () {},
      );
      _require(recovered.succeeded, 'hotkey retry failed');

      exitCode = 0;
      report =
          'PASS tray=${ready.tray.kind.name} '
          'hotkey=${ready.hotkey.kind.name} '
          'reserved=${reserved.kind.name} hide=ok recall=ok retry=ok';
      _setStatus(report);
    } catch (error, stackTrace) {
      report = 'FAIL $error\n$stackTrace';
      _setStatus(report);
    } finally {
      try {
        _record('cleanup: unregister hotkey');
        await service.unregisterGlobalHotkey();
        _record('cleanup: destroy tray');
        await trayManager.destroy();
        _record('cleanup: complete');
      } catch (cleanupError) {
        if (exitCode == 0) {
          exitCode = 1;
          report = 'FAIL cleanup: $cleanupError';
        }
      }
      if (resultPath != null && resultPath.isNotEmpty) {
        await File(resultPath).writeAsString(report);
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
      exit(exitCode);
    }
  }

  void _setStatus(String value) {
    _record(value);
    if (!mounted) return;
    setState(() => _status = value);
  }

  void _require(bool condition, String message) {
    if (!condition) throw StateError(message);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(_status, textAlign: TextAlign.center),
      ),
    ),
  );
}
