import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/storage.dart';
import 'package:matrixflow_native/task_tags.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';

/// WP12 tags, data half: the parent-task field, its stored shape, and the
/// save / restart / backup / copy paths that must not lose it.
Task _task({required String id, List<String>? tags, String? notes}) => Task(
  id: id,
  boardId: 'b-1',
  title: 'Task $id',
  quadrant: qDo,
  createdAt: 1000,
  notesMarkdown: notes,
  tags: tags,
);

Map<String, dynamic> _taskJson(Map<String, dynamic> overrides) => {
  'id': 't1',
  'boardId': 'b-1',
  'title': 'Legacy task',
  'quadrant': 1,
  'createdAt': 1000,
  'subtasks': [
    {'id': 's1', 'title': 'Step', 'completed': false},
  ],
  ...overrides,
};

Future<Store> _storeWithRawTasks(List<Map<String, dynamic>> rawTasks) async {
  SharedPreferences.setMockInitialValues({
    'matrixflow-boards': jsonEncode([
      {'id': 'b-1', 'name': 'Board', 'createdAt': 1000},
    ]),
    'matrixflow-tasks': jsonEncode(rawTasks),
  });
  final store = Store();
  await store.init();
  addTearDown(store.dispose);
  return store;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('normalizeTags', () {
    test('a missing field is an empty, growable list', () {
      final tags = normalizeTags(null);
      expect(tags, isEmpty);
      expect(() => tags.add('Work'), returnsNormally);
      expect(tags, ['Work']);
    });

    test('trims each tag and drops blanks', () {
      expect(
        normalizeTags(['  Work ', '', '   ', 'Home', '\turgent\n']),
        ['Work', 'Home', 'urgent'],
      );
    });

    test('keeps the first spelling of a case-equivalent duplicate', () {
      expect(normalizeTags(['Work', 'work', ' WORK ', 'wOrK']), ['Work']);
      expect(normalizeTags(['work', 'Work']), ['work']);
    });

    test('is idempotent and leaves the source list alone', () {
      final source = [' Work ', 'work', '', 'Home'];
      final once = normalizeTags(source);
      expect(normalizeTags(once), once);
      expect(source, [' Work ', 'work', '', 'Home']);
    });

    test('rejects a value that is not a list of strings', () {
      expect(() => normalizeTags('Work'), throwsFormatException);
      expect(() => normalizeTags({'a': 1}), throwsFormatException);
      expect(() => normalizeTags(['Work', 7]), throwsFormatException);
    });

    test('compares tags case- and whitespace-insensitively', () {
      expect(taskHasAllTags(['  Work ', 'Home'], tagKeys(['work'])), isTrue);
      expect(taskHasAllTags(['Work'], tagKeys(['work', 'home'])), isFalse);
      expect(taskHasAllTags(const [], tagKeys(const [])), isTrue);
      expect(taskHasAllTags(const ['Work'], tagKeys(['  ', ''])), isTrue);
    });
  });

  group('Task serialisation', () {
    test('defaults to no tags', () {
      expect(_task(id: 't1').tags, isEmpty);
    });

    test('writes and reads tags back unchanged', () {
      final task = _task(id: 't1', tags: ['Work', '家庭', 'Q3']);
      final restored = Task.fromJson(
        jsonDecode(jsonEncode(task.toJson())) as Map<String, dynamic>,
      );
      expect(restored.tags, ['Work', '家庭', 'Q3']);
    });

    test('omits an empty tag list so old and new records compare equal', () {
      expect(_task(id: 't1').toJson().containsKey('tags'), isFalse);
      expect(_task(id: 't1', tags: const []).toJson().containsKey('tags'), isFalse);
      expect(_task(id: 't1', tags: ['Work']).toJson()['tags'], ['Work']);
    });

    test('normalises tags read from an older or hand-edited library', () {
      final task = Task.fromJson(_taskJson({'tags': [' Work ', 'work', '']}));
      expect(task.tags, ['Work']);
    });

    test('a missing or empty tags field reads as no tags', () {
      expect(Task.fromJson(_taskJson({})).tags, isEmpty);
      expect(Task.fromJson(_taskJson({'tags': []})).tags, isEmpty);
    });

    test('v1 downgrade export drops tags', () {
      final v1 = _task(id: 't1', tags: ['Work']).toJson(targetVersion: 1);
      expect(v1.containsKey('tags'), isFalse);
    });

    test('subtasks never carry tags', () {
      final json = Task.fromJson(_taskJson({'tags': ['Work']})).toJson();
      final child = (json['subtasks'] as List).cast<Map<String, dynamic>>().single;
      expect(child.containsKey('tags'), isFalse);
    });
  });

  group('local save and restart', () {
    test('tags survive a restart', () async {
      final (store, _) = await makeStore(
        boards: [Board(id: 'b-1', name: 'Board', createdAt: 1000)],
        tasks: [_task(id: 't1', tags: ['Work', '家庭'])],
      );
      addTearDown(store.dispose);
      await store.flush();

      final reopened = Store();
      await reopened.init();
      addTearDown(reopened.dispose);
      expect(reopened.tasks.single.tags, ['Work', '家庭']);
    });

    test('a pre-tags library loads with no tags and keeps every other field', () async {
      final store = await _storeWithRawTasks([
        _taskJson({'notesMarkdown': 'Keep me', 'reminderAt': 123456}),
      ]);
      final task = store.tasks.single;
      expect(task.tags, isEmpty);
      expect(task.title, 'Legacy task');
      expect(task.notesMarkdown, 'Keep me');
      expect(task.reminderAt, 123456);
      expect(task.subtasks.single.title, 'Step');
    });

    test('messy stored tags are normalised on load, not rewritten as text', () async {
      final store = await _storeWithRawTasks([
        _taskJson({
          'tags': [' Work ', 'work', '', 'Home'],
          'title': 'Work / Home',
        }),
      ]);
      final task = store.tasks.single;
      expect(task.tags, ['Work', 'Home']);
      expect(task.title, 'Work / Home');
    });

    test('saving after a restart does not accumulate duplicate spellings', () async {
      final store = await _storeWithRawTasks([
        _taskJson({'tags': ['Work', 'work']}),
      ]);
      store.updateTask(
        Task.fromJson(store.tasks.single.toJson())..tags = ['Work', 'home'],
      );
      await store.flush();
      final reopened = Store();
      await reopened.init();
      addTearDown(reopened.dispose);
      expect(reopened.tasks.single.tags, ['Work', 'home']);
    });
  });

  group('backup export and import', () {
    test('v2 export writes tags, v1 export leaves them out', () async {
      final (store, _) = await makeStore(
        boards: [Board(id: 'b-1', name: 'Board', createdAt: 1000)],
        tasks: [_task(id: 't1', tags: ['Work']), _task(id: 't2')],
      );
      addTearDown(store.dispose);

      final v2 = jsonDecode(store.exportJson()) as Map<String, dynamic>;
      final exported = (v2['tasks'] as List).cast<Map<String, dynamic>>();
      expect(exported.singleWhere((t) => t['id'] == 't1')['tags'], ['Work']);
      expect(exported.singleWhere((t) => t['id'] == 't2').containsKey('tags'), isFalse);

      final v1 = jsonDecode(store.exportJson(version: 1)) as Map<String, dynamic>;
      final downgraded = (v1['tasks'] as List).cast<Map<String, dynamic>>();
      expect(
        downgraded.every((t) => !t.containsKey('tags')),
        isTrue,
        reason: 'v1 is a lossy downgrade export',
      );
    });

    test('a tagged backup re-imports without an unknown-field warning', () async {
      final (store, _) = await makeStore(
        boards: [Board(id: 'b-1', name: 'Board', createdAt: 1000)],
        tasks: [_task(id: 't1', tags: ['Work', 'home'])],
      );
      addTearDown(store.dispose);
      final payload = ImportPreflight.decode(
        Uint8List.fromList(utf8.encode(store.exportJson())),
      );

      final plan = store.previewImport(payload, 'overwrite');
      expect(
        plan.warnings.where((warning) => warning.contains('tags')),
        isEmpty,
      );
      expect((await store.applyImport(plan)).success, isTrue);
      await store.flush();
      expect(store.tasks.single.tags, ['Work', 'home']);
    });

    test('import accepts a legacy file with no tags and a messy tag list', () async {
      final (store, _) = await makeStore();
      addTearDown(store.dispose);
      final plan = store.previewImport({
        'version': 2,
        'boards': [
          {'id': 'b-9', 'name': 'Imported', 'createdAt': 1000},
        ],
        'tasks': [
          _taskJson({'id': 'old', 'boardId': 'b-9'}),
          _taskJson({'id': 'messy', 'boardId': 'b-9', 'tags': [' A ', 'a', '']}),
        ],
      }, 'merge');

      expect((await store.applyImport(plan)).success, isTrue);
      expect(store.tasks.singleWhere((task) => task.id == 'old').tags, isEmpty);
      expect(store.tasks.singleWhere((task) => task.id == 'messy').tags, ['A']);
    });

    test('a corrupt tags value is rejected before anything is written', () async {
      final (store, _) = await makeStore(
        tasks: [_task(id: 'keep', tags: ['Work'])],
      );
      addTearDown(store.dispose);
      final before = jsonEncode(store.tasks.map((t) => t.toJson()).toList());

      expect(
        () => store.previewImport({
          'version': 2,
          'boards': [
            {'id': 'b-1', 'name': 'Board', 'createdAt': 1000},
          ],
          'tasks': [_taskJson({'tags': 'Work'})],
        }, 'merge'),
        throwsA(isA<CorruptDataPayloadException>()),
      );
      expect(jsonEncode(store.tasks.map((t) => t.toJson()).toList()), before);
    });

    test('an identical task re-imports as a skip, not a conflict', () async {
      final (store, _) = await makeStore(
        boards: [Board(id: 'b-1', name: 'Board', createdAt: 1000)],
        tasks: [_task(id: 't1', tags: ['Work'])],
      );
      addTearDown(store.dispose);
      final payload = ImportPreflight.decode(
        Uint8List.fromList(utf8.encode(store.exportJson())),
      );

      final plan = store.previewImport(payload, 'merge');
      expect(plan.conflicts, 0);
      expect(plan.addedTasks, 0);
      expect(plan.skipped, greaterThanOrEqualTo(1));
    });
  });

  group('copy and edit paths keep tags', () {
    test('a JSON round trip copies the tag list', () {
      final task = _task(id: 't1', tags: ['Work', 'home']);
      final copy = Task.fromJson(task.toJson());
      expect(copy.tags, ['Work', 'home']);
      expect(identical(copy.tags, task.tags), isFalse);
    });

    test('updateTask stores tags without keeping the caller list', () async {
      final (store, _) = await makeStore(
        tasks: [_task(id: 't1', tags: ['Work'])],
      );
      addTearDown(store.dispose);

      final draft = Task.fromJson(store.tasks.single.toJson());
      final edited = <String>[...draft.tags, 'Home'];
      draft.tags = edited;
      store.updateTask(draft);
      expect(store.tasks.single.tags, ['Work', 'Home']);

      edited.add('Later');
      expect(
        store.tasks.single.tags,
        ['Work', 'Home'],
        reason: 'a draft must not write through into the store',
      );
    });

    test('completing and moving a task keep its tags', () async {
      final (store, _) = await makeStore(
        tasks: [_task(id: 't1', tags: ['Work', '家庭'])],
      );
      addTearDown(store.dispose);

      store.setParentCompleted(store.tasks.single, true);
      expect(store.tasks.single.tags, ['Work', '家庭']);
      expect(store.tasks.single.completed, isTrue);

      store.moveTask('t1', qPlan);
      expect(store.tasks.single.tags, ['Work', '家庭']);
      expect(store.tasks.single.quadrant, qPlan);

      store.setTaskCompleted('t1', false);
      expect(store.tasks.single.tags, ['Work', '家庭']);
      await store.flush();
      final reopened = Store();
      await reopened.init();
      addTearDown(reopened.dispose);
      expect(reopened.tasks.single.tags, ['Work', '家庭']);
    });

    test('an undo snapshot and a captured library copy keep tags', () async {
      final (store, _) = await makeStore(
        tasks: [_task(id: 't1', tags: ['Work'])],
      );
      addTearDown(store.dispose);

      final snapshot = TaskUndoSnapshot.capture(
        actionType: TaskUndoType.complete,
        task: store.tasks.single,
        boardEpoch: store.boardEpoch('b-1'),
        originalIndex: 0,
      );
      expect(snapshot.task.tags, ['Work']);
      expect(store.captureSnapshot().tasks.single.tags, ['Work']);
    });
  });
}
