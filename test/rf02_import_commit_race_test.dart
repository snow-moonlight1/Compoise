// RF02 regression: the import transaction and ordinary commands share one
// serial commit owner. Synthetic data, memory prefs, fake credential store.
//
// Migrated from test/review/os_final_review_probe.dart (RF-R01) and extended
// to cover merge/overwrite, double imports, edits at every await barrier,
// credential/slot/pointer failures and the memory/flush/restart triangle.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Credential store whose writes can be held open or made to fail.
class GatedCredentials implements CredentialStore {
  String? value;
  Completer<void>? writeGate;
  Completer<void> entered = Completer<void>();
  bool failWrite = false;
  bool failDelete = false;
  int writes = 0;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String next) async {
    writes++;
    if (!entered.isCompleted) entered.complete();
    await writeGate?.future;
    if (failWrite) throw StateError('synthetic credential write failure');
    value = next;
  }

  @override
  Future<void> delete() async {
    if (!entered.isCompleted) entered.complete();
    await writeGate?.future;
    if (failDelete) throw StateError('synthetic credential delete failure');
    value = null;
  }
}

/// Holds the first [blocked] OS06 slot writes once armed, so a test can run
/// commands at a chosen await barrier of the import transaction. Later slot
/// writes belong to commits queued behind the import and must run. The pointer
/// write and the legacy mirror keys are not slot writes.
class SlotBarrier {
  SlotBarrier({this.blocked = 1});
  final int blocked;
  bool armed = false;
  bool failPointer = false;
  final Set<int> _failedSlots = <int>{};
  final List<Completer<void>> _entered = <Completer<void>>[];
  final List<Completer<void>> _gates = <Completer<void>>[];
  int _slotWrites = 0;

  void failSlot(int index) => _failedSlots.add(index);

  Future<void> enteredAt(int index) async {
    while (_entered.length <= index) {
      _entered.add(Completer<void>());
    }
    return _entered[index].future;
  }

  void release(int index) {
    while (_gates.length <= index) {
      _gates.add(Completer<void>());
    }
    if (!_gates[index].isCompleted) _gates[index].complete();
  }

  Future<bool> write(String key, String value) async {
    if (armed &&
        key.startsWith('matrixflow-save-') &&
        key != SaveProtocol.pointerKey) {
      final index = _slotWrites++;
      while (_entered.length <= index) {
        _entered.add(Completer<void>());
      }
      while (_gates.length <= index) {
        _gates.add(Completer<void>());
      }
      if (!_entered[index].isCompleted) _entered[index].complete();
      if (index < blocked) await _gates[index].future;
      if (_failedSlots.contains(index)) return false;
    }
    if (failPointer && key == SaveProtocol.pointerKey) return false;
    return (await SharedPreferences.getInstance()).setString(key, value);
  }
}

Future<Store> openStore({
  SlotBarrier? barrier,
  CredentialStore? credentials,
}) async {
  final store = Store(
    saveWriter: barrier?.write,
    credentialStore: credentials,
  );
  await store.init();
  await store.flush();
  return store;
}

Map<String, dynamic> taskJson(String id, String boardId, String title) => {
  'id': id,
  'boardId': boardId,
  'title': title,
  'quadrant': 2,
  'createdAt': 1,
  'subtasks': <Object>[],
};

/// Existing boards verbatim, so a merge preview has nothing to conflict with.
List<Map<String, dynamic>> currentBoards(Store store) =>
    store.boards.map((board) => board.toJson()).toList();

List<Map<String, dynamic>> newBoards(String id) => [
  {'id': id, 'name': 'Imported board', 'createdAt': 1},
];

Map<String, dynamic> payload(
  List<Map<String, dynamic>> boards,
  List<Map<String, dynamic>> tasks, {
  Map<String, dynamic>? settings,
  Map<String, dynamic>? aiConfig,
}) => {
  'version': 2,
  'boards': boards,
  'tasks': tasks,
  if (settings != null) 'settings': settings,
  if (aiConfig != null) 'aiConfig': aiConfig,
};

