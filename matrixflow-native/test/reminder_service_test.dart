import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/services/desktop_shell_service.dart';
import 'package:matrixflow_native/services/reminder_service.dart';

void main() {
  group('ReminderService FNV-1a ID Generation', () {
    test('produces stable, positive 31-bit integer for task IDs', () {
      final id1 = generateNotificationId('task-123');
      final id2 = generateNotificationId('task-123');
      expect(id1, equals(id2));
      expect(id1, greaterThanOrEqualTo(0));
      expect(id1, lessThanOrEqualTo(0x7fffffff));
    });

    test('differentiates parent task and subtasks', () {
      final parentId = generateNotificationId('task-999');
      final subId1 = generateNotificationId('task-999', subtaskId: 'sub-1');
      final subId2 = generateNotificationId('task-999', subtaskId: 'sub-2');

      expect(parentId, isNot(equals(subId1)));
      expect(parentId, isNot(equals(subId2)));
      expect(subId1, isNot(equals(subId2)));
    });

    test('generates distinct IDs for varied task IDs', () {
      final ids = <int>{};
      for (var i = 0; i < 100; i++) {
        final id = generateNotificationId('task-batch-$i');
        expect(ids.contains(id), isFalse);
        ids.add(id);
      }
      expect(ids.length, equals(100));
    });
  });

  group('ReminderPayload Serialization', () {
    test('roundtrips valid payload JSON and string', () {
      const payload = ReminderPayload(
        boardId: 'board-1',
        taskId: 'task-1',
        subtaskId: 'sub-1',
      );

      final serialized = payload.serialize();
      final deserialized = ReminderPayload.deserialize(serialized);

      expect(deserialized, isNotNull);
      expect(deserialized!.boardId, equals('board-1'));
      expect(deserialized.taskId, equals('task-1'));
      expect(deserialized.subtaskId, equals('sub-1'));
      expect(deserialized, equals(payload));
    });

    test('handles null subtaskId gracefully', () {
      const payload = ReminderPayload(boardId: 'b', taskId: 't');
      final serialized = payload.serialize();
      final deserialized = ReminderPayload.deserialize(serialized);

      expect(deserialized, isNotNull);
      expect(deserialized!.subtaskId, isNull);
    });

    test('returns null on invalid or empty JSON string', () {
      expect(ReminderPayload.deserialize(null), isNull);
      expect(ReminderPayload.deserialize(''), isNull);
      expect(ReminderPayload.deserialize('not a json'), isNull);
      expect(ReminderPayload.deserialize('123'), isNull);
    });
  });

  group('InMemoryReminderService Scheduling and Suppression', () {
    late InMemoryReminderService service;

    setUp(() {
      service = InMemoryReminderService();
    });

    test('schedules future reminder and stores record', () async {
      final futureMs = DateTime.now().millisecondsSinceEpoch + 60000;
      await service.scheduleReminder(
        boardId: 'b1',
        taskId: 't1',
        title: 'Meeting',
        body: 'Prepare notes',
        triggerAtMs: futureMs,
      );

      final id = generateNotificationId('t1');
      expect(service.scheduled.containsKey(id), isTrue);
      expect(service.scheduled[id]!.title, equals('Meeting'));
      expect(service.scheduled[id]!.triggerAtMs, equals(futureMs));
    });

    test('suppresses past reminder older than 5 minutes', () async {
      final oldMs = DateTime.now().millisecondsSinceEpoch - 400000; // > 6 min ago
      await service.scheduleReminder(
        boardId: 'b1',
        taskId: 't_old',
        title: 'Old Task',
        triggerAtMs: oldMs,
      );

      final id = generateNotificationId('t_old');
      expect(service.scheduled.containsKey(id), isFalse);
    });

    test('cancels single reminder and tracks cancellation', () async {
      final futureMs = DateTime.now().millisecondsSinceEpoch + 60000;
      await service.scheduleReminder(
        boardId: 'b1',
        taskId: 't2',
        title: 'Review',
        triggerAtMs: futureMs,
      );

      final id = generateNotificationId('t2');
      expect(service.scheduled.containsKey(id), isTrue);

      await service.cancelReminder('t2');
      expect(service.scheduled.containsKey(id), isFalse);
      expect(service.cancelledIds.contains(id), isTrue);
    });

    test('cancelAllForBoard cancels parent and subtask reminders', () async {
      final futureMs = DateTime.now().millisecondsSinceEpoch + 60000;
      final task1 = Task(
        id: 't1',
        boardId: 'b1',
        title: 'Task 1',
        quadrant: 1,
        createdAt: 0,
        reminderAt: futureMs,
        subtasks: [
          SubTask(id: 's1', title: 'Sub 1', reminderAt: futureMs),
          SubTask(id: 's2', title: 'Sub 2'), // no reminder
        ],
      );

      await service.scheduleReminder(
        boardId: 'b1',
        taskId: 't1',
        title: 'Task 1',
        triggerAtMs: futureMs,
      );
      await service.scheduleReminder(
        boardId: 'b1',
        taskId: 't1',
        subtaskId: 's1',
        title: 'Sub 1',
        triggerAtMs: futureMs,
      );
      await service.scheduleReminder(
        boardId: 'b2',
        taskId: 't2',
        title: 'Task 2',
        triggerAtMs: futureMs,
      );

      expect(service.scheduled.length, equals(3));

      await service.cancelAllForBoard('b1', [task1]);

      // b1 parent and subtask should be removed; b2 stays
      expect(service.scheduled.containsKey(generateNotificationId('t1')), isFalse);
      expect(service.scheduled.containsKey(generateNotificationId('t1', subtaskId: 's1')), isFalse);
      expect(service.scheduled.containsKey(generateNotificationId('t2')), isTrue);
    });

    test('rescheduleAllFuture reschedules future uncompleted tasks and skips completed or past', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final futureMs = now + 120000;
      final pastMs = now - 600000;

      final tasks = [
        Task(
          id: 'active_future',
          boardId: 'b1',
          title: 'Future active',
          quadrant: 1,
          createdAt: 0,
          reminderAt: futureMs,
        ),
        Task(
          id: 'completed_task',
          boardId: 'b1',
          title: 'Completed',
          completed: true,
          quadrant: 1,
          createdAt: 0,
          reminderAt: futureMs,
        ),
        Task(
          id: 'past_task',
          boardId: 'b1',
          title: 'Past',
          quadrant: 1,
          createdAt: 0,
          reminderAt: pastMs,
        ),
        Task(
          id: 'with_sub',
          boardId: 'b1',
          title: 'Parent with sub',
          quadrant: 1,
          createdAt: 0,
          subtasks: [
            SubTask(id: 'sub_future', title: 'Sub Future', reminderAt: futureMs),
            SubTask(id: 'sub_done', title: 'Sub Done', completed: true, reminderAt: futureMs),
          ],
        ),
      ];

      await service.rescheduleAllFuture(tasks);

      expect(service.scheduled.containsKey(generateNotificationId('active_future')), isTrue);
      expect(service.scheduled.containsKey(generateNotificationId('completed_task')), isFalse);
      expect(service.scheduled.containsKey(generateNotificationId('past_task')), isFalse);
      expect(service.scheduled.containsKey(generateNotificationId('with_sub', subtaskId: 'sub_future')), isTrue);
      expect(service.scheduled.containsKey(generateNotificationId('with_sub', subtaskId: 'sub_done')), isFalse);
    });
  });

  group('WP25-N-Windows Desktop Platform Integration', () {
    test('checkPermission and requestPermission on Windows returns granted and true', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() {
        debugDefaultTargetPlatformOverride = null;
      });

      final service = FlutterLocalNotificationsReminderService();
      final status = await service.checkPermission();
      expect(status, equals(ReminderPermissionStatus.granted));

      final requested = await service.requestPermission();
      expect(requested, isTrue);
    });

    test('DesktopShellService window restoration coordinates with notification tap', () {
      DesktopShellService.debugIsDesktopOverride = true;
      addTearDown(() {
        DesktopShellService.debugIsDesktopOverride = null;
      });

      bool showWindowCalled = false;
      DesktopShellService.instance.onShowWindow = () {
        showWindowCalled = true;
      };

      DesktopShellService.instance.hideWindowToTray();
      expect(DesktopShellService.instance.isWindowVisible, isFalse);

      DesktopShellService.instance.restoreWindow();
      expect(DesktopShellService.instance.isWindowVisible, isTrue);
      expect(showWindowCalled, isTrue);
    });

    test('WindowsNotificationDetails configuration and duration', () {
      const details = WindowsNotificationDetails(
        subtitle: 'Subtask notes',
        duration: WindowsNotificationDuration.long,
      );
      expect(details.subtitle, equals('Subtask notes'));
      expect(details.duration, equals(WindowsNotificationDuration.long));
    });
  });
}
