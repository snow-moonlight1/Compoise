import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../storage.dart';

/// Pending reminder work stays visible until the platform confirms it.
///
/// Schedule and cancellation failures are separate rows because they need
/// opposite retries, and an undetectable permission state is called out
/// instead of being reported as granted. A retry ledger that could not be
/// read, written or extended is reported the same way: without a row the
/// storage problem would look like "nothing is pending".
class ReminderFailureBanner extends StatefulWidget {
  const ReminderFailureBanner({super.key});

  @override
  State<ReminderFailureBanner> createState() => _ReminderFailureBannerState();
}

class _ReminderFailureBannerState extends State<ReminderFailureBanner> {
  bool _retryingSchedule = false;
  bool _retryingCancel = false;
  bool _retryingLedger = false;

  String _names(Store store, Iterable<ReminderPayload> payloads) {
    final names =
        payloads
            .map((p) {
              final task = store.tasks
                  .where((t) => t.id == p.taskId)
                  .firstOrNull;
              return task?.subtasks
                      .where((s) => s.id == p.subtaskId)
                      .firstOrNull
                      ?.title ??
                  task?.title ??
                  '';
            })
            .where((s) => s.isNotEmpty)
            .take(3)
            .join(', ');
    return names;
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<Store>();
    return ValueListenableBuilder<ReminderLedgerIssue?>(
      valueListenable: store.reminderService.ledgerIssue,
      builder: (context, ledgerIssue, _) => _failures(store, ledgerIssue),
    );
  }

