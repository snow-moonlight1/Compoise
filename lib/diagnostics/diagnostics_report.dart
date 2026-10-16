import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

import '../app_version.dart';
import '../services/device_prefs.dart';
import '../storage.dart';
import 'app_log.dart';

String diagnosticsFileName(DateTime now) {
  String two(int n) => n.toString().padLeft(2, '0');
  return 'compoise-diagnostics-${now.year}-${two(now.month)}-${two(now.day)}.txt';
}

/// Facts about this install that help with a bug report.
///
/// It names settings and counts only: no task titles, notes, AI address, API
/// key or file paths.
Map<String, String> diagnosticsFacts(Store store, {DevicePrefs? prefs}) {
  final device = prefs ?? DevicePrefs.instance;
  final s = store.settings;
  final ai = store.aiConfig;
  String yesNo(bool v) => v ? 'yes' : 'no';
  return {
    'App version': appVersionLabel,
    'Build mode': kReleaseMode
        ? 'release'
        : kProfileMode
        ? 'profile'
        : 'debug',
    'Operating system':
        '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
    'System locale': Platform.localeName,
    'Language': s.language.name,
    'Theme': '${s.theme.name}, ${s.themeColor.name}',
    'Font': '${s.fontFamily.name}, ${s.fontSize.name}',
    'Neumorphic': yesNo(s.neumorphic),
    'Comic outline': yesNo(s.comicOutline),
    'Reduce motion': yesNo(s.reduceMotion),
    'Close to tray': yesNo(s.closeToTray),
    'AI preset': ai.provider,
    'AI protocol': ai.protocol.name,
    'AI model set': yesNo(ai.model.trim().isNotEmpty),
    'AI address set': yesNo(ai.baseUrl.trim().isNotEmpty),
    'AI key set': yesNo(ai.apiKey.trim().isNotEmpty),
    'AI thinking': yesNo(ai.enableThinking),
    'AI wait time': '${device.aiTimeoutSeconds}s',
    'Update check': yesNo(device.updateCheckEnabled),
    'Boards': '${store.boards.length}',
    'Tasks': '${store.tasks.length}',
    'Completed tasks': '${store.tasks.where((t) => t.completed).length}',
    'Schedule items': '${store.scheduleItems.length}',
  };
}

/// The text file a user can attach to an issue. Every value goes through the
/// same redaction as the log, so a stray secret in a setting cannot leak.
String buildDiagnosticsReport({
  required Map<String, String> facts,
  required String log,
  required DateTime now,
}) {
  final out = StringBuffer()
    ..writeln('Compoise diagnostics')
    ..writeln('Generated: ${now.toIso8601String()}')
    ..writeln(
      'Contains no task content, AI address or API key. '
      'Review it before sharing.',
    )
    ..writeln();
  for (final entry in facts.entries) {
    out.writeln('${entry.key}: ${redactLogText(entry.value)}');
  }
  out
    ..writeln()
    ..writeln('Recent log')
    ..writeln('----------');
  out.writeln(log.trim().isEmpty ? '(empty)' : log.trimRight());
  return out.toString();
}
