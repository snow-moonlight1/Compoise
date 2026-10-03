import 'dart:convert';

import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';

const String slotA = 'matrixflow-save-a';
const String slotB = 'matrixflow-save-b';
const String kTasks = 'matrixflow-tasks';
const String kBoards = 'matrixflow-boards';
const String kActiveBoard = 'matrixflow-active-board';
const String kOnboarding = 'matrixflow-has-seen-onboarding';

/// Lands batches in the current mock store and can refuse the commit point or
/// hold a payload, so a test can watch a save fail or arrive late.
class GatedWriter {
  GatedWriter({this.rejectPointer = false, this.hold = Duration.zero});

  final bool rejectPointer;
  final Duration hold;

  final List<String> batches = <String>[];
  final List<String> committed = <String>[];

  Future<SharedPreferences>? _prefs;

  Future<SharedPreferences> _handle() =>
      _prefs ??= SharedPreferences.getInstance();

  Future<bool> call(String key, String value) async {
    if (key == SaveProtocol.pointerKey && rejectPointer) return false;
    final isSlot = key == slotA || key == slotB;
    if (isSlot && hold > Duration.zero) {
      await Future<void>.delayed(hold);
    }
    final prefs = await _handle();
    final landed = await prefs.setString(key, value);
    if (isSlot) batches.add(value);
    if (key == SaveProtocol.pointerKey) committed.add(value);
    return landed;
  }
}

class BrokenPersistence extends StorePersistence {
  const BrokenPersistence();

  @override
  Future<SharedPreferences> open() => throw StateError('storage unavailable');
}

Board board(String id) => Board(id: id, name: id, createdAt: 1);

Task task(String id, String boardId) => Task(
  id: id,
  boardId: boardId,
  title: '任务 $id',
  quadrant: qDo,
  createdAt: 1,
);

