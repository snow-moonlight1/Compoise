import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/schedule_item.dart';
import 'package:matrixflow_native/schedule_time.dart';

void main() {
  final start = DateTime.utc(2026, 9, 29, 9).millisecondsSinceEpoch;
  final end = start + const Duration(hours: 1).inMilliseconds;

  ScheduleItem block(String id, {int? from, int? to}) => ScheduleItem.timeBlock(
    id: id,
    taskId: 'parent',
    startAt: from ?? start,
    endAt: to ?? end,
    timeZoneId: 'Asia/Shanghai',
  );

  group('schedule item model', () {
    test(
      'time block, linked event and board event round-trip without losing IDs',
      () {
        final records = [
          block('block'),
          ScheduleItem.event(
            id: 'linked',
            title: 'Review',
            taskId: 'parent',
            startAt: start,
            endAt: end,
            timeZoneId: 'UTC',
          ),
          ScheduleItem.event(
            id: 'standalone',
            title: 'Meeting',
            boardId: 'board',
            startAt: start,
            endAt: end,
            timeZoneId: 'America/New_York',
          ),
        ];
        for (final record in records) {
          final decoded = ScheduleItem.fromJson(record.toJson());
          expect(decoded.toJson(), record.toJson());
          expect(decoded.id, record.id);
        }
        expect(records[0].toJson().containsKey('boardId'), isFalse);
        expect(records[1].toJson().containsKey('boardId'), isFalse);
        expect(records[2].toJson().containsKey('taskId'), isFalse);
      },
    );

    test(
      'rejects invalid identity, kind, interval, zone and association fields',
      () {
        final valid = block('b').toJson();
        for (final bad in <Map<String, dynamic>>[
          {...valid, 'id': '  '},
          {...valid, 'kind': 'reminder'},
          {...valid, 'startAt': end},
          {...valid, 'endAt': start},
          {...valid, 'startAt': 8640000000000001},
          {...valid, 'endAt': 1.5},
          {...valid, 'timeZoneId': 'Mars/Olympus'},
          {...valid, 'taskId': ''},
          {...valid, 'boardId': 'board'},
          {...valid, 'title': 'Wrong'},
          {...valid, 'taskId': null},
          {...valid, 'id': 1},
        ]) {
          expect(
            () => ScheduleItem.fromJson(bad),
            throwsA(isA<Exception>()),
            reason: '$bad',
          );
        }
        final event = ScheduleItem.event(
          id: 'e',
          title: 'Meeting',
          boardId: 'board',
          startAt: start,
          endAt: end,
          timeZoneId: 'UTC',
        ).toJson();
        for (final bad in <Map<String, dynamic>>[
          {...event, 'title': ' '},
          {...event, 'taskId': 'parent'},
          {...event, 'boardId': null},
          {...event, 'boardId': ''},
          {...event, 'taskId': null},
        ]) {
          expect(
            () => ScheduleItem.fromJson(bad),
            throwsFormatException,
            reason: '$bad',
          );
        }
      },
    );

    test(
      'collection validates duplicate IDs and live parent/board references',
      () {
        final linked = block('one');
        final standalone = ScheduleItem.event(
          id: 'two',
          title: 'Meeting',
          boardId: 'board',
          startAt: start,
          endAt: end,
          timeZoneId: 'UTC',
        );
        void validate(
          Iterable<ScheduleItem> items,
          Set<String> tasks,
          Set<String> boards,
        ) => validateScheduleCollection(
          items,
          parentTaskIds: tasks,
          boardIds: boards,
        );
        expect(
          () => validate([linked, standalone], {'parent'}, {'board'}),
          returnsNormally,
        );
        expect(
          () => validate([linked, linked], {'parent'}, {'board'}),
          throwsFormatException,
        );
        expect(
          () => validate([linked], {'child-only'}, {'board'}),
          throwsFormatException,
        );
        expect(
          () => validate([standalone], {'parent'}, {}),
          throwsFormatException,
        );
      },
    );

    test('overlap is advisory and touching endpoints are separate', () {
      final one = block('one');
      final touching = block('two', from: end, to: end + 1000);
      final overlapping = block('three', from: start + 500, to: end + 500);
      expect(scheduleIntervalsOverlap(start, end, end, end + 1000), isFalse);
      expect(
        overlappingScheduleItems([
          one,
          touching,
          overlapping,
        ], one).map((item) => item.id),
        ['three'],
      );
      expect(one.toJson(), block('one').toJson());
    });
  });

  group('wall time and calendar windows', () {
    test('normal wall time resolves, invalid date and clock reject', () {
      final wall = ScheduleWallTime(
        ScheduleCivilDate(2026, 9, 29),
        hour: 9,
        minute: 15,
      );
      final candidates = wallTimeCandidates(wall, 'Asia/Shanghai');
      expect(candidates, hasLength(1));
      expect(candidates.single.offset, const Duration(hours: 8));
      expect(
        resolveWallTime(wall, 'Asia/Shanghai'),
        DateTime.utc(2026, 9, 29, 1, 15).millisecondsSinceEpoch,
      );
      expect(
        () => ScheduleCivilDate(2026, 2, 30),
        throwsA(isA<ScheduleTimeException>()),
      );
      expect(
        () => ScheduleWallTime(
          ScheduleCivilDate(2026, 1, 1),
          hour: 24,
          minute: 0,
        ),
        throwsA(isA<ScheduleTimeException>()),
      );
    });

    test('spring gap rejects instead of rolling forward', () {
      final gap = ScheduleWallTime(
        ScheduleCivilDate(2026, 3, 8),
        hour: 2,
        minute: 30,
      );
      expect(wallTimeCandidates(gap, 'America/New_York'), isEmpty);
      expect(
        () => resolveWallTime(gap, 'America/New_York'),
        throwsA(
          isA<ScheduleTimeException>().having(
            (error) => error.reason,
            'reason',
            ScheduleTimeError.gap,
          ),
        ),
      );
    });

    test('fall fold lists both offsets and requires explicit selection', () {
      final fold = ScheduleWallTime(
        ScheduleCivilDate(2026, 11, 1),
        hour: 1,
        minute: 30,
      );
      final candidates = wallTimeCandidates(fold, 'America/New_York');
      expect(candidates, hasLength(2));
      expect(candidates.map((candidate) => candidate.offset), [
        const Duration(hours: -4),
        const Duration(hours: -5),
      ]);
      expect(
        candidates[1].instantMs - candidates[0].instantMs,
        const Duration(hours: 1).inMilliseconds,
      );
      expect(
        () => resolveWallTime(fold, 'America/New_York'),
        throwsA(
          isA<ScheduleTimeException>().having(
            (error) => error.reason,
            'reason',
            ScheduleTimeError.fold,
          ),
        ),
      );
      expect(
        resolveWallTime(
          fold,
          'America/New_York',
          offset: const Duration(hours: -5),
        ),
        candidates[1].instantMs,
      );
      expect(
        () => resolveWallTime(
          fold,
          'America/New_York',
          offset: const Duration(hours: -6),
        ),
        throwsA(isA<ScheduleTimeException>()),
      );
    });

    test('DST days have 23 and 25 actual hours', () {
      final spring = dayWindow(
        ScheduleCivilDate(2026, 3, 8),
        'America/New_York',
      );
      final fall = dayWindow(
        ScheduleCivilDate(2026, 11, 1),
        'America/New_York',
      );
      expect(
        spring.endAt - spring.startAt,
        const Duration(hours: 23).inMilliseconds,
      );
      expect(
        fall.endAt - fall.startAt,
        const Duration(hours: 25).inMilliseconds,
      );
    });

    test('midnight is half-open and cross-day clips retain one interval', () {
      final first = dayWindow(ScheduleCivilDate(2026, 9, 29), 'UTC');
      final next = dayWindow(ScheduleCivilDate(2026, 9, 30), 'UTC');
      expect(first.endAt, next.startAt);
      expect(
        clipToDay(
          first.startAt,
          first.endAt,
          ScheduleCivilDate(2026, 9, 30),
          'UTC',
        ),
        isNull,
      );
      final begins = first.endAt - 30 * Duration.millisecondsPerMinute;
      final ends = first.endAt + 30 * Duration.millisecondsPerMinute;
      final left = clipToDay(
        begins,
        ends,
        ScheduleCivilDate(2026, 9, 29),
        'UTC',
      )!;
      final right = clipToDay(
        begins,
        ends,
        ScheduleCivilDate(2026, 9, 30),
        'UTC',
      )!;
      expect(left.endAt, first.endAt);
      expect(left.continuesAfter, isTrue);
      expect(right.startAt, next.startAt);
      expect(right.continuesBefore, isTrue);
    });

    test('week starts Monday; cross-week interval clips on both sides', () {
      final week = weekWindow(ScheduleCivilDate(2026, 9, 30), 'UTC');
      expect(week.startAt, DateTime.utc(2026, 9, 28).millisecondsSinceEpoch);
      expect(week.endAt, DateTime.utc(2026, 10, 5).millisecondsSinceEpoch);
      final from = week.endAt - const Duration(hours: 1).inMilliseconds;
      final to = week.endAt + const Duration(hours: 1).inMilliseconds;
      final left = clipToWeek(from, to, ScheduleCivilDate(2026, 9, 30), 'UTC')!;
      final right = clipToWeek(
        from,
        to,
        ScheduleCivilDate(2026, 10, 5),
        'UTC',
      )!;
      expect(left.endAt, right.startAt);
      expect(left.continuesAfter, isTrue);
      expect(right.continuesBefore, isTrue);
    });

    test('display-zone switch changes day membership, not saved instants', () {
      final record = block(
        'zone-switch',
        from: DateTime.utc(2026, 9, 29, 23, 30).millisecondsSinceEpoch,
        to: DateTime.utc(2026, 9, 29, 23, 45).millisecondsSinceEpoch,
      );
      final before = record.toJson();
      expect(
        clipToDay(
          record.startAt,
          record.endAt,
          ScheduleCivilDate(2026, 9, 29),
          'UTC',
        ),
        isNotNull,
      );
      expect(
        clipToDay(
          record.startAt,
          record.endAt,
          ScheduleCivilDate(2026, 9, 30),
          'Asia/Shanghai',
        ),
        isNotNull,
      );
      expect(
        clipToDay(
          record.startAt,
          record.endAt,
          ScheduleCivilDate(2026, 9, 29),
          'Asia/Shanghai',
        ),
        isNull,
      );
      expect(record.toJson(), before);
    });
  });
}
