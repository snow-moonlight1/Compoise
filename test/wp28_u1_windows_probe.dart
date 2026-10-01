// Native application probe; never use the real roaming profile.
// Run only with WP28_U1_PROBE_ROOT naming a pre-created wp28-u1-device-* folder
// beneath the OS temporary directory. Reports stay inside that fixture.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
// ignore: depend_on_referenced_packages
import 'package:path/path.dart' as p;
import 'package:matrixflow_native/main.dart' show MatrixFlowApp;
import 'package:matrixflow_native/screens/windows_upgrade_screen.dart';
import 'package:matrixflow_native/services/desktop_shell_windows.dart';
import 'package:matrixflow_native/services/single_instance.dart';
import 'package:matrixflow_native/services/windows_data_upgrade.dart';
import 'package:matrixflow_native/storage.dart';
import 'package:window_manager/window_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'wp28_u1_support.dart';

class _SyntheticCredential implements CredentialStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async {
    this.value = value;
  }

  @override
  Future<void> delete() async {
    value = null;
  }
}

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final injected = Platform.environment['WP28_U1_PROBE_ROOT'];
  if (injected == null) throw StateError('Isolated probe root required');
  final root = await Directory(injected).resolveSymbolicLinks();
  final temp = await Directory.systemTemp.resolveSymbolicLinks();
  if (!p.isWithin(temp, root) ||
      !p.basename(root).startsWith('wp28-u1-device-')) {
    throw StateError('Only an isolated OS temporary probe root is allowed');
  }
  final paths = WindowsUpgradePaths(root);
  final pluginPath = await IsolatedRootWindowsPathProvider(
    root,
  ).getApplicationSupportPath();
  final metadataPathMatches = p.equals(pluginPath!, paths.current);
  if (!metadataPathMatches) throw StateError('Unexpected probe exe identity');
  final source = File(p.join(paths.source, WindowsDataUpgrade.preferencesName));
  await Directory(paths.source).create(recursive: true);
  if (!await source.exists()) {
    await source.writeAsString(jsonEncode(mirrorEnvelope(syntheticSnapshot())));
  }
  final sourceBefore = await source.readAsBytes();
  Store.testCredentialStore = _SyntheticCredential();
  final reminders = NoopReminderService();
  ReminderService.instance = reminders;
  await ensureWindowsWindowManager();
  var activations = 0;
  await SingleInstanceController.install(
    initialArguments: args,
    onActivated: (_) {
      activations++;
    },
  );
  final upgrade = WindowsDataUpgrade(paths: () async => paths);
  WindowsUpgradeResult? result;
  runApp(
    WindowsUpgradeStartup(
      deviceLocales: const [Locale('en')],
      prepare: () async => result = await upgrade.prepare(),
      closeBeforeStore: windowManager.destroy,
      openApplication: () async {
        await openIsolatedWindowsPreferences(paths.current);
        await reminders.init();
        // Use the production app/store with a real Windows preferences plugin.
        Timer(const Duration(seconds: 8), () async {
          final reportValues = <String, Object?>{
            'passed': false,
            'status': result!.status.name,
            'exeMetadataPathMatches': metadataPathMatches,
            'preferencesPath': paths.current,
          };
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.reload();
            final committed = SaveProtocol(prefs).load();
            final tasks =
                jsonDecode(committed!.values['matrixflow-tasks']!) as List;
            final schedule =
                jsonDecode(committed.values['matrixflow-schedule']!) as List;
            final task = tasks.single as Map;
            final preserved = listEquals(
              sourceBefore,
              await source.readAsBytes(),
            );
            final passed =
                task['id'] == 'synthetic-task' &&
                task['plannedDate'] == 1790812800000 &&
                (task['subtasks'] as List).single['id'] ==
                    'synthetic-subtask' &&
                schedule.length == 1 &&
                preserved;
            reportValues.addAll({
              'passed': passed,
              'status': result!.status.name,
              'sourceBytesUnchanged': preserved,
              'taskCount': tasks.length,
              'scheduleCount': schedule.length,
              'plannedDate': task['plannedDate'],
              'activations': activations,
            });
          } catch (_) {
            reportValues['failure'] = 'Native synthetic probe failed';
          } finally {
            final report = File(
              p.join(root, 'probe-${result!.status.name}.json'),
            );
            await report.writeAsString(jsonEncode(reportValues), flush: true);
            await windowManager.destroy();
          }
        });
        return MatrixFlowApp(reminders: reminders);
      },
    ),
  );
}
