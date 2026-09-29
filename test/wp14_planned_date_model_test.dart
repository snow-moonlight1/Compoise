import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/planned_policy.dart';
import 'package:matrixflow_native/storage.dart';

import 'helpers.dart';

/// WP14: `plannedDate` is a v2 task field, so an older library, an older backup
/// and a v1 downgrade export all have to keep working around its absence.
Map<String, dynamic> _taskJson([Map<String, dynamic> override = const {}]) => {
  'id': 't1',
  'boardId': 'b-1',
  'title': 'Write the plan',
  'quadrant': qPlan,
  'isLongTerm': false,
  'completed': false,
  'createdAt': 1700000000000,
  'subtasks': <Map<String, dynamic>>[],
  ...override,
};

Task _task({String id = 't1', String boardId = 'b-1', int? plannedDate}) =>
    Task(
      id: id,
      boardId: boardId,
      title: 'Write the plan',
      quadrant: qPlan,
      createdAt: 1700000000000,
      plannedDate: plannedDate,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WP14 plannedDate serialization', () {
    test('a stored plan survives a v2 round trip', () {
      final plan = plannedDayMs(DateTime(2026, 3, 5, 14, 30))!;
      final json = _task(plannedDate: plan).toJson();
      expect(json['plannedDate'], plan);
      expect(Task.fromJson(json).plannedDate, plan);
    });

    test('an unplanned task writes no key', () {
      expect(Task.fromJson(_taskJson()).plannedDate, isNull);
      expect(_task().toJson().containsKey('plannedDate'), isFalse);
    });

    test('a v1 downgrade export leaves the plan out', () {
      final json = _task(plannedDate: 1772000000000).toJson(targetVersion: 1);
      expect(json.containsKey('plannedDate'), isFalse);
    });

    test('a record that carries both dates keeps them separate', () {
      final task = Task.fromJson(
        _taskJson({
          'deadline': 1772294399000,
          'plannedDate': 1772000000000,
        }),
      );
      expect(task.deadline, 1772294399000);
      expect(task.plannedDate, 1772000000000);
    });

    test('a non-numeric plan is refused by the reader', () {
      expect(
        () => Task.fromJson(_taskJson({'plannedDate': 'tomorrow'})),
        throwsFormatException,
      );
    });

    test('a subtask has no plan of its own', () {
      expect(
        SubTask.fromJson({'id': 's1', 'title': 'step'}).toJson().keys,
        isNot(contains('plannedDate')),
      );
    });
  });

  group('WP14 plannedDate through the Store', () {
    test('export keeps the plan, a v1 export drops it', () async {
      final plan = plannedDayMs(DateTime(2026, 3, 5))!;
      final (store, _) = await makeStore(
        boards: [Board(id: 'b-1', name: 'Board', createdAt: 1000)],
        tasks: [_task(plannedDate: plan)],
      );
      addTearDown(store.dispose);

      final restored = ExportData.fromJson(
        jsonOf(store.exportJson()),
      ).tasks.single;
      expect(restored.plannedDate, plan);

      final downgraded = ExportData.fromJson(
        jsonOf(store.exportJson(version: 1)),
      ).tasks.single;
      expect(downgraded.plannedDate, isNull);
    });

    test('an update that touches another field keeps the plan', () async {
      final plan = plannedDayMs(DateTime(2026, 3, 5))!;
      final (store, _) = await makeStore(
        boards: [Board(id: 'b-1', name: 'Board', createdAt: 1000)],
        tasks: [_task(plannedDate: plan)],
      );
      addTearDown(store.dispose);

      store.updateTask(
        Task.fromJson(store.tasks.single.toJson())..title = 'Renamed',
      );
      expect(store.tasks.single.plannedDate, plan);
      expect(store.tasks.single.title, 'Renamed');
    });

    test('undoing a completion brings the plan back', () async {
      final plan = plannedDayMs(DateTime(2026, 3, 5))!;
      final (store, _) = await makeStore(
        boards: [Board(id: 'b-1', name: 'Board', createdAt: 1000)],
        tasks: [_task(plannedDate: plan)],
      );
      addTearDown(store.dispose);

      final undo = store.toggleCompleteWithUndo(store.tasks.single);
      expect(store.tasks.single.completed, isTrue);
      expect(store.applyUndo(undo!), isTrue);
      expect(store.tasks.single.plannedDate, plan);
    });

    test('a plan set in the evening is stored as that civil day', () async {
      final (store, _) = await makeStore(
        boards: [Board(id: 'b-1', name: 'Board', createdAt: 1000)],
        tasks: [_task()],
      );
      addTearDown(store.dispose);

      store.setPlannedDay('t1', DateTime(2026, 3, 5, 21, 10));
      expect(store.tasks.single.plannedDate, plannedDayMs(DateTime(2026, 3, 5)));
      expect((await store.flush()).success, isTrue);

      final reopened = Store();
      await reopened.init();
      addTearDown(reopened.dispose);
      expect(reopened.tasks.single.plannedDate, plannedDayMs(DateTime(2026, 3, 5)));
    });
  });

  group('WP14 import preflight', () {
    test('a planned backup re-imports without an unknown-field warning', () async {
      final (store, _) = await makeStore(
        boards: [Board(id: 'b-1', name: 'Board', createdAt: 1000)],
        tasks: [_task(plannedDate: plannedDayMs(DateTime(2026, 3, 5))!)],
      );
      addTearDown(store.dispose);

      final plan = store.previewImport(
        jsonOf(store.exportJson()),
        'overwrite',
      );
      expect(
        plan.warnings.where((warning) => warning.contains('plannedDate')),
        isEmpty,
      );
      expect((await store.applyImport(plan)).success, isTrue);
      expect(
        store.tasks.single.plannedDate,
        plannedDayMs(DateTime(2026, 3, 5)),
      );
    });

    test('a legacy file with no plan imports as unplanned', () async {
      final (store, _) = await makeStore();
      addTearDown(store.dispose);
      final plan = store.previewImport({
        'version': 1,
        'boards': [
          {'id': 'b-9', 'name': 'Imported', 'createdAt': 1000},
        ],
        'tasks': [_taskJson({'id': 'old', 'boardId': 'b-9'})],
      }, 'merge');

      expect((await store.applyImport(plan)).success, isTrue);
      expect(store.tasks.single.plannedDate, isNull);
    });

    test('a bad plan timestamp is refused before anything is written', () async {
      final (store, _) = await makeStore(
        boards: [Board(id: 'b-1', name: 'Board', createdAt: 1000)],
        tasks: [_task(plannedDate: plannedDayMs(DateTime(2026, 3, 5))!)],
      );
      addTearDown(store.dispose);

      expect(
        () => store.previewImport({
          'version': 2,
          'boards': [
            {'id': 'b-1', 'name': 'Board', 'createdAt': 1000},
          ],
          'tasks': [_taskJson({'plannedDate': 'tomorrow'})],
        }, 'merge'),
        throwsA(isA<FormatException>()),
      );
      expect(store.tasks.single.plannedDate, plannedDayMs(DateTime(2026, 3, 5)));
    });

    test('two same-id tasks differing only by plan are a conflict', () async {
      final (store, _) = await makeStore(
        boards: [Board(id: 'b-1', name: 'Board', createdAt: 1000)],
        tasks: [_task(plannedDate: plannedDayMs(DateTime(2026, 3, 5))!)],
      );
      addTearDown(store.dispose);

      final plan = store.previewImport(
        jsonOf(store.exportJson()),
        'merge',
      );
      // Same id and identical content: a skip, not a conflict.
      expect(plan.conflicts, 0);
      expect(plan.skipped, greaterThan(0));

      final changed = store.previewImport({
        'version': 2,
        'boards': [
          {'id': 'b-1', 'name': 'Board', 'createdAt': 1000},
        ],
        'tasks': [
          _taskJson({'plannedDate': plannedDayMs(DateTime(2026, 3, 6))}),
        ],
      }, 'merge');
      expect(changed.conflicts, greaterThan(0));
    });
  });
}

Map<String, dynamic> jsonOf(String source) =>
    jsonDecode(source) as Map<String, dynamic>;
