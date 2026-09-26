// RF08 review counterexamples. Synthetic tasks, in-memory ledger, fake plugin.
// Run explicitly; this is not part of the default regression set:
//   flutter test --no-pub test/review/rf08_reminder_retry_probe.dart
//
// Every assertion here states the behaviour the ledger promises: a bounded
// automatic retry budget that a restart must not renew by itself.
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/services/reminder_service.dart';

/// Platform double: an accepted schedule stays pending until cancelled.
class RejectingPlugin implements FlutterLocalNotificationsPlugin {
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

Task _task(String id, {int? reminderAt, bool completed = false}) => Task(
  id: id,
  boardId: 'b1',
  title: 'Synthetic $id',
  quadrant: 1,
  createdAt: 1,
  reminderAt: reminderAt,
  completed: completed,
);

Future<FlutterLocalNotificationsReminderService> _service(
  RejectingPlugin plugin,
  ReminderLedgerStore ledger,
) async {
  final service = FlutterLocalNotificationsReminderService(
    plugin: plugin,
    ledgerStore: ledger,
  );
  await service.init();
  return service;
}

/// The Store fires reminder work without awaiting it, so let the operation
/// chain and the queued ledger write settle before reading real state.
Future<void> _settle(ReminderService service) async {
  for (var i = 0; i < 6; i++) {
    await Future<void>.delayed(Duration.zero);
  }
  await service.pendingLedgerWrites();
}

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('RF-R08a repeated starts must not renew the automatic retry budget', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final ledger = InMemoryReminderLedgerStore();
    final plugin = RejectingPlugin();
    final trigger = DateTime.now().millisecondsSinceEpoch + 600000;
    final tasks = [_task('t1', reminderAt: trigger)];

    // The user edit that armed this reminder was rejected by the platform.
    final first = await _service(plugin, ledger);
    await first.scheduleReminder(
      boardId: 'b1',
      taskId: 't1',
      title: 'Synthetic t1',
      triggerAtMs: trigger,
    );
    await _settle(first);
    expect(first.pendingJobs, hasLength(1));

    // Six cold starts: load -> reschedule all future -> reconcile -> persist.
    final attemptsPerStart = <int>[];
    final schedulesPerStart = <int>[];
    for (var start = 1; start <= 6; start++) {
      final service = await _service(plugin, ledger);
      final before = plugin.countOf(#zonedSchedule);
      await service.rescheduleAllFuture(tasks);
      await service.reconcilePending(tasks);
      await _settle(service);
      attemptsPerStart.add(
        service.pendingJobs.values.singleOrNull?.attempts ?? -1,
      );
      schedulesPerStart.add(
        (plugin.countOf(#zonedSchedule) - before) ~/ 3, // the exact/inexact ladder
      );
      // A reminder that is still not armed must stay visible to the user.
      expect(
        service.scheduleFailures.value,
        isNotEmpty,
        reason: 'start $start must not hide the failure',
      );
    }

    expect(
      attemptsPerStart,
      equals([1, 2, 3, 4, 5, 5]),
      reason: 'each start counts one automatic attempt, then the budget is spent',
    );
    expect(
      schedulesPerStart,
      equals([1, 1, 1, 1, 1, 0]),
      reason: 'a spent budget stops asking the platform on later starts',
    );
  });

  test('RF-R08b a spent budget survives a restart instead of being dropped', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final ledger = InMemoryReminderLedgerStore();
    final plugin = RejectingPlugin();
    final trigger = DateTime.now().millisecondsSinceEpoch + 600000;
    final tasks = [_task('t1', reminderAt: trigger)];

    final first = await _service(plugin, ledger);
    await first.scheduleReminder(
      boardId: 'b1',
      taskId: 't1',
      title: 'Synthetic t1',
      triggerAtMs: trigger,
    );
    await _settle(first);

    for (var start = 1; start <= ReminderService.maxAutomaticRetries + 2; start++) {
      final service = await _service(plugin, ledger);
      await service.rescheduleAllFuture(tasks);
      await service.reconcilePending(tasks);
      await _settle(service);
    }

    final last = await _service(plugin, ledger);
    await last.loadPendingJobs();
    final record = last.pendingJobs.values.single;
    expect(
      record.attempts,
      ReminderService.maxAutomaticRetries,
      reason: 'the automatic budget is spent by restarts instead of renewed',
    );
    expect(
      last.scheduleFailures.value.values.single.taskId,
      't1',
      reason: 'a reminder that could not be armed must stay reported',
    );
  });
}
