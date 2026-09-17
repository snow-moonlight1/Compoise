import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/screens/completed_screen.dart';
import 'package:matrixflow_native/storage.dart';
import 'package:matrixflow_native/task_stats.dart';
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

    test(
      'accurately calculates parent tasks, completion rate, and independent subtasks',
      () {
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
            subtasks: [SubTask(id: 's3', title: 'Sub 3', completed: true)],
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
      },
    );

    test(
      'identifies overdue incomplete tasks but ignores completed tasks with past deadlines',
      () {
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
      },
    );

    test('supports scope filtering between single board and all boards', () {
      final tasks = [
        Task(
          id: 't1',
          boardId: 'b1',
          title: 'B1 Task',
          quadrant: 1,
          createdAt: 1000,
          completed: true,
        ),
        Task(
          id: 't2',
          boardId: 'b2',
          title: 'B2 Task 1',
          quadrant: 1,
          createdAt: 1000,
          completed: false,
        ),
        Task(
          id: 't3',
          boardId: 'b2',
          title: 'B2 Task 2',
          quadrant: 2,
          createdAt: 1000,
          completed: false,
        ),
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

  group(
    'WP27-B-N: Completion history, daily distribution, and completedAt lifecycle',
    () {
      test(
        'computeCompletionHistoryStats accurately aggregates daily buckets and counts',
        () {
          final now = DateTime(2026, 9, 16, 15, 30);
          final todayMs = DateTime(2026, 9, 16, 10, 0).millisecondsSinceEpoch;
          final yesterdayMs =
              DateTime(2026, 9, 15, 18, 0).millisecondsSinceEpoch;
          final threeDaysAgoMs =
              DateTime(2026, 9, 13, 12, 0).millisecondsSinceEpoch;
          final tenDaysAgoMs =
              DateTime(2026, 9, 6, 12, 0).millisecondsSinceEpoch;

          final tasks = [
            Task(
              id: 't1',
              boardId: 'b1',
              title: 'Completed today',
              quadrant: 1,
              createdAt: 1000,
              completed: true,
              completedAt: todayMs,
            ),
            Task(
              id: 't2',
              boardId: 'b1',
              title: 'Completed yesterday with subtask',
              quadrant: 2,
              createdAt: 1000,
              completed: true,
              completedAt: yesterdayMs,
              subtasks: [
                SubTask(
                  id: 's1',
                  title: 'Sub completed yesterday',
                  completed: true,
                  completedAt: yesterdayMs,
                ),
              ],
            ),
            Task(
              id: 't3',
              boardId: 'b1',
              title: 'Completed 3 days ago',
              quadrant: 3,
              createdAt: 1000,
              completed: true,
              completedAt: threeDaysAgoMs,
            ),
            Task(
              id: 't4',
              boardId: 'b1',
              title: 'Completed 10 days ago (outside 7d window)',
              quadrant: 4,
              createdAt: 1000,
              completed: true,
              completedAt: tenDaysAgoMs,
            ),
            Task(
              id: 't5',
              boardId: 'b1',
              title: 'Legacy completed without timestamp',
              quadrant: 1,
              createdAt: 1000,
              completed: true,
              completedAt: null, // unknown date
            ),
            Task(
              id: 't6',
              boardId: 'b1',
              title: 'Active incomplete task',
              quadrant: 1,
              createdAt: 1000,
              completed: false,
            ),
          ];

          final history = computeCompletionHistoryStats(
            tasks: tasks,
            boardId: 'b1',
            days: 7,
            now: now,
          );

          expect(history.totalCompleted, 5);
          expect(history.totalCompletedWithDate, 4);
          expect(history.unknownDateCount, 1);
          expect(history.todayCount, 1);
          // Within 7 days window: today (1), yesterday (1), 3 days ago (1) = 3
          expect(history.past7DaysCount, 3);
          expect(history.dailyBuckets.length, 7);

          // Verify yesterday bucket (parent count 1, subtask count 1, never double counted)
          final yesterdayBucket = history.dailyBuckets.firstWhere(
            (b) => b.dateString == '2026-09-15',
          );
          expect(yesterdayBucket.count, 1);
          expect(yesterdayBucket.subtaskCount, 1);
          expect(yesterdayBucket.tasks.map((t) => t.id).toList(), ['t2']);
        },
      );

      test(
        'sortCompletedTasks sorts by completedAt descending and puts nulls at end',
        () {
          final tasks = [
            Task(
              id: 't_null_1',
              boardId: 'b1',
              title: 'Null 1',
              quadrant: 1,
              createdAt: 100,
              completed: true,
            ),
            Task(
              id: 't_new',
              boardId: 'b1',
              title: 'Newer',
              quadrant: 1,
              createdAt: 200,
              completed: true,
              completedAt: 2000,
            ),
            Task(
              id: 't_null_2',
              boardId: 'b1',
              title: 'Null 2',
              quadrant: 1,
              createdAt: 50,
              completed: true,
            ),
            Task(
              id: 't_old',
              boardId: 'b1',
              title: 'Older',
              quadrant: 1,
              createdAt: 300,
              completed: true,
              completedAt: 1000,
            ),
          ];

          final sorted = sortCompletedTasks(tasks);
          expect(sorted.map((t) => t.id).toList(), [
            't_new', // completedAt: 2000
            't_old', // completedAt: 1000
            't_null_1', // completedAt: null, createdAt: 100
            't_null_2', // completedAt: null, createdAt: 50
          ]);
        },
      );

      test(
        'Store lifecycle: completedAt writes on completion, clears on restore, preserves on edit and undo',
        () async {
          final (store, _) = await makeStore(
            boards: [Board(id: 'b1', name: 'Board 1', createdAt: 1000)],
            tasks: [
              Task(
                id: 't1',
                boardId: 'b1',
                title: 'Task 1',
                quadrant: 1,
                createdAt: 1000,
                completed: false,
                subtasks: [SubTask(id: 's1', title: 'Sub 1', completed: false)],
              ),
            ],
          );

          final task = store.tasks.first;
          expect(task.completedAt, isNull);
          expect(task.subtasks.first.completedAt, isNull);

          // 1. Mark completed
          store.setParentCompleted(task, true);
          final completedTask = store.tasks.first;
          expect(completedTask.completed, isTrue);
          expect(completedTask.completedAt, isNotNull);
          expect(completedTask.subtasks.first.completed, isTrue);
          expect(completedTask.subtasks.first.completedAt, isNotNull);
          final recordedCompletedAt = completedTask.completedAt!;

          // 2. Updating title on already completed task does NOT change completedAt
          completedTask.title = 'Task 1 Renamed';
          store.updateTask(completedTask);
          expect(store.tasks.first.completedAt, equals(recordedCompletedAt));

          // 3. Toggle complete with undo, then undo
          final undoSnapshot = store.toggleCompleteWithUndo(store.tasks.first);
          expect(store.tasks.first.completed, isFalse);
          expect(store.tasks.first.completedAt, isNull);
          expect(store.tasks.first.subtasks.first.completedAt, isNull);

          // Apply undo -> restores previous completed state and timestamp
          expect(undoSnapshot, isNotNull);
          final undoSuccess = store.applyUndo(undoSnapshot!);
          expect(undoSuccess, isTrue);
          expect(store.tasks.first.completed, isTrue);
          expect(store.tasks.first.completedAt, equals(recordedCompletedAt));

          // 4. Restore task resets completedAt to null
          store.restoreTask(store.tasks.first);
          expect(store.tasks.first.completed, isFalse);
          expect(store.tasks.first.completedAt, isNull);

          // 5. Auto-complete parent: when all subtasks are done, parent auto-completes with timestamp
          store.settings.autoCompleteParent = true;
          final t1 = store.tasks.first;
          t1.subtasks.first.completed = true;
          store.updateTask(t1);

          expect(store.tasks.first.completed, isTrue);
          expect(store.tasks.first.completedAt, isNotNull);

          // Uncheck subtask -> parent incomplete, completedAt cleared
          final t1Again = store.tasks.first;
          t1Again.subtasks.first.completed = false;
          store.updateTask(t1Again);
          expect(store.tasks.first.completed, isFalse);
          expect(store.tasks.first.completedAt, isNull);

          store.dispose();
        },
      );

      testWidgets('UX01: CompletedScreen retains timestamps without trends', (
        tester,
      ) async {
        final now = DateTime.now();
        final (store, _) = await makeStore(
          boards: [Board(id: 'b1', name: 'Board 1', createdAt: 1000)],
          tasks: [
            Task(
              id: 't1',
              boardId: 'b1',
              title: 'Task Done Today',
              quadrant: 1,
              createdAt: 1000,
              completed: true,
              completedAt: now.millisecondsSinceEpoch,
            ),
            Task(
              id: 't2',
              boardId: 'b1',
              title: 'Task Done Without Date',
              quadrant: 2,
              createdAt: 1000,
              completed: true,
              completedAt: null,
            ),
          ],
        );

        await tester.pumpWidget(
          wrapApp(store, const CompletedScreen(initialBoardId: 'b1')),
        );
        await tester.pumpAndSettle();

        // Retired trends and progress UI stay absent.
        expect(find.text('Completion Trends'), findsNothing);
        expect(find.byType(LinearProgressIndicator), findsNothing);

        // Timestamps on tasks
        expect(find.byKey(const ValueKey('completed-time-t1')), findsOneWidget);
        expect(find.byKey(const ValueKey('completed-time-t2')), findsOneWidget);
        expect(find.text(store.t['timeUnknown']!), findsOneWidget);

        await tester.pumpWidget(const SizedBox());
        store.dispose();
      });
    },
  );
}
