import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/planner/planner_labels.dart';
import 'package:matrixflow_native/schedule_item.dart';
import 'package:matrixflow_native/storage.dart';

import 'helpers.dart';

/// The task page and the planner pool read one library and one save path.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Task task(String id, String title, {String board = 'b1', int q = qDo}) =>
      Task(id: id, boardId: board, title: title, quadrant: q, createdAt: 1);

  test(
    'pool counts the same open tasks as the task page, scheduled or not',
    () async {
      final (store, _) = await makeStore(
        boards: [
          Board(id: 'b1', name: 'One', createdAt: 1),
          Board(id: 'b2', name: 'Two', createdAt: 1),
        ],
        tasks: [
          task('a', 'A'),
          task('b', 'B', q: qPlan),
          task('c', 'C'),
          task('d', 'D', board: 'b2'),
          Task(
            id: 'e',
            boardId: 'b1',
            title: 'E',
            quadrant: qDo,
            createdAt: 1,
            completed: true,
          ),
        ],
      );
      // A and B already have a schedule item.
      store.addScheduleItem(
        ScheduleItem.timeBlock(
          id: 's1',
          taskId: 'a',
          startAt: 1000000,
          endAt: 4600000,
          timeZoneId: 'Asia/Shanghai',
        ),
      );
      store.addScheduleItem(
        ScheduleItem.timeBlock(
          id: 's2',
          taskId: 'b',
          startAt: 5000000,
          endAt: 8600000,
          timeZoneId: 'Asia/Shanghai',
        ),
      );
      final open = store.visibleTasks.where((t) => !t.completed).toList();
      final pool = plannerPoolTasks(store.tasks, boardId: store.activeBoardId);
      expect(pool.map((t) => t.id).toSet(), open.map((t) => t.id).toSet());
      expect(pool.length, 3, reason: 'scheduled tasks stay in the pool');
      // All boards view adds the other board's open task.
      expect(plannerPoolTasks(store.tasks).length, 4);
    },
  );

  test('tasks added through the pool survive a reload on both pages', () async {
    final (store, _) = await makeStore(
      boards: [Board(id: 'b1', name: 'One', createdAt: 1)],
      tasks: [task('a', 'A'), task('b', 'B')],
    );
    store.addTasks([
      for (final n in ['x', 'y', 'z']) task(n, n.toUpperCase()),
    ]);
    final result = await store.flush(waitForReminders: false);
    expect(result.success, isTrue);

    final reloaded = Store();
    registerTestStore(reloaded);
    await reloaded.init();
    final home = reloaded.visibleTasks.where((t) => !t.completed).toList();
    final pool = plannerPoolTasks(
      reloaded.tasks,
      boardId: reloaded.activeBoardId,
    );
    expect(home.length, 5);
    expect(pool.length, 5);
    expect(pool.map((t) => t.id).toSet(), home.map((t) => t.id).toSet());
  });
}