/// Asserts memory, the state right after flush and a fresh Store reading the
/// same preferences all agree on the task titles.
Future<void> expectConsistentTitles(
  Store store,
  List<String> expected, {
  bool ordered = false,
}) async {
  final memory = store.tasks.map((t) => t.title).toList();
  if (ordered) {
    expect(memory, expected);
  } else {
    expect(memory..sort(), expected.toList()..sort());
  }
  expect((await store.flush()).success, isTrue);
  final flushed = store.tasks.map((t) => t.title).toList();
  if (ordered) {
    expect(flushed, expected);
  } else {
    expect(flushed..sort(), expected.toList()..sort());
  }
  store.dispose();
  final restarted = await openStore();
  final reread = restarted.tasks.map((t) => t.title).toList();
  if (ordered) {
    expect(reread, expected);
  } else {
    expect(reread..sort(), expected.toList()..sort());
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'RF-R01/RF02 merge import keeps a task added while its batch is committing',
    () async {
      SharedPreferences.setMockInitialValues({});
      final barrier = SlotBarrier();
      final store = await openStore(barrier: barrier);
      final boardId = store.activeBoardId;
      final plan = store.previewImport(
        payload(currentBoards(store), [
          taskJson('imported', boardId, 'Imported'),
        ]),
        'merge',
      );
      barrier.armed = true;
      final importing = store.applyImport(plan);
      await barrier.enteredAt(0);
      store.addTasks([store.newTask('Concurrent edit')]);
      barrier.release(0);
      expect((await importing).success, isTrue);
      await expectConsistentTitles(store, ['Imported', 'Concurrent edit']);
    },
  );

  test(
    'RF02 merge import keeps an edit and a deletion accepted during its commit',
    () async {
      SharedPreferences.setMockInitialValues({});
      final barrier = SlotBarrier();
      final store = await openStore(barrier: barrier);
      final boardId = store.activeBoardId;
      store.addTasks([
        Task(id: 'kept', boardId: boardId, title: 'Kept', quadrant: 1, createdAt: 1),
        Task(id: 'gone', boardId: boardId, title: 'Gone', quadrant: 1, createdAt: 1),
      ]);
      await store.flush();
      final plan = store.previewImport(
        payload(currentBoards(store), [
          taskJson('imported', boardId, 'Imported'),
        ]),
        'merge',
      );
      barrier.armed = true;
      final importing = store.applyImport(plan);
      await barrier.enteredAt(0);
      final edited = Task.fromJson(
        store.tasks.firstWhere((t) => t.id == 'kept').toJson(),
      )..title = 'Kept edited';
      store.updateTask(edited);
      store.deleteTask('gone');
      barrier.release(0);
      expect((await importing).success, isTrue);
      expect(store.tasks.map((t) => t.title), isNot(contains('Gone')));
      await expectConsistentTitles(
        store,
        ['Imported', 'Kept edited'],
      );
    },
  );

  test(
    'RF02 merge import keeps a settings change accepted during its commit',
    () async {
      SharedPreferences.setMockInitialValues({});
      final barrier = SlotBarrier();
      final store = await openStore(barrier: barrier);
      final boardId = store.activeBoardId;
      final plan = store.previewImport(
        payload(currentBoards(store), [
          taskJson('imported', boardId, 'Imported'),
        ]),
        'merge',
      );
      barrier.armed = true;
      final importing = store.applyImport(plan);
      await barrier.enteredAt(0);
      store.updateSettings((s) => s..hideCompleted = true);
      barrier.release(0);
      expect((await importing).success, isTrue);
      expect(store.settings.hideCompleted, isTrue);
      await expectConsistentTitles(store, ['Imported']);
    },
  );

  test(
    'RF02 merge import keeps an edit accepted while a credential write drains',
    () async {
      SharedPreferences.setMockInitialValues({});
      final credentials = GatedCredentials()..writeGate = Completer<void>();
      final store = await openStore(credentials: credentials);
      final boardId = store.activeBoardId;
      final updating = store.updateAIConfig(
        store.copyAIConfig()..apiKey = 'synthetic-pending',
      );
      await credentials.entered.future;
      final plan = store.previewImport(
        payload(currentBoards(store), [
          taskJson('imported', boardId, 'Imported'),
        ]),
        'merge',
      );
      final importing = store.applyImport(plan);
      // The import is now waiting on the credential queue, not on a slot.
      await Future<void>.delayed(const Duration(milliseconds: 10));
      store.addTasks([store.newTask('Concurrent edit')]);
      credentials.writeGate!.complete();
      expect((await updating), isTrue);
      expect((await importing).success, isTrue);
      expect(store.aiConfig.apiKey, 'synthetic-pending');
      await expectConsistentTitles(store, ['Imported', 'Concurrent edit']);
    },
  );

  test(
    'RF02 overwrite import wins over an edit accepted before it was applied',
    () async {
      SharedPreferences.setMockInitialValues({});
      final credentials = GatedCredentials()..writeGate = Completer<void>();
      final store = await openStore(credentials: credentials);
      store.addTasks([store.newTask('Local')]);
      await store.flush();
      final updating = store.updateAIConfig(
        store.copyAIConfig()..apiKey = 'synthetic-pending',
      );
      await credentials.entered.future;
      final plan = store.previewImport(
        payload(newBoards('board-imported'), [
          taskJson('imported', 'board-imported', 'Imported'),
        ]),
        'overwrite',
      );
      final importing = store.applyImport(plan);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      store.addTasks([store.newTask('Concurrent edit')]);
      credentials.writeGate!.complete();
      await updating;
      expect((await importing).success, isTrue);
      // The overwrite was confirmed as a full replace; the edit landed before
      // it, so the backup is the later accepted operation and wins. No mix of
      // the preview and the edit is produced.
      await expectConsistentTitles(store, ['Imported'], ordered: true);
    },
  );

  test(
    'RF02 overwrite import is followed by an edit accepted during its commit',
    () async {
      SharedPreferences.setMockInitialValues({});
      final barrier = SlotBarrier();
      final store = await openStore(barrier: barrier);
      store.addTasks([store.newTask('Local')]);
      await store.flush();
      final plan = store.previewImport(
        payload(newBoards('board-imported'), [
          taskJson('imported', 'board-imported', 'Imported'),
        ]),
        'overwrite',
      );
      barrier.armed = true;
      final importing = store.applyImport(plan);
      await barrier.enteredAt(0);
      store.addTasks([store.newTask('After import')]);
      barrier.release(0);
      expect((await importing).success, isTrue);
      // The overwrite is applied first and the add is queued after it, so the
      // serial order keeps both.
      await expectConsistentTitles(store, ['Imported', 'After import']);
    },
  );

  test('RF02 two merge imports queue on the owner and both land', () async {
    SharedPreferences.setMockInitialValues({});
    final barrier = SlotBarrier();
    final store = await openStore(barrier: barrier);
    final boardId = store.activeBoardId;
    barrier.armed = true;
    final first = store.applyImport(
      store.previewImport(
        payload(currentBoards(store), [
          taskJson('first', boardId, 'First import'),
        ]),
        'merge',
      ),
    );
    await barrier.enteredAt(0);
    final second = store.applyImport(
      store.previewImport(
        payload(currentBoards(store), [
          taskJson('second', boardId, 'Second import'),
        ]),
        'merge',
      ),
    );
    barrier.release(0);
    expect((await first).success, isTrue);
    expect((await second).success, isTrue);
    await expectConsistentTitles(
      store,
      ['First import', 'Second import'],
    );
  });

  test(
    'RF02 overwrite and merge imports both land in submission order',
    () async {
      SharedPreferences.setMockInitialValues({});
      final barrier = SlotBarrier();
      final store = await openStore(barrier: barrier);
      store.addTasks([store.newTask('Local')]);
      await store.flush();
      barrier.armed = true;
      final overwrite = store.applyImport(
        store.previewImport(
          payload(newBoards('board-imported'), [
            taskJson('imported', 'board-imported', 'Imported'),
          ]),
          'overwrite',
        ),
      );
      await barrier.enteredAt(0);
      final merge = store.applyImport(
        store.previewImport(
          payload(newBoards('board-imported'), [
            taskJson('merged', 'board-imported', 'Merged after overwrite'),
          ]),
          'merge',
        ),
      );
      barrier.release(0);
      expect((await overwrite).success, isTrue);
      expect((await merge).success, isTrue);
      await expectConsistentTitles(
        store,
        ['Imported', 'Merged after overwrite'],
      );
    },
  );

  test(
    'RF02 credential write failure leaves the old library and the accepted edit',
    () async {
      SharedPreferences.setMockInitialValues({});
      final credentials = GatedCredentials()
        ..writeGate = Completer<void>()
        ..failWrite = true;
      final store = await openStore(credentials: credentials);
      store.addTasks([store.newTask('Local')]);
      await store.flush();
      final plan = store.previewImport(
        payload(newBoards('board-imported'), [
          taskJson('imported', 'board-imported', 'Imported'),
        ], aiConfig: {
          'provider': 'custom',
          'protocol': 'openai-compatible',
          'customApiKey': 'synthetic-backup-key',
        }),
        'overwrite',
      );
      expect(plan.hasCredential, isTrue);
      final importing = store.applyImport(plan, importCredential: true);
      await credentials.entered.future;
      store.addTasks([store.newTask('Concurrent edit')]);
      credentials.writeGate!.complete();
      expect((await importing).success, isFalse);
      expect(store.credentialError, isNotNull);
      expect(store.tasks.map((t) => t.title), contains('Concurrent edit'));
      expect(store.tasks.map((t) => t.title), isNot(contains('Imported')));
      store.dispose();
      final restarted = await openStore();
      expect(restarted.tasks.map((t) => t.title), isNot(contains('Imported')));
      expect(restarted.tasks.map((t) => t.title), contains('Local'));
      restarted.dispose();
    },
  );

  test(
    'RF02 slot write failure rolls the import back and keeps the accepted edit',
    () async {
      SharedPreferences.setMockInitialValues({});
      final barrier = SlotBarrier()..failSlot(0);
      final store = await openStore(barrier: barrier);
      final boardId = store.activeBoardId;
      store.addTasks([store.newTask('Local')]);
      await store.flush();
      final plan = store.previewImport(
        payload(currentBoards(store), [
          taskJson('imported', boardId, 'Imported'),
        ]),
        'merge',
      );
      barrier.armed = true;
      final importing = store.applyImport(plan);
      await barrier.enteredAt(0);
      store.addTasks([store.newTask('Concurrent edit')]);
      barrier.release(0);
      expect((await importing).success, isFalse);
      expect(store.tasks.map((t) => t.title), isNot(contains('Imported')));
      await expectConsistentTitles(store, ['Local', 'Concurrent edit']);
    },
  );

  test('RF02 pointer write failure leaves no partial state', () async {
    SharedPreferences.setMockInitialValues({});
    final barrier = SlotBarrier();
    final store = await openStore(barrier: barrier);
    final boardId = store.activeBoardId;
    store.addTasks([store.newTask('Local')]);
    await store.flush();
    final plan = store.previewImport(
      payload(currentBoards(store), [
        taskJson('imported', boardId, 'Imported'),
      ]),
      'merge',
    );
    barrier.armed = true;
    barrier.failPointer = true;
    final importing = store.applyImport(plan);
    await barrier.enteredAt(0);
    store.addTasks([store.newTask('Concurrent edit')]);
    barrier.release(0);
    expect((await importing).success, isFalse);
    expect(store.tasks.map((t) => t.title), isNot(contains('Imported')));
    // The edit's own commit was queued while the pointer still failed; the
    // existing retry path has to be able to land it.
    barrier.failPointer = false;
    expect((await store.retrySave()).success, isTrue);
    await expectConsistentTitles(store, ['Local', 'Concurrent edit']);
  });

  test(
    'RF02 an edit conflicting with the backup refuses the import without touch',
    () async {
      SharedPreferences.setMockInitialValues({});
      final credentials = GatedCredentials()..writeGate = Completer<void>();
      final store = await openStore(credentials: credentials);
      final boardId = store.activeBoardId;
      final shared = Task(
        id: 'shared',
        boardId: boardId,
        title: 'Shared',
        quadrant: 1,
        createdAt: 1,
      );
      store.addTasks([shared]);
      await store.flush();
      final updating = store.updateAIConfig(
        store.copyAIConfig()..apiKey = 'synthetic-pending',
      );
      await credentials.entered.future;
      final plan = store.previewImport(
        payload(currentBoards(store), [
          shared.toJson(),
          taskJson('imported', boardId, 'Imported'),
        ]),
        'merge',
      );
      expect(plan.conflicts, 0);
      final importing = store.applyImport(plan);
      // Barrier before the plan is re-derived, so the edit is part of the
      // re-derivation and collides with the record carried by the backup.
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final edited = Task.fromJson(shared.toJson())..title = 'Shared edited';
      store.updateTask(edited);
      credentials.writeGate!.complete();
      await updating;
      expect((await importing).success, isFalse);
      expect(store.tasks.map((t) => t.title), isNot(contains('Imported')));
      await expectConsistentTitles(store, ['Shared edited']);
    },
  );

  test('RF02 import payload is re-derived, not replayed', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await openStore();
    final boardId = store.activeBoardId;
    final plan = store.previewImport(
      payload(currentBoards(store), [
        taskJson('imported', boardId, 'Imported'),
      ]),
      'merge',
    );
    // Accepted after the preview, before the commit: the re-derived plan must
    // report it instead of the stale preview counts.
    store.addTasks([store.newTask('Between preview and apply')]);
    expect((await store.applyImport(plan)).success, isTrue);
    await expectConsistentTitles(
      store,
      ['Imported', 'Between preview and apply'],
    );
  });

  test('RF02 confirmed import payload is isolated from later edits', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await openStore();
    final source = payload(currentBoards(store), [
      taskJson('imported', store.activeBoardId, 'Confirmed'),
    ]);
    final plan = store.previewImport(source, 'merge');

    (source['tasks'] as List).first['title'] = 'Changed after preview';
    expect(
      () => (plan.payload!['tasks'] as List).first['title'] = 'Changed in plan',
      throwsUnsupportedError,
    );
    expect((await store.applyImport(plan)).success, isTrue);
    await expectConsistentTitles(store, ['Confirmed']);
  });

  test('RF02 a hand-built plan without payload cannot replay stale state', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await openStore();
    store.addTasks([store.newTask('Local')]);
    await store.flush();
    // A plan built by hand carries no payload, so it cannot be re-derived.
    // baseRevision -1 never matches the live revision, so it is refused
    // instead of erasing the accepted task.
    final stale = ImportPlan(
      mode: 'overwrite',
      boards: const [],
      tasks: const [],
      addedBoards: 0,
      addedTasks: 0,
      skipped: 0,
      conflicts: 0,
      repaired: 0,
      removedBoards: 0,
      removedTasks: 0,
      warnings: const [],
      baseRevision: -1,
    );
    expect(stale.payload, isNull);
    expect((await store.applyImport(stale)).success, isFalse);
    await expectConsistentTitles(store, ['Local']);
  });

  test(
    'RF02 failed overwrite import keeps a settings change accepted during its commit',
    () async {
      SharedPreferences.setMockInitialValues({});
      final barrier = SlotBarrier()..failSlot(0);
      final store = await openStore(barrier: barrier);
      store.addTasks([store.newTask('Local')]);
      await store.flush();
      final plan = store.previewImport(
        payload(newBoards('board-imported'), [
          taskJson('imported', 'board-imported', 'Imported'),
        ], settings: {'theme': 'dark'}),
        'overwrite',
      );
      expect(plan.settings?.theme, ThemeModePref.dark);
      barrier.armed = true;
      final importing = store.applyImport(plan);
      await barrier.enteredAt(0);
      store.updateSettings((s) => s..language = Language.zh);
      barrier.release(0);
      expect((await importing).success, isFalse);
      // The change landed on top of the values this import supplied, so the
      // rollback keeps it instead of erasing a choice the user already made.
      expect(store.settings.theme, ThemeModePref.dark);
      expect(store.tasks.map((t) => t.title), isNot(contains('Imported')));
      expect((await store.flush()).success, isTrue);
      store.dispose();
      final restarted = await openStore();
      expect(restarted.settings.language, Language.zh);
      expect(restarted.tasks.map((t) => t.title), contains('Local'));
      expect(restarted.tasks.map((t) => t.title), isNot(contains('Imported')));
      restarted.dispose();
    },
  );

  test(
    'RF02 failed overwrite import reverts every value it brought in',
    () async {
      SharedPreferences.setMockInitialValues({});
      final barrier = SlotBarrier()..failSlot(0);
      final store = await openStore(barrier: barrier);
      store.addTasks([store.newTask('Local')]);
      await store.flush();
      final beforeBoardId = store.activeBoardId;
      expect(store.settings.theme, isNot(ThemeModePref.dark));
      // A merge import never carries settings (see ImportPreflight.inspect), so
      // only overwrite exercises the values the rollback has to put back.
      final plan = store.previewImport(
        payload(newBoards('board-imported'), [
          taskJson('imported', 'board-imported', 'Imported'),
        ], settings: {'theme': 'dark'}),
        'overwrite',
      );
      expect(plan.settings?.theme, ThemeModePref.dark);
      barrier.armed = true;
      final importing = store.applyImport(plan);
      await barrier.enteredAt(0);
      barrier.release(0);
      // Nothing was accepted during the commit, so the failed import leaves no
      // trace of its own state behind.
      expect((await importing).success, isFalse);
      expect(store.settings.theme, isNot(ThemeModePref.dark));
      expect(store.activeBoardId, beforeBoardId);
      expect(store.boards.map((b) => b.id), isNot(contains('board-imported')));
      expect(store.tasks.map((t) => t.title), isNot(contains('Imported')));
      await expectConsistentTitles(store, ['Local']);
    },
  );

  test(
    'RF02 failed import does not roll back a credential accepted during its commit',
    () async {
      SharedPreferences.setMockInitialValues({});
      final barrier = SlotBarrier()..failSlot(0);
      final credentials = GatedCredentials();
      final store = await openStore(barrier: barrier, credentials: credentials);
      store.addTasks([store.newTask('Local')]);
      await store.flush();
      final plan = store.previewImport(
        payload(newBoards('board-imported'), [
          taskJson('imported', 'board-imported', 'Imported'),
        ], aiConfig: {
          'provider': 'custom',
          'protocol': 'openai-compatible',
          'customApiKey': 'synthetic-backup-key',
        }),
        'overwrite',
      );
      expect(plan.hasCredential, isTrue);
      barrier.armed = true;
      final importing = store.applyImport(plan, importCredential: true);
      await barrier.enteredAt(0);
      final accepted = await store.updateAIConfig(
        store.copyAIConfig()..apiKey = 'synthetic-newer',
      );
      expect(accepted, isTrue);
      barrier.release(0);
      expect((await importing).success, isFalse);
      // The backup key belongs to a batch that never committed; the newer
      // choice the user accepted after it must not be erased by the rollback.
      expect(credentials.value, 'synthetic-newer');
      expect(store.aiConfig.apiKey, 'synthetic-newer');
      expect(store.tasks.map((t) => t.title), isNot(contains('Imported')));
      store.dispose();
      final restarted = await openStore(credentials: credentials);
      expect(restarted.aiConfig.apiKey, 'synthetic-newer');
      expect(restarted.tasks.map((t) => t.title), contains('Local'));
      restarted.dispose();
    },
  );
}
