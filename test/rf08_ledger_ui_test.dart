// RF08 ledger visibility: a retry ledger that cannot be read, written or
// extended must not look like "nothing is pending". Synthetic tasks, an
// in-memory ledger double and a fake reminder service only: no credentials, no
// real notifications, and no claim that a platform will deliver anything.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/l10n.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/storage.dart';
import 'package:matrixflow_native/widgets/reminder_failure_banner.dart';

import 'foundation_regression_test.dart' as fixture;
import 'helpers.dart';

/// Ledger double that can refuse reads or writes on demand, so the banner sees
/// the same reported issues a real local storage failure would produce.
class FlakyLedger implements ReminderLedgerStore {
  FlakyLedger({this.seed});

  String? seed;
  String? written;
  bool stored = false;
  bool failReads = false;
  bool failWrites = false;
  int writeCount = 0;

  @override
  Future<String?> read() async {
    if (failReads) throw StateError('synthetic ledger read failure');
    // A completed write, including a removal, is authoritative.
    return stored ? written : seed;
  }

  @override
  Future<void> write(String? next) async {
    writeCount++;
    if (failWrites) throw StateError('synthetic ledger write failure');
    written = next;
    stored = true;
  }
}

Task _task(String id, {int? reminderAt}) => Task(
  id: id,
  boardId: 'b1',
  title: 'Synthetic $id',
  quadrant: 1,
  createdAt: 1,
  reminderAt: reminderAt,
);

int _nowMs() => DateTime.now().millisecondsSinceEpoch;

ReminderPendingJob _job(String taskId) => ReminderPendingJob(
  kind: ReminderPendingKind.reschedule,
  notificationId: generateNotificationId(taskId),
  boardId: 'b1',
  taskId: taskId,
  triggerAtMs: _nowMs() + 600000,
  firstFailedAtMs: 5000,
  updatedAtMs: 5000,
);

Widget _host() => Scaffold(
  body: ListView(children: const [ReminderFailureBanner()]),
);

