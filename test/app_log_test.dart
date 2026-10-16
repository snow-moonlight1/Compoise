import 'dart:io';

import 'package:compoise/diagnostics/app_log.dart';
import 'package:compoise/diagnostics/diagnostics_report.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('redaction', () {
    test('keys, tokens, addresses and user names are removed', () {
      final out = redactLogText(
        'POST https://api.example.com/v1/chat?key=AIzaSyA1234567890abcdefghijklmn '
        'failed with Authorization: Bearer sk-live-1234567890abcdef '
        'api_key="abc123" for someone@example.com at '
        r'C:\Users\alice\AppData and /home/bob/.local '
        'token a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6',
      );
      expect(out, isNot(contains('api.example.com')));
      expect(out, isNot(contains('AIza')));
      expect(out, isNot(contains('sk-live')));
      expect(out, isNot(contains('abc123')));
      expect(out, isNot(contains('someone@')));
      expect(out, isNot(contains('alice')));
      expect(out, isNot(contains('bob')));
      expect(out, isNot(contains('a1b2c3d4e5f6a1b2c3d4e5f6')));
      expect(out, contains('<url>'));
      expect(out, contains('<email>'));
    });

    test('ordinary messages and long package names stay readable', () {
      const message =
          'Notification scheduling failed: flutter_local_notifications_plugin '
          'reminder:task-1:due';
      expect(redactLogText(message), message);
    });

    test('long messages are cut short', () {
      final log = AppLog();
      log.add(AppLogLevel.warning, 'test', 'x' * 1000);
      expect(log.entries.single.message.length, AppLog.maxMessageChars);
    });
  });

  test('memory keeps only the newest entries', () {
    final log = AppLog();
    for (var i = 0; i < AppLog.maxEntries + 20; i++) {
      log.add(AppLogLevel.info, 'test', 'entry $i');
    }
    expect(log.entries.length, AppLog.maxEntries);
    expect(log.entries.first.message, 'entry 20');
  });

  test('errors keep their type and a few stack frames', () {
    final log = AppLog();
    try {
      throw StateError('broken at https://secret.example/path');
    } catch (e, stack) {
      log.error('test', e, stack);
    }
    final text = log.entries.single.format();
    expect(text, contains('[test]'));
    expect(text, contains('Bad state'));
    expect(text, isNot(contains('secret.example')));
    expect(
      '\n'.allMatches(text).length,
      lessThanOrEqualTo(AppLog.maxStackFrames),
    );
  });

  test('the file sink writes earlier entries and rotates', () async {
    final dir = await Directory.systemTemp.createTemp('compoise-log-');
    addTearDown(() => dir.delete(recursive: true));
    final log = AppLog(maxFileBytes: 4096);
    log.add(AppLogLevel.info, 'test', 'before sink');
    await log.enableFileSink(directory: dir);
    final line = 'y' * (AppLog.maxMessageChars - 10);
    for (var i = 0; i < (log.maxFileBytes * 4) ~/ line.length; i++) {
      log.add(AppLogLevel.info, 'test', line);
    }
    final recent = await log.readRecent(maxChars: 1 << 30);
    final files = dir.listSync().whereType<File>().toList();
    expect(files.length, AppLog.maxFiles);
    for (final file in files) {
      expect(file.lengthSync(), lessThanOrEqualTo(log.maxFileBytes));
    }
    expect(recent, isNot(contains('before sink')));
    expect(recent, contains(line));
    final tail = await log.readRecent(maxChars: 500);
    expect(tail.length, lessThanOrEqualTo(500));
  });

  test('a log without files still reads back from memory', () async {
    final log = AppLog();
    log.add(AppLogLevel.warning, 'test', 'only in memory');
    expect(await log.readRecent(), contains('only in memory'));
  });

  test('the diagnostics report redacts values and names the file by date', () {
    final report = buildDiagnosticsReport(
      facts: {'App version': '1.0.0+1', 'Odd value': 'Bearer abc.def'},
      log: '2026-10-20T09:00:00.000 W [test] something',
      now: DateTime(2026, 10, 20, 9),
    );
    expect(report, contains('App version: 1.0.0+1'));
    expect(report, contains('Bearer <redacted>'));
    expect(report, isNot(contains('abc.def')));
    expect(report, contains('[test] something'));
    expect(
      diagnosticsFileName(DateTime(2026, 3, 7)),
      'compoise-diagnostics-2026-03-07.txt',
    );
  });
}
