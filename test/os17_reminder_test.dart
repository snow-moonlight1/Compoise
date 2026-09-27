import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/screens/settings_screen.dart';
import 'package:matrixflow_native/storage.dart';
import 'package:matrixflow_native/widgets/reminder_failure_banner.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'foundation_regression_test.dart' as fixture;
import 'helpers.dart';

/// Plugin double that models what the operating system holds: an id appears in
/// [nativePending] once a notification was accepted and leaves when cancelled.
class FakeNotificationPlugin implements FlutterLocalNotificationsPlugin {
  FakeNotificationPlugin({this.android, this.initResult = true});

  final AndroidFlutterLocalNotificationsPlugin? android;
  final bool? initResult;
  final List<Symbol> calls = [];
  final Set<int> nativePending = {};

  bool failSchedule = false;
  bool failCancel = false;
  bool failCancelAll = false;
  Object scheduleError = StateError('synthetic schedule failure');

  int countOf(Symbol name) => calls.where((c) => c == name).length;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = invocation.memberName;
    calls.add(name);
    if (name == #initialize) return Future<bool?>.value(initResult);
    if (name == #resolvePlatformSpecificImplementation) return android;
    if (name == #zonedSchedule || name == #show) {
      if (failSchedule) return Future<void>.error(scheduleError);
      nativePending.add(invocation.positionalArguments.first as int);
      return Future<void>.value();
    }
    if (name == #cancel) {
      if (failCancel) {
        return Future<void>.error(StateError('synthetic cancel failure'));
      }
      nativePending.remove(invocation.positionalArguments.first as int);
      return Future<void>.value();
    }
    if (name == #cancelAll) {
      if (failCancelAll) {
        return Future<void>.error(StateError('synthetic cancel-all failure'));
      }
      nativePending.clear();
      return Future<void>.value();
    }
    return Future<void>.value();
  }
}

class FakeAndroidPlugin implements AndroidFlutterLocalNotificationsPlugin {
  FakeAndroidPlugin({this.notificationsEnabled, this.canExact});

  bool? notificationsEnabled;
  bool? canExact;
  bool throwOnProbe = false;
  int requestCount = 0;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = invocation.memberName;
    if (name == #areNotificationsEnabled ||
        name == #canScheduleExactNotifications) {
      if (throwOnProbe) {
        return Future<bool?>.error(StateError('probe unavailable'));
      }
      return Future<bool?>.value(
        name == #areNotificationsEnabled ? notificationsEnabled : canExact,
      );
    }
    if (name == #requestNotificationsPermission) {
      requestCount++;
      return Future<bool?>.value(notificationsEnabled);
    }
    return Future<bool?>.value(true);
  }
}

class DelayedReminderLedgerStore implements ReminderLedgerStore {
  final initialRead = Completer<String?>();
  String? value;
  int writeCount = 0;

  @override
  Future<String?> read() => initialRead.future;

  @override
  Future<void> write(String? next) async {
    value = next;
    writeCount++;
  }
}

Task _task(String id, {int? reminderAt, bool completed = false}) => Task(
  id: id,
  boardId: 'b1',
  title: 'Synthetic $id',
  notesMarkdown: 'private notes for $id',
  quadrant: 1,
  createdAt: 1,
  reminderAt: reminderAt,
  completed: completed,
);

Future<FlutterLocalNotificationsReminderService> _service(
  FakeNotificationPlugin plugin,
  ReminderLedgerStore ledger,
) async {
  final service = FlutterLocalNotificationsReminderService(
    plugin: plugin,
    ledgerStore: ledger,
  );
  await service.init();
  return service;
}

/// The Store fires reminder work without awaiting it, so tests let both the
/// operation chain and the ledger write settle before asserting.
Future<void> _flush(ReminderService service) async {
  for (var i = 0; i < 6; i++) {
    await Future<void>.delayed(Duration.zero);
  }
  await service.pendingLedgerWrites();
}

int _id(String taskId) => generateNotificationId(taskId);