/// Route for every screen the banner is mounted on.
ValueKey<String> _row(String state) => ValueKey('reminder-ledger-$state');
const ValueKey<String> _ledgerRetry = ValueKey('retry-reminder-ledger');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => ReminderService.resetForTest());

  /// Pumps the banner on a store that uses [service] for reminder work.
  Future<Store> pumpBanner(
    WidgetTester tester,
    ReminderService service, {
    List<Task>? tasks,
  }) async {
    ReminderService.instance = service;
    final (store, _) = await makeStore(
      boards: [Board(id: 'b1', name: 'Board', createdAt: 1)],
      tasks: tasks,
    );
    await tester.pumpWidget(fixture.app(store, _host()));
    await tester.pumpAndSettle();
    return store;
  }

  testWidgets('an unreadable ledger is shown and can be read again', (
    tester,
  ) async {
    final ledger = FlakyLedger()..failReads = true;
    final service = InMemoryReminderService(ledgerStore: ledger);
    final store = await pumpBanner(tester, service);
    await service.loadPendingJobs();
    await tester.pumpAndSettle();

    expect(find.byKey(_row('read')), findsOneWidget);
    expect(
      find.textContaining(store.t['reminderLedgerUnreadable']!),
      findsOneWidget,
      reason: 'the row explains which records are in question',
    );
    // The other three states must not be reachable from one issue.
    expect(find.byKey(_row('write')), findsNothing);
    expect(find.byKey(_row('overflow')), findsNothing);
    expect(find.byKey(_row('damaged')), findsNothing);

    // Recovery is the service withdrawing the issue, not a UI timer.
    ledger.failReads = false;
    await tester.tap(find.byKey(_ledgerRetry));
    await tester.pumpAndSettle();
    expect(service.ledgerIssue.value, isNull);
    expect(find.byKey(_row('read')), findsNothing);
    expect(find.byKey(_ledgerRetry), findsNothing);
    fixture.settle(tester, store);
  });

  testWidgets('a ledger that cannot be written is shown and blocks a clean save', (
    tester,
  ) async {
    final ledger = FlakyLedger()..failWrites = true;
    final service = InMemoryReminderService(ledgerStore: ledger);
    final store = await pumpBanner(tester, service);

    await service.trackPendingJob(_job('t1'));
    await service.pendingLedgerWrites();
    await tester.pumpAndSettle();

    expect(find.byKey(_row('write')), findsOneWidget);
    expect(
      find.textContaining(store.t['reminderLedgerWriteFailed']!),
      findsOneWidget,
    );
    expect(
      (await store.flush(includeReminderLedger: true)).success,
      isFalse,
      reason: 'exit must not report a clean save while the ledger is unwritten',
    );
    expect(
      (await store.flush()).success,
      isTrue,
      reason: 'a data-only barrier keeps the library contract',
    );

    ledger.failWrites = false;
    await tester.tap(find.byKey(_ledgerRetry));
    await tester.pumpAndSettle();
    expect(service.ledgerIssue.value, isNull);
    expect(find.byKey(_row('write')), findsNothing);
    expect(ledger.written, contains('reschedule'), reason: 'the retry lands it');
    fixture.settle(tester, store);
  });

  testWidgets('a full ledger says how many records it refused and offers no retry', (
    tester,
  ) async {
    final service = InMemoryReminderService(ledgerStore: FlakyLedger());
    final store = await pumpBanner(tester, service);
    for (var i = 0; i < ReminderService.maxPendingJobs; i++) {
      await service.trackPendingJob(_job('filler-$i'));
    }
    await service.pendingLedgerWrites();
    await tester.pumpAndSettle();
    expect(find.byKey(_row('overflow')), findsNothing);

    final refused = await service.trackPendingJob(_job('one-too-many'));
    await service.pendingLedgerWrites();
    await tester.pumpAndSettle();

    expect(refused, ReminderLedgerUpdate.rejected);
    expect(find.byKey(_row('overflow')), findsOneWidget);
    expect(
      find.text(
        store.t['reminderLedgerFull']!
            .replaceAll('{count}', '${service.refusedRecords}')
            .replaceAll('{cap}', '${ReminderService.maxPendingJobs}'),
      ),
      findsOneWidget,
      reason: 'the count and the cap tell the user what the limit did',
    );
    expect(
      find.byKey(_ledgerRetry),
      findsNothing,
      reason: 'a full ledger is a fact; retrying it would change nothing',
    );
    fixture.settle(tester, store);
  });

  testWidgets('records skipped as damaged are counted instead of vanishing', (
    tester,
  ) async {
    final ledger = FlakyLedger(
      seed: jsonEncode({
        'v': 1,
        'jobs': [
          _job('t1').toJson(),
          {'kind': 'not-a-kind', 'id': 2, 'taskId': 't2'},
        ],
      }),
    );
    final service = InMemoryReminderService(ledgerStore: ledger);
    final store = await pumpBanner(tester, service);
    await service.loadPendingJobs();
    await tester.pumpAndSettle();

    expect(find.byKey(_row('damaged')), findsOneWidget);
    expect(
      find.text(
        store.t['reminderLedgerDamaged']!.replaceAll('{count}', '1'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(_ledgerRetry), findsNothing);
    fixture.settle(tester, store);
  });

  testWidgets('ledger states replace each other and leave nothing cached', (
    tester,
  ) async {
    final ledger = FlakyLedger()..failReads = true;
    final service = InMemoryReminderService(ledgerStore: ledger);
    final store = await pumpBanner(tester, service);
    await service.loadPendingJobs();
    await tester.pumpAndSettle();
    expect(find.byKey(_row('read')), findsOneWidget);

    // The read succeeds, so the read row must go before any write happens.
    ledger.failReads = false;
    await tester.tap(find.byKey(_ledgerRetry));
    await tester.pumpAndSettle();
    expect(find.byKey(_row('read')), findsNothing);

    // A storage that refuses writes reports the write state instead.
    ledger.failWrites = true;
    await service.trackPendingJob(_job('t1'));
    await service.pendingLedgerWrites();
    await tester.pumpAndSettle();
    expect(find.byKey(_row('write')), findsOneWidget);
    expect(find.byKey(_row('read')), findsNothing);

    // A ledger that is full reports the refusal instead of the write state.
    ledger.failWrites = false;
    for (var i = 0; i < ReminderService.maxPendingJobs; i++) {
      await service.trackPendingJob(_job('filler-$i'));
    }
    await service.trackPendingJob(_job('one-too-many'));
    await service.pendingLedgerWrites();
    await tester.pumpAndSettle();
    expect(find.byKey(_row('overflow')), findsOneWidget);
    expect(find.byKey(_row('write')), findsNothing);

    // A refused ledger has no service-side clear path yet, so the widget is
    // proven reactive directly: withdrawing the issue removes every ledger row
    // instead of leaving the last one cached on screen.
    service.ledgerIssue.value = null;
    await tester.pumpAndSettle();
    expect(find.byKey(_row('overflow'), skipOffstage: false), findsNothing);
    expect(find.byKey(_row('write'), skipOffstage: false), findsNothing);
    expect(find.byKey(_row('read'), skipOffstage: false), findsNothing);
    expect(
      find.byKey(const ValueKey('reminder-schedule-failure')),
      findsOneWidget,
      reason: 'the pending records are still reported as unarmed reminders',
    );
    fixture.settle(tester, store);
  });

  testWidgets('leaving the page drops every reminder subscription', (
    tester,
  ) async {
    final ledger = FlakyLedger()..failReads = true;
    final service = InMemoryReminderService(ledgerStore: ledger);
    final store = await pumpBanner(tester, service);
    await service.loadPendingJobs();
    await tester.pumpAndSettle();
    expect(find.byKey(_row('read')), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    // A late report from the service must not reach a disposed state.
    service.ledgerIssue.value = const ReminderLedgerIssue(
      kind: ReminderLedgerIssueKind.write,
      errorKind: 'synthetic late failure',
    );
    service.scheduleFailures.value = {
      1: const ReminderPayload(boardId: 'b1', taskId: 't1'),
    };
    service.cancelFailures.value = {
      2: const ReminderPayload(boardId: 'b1', taskId: 't2'),
    };
    service.observedPermission.value = ReminderPermissionStatus.unknown;
    await tester.pump();
    expect(tester.takeException(), isNull);

    // Rebuilding the page shows the current state, not the rows it used to show.
    service.ledgerIssue.value = null;
    service.scheduleFailures.value = {};
    service.cancelFailures.value = {};
    service.observedPermission.value = null;
    await tester.pumpWidget(fixture.app(store, _host()));
    await tester.pumpAndSettle();
    // A banner with nothing to report collapses to an empty row, so the page is
    // checked with offstage widgets included: the rows are what must be absent.
    expect(
      find.byType(ReminderFailureBanner, skipOffstage: false),
      findsOneWidget,
    );
    expect(find.byKey(_row('read'), skipOffstage: false), findsNothing);
    expect(find.byKey(_row('write'), skipOffstage: false), findsNothing);

    service.ledgerIssue.value = const ReminderLedgerIssue(
      kind: ReminderLedgerIssueKind.overflow,
      count: 2,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(_row('overflow')), findsOneWidget);
    fixture.settle(tester, store);
  });

  testWidgets('a ledger problem keeps the schedule and cancel rows working', (
    tester,
  ) async {
    final trigger = _nowMs() + 600000;
    final ledger = FlakyLedger()..failWrites = true;
    final service = InMemoryReminderService(ledgerStore: ledger)
      ..scheduleFault = StateError('synthetic schedule rejection');
    final store = await pumpBanner(
      tester,
      service,
      tasks: [_task('t1', reminderAt: trigger)],
    );

    await service.scheduleReminder(
      boardId: 'b1',
      taskId: 't1',
      title: 'Synthetic t1',
      triggerAtMs: trigger,
    );
    await service.pendingLedgerWrites();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reminder-schedule-failure')), findsOneWidget);
    expect(find.byKey(_row('write')), findsOneWidget);

    // The original retry keeps its own semantics and still clears its row.
    service.scheduleFault = null;
    ledger.failWrites = false;
    await tester.tap(find.byKey(const ValueKey('retry-reminders')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reminder-schedule-failure')), findsNothing);
    expect(find.byKey(_row('write')), findsNothing);
    expect(service.ledgerIssue.value, isNull);
    fixture.settle(tester, store);
  });

  test('the ledger copy exists in every language and promises no delivery', () {
    const keys = [
      'reminderLedgerUnreadable',
      'reminderLedgerWriteFailed',
      'reminderLedgerFull',
      'reminderLedgerDamaged',
    ];
    final banned = RegExp('100%|绝对|絶対|必ず届|一定送达|guaranteed|保証します');
    Set<String> placeholders(String value) => RegExp(
      r'\{([A-Za-z0-9_]+)\}',
    ).allMatches(value).map((m) => m.group(1)!).toSet();

    for (final language in Language.values) {
      for (final key in keys) {
        final value = dictOf(language)[key];
        expect(value, isNotNull, reason: '${language.name}.$key is missing');
        expect(value, isNotEmpty, reason: '${language.name}.$key is empty');
        expect(
          banned.hasMatch(value!),
          isFalse,
          reason: '${language.name}.$key may not promise delivery',
        );
      }
      expect(
        placeholders(dictOf(language)['reminderLedgerFull']!),
        placeholders(dictOf(Language.en)['reminderLedgerFull']!),
        reason: '$language reminderLedgerFull placeholder mismatch',
      );
      expect(
        placeholders(dictOf(language)['reminderLedgerDamaged']!),
        placeholders(dictOf(Language.en)['reminderLedgerDamaged']!),
        reason: '$language reminderLedgerDamaged placeholder mismatch',
      );
    }
  });
}
