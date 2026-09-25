import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

/// Isolated Windows multi-instance probe.
///
/// Refuses to start without MATRIXFLOW_OS16_DATA_DIR. It writes only inside
/// that directory and does not open SharedPreferences, credential storage, or
/// the production notification activator.
Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final dataDirPath = Platform.environment['MATRIXFLOW_OS16_DATA_DIR'];
  if (dataDirPath == null || dataDirPath.trim().isEmpty) {
    stderr.writeln('MATRIXFLOW_OS16_DATA_DIR is required');
    exit(2);
  }
  final dataDir = Directory(dataDirPath);
  await dataDir.create(recursive: true);
  final report = _Reporter(
    Platform.environment['MATRIXFLOW_OS16_SMOKE_RESULT'],
  );
  final taskId =
      Platform.environment['MATRIXFLOW_OS16_TASK_ID'] ?? 'os16-task';
  final raceMs =
      int.tryParse(Platform.environment['MATRIXFLOW_OS16_RACE_MS'] ?? '') ??
      0;

  await windowManager.ensureInitialized();
  await windowManager.setTitle('MatrixFlow OS16 isolated test');
  runApp(const MaterialApp(home: SizedBox.shrink()));

  const singleInstance = MethodChannel('matrixflow/single_instance');
  const hotkey = MethodChannel('matrixflow/os14_hotkey');
  var channelReady = false;
  try {
    singleInstance.setMethodCallHandler((call) async {
      if (call.method != 'onSecondInstance') return;
      final forwarded =
          (call.arguments as List?)?.map((item) => '$item').toList() ??
          const <String>[];
      final visible = await hotkey.invokeMethod<bool>('isVisible');
      final minimized = await windowManager.isMinimized();
      report.write(
        'FORWARDED visible=$visible minimized=$minimized args=${jsonEncode(forwarded)}',
      );
    });
    final pending = await singleInstance.invokeMethod<dynamic>('listen');
    report.write('LISTEN ${jsonEncode(pending)}');
    final scope = await singleInstance.invokeMethod<dynamic>('scope');
    report.write('SCOPE ${jsonEncode(scope)}');
    channelReady = true;
  } on MissingPluginException {
    report.write('NO_SINGLE_INSTANCE_CHANNEL');
  }

  report.write(
    'WRITER pid=$pid channel=$channelReady args=${jsonEncode(args)}',
  );
  await _writeLibrary(dataDir, taskId, raceMs, report);

  if (Platform.environment['MATRIXFLOW_OS16_HIDE'] == '1') {
    final hidden = await hotkey.invokeMethod<bool>('hide');
    report.write('HIDDEN hidden=$hidden');
  } else if (Platform.environment['MATRIXFLOW_OS16_MINIMIZE'] == '1') {
    await windowManager.minimize();
    report.write(
      'MINIMIZED minimized=${await windowManager.isMinimized()}',
    );
  }

  final visible = await hotkey.invokeMethod<bool>('isVisible');
  report.write(
    'READY pid=$pid visible=$visible minimized=${await windowManager.isMinimized()}',
  );

  final commandFile = File('${dataDir.path}\\command.txt');
  final stopFile = File('${dataDir.path}\\stop');
  final deadline = DateTime.now().add(const Duration(seconds: 90));
  while (DateTime.now().isBefore(deadline)) {
    if (stopFile.existsSync()) break;
    if (commandFile.existsSync()) {
      final command = commandFile.readAsStringSync().trim();
      if (command.isNotEmpty) {
        commandFile.deleteSync();
        if (command == 'hide') {
          final hidden = await hotkey.invokeMethod<bool>('hide');
          report.write('COMMAND_HIDE hidden=$hidden');
        } else if (command == 'minimize') {
          await windowManager.minimize();
          report.write(
            'COMMAND_MINIMIZE minimized=${await windowManager.isMinimized()}',
          );
        } else if (command == 'stop') {
          break;
        }
        final nowVisible = await hotkey.invokeMethod<bool>('isVisible');
        report.write(
          'COMMAND_DONE command=$command visible=$nowVisible minimized=${await windowManager.isMinimized()}',
        );
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  report.write('EXIT pid=$pid');
  exit(0);
}

Future<void> _writeLibrary(
  Directory dataDir,
  String taskId,
  int raceMs,
  _Reporter report,
) async {
  final file = File('${dataDir.path}\\library.json');
  Map<String, dynamic> document;
  if (file.existsSync()) {
    final decoded = jsonDecode(file.readAsStringSync());
    document = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
  } else {
    document = <String, dynamic>{};
  }
  final tasks =
      (document['tasks'] as List?)?.map((item) => '$item').toList() ??
      <String>[];
  report.write('READ pid=$pid tasks=${jsonEncode(tasks)}');
  if (raceMs > 0) {
    await Future<void>.delayed(Duration(milliseconds: raceMs));
  }
  if (!tasks.contains(taskId)) tasks.add(taskId);
  document['tasks'] = tasks;
  file.writeAsStringSync(jsonEncode(document), flush: true);
  report.write('WROTE pid=$pid tasks=${jsonEncode(tasks)}');
}

class _Reporter {
  _Reporter(this.path);

  final String? path;

  void write(String message) {
    final target = path;
    final line = '${DateTime.now().toIso8601String()} $message\n';
    if (target == null || target.isEmpty) {
      stdout.write(line);
      return;
    }
    File(target).writeAsStringSync(line, mode: FileMode.append, flush: true);
  }
}
