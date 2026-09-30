import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/planner/schedule_edit_session.dart';
import 'package:matrixflow_native/schedule_item.dart';
import 'package:matrixflow_native/schedule_time.dart';
import 'package:matrixflow_native/storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'wp15_c2_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final delete in [false, true]) {
    test(
      '${delete ? 'delete' : 'edit'} flush failure retries without replaying the command',
      () async {
        var fail = false;
        final store = await c2Store(
          items: [c1Items().first],
          writer: (key, value) async {
            if (fail && key == SaveProtocol.pointerKey) return false;
            return (await SharedPreferences.getInstance()).setString(
              key,
              value,
            );
          },
        );
        final s = ScheduleEditSession.edit(store, store.scheduleItems.single);
        s.start.time = '00:45';
        fail = true;
        expect(
          await (delete ? s.delete() : s.submit(s.review())),
          ScheduleSubmitResult.unsaved,
        );
        final revision = store.scheduleRevision(s.id);
        fail = false;
        expect(await s.retry(), ScheduleSubmitResult.saved);
        expect(store.scheduleRevision(s.id), revision);
        expect(store.scheduleItems.length, delete ? 0 : 1);
        await store.flush(waitForReminders: false);
        store.dispose();
      },
    );
  }
  Future<void> finish(Store store) async {
    await store.flush(waitForReminders: false);
    store.dispose();
  }

  ScheduleEditSession create(Store store) =>
      ScheduleEditSession.create(
          store,
          ScheduleItemKind.event,
          c1Zone,
          ScheduleCivilDate(2026, 9, 30),
        )
        ..title = 'New'
        ..boardId = 'home'
        ..start.time = '10:00'
        ..end.time = '11:00';

  test(
    'new input has no assumed start/end time or association and cancellation writes nothing',
    () async {
      final store = await c2Store();
      final before = c2Library(store);
      final s = ScheduleEditSession.create(
        store,
        ScheduleItemKind.timeBlock,
        c1Zone,
        ScheduleCivilDate(2026, 9, 30),
      );
      expect(s.start.time, isEmpty);
      expect(s.end.time, isEmpty);
      expect(s.taskId, isNull);
      expect(s.review, throwsA(isA<ScheduleTimeException>()));
      expect(c2Library(store), before);
      await finish(store);
    },
  );

  test(
    'review and save create only a schedule record with explicit parent or board',
    () async {
      final store = await c2Store(items: []);
      final tasks = jsonEncode(store.tasks.map((t) => t.toJson()).toList());
      final s = create(store);
      expect(store.scheduleItems, isEmpty);
      expect(await s.submit(s.review()), ScheduleSubmitResult.saved);
      final block =
          ScheduleEditSession.create(
              store,
              ScheduleItemKind.timeBlock,
              c1Zone,
              ScheduleCivilDate(2026, 9, 30),
            )
            ..taskId = 'outline'
            ..start.time = '12:00'
            ..end.time = '13:00';
      expect(await block.submit(block.review()), ScheduleSubmitResult.saved);
      expect(store.scheduleItems, hasLength(2));
      expect(jsonEncode(store.tasks.map((t) => t.toJson()).toList()), tasks);
      final orphan = create(store)
        ..taskId = 'not-a-parent'
        ..boardId = null;
      expect(orphan.review, throwsFormatException);
      await finish(store);
    },
  );

  test(
    'editing restores original zone, both fold offsets and exact subsecond endpoints; same values are a no-op',
    () async {
      const zone = 'America/New_York';
      final date = ScheduleCivilDate(2026, 11, 1);
      final fold = wallTimeCandidates(
        ScheduleWallTime(
          date,
          hour: 1,
          minute: 15,
          second: 12,
          millisecond: 345,
        ),
        zone,
      );
      final item = c1Event(
        'fold',
        fold[0].instantMs,
        fold[1].instantMs,
        zone: zone,
      );
      final store = await c2Store(items: [item]);
      final before = c2Library(store);
      final s = ScheduleEditSession.edit(store, item);
      expect(s.timeZoneId, zone);
      expect(s.start.offset, const Duration(hours: -4));
      expect(s.end.offset, const Duration(hours: -5));
      expect(s.start.time, '01:15:12.345');
      expect(s.review().item.toJson(), item.toJson());
      expect(await s.submit(s.review()), ScheduleSubmitResult.saved);
      expect(c2Library(store), before);
      await finish(store);
    },
  );

  test(
    'gap rejects; fold requires chosen offset for each edited endpoint',
    () async {
      final store = await c2Store(items: []);
      final s = create(store)
        ..timeZoneId = 'America/New_York'
        ..start.date = '2026-03-08'
        ..start.time = '02:30'
        ..end.date = '2026-03-08'
        ..end.time = '04:00';
      expect(
        s.review,
        throwsA(
          isA<ScheduleTimeException>().having(
            (e) => e.reason,
            'reason',
            ScheduleTimeError.gap,
          ),
        ),
      );
      s.start
        ..date = '2026-11-01'
        ..time = '01:15';
      s.end
        ..date = '2026-11-01'
        ..time = '01:45';
      expect(
        s.review,
        throwsA(
          isA<ScheduleTimeException>().having(
            (e) => e.reason,
            'reason',
            ScheduleTimeError.fold,
          ),
        ),
      );
      s.start.offset = const Duration(hours: -4);
      expect(s.review, throwsA(isA<ScheduleTimeException>()));
      s.end.offset = const Duration(hours: -5);
      expect(
        s.review().item.endAt - s.review().item.startAt,
        90 * Duration.millisecondsPerMinute,
      );
      expect(await s.submit(s.review()), ScheduleSubmitResult.saved);
      await finish(store);
    },
  );

  test(
    'unknown zones, invalid dates, reversed or zero intervals reject without writes',
    () async {
      final store = await c2Store(items: []);
      final s = create(store);
      s.timeZoneId = 'CST';
      expect(s.review, throwsA(isA<ScheduleTimeException>()));
      s.timeZoneId = c1Zone;
      s.start.date = '2026-02-30';
      expect(s.review, throwsA(isA<ScheduleTimeException>()));
      s.start.date = '2026-09-30';
      s.end.time = '10:00';
      expect(s.review, throwsFormatException);
      s.end.time = '09:59';
      expect(s.review, throwsFormatException);
      expect(store.scheduleItems, isEmpty);
      await finish(store);
    },
  );

  test(
    'cross-day and cross-week intervals have no added span limit; overlap confirmation is required',
    () async {
      final store = await c2Store();
      final s = create(store)
        ..start.date = '2026-09-27'
        ..start.time = '23:00'
        ..end.date = '2026-10-06'
        ..end.time = '00:00';
      final review = s.review();
      expect(review.overlaps, hasLength(4));
      final before = c2Library(store);
      expect(await s.submit(review), ScheduleSubmitResult.reviewChanged);
      expect(c2Library(store), before);
      expect(
        await s.submit(review, allowOverlap: true),
        ScheduleSubmitResult.saved,
      );
      expect(store.scheduleItems, hasLength(5));
      await finish(store);
    },
  );

  test(
    'overlap changes after review require a fresh review and never silently save',
    () async {
      final store = await c2Store(items: []);
      final s = create(store);
      final review = s.review();
      store.addScheduleItem(c1Event('external', c1At(30, 10), c1At(30, 11)));
      expect(
        await s.submit(review, allowOverlap: true),
        ScheduleSubmitResult.reviewChanged,
      );
      expect(store.scheduleItems.single.id, 'external');
      expect(
        await s.submit(s.review(), allowOverlap: true),
        ScheduleSubmitResult.saved,
      );
      await finish(store);
    },
  );

  test(
    'external edit or deletion makes captured revision stale for edit and delete',
    () async {
      final store = await c2Store();
      final item = store.scheduleItems.first;
      final s = ScheduleEditSession.edit(store, item);
      final review = s.review();
      store.updateScheduleItem(
        ScheduleItem.fromJson({...item.toJson(), 'startAt': item.startAt + 1}),
        expectedRevision: store.scheduleRevision(item.id),
      );
      expect(
        await s.submit(review, allowOverlap: true),
        ScheduleSubmitResult.stale,
      );
      expect(await s.delete(), ScheduleSubmitResult.stale);
      final deleted = ScheduleEditSession.edit(
        store,
        store.scheduleItems.first,
      );
      store.deleteScheduleItem(
        item.id,
        expectedRevision: store.scheduleRevision(item.id),
      );
      expect(await deleted.delete(), ScheduleSubmitResult.stale);
      await finish(store);
    },
  );

  test(
    'delete confirmation command deletes only the selected id and not task or overlaps',
    () async {
      final store = await c2Store();
      final tasks = jsonEncode(store.tasks.map((t) => t.toJson()).toList());
      final s = ScheduleEditSession.edit(store, store.scheduleItems.first);
      expect(await s.delete(), ScheduleSubmitResult.saved);
      expect(store.scheduleItems.map((i) => i.id), [
        'linked',
        'independent',
        'done',
      ]);
      expect(jsonEncode(store.tasks.map((t) => t.toJson()).toList()), tasks);
      await finish(store);
    },
  );

  test(
    'moving across DST preserves actual milliseconds and association; edge resize preserves the other endpoint',
    () async {
      final start = DateTime.utc(2026, 3, 8, 6, 30).millisecondsSinceEpoch;
      final item = c1Event(
        'move',
        start,
        start + 2 * Duration.millisecondsPerHour,
        taskId: 'outline',
        zone: 'America/New_York',
      );
      final store = await c2Store(items: [item]);
      final move = ScheduleEditSession.edit(
        store,
        item,
        mode: ScheduleEditMode.move,
        displayZone: 'America/New_York',
        target: ScheduleWallTime(
          ScheduleCivilDate(2026, 11, 1),
          hour: 1,
          minute: 30,
        ),
      );
      expect(move.start.offset, isNull);
      expect(move.review, throwsA(isA<ScheduleTimeException>()));
      move.start.offset = const Duration(hours: -5);
      move.title = 'ignored';
      move.taskId = 'done';
      final moved = move.review().item;
      expect(moved.endAt - moved.startAt, item.endAt - item.startAt);
      expect(moved.taskId, 'outline');
      expect(moved.title, item.title);
      expect(await move.submit(move.review()), ScheduleSubmitResult.saved);
      final resize = ScheduleEditSession.edit(
        store,
        moved,
        mode: ScheduleEditMode.resizeStart,
        displayZone: c1Zone,
      );
      resize.start.time = '15:00';
      resize.start.offset = null;
      expect(resize.review().item.endAt, moved.endAt);
      final end = ScheduleEditSession.edit(
        store,
        moved,
        mode: ScheduleEditMode.resizeEnd,
        displayZone: c1Zone,
      );
      end.end.time = '18:00';
      end.end.offset = null;
      expect(end.review().item.startAt, moved.startAt);
      await finish(store);
    },
  );

  test(
    'failed flush retains a pending change; retry does not replay mutation or increase schedule revision',
    () async {
      var fail = false;
      final store = await c2Store(
        items: [],
        writer: (key, value) async {
          if (fail && key == SaveProtocol.pointerKey) return false;
          return (await SharedPreferences.getInstance()).setString(key, value);
        },
      );
      fail = true;
      final s = create(store);
      expect(await s.submit(s.review()), ScheduleSubmitResult.unsaved);
      final revision = store.scheduleRevision(s.id);
      expect(await s.submit(s.review()), ScheduleSubmitResult.busy);
      fail = false;
      expect(await s.retry(), ScheduleSubmitResult.saved);
      expect(store.scheduleRevision(s.id), revision);
      expect(store.scheduleItems, hasLength(1));
      await finish(store);
    },
  );

  test(
    'pending save blocks duplicate commands and detects changes during flush',
    () async {
      final gate = Completer<void>();
      var hold = false;
      final store = await c2Store(
        items: [],
        writer: (key, value) async {
          if (hold && key == SaveProtocol.pointerKey) await gate.future;
          return (await SharedPreferences.getInstance()).setString(key, value);
        },
      );
      hold = true;
      final s = create(store);
      final review = s.review();
      final pending = s.submit(review);
      expect(await s.submit(review), ScheduleSubmitResult.busy);
      store.deleteScheduleItem(
        s.id,
        expectedRevision: store.scheduleRevision(s.id),
      );
      gate.complete();
      expect(await pending, ScheduleSubmitResult.stale);
      expect(await s.retry(), ScheduleSubmitResult.stale);
      await finish(store);
    },
  );

  test('startup recovery blocks submit and delete', () async {
    final store = await c2Store(recovery: true);
    final s = create(store);
    expect(await s.submit(s.review()), ScheduleSubmitResult.recovery);
    expect(await s.delete(), ScheduleSubmitResult.recovery);
    expect(store.scheduleItems, isEmpty);
    store.dispose();
  });
}
