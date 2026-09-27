import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:matrixflow_native/services/desktop_shell_service.dart';
import 'package:matrixflow_native/services/desktop_shell_windows.dart';

String? _reportPath;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _reportPath = Platform.environment['MATRIXFLOW_OS15_SMOKE_RESULT'];
  _record('START isolated OS15 Windows exit smoke');
  await ensureWindowsWindowManager();
  runApp(const MaterialApp(home: _ExitSmokeWindow()));
}

void _record(String message) {
  final path = _reportPath;
  if (path == null || path.isEmpty) return;
  File(
    path,
  ).writeAsStringSync('$message\n', mode: FileMode.append, flush: true);
}

class _ExitSmokeWindow extends StatefulWidget {
  const _ExitSmokeWindow();

  @override
  State<_ExitSmokeWindow> createState() => _ExitSmokeWindowState();
}

class _ExitSmokeWindowState extends State<_ExitSmokeWindow> {
  String _status = 'Preparing isolated OS15 exit test…';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_run());
    });
  }

  Future<void> _run() async {
    final host = WindowsDesktopShellHost();
    final service = DesktopShellService.forTest(host);
    final ready = await service.applySettings(
      closeToTray: false,
      globalShortcut: '',
    );
    if (!ready.tray.succeeded) {
      _record('FAIL tray initialization: ${ready.tray.kind.name}');
      exitCode = 2;
      return;
    }

    service.onExit = () async {
      _record('COORDINATOR started');
      await Future<void>.delayed(const Duration(milliseconds: 150));
      _record('COORDINATOR completed');
      return true;
    };
    if (mounted) {
      setState(() => _status = 'Requesting coordinated real window close…');
    }
    _record('EXIT requested');
    unawaited(service.exitApplication());
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
