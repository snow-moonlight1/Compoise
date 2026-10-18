import 'dart:convert';
import 'package:compoise/models.dart';
import 'package:compoise/storage.dart';
import 'package:compoise/widgets/task_edit_draft.dart';
import 'package:flutter_test/flutter_test.dart';
import 'helpers.dart';

Task counted({int? target = 2, int value = 0}) => Task(
  id: 'practice',
  boardId: 'work',
  title: 'Practice',
  quadrant: 2,
  createdAt: 1,
  countProgress: CountProgress(value: value, target: target),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final board = Board(id: 'work', name: 'Work', createdAt: 1);

  test(
    'editing a target preserves counts recorded since the editor opened',
    () {
      final draft = TaskEditDraft(
        counted(target: 50, value: 1),
        onChanged: () {},
      );
      addTearDown(draft.dispose);
      draft.countProgress = CountProgress(value: 1, target: 100);
      final live = counted(target: 50, value: 3);
      expect(
        draft.applyTo(live).countProgress,
        CountProgress(value: 3, target: 100),
      );
      draft.countProgress = CountProgress(value: 1, target: 2);
      expect(() => draft.applyTo(live), throwsA(isA<CountProgressException>()));
    },
  );

  test('multi-volume v4 restores finite and unlimited counters', () {
    final tasks = [
      counted(target: 50, value: 12)..notesMarkdown = 'x' * (5 * 1024 * 1024),
      counted(target: null, value: 9)
        ..id = 'second'
        ..notesMarkdown = 'y' * (5 * 1024 * 1024),
    ];
    final source = ExportData(
      boards: [board],
      tasks: tasks,
      settings: AppSettings(),
      aiConfig: AIConfig(),
    );
    final bundle = buildBackupBundle(jsonEncode(source.toJson()));
    expect(bundle.recoverable, isTrue);
    expect(bundle.parts.length, greaterThan(1));
    var boards = <Board>[];
    var restored = <Task>[];
    for (var i = 0; i < bundle.parts.length; i++) {
      final plan = ImportPreflight.inspect(
        jsonDecode(bundle.parts[i].json) as Map<String, dynamic>,
        i == 0 ? 'overwrite' : 'merge',
        currentBoards: boards,
        currentTasks: restored,
        revision: i,
      );
      boards = plan.boards;
      restored = plan.tasks;
    }
    expect(
      {for (final task in restored) task.id: task.countProgress},
      {
        'practice': CountProgress(value: 12, target: 50),
        'second': CountProgress(value: 9),
      },
    );
  });

  test(
    'finite progress completes on the target, undo restores it and survives restart',
    () async {
      final (store, _) = await makeStore(boards: [board], tasks: [counted()]);
      addTearDown(store.dispose);
      final first = store.recordTaskCount('practice')!;
      expect(store.tasks.single.completed, isFalse);
      expect(store.tasks.single.countProgress!.value, 1);
      final second = store.recordTaskCount('practice')!;
      expect(store.canApplyUndo(first), isFalse);
      expect(store.tasks.single.completed, isTrue);
      expect(store.recordTaskCount('practice'), isNull);
      expect(store.applyUndo(second), isTrue);
      expect(store.tasks.single.completed, isFalse);
      expect(store.tasks.single.countProgress!.value, 1);
      await store.flush(waitForReminders: false);
      final reopened = Store();
      registerTestStore(reopened);
      addTearDown(reopened.dispose);
      await reopened.init();
      expect(reopened.tasks.single.countProgress!.value, 1);
    },
  );

  test(
    'unlimited progress keeps one task and dates until manually finished',
    () async {
      final task = counted(target: null)..deadline = 1999999999999;
      final (store, _) = await makeStore(boards: [board], tasks: [task]);
      addTearDown(store.dispose);
      for (var i = 0; i < 55; i++) {
        store.recordTaskCount('practice');
      }
      expect(store.tasks, hasLength(1));
      expect(store.tasks.single.completed, isFalse);
      expect(store.tasks.single.countProgress!.value, 55);
      expect(store.tasks.single.deadline, task.deadline);
      store.setParentCompleted(store.tasks.single, true);
      expect(store.tasks.single.completed, isTrue);
      store.restoreTask(store.tasks.single);
      expect(store.tasks.single.countProgress!.value, 55);
    },
  );

  test(
    'subtasks cannot auto-complete count goals and reopening allows one more unit',
    () async {
      final task = counted()..subtasks = [SubTask(id: 'step', title: 'Step')];
      final (store, _) = await makeStore(
        boards: [board],
        tasks: [task],
        settings: AppSettings()..autoCompleteParent = true,
      );
      addTearDown(store.dispose);
      store.setSubtaskCompleted(task.id, 'step', true);
      expect(store.tasks.single.completed, isFalse);
      store.recordTaskCount(task.id);
      store.recordTaskCount(task.id);
      store.restoreTask(store.tasks.single);
      expect(store.tasks.single.countProgress!.value, 1);
      expect(store.tasks.single.completed, isFalse);
      store.recordTaskCount(task.id);
      expect(store.tasks.single.completed, isTrue);
    },
  );

  test(
    'v4 backup and split restore preserve counters; old export refuses loss',
    () async {
      final (store, _) = await makeStore(
        boards: [board],
        tasks: [counted(value: 1)],
      );
      addTearDown(store.dispose);
      final payload = jsonDecode(store.exportJson()) as Map<String, dynamic>;
      expect(payload['version'], 4);
      final migrated = DataMigrator.migratePayload(payload);
      expect(
        migrated.tasks.single.countProgress,
        CountProgress(value: 1, target: 2),
      );
      expect(() => store.exportJson(version: 3), throwsFormatException);
      final bundle = buildBackupBundle(jsonEncode(payload));
      expect(bundle.parts, isNotEmpty);
      // The backup writer validates every generated volume with preflight.
      expect(
        jsonDecode(bundle.parts.single.json)['tasks'][0]['countProgress'],
        {'value': 1, 'target': 2},
      );
    },
  );

  test(
    'old backups import normally; malformed progress never silently disappears',
    () {
      final payload = ExportData(
        version: 3,
        boards: [board],
        tasks: [],
        settings: AppSettings(),
        aiConfig: AIConfig(),
      ).toJson();
      expect(DataMigrator.migratePayload(payload).targetVersion, 4);
      for (final raw in [
        {'value': -1},
        {'value': 2, 'target': 1},
        {'value': 0, 'target': 0},
        {'value': 1.5},
        {'value': 0, 'extra': true},
      ]) {
        expect(
          () => Task.fromJson({...counted().toJson(), 'countProgress': raw}),
          throwsFormatException,
        );
      }
      payload['tasks'] = [counted().toJson()];
      expect(() => DataMigrator.migratePayload(payload), throwsFormatException);
      expect(
        () => ImportPreflight.inspect(
          payload,
          'merge',
          currentBoards: [board],
          currentTasks: [],
          revision: 0,
        ),
        throwsA(isA<Exception>()),
      );
    },
  );
}
