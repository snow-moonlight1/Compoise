import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../storage.dart';

/// Pending reminder work stays visible until the platform confirms it.
///
/// Schedule and cancellation failures are separate rows because they need
/// opposite retries, and an undetectable permission state is called out
/// instead of being reported as granted.
class ReminderFailureBanner extends StatefulWidget {
  const ReminderFailureBanner({super.key});

  @override
  State<ReminderFailureBanner> createState() => _ReminderFailureBannerState();
}

class _ReminderFailureBannerState extends State<ReminderFailureBanner> {
  bool _retryingSchedule = false;
  bool _retryingCancel = false;

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

  Widget _row(
    BuildContext context, {
    required Key bannerKey,
    required Key buttonKey,
    required String message,
    required String names,
    required bool busy,
    required Future<void> Function() onRetry,
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
