// RF08 ledger issue lifecycle: a full or damaged ledger banner must have a
// defined clearing time. Synthetic tasks, an in-memory ledger double and a fake
// reminder service only: no credentials, no real notifications, and no claim
// that a platform will deliver anything.
//
// The two lifecycles under test:
//   full ledger      -> capacity released -> reconcile again
//   damaged records  -> ledger repaired   -> read again / restart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/l10n.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/storage.dart';
import 'package:matrixflow_native/widgets/reminder_failure_banner.dart';

import 'foundation_regression_test.dart' as fixture;
import 'helpers.dart';

/// Ledger double that can be seeded with raw bytes and made to refuse writes,
/// so both the damaged and the repaired state are reachable without a device.
class SeededLedger implements ReminderLedgerStore {
  SeededLedger({this.seed});

  String? seed;
  String? written;
  bool stored = false;
  bool failWrites = false;
  bool failReads = false;
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

Task _task(String id, {int? reminderAt, bool completed = false}) => Task(
  id: id,
  boardId: 'b1',
  title: 'Synthetic $id',
  quadrant: 1,
  createdAt: 1,
  reminderAt: reminderAt,
  completed: completed,
);

int _nowMs() => DateTime.now().millisecondsSinceEpoch;

/// One non-exhausted filler record, so the ledger can be brought to its cap
/// without depending on the platform.
ReminderPendingJob _filler(int i) => ReminderPendingJob(
  kind: ReminderPendingKind.reschedule,
  notificationId: 1000 + i,
  boardId: 'b1',
  taskId: 'filler-$i',
  triggerAtMs: _nowMs() + 600000,
  firstFailedAtMs: 1000 + i,
  updatedAtMs: 1000 + i,
);

String _fillerKey(int i) => '${ReminderPendingKind.reschedule.name}:${1000 + i}';

int _id(String taskId) => generateNotificationId(taskId);
String _key(String taskId) => '${ReminderPendingKind.reschedule.name}:${_id(taskId)}';

/// Brings the ledger exactly to its cap and returns the service.
Future<InMemoryReminderService> _fullLedger(ReminderLedgerStore ledger) async {
  final service = InMemoryReminderService(ledgerStore: ledger);
  for (var i = 0; i < ReminderService.maxPendingJobs; i++) {
    expect(await service.trackPendingJob(_filler(i)), ReminderLedgerUpdate.recorded);
  }
  expect(service.pendingJobs, hasLength(ReminderService.maxPendingJobs));
  return service;
}

Widget _host() => Scaffold(
  body: ListView(children: const [ReminderFailureBanner()]),
);

ValueKey<String> _row(String state) => ValueKey('reminder-ledger-$state');
const ValueKey<String> _ledgerRetry = ValueKey('retry-reminder-ledger');
const ValueKey<String> _ledgerRepair = ValueKey('repair-reminder-ledger');

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

