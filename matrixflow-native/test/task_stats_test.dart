import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/screens/completed_screen.dart';
import 'package:matrixflow_native/screens/matrix_screen.dart';
import 'package:matrixflow_native/storage.dart';
import 'package:matrixflow_native/task_stats.dart';
import 'package:matrixflow_native/widgets/task_stats_bar.dart';
import 'package:provider/provider.dart';

import 'helpers.dart';

Widget wrapApp(Store store, Widget home) {
  return ChangeNotifierProvider.value(
    value: store,
    child: MaterialApp(
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('en'), Locale('zh'), Locale('ja')],
      home: home,
    ),
  );
}

void main() {
  group('WP27-A-N: TaskStats unit calculation', () {
    test('empty tasks list returns 0% completion rate without false 100%', () {
      final stats = computeTaskStats(tasks: []);
      expect(stats.totalTasks, 0);
      expect(stats.completedTasks, 0);
      expect(stats.incompleteTasks, 0);
      expect(stats.overdueTasks, 0);
      expect(stats.completionRate, 0.0);
      expect(stats.percentageText, '0%');
      expect(stats.subtaskTotal, 0);
      expect(stats.subtaskCompleted, 0);
      expect(stats.subtaskCompletionRate, 0.0);
    });

    test('accurately calculates parent tasks, completion rate, and independent subtasks', () {
      final tasks = [
        Task(
          id: 't1',
          boardId: 'b1',
          title: 'Parent 1',
          quadrant: 1,
          createdAt: 1000,
          completed: true,
          subtasks: [
            SubTask(id: 's1', title: 'Sub 1', completed: true),
            SubTask(id: 's2', title: 'Sub 2', completed: false),
          ],
        ),
        Task(
          id: 't2',
          boardId: 'b1',
          title: 'Parent 2',
          quadrant: 2,
          createdAt: 1000,
          completed: false,
          subtasks: [
            SubTask(id: 's3', title: 'Sub 3', completed: true),
          ],
        ),
        Task(
          id: 't3',
          boardId: 'b1',
          title: 'Parent 3',
          quadrant: 3,
          createdAt: 1000,
          completed: false,
        ),
        Task(
          id: 't4',
          boardId: 'b1',
          title: 'Parent 4',
          quadrant: 4,
          createdAt: 1000,
          completed: true,
        ),
      ];

      final stats = computeTaskStats(tasks: tasks, boardId: 'b1');
      // 4 parents: 2 completed, 2 incomplete -> 50%
      expect(stats.totalTasks, 4);
      expect(stats.completedTasks, 2);
      expect(stats.incompleteTasks, 2);
      expect(stats.completionRate, 0.5);
      expect(stats.percentageText, '50%');

      // 3 subtasks across all parents: 2 completed, 1 incomplete -> 67%
      expect(stats.subtaskTotal, 3);
      expect(stats.subtaskCompleted, 2);
      expect(stats.subtaskCompletionRate, closeTo(2 / 3, 0.01));
      expect(stats.subtaskPercentageText, '67%');
    });

    test('identifies overdue incomplete tasks but ignores completed tasks with past deadlines', () {
      final now = DateTime(2026, 9, 12, 12, 0);
      final pastDeadline = DateTime(2026, 9, 10).millisecondsSinceEpoch;
      final futureDeadline = DateTime(2026, 9, 15).millisecondsSinceEpoch;

      final tasks = [
        // Overdue incomplete parent task
        Task(
          id: 't1',
          boardId: 'b1',
          title: 'Overdue task',
          quadrant: 1,
          createdAt: 1000,
          deadline: pastDeadline,
          completed: false,
        ),
        // Past deadline but already completed -> NOT overdue
        Task(
          id: 't2',
          boardId: 'b1',
          title: 'Completed past deadline',
          quadrant: 2,
          createdAt: 1000,
          deadline: pastDeadline,
          completed: true,
        ),
        // Future deadline incomplete -> NOT overdue
        Task(
          id: 't3',
          boardId: 'b1',
          title: 'Future task',
          quadrant: 3,
          createdAt: 1000,
          deadline: futureDeadline,
          completed: false,
        ),
      ];

      final stats = computeTaskStats(tasks: tasks, boardId: 'b1', now: now);
      expect(stats.totalTasks, 3);
      expect(stats.overdueTasks, 1);
    });

    test('supports scope filtering between single board and all boards', () {
      final tasks = [
        Task(id: 't1', boardId: 'b1', title: 'B1 Task', quadrant: 1, createdAt: 1000, completed: true),
        Task(id: 't2', boardId: 'b2', title: 'B2 Task 1', quadrant: 1, createdAt: 1000, completed: false),
        Task(id: 't3', boardId: 'b2', title: 'B2 Task 2', quadrant: 2, createdAt: 1000, completed: false),
      ];

      final b1Stats = computeTaskStats(tasks: tasks, boardId: 'b1');
      expect(b1Stats.totalTasks, 1);
      expect(b1Stats.completedTasks, 1);
      expect(b1Stats.completionRate, 1.0);

      final b2Stats = computeTaskStats(tasks: tasks, boardId: 'b2');
      expect(b2Stats.totalTasks, 2);
      expect(b2Stats.completedTasks, 0);
      expect(b2Stats.completionRate, 0.0);

      final allStats = computeTaskStats(tasks: tasks, boardId: null);
      expect(allStats.totalTasks, 3);
      expect(allStats.completedTasks, 1);
      expect(allStats.completionRate, closeTo(1 / 3, 0.01));
    });
  });

  group('WP27-A-N: TaskStatsBar widget in UI', () {
    testWidgets('renders TaskStatsBar with progress indicator, chips, and scope switch', (tester) async {
      final past = DateTime(2026, 9, 10).millisecondsSinceEpoch;

      final (store, _) = await makeStore(
        boards: [
          Board(id: 'b1', name: 'Board 1', createdAt: 1000),
          Board(id: 'b2', name: 'Board 2', createdAt: 1000),
        ],
        tasks: [
          Task(
            id: 't1',
            boardId: 'b1',
            title: 'Task 1',
            quadrant: 1,
            createdAt: 1000,
            completed: true,
            subtasks: [
              SubTask(id: 'st1', title: 'Sub 1', completed: true),
              SubTask(id: 'st2', title: 'Sub 2', completed: false),
            ],
          ),
          Task(
            id: 't2',
            boardId: 'b1',
            title: 'Task 2 Overdue',
            quadrant: 2,
            createdAt: 1000,
            deadline: past,
            completed: false,
          ),
          Task(
            id: 't3',
            boardId: 'b2',
            title: 'Task 3 on B2',
            quadrant: 3,
            createdAt: 1000,
            completed: false,
          ),
        ],
      );

      await tester.pumpWidget(wrapApp(store, const MatrixHome()));
      await tester.pumpAndSettle();

      // Verify TaskStatsBar is rendered
      expect(find.byType(TaskStatsBar), findsOneWidget);
      expect(find.byKey(const ValueKey('task-stats-bar')), findsOneWidget);

      // On Board 1: 2 tasks total, 1 completed (50%), 1 overdue, 2 subtasks (1 completed)
      expect(find.text('${store.t['statsCompletionRate']}: 50%'), findsOneWidget);
      expect(find.byKey(const ValueKey('stats-overdue-chip')), findsOneWidget);
      expect(find.byKey(const ValueKey('stats-subtasks-chip')), findsOneWidget);
      expect(find.text('${store.t['statsScopeCurrent']}'), findsOneWidget);

      // Toggle scope to "All Boards"
      await tester.tap(find.byKey(const ValueKey('stats-scope-toggle-btn')));
      await tester.pumpAndSettle();

      // Across all boards: 3 tasks total, 1 completed (33%)
      expect(find.text('${store.t['statsScopeAll']}'), findsOneWidget);
      expect(find.text('${store.t['statsCompletionRate']}: 33%'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      store.dispose();
    });

    testWidgets('CompletedScreen header displays completion rate chip', (tester) async {
      final (store, _) = await makeStore(
        boards: [Board(id: 'b1', name: 'Board 1', createdAt: 1000)],
        tasks: [
          Task(id: 't1', boardId: 'b1', title: 'Task 1', quadrant: 1, createdAt: 1000, completed: true),
          Task(id: 't2', boardId: 'b1', title: 'Task 2', quadrant: 2, createdAt: 1000, completed: false),
        ],
      );

      await tester.pumpWidget(wrapApp(store, const CompletedScreen(initialBoardId: 'b1')));
      await tester.pumpAndSettle();

      // Header should display completed count and completion rate chip
      expect(find.text('${store.t['statsCompletionRate']}: 50%'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      store.dispose();
    });
  });
}
