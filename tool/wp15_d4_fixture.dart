// Synthetic, offline v3 fixtures for a dedicated VM/profile. No application IO.
import 'dart:convert';
import 'dart:io';

import 'package:matrixflow_native/schedule_item.dart';
import 'package:matrixflow_native/schedule_time.dart';

Map<String, Object?> d4Fixture({required bool fold}) {
  const zone = 'America/New_York';
  final day = ScheduleCivilDate(2026, fold ? 11 : 3, fold ? 1 : 8);
  int at(ScheduleCivilDate date, int hour, int minute, {int? offset}) =>
      resolveWallTime(
        ScheduleWallTime(date, hour: hour, minute: minute),
        zone,
        offset: offset == null ? null : Duration(minutes: offset),
      );
  final start = at(day, fold ? 1 : 0, 30, offset: fold ? -240 : null);
  final end = at(day, 1, 45, offset: fold ? -300 : null);
  final items = [
    ScheduleItem.timeBlock(
      id: 'd4-block',
      taskId: 'd4-parent',
      startAt: start,
      endAt: end,
      timeZoneId: zone,
    ),
    ScheduleItem.event(
      id: 'd4-overlap',
      title: 'D4 overlapping event',
      boardId: 'd4-board',
      startAt: start,
      endAt: end,
      timeZoneId: zone,
    ),
    ScheduleItem.event(
      id: 'd4-midnight',
      title: 'D4 ends at midnight',
      boardId: 'd4-board',
      startAt: at(day.addDays(-1), 23, 30),
      endAt: at(day, 0, 0),
      timeZoneId: zone,
    ),
    ScheduleItem.event(
      id: 'd4-cross',
      title: 'D4 crosses midnight',
      boardId: 'd4-board',
      startAt: at(day, 23, 30),
      endAt: at(day.addDays(1), 0, 30),
      timeZoneId: zone,
    ),
    ScheduleItem.timeBlock(
      id: 'd4-completed',
      taskId: 'd4-done',
      startAt: at(day.addDays(1), 0, 0) - 1,
      endAt: at(day.addDays(1), 0, 0),
      timeZoneId: zone,
    ),
  ];
  validateScheduleCollection(
    items,
    parentTaskIds: {'d4-parent', 'd4-done'},
    boardIds: {'d4-board'},
  );
  return {
    'version': 3,
    'timestamp': '2026-10-03T00:00:00.000Z',
    'boards': [
      {'id': 'd4-board', 'name': 'Synthetic D4', 'createdAt': 1},
    ],
    'tasks': [
      for (final completed in [false, true])
        {
          'id': completed ? 'd4-done' : 'd4-parent',
          'title': completed ? 'D4 completed parent' : 'D4 parent',
          'boardId': 'd4-board',
          'quadrant': completed ? 3 : 2,
          'completed': completed,
          'createdAt': 1,
          'isLongTerm': false,
          'urgencyMode': 'manual',
          'subtasks': <Object?>[],
          'plannedDate': DateTime.utc(2026, 3, 7).millisecondsSinceEpoch,
          'deadline': DateTime.utc(
            2030,
            3,
            9,
            23,
            59,
            59,
          ).millisecondsSinceEpoch,
          'reminderAt': DateTime.utc(2030, 3, 9, 9).millisecondsSinceEpoch,
        },
    ],
    'scheduleItems': items.map((item) => item.toJson()).toList(),
    'settings': {'language': 'en'},
    'aiConfig': <String, Object?>{},
  };
}

void main() {
  final root = Directory('build/wp15-d4/manual')..createSync(recursive: true);
  for (final fold in [false, true]) {
    final file = File('${root.path}/${fold ? 'fold' : 'spring'}.json');
    file.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(d4Fixture(fold: fold)),
      flush: true,
    );
    stdout.writeln(file.absolute.path);
  }
}
