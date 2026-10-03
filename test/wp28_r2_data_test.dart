import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/schedule_item.dart';
import 'package:matrixflow_native/schedule_time.dart';
import 'package:matrixflow_native/screenshot_import/screenshot_submission.dart';
import 'package:matrixflow_native/services/windows_upgrade_validation_fixture.dart';
import 'package:matrixflow_native/storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<Store> open({bool schedule = true, SaveWrite? writer}) async {
    SharedPreferences.setMockInitialValues({
      for (final entry in r2SyntheticValues(schedule: schedule).entries)
        entry.key: entry.key == 'matrixflow-has-seen-onboarding'
            ? entry.value == 'true'
            : entry.value,
    });
    final store = Store(
      reminders: NoopReminderService(),
      credentialStore: R2SeedCredentials(),
      saveWriter: writer,
    );
    await store.init();
    expect((await store.flush()).success, isTrue);
    addTearDown(store.dispose);
    return store;
  }

  test(
    'rich seed retains every task field, three boards and empty board',
    () async {
      final store = await open();
      expect(r2Library(store), r2LibraryFromValues(r2SyntheticValues()));
      expect(store.tasks.first.notesMarkdown, r2LongNote);
      expect(store.tasks.first.notesMarkdown!.length, greaterThan(8000));
      expect(store.tasks.first.subtasks.first.completed, isTrue);
      expect(store.tasks.last.completedAt, 1790813000000);
      expect(store.boards, hasLength(3));
      validateScheduleCollection(
        store.scheduleItems,
        parentTaskIds: store.tasks.map((task) => task.id).toSet(),
        boardIds: store.boards.map((board) => board.id).toSet(),
      );
    },
  );

  test(
    'cross-day, gap, fold and overlapping records keep absolute times',
    () async {
      final store = await open();
      tz.TZDateTime local(ScheduleItem item, int instant) =>
          tz.TZDateTime.fromMillisecondsSinceEpoch(
            scheduleLocation(item.timeZoneId),
            instant,
          );
      final crossDay = store.scheduleItems.first;
      expect(local(crossDay, crossDay.startAt).day, 1);
      expect(local(crossDay, crossDay.endAt).day, 2);
      expect(
        overlappingScheduleItems(
          store.scheduleItems,
          crossDay,
        ).map((s) => s.id),
        contains('synthetic-linked-event'),
      );
      final gap = store.scheduleItems[2], fold = store.scheduleItems[3];
      expect(local(gap, gap.startAt).hour, 1);
      expect(local(gap, gap.endAt).hour, 3);
      expect(gap.endAt - gap.startAt, 3600000);
      expect(local(fold, fold.startAt).hour, 1);
      expect(local(fold, fold.endAt).hour, 1);
      expect(local(fold, fold.startAt).timeZoneOffset.inMinutes, -240);
      expect(local(fold, fold.endAt).timeZoneOffset.inMinutes, -300);
      expect(fold.endAt - fold.startAt, 3600000);
    },
  );

  test(
    'public submission pointer failure keeps committed state; retry keeps ids and literal dates',
    () async {
      var fail = false, allocated = 0;
      final store = await open(
        writer: (key, value) async {
          if (fail && key == SaveProtocol.pointerKey) return false;
          return (await SharedPreferences.getInstance()).setString(key, value);
        },
      );
      final before = r2Library(store);
      final prefs = await SharedPreferences.getInstance();
      final committed = SaveProtocol(prefs).load()!;
      final batch = r2ScreenshotBatch('synthetic-second-board');
      final submission = ScreenshotSubmission(
        batch,
        idFactory: () => 'r2-${allocated++}',
      );
      final confirmed = batch.snapshot();
      fail = true;
      await expectLater(submission.commit(store, confirmed), throwsStateError);
      expect(r2Library(store), before);
      expect(SaveProtocol(prefs).load()!.values, committed.values);
      expect(SaveProtocol(prefs).load()!.revision, committed.revision);
      fail = false;
      await submission.commit(store, confirmed);
      await submission.commit(store, confirmed);
      expect(allocated, 2);
      final task = store.tasks.singleWhere((task) => task.id == 'r2-0');
      expect(task.subtasks.single.id, 'r2-1');
      expect(task.notesMarkdown, r2DateNotes);
      expect(task.subtasks.single.notesMarkdown, r2ChildDateNotes);
      expect([
        task.deadline,
        task.plannedDate,
        task.reminderAt,
        task.subtasks.single.deadline,
        task.subtasks.single.reminderAt,
      ], everyElement(isNull));
      expect(task.subtasks.single.completed, isTrue);
      expect(jsonEncode(task.toJson()), isNot(contains('synthetic-image')));
      expect(
        store.scheduleItems.map((s) => s.toJson()).toList(),
        before['schedule'],
      );
    },
  );

  test('v3 backup restores all fields after screenshot merge', () async {
    final store = await open();
    final batch = r2ScreenshotBatch('synthetic-second-board');
    var id = 0;
    await ScreenshotSubmission(
      batch,
      idFactory: () => 'r2-${id++}',
    ).commit(store, batch.snapshot());
    final before = r2Library(store);
    final backup = ImportPreflight.decode(utf8.encode(store.exportJson()));
    store.clearBoard('synthetic-board');
    expect(
      (await store.applyImport(
        store.previewImport(backup, 'overwrite'),
      )).success,
      isTrue,
    );
    // Active-board/onboarding are local fields outside the backup schema.
    for (final field in ['tasks', 'boards', 'schedule', 'config', 'settings']) {
      expect(r2Library(store)[field], before[field], reason: field);
    }
  });

  for (final version in [1, 2]) {
    test(
      'v$version import remains valid and downgrade requires explicit schedule loss',
      () async {
        final store = await open();
        expect(
          () => store.exportJson(version: version),
          throwsA(
            isA<ScheduleExportLossException>().having(
              (e) => e.lostScheduleItems,
              'lost records',
              4,
            ),
          ),
        );
        final result = store.exportJsonResult(
          version: version,
          allowScheduleLoss: true,
        );
        expect(result.lostScheduleItems, 4);
        final backup = ImportPreflight.decode(utf8.encode(result.json));
        expect(backup.containsKey('scheduleItems'), isFalse);
        final expected = (backup['tasks'] as List)
            .map((task) => Task.fromJson(task).toJson())
            .toList();
        expect(
          (await store.applyImport(
            store.previewImport(backup, 'overwrite'),
          )).success,
          isTrue,
        );
        expect(store.tasks.map((t) => t.toJson()).toList(), expected);
        expect(store.scheduleItems, isEmpty);
      },
    );
  }

  test(
    'legacy missing schedule retains dates without creating records',
    () async {
      final store = await open(schedule: false);
      expect(store.scheduleItems, isEmpty);
      expect(store.tasks.first.plannedDate, 1790812800000);
      final prefs = await SharedPreferences.getInstance();
      expect(
        SaveProtocol(prefs).load()!.values[SaveProtocol.scheduleKey],
        '[]',
      );
    },
  );
}
