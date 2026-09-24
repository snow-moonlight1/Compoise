import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:matrixflow_native/services/desktop_shell_host.dart';
import 'package:matrixflow_native/services/desktop_shell_windows.dart';
import 'package:matrixflow_native/services/reminder_service.dart';

/// Real Windows notification and tray smoke.
///
/// This process talks to the platform plugins and does not open the task
/// profile, so user tasks and settings stay untouched.
/// Run it only when a Windows desktop session is available:
///
/// flutter run -d windows -t tool/os25_platform_smoke.dart --no-pub
///
/// Set MATRIXFLOW_OS25_SMOKE_RESULT to a file path to keep the one-line report.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final resultPath = Platform.environment['MATRIXFLOW_OS25_SMOKE_RESULT'];
  if (!Platform.isWindows) {
    _write(
      resultPath,
      'NOT-RUN real notification and tray smoke requires Windows. '
      'This process did not execute it.',
    );
    exit(2);
  }

  runApp(const MaterialApp(home: _SmokeWindow()));
}

void _write(String? path, String message) {
  if (path == null || path.isEmpty) return;
  File(path).writeAsStringSync('$message\n');
}

class _SmokeWindow extends StatefulWidget {
  const _SmokeWindow();

  @override
  State<_SmokeWindow> createState() => _SmokeWindowState();
}

class _SmokeWindowState extends State<_SmokeWindow> {
  String _status = 'Starting OS25 platform smoke…';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_run());
    });
  }

  Future<void> _run() async {
    final resultPath = Platform.environment['MATRIXFLOW_OS25_SMOKE_RESULT'];
    final notifications = FlutterLocalNotificationsReminderService();
    final taskId = 'os25-smoke-${DateTime.now().microsecondsSinceEpoch}';
    WindowsDesktopShellHost? host;
    var exitCode = 1;
    var report = 'FAIL OS25 platform smoke stopped before completion.';

    try {
      await ensureWindowsWindowManager();
      await notifications.init();
      await notifications.scheduleReminder(
        boardId: 'os25-smoke',
        taskId: taskId,
        title: 'OS25 smoke',
        triggerAtMs: DateTime.now()
            .subtract(const Duration(seconds: 1))
            .millisecondsSinceEpoch,
      );
      final failures = notifications.scheduleFailures.value.length;
      if (failures != 0) {
        throw StateError(
          'notification plugin did not show the smoke notification '
          '(failures=$failures)',
        );
      }

      host = WindowsDesktopShellHost();
      final tray = await host.start(
        DesktopShellHostCallbacks(
          onWindowCloseRequested: () {},
          onRestoreRequested: () {},
        ),
      );
      if (!tray.succeeded) {
        throw StateError('tray initialization returned ${tray.kind.name}');
      }

      exitCode = 0;
      report =
          'PASS notification=shown tray=${tray.kind.name} profile=untouched';
      _setStatus(report);
    } catch (error, stackTrace) {
      report = 'FAIL $error\n$stackTrace';
      _setStatus(report);
    } finally {
      try {
        await notifications.cancelReminder(taskId);
      } catch (error) {
        if (exitCode == 0) {
          exitCode = 1;
          report = 'FAIL notification cleanup: $error';
        }
      }
      try {
        await host?.destroy();
      } catch (error) {
        if (exitCode == 0) {
          exitCode = 1;
          report = 'FAIL tray cleanup: $error';
        }
      }
      _write(resultPath, report.split('\n').first);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      exit(exitCode);
    }
  }

  void _setStatus(String value) {
    if (!mounted) return;
    setState(() => _status = value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_status, textAlign: TextAlign.center),
        ),
      ),
    );
  }
}
