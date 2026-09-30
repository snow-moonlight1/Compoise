import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/import_preview/draft_model.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/screenshot_import/screenshot_submission.dart';
import 'package:matrixflow_native/storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

DraftBatch confirmed(String board, {bool confirm = true}) {
  final tasks = [
    DraftTask(
      id: 'root',
      imageId: 'image-1',
      sourceRow: 0,
      title: 'Root',
      checked: false,
      dueText: '**tomorrow**',
      keepDueText: true,
    ),
    DraftTask(
      id: 'child',
      imageId: 'image-1',
      sourceRow: 1,
      title: 'Child',
      checked: true,
      parentId: 'root',
      dueText: '2099-01-01',
    ),
  ];
  for (final task in tasks) {
    task.confirmed = confirm;
  }
  return DraftBatch(
      images: [
        DraftImage(id: 'image-1', tasks: tasks),
        DraftImage(id: 'image-2', tasks: [], error: 'Failed'),
      ],
    )
    ..boardId = board
    ..quadrant = 3;
}

class Credentials implements CredentialStore {
  String? value;
  Completer<void>? gate;
  final entered = Completer<void>();
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String next) async {
    if (!entered.isCompleted) entered.complete();
    await gate?.future;
    value = next;
  }

  @override
  Future<void> delete() async {
    value = null;
  }
}

class Writer {
  bool armed = false, fail = false;
  int pointers = 0;
  Completer<void>? gate;
  final entered = Completer<void>();
  Future<bool> write(String key, String value) async {
    if (armed &&
        key.startsWith('matrixflow-save-') &&
        key != SaveProtocol.pointerKey) {
      if (!entered.isCompleted) entered.complete();
      await gate?.future;
    }
    if (armed && key == SaveProtocol.pointerKey) {
      pointers++;
      if (fail) return false;
    }
    return (await SharedPreferences.getInstance()).setString(key, value);
  }
}

