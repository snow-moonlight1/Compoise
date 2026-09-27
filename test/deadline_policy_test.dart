import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/screens/settings_screen.dart';
import 'package:matrixflow_native/storage.dart';
import 'package:matrixflow_native/widgets/task_detail_panel.dart';
import 'package:provider/provider.dart';

import 'helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('calendarDaysLeft algorithm', () {
    test('same day returns 0 regardless of time-of-day offsets', () {
      final now = DateTime(2026, 9, 15, 8, 30, 0);
      final deadlineMorning = DateTime(2026, 9, 15, 9, 0, 0).millisecondsSinceEpoch;
      final deadlineNight = DateTime(2026, 9, 15, 23, 59, 59).millisecondsSinceEpoch;
      expect(calendarDaysLeft(deadlineMorning, now: now), 0);
      expect(calendarDaysLeft(deadlineNight, now: now), 0);
    });

    test('tomorrow returns 1, yesterday returns -1', () {
      final now = DateTime(2026, 9, 15, 14, 0, 0);
      final tomorrow = DateTime(2026, 9, 16, 0, 1, 0).millisecondsSinceEpoch;
      final yesterday = DateTime(2026, 9, 14, 23, 59, 0).millisecondsSinceEpoch;
      expect(calendarDaysLeft(tomorrow, now: now), 1);
      expect(calendarDaysLeft(yesterday, now: now), -1);
    });

    test('cross-month and cross-year transitions', () {
      final endOfSep = DateTime(2026, 9, 30, 22, 0, 0);
      final startOfOct = DateTime(2026, 10, 1, 6, 0, 0).millisecondsSinceEpoch;
      expect(calendarDaysLeft(startOfOct, now: endOfSep), 1);

      final endOfYear = DateTime(2026, 12, 31, 23, 0, 0);
      final newYear = DateTime(2027, 1, 1, 1, 0, 0).millisecondsSinceEpoch;
      expect(calendarDaysLeft(newYear, now: endOfYear), 1);
    });

    test('leap year handles Feb 29 accurately', () {
      final feb28 = DateTime(2028, 2, 28, 12, 0, 0);
      final mar1 = DateTime(2028, 3, 1, 12, 0, 0).millisecondsSinceEpoch;
      expect(calendarDaysLeft(mar1, now: feb28), 2);
    });

    test('immune to DST clock shift discrepancies', () {
      final beforeShift = DateTime(2026, 3, 28, 10, 0, 0);
      final afterShift = DateTime(2026, 3, 29, 10, 0, 0).millisecondsSinceEpoch;
      expect(calendarDaysLeft(afterShift, now: beforeShift), 1);
    });
  });

  group('isDeadlineUrgent policy', () {
    final now = DateTime(2026, 9, 15, 10, 0, 0);
    const threshold = 3;

    test('null deadline is never urgent', () {
      expect(isDeadlineUrgent(null, threshold, now: now), isFalse);
    });

    test('overdue and today are urgent', () {
      final overdue = DateTime(2026, 9, 13, 10, 0, 0).millisecondsSinceEpoch;
      final today = DateTime(2026, 9, 15, 18, 0, 0).millisecondsSinceEpoch;
      expect(isDeadlineUrgent(overdue, threshold, now: now), isTrue);
      expect(isDeadlineUrgent(today, threshold, now: now), isTrue);
    });

    test('inclusive of threshold days (0..N are urgent, N+1 is not)', () {
      final day1 = DateTime(2026, 9, 16, 10, 0, 0).millisecondsSinceEpoch;
      final day2 = DateTime(2026, 9, 17, 10, 0, 0).millisecondsSinceEpoch;
      final day3 = DateTime(2026, 9, 18, 10, 0, 0).millisecondsSinceEpoch;
      final day4 = DateTime(2026, 9, 19, 10, 0, 0).millisecondsSinceEpoch;

      expect(isDeadlineUrgent(day1, threshold, now: now), isTrue);
      expect(isDeadlineUrgent(day2, threshold, now: now), isTrue);
      expect(isDeadlineUrgent(day3, threshold, now: now), isTrue);
      expect(isDeadlineUrgent(day4, threshold, now: now), isFalse);
    });
  });

  group('quadrant helpers', () {
    test('isUrgentQuadrant and isImportantQuadrant identification', () {
      expect(isUrgentQuadrant(qDo), isTrue); // Q1
      expect(isUrgentQuadrant(qPlan), isFalse); // Q2
      expect(isUrgentQuadrant(qDelegate), isTrue); // Q3
      expect(isUrgentQuadrant(qEliminate), isFalse); // Q4

      expect(isImportantQuadrant(qDo), isTrue); // Q1
      expect(isImportantQuadrant(qPlan), isTrue); // Q2
      expect(isImportantQuadrant(qDelegate), isFalse); // Q3
      expect(isImportantQuadrant(qEliminate), isFalse); // Q4
    });

    test('promoteToUrgent preserves importance', () {
      expect(promoteToUrgent(qPlan), qDo); // Q2 -> Q1
      expect(promoteToUrgent(qEliminate), qDelegate); // Q4 -> Q3
      expect(promoteToUrgent(qDo), qDo); // Q1 stays Q1
      expect(promoteToUrgent(qDelegate), qDelegate); // Q3 stays Q3
    });
  });

  group('Store deadline promotion & UrgencyMode policy', () {
    late Store store;
    const boardId = 'b-test';
    final now = DateTime(2026, 9, 15, 10, 0, 0);

    setUp(() async {
      final res = await makeStore(
        boards: [Board(id: boardId, name: 'Test Board', createdAt: 1000)],
      );
      store = res.$1;
    });

    tearDown(() {
      store.dispose();
    });

    test('auto promotes Q2->Q1 and Q4->Q3 for uncompleted tasks within threshold', () {
      // addTasks promotes using the real clock before the explicit policy pass.
      final now = DateTime.now();
      final taskQ2 = Task(
        id: 't-q2',
        boardId: boardId,
        title: 'Q2 due in 2 days',
        quadrant: qPlan,
        createdAt: now.millisecondsSinceEpoch,
        deadline: DateTime(now.year, now.month, now.day + 2, 18).millisecondsSinceEpoch, // 2 days away <= 3
        urgencyMode: UrgencyMode.auto,
      );
      final taskQ4 = Task(
        id: 't-q4',
        boardId: boardId,
        title: 'Q4 due today',
        quadrant: qEliminate,
        createdAt: now.millisecondsSinceEpoch,
        deadline: DateTime(now.year, now.month, now.day + 0, 18).millisecondsSinceEpoch, // 0 days away
        urgencyMode: UrgencyMode.auto,
      );
      final taskQ2Far = Task(
        id: 't-q2-far',
        boardId: boardId,
        title: 'Q2 due in 5 days',
        quadrant: qPlan,
        createdAt: now.millisecondsSinceEpoch,
        deadline: DateTime(now.year, now.month, now.day + 5, 18).millisecondsSinceEpoch, // 5 days > 3
        urgencyMode: UrgencyMode.auto,
      );

      store.addTasks([taskQ2, taskQ4, taskQ2Far]);
      store.promoteDeadlinesNow(now: now);

      expect(store.tasks.firstWhere((t) => t.id == 't-q2').quadrant, qDo);
      expect(store.tasks.firstWhere((t) => t.id == 't-q4').quadrant, qDelegate);
      expect(store.tasks.firstWhere((t) => t.id == 't-q2-far').quadrant, qPlan);
    });

    test('does NOT promote completed tasks or tasks without deadlines', () {
      final completedTask = Task(
        id: 't-completed',
        boardId: boardId,
        title: 'Completed in Q2',
        quadrant: qPlan,
        completed: true,
        createdAt: now.millisecondsSinceEpoch,
        deadline: DateTime(2026, 9, 15, 12, 0, 0).millisecondsSinceEpoch,
        urgencyMode: UrgencyMode.auto,
      );
      final noDateTask = Task(
        id: 't-nodate',
        boardId: boardId,
        title: 'No date in Q2',
        quadrant: qPlan,
        createdAt: now.millisecondsSinceEpoch,
        deadline: null,
        urgencyMode: UrgencyMode.auto,
      );

      store.addTasks([completedTask, noDateTask]);
      store.promoteDeadlinesNow(now: now);

      expect(store.tasks.firstWhere((t) => t.id == 't-completed').quadrant, qPlan);
      expect(store.tasks.firstWhere((t) => t.id == 't-nodate').quadrant, qPlan);
    });

    test('does NOT demote tasks from Q1 or Q3 if deadline is far away', () {
      final taskQ1 = Task(
        id: 't-q1',
        boardId: boardId,
        title: 'Q1 due next week',
        quadrant: qDo,
        createdAt: now.millisecondsSinceEpoch,
        deadline: DateTime(2026, 9, 25, 12, 0, 0).millisecondsSinceEpoch,
        urgencyMode: UrgencyMode.auto,
      );

      store.addTasks([taskQ1]);
      store.promoteDeadlinesNow(now: now);

      expect(store.tasks.firstWhere((t) => t.id == 't-q1').quadrant, qDo);
    });

    test('manual tasks are NEVER automatically promoted even when overdue', () {
      final manualTask = Task(
        id: 't-manual',
        boardId: boardId,
        title: 'Manual Q2 overdue',
        quadrant: qPlan,
        createdAt: now.millisecondsSinceEpoch,
        deadline: DateTime(2026, 9, 14, 12, 0, 0).millisecondsSinceEpoch, // overdue
        urgencyMode: UrgencyMode.manual,
      );

      store.addTasks([manualTask]);
      store.promoteDeadlinesNow(now: now);

      // Remains in Q2 because urgencyMode is manual
      expect(store.tasks.firstWhere((t) => t.id == 't-manual').quadrant, qPlan);
    });

    test('moveTask across urgency dimensions sets urgencyMode to manual', () {
      final task = Task(
        id: 't-move',
        boardId: boardId,
        title: 'Moving task',
        quadrant: qPlan, // Q2: Not urgent
        createdAt: now.millisecondsSinceEpoch,
        urgencyMode: UrgencyMode.auto,
      );
      store.addTasks([task]);

      // Move Q2 -> Q1: shifts from not urgent to urgent
      store.moveTask('t-move', qDo);
      expect(store.tasks.firstWhere((t) => t.id == 't-move').urgencyMode, UrgencyMode.manual);

      // Move Q1 -> Q2: shifts back to not urgent -> stays manual
      store.moveTask('t-move', qPlan);
      expect(store.tasks.firstWhere((t) => t.id == 't-move').urgencyMode, UrgencyMode.manual);
    });

    test('moveTask across importance only preserves urgencyMode', () {
      final task = Task(
        id: 't-importance',
        boardId: boardId,
        title: 'Importance shift',
        quadrant: qDo, // Q1: Urgent
        createdAt: now.millisecondsSinceEpoch,
        urgencyMode: UrgencyMode.auto,
      );
      store.addTasks([task]);

      // Move Q1 -> Q3: both are urgent, only importance changes
      store.moveTask('t-importance', qDelegate);
      expect(store.tasks.firstWhere((t) => t.id == 't-importance').urgencyMode, UrgencyMode.auto);
    });

    test('resetTaskUrgencyMode restores auto and immediately promotes if due', () {
      final task = Task(
        id: 't-reset',
        boardId: boardId,
        title: 'Task to restore auto',
        quadrant: qPlan,
        createdAt: now.millisecondsSinceEpoch,
        deadline: DateTime(2026, 9, 15, 12, 0, 0).millisecondsSinceEpoch, // today
        urgencyMode: UrgencyMode.manual,
      );
      store.addTasks([task]);
      expect(store.tasks.firstWhere((t) => t.id == 't-reset').quadrant, qPlan);

      store.resetTaskUrgencyMode('t-reset');

      final restored = store.tasks.firstWhere((t) => t.id == 't-reset');
      expect(restored.urgencyMode, UrgencyMode.auto);
      expect(restored.quadrant, qDo); // Promoted to Q1!
    });

    test('subtask deadlines do NOT promote parent task', () {
      final parent = Task(
        id: 't-parent',
        boardId: boardId,
        title: 'Parent with no deadline',
        quadrant: qPlan,
        createdAt: now.millisecondsSinceEpoch,
        deadline: null,
        urgencyMode: UrgencyMode.auto,
        subtasks: [
          SubTask(
            id: 's-urgent',
            title: 'Subtask due today',
            deadline: DateTime(2026, 9, 15, 12, 0, 0).millisecondsSinceEpoch,
          ),
        ],
      );

      store.addTasks([parent]);
      store.promoteDeadlinesNow(now: now);

      expect(store.tasks.firstWhere((t) => t.id == 't-parent').quadrant, qPlan);
    });

    test('grouping preserves manual urgencyMode if any grouped task was manual', () {
      final task1 = Task(
        id: 'g-1',
        boardId: boardId,
        title: 'Item 1',
        quadrant: qPlan,
        createdAt: now.millisecondsSinceEpoch,
        urgencyMode: UrgencyMode.auto,
      );
      final task2 = Task(
        id: 'g-2',
        boardId: boardId,
        title: 'Item 2',
        quadrant: qPlan,
        createdAt: now.millisecondsSinceEpoch,
        urgencyMode: UrgencyMode.manual,
      );
      store.addTasks([task1, task2]);

      final parent = store.groupTasks(['g-1', 'g-2'], 'Group Parent');
      expect(parent.urgencyMode, UrgencyMode.manual);
    });
  });

  group('WP22-C-N Widget tests', () {
    const boardId = 'b-ui-test';

    testWidgets('TaskDetailPanel shows manual urgency banner and restores auto', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final now = DateTime.now();
      final todayDeadline = DateTime(now.year, now.month, now.day, 20, 0).millisecondsSinceEpoch;
      final task = Task(
        id: 't-ui-1',
        boardId: boardId,
        title: 'Task with manual urgency in Q2',
        quadrant: qPlan,
        createdAt: now.millisecondsSinceEpoch,
        deadline: todayDeadline,
        urgencyMode: UrgencyMode.manual,
      );

      late Store store;
      await tester.runAsync(() async {
        final res = await makeStore(
          boards: [Board(id: boardId, name: 'UI Board', createdAt: 1000)],
          tasks: [task],
        );
        store = res.$1;
      });
      addTearDown(store.dispose);

      await tester.pumpWidget(
        ChangeNotifierProvider<Store>.value(
          value: store,
          child: MaterialApp(
            home: Scaffold(
              body: TaskDetailPanel(task: task),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Manual notice & restore button should be visible
      expect(find.byKey(const ValueKey('reset-urgency-auto')), findsOneWidget);
      expect(find.text(store.t['urgencyManualNotice']!), findsOneWidget);

      // Tap restore auto
      await tester.ensureVisible(find.byKey(const ValueKey('reset-urgency-auto')));
      await tester.tap(find.byKey(const ValueKey('reset-urgency-auto')));
      await tester.pumpAndSettle();

      // Banner should disappear after restoring auto
      expect(find.byKey(const ValueKey('reset-urgency-auto')), findsNothing);

      // Save the task
      await tester.tap(find.byKey(const ValueKey('save-task')));
      await tester.pumpAndSettle();

      // The saved task in store should now have auto mode and be promoted to Q1 (because deadline is today)
      final savedTask = store.tasks.firstWhere((t) => t.id == task.id);
      expect(savedTask.urgencyMode, UrgencyMode.auto);
      expect(savedTask.quadrant, qDo);
    });

    testWidgets('TaskDetailPanel selecting different urgency quadrant sets manual', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final now = DateTime.now();
      final task = Task(
        id: 't-ui-2',
        boardId: boardId,
        title: 'Task initially auto in Q1',
        quadrant: qDo,
        createdAt: now.millisecondsSinceEpoch,
        urgencyMode: UrgencyMode.auto,
      );

      late Store store;
      await tester.runAsync(() async {
        final res = await makeStore(
          boards: [Board(id: boardId, name: 'UI Board', createdAt: 1000)],
          tasks: [task],
        );
        store = res.$1;
      });
      addTearDown(store.dispose);

      await tester.pumpWidget(
        ChangeNotifierProvider<Store>.value(
          value: store,
          child: MaterialApp(
            home: Scaffold(
              body: TaskDetailPanel(task: task),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Auto mode: no banner
      expect(find.byKey(const ValueKey('reset-urgency-auto')), findsNothing);

      // Tap Q2 choice chip (shifts urgency from urgent to not urgent)
      await tester.tap(find.text(store.t['q2']!));
      await tester.pumpAndSettle();

      // Banner now appears!
      expect(find.byKey(const ValueKey('reset-urgency-auto')), findsOneWidget);

      // Save
      await tester.tap(find.byKey(const ValueKey('save-task')));
      await tester.pumpAndSettle();

      final savedTask = store.tasks.firstWhere((t) => t.id == task.id);
      expect(savedTask.urgencyMode, UrgencyMode.manual);
      expect(savedTask.quadrant, qPlan);
    });

    testWidgets('SettingsScreen displays urgency threshold explanation subtitle', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      late Store store;
      await tester.runAsync(() async {
        final res = await makeStore();
        store = res.$1;
      });
      addTearDown(store.dispose);

      await tester.pumpWidget(
        ChangeNotifierProvider<Store>.value(
          value: store,
          child: const MaterialApp(
            home: SettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(store.t['urgencyThreshold']!), findsOneWidget);
      final expectedDesc = store.t['urgencyThresholdDesc']!
          .replaceAll('{n}', '${store.settings.urgencyThresholdDays}');
      expect(find.text(expectedDesc), findsOneWidget);
    });
  });
}
