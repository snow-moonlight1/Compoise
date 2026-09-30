import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/schedule_item.dart';
import 'package:matrixflow_native/schedule_time.dart';
import 'package:matrixflow_native/widgets/schedule_layout.dart';

import 'support/wp15_c1_fixtures.dart';

List<ScheduleEntry> _entries(List<ScheduleItem> items) =>
    scheduleEntries(items: items, tasks: c1Tasks(), boards: c1Boards());

ScheduleDayLayout _day(int day, List<ScheduleItem> items) => ScheduleDayLayout(
  date: ScheduleCivilDate(2026, 9, day),
  timeZoneId: c1Zone,
  entries: _entries(items),
);

void main() {
  test(
    'current parent titles, board, quadrant and completion drive associations',
    () {
      final tasks = c1Tasks();
      tasks.first
        ..title = 'Renamed'
        ..boardId = 'home'
        ..quadrant = 4
        ..completed = true;
      final entries = scheduleEntries(
        items: c1Items(),
        tasks: tasks,
        boards: c1Boards(),
        boardId: 'home',
      );
      expect(entries, hasLength(4));
      final block = entries.first;
      expect(block.title, 'Renamed');
      expect(block.boardName, 'Home board');
      expect(block.quadrant, 4);
      expect(block.completed, isTrue);
      expect(entries[1].title, 'Event linked');
      expect(entries[1].taskTitle, 'Renamed');
      expect(entries[2].taskTitle, isNull);
      expect(
        scheduleEntries(
          items: c1Items(),
          tasks: tasks,
          boards: c1Boards(),
          boardId: 'work',
        ),
        isEmpty,
      );
    },
  );

  test('midnight is half open and cross-day slices retain identity', () {
    final items = [
      c1Event('ends', c1At(29, 23), c1At(30, 0)),
      c1Event('starts', c1At(30, 0), c1At(30, 1)),
      c1Event('cross', c1At(29, 23), c1At(30, 1)),
    ];
    expect(_day(29, items).placements.map((p) => p.entry.item.id), [
      'cross',
      'ends',
    ]);
    final next = _day(30, items).placements;
    expect(next.map((p) => p.entry.item.id), ['cross', 'starts']);
    expect(next.first.slice.continuesBefore, isTrue);
    expect(next.first.slice.continuesAfter, isFalse);
    expect(next.first.slice.startAt, c1At(30, 0));
    expect(next.first.entry.item.startAt, c1At(29, 23));
  });

  test('multiweek query includes records that started outside the week', () {
    final item = c1Event('weeks', c1At(13, 23), c1At(29, 1));
    final layouts = [
      for (var d = 21; d <= 27; d++) _day(d, [item]),
    ];
    for (final layout in layouts) {
      expect(layout.placements, hasLength(1));
      expect(layout.placements.single.slice.continuesBefore, isTrue);
      expect(layout.placements.single.slice.continuesAfter, isTrue);
      expect(layout.placements.single.entry.item.id, item.id);
    }
    final endAtMonday = c1Event('stop', c1At(27, 23), c1At(28, 0));
    expect(_day(28, [endAtMonday]).placements, isEmpty);
  });

  test(
    'mixed overlaps and identical blocks have separate lanes and no mutation',
    () {
      final items = c1Items();
      items.add(
        ScheduleItem.timeBlock(
          id: 'block-2',
          taskId: 'outline',
          startAt: items.first.startAt,
          endAt: items.first.endAt,
          timeZoneId: c1Zone,
        ),
      );
      final before = jsonEncode(items.map((item) => item.toJson()).toList());
      final layout = _day(30, items);
      expect(layout.laneCount, 4);
      expect(
        layout.placements.take(4).map((p) => p.lane).toSet(),
        hasLength(4),
      );
      expect(jsonEncode(items.map((item) => item.toJson()).toList()), before);
    },
  );

  test(
    'touching intervals reuse a lane; minimum touch targets never collide',
    () {
      final items = [
        c1Event('a', c1At(30, 1), c1At(30, 2)),
        c1Event('b', c1At(30, 2), c1At(30, 3)),
      ];
      expect(_day(30, items).laneCount, 1);
      final short = _day(30, [
        c1Event('short-a', c1At(30, 1), c1At(30, 1, minute: 1)),
        c1Event('short-b', c1At(30, 1, minute: 1), c1At(30, 1, minute: 2)),
      ]);
      expect(short.laneCount, 2);
      expect(short.placements.every((p) => p.height >= 48), isTrue);
    },
  );

  test(
    'dense overlaps expand horizontally and final millisecond is reachable',
    () {
      final layout = _day(30, [
        for (var i = 0; i < 20; i++) c1Event('$i', c1At(30, 1), c1At(30, 2)),
        c1Event(
          'last',
          c1At(30, 24 - 1, minute: 59) + 59999,
          dayWindow(ScheduleCivilDate(2026, 9, 30), c1Zone).endAt,
        ),
      ]);
      expect(layout.laneCount, 20);
      for (final p in layout.placements) {
        expect(p.top + p.height, lessThanOrEqualTo(layout.height));
      }
    },
  );

  for (final (month, day, hours, count) in [(3, 8, 23, 24), (11, 1, 25, 26)]) {
    test(
      '$hours-hour day uses adjacent civil boundaries and real hour candidates',
      () {
        const zone = 'America/New_York';
        final date = ScheduleCivilDate(2026, month, day);
        final window = dayWindow(date, zone);
        final item = c1Event('dst', window.startAt, window.endAt, zone: zone);
        final layout = ScheduleDayLayout(
          date: date,
          timeZoneId: zone,
          entries: _entries([item]),
        );
        expect(layout.axisHeight, hours * 80);
        expect(layout.ticks, hasLength(count));
        expect(layout.placements.single.height, hours * 80);
        expect(
          layout.ticks.map((tick) => tick.top).toList(),
          orderedEquals(layout.ticks.map((tick) => tick.top).toList()..sort()),
        );
        if (hours == 23) {
          expect(
            layout.ticks.where((tick) => tick.label.startsWith('02:')),
            isEmpty,
          );
        } else {
          final folds = layout.ticks
              .where((tick) => tick.label.startsWith('01:'))
              .toList();
          expect(folds.map((tick) => tick.label), [
            '01:00 UTC-04:00',
            '01:00 UTC-05:00',
          ]);
          expect(folds[1].top - folds[0].top, 80);
        }
      },
    );
  }

  test(
    'two fold candidates produce distinct separately accessible records',
    () {
      const zone = 'America/New_York';
      final date = ScheduleCivilDate(2026, 11, 1);
      final folds = wallTimeCandidates(
        ScheduleWallTime(date, hour: 1, minute: 15),
        zone,
      );
      final layout = ScheduleDayLayout(
        date: date,
        timeZoneId: zone,
        entries: _entries([
          for (var i = 0; i < 2; i++)
            c1Event(
              'fold$i',
              folds[i].instantMs,
              folds[i].instantMs + 30 * Duration.millisecondsPerMinute,
              zone: zone,
            ),
        ]),
      );
      expect(layout.placements, hasLength(2));
      expect(layout.placements[1].top - layout.placements[0].top, 80);
      expect(scheduleClockLabel(folds[0].instantMs, zone), '01:15 UTC-04:00');
      expect(scheduleClockLabel(folds[1].instantMs, zone), '01:15 UTC-05:00');
    },
  );

  test(
    'display zone changes labels and date clipping, never saved endpoints',
    () {
      final item = c1Event('zone', c1At(30, 0), c1At(30, 1));
      final before = jsonEncode(item.toJson());
      final utc = ScheduleDayLayout(
        date: ScheduleCivilDate(2026, 9, 29),
        timeZoneId: 'UTC',
        entries: _entries([item]),
      );
      expect(utc.placements, hasLength(1));
      expect(scheduleClockLabel(item.startAt, 'UTC'), '16:00 UTC+00:00');
      expect(jsonEncode(item.toJson()), before);
    },
  );

  test('half-hour DST day and subsecond labels preserve exact time', () {
    final layout = ScheduleDayLayout(
      date: ScheduleCivilDate(2026, 10, 4),
      timeZoneId: 'Australia/Lord_Howe',
      entries: const [],
    );
    expect(layout.axisHeight, 23.5 * 80);
    expect(layout.ticks.any((tick) => tick.label.startsWith('02:00')), isFalse);
    expect(
      scheduleClockLabel(c1At(30, 0) + 1234, c1Zone),
      '00:00:01.234 UTC+08:00',
    );
  });
}