Map<String, Object> legacySeed(String boardId, String taskId) =>
    <String, Object>{
      kBoards: jsonEncode(<Object?>[board(boardId).toJson()]),
      kTasks: jsonEncode(<Object?>[task(taskId, boardId).toJson()]),
      kActiveBoard: boardId,
      kOnboarding: true,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('a refused commit', () {
    test('keeps the library readable and reports the failure', () async {
      final writer = GatedWriter(rejectPointer: true);
      final (store, _) = await makeStore(
        boards: [board('board-r')],
        tasks: [task('reject-me', 'board-r')],
        saveWriter: writer.call,
      );
      expect(store.ready, isTrue);
      expect(store.tasks.map((item) => item.id), ['reject-me']);
      expect(writer.batches, hasLength(1), reason: 'the slot was written');
      expect(writer.committed, isEmpty, reason: 'the commit point was refused');
      expect(store.lastSaveResult.success, isFalse);
      expect(store.persistenceError, isNotNull);

      // Settling a failed save has to finish the attempt, not abandon it.
      await drainTestStores();
      expect(writer.batches, hasLength(1));
    });

    test('cannot poison the next case', () async {
      final (store, _) = await makeStore(
        boards: [board('board-clean')],
        tasks: [task('clean', 'board-clean')],
      );
      expect(store.tasks.map((item) => item.id), ['clean']);
      final prefs = await SharedPreferences.getInstance();
      final committed = SaveProtocol.readCommitted(prefs.get);
      expect(committed?.values[kTasks], isNot(contains('reject-me')));
    });
  });

  test('a queue disposed on the way writes nothing further and still drains', () async {
    final writer = GatedWriter();
    final (store, _) = await makeStore(
      boards: [board('board-d')],
      tasks: [task('kept', 'board-d')],
      saveWriter: writer.call,
    );
    expect(writer.batches, hasLength(1));

    store.addTasks([task('dropped', 'board-d')]);
    store.dispose();
    await drainTestStores();

    expect(
      writer.batches,
      hasLength(1),
      reason: 'dispose stops the queue before the next batch is derived',
    );
    expect(store.tasks.map((item) => item.id).toSet(), {'kept', 'dropped'});
  });

  test('a store whose init failed still drains and writes nothing', () async {
    final writer = GatedWriter();
    final store = Store(
      persistence: const BrokenPersistence(),
      saveWriter: writer.call,
    );
    registerTestStore(store);
    await store.init();
    expect(store.ready, isFalse);
    expect(store.startupError, isNotNull);

    await drainTestStores();

    expect(writer.batches, isEmpty);
    expect(writer.committed, isEmpty);
    store.dispose();
  });

  test('the drain never disposes, so a second dispose stays loud', () async {
    final (store, _) = await makeStore(
      boards: [board('board-x')],
      tasks: [task('x', 'board-x')],
    );
    // Throws if the helper had disposed the store under the test.
    store.dispose();
    expect(() => store.dispose(), throwsA(isA<FlutterError>()));
    await drainTestStores();
  });

  test('makeStore called twice in one case keeps the libraries apart', () async {
    final firstWriter = GatedWriter();
    final (first, _) = await makeStore(
      boards: [board('board-1')],
      tasks: [task('first', 'board-1')],
      saveWriter: firstWriter.call,
    );
    final (second, _) = await makeStore(
      boards: [board('board-2')],
      tasks: [task('second', 'board-2')],
    );

    expect(first.tasks.map((item) => item.id), ['first']);
    expect(second.tasks.map((item) => item.id), ['second']);
    expect(
      firstWriter.committed,
      hasLength(1),
      reason: 'the first library committed before the second case seed replaced it',
    );
    final prefs = await SharedPreferences.getInstance();
    final committed = SaveProtocol.readCommitted(prefs.get)?.values[kTasks];
    expect(committed, contains('second'));
    expect(committed, isNot(contains('first')));

    await drainTestStores();
  });

  test('an enrolled store the helper did not build is drained too', () async {
    final writer = GatedWriter(hold: const Duration(milliseconds: 40));
    SharedPreferences.setMockInitialValues(legacySeed('board-f', 'foreign'));
    final store = Store(saveWriter: writer.call);
    registerTestStore(store);
    await store.init();
    store.addTasks([task('late', 'board-f')]);

    await drainTestStores();

    final prefs = await SharedPreferences.getInstance();
    final committed = SaveProtocol.readCommitted(prefs.get)?.values[kTasks];
    expect(committed, allOf(contains('foreign'), contains('late')));
    store.dispose();
  });

  test('registering the same store twice drains it once', () async {
    final writer = GatedWriter(hold: const Duration(milliseconds: 20));
    SharedPreferences.setMockInitialValues(legacySeed('board-s', 'seeded'));
    final store = Store(saveWriter: writer.call);
    registerTestStore(store);
    registerTestStore(store);
    await store.init();
    store.updateSettings((settings) => settings..hideCompleted = true);

    await drainTestStores();
    final batchesAfterDrain = writer.batches.length;

    await drainTestStores();
    expect(writer.batches, hasLength(batchesAfterDrain));
    store.dispose();
  });

  testWidgets(
    'a fake-clock case converges at creation and settles on request',
    (tester) async {
      final writer = GatedWriter();
      late Store store;
      await tester.runAsync(() async {
        store = (await makeStore(
          boards: [board('board-w')],
          tasks: [task('w', 'board-w')],
          saveWriter: writer.call,
        )).$1;
        expect(store.tasks.map((item) => item.id), ['w']);
        expect(
          writer.committed,
          hasLength(1),
          reason: 'the initial commit lands before makeStore returns',
        );

        store.addTasks([task('late-w', 'board-w')]);
        await store.flush(waitForReminders: false);
        expect(writer.committed, hasLength(2));
        final prefs = await SharedPreferences.getInstance();
        expect(
          SaveProtocol.readCommitted(prefs.get)?.values[kTasks],
          allOf(contains('w'), contains('late-w')),
        );
      });
      store.dispose();
    },
  );

  test('the case after a widget case still starts from its own seed', () async {
    final (store, _) = await makeStore(
      boards: [board('board-after-widget')],
      tasks: [task('after-widget', 'board-after-widget')],
    );
    expect(store.tasks.map((item) => item.id), ['after-widget']);
    final prefs = await SharedPreferences.getInstance();
    expect(
      SaveProtocol.readCommitted(prefs.get)?.values[kTasks],
      isNot(contains('late-w')),
    );
  });
}