  group('RF08 a full ledger recovers the reminder it refused', () {
    test('a freed slot puts the refused reminder back instead of forgetting it', () async {
      final trigger = _nowMs() + 600000;
      final tasks = [_task('t-new', reminderAt: trigger)];
      final service = await _fullLedger(SeededLedger())
        ..scheduleFault = StateError('synthetic schedule rejection');

      // A reminder the user still expects arrives while the ledger is full.
      final refused = await service.scheduleReminder(
        boardId: 'b1',
        taskId: 't-new',
        title: 'Synthetic t-new',
        triggerAtMs: trigger,
      );
      expect(refused.needsRetry, isTrue);
      expect(service.ledgerIssue.value?.kind, ReminderLedgerIssueKind.overflow);
      expect(service.refusedRecords, 1);
      expect(
        service.pendingJobs.containsKey(_key('t-new')),
        isFalse,
        reason: 'a full ledger refused the record, so it is not tracked yet',
      );

      // Capacity is released, then reconciliation runs again.
      await service.clearPendingJob(_fillerKey(0));
      final report = await service.reconcilePending(tasks);

      expect(
        service.ledgerIssue.value,
        isNull,
        reason: 'with capacity back, the full-ledger fact must not stay on screen',
      );
      expect(
        service.pendingJobs.containsKey(_key('t-new')),
        isTrue,
        reason: 'the refused reminder is tracked again, not silently forgotten',
      );
      expect(report.retried, greaterThanOrEqualTo(1));
      expect(service.scheduleFailures.value.values.map((p) => p.taskId), contains('t-new'));

      // And once the channel works again the recovered record is really retried.
      service.scheduleFault = null;
      final recovered = await service.reconcilePending(tasks);
      expect(recovered.recovered, 1);
      expect(service.pendingJobs.containsKey(_key('t-new')), isFalse);
      expect(service.scheduleFailures.value.isEmpty, isTrue);
      expect(service.ledgerIssue.value, isNull);
      expect(service.refusedRecords, 1, reason: 'the refusal was still counted once');
    });

    test('a reconcile pass that frees slots hands them to the refused work', () async {
      final trigger = _nowMs() + 600000;
      final tasks = [_task('t-new', reminderAt: trigger)];
      final service = await _fullLedger(SeededLedger())
        ..scheduleFault = StateError('synthetic schedule rejection');
      await service.scheduleReminder(
        boardId: 'b1',
        taskId: 't-new',
        title: 'Synthetic t-new',
        triggerAtMs: trigger,
      );
      expect(service.ledgerIssue.value?.kind, ReminderLedgerIssueKind.overflow);

      // This pass is the one that frees capacity: it drops the filler records,
      // which no task backs any more. The refused reminder must get one of those
      // slots instead of being left behind by the pass that freed them.
      final report = await service.reconcilePending(tasks);
      expect(report.dropped, ReminderService.maxPendingJobs);
      expect(
        service.pendingJobs.containsKey(_key('t-new')),
        isTrue,
        reason: 'a freed slot belongs to the refused reminder, not to nobody',
      );
      expect(service.ledgerIssue.value, isNull);

      // And the next pass retries it like any other pending record.
      service.scheduleFault = null;
      final recovered = await service.reconcilePending(tasks);
      expect(recovered.recovered, 1);
      expect(service.pendingJobs, isEmpty);
      expect(service.scheduleFailures.value, isEmpty);
    });

    test('a refusal for a reminder the data no longer backs goes away with it', () async {
      final trigger = _nowMs() + 600000;
      final service = await _fullLedger(SeededLedger())
        ..scheduleFault = StateError('synthetic schedule rejection');
      await service.scheduleReminder(
        boardId: 'b1',
        taskId: 't-done',
        title: 'Synthetic t-done',
        triggerAtMs: trigger,
      );
      expect(service.ledgerIssue.value?.kind, ReminderLedgerIssueKind.overflow);
      expect(service.refusedRecords, 1);

      // The user completed the task, so nothing backs the refused reminder.
      final report = await service.reconcilePending([
        _task('t-done', reminderAt: trigger, completed: true),
      ]);

      expect(
        service.ledgerIssue.value,
        isNull,
        reason: 'the refusal left with the reminder it belonged to',
      );
      expect(service.pendingJobs.containsKey(_key('t-done')), isFalse);
      expect(service.scheduleFailures.value.isEmpty, isTrue);
      expect(
        report.retried,
        0,
        reason: 'a reminder the data no longer backs is not re-armed',
      );
    });

    test('a full clear owns the refusals too', () async {
      final trigger = _nowMs() + 600000;
      final service = await _fullLedger(SeededLedger())
        ..scheduleFault = StateError('synthetic schedule rejection');
      await service.scheduleReminder(
        boardId: 'b1',
        taskId: 't-new',
        title: 'Synthetic t-new',
        triggerAtMs: trigger,
      );
      expect(service.ledgerIssue.value?.kind, ReminderLedgerIssueKind.overflow);

      await service.clearAllPendingJobs();
      expect(service.pendingJobs, isEmpty);
      expect(
        service.ledgerIssue.value,
        isNull,
        reason: 'a deliberate wipe clears the refusal row as well',
      );
    });
  });

