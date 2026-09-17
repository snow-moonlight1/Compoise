import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../storage.dart';

/// Production scheduling errors remain visible until retry succeeds or is cancelled.
class ReminderFailureBanner extends StatefulWidget {
  const ReminderFailureBanner({super.key});

  @override
  State<ReminderFailureBanner> createState() => _ReminderFailureBannerState();
}

class _ReminderFailureBannerState extends State<ReminderFailureBanner> {
  bool _retrying = false;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<Store>();
    return ValueListenableBuilder<Map<int, ReminderPayload>>(
      valueListenable: ReminderService.instance.scheduleFailures,
      builder: (context, failures, _) {
        if (failures.isEmpty) return const SizedBox.shrink();
        final names = failures.values
            .map((p) {
              final task =
                  store.tasks.where((t) => t.id == p.taskId).firstOrNull;
              return task?.subtasks
                      .where((s) => s.id == p.subtaskId)
                      .firstOrNull
                      ?.title ??
                  task?.title ??
                  '';
            })
            .where((s) => s.isNotEmpty)
            .join(', ');
        return Padding(
          key: const ValueKey('reminder-schedule-failure'),
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${store.t['reminderScheduleFailed']} $names',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
              TextButton(
                key: const ValueKey('retry-reminders'),
                onPressed:
                    _retrying
                        ? null
                        : () async {
                          setState(() => _retrying = true);
                          try {
                            for (final payload in failures.values.toList()) {
                              await store.retryReminder(payload);
                            }
                          } finally {
                            if (mounted) setState(() => _retrying = false);
                          }
                        },
                child: Text(store.t['retry']!),
              ),
            ],
          ),
        );
      },
    );
  }
}
