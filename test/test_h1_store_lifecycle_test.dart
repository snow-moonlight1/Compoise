import 'dart:async';
import 'dart:convert';

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

/// Writes the Store's batches into the mock platform store and can hold every
/// whole-library payload for a fixed time first.
///
/// The hold is a fixture that keeps a case owing a write, never a wait that
/// makes an assertion pass: [commitLanded] completes when the batch really
/// reached storage.
class HoldingSaveWriter {
  HoldingSaveWriter({this.hold = Duration.zero});

  final Duration hold;

  /// Slot payloads, in the order they reached storage.
  final List<String> batches = <String>[];

  /// Save pointers that reached storage, i.e. commits a later reader can find.
  final List<String> committed = <String>[];

  Future<SharedPreferences>? _prefs;
  Completer<void>? _landing;

  /// Completes once the first commit point has landed; already done if a batch
  /// landed before anyone started waiting.
  Future<void> get commitLanded => (_landing ??= Completer<void>()).future;

  Future<SharedPreferences> _handle() =>
      _prefs ??= SharedPreferences.getInstance();

  Future<bool> call(String key, String value) async {
    final isSlot = key == slotA || key == slotB;
    if (isSlot && hold > Duration.zero) {
      await Future<void>.delayed(hold);
    }
    final prefs = await _handle();
    final landed = await prefs.setString(key, value);
    if (isSlot) batches.add(value);
    if (key == SaveProtocol.pointerKey) {
      committed.add(value);
      final landing = _landing ??= Completer<void>();
      if (!landing.isCompleted) landing.complete();
    }
    return landed;
  }
}

Task libraryTask(String id, String boardId) => Task(
  id: id,
  boardId: boardId,
  title: '任务 $id',
  quadrant: qDo,
  createdAt: 1,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Shared by the two cases below: the second one has to observe what the
  // first one still owed storage.
  final caseASave = HoldingSaveWriter(hold: const Duration(milliseconds: 150));

  group('a finished case cannot leave a whole-library save open', () {
    test('case A seeds its own library through the helper', () async {
      final (store, _) = await makeStore(
        boards: [Board(id: 'board-a', name: 'A', createdAt: 1)],
        tasks: [libraryTask('leak-me', 'board-a')],
        saveWriter: caseASave.call,
      );
      final caseALibrary = store.tasks.map((task) => task.id).toList();
      expect(store.ready, isTrue);
      expect(caseALibrary, ['leak-me']);
    });

    test('case B boots from its own seed only', () async {
      expect(
        caseASave.committed,
        isNotEmpty,
        reason:
            "case A's save has to reach storage before the next case resets "
            'the mock; a held handle writes into whatever store is current.',
      );

      SharedPreferences.setMockInitialValues(<String, Object>{
        kTasks: jsonEncode(<Object?>[libraryTask('case-b', 'board-b').toJson()]),
        kBoards: jsonEncode(
          <Object?>[Board(id: 'board-b', name: 'B', createdAt: 1).toJson()],
        ),
        kActiveBoard: 'board-b',
        kOnboarding: true,
      });

      // Case A still owes this save: it lands here, into the generation case B
      // already installed, the way a slow disk would.
      await caseASave.commitLanded;
      final prefs = await SharedPreferences.getInstance();
      expect(
        SaveProtocol.readCommitted(prefs.get)?.values[kTasks],
        isNot(contains('leak-me')),
        reason: 'a finished case must not commit into the next library',
      );

      final store = Store();
      addTearDown(store.dispose);
      await store.init();
      expect(store.hasStartupRecovery, isFalse);
      expect(store.tasks.map((task) => task.id), ['case-b']);
    });
  });

  test('the helper returns a store whose initial commit already landed', () async {
    final writer = HoldingSaveWriter();
    final (store, _) = await makeStore(
      boards: [Board(id: 'board-q', name: 'Q', createdAt: 1)],
      tasks: [libraryTask('quiet', 'board-q')],
      saveWriter: writer.call,
    );
    expect(store.tasks.map((task) => task.id), ['quiet']);
    expect(writer.committed, hasLength(1));
    expect(store.lastSaveResult.revision, 1);
    expect(store.persistenceError, isNull);
  });

  test('one held handle can write into the next mock generation', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      SaveProtocol.pointerKey: slotA,
    });
    final held = await SharedPreferences.getInstance();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    expect(await held.setString(slotA, 'from-the-previous-case'), isTrue);
    final next = await SharedPreferences.getInstance();
    expect(next.getString(slotA), 'from-the-previous-case');
  });
}
