import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/storage.dart';

import 'helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Task task(
    String id,
    String board,
    int quadrant, {
    UrgencyMode urgencyMode = UrgencyMode.auto,
  }) => Task(
    id: id,
    boardId: board,
    title: id,
    quadrant: quadrant,
    createdAt: 1,
    urgencyMode: urgencyMode,
  );

  test(
    'WP10 moves a selection in one persisted revision and retains order',
    () async {
      final (store, _) = await makeStore(
        boards: [
          Board(id: 'b1', name: 'One', createdAt: 1),
          Board(id: 'b2', name: 'Two', createdAt: 2),
        ],
        tasks: [
          task('a', 'b1', qDo),
          task('already', 'b1', qPlan),
          task('b', 'b1', qDo),
          task('c', 'b1', qDelegate),
          task('other-board', 'b2', qDo),
        ],
      );
      addTearDown(store.dispose);
      store.setPlannedDay('a', DateTime(2026, 9, 30, 14));
      final plannedDate = store.tasks.firstWhere((t) => t.id == 'a').plannedDate;
      expect((await store.flush()).success, isTrue);
      final revision = store.lastSaveResult.revision;
      final untouchedRevision = store.taskSeq('already');

      expect(
        store.moveTasks({'a', 'already', 'b', 'other-board', 'missing'}, qPlan),
        2,
      );
      expect((await store.flush()).success, isTrue);
      expect(store.lastSaveResult.revision, revision + 1);
      expect(store.tasksIn(qPlan).map((t) => t.id), ['a', 'b', 'already']);
      expect(store.taskSeq('already'), untouchedRevision);
      expect(
        store.tasks.firstWhere((t) => t.id == 'a').urgencyMode,
        UrgencyMode.manual,
      );
      expect(store.tasks.firstWhere((t) => t.id == 'a').plannedDate, plannedDate);
      expect(
        store.tasks.firstWhere((t) => t.id == 'other-board').quadrant,
        qDo,
      );

      final reloaded = Store();
      addTearDown(reloaded.dispose);
      await reloaded.init();
      expect(reloaded.tasksIn(qPlan).map((t) => t.id), ['a', 'b', 'already']);
      expect(reloaded.tasks.firstWhere((t) => t.id == 'a').plannedDate, plannedDate);
      expect(
        reloaded.tasks.firstWhere((t) => t.id == 'other-board').quadrant,
        qDo,
      );
    },
  );

  test('WP10 no-op selection does not save or invalidate undo', () async {
    final (store, _) = await makeStore();
    addTearDown(store.dispose);
    store.addTasks([task('b', store.activeBoardId, qPlan)]);
    expect((await store.flush()).success, isTrue);
    final revision = store.lastSaveResult.revision;
    final taskRevision = store.taskSeq('b');

    expect(store.moveTasks({'b', 'missing'}, qPlan), 0);
    expect((await store.flush()).success, isTrue);
    expect(store.lastSaveResult.revision, revision);
    expect(store.taskSeq('b'), taskRevision);
    expect(() => store.moveTasks({'b'}, 99), throwsArgumentError);
  });
}