  /// Rows for everything the banner reports: pending schedule and cancellation
  /// work plus whatever the retry ledger says about its own storage. The ledger
  /// row is driven straight from the notifier, so it disappears as soon as the
  /// service withdraws the issue instead of being cached here.
  Widget _failures(Store store, ReminderLedgerIssue? ledgerIssue) {
    return ValueListenableBuilder<Map<int, ReminderPayload>>(
      valueListenable: store.reminderService.scheduleFailures,
      builder: (context, scheduleFailures, _) =>
          ValueListenableBuilder<Map<int, ReminderPayload>>(
            valueListenable: store.reminderService.cancelFailures,
            builder:
                (context, cancelFailures, _) =>
                    ValueListenableBuilder<ReminderPermissionStatus?>(
                      valueListenable:
                          store.reminderService.observedPermission,
                      builder: (context, permission, _) {
                        final hasFailures =
                            scheduleFailures.isNotEmpty ||
                            cancelFailures.isNotEmpty;
                        final rows = <Widget>[
                          if (scheduleFailures.isNotEmpty)
                            _row(
                              context,
                              bannerKey: const ValueKey('reminder-schedule-failure'),
                              buttonKey: const ValueKey('retry-reminders'),
                              message: store.t['reminderScheduleFailed']!,
                              names: _names(
                                store,
                                scheduleFailures.values,
                              ),
                              busy: _retryingSchedule,
                              onRetry: () async {
                                setState(() => _retryingSchedule = true);
                                try {
                                  for (final payload
                                      in scheduleFailures.values.toList()) {
                                    await store.retryReminder(payload);
                                  }
                                } finally {
                                  if (mounted) {
                                    setState(() => _retryingSchedule = false);
                                  }
                                }
                              },
                            ),
                          if (cancelFailures.isNotEmpty)
                            _row(
                              context,
                              bannerKey: const ValueKey('reminder-cancel-failure'),
                              buttonKey: const ValueKey(
                                'retry-reminder-cancellations',
                              ),
                              message: store.t['reminderCancelFailed']!,
                              names: _names(store, cancelFailures.values),
                              busy: _retryingCancel,
                              onRetry: () async {
                                setState(() => _retryingCancel = true);
                                try {
                                  for (final payload
                                      in cancelFailures.values.toList()) {
                                    await store.retryReminderCancellation(
                                      payload,
                                    );
                                  }
                                } finally {
                                  if (mounted) {
                                    setState(() => _retryingCancel = false);
                                  }
                                }
                              },
                            ),
                          if (ledgerIssue != null)
                            _row(
                              context,
                              bannerKey: _ledgerKey(ledgerIssue.kind),
                              buttonKey: const ValueKey('retry-reminder-ledger'),
                              message: _ledgerMessage(store, ledgerIssue),
                              busy: _retryingLedger,
                              onRetry: _ledgerRetry(ledgerIssue.kind),
                            ),
                          if (hasFailures &&
                              permission == ReminderPermissionStatus.unknown)
                            _note(
                              context,
                              key: const ValueKey('reminder-permission-unknown'),
                              message: store.t['permissionUnknown']!,
                            ),
                          if (hasFailures &&
                              permission ==
                                  ReminderPermissionStatus.unsupported)
                            _note(
                              context,
                              key: const ValueKey(
                                'reminder-permission-unsupported',
                              ),
                              message: store.t['permissionUnsupported']!,
                            ),
                        ];
                        if (rows.isEmpty) return const SizedBox.shrink();
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: rows,
                        );
                      },
                    ),
          ),
    );
  }

  /// Identifies which ledger problem is on screen, so a regression test can
  /// tell the four states apart instead of only proving "something is shown".
  Key _ledgerKey(ReminderLedgerIssueKind kind) => switch (kind) {
    ReminderLedgerIssueKind.read => const ValueKey('reminder-ledger-read'),
    ReminderLedgerIssueKind.write => const ValueKey('reminder-ledger-write'),
    ReminderLedgerIssueKind.overflow => const ValueKey(
      'reminder-ledger-overflow',
    ),
    ReminderLedgerIssueKind.damaged => const ValueKey('reminder-ledger-damaged'),
  };

  /// What the ledger problem means for the user. The wording stays about the
  /// retry records this app keeps: it never promises that the system will
  /// deliver a notification.
  String _ledgerMessage(Store store, ReminderLedgerIssue issue) =>
      switch (issue.kind) {
        ReminderLedgerIssueKind.read => store.t['reminderLedgerUnreadable']!,
        ReminderLedgerIssueKind.write => store.t['reminderLedgerWriteFailed']!,
        ReminderLedgerIssueKind.overflow => store.t['reminderLedgerFull']!
            .replaceAll('{count}', '${issue.count}')
            .replaceAll('{cap}', '${ReminderService.maxPendingJobs}'),
        ReminderLedgerIssueKind.damaged => store.t['reminderLedgerDamaged']!
            .replaceAll('{count}', '${issue.count}'),
      };

  /// The action that actually fits the reported problem. A full ledger and
  /// records that were already skipped are facts about what is stored, so they
  /// are reported without a button that could not change them.
  Future<void> Function()? _ledgerRetry(ReminderLedgerIssueKind kind) =>
      switch (kind) {
        ReminderLedgerIssueKind.read => _rereadLedger,
        ReminderLedgerIssueKind.write => _rewriteLedger,
        ReminderLedgerIssueKind.overflow ||
        ReminderLedgerIssueKind.damaged => null,
      };

  Future<void> _rereadLedger() async {
    final service = context.read<Store>().reminderService;
    setState(() => _retryingLedger = true);
    try {
      await service.loadPendingJobs();
    } finally {
      if (mounted) setState(() => _retryingLedger = false);
    }
  }

  Future<void> _rewriteLedger() async {
    final service = context.read<Store>().reminderService;
    setState(() => _retryingLedger = true);
    try {
      await service.retryPendingLedger();
    } finally {
      if (mounted) setState(() => _retryingLedger = false);
    }
  }

  Widget _row(
    BuildContext context, {
    required Key bannerKey,
    required String message,
    String names = '',
    Key? buttonKey,
    required bool busy,
    Future<void> Function()? onRetry,
  }) {
    final store = context.read<Store>();
    return Padding(
      key: bannerKey,
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              names.isEmpty ? message : '$message $names',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
          // A ledger state the user cannot act on here has no button, so the
          // row states the fact instead of offering a retry that changes nothing.
          if (onRetry != null)
            TextButton(
              key: buttonKey,
              onPressed: busy ? null : onRetry,
              child: Text(store.t['retry']!),
            ),
        ],
      ),
    );
  }

  Widget _note(BuildContext context, {required Key key, required String message}) {
    return Padding(
      key: key,
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Text(
        message,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurface.withValues(
            alpha: 0.7,
          ),
        ),
      ),
    );
  }
}
