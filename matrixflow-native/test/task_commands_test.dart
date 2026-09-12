import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WP24-N task_commands unit tests & invalidation contract', () {
    late Store store;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      store = Store();
      await store.init();
    });

    test('deleteTaskWithUndo immediately removes task and persists; applyUndo restores original index and quadrant', () {
      final t1 = store.newTask('Task 1', quadrant: qDo);
      final t2 = store.newTask('Task 2', quadrant: qDo);
      final t3 = store.newTask('Task 3', quadrant: qPlan);
      store.addTasks([t1, t2, t3]);

      expect(store.tasks.length, 3);
      expect(store.tasksIn(qDo).map((t) => t.title).toList(), ['Task 1', 'Task 2']);

      // Delete Task 1 with undo
      final snapshot = store.deleteTaskWithUndo(t1.id);
      expect(snapshot, isNotNull);
      expect(snapshot!.actionType, TaskUndoType.delete);
      expect(snapshot.taskId, t1.id);
      expect(snapshot.task.title, 'Task 1');
      expect(store.tasks.length, 2);
      expect(store.tasksIn(qDo).map((t) => t.title).toList(), ['Task 2']);

      // Undo deletion
      final undone = store.applyUndo(snapshot);
      expect(undone, isTrue);
      expect(store.tasks.length, 3);
      expect(store.tasksIn(qDo).map((t) => t.title).toList(), ['Task 1', 'Task 2']);
      expect(store.tasks.first.id, t1.id);
    });

    test('toggleCompleteWithUndo cascades to subtasks; applyUndo restores parent and all subtasks', () {
      final parent = store.newTask('Parent Task', quadrant: qDo)
        ..subtasks = [
          SubTask(id: 's1', title: 'Sub 1', completed: false),
          SubTask(id: 's2', title: 'Sub 2', completed: false),
        ];
      store.addTasks([parent]);

      expect(parent.completed, isFalse);

      // Complete with undo
      final snap1 = store.toggleCompleteWithUndo(parent);
      expect(snap1, isNotNull);
      expect(snap1!.actionType, TaskUndoType.complete);
      expect(parent.completed, isTrue);
      expect(parent.subtasks.every((s) => s.completed), isTrue);

      // Undo complete -> should restore incomplete state for parent and all subtasks
      final ok1 = store.applyUndo(snap1);
      expect(ok1, isTrue);
      expect(parent.completed, isFalse);
      expect(parent.subtasks.every((s) => !s.completed), isTrue);

      // Toggle again (restore) -> undo restore -> re-completes
      parent.completed = true;
      parent.subtasks.first.completed = true;
      parent.subtasks.last.completed = true;
      store.updateTask(parent);

      final snap2 = store.toggleCompleteWithUndo(parent);
      expect(snap2, isNotNull);
      expect(snap2!.actionType, TaskUndoType.restore);
      expect(parent.completed, isFalse);

      final ok2 = store.applyUndo(snap2);
      expect(ok2, isTrue);
      expect(parent.completed, isTrue);
      expect(parent.subtasks.every((s) => s.completed), isTrue);
    });

    test('invalidation contract: delete task -> clearBoard -> undo rejected and cannot resurrect task', () {
      final t1 = store.newTask('Task to Clear', quadrant: qDo);
      store.addTasks([t1]);

      final snapshot = store.deleteTaskWithUndo(t1.id);
      expect(snapshot, isNotNull);

      // Clear board bumps epoch
      store.clearBoard(store.activeBoardId);
      expect(store.tasks, isEmpty);

      // Attempt undo -> must fail and cannot resurrect task
      final undone = store.applyUndo(snapshot!);
      expect(undone, isFalse);
      expect(store.tasks, isEmpty);
    });

    test('invalidation contract: delete task -> clearQuadrant -> undo rejected and cannot resurrect task', () {
      final t1 = store.newTask('Task in Q1', quadrant: qDo);
      final t2 = store.newTask('Task in Q2', quadrant: qPlan);
      store.addTasks([t1, t2]);

      final snapshot = store.deleteTaskWithUndo(t1.id);
      expect(snapshot, isNotNull);

      // Clear quadrant Q1 bumps epoch for active board
      store.clearQuadrant(qDo);

      // Attempt undo -> must fail
      final undone = store.applyUndo(snapshot!);
      expect(undone, isFalse);
      expect(store.tasksIn(qDo), isEmpty);
      expect(store.tasksIn(qPlan).length, 1);
    });

    test('invalidation contract: delete task -> overwrite import -> undo rejected and cannot resurrect task', () {
      final t1 = store.newTask('Pre-import Task', quadrant: qDo);
      store.addTasks([t1]);

      final snapshot = store.deleteTaskWithUndo(t1.id);
      expect(snapshot, isNotNull);

      // Overwrite import bumps all board epochs
      final backup = {
        'version': 1,
        'timestamp': 1000,
        'boards': [
          {'id': 'b-new', 'name': 'Imported Board', 'createdAt': 1000},
        ],
        'tasks': [
          {'id': 't-new', 'title': 'Imported Task', 'boardId': 'b-new', 'quadrant': 1, 'isLongTerm': false, 'completed': false, 'subtasks': []},
        ],
      };
      store.importData(backup, 'overwrite');

      // Attempt undo of old deletion -> must fail
      final undone = store.applyUndo(snapshot!);
      expect(undone, isFalse);
      expect(store.tasks.map((t) => t.id).toList(), ['t-new']);
    });

    test('invalidation contract: delete task -> deleteBoard -> undo rejected and cannot recreate board', () {
      store.createBoard('Secondary Board');
      final secondBoardId = store.activeBoardId;
      final t = store.newTask('Task on Secondary', quadrant: qDo);
      store.addTasks([t]);

      final snapshot = store.deleteTaskWithUndo(t.id);
      expect(snapshot, isNotNull);

      // Delete the board
      store.deleteBoard(secondBoardId);
      expect(store.boards.any((b) => b.id == secondBoardId), isFalse);

      // Attempt undo -> must fail
      final undone = store.applyUndo(snapshot!);
      expect(undone, isFalse);
      expect(store.boards.any((b) => b.id == secondBoardId), isFalse);
    });

    test('invalidation contract: complete task -> modify title/quadrant -> undo rejected to protect edits', () {
      final t = store.newTask('Original Title', quadrant: qDo);
      store.addTasks([t]);

      final snapshot = store.toggleCompleteWithUndo(t);
      expect(snapshot, isNotNull);
      expect(t.completed, isTrue);

      // Subsequent edit: title is modified
      t.title = 'Modified Title';
      store.updateTask(t);

      // Attempt undo -> must fail to protect subsequent edits from being overwritten
      final undone = store.applyUndo(snapshot!);
      expect(undone, isFalse);
      expect(t.title, 'Modified Title');
      expect(t.completed, isTrue);
    });

    test('consecutive deletions: two tasks deleted in sequence, each undo restores the correct task', () {
      final t1 = store.newTask('Alpha', quadrant: qDo);
      final t2 = store.newTask('Beta', quadrant: qDo);
      store.addTasks([t1, t2]);

      final snapAlpha = store.deleteTaskWithUndo(t1.id);
      final snapBeta = store.deleteTaskWithUndo(t2.id);

      expect(store.tasksIn(qDo), isEmpty);

      // Undo Beta first
      expect(store.applyUndo(snapBeta!), isTrue);
      expect(store.tasksIn(qDo).map((t) => t.title).toList(), ['Beta']);

      // Undo Alpha second
      expect(store.applyUndo(snapAlpha!), isTrue);
      expect(store.tasksIn(qDo).map((t) => t.title).toSet(), {'Alpha', 'Beta'});
    });
  });
}
