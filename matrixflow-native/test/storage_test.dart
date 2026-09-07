import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/models.dart';

import 'helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('merge import dedupes by id and drops orphans', () async {
    final (store, _) = await makeStore(
      boards: [Board(id: 'b1', name: 'My Tasks', createdAt: 1)],
      tasks: [Task(id: 't1', boardId: 'b1', title: 'existing', quadrant: qDo, createdAt: 1)],
    );

    final imported = store.importData({
      'boards': [
        {'id': 'b1', 'name': 'My Tasks', 'createdAt': 1},
        {'id': 'b2', 'name': 'Second', 'createdAt': 2},
      ],
      'tasks': [
        // duplicate id → skipped
        {'id': 't1', 'boardId': 'b1', 'title': 'existing', 'quadrant': 1, 'createdAt': 1},
        // valid new task
        {'id': 't2', 'boardId': 'b2', 'title': 'new', 'quadrant': 2, 'createdAt': 2},
        // orphan (boardId not present anywhere) → dropped
        {'id': 't3', 'boardId': 'nope', 'title': 'orphan', 'quadrant': 3, 'createdAt': 3},
      ],
    }, 'merge');

    expect(imported, 1);
    expect(store.boards.length, 2);
    // existing tasks stay first, new imports append (same as the web app)
    expect(store.tasks.map((task) => task.id), ['t1', 't2']);
  });

  test('overwrite replaces everything and can import settings', () async {
    final (store, _) = await makeStore(
      boards: [Board(id: 'b1', name: 'My Tasks', createdAt: 1)],
      tasks: [Task(id: 't1', boardId: 'b1', title: 'old', quadrant: qDo, createdAt: 1)],
    );

    final count = store.importData({
      'version': 1,
      'boards': [
        {'id': 'b9', 'name': 'Imported', 'createdAt': 9}
      ],
      'tasks': [
        {'id': 't9', 'boardId': 'b9', 'title': 'fresh', 'quadrant': 2, 'createdAt': 9}
      ],
      'settings': {
        'language': 'zh',
        'hideCompleted': true,
        'urgencyThresholdDays': 5,
      },
    }, 'overwrite');

    expect(count, 1);
    expect(store.boards.single.id, 'b9');
    expect(store.tasks.single.title, 'fresh');
    expect(store.settings.language, Language.zh);
    expect(store.settings.hideCompleted, isTrue);
    expect(store.settings.urgencyThresholdDays, 5);
    expect(store.activeBoardId, 'b9');
  });

  test('bad export shape throws FormatException', () async {
    final (store, _) = await makeStore();
    expect(() => store.importData({'boards': 'nope'}, 'merge'), throwsFormatException);
  });

  test('groupTasks folds tasks into a parent with subtasks', () async {
    final (store, _) = await makeStore(
      boards: [Board(id: 'b1', name: 'B', createdAt: 1)],
      tasks: [
        Task(id: 't1', boardId: 'b1', title: 'milk', quadrant: qPlan, createdAt: 1),
        Task(id: 't2', boardId: 'b1', title: 'eggs', quadrant: qPlan, createdAt: 2),
      ],
    );

    final parent = store.groupTasks(['t1', 't2'], 'Shopping');
    expect(store.tasks.map((task) => task.id), [parent.id]);
    expect(parent.subtasks.map((s) => s.title), ['milk', 'eggs']);
  });

  test('autoCompleteParent flips parent when all subtasks done', () async {
    final (store, _) = await makeStore(
      boards: [Board(id: 'b1', name: 'B', createdAt: 1)],
      tasks: [
        Task(
          id: 't1',
          boardId: 'b1',
          title: 'parent',
          quadrant: qDo,
          createdAt: 1,
          subtasks: [
            SubTask(id: 's1', title: 'a'),
            SubTask(id: 's2', title: 'b'),
          ],
        ),
      ],
    );
    store.updateSettings((s) => s..autoCompleteParent = true);

    final task = store.tasks.single;
    task.subtasks[0].completed = true;
    store.updateTask(task);
    expect(store.tasks.single.completed, isFalse);

    task.subtasks[1].completed = true;
    store.updateTask(task);
    expect(store.tasks.single.completed, isTrue);
  });

  test('deadline promotion moves Q2→Q1 and Q4→Q3 inside threshold', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final (store, _) = await makeStore(
      boards: [Board(id: 'b1', name: 'B', createdAt: 1)],
      tasks: [
        Task(id: 't1', boardId: 'b1', title: 'soon-plan', quadrant: qPlan, createdAt: 1, deadline: now + 86400000),
        Task(id: 't2', boardId: 'b1', title: 'far-plan', quadrant: qPlan, createdAt: 1, deadline: now + 30 * 86400000),
        Task(id: 't3', boardId: 'b1', title: 'soon-eliminate', quadrant: qEliminate, createdAt: 1, deadline: now + 86400000),
        Task(id: 't4', boardId: 'b1', title: 'completed-plan', quadrant: qPlan, completed: true, createdAt: 1, deadline: now - 86400000),
      ],
    );

    store.applyDeadlinePromotionForTest();

    final byId = {for (final task in store.tasks) task.id: task};
    expect(byId['t1']!.quadrant, qDo);
    expect(byId['t2']!.quadrant, qPlan);
    expect(byId['t3']!.quadrant, qDelegate);
    expect(byId['t4']!.quadrant, qPlan); // completed tasks never move
  });
}
