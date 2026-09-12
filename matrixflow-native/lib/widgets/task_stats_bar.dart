import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../storage.dart';
import '../task_stats.dart';

/// Interactive statistics bar showing completion rate, pending tasks,
/// overdue warnings, subtask progression, and scope toggle.
class TaskStatsBar extends StatefulWidget {
  final bool initiallyAllBoards;
  final ValueChanged<bool>? onScopeChanged;

  const TaskStatsBar({
    super.key,
    this.initiallyAllBoards = false,
    this.onScopeChanged,
  });

  @override
  State<TaskStatsBar> createState() => _TaskStatsBarState();
}

class _TaskStatsBarState extends State<TaskStatsBar> {
  late bool _allBoards;

  @override
  void initState() {
    super.initState();
    _allBoards = widget.initiallyAllBoards;
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<Store>();
    final t = store.t;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final stats = computeTaskStats(
      tasks: store.tasks,
      boardId: _allBoards ? null : store.activeBoardId,
    );

    final progressColor =
        stats.completionRate >= 1.0
            ? Colors.green
            : theme.colorScheme.primary;

    return Container(
      key: const ValueKey('task-stats-bar'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color:
            isDark
                ? theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.35,
                )
                : const Color(0xFFF8FAFC),
        border: Border(
          bottom: BorderSide(
            color:
                isDark
                    ? theme.colorScheme.outlineVariant
                    : const Color(0xFFE2E8F0),
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // Scope toggle button
              InkWell(
                key: const ValueKey('stats-scope-toggle-btn'),
                borderRadius: BorderRadius.circular(6),
                onTap: () {
                  setState(() {
                    _allBoards = !_allBoards;
                  });
                  widget.onScopeChanged?.call(_allBoards);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _allBoards
                            ? Icons.dashboard_outlined
                            : Icons.view_quilt_outlined,
                        size: 13,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        _allBoards
                            ? (t['statsScopeAll'] ?? 'All Boards')
                            : (t['statsScopeCurrent'] ?? 'Current Board'),
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        Icons.swap_horiz,
                        size: 12,
                        color: theme.colorScheme.primary.withValues(alpha: 0.7),
                      ),
                    ],
                  ),
                ),
              ),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  // Progress text (e.g. Completion: 40%)
                  Text(
                    '${t['statsCompletionRate'] ?? 'Completion'}: ${stats.percentageText}',
                    key: const ValueKey('stats-progress-text'),
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: progressColor,
                    ),
                  ),
                  // Incomplete badge
                  _chipBadge(
                    label:
                        '${t['statsIncomplete'] ?? 'Pending'}: ${stats.incompleteTasks}',
                    theme: theme,
                    textColor: theme.colorScheme.onSurfaceVariant,
                    bgColor:
                        isDark
                            ? theme.colorScheme.surfaceContainerHighest
                            : const Color(0xFFEDF2F7),
                  ),
                  // Overdue badge (if > 0)
                  if (stats.overdueTasks > 0)
                    _chipBadge(
                      key: const ValueKey('stats-overdue-chip'),
                      label:
                          '${t['statsOverdue'] ?? 'Overdue'}: ${stats.overdueTasks}',
                      theme: theme,
                      textColor: theme.colorScheme.error,
                      bgColor: theme.colorScheme.error.withValues(alpha: 0.12),
                    ),
                  // Subtasks badge (if > 0)
                  if (stats.subtaskTotal > 0)
                    _chipBadge(
                      key: const ValueKey('stats-subtasks-chip'),
                      label:
                          '${t['statsSubtasks'] ?? 'Sub-items'}: ${stats.subtaskCompleted}/${stats.subtaskTotal}',
                      theme: theme,
                      textColor: theme.colorScheme.primary,
                      bgColor: theme.colorScheme.primary.withValues(alpha: 0.1),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 4),
          // Linear progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              key: const ValueKey('stats-progress-indicator'),
              value: stats.completionRate,
              minHeight: 2.5,
              backgroundColor:
                  isDark
                      ? theme.colorScheme.surfaceContainerHighest
                      : const Color(0xFFE2E8F0),
              valueColor: AlwaysStoppedAnimation<Color>(progressColor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chipBadge({
    Key? key,
    required String label,
    required ThemeData theme,
    required Color textColor,
    required Color bgColor,
  }) {
    return Container(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );
  }
}
