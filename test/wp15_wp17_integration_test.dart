import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/import_preview/draft_model.dart';
import 'package:matrixflow_native/planner/schedule_edit_session.dart';
import 'package:matrixflow_native/schedule_item.dart';
import 'package:matrixflow_native/schedule_time.dart';
import 'package:matrixflow_native/screens/settings_backup_messages.dart';
import 'package:matrixflow_native/screenshot_import/screenshot_submission.dart';
import 'package:matrixflow_native/storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'screenshot merge, Planner edit and v3 backup preserve one library',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = Store();
      await store.init();
      await store.flush(waitForReminders: false);
      addTearDown(() async {
        await store.flush(waitForReminders: false);
        store.dispose();
      });

      final board = store.boards.first.id;
      final start = DateTime.utc(2026, 10, 1, 1).millisecondsSinceEpoch;
      final oldEvent = ScheduleItem.event(
        id: 'existing-event',
        title: 'Existing meeting',
        boardId: board,
        startAt: start,
        endAt: start + const Duration(hours: 1).inMilliseconds,
        timeZoneId: 'Asia/Shanghai',
      );
      store.addScheduleItem(oldEvent);
      await store.flush(waitForReminders: false);
      final oldRevision = store.scheduleRevision(oldEvent.id);

      final root = DraftTask(
        id: 'draft-root',
        imageId: 'image-1',
        sourceRow: 0,
        title: 'Imported work',
        checked: false,
      )..confirmed = true;
      final child = DraftTask(
        id: 'draft-child',
        imageId: 'image-1',
        sourceRow: 1,
        title: 'Already done',
        checked: true,
        parentId: root.id,
      )..confirmed = true;
      final draft =
          DraftBatch(
              images: [
                DraftImage(id: 'image-1', tasks: [root, child]),
              ],
            )
            ..boardId = board
            ..quadrant = 2;
      final submission = ScreenshotSubmission(draft);
      await submission.commit(store, draft.snapshot());
      expect(store.scheduleItems.single.toJson(), oldEvent.toJson());
      expect(store.scheduleRevision(oldEvent.id), oldRevision);
      final imported = store.tasks.single;
      expect(imported.subtasks.single.completed, isTrue);
      expect(imported.completed, isFalse);
      expect(imported.plannedDate, isNull);
      expect(imported.deadline, isNull);
      expect(imported.reminderAt, isNull);

      final editor =
          ScheduleEditSession.create(
              store,
              ScheduleItemKind.timeBlock,
              'Asia/Shanghai',
              ScheduleCivilDate(2026, 10, 1),
            )
            ..taskId = imported.id
            ..start.time = '11:00'
            ..end.time = '12:00';
      expect(await editor.submit(editor.review()), ScheduleSubmitResult.saved);
      final beforeTasks = jsonEncode(
        store.tasks.map((task) => task.toJson()).toList(),
      );
      final beforeSchedule = jsonEncode(
        store.scheduleItems.map((item) => item.toJson()).toList(),
      );
      final backup = jsonDecode(store.exportJson()) as Map<String, dynamic>;
      expect(backup['version'], 3);
      expect(backup['scheduleItems'], hasLength(2));

      // Overwrite preview uses B2's summary adapter, then restores both collections.
      store.clearBoard(board);
      expect(store.tasks, isEmpty);
      // Clearing tasks keeps a board's independent events; linked blocks go.
      expect(store.scheduleItems.single.toJson(), oldEvent.toJson());
      store.deleteScheduleItem(
        oldEvent.id,
        expectedRevision: store.scheduleRevision(oldEvent.id),
      );
      expect(store.scheduleItems, isEmpty);
      await store.flush(waitForReminders: false);
      final plan = store.previewImport(backup, 'overwrite');
      expect(plan.conflicts, 0);
      expect(plan.addedScheduleItems, 2);
      expect(
        backupImportSummary(store.t, plan),
        contains('${store.t['importScheduleAdded']}: 2'),
      );
      expect((await store.applyImport(plan)).success, isTrue);
      expect(
        jsonEncode(store.tasks.map((task) => task.toJson()).toList()),
        beforeTasks,
      );
      expect(
        jsonEncode(store.scheduleItems.map((item) => item.toJson()).toList()),
        beforeSchedule,
      );
      expect(
        store.scheduleItems.where((item) => item.taskId == imported.id),
        hasLength(1),
      );
    },
  );
}
