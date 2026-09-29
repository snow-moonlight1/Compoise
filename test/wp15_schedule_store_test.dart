import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/schedule_item.dart';
import 'package:matrixflow_native/storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const board = 'board';
  const otherBoard = 'other';
  const start = 1790701200000;
  const end = start + 3600000;

  Task task(String id, {String boardId = board}) => Task(
    id: id,
    boardId: boardId,
    title: id,
    quadrant: 2,
    createdAt: 1,
    plannedDate: 1790697600000,
    deadline: 1900000000000,
  );

  ScheduleItem block(String id, String taskId) => ScheduleItem.timeBlock(
    id: id,
    taskId: taskId,
    startAt: start,
    endAt: end,
    timeZoneId: 'Asia/Shanghai',
  );

  ScheduleItem linkedEvent(String id, String taskId) => ScheduleItem.event(
    id: id,
    title: 'Review',
    taskId: taskId,
    startAt: start,
    endAt: end,
    timeZoneId: 'Asia/Shanghai',
  );

  ScheduleItem boardEvent(String id, String boardId) => ScheduleItem.event(
    id: id,
    title: 'Meeting',
    boardId: boardId,
    startAt: start,
    endAt: end,
    timeZoneId: 'UTC',
  );

  Future<Store> open({SaveWrite? writer}) async {
    final store = Store(saveWriter: writer);
    await store.init();
    await store.flush();
    return store;
  }

  Future<Store> seeded() async {
    SharedPreferences.setMockInitialValues({
      'matrixflow-boards': jsonEncode([
        Board(id: board, name: 'Board', createdAt: 1).toJson(),
        Board(id: otherBoard, name: 'Other', createdAt: 1).toJson(),
      ]),
      'matrixflow-tasks': jsonEncode([task('a').toJson(), task('b').toJson()]),
    });
    return open();
  }

  /// Commits a batch whose schedule value is unreadable, and returns the
  /// pointer key with the exact bytes the library was left with.
  Future<(String, String)> commitDamagedSchedule(String rawSchedule) async {
    final store = await seeded();
    final prefs = await SharedPreferences.getInstance();
    final protocol = SaveProtocol(prefs);
    final values = Map<String, String>.from(protocol.load()!.values);
    values[SaveProtocol.scheduleKey] = rawSchedule;
    expect((await protocol.commit(values)).success, isTrue);
    final pointer = prefs.getString(SaveProtocol.pointerKey)!;
    final slot = prefs.getString(pointer)!;
    store.dispose();
    return (pointer, slot);
  }

  test(
    'old library migrates an absent schedule to an empty committed value',
    () async {
      final store = await seeded();
      addTearDown(store.dispose);
      expect(store.scheduleItems, isEmpty);
      expect(
        store.startupDataStates[SaveProtocol.scheduleKey],
        StartupDataState.missing,
      );
      final prefs = await SharedPreferences.getInstance();
      final values = SaveProtocol(prefs).load()!.values;
      expect(values[SaveProtocol.scheduleKey], '[]');
      expect(store.tasks.first.plannedDate, task('a').plannedDate);
      expect(store.tasks.first.deadline, task('a').deadline);
    },
  );

  test(
    'task and schedule persist in one committed slot and reload together',
    () async {
      final store = await seeded();
      store.addScheduleItem(block('block', 'a'));
      store.addScheduleItem(linkedEvent('linked', 'a'));
      store.addScheduleItem(boardEvent('event', board));
      expect((await store.flush()).success, isTrue);
      final prefs = await SharedPreferences.getInstance();
      final values = SaveProtocol(prefs).load()!.values;
      expect(
        jsonDecode(values[SaveProtocol.scheduleKey]!) as List,
        hasLength(3),
      );
      expect(jsonDecode(values['matrixflow-tasks']!) as List, hasLength(2));
      store.dispose();
      final reopened = await open();
      addTearDown(reopened.dispose);
      expect(reopened.scheduleItems.map((item) => item.id), [
        'block',
        'linked',
        'event',
      ]);
      expect(reopened.tasks.first.plannedDate, task('a').plannedDate);
    },
  );

  test(
    'an old committed slot ignores a newer schedule compatibility mirror',
    () async {
      final original = await seeded();
      final prefs = await SharedPreferences.getInstance();
      final values = Map<String, String>.from(
        SaveProtocol(prefs).load()!.values,
      )..remove(SaveProtocol.scheduleKey);
      final protocol = SaveProtocol(prefs);
      expect((await protocol.commit(values)).success, isTrue);
      await prefs.setString(
        SaveProtocol.scheduleKey,
        jsonEncode([block('uncommitted', 'a').toJson()]),
      );
      original.dispose();
      final reopened = await open();
      addTearDown(reopened.dispose);
      expect(reopened.scheduleItems, isEmpty);
      expect(
        reopened.startupDataStates[SaveProtocol.scheduleKey],
        StartupDataState.missing,
      );
    },
  );

  test(
    'bad saved IANA zone protects original slot and surfaces recovery',
    () async {
      final original = await seeded();
      final prefs = await SharedPreferences.getInstance();
      final protocol = SaveProtocol(prefs);
      final values = Map<String, String>.from(protocol.load()!.values);
      values[SaveProtocol.scheduleKey] = jsonEncode([
        {...block('bad', 'a').toJson(), 'timeZoneId': 'Unknown/Zone'},
      ]);
      expect((await protocol.commit(values)).success, isTrue);
      final pointer = prefs.getString(SaveProtocol.pointerKey)!;
      final savedSlot = prefs.getString(pointer)!;
      original.dispose();

      final reopened = await open();
      addTearDown(reopened.dispose);
      expect(reopened.hasStartupRecovery, isTrue);
      expect(reopened.recoveryKeys, contains(SaveProtocol.scheduleKey));
      expect(reopened.scheduleItems, isEmpty);
      expect(prefs.getString(pointer), savedSlot);
      expect(reopened.recoveryCopyJson(), contains('Unknown/Zone'));
      expect(
        () => reopened.addScheduleItem(block('new', 'a')),
        throwsStateError,
      );
    },
  );

  test(
    'revision checks reject stale edits; duplicate and orphan references fail',
    () async {
      final store = await seeded();
      addTearDown(store.dispose);
      final first = block('block', 'a');
      store.addScheduleItem(first);
      final revision = store.scheduleRevision(first.id);
      expect(
        store.updateScheduleItem(first, expectedRevision: revision),
        isTrue,
      );
      expect(store.scheduleRevision(first.id), revision);
      final changed = ScheduleItem.timeBlock(
        id: first.id,
        taskId: 'a',
        startAt: start + 1000,
        endAt: end + 1000,
        timeZoneId: 'Asia/Shanghai',
      );
      expect(
        store.updateScheduleItem(changed, expectedRevision: revision),
        isTrue,
      );
      expect(
        store.updateScheduleItem(first, expectedRevision: revision),
        isFalse,
      );
      expect(
        () => store.updateScheduleItem(
          block('block', 'missing'),
          expectedRevision: store.scheduleRevision(first.id),
        ),
        throwsFormatException,
      );
      expect(
        store.deleteScheduleItem(first.id, expectedRevision: revision),
        isFalse,
      );
      expect(
        store.deleteScheduleItem(
          first.id,
          expectedRevision: store.scheduleRevision(first.id),
        ),
        isTrue,
      );
      expect(
        () => store.addScheduleItem(block('orphan', 'child-only')),
        throwsFormatException,
      );
      expect(
        () => store.addScheduleItem(boardEvent('orphan-board', 'missing')),
        throwsFormatException,
      );
      store.addScheduleItem(block('same', 'a'));
      expect(
        () => store.addScheduleItem(block('same', 'b')),
        throwsFormatException,
      );
    },
  );

  test(
    'completion retains links; delete and undo restore exactly those links',
    () async {
      final store = await seeded();
      addTearDown(store.dispose);
      store.addScheduleItem(block('block', 'a'));
      store.addScheduleItem(linkedEvent('linked', 'a'));
      store.addScheduleItem(boardEvent('independent', board));
      final plan = task('a');
      store.setParentCompleted(
        store.tasks.firstWhere((t) => t.id == 'a'),
        true,
      );
      expect(store.scheduleItems, hasLength(3));
      final snapshot = store.deleteTaskWithUndo('a')!;
      expect(store.scheduleItems.map((item) => item.id), ['independent']);
      expect(store.applyUndo(snapshot), isTrue);
      expect(store.scheduleItems.map((item) => item.id), [
        'independent',
        'block',
        'linked',
      ]);
      expect(
        store.tasks.firstWhere((t) => t.id == 'a').plannedDate,
        plan.plannedDate,
      );
      expect(
        store.tasks.firstWhere((t) => t.id == 'a').deadline,
        plan.deadline,
      );
      store.deleteTask('a');
      expect(store.scheduleItems.map((item) => item.id), ['independent']);
      expect((await store.flush()).success, isTrue);
    },
  );

  test(
    'grouping re-parents links; board move follows task without changing item',
    () async {
      final store = await seeded();
      addTearDown(store.dispose);
      store.addScheduleItem(block('block', 'a'));
      store.addScheduleItem(linkedEvent('linked', 'b'));
      final parent = store.groupTasks({'a', 'b'}, 'Group');
      expect(store.scheduleItems.map((item) => item.taskId), [
        parent.id,
        parent.id,
      ]);
      expect(store.scheduleItems.map((item) => item.id), ['block', 'linked']);
      final before = store.scheduleItems.first.toJson();
      store.updateTask(Task.fromJson(parent.toJson())..boardId = otherBoard);
      expect(store.tasks.single.boardId, otherBoard);
      expect(store.scheduleItems.first.toJson(), before);
      expect((await store.flush()).success, isTrue);
    },
  );

  test(
    'clear paths and board deletion remove linked and independent records',
    () async {
      final store = await seeded();
      addTearDown(store.dispose);
      store.addScheduleItem(block('a-block', 'a'));
      store.addScheduleItem(block('b-block', 'b'));
      store.addScheduleItem(boardEvent('own', board));
      store.clearQuadrant(2, boardId: board);
      expect(store.scheduleItems.map((item) => item.id), ['own']);
      store.addTasks([task('c')]);
      store.addScheduleItem(block('c-block', 'c'));
      expect(store.clearBoard(board), 1);
      expect(store.scheduleItems.map((item) => item.id), ['own']);
      store.deleteBoard(board);
      expect(store.scheduleItems, isEmpty);
      expect((await store.flush()).success, isTrue);
    },
  );

  test(
    'failed commit keeps task and schedule together; retry persists both',
    () async {
      SharedPreferences.setMockInitialValues({});
      var reject = false;
      final store = await open(
        writer: (key, value) async {
          if (reject && key == SaveProtocol.pointerKey) return false;
          return (await SharedPreferences.getInstance()).setString(key, value);
        },
      );
      reject = true;
      store.addTasks([task('new', boardId: store.activeBoardId)]);
      store.addScheduleItem(block('new-block', 'new'));
      expect((await store.flush()).success, isFalse);
      expect(store.persistenceError, isNotNull);
      final old = await open();
      expect(old.tasks, isEmpty);
      expect(old.scheduleItems, isEmpty);
      old.dispose();
      reject = false;
      expect((await store.retrySave()).success, isTrue);
      store.dispose();
      final reopened = await open();
      addTearDown(reopened.dispose);
      expect(reopened.tasks.single.id, 'new');
      expect(reopened.scheduleItems.single.id, 'new-block');
    },
  );

  test(
    'failed legacy overwrite rolls schedule back with task and board',
    () async {
      SharedPreferences.setMockInitialValues({});
      var reject = false;
      final store = await open(
        writer: (key, value) async {
          if (reject && key == SaveProtocol.pointerKey) return false;
          return (await SharedPreferences.getInstance()).setString(key, value);
        },
      );
      store.addTasks([task('old', boardId: store.activeBoardId)]);
      store.addScheduleItem(block('old-block', 'old'));
      await store.flush();
      reject = true;
      final plan = store.previewImport({
        'version': 2,
        'boards': [
          {'id': 'new-board', 'name': 'New', 'createdAt': 1},
        ],
        'tasks': [task('imported', boardId: 'new-board').toJson()],
      }, 'overwrite');
      final result = await store.applyImport(plan);
      expect(result.success, isFalse);
      expect(store.tasks.single.id, 'old');
      expect(store.scheduleItems.single.id, 'old-block');
      store.dispose();
      final reopened = await open();
      addTearDown(reopened.dispose);
      expect(reopened.tasks.single.id, 'old');
      expect(reopened.scheduleItems.single.id, 'old-block');
    },
  );

  test('orphaned saved link is recovery data, not a dropped record', () async {
    SharedPreferences.setMockInitialValues({
      'matrixflow-boards': jsonEncode([
        Board(id: board, name: 'Board', createdAt: 1).toJson(),
      ]),
      'matrixflow-tasks': '[]',
      SaveProtocol.scheduleKey: jsonEncode([block('orphan', 'gone').toJson()]),
    });
    final store = await open();
    addTearDown(store.dispose);
    expect(store.hasStartupRecovery, isTrue);
    expect(store.recoveryKeys, contains(SaveProtocol.scheduleKey));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(SaveProtocol.scheduleKey), contains('orphan'));
  });

  test('legacy merge retains schedule; overwrite clears it', () async {
    final store = await seeded();
    addTearDown(store.dispose);
    store.addScheduleItem(block('old-block', 'a'));
    final payload = {
      'version': 2,
      'boards': [
        {'id': 'new-board', 'name': 'New', 'createdAt': 1},
      ],
      'tasks': [task('imported', boardId: 'new-board').toJson()],
    };
    expect(
      (await store.applyImport(store.previewImport(payload, 'merge'))).success,
      isTrue,
    );
    expect(store.scheduleItems.single.id, 'old-block');
    expect(
      (await store.applyImport(
        store.previewImport(payload, 'overwrite'),
      )).success,
      isTrue,
    );
    expect(store.scheduleItems, isEmpty);
    expect((await store.flush()).success, isTrue);
  });

  test('malformed schedule JSON in a committed slot enters recovery', () async {
    final damaged = await commitDamagedSchedule('{not json');
    final reopened = await open();
    addTearDown(reopened.dispose);
    expect(reopened.hasStartupRecovery, isTrue);
    expect(reopened.recoveryKeys, contains(SaveProtocol.scheduleKey));
    expect(reopened.scheduleItems, isEmpty);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(damaged.$1), damaged.$2);
    expect(reopened.recoveryCopyJson(), contains('{not json'));
  });

  test('a duplicated schedule id in a committed slot enters recovery',
      () async {
        final damaged = await commitDamagedSchedule(
          jsonEncode([block('dup', 'a').toJson(), block('dup', 'b').toJson()]),
        );
        final reopened = await open();
        addTearDown(reopened.dispose);
        expect(reopened.hasStartupRecovery, isTrue);
        expect(reopened.recoveryKeys, contains(SaveProtocol.scheduleKey));
        expect(reopened.scheduleItems, isEmpty);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString(damaged.$1), damaged.$2);
        expect(reopened.tasks, hasLength(2));
      });

  test('a damaged schedule is only cleared after an explicit discard',
      () async {
        SharedPreferences.setMockInitialValues({
          'matrixflow-boards': jsonEncode([
            Board(id: board, name: 'Board', createdAt: 1).toJson(),
          ]),
          'matrixflow-tasks': jsonEncode([task('a').toJson()]),
          SaveProtocol.scheduleKey: jsonEncode([
            block('orphan', 'gone').toJson(),
          ]),
        });
        final store = await open();
        addTearDown(store.dispose);
        expect(store.hasStartupRecovery, isTrue);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString(SaveProtocol.scheduleKey), contains('orphan'));
        expect(store.tasks.single.id, 'a');

        expect(await store.discardDamagedStartupData(), isTrue);
        expect((await store.flush()).success, isTrue);
        expect(store.hasStartupRecovery, isFalse);
        expect(store.scheduleItems, isEmpty);
        expect(store.tasks.single.id, 'a');
        expect(store.tasks.single.plannedDate, task('a').plannedDate);
        expect(
          SaveProtocol(prefs).load()!.values[SaveProtocol.scheduleKey],
          '[]',
        );

        final reopened = await open();
        addTearDown(reopened.dispose);
        expect(reopened.hasStartupRecovery, isFalse);
        expect(reopened.scheduleItems, isEmpty);
        expect(reopened.tasks.single.id, 'a');
      });
}
