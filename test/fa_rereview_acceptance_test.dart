// RFA01. The probe in test/review/ keeps its original expectation.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/services/desktop_exit_coordinator.dart';
import 'package:matrixflow_native/storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'rf02_import_commit_race_test.dart' as fixture;

class GatedAlignment extends InMemoryReminderService {
  final entered = [Completer<void>(), Completer<void>()];
  final release = [Completer<void>(), Completer<void>()];
  int calls = 0;

  @override
  Future<void> alignToTasks(List<Task> tasks) async {
    final index = calls++;
    if (index < 2) {
      entered[index].complete();
      await release[index].future;
    }
    await super.alignToTasks(tasks);
  }
}

Future<Store> importingStore(GatedAlignment reminders) async {
  SharedPreferences.setMockInitialValues({});
  final store = Store(reminders: reminders);
  await store.init();
  await store.flush();
  final first = DateTime.now()
      .add(const Duration(days: 2))
      .millisecondsSinceEpoch;
  final plan = store.previewImport(
    fixture.payload(fixture.currentBoards(store), [
      {
        ...fixture.taskJson('imported', store.activeBoardId, 'Synthetic'),
        'reminderAt': first,
      },
    ]),
    'merge',
  );
  expect((await store.applyImport(plan)).success, isTrue);
  await reminders.entered[0].future;
  return store;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'RFA01 flush waits for a reminder repair accepted while it waits',
    () async {
      final reminders = GatedAlignment();
      final store = await importingStore(reminders);
      var flushDone = false;
      final flushing = store.flush(includeReminderLedger: true).then((result) {
        flushDone = true;
        return result;
      });
      final edited = Task.fromJson(store.tasks.single.toJson())
        ..reminderAt =
            store.tasks.single.reminderAt! +
            const Duration(days: 1).inMilliseconds;
      store.updateTask(edited);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      reminders.release[0].complete();
      await reminders.entered[1].future;
      await Future<void>.delayed(Duration.zero);
      expect(flushDone, isFalse);
      reminders.release[1].complete();
      final result = await flushing;
      expect(result.success, isTrue);
      expect(flushDone, isTrue);
      expect(reminders.scheduled.values.single.triggerAtMs, edited.reminderAt);
      await store.flush();
      store.dispose();
    },
  );

  test('RFA01 flush waits for a deletion accepted while it waits', () async {
    final reminders = GatedAlignment();
    final store = await importingStore(reminders);
    var flushDone = false;
    final flushing = store.flush(includeReminderLedger: true).then((result) {
      flushDone = true;
      return result;
    });
    store.deleteTask('imported');
    reminders.release[0].complete();
    await reminders.entered[1].future;
    expect(flushDone, isFalse);
    reminders.release[1].complete();
    expect((await flushing).success, isTrue);
    expect(
      reminders.scheduled.values.map((item) => item.taskId),
      isNot(contains('imported')),
    );
    store.dispose();
  });

  test(
    'RFA01 flush waits for a second import accepted while it waits',
    () async {
      final reminders = GatedAlignment();
      final store = await importingStore(reminders);
      var flushDone = false;
      final flushing = store.flush(includeReminderLedger: true).then((result) {
        flushDone = true;
        return result;
      });
      final secondWhen = DateTime.now()
          .add(const Duration(days: 4))
          .millisecondsSinceEpoch;
      final second = store.applyImport(
        store.previewImport(
          fixture.payload(fixture.currentBoards(store), [
            {
              ...fixture.taskJson('later', store.activeBoardId, 'Later'),
              'reminderAt': secondWhen,
            },
          ]),
          'merge',
        ),
      );
      reminders.release[0].complete();
      await reminders.entered[1].future;
      expect(flushDone, isFalse);
      reminders.release[1].complete();
      expect((await second).success, isTrue);
      expect((await flushing).success, isTrue);
      expect(
        reminders.scheduled.values.map((item) => item.triggerAtMs),
        contains(secondWhen),
      );
      store.dispose();
    },
  );

  test('RFA02 a library past both the count and file limits round-trips', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await fixture.openStore();
    addTearDown(store.dispose);
    for (var i = 0; i < ImportPreflight.maxBoards; i++) {
      store.createBoard('Extra $i');
    }
    final note = '整' * 3000000;
    store.addTasks([
      Task(
        id: 'giant',
        boardId: store.boards.last.id,
        title: 'Giant',
        quadrant: 1,
        createdAt: 1,
        notesMarkdown: note,
      ),
    ]);
    expect(store.boards.length, greaterThan(ImportPreflight.maxBoards));
    final bundle = await store.exportBackup();
    expect(bundle.recoverable, isTrue);
    expect(bundle.status, BackupStatus.recovery);
    expect(
      bundle.parts.every((part) => part.bytes <= ImportPreflight.maxFileBytes),
      isTrue,
    );
    SharedPreferences.setMockInitialValues({});
    final empty = Store();
    await empty.init();
    addTearDown(empty.dispose);
    for (var i = 0; i < bundle.parts.length; i++) {
      final plan = empty.previewImport(
        jsonDecode(bundle.parts[i].json) as Map<String, dynamic>,
        i == 0 ? 'overwrite' : 'merge',
      );
      expect((await empty.applyImport(plan)).success, isTrue, reason: 'part $i');
    }
    expect(empty.boards.length, store.boards.length);
    expect(empty.tasks.single.notesMarkdown, note);
    expect(empty.tasks.single.title, 'Giant');
    expect(empty.tasks.single.boardId, store.tasks.single.boardId);
  });

  test('RFA01 an exit timeout is not a successful save', () async {
    final reminders = GatedAlignment();
    final store = await importingStore(reminders);
    addTearDown(() {
      for (final gate in reminders.release) {
        if (!gate.isCompleted) gate.complete();
      }
      store.dispose();
    });
    final coordinator = DesktopExitSaveCoordinator(
      flush: () => store.flush(includeReminderLedger: true),
      retrySave: () => store.retrySave(includeReminderLedger: true),
      chooseAfterProblem: (_) async => DesktopExitSaveChoice.cancel,
      timeout: const Duration(milliseconds: 30),
    );
    expect(await coordinator.prepareToExit(), isFalse);
  });
}
