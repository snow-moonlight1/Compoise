import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/screens/startup_recovery_screen.dart';
import 'package:matrixflow_native/storage.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<Store> open({SaveWrite? writer}) async {
    final store = Store(saveWriter: writer);
    await store.init();
    await store.flush();
    return store;
  }

  Map<String, dynamic> payload({String title = 'new'}) => {
    'version': 2,
    'boards': [
      {'id': 'board-new', 'name': 'New', 'createdAt': 1},
    ],
    'tasks': [
      {
        'id': 'task-new',
        'boardId': 'board-new',
        'title': title,
        'quadrant': 2,
        'createdAt': 1,
        'subtasks': <Object>[],
      },
    ],
  };

  for (final failure in [1, 2]) {
    for (final throwsError in [false, true]) {
      test(
        'OS06 restart retains old batch after write $failure ${throwsError ? 'throws' : 'returns false'}',
        () async {
          SharedPreferences.setMockInitialValues({});
          final original = await open();
          original.addTasks([
            Task(
              id: 'old',
              boardId: original.boards.first.id,
              title: 'Old',
              quadrant: 1,
              createdAt: 1,
            ),
          ]);
          expect((await original.flush()).success, isTrue);
          original.dispose();
          var calls = 0;
          var armed = false;
          final failed = await open(
            writer: (key, value) async {
              if (armed) calls++;
              if (armed && calls == failure) {
                if (throwsError) throw StateError('synthetic failure');
                return false;
              }
              return (await SharedPreferences.getInstance()).setString(
                key,
                value,
              );
            },
          );
          armed = true;
          final plan = failed.previewImport(payload(), 'overwrite');
          final result = await failed.applyImport(plan);
          if (!result.success) {
            expect(failed.tasks.single.title, 'Old');
            failed.dispose();
            final restarted = await open();
            expect(restarted.tasks.single.title, 'Old');
            expect(restarted.boards.single.id, isNot('board-new'));
            restarted.dispose();
          } else {
            failed.dispose();
            final restarted = await open();
            expect(restarted.tasks.single.title, 'new');
            expect(restarted.boards.single.id, 'board-new');
            restarted.dispose();
          }
        },
      );
    }
  }

  test('OS06 failed save is observable and retry clears error', () async {
    SharedPreferences.setMockInitialValues({});
    var reject = false;
    final store = await open(
      writer: (key, value) async {
        if (reject && key == SaveProtocol.pointerKey) return false;
        return (await SharedPreferences.getInstance()).setString(key, value);
      },
    );
    reject = true;
    store.createBoard('Second');
    expect((await store.flush()).success, isFalse);
    expect(store.persistenceError, isNotNull);
    reject = false;
    expect((await store.retrySave()).success, isTrue);
    expect(store.persistenceError, isNull);
    store.dispose();
    final restarted = await open();
    expect(restarted.boards.any((b) => b.name == 'Second'), isTrue);
    restarted.dispose();
  });

  test(
    'OS06 overlapping commits serialize revisions and keep latest batch',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final gate = Completer<void>();
      var blocked = false;
      final protocol = SaveProtocol(
        prefs,
        writer: (key, value) async {
          if (!blocked && key == 'matrixflow-save-a') {
            blocked = true;
            await gate.future;
          }
          return prefs.setString(key, value);
        },
      );
      Map<String, String> values(String name) => {
        'matrixflow-tasks': '[]',
        'matrixflow-boards': jsonEncode([
          {'id': name, 'name': name, 'createdAt': 1},
        ]),
        'matrixflow-config': '{}',
        'matrixflow-settings': '{}',
        'matrixflow-active-board': name,
        'matrixflow-has-seen-onboarding': 'false',
      };
      final first = protocol.commit(values('first'));
      final second = protocol.commit(values('second'));
      gate.complete();
      expect((await first).revision, 1);
      expect((await second).revision, 2);
      final restored = SaveProtocol(prefs).load()!;
      expect(restored.revision, 2);
      expect(restored.values['matrixflow-active-board'], 'second');
    },
  );

  test(
    'OS06 mirror failure after commit restarts on complete new batch',
    () async {
      SharedPreferences.setMockInitialValues({});
      var rejectMirror = false;
      final store = await open(
        writer: (key, value) async {
          if (rejectMirror && key == 'matrixflow-active-board') return false;
          return (await SharedPreferences.getInstance()).setString(key, value);
        },
      );
      rejectMirror = true;
      final plan = store.previewImport(payload(), 'overwrite');
      expect((await store.applyImport(plan)).success, isTrue);
      store.dispose();
      final restarted = await open();
      expect(restarted.boards.single.id, 'board-new');
      expect(restarted.tasks.single.title, 'new');
      restarted.dispose();
    },
  );

  test(
    'OS06 simultaneous mutations coalesce into a consistent batch',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = await open();
      store.createBoard('Parallel');
      final boardId = store.activeBoardId;
      store.addTasks([
        Task(
          id: 'parallel-task',
          boardId: boardId,
          title: 'Parallel task',
          quadrant: 1,
          createdAt: 1,
        ),
      ]);
      expect((await store.flush()).success, isTrue);
      store.dispose();
      final restarted = await open();
      expect(restarted.tasks.single.boardId, restarted.boards.last.id);
      restarted.dispose();
    },
  );

  testWidgets('OS06 damaged commit pointer enters OS05 recovery screen', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      SaveProtocol.pointerKey: 'invalid',
    });
    final store = await open();
    addTearDown(store.dispose);
    expect(store.hasStartupRecovery, isTrue);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: store,
        child: const MaterialApp(home: StartupRecoveryScreen()),
      ),
    );
    expect(find.text(store.t['recoverySaveBatch']!), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  test(
    'OS07 preflight bounds, versions, duplicate children, orphans and empty backup',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = await open();
      expect(
        store.previewImport({'boards': [], 'tasks': []}, 'merge').warnings,
        contains('Empty backup'),
      );
      expect(
        () => store.previewImport({...payload(), 'version': 4}, 'overwrite'),
        throwsFormatException,
      );
      expect(
        () => ImportPreflight.decode(
          Uint8List(ImportPreflight.maxFileBytes + 1),
        ),
        throwsFormatException,
      );
      final nested =
          '${List.filled(13, '[').join()}${List.filled(13, ']').join()}';
      expect(
        () => ImportPreflight.decode(Uint8List.fromList(utf8.encode(nested))),
        throwsFormatException,
      );
      final duplicate = payload();
      (duplicate['tasks'] as List).first['subtasks'] = [
        {'id': 'child', 'title': 'one'},
        {'id': 'child', 'title': 'two'},
      ];
      expect(
        () => store.previewImport(duplicate, 'overwrite'),
        throwsFormatException,
      );
      expect(
        () => store.importData(duplicate, 'overwrite'),
        throwsFormatException,
      );
      final damaged = payload();
      (damaged['tasks'] as List).first.remove('id');
      expect(
        () => store.previewImport(damaged, 'overwrite'),
        throwsA(isA<CorruptDataPayloadException>()),
      );
      final tooManyBoards = payload();
      tooManyBoards['boards'] = List.generate(
        ImportPreflight.maxBoards + 1,
        (index) => {'id': 'board-$index', 'name': 'B', 'createdAt': 1},
      );
      expect(
        () => store.previewImport(tooManyBoards, 'overwrite'),
        throwsFormatException,
      );
      final orphan = payload();
      (orphan['tasks'] as List).first['boardId'] = 'absent';
      expect(
        () => store.previewImport(orphan, 'overwrite'),
        throwsFormatException,
      );
      expect(store.previewImport(orphan, 'merge').skipped, 1);
      final v1 = store.previewImport({...payload(), 'version': 1}, 'overwrite');
      expect(v1.warnings, isNotEmpty);
      final normalized = payload();
      (normalized['tasks'] as List).first['quadrant'] = 9;
      normalized['settings'] = {'urgencyThresholdDays': 99};
      expect(store.previewImport(normalized, 'overwrite').repaired, 2);
      final unknown = payload();
      (unknown['tasks'] as List).first['futureField'] = 1;
      expect(
        store.previewImport(unknown, 'merge').warnings,
        contains('Task 1: futureField'),
      );
      final duplicateBoard = payload();
      (duplicateBoard['boards'] as List).add({
        'id': 'board-new',
        'name': 'New',
        'createdAt': 1,
      });
      expect(store.previewImport(duplicateBoard, 'overwrite').skipped, 1);
      (duplicateBoard['boards'] as List).last['name'] = 'Different';
      expect(
        () => store.previewImport(duplicateBoard, 'overwrite'),
        throwsFormatException,
      );
      final duplicateTask = payload();
      (duplicateTask['tasks'] as List).add({
        'id': 'task-new',
        'boardId': 'board-new',
        'title': 'Different',
        'quadrant': 2,
        'createdAt': 1,
      });
      expect(
        () => store.previewImport(duplicateTask, 'merge'),
        throwsFormatException,
      );
      store.dispose();
    },
  );

  test(
    'OS07 cancelled preview leaves state; failed apply leaves old library',
    () async {
      SharedPreferences.setMockInitialValues({});
      var reject = false;
      final store = await open(
        writer: (key, value) async {
          if (reject && key == SaveProtocol.pointerKey) return false;
          return (await SharedPreferences.getInstance()).setString(key, value);
        },
      );
      final oldBoard = store.boards.single.id;
      final plan = store.previewImport(payload(), 'overwrite');
      expect(store.boards.single.id, oldBoard); // cancellation does not apply
      reject = true;
      expect((await store.applyImport(plan)).success, isFalse);
      expect(store.boards.single.id, oldBoard);
      store.dispose();
      final restarted = await open();
      expect(restarted.boards.single.id, oldBoard);
      restarted.dispose();
    },
  );

  test(
    'OS07 merge reports skips and conflicts without changing state',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = await open();
      final first = store.previewImport(payload(), 'merge');
      expect((await store.applyImport(first)).success, isTrue);
      final identical = store.previewImport(payload(), 'merge');
      expect(identical.skipped, 2);
      final conflict = store.previewImport(
        payload(title: 'different'),
        'merge',
      );
      expect(conflict.conflicts, 1);
      expect((await store.applyImport(conflict)).success, isFalse);
      expect(store.tasks.single.title, 'new');
      store.dispose();
    },
  );
}
