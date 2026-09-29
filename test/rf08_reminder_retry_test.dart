// RF08 default regression: the reminder retry ledger must be bounded, durable
// and honest. Synthetic tasks, in-memory ledgers and a fake platform only: no
// credentials, no real notifications and no device claims.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Platform double: an accepted schedule stays pending until cancelled, and
/// every call is recorded so "did we ask again" can be answered.
class CountingPlugin implements FlutterLocalNotificationsPlugin {
  bool failSchedule = true;
  bool failCancel = false;
  final List<Symbol> calls = [];
  final Set<int> nativePending = {};

  int countOf(Symbol name) => calls.where((c) => c == name).length;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = invocation.memberName;
    calls.add(name);
    if (name == #initialize) return Future<bool?>.value(true);
    if (name == #resolvePlatformSpecificImplementation) return null;
    if (name == #zonedSchedule || name == #show) {
      if (failSchedule) {
        return Future<void>.error(StateError('synthetic schedule rejection'));
      }
      nativePending.add(invocation.positionalArguments.first as int);
      return Future<void>.value();
    }
    if (name == #cancel) {
      if (failCancel) {
        return Future<void>.error(StateError('synthetic cancel rejection'));
      }
      nativePending.remove(invocation.positionalArguments.first as int);
      return Future<void>.value();
    }
    if (name == #cancelAll) {
      nativePending.clear();
      return Future<void>.value();
    }
    return Future<void>.value();
  }
}

/// Ledger that can be blocked, made to fail, or seeded with raw JSON.
class ScriptedLedgerStore implements ReminderLedgerStore {
  ScriptedLedgerStore({this.seed});

  String? value;
  String? seed;
  int writeCount = 0;
  int readCount = 0;
  bool written = false;
  bool failWrites = false;
  bool failReads = false;
  Completer<void>? holdWrites;
  Completer<String?>? holdRead;

  @override
  Future<String?> read() async {
    readCount++;
    final held = holdRead;
    if (held != null) return held.future;
    if (failReads) throw StateError('synthetic ledger read failure');
    // A completed write, including a removal, is authoritative.
    return written ? value : seed;
  }

