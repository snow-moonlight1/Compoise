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
}
