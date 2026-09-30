// Run explicitly with the pinned Flutter SDK; excluded from ordinary discovery.
// Synthetic capacity measurements, printed as JSON for the parent WP15 notes.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/backup_export.dart';
import 'package:matrixflow_native/import_preflight.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/schedule_item.dart';

const _start = 1790701200000;

void main() {
  test('WP15 structural and maximum-title library measurements', () {
    final structural = ExportData(
      timestamp: _start,
      boards: [
        for (var b = 0; b < ImportPreflight.maxBoards; b++)
          Board(id: 'b$b', name: 'B', createdAt: 1),
      ],
      tasks: [
        for (var t = 0; t < ImportPreflight.maxTasks; t++)
          Task(
            id: 't$t',
            boardId: 'b${t % ImportPreflight.maxBoards}',
            title: 'T',
            quadrant: 1,
            createdAt: 1,
            subtasks: [
              for (var s = 0; s < 5; s++) SubTask(id: 't${t}s$s', title: 'S'),
            ],
          ),
      ],
      scheduleItems: [
        for (var s = 0; s < ImportPreflight.maxScheduleItems; s++)
          ScheduleItem.timeBlock(
            id: 's$s',
            taskId: 't$s',
            startAt: _start,
            endAt: _start + 3600000,
            timeZoneId: 'Asia/Shanghai',
          ),
      ],
      settings: AppSettings(),
      aiConfig: AIConfig(),
    ).toJson();
    final clock = Stopwatch()..start();
    final encoded = jsonEncode(structural);
    final encodeMs = clock.elapsedMilliseconds;
    clock.reset();
    final bytes = Uint8List.fromList(utf8.encode(encoded));
    ImportPreflight.decode(bytes);
    final decodeMs = clock.elapsedMilliseconds;
    clock.reset();
    final structureBundle = buildBackupBundle(encoded);
    final restoreMs = clock.elapsedMilliseconds;
    expect(structureBundle.recoverable, isTrue);
    // ignore: avoid_print
    print(
      jsonEncode({
        'fixture': 'all ordinary record caps, time blocks, no large text',
        'utf8Bytes': bytes.length,
        'encodeMs': encodeMs,
        'decodeMs': decodeMs,
        'bundleAndRestoreMs': restoreMs,
        'parts': structureBundle.parts.length,
      }),
    );

    (structural['tasks'] as List).first['notesMarkdown'] =
        'x' * ImportPreflight.maxBytes;
    final withTextJson = jsonEncode(structural);
    clock.reset();
    final withTextBundle = buildBackupBundle(withTextJson);
    final withTextRestoreMs = clock.elapsedMilliseconds;
    expect(withTextBundle.recoverable, isTrue);
    expect(withTextBundle.parts.length, greaterThan(1));
    // ignore: avoid_print
    print(
      jsonEncode({
        'fixture':
            'all ordinary record caps, time blocks, plus 4 MiB task notes',
        'utf8Bytes': utf8.encode(withTextJson).length,
        'bundleAndRestoreMs': withTextRestoreMs,
        'parts': withTextBundle.parts.length,
        'partBytes': withTextBundle.parts.map((part) => part.bytes).toList(),
      }),
    );

    final titled = ExportData(
      timestamp: _start,
      boards: [
        for (var b = 0; b < 10; b++) Board(id: 'b$b', name: 'B', createdAt: 1),
      ],
      tasks: [],
      scheduleItems: [
        for (var s = 0; s < ImportPreflight.maxScheduleItems; s++)
          ScheduleItem.event(
            id: 'e$s',
            title: '"' * (ImportPreflight.maxScheduleTitleBytes ~/ 2),
            boardId: 'b${s ~/ 1000}',
            startAt: _start,
            endAt: _start + 3600000,
            timeZoneId: 'Asia/Shanghai',
          ),
      ],
      settings: AppSettings(),
      aiConfig: AIConfig(),
    ).toJson();
    clock.reset();
    final titleJson = jsonEncode(titled);
    final titleEncodeMs = clock.elapsedMilliseconds;
    clock.reset();
    final titleBundle = buildBackupBundle(titleJson);
    final titleRestoreMs = clock.elapsedMilliseconds;
    expect(titleBundle.recoverable, isTrue);
    expect(titleBundle.parts.length, greaterThan(1));
    expect(
      titleBundle.parts.every(
        (part) => part.bytes <= ImportPreflight.maxFileBytes,
      ),
      isTrue,
    );
    // ignore: avoid_print
    print(
      jsonEncode({
        'fixture':
            '10000 independent events at 4096 escaped title bytes, 10 boards',
        'utf8Bytes': utf8.encode(titleJson).length,
        'encodeMs': titleEncodeMs,
        'bundleAndRestoreMs': titleRestoreMs,
        'parts': titleBundle.parts.length,
        'partBytes': titleBundle.parts.map((part) => part.bytes).toList(),
      }),
    );
  });
}
