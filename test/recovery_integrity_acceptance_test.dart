import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/recovery_text.dart';
import 'package:matrixflow_native/storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'rf02_import_commit_race_test.dart' as fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'a continuation imported into a selected board must not edit another board',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = await fixture.openStore();
      addTearDown(store.dispose);
      final sourceId = store.activeBoardId;
      final task = store.newTask('Synthetic')..notesMarkdown = 'first-';
      store.addTasks([task]);
      store.createBoard('Selected destination');
      final targetId = store.boards.firstWhere((b) => b.id != sourceId).id;
      await store.flush();
      const full = 'first-second';
      final continuation = {
        ...fixture.payload(fixture.currentBoards(store), []),
        'recovery': true,
        'recoveryChunks': [
          {
            'taskId': task.id,
            'field': 'notesMarkdown',
            'index': 1,
            'offset': 6,
            'length': full.length,
            'archiveId': recoverySha256Hex(utf8.encode(full)),
            'prefixSha256': recoverySha256Hex(utf8.encode('first-')),
            'text': 'second',
          },
        ],
      };
      try {
        await store.applyImport(
          store.previewImport(continuation, 'merge', targetBoardId: targetId),
        );
      } on BackupRejectedException {
        // A continuation whose task belongs elsewhere must be rejected.
      }
      expect(store.tasks.single.boardId, sourceId);
      expect(
        store.tasks.single.notesMarkdown,
        'first-',
        reason: 'The user selected a different destination board.',
      );
    },
  );

  test('last recovery piece must match the declared full content hash', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await fixture.openStore();
    addTearDown(store.dispose);
    final task = store.newTask('Synthetic');
    store.addTasks([task]);
    await store.flush();
    const full = 'first-second';
    Map<String, dynamic> payload(int offset, String text) => {
      ...fixture.payload(fixture.currentBoards(store), []),
      'recovery': true,
      'recoveryChunks': [
        {
          'taskId': task.id,
          'field': 'notesMarkdown',
          'index': offset == 0 ? 0 : 1,
          'offset': offset,
          'length': full.length,
          'archiveId': recoverySha256Hex(utf8.encode(full)),
          'prefixSha256': recoverySha256Hex(
            utf8.encode(full.substring(0, offset)),
          ),
          'text': text,
        },
      ],
    };
    expect(
      (await store.applyImport(
        store.previewImport(payload(0, 'first-'), 'merge'),
      )).success,
      isTrue,
    );
    var accepted = false;
    try {
      accepted = (await store.applyImport(
        store.previewImport(payload(6, 'BROKEN'), 'merge'),
      )).success;
    } on BackupRejectedException {
      // Corruption must be rejected before the live task is changed.
    }
    expect(
      accepted,
      isFalse,
      reason:
          'Same-length altered final text must not clear the recovery cursor. '
          'actual=${store.tasks.single.notesMarkdown}, pending=${store.tasks.single.recoveryPending}',
    );
    expect(store.tasks.single.notesMarkdown, 'first-');
  });

  test(
    'the selected board can continue its own parent and child fields',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = await fixture.openStore();
      addTearDown(store.dispose);
      final sourceId = store.activeBoardId;
      final task = store.newTask('Synthetic')
        ..notesMarkdown = 'first-'
        ..subtasks = [
          SubTask(id: 'child', title: 'Child', notesMarkdown: 'kid-'),
        ];
      store.addTasks([task]);
      store.createBoard('Somewhere else');
      await store.flush();
      final parent = _piece(
        taskId: task.id,
        field: 'notesMarkdown',
        full: 'first-second',
        offset: 6,
        text: 'second',
      );
      final child = _piece(
        taskId: task.id,
        field: 'notesMarkdown',
        full: 'kid-more',
        offset: 4,
        text: 'more',
        subtaskId: 'child',
      );
      final file = _file(store, [parent, child]);
      expect(
        (await store.applyImport(
          store.previewImport(file, 'merge', targetBoardId: sourceId),
        )).success,
        isTrue,
      );
      expect(store.tasks.single.notesMarkdown, 'first-second');
      expect(store.tasks.single.subtasks.single.notesMarkdown, 'kid-more');
      expect(store.tasks.single.boardId, sourceId);
      expect(
        (await store.applyImport(
          store.previewImport(file, 'merge', targetBoardId: sourceId),
        )).success,
        isTrue,
      );
      expect(store.tasks.single.notesMarkdown, 'first-second');
      expect(store.tasks.single.subtasks.single.notesMarkdown, 'kid-more');
    },
  );

  test('one out-of-board chunk rejects the whole continuation file', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await fixture.openStore();
    addTearDown(store.dispose);
    final sourceId = store.activeBoardId;
    final home = store.newTask('Home')..notesMarkdown = 'home-';
    store.addTasks([home]);
    store.createBoard('Other');
    final otherId = store.activeBoardId;
    final away = store.newTask('Away')..notesMarkdown = 'away-';
    store.addTasks([away]);
    await store.flush();
    expect(
      () => store.previewImport(
        _file(store, [
          _piece(
            taskId: home.id,
            field: 'notesMarkdown',
            full: 'home-kept',
            offset: 5,
            text: 'kept',
          ),
          _piece(
            taskId: away.id,
            field: 'notesMarkdown',
            full: 'away-next',
            offset: 5,
            text: 'next',
          ),
        ]),
        'merge',
        targetBoardId: sourceId,
      ),
      throwsA(
        isA<BackupRejectedException>().having(
          (error) => error.copy,
          'copy',
          'importErrorRecoveryBoard',
        ),
      ),
    );
    expect(store.tasks.map((task) => task.notesMarkdown), ['away-', 'home-']);
    expect(store.tasks.map((task) => task.boardId).toSet(), {
      sourceId,
      otherId,
    });
  });

  test(
    'commit rechecks the board after the task moves or the board is deleted',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = await fixture.openStore();
      addTearDown(store.dispose);
      final sourceId = store.activeBoardId;
      final task = store.newTask('Synthetic')..notesMarkdown = 'first-';
      store.addTasks([task]);
      store.createBoard('Later home');
      final laterId = store.activeBoardId;
      await store.flush();
      final continuation = _file(store, [
        _piece(
          taskId: task.id,
          field: 'notesMarkdown',
          full: 'first-second',
          offset: 6,
          text: 'second',
        ),
      ]);
      final planned = store.previewImport(
        continuation,
        'merge',
        targetBoardId: sourceId,
      );
      store.updateTask(
        Task.fromJson(store.tasks.single.toJson())..boardId = laterId,
      );
      expect((await store.applyImport(planned)).success, isFalse);
      expect(store.tasks.single.boardId, laterId);
      expect(store.tasks.single.notesMarkdown, 'first-');

      final onLater = store.previewImport(
        continuation,
        'merge',
        targetBoardId: laterId,
      );
      store.deleteBoard(laterId);
      expect((await store.applyImport(onLater)).success, isFalse);
      expect(
        store.tasks.where((item) => item.notesMarkdown == 'first-second'),
        isEmpty,
      );
      expect(store.tasks.where((item) => item.boardId == laterId), isEmpty);
    },
  );

  test(
    'a first volume mapped onto a board stays bound to that board',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = await fixture.openStore();
      addTearDown(store.dispose);
      final origin = store.activeBoardId;
      store.createBoard('Destination');
      final destination = store.activeBoardId;
      const parent = 'first-second';
      const child = 'kid-more';
      final shell = {
        ...fixture.payload(fixture.newBoards('backup-board'), [
          {
            ...fixture.taskJson('mapped', 'backup-board', 'Synthetic'),
            'subtasks': [
              {'id': 'child', 'title': 'Child'},
            ],
          },
        ]),
        'recovery': true,
        'recoveryChunks': [
          _piece(
            taskId: 'mapped',
            field: 'notesMarkdown',
            full: parent,
            offset: 0,
            text: 'first-',
          ),
          _piece(
            taskId: 'mapped',
            field: 'notesMarkdown',
            full: child,
            offset: 0,
            text: 'kid-',
            subtaskId: 'child',
          ),
        ],
      };
      expect(
        (await store.applyImport(
          store.previewImport(shell, 'merge', targetBoardId: destination),
        )).success,
        isTrue,
      );
      expect(store.tasks.single.boardId, destination);
      expect(store.tasks.single.notesMarkdown, 'first-');
      expect(store.tasks.single.subtasks.single.notesMarkdown, 'kid-');

      final rest = _file(store, [
        _piece(
          taskId: 'mapped',
          field: 'notesMarkdown',
          full: parent,
          offset: 6,
          text: 'second',
        ),
        _piece(
          taskId: 'mapped',
          field: 'notesMarkdown',
          full: child,
          offset: 4,
          text: 'more',
          subtaskId: 'child',
        ),
      ]);
      expect(
        () => store.previewImport(rest, 'merge', targetBoardId: origin),
        throwsA(isA<BackupRejectedException>()),
      );
      expect(store.tasks.single.notesMarkdown, 'first-');
      expect(store.tasks.single.subtasks.single.notesMarkdown, 'kid-');
      expect(
        (await store.applyImport(
          store.previewImport(rest, 'merge', targetBoardId: destination),
        )).success,
        isTrue,
      );
      expect(store.tasks.single.boardId, destination);
      expect(store.tasks.single.notesMarkdown, parent);
      expect(store.tasks.single.subtasks.single.notesMarkdown, child);
      expect(store.tasks.single.recoveryPending, isNull);
      expect(store.tasks.single.subtasks.single.recoveryPending, isNull);
    },
  );

  test(
    'completing a field checks the full text of every recovered field',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = await fixture.openStore();
      addTearDown(store.dispose);
      final task = store.newTask('Hello')
        ..reasoning = 'why-'
        ..subtasks = [
          SubTask(id: 'child', title: 'Kid', notesMarkdown: 'kid-'),
        ];
      store.addTasks([task]);
      await store.flush();
      final sourceId = store.tasks.single.boardId;

      Future<void> merge(List<Map<String, dynamic>> chunks) async {
        expect(
          (await store.applyImport(
            store.previewImport(
              _file(store, chunks),
              'merge',
              targetBoardId: sourceId,
            ),
          )).success,
          isTrue,
        );
      }

      await merge([
        _piece(
          taskId: task.id,
          field: 'title',
          full: 'Hello!',
          offset: 5,
          text: '!',
        ),
        _piece(
          taskId: task.id,
          field: 'reasoning',
          full: 'why-now',
          offset: 4,
          text: 'now',
        ),
        _piece(
          taskId: task.id,
          field: 'notesMarkdown',
          full: '整完',
          offset: 0,
          text: '整',
        ),
        _piece(
          taskId: task.id,
          field: 'notesMarkdown',
          full: 'kid-more',
          offset: 4,
          text: 'more',
          subtaskId: 'child',
        ),
      ]);
      expect(store.tasks.single.title, 'Hello!');
      expect(store.tasks.single.reasoning, 'why-now');
      expect(store.tasks.single.notesMarkdown, '整');
      expect(store.tasks.single.subtasks.single.notesMarkdown, 'kid-more');

      final repeated = _file(store, [
        _piece(
          taskId: task.id,
          field: 'title',
          full: 'Hello!',
          offset: 5,
          text: '!',
        ),
      ]);
      expect(
        (await store.applyImport(
          store.previewImport(repeated, 'merge', targetBoardId: sourceId),
        )).success,
        isTrue,
      );
      expect(store.tasks.single.title, 'Hello!');

      expect(
        () => store.previewImport(
          _file(store, [
            _piece(
              taskId: task.id,
              field: 'notesMarkdown',
              full: '整完',
              offset: 1,
              text: '坏',
            ),
            _piece(
              taskId: task.id,
              field: 'reasoning',
              full: 'why-now',
              offset: 4,
              text: 'now',
            ),
          ]),
          'merge',
          targetBoardId: sourceId,
        ),
        throwsA(isA<BackupRejectedException>()),
      );
      expect(store.tasks.single.notesMarkdown, '整');
      expect(store.tasks.single.reasoning, 'why-now');
      expect(store.tasks.single.recoveryPending?['notesMarkdown'], isNotNull);

      final fresh = store.newTask('Empty');
      store.addTasks([fresh]);
      final brokenWhole = _piece(
        taskId: fresh.id,
        field: 'notesMarkdown',
        full: 'first-second',
        offset: 0,
        text: 'first-BROKEN',
      );
      expect(
        () => store.previewImport(
          _file(store, [brokenWhole]),
          'merge',
          targetBoardId: sourceId,
        ),
        throwsA(isA<BackupRejectedException>()),
      );
      expect(
        store.tasks.firstWhere((item) => item.id == fresh.id).notesMarkdown,
        isNull,
      );

      final stripped = _piece(
        taskId: task.id,
        field: 'notesMarkdown',
        full: '整完',
        offset: 1,
        text: '完',
      );
      stripped.remove('archiveId');
      expect(
        () => store.previewImport(
          _file(store, [stripped]),
          'merge',
          targetBoardId: sourceId,
        ),
        throwsA(isA<BackupRejectedException>()),
      );
      expect(
        store.tasks.singleWhere((item) => item.id == task.id).notesMarkdown,
        '整',
      );
    },
  );
}

Map<String, dynamic> _file(Store store, List<Map<String, dynamic>> chunks) => {
  ...fixture.payload(fixture.currentBoards(store), []),
  'recovery': true,
  'recoveryChunks': chunks,
};

Map<String, dynamic> _piece({
  required String taskId,
  required String field,
  required String full,
  required int offset,
  required String text,
  String? subtaskId,
}) => {
  'taskId': taskId,
  if (subtaskId != null) 'subtaskId': subtaskId,
  'field': field,
  'index': offset == 0 ? 0 : 1,
  'offset': offset,
  'length': full.length,
  'archiveId': recoverySha256Hex(utf8.encode(full)),
  'prefixSha256': recoverySha256Hex(utf8.encode(full.substring(0, offset))),
  'text': text,
};