void main() {
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    ReminderService.resetForTest();
  });

  group('OS17 permission probe honesty', () {
    test('Android answers null or throws: unknown, never granted', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final android = FakeAndroidPlugin();
      final service = FlutterLocalNotificationsReminderService(
        plugin: FakeNotificationPlugin(android: android),
      );

      expect(await service.checkPermission(), ReminderPermissionStatus.unknown);

      android.throwOnProbe = true;
      expect(
        await service.checkPermission(),
        ReminderPermissionStatus.unknown,
        reason: 'a failing probe must not be reported as granted',
      );

      android
        ..throwOnProbe = false
        ..notificationsEnabled = false;
      expect(await service.checkPermission(), ReminderPermissionStatus.denied);

      android
        ..notificationsEnabled = true
        ..canExact = false;
      expect(
        await service.checkPermission(),
        ReminderPermissionStatus.inexactOnly,
      );

      android.canExact = null;
      expect(await service.checkPermission(), ReminderPermissionStatus.unknown);

      android.canExact = true;
      expect(await service.checkPermission(), ReminderPermissionStatus.granted);
      expect(android.requestCount, 0);
    });

    test('a missing Android implementation is unsupported', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final service = FlutterLocalNotificationsReminderService(
        plugin: FakeNotificationPlugin(),
      );
      expect(
        await service.checkPermission(),
        ReminderPermissionStatus.unsupported,
      );
    });

    test('Windows reports unknown and only a decline is unsupported', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      final accepted = await _service(
        FakeNotificationPlugin(initResult: true),
        InMemoryReminderLedgerStore(),
      );
      expect(
        await accepted.checkPermission(),
        ReminderPermissionStatus.unknown,
      );
      expect(
        await accepted.requestPermission(),
        ReminderPermissionStatus.unknown,
        reason: 'there is nothing to request on Windows',
      );

      final declined = await _service(
        FakeNotificationPlugin(initResult: false),
        InMemoryReminderLedgerStore(),
      );
      expect(
        await declined.checkPermission(),
        ReminderPermissionStatus.unsupported,
      );
      final result = await declined.scheduleReminder(
        boardId: 'b1',
        taskId: 't1',
        title: 'Synthetic t1',
        triggerAtMs: DateTime.now().millisecondsSinceEpoch + 60000,
      );
      expect(result.needsRetry, isTrue);
    });

    test('the last real probe is cached for the banner', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final android = FakeAndroidPlugin(
        notificationsEnabled: true,
        canExact: true,
      );
      final service = FlutterLocalNotificationsReminderService(
        plugin: FakeNotificationPlugin(android: android),
      );
      expect(service.observedPermission.value, isNull);
      await service.checkPermission();
      expect(
        service.observedPermission.value,
        ReminderPermissionStatus.granted,
      );
    });
  });

  group('OS17 schedule and cancel results', () {
    test(
      'a rejected schedule reports failed and keeps a retry record',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        final ledger = InMemoryReminderLedgerStore();
        final plugin = FakeNotificationPlugin()..failSchedule = true;
        final service = await _service(plugin, ledger);
        final trigger = DateTime.now().millisecondsSinceEpoch + 600000;

        final result = await service.scheduleReminder(
          boardId: 'b1',
          taskId: 't1',
          title: 'Synthetic t1',
          body: 'private notes for t1',
          triggerAtMs: trigger,
        );

        expect(result.status, ReminderScheduleStatus.failed);
        expect(result.errorKind, 'StateError');
        expect(
          service.scheduleFailures.value.keys.single,
          result.notificationId,
        );
        expect(service.cancelFailures.value, isEmpty);
        await _flush(service);
        // The persisted record carries ids only, never task content.
        expect(ledger.value, contains('reschedule'));
        expect(ledger.value, isNot(contains('Synthetic t1')));
        expect(ledger.value, isNot(contains('private notes')));

        plugin.failSchedule = false;
        final retry = await service.scheduleReminder(
          boardId: 'b1',
          taskId: 't1',
          title: 'Synthetic t1',
          triggerAtMs: trigger,
        );
        expect(retry.accepted, isTrue);
        expect(service.scheduleFailures.value, isEmpty);
        expect(service.pendingJobs, isEmpty);
        expect(plugin.nativePending, {_id('t1')});
        await _flush(service);
        expect(ledger.value, isNull);
      },
    );

    test('a failed cancel is reported apart from a failed schedule', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final plugin = FakeNotificationPlugin();
      final service = await _service(plugin, InMemoryReminderLedgerStore());
      await service.scheduleReminder(
        boardId: 'b1',
        taskId: 't9',
        title: 'Synthetic t9',
        triggerAtMs: DateTime.now().millisecondsSinceEpoch + 600000,
      );
      expect(service.trackedReminders.keys, [_id('t9')]);

      plugin.failCancel = true;
      final failed = await service.cancelReminder('t9');
      expect(failed.status, ReminderCancelStatus.failed);
      expect(service.cancelFailures.value.values.single.taskId, 't9');
      expect(service.scheduleFailures.value, isEmpty);

      plugin.failCancel = false;
      final retry = await service.cancelReminder('t9');
      expect(retry.succeeded, isTrue);
      expect(service.cancelFailures.value, isEmpty);
      expect(service.pendingJobs, isEmpty);
      expect(service.trackedReminders, isEmpty);
    });

    test(
      'a bulk cancel failure degrades to per-notification retries',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        final plugin = FakeNotificationPlugin();
        final service = await _service(plugin, InMemoryReminderLedgerStore());
        final trigger = DateTime.now().millisecondsSinceEpoch + 600000;
        await service.scheduleReminder(
          boardId: 'b1',
          taskId: 't1',
          title: 'Synthetic t1',
          triggerAtMs: trigger,
        );
        await service.scheduleReminder(
          boardId: 'b1',
          taskId: 't2',
          title: 'Synthetic t2',
          triggerAtMs: trigger,
        );
        expect(service.trackedReminders, hasLength(2));

        plugin
          ..failCancelAll = true
          ..failCancel = true;
        await service.cancelAll();
        await _flush(service);

        expect(service.cancelFailures.value, hasLength(2));
        expect(plugin.countOf(#cancel), 2);
        expect(service.scheduleFailures.value, isEmpty);
      },
    );

    test(
      'a test reminder does not create retry work for a synthetic task',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        final plugin = FakeNotificationPlugin()..failSchedule = true;
        final service = await _service(plugin, InMemoryReminderLedgerStore());

        final result = await service.scheduleReminder(
          boardId: 'b1',
          taskId: 'test-win-notif',
          title: 'Compoise',
          triggerAtMs: DateTime.now().millisecondsSinceEpoch,
          recordRetry: false,
        );
        expect(result.needsRetry, isTrue);
        expect(service.pendingJobs, isEmpty);
        expect(service.scheduleFailures.value, isEmpty);
      },
    );
  });

  group('OS17 restart compensation', () {
    test(
      'a new failure waits for the startup ledger read before writing',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        final priorLedger = InMemoryReminderLedgerStore();
        final first = await _service(
          FakeNotificationPlugin()..failSchedule = true,
          priorLedger,
        );
        final trigger = DateTime.now().millisecondsSinceEpoch + 600000;
        await first.scheduleReminder(
          boardId: 'b1',
          taskId: 'old',
          title: 'Synthetic old',
          triggerAtMs: trigger,
        );
        await _flush(first);

        final delayed = DelayedReminderLedgerStore();
        final second = await _service(
          FakeNotificationPlugin()..failSchedule = true,
          delayed,
        );
        final loading = second.loadPendingJobs();
        await second.scheduleReminder(
          boardId: 'b1',
          taskId: 'new',
          title: 'Synthetic new',
          triggerAtMs: trigger,
        );
        expect(delayed.writeCount, 0);

        delayed.initialRead.complete(priorLedger.value);
        await loading;
        await _flush(second);
        expect(second.pendingJobs, hasLength(2));
        expect(delayed.value, contains('old'));
        expect(delayed.value, contains('new'));
      },
    );

    test('a new process retries the schedule the ledger recorded', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final ledger = InMemoryReminderLedgerStore();
      final failing = FakeNotificationPlugin()..failSchedule = true;
      final first = await _service(failing, ledger);
      final trigger = DateTime.now().millisecondsSinceEpoch + 600000;
      await first.scheduleReminder(
        boardId: 'b1',
        taskId: 't1',
        title: 'Synthetic t1',
        triggerAtMs: trigger,
      );
      await _flush(first);
      expect(ledger.value, isNotNull);

      final afterRestart = FakeNotificationPlugin();
      final second = await _service(afterRestart, ledger);
      await second.loadPendingJobs();
      expect(second.pendingJobs, hasLength(1));
      final report = await second.reconcilePending([
        _task('t1', reminderAt: trigger),
      ]);

      expect(report.retried, 1);
      expect(report.recovered, 1);
      expect(afterRestart.nativePending, {_id('t1')});
      expect(second.pendingJobs, isEmpty);
      expect(second.scheduleFailures.value, isEmpty);
      await _flush(second);
      expect(ledger.value, isNull);
    });

    test('a reminder the user deleted is never resurrected', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final ledger = InMemoryReminderLedgerStore();
      final failing = FakeNotificationPlugin()..failSchedule = true;
      final first = await _service(failing, ledger);
      final trigger = DateTime.now().millisecondsSinceEpoch + 600000;
      await first.scheduleReminder(
        boardId: 'b1',
        taskId: 't1',
        title: 'Synthetic t1',
        triggerAtMs: trigger,
      );
      await _flush(first);

      final afterRestart = FakeNotificationPlugin();
      final second = await _service(afterRestart, ledger);
      final report = await second.reconcilePending([_task('t1')]);

      expect(report.dropped, 1);
      expect(afterRestart.countOf(#zonedSchedule), 0);
      expect(afterRestart.nativePending, isEmpty);
      expect(second.pendingJobs, isEmpty);
    });

    test('a completed task drops its pending schedule too', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final ledger = InMemoryReminderLedgerStore();
      final failing = FakeNotificationPlugin()..failSchedule = true;
      final first = await _service(failing, ledger);
      final trigger = DateTime.now().millisecondsSinceEpoch + 600000;
      await first.scheduleReminder(
        boardId: 'b1',
        taskId: 't1',
        title: 'Synthetic t1',
        triggerAtMs: trigger,
      );
      await _flush(first);

      final second = await _service(FakeNotificationPlugin(), ledger);
      final report = await second.reconcilePending([
        _task('t1', reminderAt: trigger, completed: true),
      ]);
      expect(report.dropped, 1);
      expect(second.pendingJobs, isEmpty);
    });

    test(
      're-editing the time replaces the pending record instead of adding one',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        final ledger = InMemoryReminderLedgerStore();
        final plugin = FakeNotificationPlugin()..failSchedule = true;
        final service = await _service(plugin, ledger);
        final oldTrigger = DateTime.now().millisecondsSinceEpoch + 600000;
        final newTrigger = oldTrigger + 120000;

        await service.scheduleReminder(
          boardId: 'b1',
          taskId: 't1',
          title: 'Synthetic t1',
          triggerAtMs: oldTrigger,
        );
        expect(service.pendingJobs.values.single.triggerAtMs, oldTrigger);
        await service.scheduleReminder(
          boardId: 'b1',
          taskId: 't1',
          title: 'Synthetic t1',
          triggerAtMs: newTrigger,
        );
        expect(service.pendingJobs, hasLength(1));
        expect(service.pendingJobs.values.single.triggerAtMs, newTrigger);
        expect(service.pendingJobs.values.single.attempts, 0);

        plugin.failSchedule = false;
        await service.reconcilePending([_task('t1', reminderAt: newTrigger)]);
        expect(plugin.nativePending, {_id('t1')});
        expect(service.pendingJobs, isEmpty);
      },
    );

    test('automatic retries are bounded', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final plugin = FakeNotificationPlugin()..failSchedule = true;
      final service = await _service(plugin, InMemoryReminderLedgerStore());
      final trigger = DateTime.now().millisecondsSinceEpoch + 600000;
      await service.scheduleReminder(
        boardId: 'b1',
        taskId: 't1',
        title: 'Synthetic t1',
        triggerAtMs: trigger,
      );

      final tasks = [_task('t1', reminderAt: trigger)];
      for (var pass = 1; pass <= ReminderService.maxAutomaticRetries; pass++) {
        final report = await service.reconcilePending(tasks);
        expect(report.retried, 1, reason: 'pass $pass retries once');
        expect(service.pendingJobs.values.single.attempts, pass);
      }
      // RF08: a spent budget stops the automatic retries but keeps the failure
      // reported, instead of dropping the record as if it had succeeded.
      final last = await service.reconcilePending(tasks);
      expect(last.dropped, 0);
      expect(last.exhausted, 1);
      expect(service.pendingJobs, hasLength(1));
      expect(service.pendingJobs.values.single.exhausted, isTrue);
      expect(service.scheduleFailures.value, hasLength(1));

      final callsAfterBudget = plugin.countOf(#zonedSchedule);
      final extra = await service.reconcilePending(tasks);
      expect(extra.retried, 0);
      expect(extra.exhausted, 1);
      expect(
        plugin.countOf(#zonedSchedule),
        callsAfterBudget,
        reason: 'the ledger stops retrying once the bound is reached',
      );
    });

    test('a pending cancel is finished after restart', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final ledger = InMemoryReminderLedgerStore();
      final plugin = FakeNotificationPlugin();
      final first = await _service(plugin, ledger);
      await first.scheduleReminder(
        boardId: 'b1',
        taskId: 't1',
        title: 'Synthetic t1',
        triggerAtMs: DateTime.now().millisecondsSinceEpoch + 600000,
      );
      plugin.failCancel = true;
      await first.cancelReminder('t1');
      await _flush(first);
      expect(first.cancelFailures.value, hasLength(1));

      plugin.failCancel = false;
      final second = await _service(plugin, ledger);
      final report = await second.reconcilePending([_task('t1')]);
      expect(report.recovered, 1);
      expect(plugin.nativePending, isEmpty);
      expect(second.cancelFailures.value, isEmpty);
      await _flush(second);
      expect(ledger.value, isNull);
    });

    test(
      'a reminder re-added for a pending cancel replaces the ghost',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        final ledger = InMemoryReminderLedgerStore();
        final plugin = FakeNotificationPlugin();
        final first = await _service(plugin, ledger);
        final trigger = DateTime.now().millisecondsSinceEpoch + 600000;
        await first.scheduleReminder(
          boardId: 'b1',
          taskId: 't1',
          title: 'Synthetic t1',
          triggerAtMs: trigger,
        );
        plugin.failCancel = true;
        await first.cancelReminder('t1');
        await _flush(first);

        plugin.failCancel = false;
        final second = await _service(plugin, ledger);
        final cancelsBefore = plugin.countOf(#cancel);
        final report = await second.reconcilePending([
          _task('t1', reminderAt: trigger + 300000),
        ]);
        expect(report.dropped, 1);
        expect(
          plugin.countOf(#cancel),
          cancelsBefore,
          reason: 'the newer reminder replaces the ghost, no cancel needed',
        );
        expect(second.pendingJobs, isEmpty);
      },
    );
  });

  group('OS17 store wiring', () {
    test(
      'startup reconciliation retries the reminder that failed last run',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        SharedPreferences.setMockInitialValues({});
        final ledger = InMemoryReminderLedgerStore();
        final trigger = DateTime.now().millisecondsSinceEpoch + 600000;
        final failing = FakeNotificationPlugin()..failSchedule = true;
        final first = await _service(failing, ledger);
        await first.scheduleReminder(
          boardId: 'b1',
          taskId: 't1',
          title: 'Synthetic t1',
          triggerAtMs: trigger,
        );
        await _flush(first);
        expect(first.scheduleFailures.value, hasLength(1));

        final recovered = FakeNotificationPlugin();
        final service = await _service(recovered, ledger);
        ReminderService.instance = service;
        final (store, _) = await makeStore(
          boards: [Board(id: 'b1', name: 'Board', createdAt: 1)],
          tasks: [_task('t1', reminderAt: trigger)],
        );
        await store.reconcileReminders();

        expect(recovered.nativePending, {_id('t1')});
        expect(service.scheduleFailures.value, isEmpty);
        expect(service.pendingJobs, isEmpty);
        store.dispose();
      },
    );

    test(
      'editing then deleting a reminder leaves nothing in the platform',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        SharedPreferences.setMockInitialValues({});
        final plugin = FakeNotificationPlugin();
        final service = await _service(plugin, InMemoryReminderLedgerStore());
        ReminderService.instance = service;
        final (store, _) = await makeStore(
          boards: [Board(id: 'b1', name: 'Board', createdAt: 1)],
          tasks: [_task('t1')],
        );

        final task = store.tasks.single;
        final soon = DateTime.now().millisecondsSinceEpoch + 600000;
        store.updateTask(Task.fromJson(task.toJson())..reminderAt = soon);
        store.updateTask(
          Task.fromJson(task.toJson())..reminderAt = soon + 60000,
        );
        store.updateTask(Task.fromJson(task.toJson())..reminderAt = null);
        store.deleteTask(task.id);
        await store.reconcileReminders();

        expect(plugin.nativePending, isEmpty);
        expect(service.pendingJobs, isEmpty);
        expect(service.scheduleFailures.value, isEmpty);
        expect(service.cancelFailures.value, isEmpty);
        store.dispose();
      },
    );

    test(
      'a cancel that fails while the task is deleted keeps a retry record',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        SharedPreferences.setMockInitialValues({});
        final plugin = FakeNotificationPlugin();
        final service = await _service(plugin, InMemoryReminderLedgerStore());
        ReminderService.instance = service;
        final trigger = DateTime.now().millisecondsSinceEpoch + 600000;
        final (store, _) = await makeStore(
          boards: [Board(id: 'b1', name: 'Board', createdAt: 1)],
          tasks: [_task('t1', reminderAt: trigger)],
        );
        await store.reconcileReminders();
        expect(plugin.nativePending, {_id('t1')});

        plugin.failCancel = true;
        store.deleteTask('t1');
        await _flush(service);

        expect(service.cancelFailures.value.values.single.taskId, 't1');
        // Reconciling cannot re-arm a reminder whose task is gone, but it does
        // re-issue the cancellation the platform never confirmed.
        plugin.failCancel = false;
        final report = await service.reconcilePending(store.tasks);
        expect(report.recovered, 1);
        expect(plugin.nativePending, isEmpty);
        expect(service.cancelFailures.value, isEmpty);
        store.dispose();
      },
    );
  });

  group('OS17 settings test reminder', () {
    Future<void> tapKey(WidgetTester tester, Key key) async {
      final button = find.byKey(key);
      await tester.scrollUntilVisible(
        button,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(button, findsOneWidget);
      await tester.tap(button);
      await tester.pumpAndSettle();
    }

    Future<Store> pumpSettings(
      WidgetTester tester,
      ReminderService service,
    ) async {
      // The reminders section sits far down a lazily built settings list.
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      ReminderService.instance = service;
      final (store, _) = await makeStore(
        boards: [Board(id: 'b1', name: 'Board', createdAt: 1)],
      );
      await tester.pumpWidget(fixture.app(store, const SettingsScreen()));
      await tester.pumpAndSettle();
      return store;
    }

    testWidgets('a rejected test notification is never reported as sent', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final service = InMemoryReminderService()
        ..scheduleFault = StateError('synthetic');
      final store = await pumpSettings(tester, service);

      await tapKey(tester, const ValueKey('test-android-notif-btn'));

      expect(
        find.textContaining(store.t['reminderTestFailed']!),
        findsOneWidget,
      );
      expect(
        find.textContaining(store.t['testNotificationSent']!),
        findsNothing,
      );
      expect(service.pendingJobs, isEmpty);
      debugDefaultTargetPlatformOverride = null;
      fixture.settle(tester, store);
    });

    testWidgets('an accepted test notification is reported as accepted', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final service = InMemoryReminderService();
      final store = await pumpSettings(tester, service);

      await tapKey(tester, const ValueKey('test-android-notif-btn'));

      expect(
        find.textContaining(store.t['testNotificationSent']!),
        findsOneWidget,
      );
      expect(service.scheduled.keys, contains(_id('test-win-notif')));
      debugDefaultTargetPlatformOverride = null;
      fixture.settle(tester, store);
    });

    testWidgets('permission check shows unknown instead of a false grant', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      final service = InMemoryReminderService(
        permission: ReminderPermissionStatus.unknown,
      );
      final store = await pumpSettings(tester, service);

      final button = find.byKey(const ValueKey('check-permissions-btn'));
      await tester.scrollUntilVisible(
        button,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text(store.t['permissionUnknown']!), findsOneWidget);
      expect(find.text(store.t['permissionGranted']!), findsNothing);
      debugDefaultTargetPlatformOverride = null;
      fixture.settle(tester, store);
    });
  });

  group('OS17 failure banner', () {
    Future<Store> pumpBanner(
      WidgetTester tester,
      ReminderService service,
    ) async {
      SharedPreferences.setMockInitialValues({});
      ReminderService.instance = service;
      final (store, _) = await makeStore(
        boards: [Board(id: 'b1', name: 'Board', createdAt: 1)],
        tasks: [
          _task(
            't1',
            reminderAt: DateTime.now().millisecondsSinceEpoch + 600000,
          ),
        ],
      );
      await tester.pumpWidget(
        ChangeNotifierProvider<Store>.value(
          value: store,
          child: MaterialApp(
            home: Scaffold(
              body: ListView(children: const [ReminderFailureBanner()]),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return store;
    }

    testWidgets('schedule and cancel failures get separate rows and retries', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final service = InMemoryReminderService()
        ..scheduleFault = StateError('synthetic');
      final store = await pumpBanner(tester, service);
      final trigger = DateTime.now().millisecondsSinceEpoch + 600000;

      await service.scheduleReminder(
        boardId: 'b1',
        taskId: 't1',
        title: 'Synthetic t1',
        triggerAtMs: trigger,
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('reminder-schedule-failure')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('reminder-cancel-failure')),
        findsNothing,
      );

      // A cancel failure is a different problem with a different retry.
      service
        ..scheduleFault = null
        ..cancelFault = StateError('synthetic');
      await service.cancelReminder('missing-task');
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('reminder-cancel-failure')),
        findsOneWidget,
      );

      service.cancelFault = null;
      await tester.tap(
        find.byKey(const ValueKey('retry-reminder-cancellations')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('reminder-cancel-failure')),
        findsNothing,
      );

      service.scheduleFault = null;
      await tester.tap(find.byKey(const ValueKey('retry-reminders')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('reminder-schedule-failure')),
        findsNothing,
      );
      expect(service.pendingJobs, isEmpty);
      debugDefaultTargetPlatformOverride = null;
      fixture.settle(tester, store);
    });

    testWidgets('an unknown permission state is called out, not hidden', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      final service = InMemoryReminderService(
        permission: ReminderPermissionStatus.unknown,
      )..scheduleFault = StateError('synthetic');
      final store = await pumpBanner(tester, service);
      await service.checkPermission();
      await service.scheduleReminder(
        boardId: 'b1',
        taskId: 't1',
        title: 'Synthetic t1',
        triggerAtMs: DateTime.now().millisecondsSinceEpoch + 600000,
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('reminder-permission-unknown')),
        findsOneWidget,
      );
      expect(find.text(store.t['permissionUnknown']!), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
      fixture.settle(tester, store);
    });
  });
}