  group('RF08 a damaged ledger has a repair path', () {
    /// One readable record plus one record that cannot be parsed.
    String damagedSeed() => jsonEncode({
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
        {'kind': 'not-a-kind', 'id': 2, 'taskId': 't2'},
      ],
    });

    test('a clean write repairs the stored ledger and clears the damaged row', () async {
      final ledger = SeededLedger(seed: damagedSeed());
      final service = InMemoryReminderService(ledgerStore: ledger);
      await service.loadPendingJobs();
      expect(service.ledgerIssue.value?.kind, ReminderLedgerIssueKind.damaged);
      expect(service.ledgerIssue.value?.count, 1);
      expect(service.pendingJobs, hasLength(1), reason: 'the readable record loaded');

      // Repairing means giving up the unreadable records and rewriting the
      // ones this read could keep, so the stored bytes stop containing garbage.
      expect(await service.retryPendingLedger(), isTrue);
      expect(
        service.ledgerIssue.value,
        isNull,
        reason: 'the explicit repair is the confirmation behind the skip notice',
      );
      expect(ledger.written, isNotNull);
      expect(ledger.written, isNot(contains('not-a-kind')));

      // A restart reads the repaired bytes and reports nothing.
      final afterRestart = InMemoryReminderService(ledgerStore: ledger);
      await afterRestart.loadPendingJobs();
      expect(afterRestart.ledgerIssue.value, isNull);
      expect(afterRestart.pendingJobs, hasLength(1));
    });

    test('an incidental write does not hide the skip notice', () async {
      final ledger = SeededLedger(seed: damagedSeed());
      final service = InMemoryReminderService(ledgerStore: ledger);
      await service.loadPendingJobs();
      expect(service.ledgerIssue.value?.kind, ReminderLedgerIssueKind.damaged);

      // Any ordinary reminder failure rewrites the stored list. That write must
      // not make the notice disappear before the user ever saw it.
      await service.trackPendingJob(
        ReminderPendingJob(
          kind: ReminderPendingKind.reschedule,
          notificationId: 4242,
          boardId: 'b1',
          taskId: 't-live',
          triggerAtMs: _nowMs() + 600000,
          firstFailedAtMs: 2000,
          updatedAtMs: 2000,
        ),
      );
      expect((await service.pendingLedgerWrites()).success, isTrue);
      expect(
        service.ledgerIssue.value?.kind,
        ReminderLedgerIssueKind.damaged,
        reason: 'only a repair or a clean read may clear the skip notice',
      );
      expect(ledger.written, isNot(contains('not-a-kind')));

      // The rewritten bytes are clean, so the next process reports nothing.
      final afterRestart = InMemoryReminderService(ledgerStore: ledger);
      await afterRestart.loadPendingJobs();
      expect(afterRestart.ledgerIssue.value, isNull);
      expect(afterRestart.pendingJobs, hasLength(2));
    });

    test('an unrepaired ledger is reported again instead of being cleared', () async {
      final ledger = SeededLedger(seed: damagedSeed());
      final first = InMemoryReminderService(ledgerStore: ledger);
      await first.loadPendingJobs();
      expect(first.ledgerIssue.value?.kind, ReminderLedgerIssueKind.damaged);

      // No write happened, so a fresh process must still report the damage.
      final second = InMemoryReminderService(ledgerStore: ledger);
      await second.loadPendingJobs();
      expect(
        second.ledgerIssue.value?.kind,
        ReminderLedgerIssueKind.damaged,
        reason: 'nothing repaired the bytes, so the row must come back',
      );
      expect(second.ledgerIssue.value?.count, 1);
    });

    test('a failing repair reports the write problem instead of hiding it', () async {
      final ledger = SeededLedger(seed: damagedSeed())..failWrites = true;
      final service = InMemoryReminderService(ledgerStore: ledger);
      await service.loadPendingJobs();
      expect(service.ledgerIssue.value?.kind, ReminderLedgerIssueKind.damaged);

      expect(await service.retryPendingLedger(), isFalse);
      expect(
        service.ledgerIssue.value?.kind,
        ReminderLedgerIssueKind.write,
        reason: 'a repair that could not land is the write problem, not success',
      );

      ledger.failWrites = false;
      expect(await service.retryPendingLedger(), isTrue);
      expect(service.ledgerIssue.value, isNull);
    });
  });

  group('RF08 the banner follows the service lifecycle', () {
    testWidgets('a damaged ledger offers a repair that really clears the row', (tester) async {
      final ledger = SeededLedger(
        seed: jsonEncode({
          'v': 1,
          'jobs': [
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
        find.text(store.t['reminderLedgerDamaged']!.replaceAll('{count}', '1')),
        findsOneWidget,
      );
      // The damaged row may not reuse the plain retry label: it names a repair.
      expect(find.byKey(_ledgerRetry), findsNothing);
      expect(find.byKey(_ledgerRepair), findsOneWidget);

      await tester.tap(find.byKey(_ledgerRepair));
      await tester.pumpAndSettle();
      expect(service.ledgerIssue.value, isNull);
      expect(find.byKey(_row('damaged'), skipOffstage: false), findsNothing);
      expect(find.byKey(_ledgerRepair, skipOffstage: false), findsNothing);
      fixture.settle(tester, store);
    });

    testWidgets('the full-ledger row offers no retry and leaves once work is recovered', (
      tester,
    ) async {
      final trigger = _nowMs() + 600000;
      final service = InMemoryReminderService(ledgerStore: SeededLedger())
        ..scheduleFault = StateError('synthetic schedule rejection');
      final store = await pumpBanner(tester, service);
      for (var i = 0; i < ReminderService.maxPendingJobs; i++) {
        await service.trackPendingJob(_filler(i));
      }
      await service.scheduleReminder(
        boardId: 'b1',
        taskId: 't-new',
        title: 'Synthetic t-new',
        triggerAtMs: trigger,
      );
      await tester.pumpAndSettle();

      expect(find.byKey(_row('overflow')), findsOneWidget);
      expect(find.byKey(_ledgerRetry), findsNothing);
      expect(
        find.byKey(_ledgerRepair),
        findsNothing,
        reason: 'a full ledger is fixed by freeing capacity, not by a button',
      );

      // Freeing a slot is the recovery condition the service acts on.
      await service.clearPendingJob(_fillerKey(0));
      await tester.pumpAndSettle();
      expect(find.byKey(_row('overflow'), skipOffstage: false), findsNothing);
      expect(
        find.byKey(const ValueKey('reminder-schedule-failure')),
        findsOneWidget,
        reason: 'the recovered reminder is still reported as unarmed',
      );
      fixture.settle(tester, store);
    });
  });

  test('the repair label exists in every language and promises no delivery', () {
    final banned = RegExp('100%|绝对|絶対|必ず届|一定送达|guaranteed|保証します');
    for (final language in Language.values) {
      final value = dictOf(language)['reminderLedgerRepair'];
      expect(value, isNotNull, reason: '${language.name} is missing the repair label');
      expect(value, isNotEmpty, reason: '${language.name} repair label is empty');
      expect(
        banned.hasMatch(value!),
        isFalse,
        reason: '${language.name} repair label may not promise delivery',
      );
    }
  });
}