Future<Store> open({Writer? writer, Credentials? credentials}) async {
  SharedPreferences.setMockInitialValues({});
  final store = Store(saveWriter: writer?.write, credentialStore: credentials);
  await store.init();
  await store.flush();
  addTearDown(store.dispose);
  return store;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'confirmed fields map once to roots/subtasks and literal notes, one batch',
    () async {
      final writer = Writer();
      final counted = await open(writer: writer);
      final batch = confirmed(counted.activeBoardId);
      var ids = 0;
      final submit = ScreenshotSubmission(
        batch,
        idFactory: () => 'stable-${ids++}',
      );
      writer.armed = true;
      expect(counted.tasks, isEmpty);
      await submit.commit(counted, batch.snapshot());
      expect(writer.pointers, 1);
      final root = counted.tasks.single;
      expect(root.id, 'stable-0');
      expect(root.subtasks.single.id, 'stable-1');
      expect(root.completed, false);
      expect(root.subtasks.single.completed, true);
      expect(root.boardId, counted.activeBoardId);
      expect(root.quadrant, 3);
      expect(root.notesMarkdown, r'\*\*tomorrow\*\*');
      expect(root.subtasks.single.notesMarkdown, isNull);
      expect(root.deadline, isNull);
      expect(root.plannedDate, isNull);
      expect(root.reminderAt, isNull);
      expect(root.subtasks.single.deadline, isNull);
      final json = jsonEncode(root.toJson());
      for (final forbidden in [
        'image-1',
        'sourceRow',
        'OCR',
        'path',
        'box',
        'engine',
      ]) {
        expect(json, isNot(contains(forbidden)));
      }
      await submit.commit(counted, batch.snapshot());
      expect(writer.pointers, 1);
      expect(ids, 2);
      await counted.flush();
      final restarted = Store();
      await restarted.init();
      addTearDown(restarted.dispose);
      expect(restarted.tasks.single.toJson(), root.toJson());
    },
  );

  test(
    'unconfirmed, forged, cancelled and edited submissions make zero writes',
    () async {
      final writer = Writer();
      final store = await open(writer: writer);
      writer.armed = true;
      final batch = confirmed(store.activeBoardId, confirm: false);
      final flow = ScreenshotSubmission(batch);
      final fake = ImportSubmission(
        boardId: store.activeBoardId,
        quadrant: 3,
        tasks: const [
          ImportTask(
            id: 'root',
            imageId: 'image-1',
            title: 'Root',
            checked: false,
          ),
        ],
        skippedCount: 1,
      );
      await expectLater(flow.commit(store, fake), throwsStateError);
      for (final task in batch.activeTasks) {
        task.confirmed = true;
      }
      final snapshot = batch.snapshot();
      batch.activeTasks.first.title = 'Changed';
      await expectLater(flow.commit(store, snapshot), throwsStateError);
      flow.cancel();
      await expectLater(flow.commit(store, batch.snapshot()), throwsStateError);
      expect(store.tasks, isEmpty);
      expect(writer.pointers, 0);
    },
  );

  test('nested child and cross-image parent cannot be saved', () async {
    final store = await open(), batch = confirmed('unused');
    batch.boardId = store.activeBoardId;
    final third = DraftTask(
      id: 'grandchild',
      imageId: 'image-1',
      sourceRow: 2,
      title: 'Nested',
      checked: false,
      parentId: 'child',
    )..confirmed = true;
    batch.images.first.tasks.add(third);
    expect(batch.canSubmit, true);
    await expectLater(
      ScreenshotSubmission(batch).commit(store, batch.snapshot()),
      throwsStateError,
    );
    third.parentId = 'root';
    final mismatched = ImportSubmission(
      boardId: batch.boardId!,
      quadrant: 3,
      tasks: [
        batch.snapshot().tasks.first,
        const ImportTask(
          id: 'child',
          imageId: 'image-2',
          title: 'Child',
          checked: true,
          parentId: 'root',
        ),
      ],
      skippedCount: 1,
    );
    await expectLater(
      ScreenshotSubmission(batch).commit(store, mismatched),
      throwsStateError,
    );
    expect(store.tasks, isEmpty);
  });

  test(
    'pointer failure rolls back and retry reuses ids without duplicates',
    () async {
      final writer = Writer();
      final store = await open(writer: writer);
      final batch = confirmed(store.activeBoardId);
      var ids = 0;
      final flow = ScreenshotSubmission(
        batch,
        idFactory: () => 'retry-${ids++}',
      );
      writer.armed = true;
      writer.fail = true;
      await expectLater(flow.commit(store, batch.snapshot()), throwsStateError);
      expect(store.tasks, isEmpty);
      expect(ids, 2);
      writer.fail = false;
      await flow.commit(store, batch.snapshot());
      expect(ids, 2);
      expect(store.tasks.single.id, 'retry-0');
      expect(store.tasks.single.subtasks.single.id, 'retry-1');
      await flow.commit(store, batch.snapshot());
      expect(store.tasks.length, 1);
    },
  );

  for (final change in ['delete', 'unconfirm', 'edit', 'cancel', 'add']) {
    test('live $change while credential queue drains is revalidated', () async {
      final credentials = Credentials(), writer = Writer();
      final store = await open(credentials: credentials, writer: writer);
      store.createBoard('Second');
      await store.flush();
      final destination = store.activeBoardId;
      final batch = confirmed(destination);
      // Use the flow's own batch so the submitted snapshot matches.
      final active = ScreenshotSubmission(batch);
      credentials.gate = Completer<void>();
      final config = AIConfig.fromJson(store.aiConfig.toJson())
        ..apiKey = 'synthetic';
      final updating = store.updateAIConfig(config);
      await credentials.entered.future;
      writer.armed = true;
      final saving = active.commit(store, batch.snapshot());
      final outcome = change == 'add'
          ? saving
          : expectLater(saving, throwsStateError);
      if (change == 'delete') store.deleteBoard(destination);
      if (change == 'unconfirm') batch.activeTasks.first.confirmed = false;
      if (change == 'edit') batch.activeTasks.first.title = 'edited';
      if (change == 'cancel') active.cancel();
      if (change == 'add') store.addTasks([store.newTask('Live addition')]);
      credentials.gate!.complete();
      await updating;
      if (change == 'add') {
        await outcome;
        expect(
          store.tasks.map((t) => t.title),
          containsAll(['Root', 'Live addition']),
        );
      } else {
        await outcome;
        expect(store.tasks.where((t) => t.title == 'Root'), isEmpty);
      }
    });
  }

  test(
    'ordinary edits during failed disk commit survive screenshot rollback',
    () async {
      final writer = Writer();
      final store = await open(writer: writer);
      final batch = confirmed(store.activeBoardId);
      writer.armed = true;
      writer.fail = true;
      writer.gate = Completer<void>();
      final saving = ScreenshotSubmission(
        batch,
      ).commit(store, batch.snapshot());
      await writer.entered.future;
      store.addTasks([store.newTask('Concurrent edit')]);
      writer.gate!.complete();
      await expectLater(saving, throwsStateError);
      expect(store.tasks.map((task) => task.title).toList(), [
        'Concurrent edit',
      ]);
      writer.fail = false;
      await store.retrySave();
    },
  );
}
