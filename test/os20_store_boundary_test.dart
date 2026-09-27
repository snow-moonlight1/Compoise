import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const board = 'b';

  Task task({
    int quadrant = qPlan,
    UrgencyMode urgencyMode = UrgencyMode.auto,
    int? deadline,
    int? reminderAt,
    List<SubTask>? subtasks,
  }) => Task(
    id: 't',
    boardId: board,
    title: 'Alpha',
    quadrant: quadrant,
    createdAt: 1,
    deadline: deadline,
    reminderAt: reminderAt,
    urgencyMode: urgencyMode,
    subtasks:
        subtasks ??
        [SubTask(id: 's1', title: 'One'), SubTask(id: 's2', title: 'Two')],
  );

  Future<Store> open(Task seed) async {
    final (store, _) = await makeStore(
      boards: [Board(id: board, name: 'Board', createdAt: 1)],
      tasks: [seed],
    );
    addTearDown(store.dispose);
    return store;
  }

  group('OS20 revisions invalidate undo after the task changes again', () {
    test('moving away and back does not let the old undo restore completion', () async {
      final store = await open(task());
      final undo = store.toggleCompleteWithUndo(store.tasks.single)!;
      expect(store.canApplyUndo(undo), isTrue);

      store.moveTask('t', qDo);
      store.moveTask('t', qPlan);

      final current = store.tasks.single;
      expect(current.quadrant, qPlan);
      expect(current.urgencyMode, UrgencyMode.manual);
      expect(current.completed, isTrue);
      expect(store.canApplyUndo(undo), isFalse);
      expect(store.applyUndo(undo), isFalse);
      expect(store.tasks.single.completed, isTrue);
      expect(store.tasks.single.urgencyMode, UrgencyMode.manual);
    });

    test('a same-quadrant move does not invalidate undo', () async {
      final store = await open(task(quadrant: qDo));
      final undo = store.toggleCompleteWithUndo(store.tasks.single)!;
      final revision = store.taskSeq('t');
      store.moveTask('t', qDo);
      expect(store.taskSeq('t'), revision);
      expect(store.applyUndo(undo), isTrue);
      expect(store.tasks.single.completed, isFalse);
    });

    test('resetting urgency mode invalidates the previous completion undo', () async {
      final store = await open(task(quadrant: qDo, urgencyMode: UrgencyMode.manual));
      final undo = store.toggleCompleteWithUndo(store.tasks.single)!;
      store.resetTaskUrgencyMode('t');
      expect(store.tasks.single.urgencyMode, UrgencyMode.auto);
      expect(store.tasks.single.quadrant, qDo);
      expect(store.applyUndo(undo), isFalse);
      expect(store.tasks.single.completed, isTrue);
      expect(store.tasks.single.urgencyMode, UrgencyMode.auto);
    });

    test('a no-op urgency reset leaves the previous undo applicable', () async {
      final store = await open(task(quadrant: qDo));
      final undo = store.toggleCompleteWithUndo(store.tasks.single)!;
      final revision = store.taskSeq('t');
      store.resetTaskUrgencyMode('t');
      expect(store.taskSeq('t'), revision);
      expect(store.applyUndo(undo), isTrue);
      expect(store.tasks.single.completed, isFalse);
    });

    test('parent edit, child edit, child removal, and child completion block the old undo', () async {
      final store = await open(task());
      final undo = store.toggleCompleteWithUndo(store.tasks.single)!;

      store.updateTask(Task.fromJson(store.tasks.single.toJson())..title = 'Renamed');
      expect(store.applyUndo(undo), isFalse);
      expect(store.tasks.single.title, 'Renamed');
      expect(store.tasks.single.completed, isTrue);

      final afterEdit = store.toggleCompleteWithUndo(store.tasks.single)!;
      var edited = Task.fromJson(store.tasks.single.toJson());
      edited.subtasks.first.title = 'Renamed child';
      store.updateTask(edited);
      expect(store.applyUndo(afterEdit), isFalse);
      expect(store.tasks.single.subtasks.first.title, 'Renamed child');

      final afterChild = store.toggleCompleteWithUndo(store.tasks.single)!;
      edited = Task.fromJson(store.tasks.single.toJson())..subtasks = [edited.subtasks.first];
      store.updateTask(edited);
      expect(store.applyUndo(afterChild), isFalse);
      expect(store.tasks.single.subtasks, hasLength(1));

      final afterRemoval = store.toggleCompleteWithUndo(store.tasks.single)!;
      store.setSubtaskCompleted('t', 's1', true);
      expect(store.applyUndo(afterRemoval), isFalse);
      expect(store.tasks.single.subtasks.single.completed, isTrue);
    });

    test('deleting the task rejects the old completion undo', () async {
      final store = await open(task());
      final undo = store.toggleCompleteWithUndo(store.tasks.single)!;
      store.deleteTask('t');
      expect(store.applyUndo(undo), isFalse);
      expect(store.tasks, isEmpty);
    });
  });

  group('OS20 commands keep save and reminder behavior', () {
    test('move and urgency reset persist across a reload', () async {
      final store = await open(
        task(quadrant: qDo, urgencyMode: UrgencyMode.manual),
      );
      store.moveTask('t', qDelegate);
      expect((await store.flush()).success, isTrue);

      final moved = Store();
      addTearDown(moved.dispose);
      await moved.init();
      expect(moved.tasks.single.quadrant, qDelegate);
      expect(moved.tasks.single.urgencyMode, UrgencyMode.manual);

      moved.resetTaskUrgencyMode('t');
      expect(moved.tasks.single.urgencyMode, UrgencyMode.auto);
      expect((await moved.flush()).success, isTrue);

      final reset = Store();
      addTearDown(reset.dispose);
      await reset.init();
      expect(reset.tasks.single.quadrant, qDelegate);
      expect(reset.tasks.single.urgencyMode, UrgencyMode.auto);
    });

    test('task commands use the injected reminder service', () async {
      final injected = InMemoryReminderService();
      final other = InMemoryReminderService();
      addTearDown(ReminderService.resetForTest);
      ReminderService.instance = other;
      SharedPreferences.setMockInitialValues({
        'matrixflow-boards':
            '[{"id":"b","name":"Board","createdAt":1}]',
        'matrixflow-tasks': '[]',
        'matrixflow-has-seen-onboarding': true,
      });
      final store = Store(reminders: injected);
      addTearDown(store.dispose);
      await store.init();
      final when = DateTime.now().millisecondsSinceEpoch + 3600000;
      store.addTasks([
        task(
          quadrant: qDo,
          reminderAt: when,
          subtasks: [
            SubTask(id: 's1', title: 'One', reminderAt: when),
          ],
        ),
      ]);
      expect(injected.scheduled, isNotEmpty);
      expect(other.scheduled, isEmpty);

      final scheduledBeforeMove = Map<int, ScheduledReminderRecord>.from(
        injected.scheduled,
      );
      store.moveTask('t', qDelegate);
      expect(injected.scheduled.keys, scheduledBeforeMove.keys);

      store.setSubtaskCompleted('t', 's1', true);
      expect(injected.cancelledIds, isNotEmpty);
      expect(store.tasks.single.subtasks.single.completedAt, isNotNull);

      store.deleteTask('t');
      expect(injected.scheduled, isEmpty);
      expect(other.scheduled, isEmpty);
    });

    test('search-style parent completion does not cascade, and records completedAt', () async {
      final store = await open(task());
      store.setTaskCompleted('t', true);
      expect(store.tasks.single.completed, isTrue);
      expect(store.tasks.single.completedAt, isNotNull);
      expect(store.tasks.single.subtasks.every((sub) => !sub.completed), isTrue);
    });
  });

  group('OS20 reads are snapshots and writes stay on commands', () {
    test('a snapshot edit and a list add do not change the store', () async {
      final store = await open(task());
      final snapshot = store.captureSnapshot();
      snapshot.tasks.single.title = 'Mutated copy';
      snapshot.aiConfig.model = 'mutated-model';
      expect(store.tasks.single.title, 'Alpha');
      expect(store.aiConfig.model, isNot('mutated-model'));
      expect(() => store.tasks.add(task(quadrant: qDo)), throwsUnsupportedError);
      expect(store.tasks, hasLength(1));
    });

    test('startup uses the injected persistence port', () async {
      SharedPreferences.setMockInitialValues({});
      final store = Store(persistence: _ThrowingPersistence());
      addTearDown(store.dispose);
      await store.init();
      expect(store.ready, isFalse);
      expect(store.startupError, isNotNull);
    });

    test('in-place config edits still reach updateAIConfig', () async {
      final store = await open(task());
      store.aiConfig.model = 'synthetic-model';
      expect(await store.updateAIConfig(store.aiConfig), isTrue);
      expect(store.captureSnapshot().aiConfig.model, 'synthetic-model');
    });
  });
}

class _ThrowingPersistence extends StorePersistence {
  @override
  Future<SharedPreferences> open() async => throw StateError('injected');
}
