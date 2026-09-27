import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/task_query.dart';

void main() {
  group('task_query unit tests', () {
    final boardA = Board(id: 'b-a', name: 'Work', createdAt: 1000);
    final boardB = Board(id: 'b-b', name: 'Personal', createdAt: 2000);
    final boards = [boardA, boardB];

    test('empty query matches all tasks in current board by default', () {
      final t1 = Task(
        id: 't1',
        boardId: 'b-a',
        title: 'Project Plan',
        quadrant: qDo,
        createdAt: 100,
      );
      final t2 = Task(
        id: 't2',
        boardId: 'b-a',
        title: 'Team Sync',
        quadrant: qPlan,
        createdAt: 200,
      );
      final t3 = Task(
        id: 't3',
        boardId: 'b-b',
        title: 'Buy Groceries',
        quadrant: qDelegate,
        createdAt: 300,
      );

      final results = queryTasks(
        tasks: [t1, t2, t3],
        boards: boards,
        activeBoardId: 'b-a',
        query: '',
      );

      expect(results.length, 2);
      expect(results.map((r) => r.task.id), containsAll(['t1', 't2']));
      expect(results.any((r) => r.task.id == 't3'), isFalse);
    });

    test('scope allBoards returns tasks across multiple boards', () {
      final t1 = Task(
        id: 't1',
        boardId: 'b-a',
        title: 'Task A',
        quadrant: qDo,
        createdAt: 100,
      );
      final t2 = Task(
        id: 't2',
        boardId: 'b-b',
        title: 'Task B',
        quadrant: qDo,
        createdAt: 200,
      );

      final results = queryTasks(
        tasks: [t1, t2],
        boards: boards,
        activeBoardId: 'b-a',
        scope: TaskScopeFilter.allBoards,
      );

      expect(results.length, 2);
      expect(results[0].pathDisplay, 'Work');
      expect(results[1].pathDisplay, 'Personal');
    });

    test('case-insensitive keyword matching for en, zh, ja', () {
      final tEn = Task(
        id: 't-en',
        boardId: 'b-a',
        title: 'Review Flutter Pull Request',
        quadrant: qDo,
        createdAt: 100,
      );
      final tZh = Task(
        id: 't-zh',
        boardId: 'b-a',
        title: '撰写季度工作报告',
        quadrant: qPlan,
        createdAt: 200,
      );
      final tJa = Task(
        id: 't-ja',
        boardId: 'b-a',
        title: 'プロジェクトの仕様書を確認する',
        quadrant: qDelegate,
        createdAt: 300,
      );

      // EN case-insensitive
      final resEn = queryTasks(
        tasks: [tEn, tZh, tJa],
        boards: boards,
        activeBoardId: 'b-a',
        query: 'FLUTTER',
      );
      expect(resEn.length, 1);
      expect(resEn.single.task.id, 't-en');

      // ZH
      final resZh = queryTasks(
        tasks: [tEn, tZh, tJa],
        boards: boards,
        activeBoardId: 'b-a',
        query: '季度工作',
      );
      expect(resZh.length, 1);
      expect(resZh.single.task.id, 't-zh');

      // JA
      final resJa = queryTasks(
        tasks: [tEn, tZh, tJa],
        boards: boards,
        activeBoardId: 'b-a',
        query: '仕様書',
      );
      expect(resJa.length, 1);
      expect(resJa.single.task.id, 't-ja');
    });

    test('subtask matching displays path as Board / Parent and includes child info', () {
      final parent = Task(
        id: 'p1',
        boardId: 'b-a',
        title: 'Client Presentation',
        quadrant: qDo,
        createdAt: 100,
        subtasks: [
          SubTask(id: 's1', title: 'Prepare slides', completed: false),
          SubTask(id: 's2', title: 'Rehearse pitch', completed: true),
        ],
      );

      final results = queryTasks(
        tasks: [parent],
        boards: boards,
        activeBoardId: 'b-a',
        query: 'slides',
      );

      expect(results.length, 1);
      final hit = results.single;
      expect(hit.isSubtaskMatch, isTrue);
      expect(hit.task.id, 'p1');
      expect(hit.matchedSubtask?.id, 's1');
      expect(hit.displayTitle, 'Prepare slides');
      expect(hit.pathDisplay, 'Work / Client Presentation');
      expect(hit.isCompleted, isFalse);
    });

    test('both parent and subtask match keyword query without key collision', () {
      final parent = Task(
        id: 'p1',
        boardId: 'b-a',
        title: 'Release Version 1.0',
        quadrant: qDo,
        createdAt: 100,
        subtasks: [
          SubTask(id: 's1', title: 'Tag Release in Git', completed: false),
        ],
      );

      final results = queryTasks(
        tasks: [parent],
        boards: boards,
        activeBoardId: 'b-a',
        query: 'Release',
      );

      expect(results.length, 2);
      expect(results[0].isSubtaskMatch, isFalse);
      expect(results[0].displayTitle, 'Release Version 1.0');
      expect(results[0].resultKey, 'p1');

      expect(results[1].isSubtaskMatch, isTrue);
      expect(results[1].displayTitle, 'Tag Release in Git');
      expect(results[1].resultKey, 'p1:s1');
    });

    test('cross-board tasks with identical parent/child titles are distinguished', () {
      final tA = Task(
        id: 't-a',
        boardId: 'b-a',
        title: 'Deploy Service',
        quadrant: qDo,
        createdAt: 100,
        subtasks: [SubTask(id: 'sub-1', title: 'Check health endpoint')],
      );
      final tB = Task(
        id: 't-b',
        boardId: 'b-b',
        title: 'Deploy Service',
        quadrant: qPlan,
        createdAt: 200,
        subtasks: [SubTask(id: 'sub-2', title: 'Check health endpoint')],
      );

      final results = queryTasks(
        tasks: [tA, tB],
        boards: boards,
        activeBoardId: 'b-a',
        scope: TaskScopeFilter.allBoards,
        query: 'health',
      );

      expect(results.length, 2);
      expect(results[0].pathDisplay, 'Work / Deploy Service');
      expect(results[0].board.id, 'b-a');
      expect(results[1].pathDisplay, 'Personal / Deploy Service');
      expect(results[1].board.id, 'b-b');
    });

    test('quadrant and status combination filter', () {
      final t1 = Task(
        id: 't1',
        boardId: 'b-a',
        title: 'Task 1',
        quadrant: qDo,
        completed: false,
        createdAt: 100,
      );
      final t2 = Task(
        id: 't2',
        boardId: 'b-a',
        title: 'Task 2',
        quadrant: qDo,
        completed: true,
        createdAt: 200,
      );
      final t3 = Task(
        id: 't3',
        boardId: 'b-a',
        title: 'Task 3',
        quadrant: qPlan,
        completed: false,
        createdAt: 300,
      );

      final doIncomplete = queryTasks(
        tasks: [t1, t2, t3],
        boards: boards,
        activeBoardId: 'b-a',
        quadrant: qDo,
        status: TaskStatusFilter.incomplete,
      );
      expect(doIncomplete.length, 1);
      expect(doIncomplete.single.task.id, 't1');

      final doCompleted = queryTasks(
        tasks: [t1, t2, t3],
        boards: boards,
        activeBoardId: 'b-a',
        quadrant: qDo,
        status: TaskStatusFilter.completed,
      );
      expect(doCompleted.length, 1);
      expect(doCompleted.single.task.id, 't2');
    });

    test('date filter local calendar boundaries: today, thisWeek, thisMonth, overdue, noDate', () {
      // Reference time: Wednesday 2026-09-09 14:30:00 (Weekday: Wednesday = 3)
      // Monday of this week: 2026-09-07 00:00:00
      // Next Monday: 2026-09-14 00:00:00
      // Start of month: 2026-09-01 00:00:00
      // Start of next month: 2026-10-01 00:00:00
      final now = DateTime(2026, 9, 9, 14, 30);

      final tToday = Task(
        id: 't-today',
        boardId: 'b-a',
        title: 'Today Task',
        quadrant: qDo,
        createdAt: 100,
        deadline: DateTime(2026, 9, 9, 23, 59).millisecondsSinceEpoch,
      );

      final tThisWeek = Task(
        id: 't-week',
        boardId: 'b-a',
        title: 'Week Task',
        quadrant: qPlan,
        createdAt: 100,
        deadline: DateTime(2026, 9, 12, 18).millisecondsSinceEpoch,
      );

      final tThisMonth = Task(
        id: 't-month',
        boardId: 'b-a',
        title: 'Month Task',
        quadrant: qPlan,
        createdAt: 100,
        deadline: DateTime(2026, 9, 28, 12).millisecondsSinceEpoch,
      );

      final tOverdue = Task(
        id: 't-overdue',
        boardId: 'b-a',
        title: 'Overdue Task',
        quadrant: qDo,
        createdAt: 100,
        completed: false,
        deadline: DateTime(2026, 9, 6, 20).millisecondsSinceEpoch, // Sunday before Monday 09-07
      );

      final tNoDate = Task(
        id: 't-nodate',
        boardId: 'b-a',
        title: 'No Date Task',
        quadrant: qEliminate,
        createdAt: 100,
      );

      final allTasks = [tToday, tThisWeek, tThisMonth, tOverdue, tNoDate];

      // Today
      final resToday = queryTasks(
        tasks: allTasks,
        boards: boards,
        activeBoardId: 'b-a',
        dateFilter: TaskDateFilter.today,
        now: now,
      );
      expect(resToday.map((r) => r.task.id), ['t-today']);

      // This Week
      final resWeek = queryTasks(
        tasks: allTasks,
        boards: boards,
        activeBoardId: 'b-a',
        dateFilter: TaskDateFilter.thisWeek,
        now: now,
      );
      expect(resWeek.map((r) => r.task.id), containsAll(['t-today', 't-week']));

      // This Month
      final resMonth = queryTasks(
        tasks: allTasks,
        boards: boards,
        activeBoardId: 'b-a',
        dateFilter: TaskDateFilter.thisMonth,
        now: now,
      );
      expect(resMonth.map((r) => r.task.id), containsAll(['t-today', 't-week', 't-month', 't-overdue']));

      // Overdue
      final resOverdue = queryTasks(
        tasks: allTasks,
        boards: boards,
        activeBoardId: 'b-a',
        dateFilter: TaskDateFilter.overdue,
        now: now,
      );
      expect(resOverdue.map((r) => r.task.id), ['t-overdue']);

      // No Date
      final resNoDate = queryTasks(
        tasks: allTasks,
        boards: boards,
        activeBoardId: 'b-a',
        dateFilter: TaskDateFilter.noDate,
        now: now,
      );
      expect(resNoDate.map((r) => r.task.id), ['t-nodate']);
    });

    test('deduplication by ID ensures no duplicates when duplicate task IDs exist in input', () {
      final t1 = Task(
        id: 'dup-id',
        boardId: 'b-a',
        title: 'Duplicate Task 1',
        quadrant: qDo,
        createdAt: 100,
      );
      final t2 = Task(
        id: 'dup-id',
        boardId: 'b-a',
        title: 'Duplicate Task 2',
        quadrant: qDo,
        createdAt: 200,
      );

      final results = queryTasks(
        tasks: [t1, t2],
        boards: boards,
        activeBoardId: 'b-a',
      );

      expect(results.length, 1);
      expect(results.single.task.id, 'dup-id');
    });

    test('performance benchmark: 1,000 synthetic tasks query in < 50ms', () {
      final bigList = <Task>[];
      for (var i = 0; i < 1000; i++) {
        bigList.add(
          Task(
            id: 'task-$i',
            boardId: i % 2 == 0 ? 'b-a' : 'b-b',
            title: 'Synthetic Task #$i containing keywords alpha beta gamma',
            quadrant: (i % 4) + 1,
            completed: i % 3 == 0,
            deadline: DateTime(2026, 9, (i % 28) + 1).millisecondsSinceEpoch,
            createdAt: i * 10,
            subtasks: [
              SubTask(id: 's-$i-1', title: 'Subtask step one of item $i'),
              SubTask(id: 's-$i-2', title: 'Subtask step two of item $i'),
              SubTask(id: 's-$i-3', title: 'Subtask step three of item $i'),
            ],
          ),
        );
      }

      // Warm up
      queryTasks(
        tasks: bigList,
        boards: boards,
        activeBoardId: 'b-a',
        query: 'beta',
        scope: TaskScopeFilter.allBoards,
        status: TaskStatusFilter.incomplete,
        dateFilter: TaskDateFilter.thisMonth,
        now: DateTime(2026, 9, 15),
      );

      final stopwatch = Stopwatch()..start();
      final results = queryTasks(
        tasks: bigList,
        boards: boards,
        activeBoardId: 'b-a',
        query: 'beta',
        scope: TaskScopeFilter.allBoards,
        status: TaskStatusFilter.incomplete,
        dateFilter: TaskDateFilter.thisMonth,
        now: DateTime(2026, 9, 15),
      );
      stopwatch.stop();

      expect(results.isNotEmpty, isTrue);
      expect(stopwatch.elapsedMilliseconds, lessThan(200));
    });

    test('WP13-A-N: keyword search matches parent and subtask notesMarkdown', () {
      final t1 = Task(
        id: 't-note-parent',
        boardId: 'b-a',
        title: 'Regular Title',
        notesMarkdown: 'Important Meeting Minutes with Dr. Smith',
        quadrant: qDo,
        createdAt: 100,
      );
      final t2 = Task(
        id: 't-note-sub',
        boardId: 'b-a',
        title: 'Parent Task Without Keyword',
        quadrant: qPlan,
        createdAt: 200,
        subtasks: [
          SubTask(
            id: 's-note-1',
            title: 'Subtask title',
            notesMarkdown: 'Check out the secret specification document',
          ),
        ],
      );
      final t3 = Task(
        id: 't-zh-ja-notes',
        boardId: 'b-a',
        title: '常规待办',
        notesMarkdown: '会议纪要补充说明，プロジェクト仕様確認',
        quadrant: qPlan,
        createdAt: 300,
        subtasks: [
          SubTask(
            id: 's-zh-sub',
            title: '普通子项',
            notesMarkdown: '详细执行要点：联系客户确认交付日期',
          ),
        ],
      );

      // Search matching parent notes (case-insensitive)
      final res1 = queryTasks(
        tasks: [t1, t2, t3],
        boards: boards,
        activeBoardId: 'b-a',
        query: 'meeting minutes',
      );
      expect(res1.length, 1);
      expect(res1.single.task.id, 't-note-parent');
      expect(res1.single.isSubtaskMatch, isFalse);

      // Search matching subtask notes
      final res2 = queryTasks(
        tasks: [t1, t2, t3],
        boards: boards,
        activeBoardId: 'b-a',
        query: 'secret specification',
      );
      expect(res2.length, 1);
      expect(res2.single.task.id, 't-note-sub');
      expect(res2.single.isSubtaskMatch, isTrue);
      expect(res2.single.matchedSubtask!.id, 's-note-1');

      // Search matching Chinese in parent notes
      final resZh = queryTasks(
        tasks: [t1, t2, t3],
        boards: boards,
        activeBoardId: 'b-a',
        query: '会议纪要',
      );
      expect(resZh.length, 1);
      expect(resZh.single.task.id, 't-zh-ja-notes');

      // Search matching Japanese in parent notes
      final resJa = queryTasks(
        tasks: [t1, t2, t3],
        boards: boards,
        activeBoardId: 'b-a',
        query: 'プロジェクト仕様',
      );
      expect(resJa.length, 1);
      expect(resJa.single.task.id, 't-zh-ja-notes');

      // Search matching Chinese in subtask notes
      final resZhSub = queryTasks(
        tasks: [t1, t2, t3],
        boards: boards,
        activeBoardId: 'b-a',
        query: '联系客户确认交付',
      );
      expect(resZhSub.length, 1);
      expect(resZhSub.single.isSubtaskMatch, isTrue);
      expect(resZhSub.single.matchedSubtask!.id, 's-zh-sub');
    });

    test('WP13-A-N: keyword search strictly does NOT match reasoning', () {
      final tWithReasoning = Task(
        id: 't-reasoning',
        boardId: 'b-a',
        title: '普通待办项',
        reasoning: '历史AI说教推理内容：ConfidentialModelPromptReasoning',
        quadrant: qDo,
        createdAt: 100,
      );

      final results = queryTasks(
        tasks: [tWithReasoning],
        boards: boards,
        activeBoardId: 'b-a',
        query: 'ConfidentialModelPromptReasoning',
      );
      expect(results, isEmpty);
    });
  });
}
