import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:matrixflow_native/ai_service.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('active board and empty task list survive restart', () async {
    final (store, _) = await makeStore();
    store.createBoard('second');
    final active = store.activeBoardId;
    final task = store.newTask('temporary');
    store.addTasks([task]);
    store.deleteTask(task.id);
    await store.flush();
    store.dispose();
    final reopened = Store();
    addTearDown(reopened.dispose);
    await reopened.init();
    expect(reopened.activeBoardId, active);
    expect(reopened.tasks, isEmpty);
  });

  test('invalid settings and typed preferences cannot hang startup', () async {
    SharedPreferences.setMockInitialValues({
      'matrixflow-settings': jsonEncode({'hideCompleted': 'invalid'}),
      'matrixflow-config': 42,
    });
    final store = Store();
    addTearDown(store.dispose);
    await store.init();
    expect(store.ready, isTrue);
    expect(store.corruptNotice, isNotNull);
  });

  test(
    'legacy and orphan tasks are recovered even when the first task has a board',
    () async {
      final (store, _) = await makeStore(
        boards: [Board(id: 'b', name: 'B', createdAt: 1)],
        tasks: [
          Task(
            id: 'one',
            boardId: 'b',
            title: 'normal',
            quadrant: qDo,
            createdAt: 1,
          ),
          Task(
            id: 'two',
            boardId: '',
            title: 'legacy',
            quadrant: qDo,
            createdAt: 1,
          ),
          Task(
            id: 'three',
            boardId: 'missing',
            title: 'orphan',
            quadrant: qDo,
            createdAt: 1,
          ),
        ],
      );
      addTearDown(store.dispose);
      expect(store.visibleTasks, hasLength(3));
    },
  );

  test(
    'new deadline and changed urgency threshold promote immediately',
    () async {
      final (store, _) = await makeStore();
      addTearDown(store.dispose);
      final task = store.newTask('soon', quadrant: qPlan)
        ..deadline =
            DateTime.now().add(const Duration(days: 7)).millisecondsSinceEpoch;
      store.addTasks([task]);
      expect(task.quadrant, qPlan);
      store.updateSettings((settings) => settings..urgencyThresholdDays = 8);
      expect(task.quadrant, qDo);
      final edit = store.newTask('edit', quadrant: qPlan);
      store.addTasks([edit]);
      edit.deadline = DateTime.now().millisecondsSinceEpoch;
      store.updateTask(edit);
      expect(edit.quadrant, qDo);
    },
  );

  test(
    'unknown backup versions and overwrite orphans cannot change data',
    () async {
      final (store, _) = await makeStore();
      addTearDown(store.dispose);
      final active = store.activeBoardId;
      expect(
        () => store.importData({
          'version': 2,
          'boards': [],
          'tasks': [],
        }, 'overwrite'),
        throwsFormatException,
      );
      expect(
        () => store.importData({
          'boards': [],
          'tasks': [
            {'id': 't', 'boardId': 'gone'},
          ],
        }, 'overwrite'),
        throwsFormatException,
      );
      expect(store.activeBoardId, active);
      expect(store.tasks, isEmpty);
    },
  );

  test(
    'hideCompleted filters by completed across boards and never rewrites flags',
    () async {
      final (store, _) = await makeStore(
        boards: [
          Board(id: 'a', name: 'A', createdAt: 1),
          Board(id: 'b', name: 'B', createdAt: 2),
        ],
        tasks: [
          Task(
            id: 'a-done',
            boardId: 'a',
            title: 'done a',
            quadrant: qDo,
            completed: true,
            createdAt: 1,
          ),
          Task(
            id: 'a-open',
            boardId: 'a',
            title: 'open a',
            quadrant: qDo,
            createdAt: 1,
          ),
          Task(
            id: 'b-done',
            boardId: 'b',
            title: 'done b',
            quadrant: qDo,
            completed: true,
            createdAt: 1,
          ),
        ],
      );
      addTearDown(store.dispose);
      store.setActiveBoard('a');
      store.updateSettings((s) => s..hideCompleted = true);
      expect(store.visibleTasks.map((task) => task.id), ['a-open']);
      expect(store.tasks.firstWhere((task) => task.id == 'a-done').completed, isTrue);
      expect(store.tasks.firstWhere((task) => task.id == 'b-done').completed, isTrue);
      store.setActiveBoard('b');
      expect(store.visibleTasks, isEmpty);
      expect(store.tasks.where((task) => task.completed).map((task) => task.id), [
        'a-done',
        'b-done',
      ]);
    },
  );

  test(
    'generated task and repeated child titles have unique identifiers',
    () async {
      final (store, _) = await makeStore();
      addTearDown(store.dispose);
      final ids = List.generate(10000, (_) => store.newTask('same').id);
      expect(ids.toSet(), hasLength(ids.length));
      final task = AIAnalysisResult(
        title: 'repeated',
        quadrant: qDo,
        subtasks: ['same', 'same'],
      ).toTask(id: 't', boardId: 'b', createdAt: 1);
      expect(task.subtasks.map((s) => s.id).toSet(), hasLength(2));
    },
  );

  test(
    'corrupt record does not prevent startup or discard valid siblings',
    () async {
      SharedPreferences.setMockInitialValues({
        'matrixflow-tasks': jsonEncode([
          {'id': 'good', 'title': 'keep', 'boardId': ''},
          {'title': 'missing id'},
        ]),
      });
      final store = Store();
      addTearDown(store.dispose);
      await store.init();
      expect(store.ready, isTrue);
      expect(store.tasks.single.id, 'good');
      expect(store.visibleTasks, hasLength(1));
      expect(store.corruptNotice, isNotNull);
    },
  );

  test('duplicates inside a single backup are deduplicated', () async {
    final (store, _) = await makeStore();
    addTearDown(store.dispose);
    final board = {'id': 'b', 'name': 'new'};
    final task = {'id': 't', 'boardId': 'b', 'title': 'new'};
    expect(
      store.importData({
        'boards': [board, board],
        'tasks': [task, task],
      }, 'merge'),
      1,
    );
    expect(store.boards.where((b) => b.id == 'b'), hasLength(1));
    expect(store.tasks, hasLength(1));
  });

  test('failed overwrite leaves all state unchanged', () async {
    final (store, _) = await makeStore();
    addTearDown(store.dispose);
    store.addTasks([store.newTask('keep')]);
    final before = store.tasks.single;
    final boardId = store.activeBoardId;
    expect(
      () => store.importData({
        'boards': [],
        'tasks': [],
        'settings': {'hideCompleted': 'wrong'},
      }, 'overwrite'),
      throwsA(anything),
    );
    expect(store.tasks.single, same(before));
    expect(store.activeBoardId, boardId);
    expect(store.boards.single.id, boardId);
  });

  test('grouping preserves existing child tasks and deadlines', () async {
    final (store, _) = await makeStore();
    addTearDown(store.dispose);
    final first = store.newTask('project')
      ..subtasks = [SubTask(id: 'sub', title: 'step', deadline: 123)];
    final second = store.newTask('other');
    store.addTasks([first, second]);
    final grouped = store.groupTasks([first.id, second.id], 'group');
    expect(
      grouped.subtasks.any(
        (s) => s.title.contains('step') && s.deadline == 123,
      ),
      isTrue,
    );
  });

  test(
    'new child reopens completed parent when auto completion is enabled',
    () async {
      final (store, _) = await makeStore(
        settings: AppSettings(autoCompleteParent: true),
      );
      addTearDown(store.dispose);
      final task = store.newTask('parent')..completed = true;
      store.addTasks([task]);
      store.appendSubtasks(task.id, [SubTask(id: 'child', title: 'new')]);
      expect(store.tasks.single.completed, isFalse);
    },
  );

  test(
    'invalid AI response reports failure instead of successful empty result',
    () async {
      final ai = AIService(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {'content': 'not JSON'},
                },
              ],
            }),
            200,
          ),
        ),
      );
      await expectLater(
        ai.analyzeTasks(
          inputs: ['keep input'],
          config: AIConfig(baseUrl: 'https://example.test', apiKey: 'test'),
          language: Language.en,
          autoDecompose: false,
        ),
        throwsA(anything),
      );
    },
  );

  test('out of range settings and quadrants normalize safely', () {
    expect(
      AppSettings.fromJson({'urgencyThresholdDays': 99}).urgencyThresholdDays,
      14,
    );
    expect(Task.fromJson({'id': 't', 'quadrant': 'Q2'}).quadrant, qPlan);
    expect(normalizeQuadrant(12), qEliminate);
  });

  test(
    'WP07-N: query completed tasks directly, unaffected by hideCompleted, scope filtering by board or all boards',
    () async {
      final (store, _) = await makeStore(
        boards: [
          Board(id: 'b1', name: 'Board 1', createdAt: 100),
          Board(id: 'b2', name: 'Board 2', createdAt: 200),
        ],
        tasks: [
          Task(
            id: 't1',
            boardId: 'b1',
            title: 'B1 Done',
            quadrant: qDo,
            completed: true,
            createdAt: 101,
          ),
          Task(
            id: 't2',
            boardId: 'b1',
            title: 'B1 Active',
            quadrant: qPlan,
            completed: false,
            createdAt: 102,
          ),
          Task(
            id: 't3',
            boardId: 'b2',
            title: 'B2 Done',
            quadrant: qDelegate,
            completed: true,
            createdAt: 201,
          ),
          Task(
            id: 't4',
            boardId: 'b2',
            title: 'B2 Active',
            quadrant: qEliminate,
            completed: false,
            createdAt: 202,
          ),
        ],
      );
      addTearDown(store.dispose);

      // Default active board is b1
      expect(store.activeBoardId, 'b1');

      // Unfiltered (boardId == null) gives all completed tasks
      final allCompleted = store.completedTasks();
      expect(allCompleted.map((t) => t.id).toList(), ['t1', 't3']);
      expect(store.completedTaskCount(), 2);

      // Filtered to current board (b1)
      final b1Completed = store.completedTasks(boardId: 'b1');
      expect(b1Completed.map((t) => t.id).toList(), ['t1']);
      expect(store.completedTaskCount(boardId: 'b1'), 1);

      // Filtered to b2
      final b2Completed = store.completedTasks(boardId: 'b2');
      expect(b2Completed.map((t) => t.id).toList(), ['t3']);
      expect(store.completedTaskCount(boardId: 'b2'), 1);

      // Now toggle hideCompleted = true
      store.updateSettings((s) => s..hideCompleted = true);
      // visibleTasks on b1 now excludes t1
      expect(store.visibleTasks.map((t) => t.id).toList(), ['t2']);

      // But completedTasks query is NOT affected by hideCompleted
      expect(store.completedTasks().map((t) => t.id).toList(), ['t1', 't3']);
      expect(store.completedTasks(boardId: 'b1').map((t) => t.id).toList(), ['t1']);
    },
  );

  test(
    'WP07-N: restore completed task cascades to subtasks and prevents autoCompleteParent from immediately re-marking complete',
    () async {
      final (store, _) = await makeStore(
        settings: AppSettings(autoCompleteParent: true, hideCompleted: true),
        boards: [Board(id: 'b1', name: 'Board 1', createdAt: 100)],
        tasks: [
          Task(
            id: 'parent1',
            boardId: 'b1',
            title: 'Parent Task',
            quadrant: qDo,
            completed: true,
            createdAt: 101,
            subtasks: [
              SubTask(id: 's1', title: 'Sub 1', completed: true),
              SubTask(id: 's2', title: 'Sub 2', completed: true),
            ],
          ),
        ],
      );
      addTearDown(store.dispose);

      // Initially, because hideCompleted is true and task is completed, visibleTasks is empty
      expect(store.visibleTasks, isEmpty);
      expect(store.completedTasks(boardId: 'b1').length, 1);

      // Restore the task
      final task = store.tasks.firstWhere((t) => t.id == 'parent1');
      store.restoreTask(task);

      // Task is restored (completed == false)
      expect(task.completed, isFalse);
      // Subtasks cascade to completed == false
      expect(task.subtasks.every((s) => !s.completed), isTrue);

      // autoCompleteParent did NOT re-mark it complete
      expect(store.tasks.firstWhere((t) => t.id == 'parent1').completed, isFalse);

      // Because it is now active, it immediately reappears in visibleTasks at its original quadrant
      expect(store.visibleTasks.length, 1);
      expect(store.visibleTasks.first.id, 'parent1');
      expect(store.visibleTasks.first.quadrant, qDo);
      expect(store.visibleTasks.first.boardId, 'b1');

      // Now it's no longer in completedTasks
      expect(store.completedTasks(boardId: 'b1'), isEmpty);

      // Flush and reopen: persists uncompleted state
      await store.flush();
      final reopened = Store();
      addTearDown(reopened.dispose);
      await reopened.init();
      final reopenedTask = reopened.tasks.firstWhere((t) => t.id == 'parent1');
      expect(reopenedTask.completed, isFalse);
      expect(reopenedTask.subtasks.every((s) => !s.completed), isTrue);
    },
  );

  test(
    'WP07-N: deleting a task in completed view does not leak to other boards',
    () async {
      final (store, _) = await makeStore(
        boards: [
          Board(id: 'b1', name: 'Board 1', createdAt: 100),
          Board(id: 'b2', name: 'Board 2', createdAt: 200),
        ],
        tasks: [
          Task(id: 't1', boardId: 'b1', title: 'B1 Done', quadrant: qDo, completed: true, createdAt: 1),
          Task(id: 't2', boardId: 'b2', title: 'B2 Done', quadrant: qPlan, completed: true, createdAt: 2),
        ],
      );
      addTearDown(store.dispose);

      // Delete t1
      store.deleteTask('t1');

      expect(store.tasks.any((t) => t.id == 't1'), isFalse);
      expect(store.tasks.any((t) => t.id == 't2'), isTrue);
      expect(store.completedTasks().map((t) => t.id).toList(), ['t2']);
    },
  );
}