  @override
  Future<void> write(String? next) async {
    final held = holdWrites;
    if (held != null) await held.future;
    writeCount++;
    if (failWrites) throw StateError('synthetic ledger write failure');
    value = next;
    written = true;
  }
}

Task _task(String id, {int? reminderAt, bool completed = false}) => Task(
  id: id,
  boardId: 'b1',
  title: 'Synthetic $id',
  quadrant: 1,
  createdAt: 1,
  reminderAt: reminderAt,
  completed: completed,
);

int _id(String taskId) => generateNotificationId(taskId);
int _nowMs() => DateTime.now().millisecondsSinceEpoch;
String _key(String taskId) => 'reschedule:${_id(taskId)}';

Future<FlutterLocalNotificationsReminderService> _service(
  CountingPlugin plugin,
  ReminderLedgerStore ledger,
) async {
  final service = FlutterLocalNotificationsReminderService(
    plugin: plugin,
    ledgerStore: ledger,
  );
  await service.init();
  return service;
}

/// Reminder work is fired without being awaited, so let the operation chain and
/// the queued ledger write settle before reading real state.
Future<void> _settle(ReminderService service) async {
  for (var i = 0; i < 6; i++) {
    await Future<void>.delayed(Duration.zero);
  }
  await service.pendingLedgerWrites();
}

/// A Store wired to the reminder service under test, so the startup
/// coordination and the exit barrier act on the same ledger.
Future<Store> _storeWith(ReminderService service, List<Task> tasks) async {
  SharedPreferences.setMockInitialValues({
    'matrixflow-boards': jsonEncode([
      Board(id: 'b1', name: 'Board', createdAt: 1).toJson(),
    ]),
    'matrixflow-tasks': jsonEncode(tasks.map((t) => t.toJson()).toList()),
  });
  final store = Store(
    reminders: service,
    saveWriter: (key, value) async =>
        (await SharedPreferences.getInstance()).setString(key, value),
  );
  await store.init();
  return store;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    ReminderService.resetForTest();
  });

  group('RF08 a restart may not renew the automatic retry budget', () {
    test('six failing starts spend one attempt each and then stop asking', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final ledger = InMemoryReminderLedgerStore();
      final plugin = CountingPlugin();
      final trigger = _nowMs() + 600000;
      final tasks = [_task('t1', reminderAt: trigger)];

      // The user edit that armed the reminder was rejected by the platform.
      final first = await _service(plugin, ledger);
      await first.scheduleReminder(
        boardId: 'b1',
        taskId: 't1',
        title: 'Synthetic t1',
        triggerAtMs: trigger,
      );
      await _settle(first);
      expect(
        first.pendingJobs[_key('t1')]!.firstFailedAtMs,
        isNotNull,
        reason: 'the first failure is remembered',
      );

      // Six cold starts: load -> rebuild future reminders -> reconcile -> persist.
      final attempts = <int>[];
      final ages = <int>[];
      for (var start = 1; start <= 6; start++) {
        final service = await _service(plugin, ledger);
        final before = plugin.countOf(#zonedSchedule);
        await service.rescheduleAllFuture(tasks);
        await service.reconcilePending(tasks);
        await _settle(service);
        final record = service.pendingJobs[_key('t1')];
        attempts.add(record?.attempts ?? -1);
        ages.add((_nowMs() - (record?.firstFailedAtMs ?? 0)) ~/ 1000);
        expect(
          service.scheduleFailures.value,
          hasLength(1),
          reason: 'start $start must keep the unarmed reminder visible',
        );
        expect(
          (plugin.countOf(#zonedSchedule) - before) ~/ 3,
          lessThanOrEqualTo(1),
          reason: 'start $start may count one attempt, not two for one cycle',
        );
      }

      expect(
        attempts,
        equals([1, 2, 3, 4, 5, 5]),
        reason: 'a restart grows the spent budget instead of resetting it',
      );
      expect(
        ages.every((age) => age <= ages.first + 2),
        isTrue,
        reason: 'the first failure time is never pushed forward by a retry',
      );
    });

    test('a spent budget survives a restart as an exhausted visible record', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final ledger = InMemoryReminderLedgerStore();
      final plugin = CountingPlugin();
      final trigger = _nowMs() + 600000;
      final tasks = [_task('t1', reminderAt: trigger)];

      final first = await _service(plugin, ledger);
      await first.scheduleReminder(
        boardId: 'b1',
        taskId: 't1',
        title: 'Synthetic t1',
        triggerAtMs: trigger,
      );
      await _settle(first);

      for (var start = 0; start < ReminderService.maxAutomaticRetries + 2; start++) {
        final service = await _service(plugin, ledger);
        await service.rescheduleAllFuture(tasks);
        await service.reconcilePending(tasks);
        await _settle(service);
      }

      // A new process reading the persisted ledger sees the same state.
      final afterRestart = await _service(plugin, ledger);
      await afterRestart.loadPendingJobs();
      final record = afterRestart.pendingJobs[_key('t1')]!;
      expect(record.attempts, ReminderService.maxAutomaticRetries);
      expect(record.exhausted, isTrue);
      expect(afterRestart.scheduleFailures.value.values.single.taskId, 't1');
      expect(afterRestart.ledgerIssue.value, isNull);

      final callsWhenExhausted = plugin.countOf(#zonedSchedule);
      await afterRestart.rescheduleAllFuture(tasks);
      final report = await afterRestart.reconcilePending(tasks);
      expect(report.retried, 0);
      expect(report.exhausted, 1);
      expect(
        plugin.countOf(#zonedSchedule),
        callsWhenExhausted,
        reason: 'an exhausted generation is not offered to the platform again',
      );
    });

    test('only a real reminder change or a user retry opens a new generation', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final service = await _service(
        CountingPlugin(),
        InMemoryReminderLedgerStore(),
      );
      final trigger = _nowMs() + 600000;
      // The user edit that armed the reminder was rejected.
      await service.scheduleReminder(
        boardId: 'b1',
        taskId: 't1',
        title: 'Synthetic t1',
        triggerAtMs: trigger,
      );
      for (var pass = 1; pass <= ReminderService.maxAutomaticRetries; pass++) {
        await service.reconcilePending([_task('t1', reminderAt: trigger)]);
      }
      final spent = service.pendingJobs[_key('t1')]!;
      expect(spent.exhausted, isTrue);
      final spentSince = spent.firstFailedAtMs;

      // An unrelated edit is the same generation, so it stays exhausted.
      await service.scheduleReminder(
        boardId: 'b1',
        taskId: 't1',
        title: 'Renamed by the user',
        triggerAtMs: trigger,
      );
      expect(service.pendingJobs[_key('t1')]!.exhausted, isTrue);
      expect(service.pendingJobs[_key('t1')]!.firstFailedAtMs, spentSince);

      // A user-requested retry is a new generation with a fresh budget.
      await service.scheduleReminder(
        boardId: 'b1',
        taskId: 't1',
        title: 'Synthetic t1',
        triggerAtMs: trigger,
        userInitiated: true,
      );
      final restarted = service.pendingJobs[_key('t1')]!;
      expect(restarted.exhausted, isFalse);
      expect(restarted.attempts, 0);
      expect(restarted.firstFailedAtMs, isNot(spentSince));

      // A changed trigger time is a new generation too, and it replaces the
      // outdated record instead of adding a second one.
      final moved = trigger + 120000;
      await service.scheduleReminder(
        boardId: 'b1',
        taskId: 't1',
        title: 'Synthetic t1',
        triggerAtMs: moved,
      );
      final movedRecord = service.pendingJobs[_key('t1')]!;
      expect(movedRecord.triggerAtMs, moved);
      expect(movedRecord.attempts, 0);
      expect(service.pendingJobs, hasLength(1));
    });

    test('a deleted, completed or re-dated reminder is not resurrected', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final plugin = CountingPlugin();
      final trigger = _nowMs() + 600000;

      // Each case starts from its own persisted record, because resolving one
      // case is allowed to clear the ledger.
      Future<InMemoryReminderLedgerStore> seeded() async {
        final ledger = InMemoryReminderLedgerStore();
        final service = await _service(plugin, ledger);
        await service.scheduleReminder(
          boardId: 'b1',
          taskId: 't1',
          title: 'Synthetic t1',
          triggerAtMs: trigger,
        );
        await _settle(service);
        expect(service.pendingJobs, hasLength(1));
        return ledger;
      }

      Future<void> expectNoPlatformRetry(
        InMemoryReminderLedgerStore ledger,
        List<Task> tasks,
      ) async {
        final service = await _service(plugin, ledger);
        final before = plugin.countOf(#zonedSchedule);
        final report = await service.reconcilePending(tasks);
        expect(report.retried, 0);
        expect(report.dropped, 1);
        expect(service.pendingJobs, isEmpty);
        expect(
          plugin.countOf(#zonedSchedule),
          before,
          reason: 'no outdated reminder was handed to the platform',
        );
      }

      await expectNoPlatformRetry(await seeded(), [_task('t1')]);
      await expectNoPlatformRetry(await seeded(), [
        _task('t1', reminderAt: trigger, completed: true),
      ]);
      await expectNoPlatformRetry(await seeded(), [
        _task('t1', reminderAt: trigger + 60000),
      ]);
    });

    test('a spent budget does not keep a reminder the data no longer backs', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final plugin = CountingPlugin();
      final trigger = _nowMs() + 600000;
      final ledger = InMemoryReminderLedgerStore();
      final tasks = [_task('t1', reminderAt: trigger)];

      final armed = await _service(plugin, ledger);
      await armed.scheduleReminder(
        boardId: 'b1',
        taskId: 't1',
        title: 'Synthetic t1',
        triggerAtMs: trigger,
      );
      await _settle(armed);
      for (var pass = 0; pass < ReminderService.maxAutomaticRetries; pass++) {
        final service = await _service(plugin, ledger);
        await service.reconcilePending(tasks);
        await _settle(service);
      }
      final spent = await _service(plugin, ledger);
      await spent.loadPendingJobs();
      expect(spent.pendingJobs[_key('t1')]!.exhausted, isTrue);
      expect(
        spent.scheduleFailures.value,
        hasLength(1),
        reason: 'a still wanted reminder stays reported while spent',
      );

      // The user completed the task, so nothing backs the record any more.
      final after = await _service(plugin, ledger);
      final report = await after.reconcilePending([
        _task('t1', reminderAt: trigger, completed: true),
      ]);
      await _settle(after);
      expect(
        report.dropped,
        1,
        reason: 'a spent budget must not outlive the reminder it belongs to',
      );
      expect(after.pendingJobs, isEmpty);
      expect(
        after.scheduleFailures.value,
        isEmpty,
        reason: 'the banner must not keep blaming a completed task',
      );
    });

    test('a recovered channel clears the record instead of leaving it behind', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final ledger = InMemoryReminderLedgerStore();
      final plugin = CountingPlugin();
      final trigger = _nowMs() + 600000;
      final tasks = [_task('t1', reminderAt: trigger)];

      final broken = await _service(plugin, ledger);
      await broken.scheduleReminder(
        boardId: 'b1',
        taskId: 't1',
        title: 'Synthetic t1',
        triggerAtMs: trigger,
      );
      await _settle(broken);
      expect(broken.pendingJobs, hasLength(1));

      plugin.failSchedule = false;
      final repaired = await _service(plugin, ledger);
      await repaired.rescheduleAllFuture(tasks);
      final report = await repaired.reconcilePending(tasks);
      await _settle(repaired);
      // The fresh rebuild pass armed it, so reconciliation has nothing to redo.
      expect(report.retried, 0);
      expect(repaired.pendingJobs, isEmpty);
      expect(repaired.scheduleFailures.value, isEmpty);
      expect(plugin.nativePending, {_id('t1')});
      expect(ledger.value, isNull);
    });

    // PART3
  });

  group('RF08 ledger durability has an explicit completion result', () {
    test('a delayed ledger write is waited for, never reported as saved early', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final ledger = ScriptedLedgerStore()..holdWrites = Completer<void>();
      final service = await _service(CountingPlugin(), ledger);

      await service.scheduleReminder(
        boardId: 'b1',
        taskId: 't1',
        title: 'Synthetic t1',
        triggerAtMs: _nowMs() + 600000,
      );
      // The in-memory ledger answers the UI immediately.
      expect(service.scheduleFailures.value, hasLength(1));
      expect(ledger.writeCount, 0, reason: 'the write is still blocked');

      var finished = false;
      ReminderLedgerWriteResult? result;
      final waiting = service.flushPendingLedger().then((value) {
        result = value;
        finished = true;
      });
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(finished, isFalse, reason: 'flush must not pass a blocked write');
      expect(ledger.value, isNull);

      ledger.holdWrites!.complete();
      await waiting;
      expect(result!.writes, 1);
      expect(result!.success, isTrue);
      expect(result!.failed, isFalse);
      expect(ledger.value, contains('reschedule'));
    });

    test('a failed ledger write is visible and fails the exit barrier', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final ledger = ScriptedLedgerStore()..failWrites = true;
      final service = await _service(CountingPlugin(), ledger);
      final trigger = _nowMs() + 600000;
      await service.scheduleReminder(
        boardId: 'b1',
        taskId: 't1',
        title: 'Synthetic t1',
        triggerAtMs: trigger,
      );

      final failed = await service.flushPendingLedger();
      expect(failed.failed, isTrue);
      expect(failed.errorKind, isNotNull);
      expect(service.ledgerIssue.value?.kind, ReminderLedgerIssueKind.write);
      expect(
        service.scheduleFailures.value,
        hasLength(1),
        reason: 'the failure stays reported even though storage refused it',
      );

      // The store still backs the reminder, so the record is not dropped.
      final store = await _storeWith(service, [_task('t1', reminderAt: trigger)]);
      expect(service.pendingJobs, hasLength(1));
      expect(
        (await store.flush(includeReminderLedger: true)).success,
        isFalse,
        reason: 'exit must not claim success while the ledger is unwritten',
      );
      expect(
        (await store.flush()).success,
        isTrue,
        reason: 'a data-only barrier keeps the library contract',
      );

      ledger.failWrites = false;
      expect(
        (await store.retrySave(includeReminderLedger: true)).success,
        isTrue,
      );
      expect(service.ledgerIssue.value, isNull);
      expect(ledger.value, contains('reschedule'));
      store.dispose();
    });

    test('a retry that still cannot land the ledger is not a clean save', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      // The storage fault is permanent, so retrying cannot land the record.
      final ledger = ScriptedLedgerStore()..failWrites = true;
      final service = await _service(CountingPlugin(), ledger);
      final trigger = _nowMs() + 600000;
      await service.scheduleReminder(
        boardId: 'b1',
        taskId: 't1',
        title: 'Synthetic t1',
        triggerAtMs: trigger,
      );
      final store = await _storeWith(service, [_task('t1', reminderAt: trigger)]);

      final result = await store.retrySave(includeReminderLedger: true);
      expect(
        result.success,
        isFalse,
        reason: 'a refused ledger must not be reported as saved after retrying',
      );
      expect(
        service.ledgerIssue.value?.kind,
        ReminderLedgerIssueKind.write,
        reason: 'the caller can still see why the barrier failed',
      );
      expect(
        service.scheduleFailures.value,
        hasLength(1),
        reason: 'the reminder work stays reported, not silently dropped',
      );
      store.dispose();
    });

    test('an unreadable ledger is reported and retried, not treated as empty', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final ledger = ScriptedLedgerStore()..failReads = true;
      final service = await _service(CountingPlugin(), ledger);
      await service.loadPendingJobs();
      expect(service.ledgerIssue.value?.kind, ReminderLedgerIssueKind.read);

      ledger.failReads = false;
      final second = await _service(CountingPlugin(), ledger);
      await second.loadPendingJobs();
      expect(second.ledgerIssue.value, isNull);
      expect(ledger.readCount, greaterThan(1), reason: 'the read is retried');
    });

    test('a damaged ledger is reported and the readable records still load', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final ledger = ScriptedLedgerStore(
        seed: jsonEncode({
          'v': 1,
          'jobs': [
            {
              'kind': 'reschedule',
              'id': _id('t1'),
              'boardId': 'b1',
              'taskId': 't1',
              'triggerAtMs': _nowMs() + 600000,
              'attempts': 1,
              'firstFailedAtMs': 1000,
              'updatedAtMs': 1000,
            },
            {'kind': 'reschedule'},
          ],
        }),
      );
      final service = await _service(CountingPlugin(), ledger);
      await service.loadPendingJobs();
      expect(service.ledgerIssue.value?.kind, ReminderLedgerIssueKind.damaged);
      expect(service.pendingJobs, hasLength(1));
      expect(service.pendingJobs.values.single.taskId, 't1');
    });
  });

  group('RF08 a full ledger refuses work explicitly', () {
    ReminderPendingJob filler(int i, {bool exhausted = false}) =>
        ReminderPendingJob(
          kind: ReminderPendingKind.reschedule,
          notificationId: 1000 + i,
          boardId: 'b1',
          taskId: 'filler-$i',
          triggerAtMs: _nowMs() + 600000,
          firstFailedAtMs: 1000 + i,
          updatedAtMs: 1000 + i,
          exhausted: exhausted,
        );

    test('the 65th failure is refused, reported, and not counted as saved', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final service = await _service(
        CountingPlugin(),
        InMemoryReminderLedgerStore(),
      );
      for (var i = 0; i < ReminderService.maxPendingJobs; i++) {
        expect(
          await service.trackPendingJob(filler(i)),
          ReminderLedgerUpdate.recorded,
        );
      }
      expect(service.pendingJobs, hasLength(ReminderService.maxPendingJobs));

      final refused = await service.trackPendingJob(
        ReminderPendingJob(
          kind: ReminderPendingKind.reschedule,
          notificationId: 9999,
          boardId: 'b1',
          taskId: 'one-too-many',
          triggerAtMs: _nowMs() + 600000,
          firstFailedAtMs: 5000,
          updatedAtMs: 5000,
        ),
      );
      expect(refused, ReminderLedgerUpdate.rejected);
      expect(service.pendingJobs, hasLength(ReminderService.maxPendingJobs));
      expect(
        service.pendingJobs.values.map((job) => job.taskId),
        isNot(contains('one-too-many')),
      );
      expect(service.refusedRecords, 1);
      expect(service.ledgerIssue.value?.kind, ReminderLedgerIssueKind.overflow);
      expect(service.ledgerIssue.value?.count, 1);
    });

    test('an exhausted record makes room for live work before the cap', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final service = await _service(
        CountingPlugin(),
        InMemoryReminderLedgerStore(),
      );
      // The ledger is full and only one record has spent its budget.
      for (var i = 0; i < ReminderService.maxPendingJobs; i++) {
        await service.trackPendingJob(filler(i, exhausted: i == 0));
      }
      expect(service.pendingJobs, hasLength(ReminderService.maxPendingJobs));
      final live = await service.trackPendingJob(
        ReminderPendingJob(
          kind: ReminderPendingKind.reschedule,
          notificationId: _id('t1'),
          boardId: 'b1',
          taskId: 't1',
          triggerAtMs: _nowMs() + 600000,
          firstFailedAtMs: 6000,
          updatedAtMs: 6000,
        ),
      );
      expect(live, ReminderLedgerUpdate.recorded);
      expect(service.pendingJobs, hasLength(ReminderService.maxPendingJobs));
      expect(
        service.pendingJobs.values.map((job) => job.taskId),
        isNot(contains('filler-0')),
        reason: 'the spent record is the one that may be dropped',
      );
      expect(service.pendingJobs.values.map((job) => job.taskId), contains('t1'));
      expect(service.ledgerIssue.value, isNull);
    });
  });

  group('RF08 a clear racing an in-flight load is not undone', () {
    Future<ScriptedLedgerStore> seededLedger(CountingPlugin plugin) async {
      final trigger = _nowMs() + 600000;
      final seed = InMemoryReminderLedgerStore();
      final seeded = await _service(plugin, seed);
      await seeded.scheduleReminder(
        boardId: 'b1',
        taskId: 't1',
        title: 'Synthetic t1',
        triggerAtMs: trigger,
      );
      await _settle(seeded);
      expect(seeded.pendingJobs, hasLength(1));
      return ScriptedLedgerStore(seed: seed.value)
        ..holdRead = Completer<String?>();
    }

    test('a single-key clear during the read reaches storage too', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final plugin = CountingPlugin();
      final ledger = await seededLedger(plugin);
      final service = await _service(plugin, ledger);

      final loading = service.loadPendingJobs();
      // The user clears the reminder while the stored ledger is still reading.
      await service.clearPendingJob(_key('t1'));
      ledger.holdRead!.complete(ledger.seed);
      ledger.holdRead = null;
      await loading;
      await _settle(service);

      expect(service.pendingJobs, isEmpty);
      expect(service.scheduleFailures.value, isEmpty);
      expect(ledger.value, isNull, reason: 'the clear reached storage too');

      final afterRestart = await _service(plugin, ledger);
      await afterRestart.loadPendingJobs();
      expect(afterRestart.pendingJobs, isEmpty);
    });

    test('a notification clear during the read reaches storage too', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final plugin = CountingPlugin();
      final ledger = await seededLedger(plugin);
      final service = await _service(plugin, ledger);

      final loading = service.loadPendingJobs();
      await service.clearPendingForNotification(_id('t1'));
      ledger.holdRead!.complete(ledger.seed);
      ledger.holdRead = null;
      await loading;
      await _settle(service);

      expect(service.pendingJobs, isEmpty);
      expect(ledger.value, isNull);
      final afterRestart = await _service(plugin, ledger);
      await afterRestart.loadPendingJobs();
      expect(afterRestart.pendingJobs, isEmpty);
    });

    test('an unreadable old ledger is not replaced by a new failure', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final plugin = CountingPlugin();
      final ledger = await seededLedger(plugin);
      ledger.holdRead = null;
      ledger.failReads = true;
      final service = await _service(plugin, ledger);

      await service.trackPendingJob(ReminderPendingJob(
        kind: ReminderPendingKind.reschedule,
        notificationId: _id('t2'),
        boardId: 'b1',
        taskId: 't2',
        triggerAtMs: _nowMs() + 600000,
        firstFailedAtMs: _nowMs(),
        updatedAtMs: _nowMs(),
      ));
      final first = await service.flushPendingLedger();
      expect(first.success, isFalse);
      expect(ledger.written, isFalse, reason: 'the unreadable old jobs remain on disk');
      expect(service.ledgerIssue.value?.kind, ReminderLedgerIssueKind.read);

      ledger.failReads = false;
      expect(await service.retryPendingLedger(), isTrue);
      final afterRestart = await _service(plugin, ledger);
      await afterRestart.loadPendingJobs();
      expect(afterRestart.pendingJobs.values.map((job) => job.taskId).toSet(),
          {'t1', 't2'});
    });

    test('a full clear wins over a read that is still in flight', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final plugin = CountingPlugin();
      final ledger = await seededLedger(plugin);
      final service = await _service(plugin, ledger);

      final loading = service.loadPendingJobs();
      final clearing = service.clearAllPendingJobs();
      ledger.holdRead!.complete(ledger.seed);
      ledger.holdRead = null;
      await loading;
      await clearing;
      await _settle(service);

      expect(service.pendingJobs, isEmpty);
      expect(ledger.value, isNull);
      final afterRestart = await _service(plugin, ledger);
      await afterRestart.loadPendingJobs();
      expect(afterRestart.pendingJobs, isEmpty);
    });
  });

  group('RF08 cancellation retries keep their identity', () {
    test('repeated cancel failures accumulate and keep the notification id', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final ledger = InMemoryReminderLedgerStore();
      final plugin = CountingPlugin()..failSchedule = false;
      final service = await _service(plugin, ledger);
      // The platform holds a real notification, so cancelling it is owed work.
      await service.scheduleReminder(
        boardId: 'b1',
        taskId: 't1',
        title: 'Synthetic t1',
        triggerAtMs: _nowMs() + 600000,
      );
      await _settle(service);
      expect(plugin.nativePending, {_id('t1')});

      plugin.failCancel = true;
      expect((await service.cancelReminder('t1')).needsRetry, isTrue);
      final cancelKey = 'cancel:${_id('t1')}';
      final first = service.pendingJobs[cancelKey]!;
      expect(first.notificationId, _id('t1'));
      expect(first.taskId, 't1');
      expect(first.boardId, 'b1', reason: 'the retry keeps its notification identity');
      await _settle(service);

      for (var pass = 0; pass < ReminderService.maxAutomaticRetries; pass++) {
        final next = await _service(plugin, ledger);
        await next.reconcilePending([_task('t1')]);
        await _settle(next);
      }

      final spent = await _service(plugin, ledger);
      await spent.loadPendingJobs();
      final record = spent.pendingJobs[cancelKey]!;
      expect(record.notificationId, _id('t1'), reason: 'identity is preserved');
      expect(record.taskId, 't1');
      expect(record.exhausted, isTrue);
      expect(spent.cancelFailures.value.values.single.taskId, 't1');

      // A spent cancellation budget waits for the user instead of retrying on
      // its own, so the ghost is only cleared by an explicit retry.
      plugin.failCancel = false;
      final waiting = await _service(plugin, ledger);
      final paused = await waiting.reconcilePending([_task('t1')]);
      expect(paused.recovered, 0, reason: 'an exhausted record is not auto-retried');
      expect(paused.exhausted, 1);
      expect(waiting.cancelFailures.value, hasLength(1));

      final retried = await waiting.cancelReminder('t1', userInitiated: true);
      expect(retried.succeeded, isTrue);
      await _settle(waiting);
      expect(waiting.cancelFailures.value, isEmpty);
      expect(waiting.pendingJobs, isEmpty);
      expect(plugin.nativePending, isEmpty);
    });

    test('a user-requested cancel retry starts a new generation', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final plugin = CountingPlugin()
        ..failSchedule = false
        ..failCancel = true;
      final service = await _service(plugin, InMemoryReminderLedgerStore());
      await service.scheduleReminder(
        boardId: 'b1',
        taskId: 't1',
        title: 'Synthetic t1',
        triggerAtMs: _nowMs() + 600000,
      );
      await service.cancelReminder('t1');
      await _settle(service);
      final cancelKey = 'cancel:${_id('t1')}';
      final spentSince = service.pendingJobs[cancelKey]!.firstFailedAtMs;

      final cancelCalls = plugin.countOf(#cancel);
      await service.cancelReminder('t1', userInitiated: true);
      final restarted = service.pendingJobs[cancelKey]!;
      expect(plugin.countOf(#cancel), cancelCalls + 1);
      expect(restarted.attempts, 0);
      expect(restarted.firstFailedAtMs, greaterThanOrEqualTo(spentSince!));
      expect(restarted.notificationId, _id('t1'));
    });
  });

  group('RF08 store startup coordination', () {
    test('a startup pass continues the stored budget and reports its outcome', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final ledger = InMemoryReminderLedgerStore();
      final plugin = CountingPlugin();
      final trigger = _nowMs() + 600000;

      final first = await _service(plugin, ledger);
      await first.scheduleReminder(
        boardId: 'b1',
        taskId: 't1',
        title: 'Synthetic t1',
        triggerAtMs: trigger,
      );
      await _settle(first);

      for (var start = 1; start <= 2; start++) {
        // A new process each time: a fresh service reading the same ledger.
        final service = await _service(plugin, ledger);
        final store = await _storeWith(service, [_task('t1', reminderAt: trigger)]);
        // The store's own startup pass already ran; this is the next cycle.
        await _settle(service);
        final before = service.pendingJobs[_key('t1')]?.attempts ?? 0;
        final report = await store.reconcileReminders();
        expect(store.lastReminderReport, isNotNull);
        expect(
          service.pendingJobs[_key('t1')]!.attempts,
          before + 1,
          reason: 'one startup pass counts exactly one more attempt',
        );
        expect(report.skipped, 1, reason: 'the fresh pass already tried it');
        expect(report.retried, 0);
        expect(report.needsAttention, isTrue);
        store.dispose();
      }

      // The ledger on disk is the one a fresh process reads back.
      final afterRestart = await _service(plugin, ledger);
      await afterRestart.loadPendingJobs();
      expect(afterRestart.pendingJobs[_key('t1')]!.attempts, 4);
      expect(afterRestart.pendingJobs[_key('t1')]!.exhausted, isFalse);
    });

    test('a user edit after exhaustion re-arms the reminder', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final plugin = CountingPlugin();
      final service = await _service(plugin, InMemoryReminderLedgerStore());
      final trigger = _nowMs() + 600000;
      final store = await _storeWith(service, [_task('t1', reminderAt: trigger)]);
      for (var pass = 0; pass < ReminderService.maxAutomaticRetries + 1; pass++) {
        await store.reconcileReminders();
      }
      expect(service.pendingJobs[_key('t1')]!.exhausted, isTrue);
      // The user moves the reminder: a new generation, so the platform is asked.
      plugin.failSchedule = false;
      final task = store.tasks.single;
      store.updateTask(
        Task.fromJson(task.toJson())..reminderAt = trigger + 300000,
      );
      await _settle(service);
      expect(plugin.nativePending, {_id('t1')});
      expect(service.pendingJobs, isEmpty);
      expect(service.scheduleFailures.value, isEmpty);
      store.dispose();
    });

    test('deleting a task after exhaustion clears the pending record', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final plugin = CountingPlugin();
      final service = await _service(plugin, InMemoryReminderLedgerStore());
      final trigger = _nowMs() + 600000;
      final store = await _storeWith(service, [_task('t1', reminderAt: trigger)]);
      for (var pass = 0; pass < ReminderService.maxAutomaticRetries + 1; pass++) {
        await store.reconcileReminders();
      }
      expect(service.pendingJobs, hasLength(1));

      // Deleting the task must leave no retry work behind at all.
      store.deleteTask('t1');
      await store.reconcileReminders();
      await _settle(service);
      expect(service.pendingJobs, isEmpty);
      expect(service.scheduleFailures.value, isEmpty);
      expect(service.cancelFailures.value, isEmpty);
      expect(plugin.nativePending, isEmpty);
      store.dispose();
    });
  });
}
