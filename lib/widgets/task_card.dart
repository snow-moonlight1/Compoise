import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../planned_policy.dart';
import '../storage.dart';
import '../ui/motion_policy.dart';
import 'anim.dart';
import 'animated_task_title.dart';
import 'date_edit_fields.dart';
import 'task_hierarchy_checkbox.dart';

export '../deadline_policy.dart' show calendarDaysLeft, isDeadlineUrgent;

/// Matrix rows share one column; focus/list rows indent children 16dp.
enum TaskRowLayout { matrixCompact, hierarchical }

class TaskCard extends StatelessWidget {
  static const double checkColumnWidth = TaskHierarchyStyle.hitTargetSize;
  static const double parentCheckVisual =
      TaskHierarchyStyle.parentCheckboxVisualSize;
  static const double childCheckVisual =
      TaskHierarchyStyle.childCheckboxVisualSize;
  static const double hierarchicalIndent = 16;

  final Task task;
  final int entranceIndex;
  final VoidCallback onChanged;
  final VoidCallback onEdit;
  final void Function(String subtaskId)? onEditSubtask;
  final VoidCallback onDelete;
  final VoidCallback onDecompose;
  final VoidCallback onDecomposeStart; // signals busy state externally
  final bool selecting;
  final bool selected;
  final VoidCallback? onSelect;
  final bool expanded;
  final VoidCallback? onToggleExpand;
  final VoidCallback? onEnsureExpanded;
  final TaskRowLayout rowLayout;

  const TaskCard({
    super.key,
    required this.task,
    required this.entranceIndex,
    required this.onChanged,
    required this.onEdit,
    this.onEditSubtask,
    required this.onDelete,
    required this.onDecompose,
    required this.onDecomposeStart,
    this.selecting = false,
    this.selected = false,
    this.onSelect,
    this.expanded = false,
    this.onToggleExpand,
    this.onEnsureExpanded,
    this.rowLayout = TaskRowLayout.matrixCompact,
  });

  @override
  Widget build(BuildContext context) {
    final store = context.read<Store>();
    final t = store.t;
    final theme = Theme.of(context);
    final daysLeft =
        task.deadline == null ? null : calendarDaysLeft(task.deadline!);

    final reduceMotion = MotionPolicy.reduceMotionOf(context);

    return StaggerIn(
      key: ValueKey('stagger-${task.id}'),
      index: entranceIndex,
      child: Dismissible(
        key: ValueKey('dismiss-${task.id}'),
        direction:
            selecting ? DismissDirection.none : DismissDirection.horizontal,
        movementDuration:
            reduceMotion ? Duration.zero : MotionPolicy.dismissible,
        resizeDuration:
            reduceMotion ? Duration.zero : MotionPolicy.dismissible,
        background: _buildSwipeBackground(
          context: context,
          alignment: Alignment.centerLeft,
          color:
              task.completed
                  ? (theme.brightness == Brightness.light
                      ? const Color(0xFFE0E7FF)
                      : const Color(0xFF312E81))
                  : (theme.brightness == Brightness.light
                      ? const Color(0xFFDCFCE7)
                      : const Color(0xFF14532D)),
          iconColor:
              task.completed
                  ? (theme.brightness == Brightness.light
                      ? const Color(0xFF4F46E5)
                      : const Color(0xFF818CF8))
                  : (theme.brightness == Brightness.light
                      ? const Color(0xFF16A34A)
                      : const Color(0xFF4ADE80)),
          icon: task.completed ? Icons.undo : Icons.check_circle_outline,
          label:
              task.completed
                  ? (t['restoreTask'] ?? 'Restore')
                  : (t['complete'] ?? 'Complete'),
        ),
        secondaryBackground: _buildSwipeBackground(
          context: context,
          alignment: Alignment.centerRight,
          color:
              theme.brightness == Brightness.light
                  ? const Color(0xFFFEE2E2)
                  : const Color(0xFF7F1D1D),
          iconColor:
              theme.brightness == Brightness.light
                  ? const Color(0xFFDC2626)
                  : const Color(0xFFF87171),
          icon: Icons.delete_outline,
          label: t['delete'] ?? 'Delete',
        ),
        confirmDismiss: (direction) async {
          if (direction == DismissDirection.startToEnd) {
            // Swipe right: toggle complete / restore
            HapticFeedback.lightImpact();
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (context.mounted) {
                final snapshot = store.toggleCompleteWithUndo(task);
                onChanged();
                if (snapshot != null) {
                  _showUndoSnackBar(
                    context,
                    msg:
                        '${task.title}: ${task.completed ? (t['taskCompleted'] ?? 'Task completed') : (t['taskRestored'] ?? 'Task restored')}',
                    snapshot: snapshot,
                    store: store,
                  );
                }
              }
            });
            return false;
          } else if (direction == DismissDirection.endToStart) {
            // Swipe left: delete
            HapticFeedback.lightImpact();
            return true;
          }
          return false;
        },
        onDismissed: (direction) {
          if (direction == DismissDirection.endToStart) {
            final snapshot = store.deleteTaskWithUndo(task.id);
            onChanged();
            if (snapshot != null) {
              _showUndoSnackBar(
                context,
                msg: '${task.title}: ${t['taskDeleted'] ?? 'Task deleted'}',
                snapshot: snapshot,
                store: store,
              );
            }
          }
        },
        child: Material(
          color:
              selected
                  ? (theme.brightness == Brightness.light
                      ? const Color(0xFFE6EEFF)
                      : theme.colorScheme.primary.withValues(alpha: 0.18))
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(2, 2, 2, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _parentRow(context, store, t, theme, daysLeft),
                if (task.subtasks.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: checkColumnWidth),
                    child: _expandToggle(t, theme),
                  ),
                if (expanded) ..._subtaskRows(context, t, theme),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _parentRow(
    BuildContext context,
    Store store,
    Map<String, String> t,
    ThemeData theme,
    int? daysLeft,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _checkColumn(
          key: ValueKey('complete-${task.id}'),
          visualKey: ValueKey('complete-${task.id}-visual'),
          semanticsLabel: taskCheckboxLabel(
            t: t,
            level: TaskHierarchyLevel.parent,
            value: task.completed,
            title: task.title,
          ),
          level: TaskHierarchyLevel.parent,
          value: task.completed,
          onToggle: () {
            store.setParentCompleted(task, !task.completed);
            onChanged();
          },
        ),
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: selecting ? onSelect : onEdit,
            onSecondaryTapDown:
                selecting
                    ? null
                    : (details) =>
                        _showContextMenu(context, details.globalPosition),
            child: Padding(
            padding: const EdgeInsets.only(top: 13, right: 8, bottom: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: AnimatedStrikeThroughText(
                        key: ValueKey('task-title-anim-${task.id}'),
                        text: task.title,
                        completed: task.completed,
                        textKey: ValueKey('task-title-${task.id}'),
                        strikeKey: ValueKey('task-strike-${task.id}'),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontSize: TaskHierarchyStyle.parentTitleSize,
                          height: 1.4,
                          fontWeight: FontWeight.w500,
                          color:
                              task.completed
                                  ? theme.colorScheme.onSurface.withValues(
                                    alpha: 0.38,
                                  )
                                  : (theme.brightness == Brightness.light
                                      ? const Color(0xFF242A32)
                                      : null),
                        ),
                      ),
                    ),
                    if (task.isLongTerm && !task.hasSubtasks && !selecting)
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: t['decomposingSingle'],
                        icon: const Icon(
                          Icons.call_split,
                          size: 16,
                          color: Color(0xFFF59E0B),
                        ),
                        onPressed: () {
                          onDecomposeStart();
                          onDecompose();
                        },
                      ),
                  ],
                ),
                if (selected)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      t['selectedMark']!,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                Row(
                  children: [
                    _PlannedChip(
                      task: task,
                      done: task.completed,
                      t: t,
                    ),
                    _DeadlineChip(
                      daysLeft: daysLeft,
                      done: task.completed,
                      t: t,
                      isUrgent: isDeadlineUrgent(
                        task.deadline,
                        store.settings.urgencyThresholdDays,
                      ),
                    ),
                    if (task.reminderAt != null) ...[
                      const SizedBox(width: 4),
                      Icon(
                        Icons.notifications_active_outlined,
                        size: 14,
                        color:
                            task.completed
                                ? theme.colorScheme.onSurface.withValues(
                                  alpha: 0.38,
                                )
                                : theme.colorScheme.primary,
                      ),
                    ],
                  ],
                ),
              ],
            ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _expandToggle(Map<String, String> t, ThemeData theme) {
    final done = task.subtasks.where((sub) => sub.completed).length;
    final label = (t['subtaskProgress'] ?? 'Subtasks {done}/{total}')
        .replaceAll('{done}', '$done')
        .replaceAll('{total}', '${task.subtasks.length}');
    return Semantics(
      container: true,
      button: true,
      expanded: expanded,
      label: subtaskToggleLabel(
        t: t,
        title: task.title,
        done: done,
        total: task.subtasks.length,
      ),
      child: InkWell(
        key: ValueKey('expand-${task.id}'),
        onTap: onToggleExpand,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: TaskHierarchyStyle.hitTargetSize,
          ),
          child: ExcludeSemantics(
            child: Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.7,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _subtaskRows(
    BuildContext context,
    Map<String, String> t,
    ThemeData theme,
  ) {
    if (task.subtasks.isEmpty) return [];
    final store = context.read<Store>();
    final thresholdDays = store.settings.urgencyThresholdDays;
    final indent =
        rowLayout == TaskRowLayout.hierarchical ? hierarchicalIndent : 0.0;
    return [
      for (final sub in task.subtasks)
        Padding(
          padding: EdgeInsets.only(left: indent, top: 2, bottom: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _checkColumn(
                key: ValueKey('task-subtask-check-${sub.id}'),
                visualKey: ValueKey('task-subtask-check-${sub.id}-visual'),
                semanticsLabel: taskCheckboxLabel(
                  t: t,
                  level: TaskHierarchyLevel.child,
                  value: sub.completed,
                  title: sub.title,
                ),
                level: TaskHierarchyLevel.child,
                value: sub.completed,
                onToggle: () {
                  store.setSubtaskCompleted(task.id, sub.id, !sub.completed);
                  onChanged();
                },
              ),
              Expanded(
                child: InkWell(
                  key: ValueKey('subtask-title-${sub.id}'),
                  borderRadius: BorderRadius.circular(4),
                  onTap:
                      selecting
                          ? onSelect
                          : () {
                            if (onEditSubtask != null) {
                              onEditSubtask!(sub.id);
                            } else {
                              onEdit();
                            }
                          },
                  child: Padding(
                    padding: const EdgeInsets.only(top: 13, right: 8, bottom: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AnimatedStrikeThroughText(
                          key: ValueKey('subtask-title-anim-${sub.id}'),
                          text: sub.title,
                          completed: sub.completed,
                          textKey: ValueKey('subtask-title-text-${sub.id}'),
                          strikeKey: ValueKey('subtask-strike-${sub.id}'),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: TaskHierarchyStyle.childTitleSize,
                            height: 1.4,
                            fontWeight: FontWeight.w400,
                            color:
                                sub.completed
                                    ? theme.colorScheme.onSurface.withValues(
                                      alpha: 0.38,
                                    )
                                    : null,
                          ),
                        ),
                        if (sub.deadline != null)
                          _DeadlineChip(
                            daysLeft: calendarDaysLeft(sub.deadline!),
                            done: sub.completed,
                            t: t,
                            isUrgent: isDeadlineUrgent(
                              sub.deadline,
                              thresholdDays,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              if (sub.reminderAt != null)
                Padding(
                  padding: const EdgeInsets.only(top: 14, right: 4),
                  child: Icon(
                    Icons.notifications_active_outlined,
                    size: 12,
                    color:
                        sub.completed
                            ? theme.colorScheme.onSurface.withValues(
                              alpha: 0.38,
                            )
                            : theme.colorScheme.primary,
                  ),
                ),
            ],
          ),
        ),
    ];
  }

  Widget _checkColumn({
    required Key key,
    required Key visualKey,
    required String? semanticsLabel,
    required TaskHierarchyLevel level,
    required bool value,
    required VoidCallback onToggle,
  }) {
    return TaskHierarchyCheckbox(
      level: level,
      value: value,
      semanticsLabel: semanticsLabel,
      hitTargetKey: key,
      visualKey: visualKey,
      onChanged: (_) => onToggle(),
    );
  }

  static Widget _buildSwipeBackground({
    required BuildContext context,
    required Alignment alignment,
    required Color color,
    required Color iconColor,
    required IconData icon,
    required String label,
  }) {
    final isLeft = alignment == Alignment.centerLeft;
    return Container(
      alignment: alignment,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isLeft) ...[
            Icon(icon, color: iconColor, size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: iconColor,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ] else ...[
            Text(
              label,
              style: TextStyle(
                color: iconColor,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
            const SizedBox(width: 8),
            Icon(icon, color: iconColor, size: 20),
          ],
        ],
      ),
    );
  }

  static void _showUndoSnackBar(
    BuildContext context, {
    required String msg,
    required TaskUndoSnapshot snapshot,
    required Store store,
  }) {
    final t = store.t;
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          key: const ValueKey('task-undo-snackbar'),
          content: Text(msg),
          duration: const Duration(seconds: 5),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            key: const ValueKey('undo-action-btn'),
            label: t['undo'] ?? 'Undo',
            onPressed: () {
              final ok = store.applyUndo(snapshot);
              if (ok) {
                HapticFeedback.lightImpact();
                messenger
                  ..hideCurrentSnackBar()
                  ..showSnackBar(
                    SnackBar(
                      content: Text(t['actionUndone'] ?? 'Action undone'),
                      duration: const Duration(milliseconds: 1500),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
              } else {
                messenger
                  ..hideCurrentSnackBar()
                  ..showSnackBar(
                    SnackBar(
                      content: Text(
                        t['undoUnavailable'] ?? 'Cannot undo this action',
                      ),
                      duration: const Duration(milliseconds: 1800),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
              }
            },
          ),
        ),
      );
  }

  Future<void> _showContextMenu(BuildContext context, Offset position) async {
    if (selecting) return;
    final store = context.read<Store>();
    final t = store.t;
    final theme = Theme.of(context);
    final target = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx + 1,
        position.dy + 1,
      ),
      items: [
        PopupMenuItem<String>(
          key: ValueKey('context-complete-${task.id}'),
          value: 'toggle_complete',
          child: Row(
            children: [
              Icon(
                task.completed ? Icons.undo : Icons.check_circle_outline,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                task.completed
                    ? (t['restoreTask'] ?? 'Restore')
                    : (t['complete'] ?? 'Complete'),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          enabled: false,
          child: Text(
            t['moveTo'] ?? 'Move to',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        for (final q in allQuadrants)
          if (q != task.quadrant)
            PopupMenuItem<String>(
              key: ValueKey('move-to-q$q-${task.id}'),
              value: 'move_to_$q',
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: Color(quadrantColors[q]!),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(t['q$q']!, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          key: ValueKey('context-delete-${task.id}'),
          value: 'delete',
          child: Row(
            children: [
              Icon(
                Icons.delete_outline,
                size: 18,
                color: theme.colorScheme.error,
              ),
              const SizedBox(width: 8),
              Text(
                t['delete'] ?? 'Delete',
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
          ),
        ),
      ],
    );

    if (target != null && context.mounted) {
      if (target == 'toggle_complete') {
        HapticFeedback.lightImpact();
        final snapshot = store.toggleCompleteWithUndo(task);
        onChanged();
        if (snapshot != null) {
          _showUndoSnackBar(
            context,
            msg:
                '${task.title}: ${task.completed ? (t['taskCompleted'] ?? 'Task completed') : (t['taskRestored'] ?? 'Task restored')}',
            snapshot: snapshot,
            store: store,
          );
        }
      } else if (target == 'delete') {
        HapticFeedback.lightImpact();
        final snapshot = store.deleteTaskWithUndo(task.id);
        onChanged();
        if (snapshot != null) {
          _showUndoSnackBar(
            context,
            msg: '${task.title}: ${t['taskDeleted'] ?? 'Task deleted'}',
            snapshot: snapshot,
            store: store,
          );
        }
      } else if (target.startsWith('move_to_')) {
        final targetQuadrant = int.parse(target.substring(8));
        HapticFeedback.selectionClick();
        store.moveTask(task.id, targetQuadrant);
        final qName = switch (targetQuadrant) {
          qDo => t['q1']!,
          qPlan => t['q2']!,
          qDelegate => t['q3']!,
          _ => t['q4']!,
        };
        final msg = (t['taskMoved'] ?? 'Moved to {quadrant}').replaceAll(
          '{quadrant}',
          qName,
        );
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text('${task.title}: $msg'),
              duration: const Duration(milliseconds: 1800),
              behavior: SnackBarBehavior.floating,
            ),
          );
      }
    }
  }
}

/// The planned day, marked apart from [_DeadlineChip]: a plan says when the work
/// is scheduled and never turns red, so the two cannot be read as one signal.
class _PlannedChip extends StatelessWidget {
  final Task task;
  final bool done;
  final Map<String, String> t;
  const _PlannedChip({
    required this.task,
    required this.done,
    required this.t,
  });

  @override
  Widget build(BuildContext context) {
    final days = plannedDaysLeft(task.plannedDate);
    if (days == null || done) return const SizedBox.shrink();
    final day = DateTime.fromMillisecondsSinceEpoch(task.plannedDate!);
    final color = Theme.of(context).colorScheme.primary.withValues(
      alpha: 0.75,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 3, right: 6),
      child: Tooltip(
        message: t['plannedDate']!,
        child: Row(
          key: ValueKey('task-planned-${task.id}'),
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event_note, size: 11, color: color),
            const SizedBox(width: 3),
            Flexible(
              child: Text(
                days == 0
                    ? t['today']!
                    : days == 1
                    ? t['tomorrow']!
                    : formatCivilDate(day),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeadlineChip extends StatelessWidget {
  final int? daysLeft;
  final bool done;
  final Map<String, String> t;
  final bool isUrgent;
  const _DeadlineChip({
    required this.daysLeft,
    required this.done,
    required this.t,
    this.isUrgent = false,
  });

  @override
  Widget build(BuildContext context) {
    if (daysLeft == null || done) return const SizedBox.shrink();
    final overdue = daysLeft! < 0;
    final today = daysLeft == 0;
    final color =
        overdue || today
            ? Theme.of(context).colorScheme.error
            : isUrgent
            ? Colors.orange
            : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4);
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.calendar_month, size: 11, color: color),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              overdue
                  ? t['overdue']!
                  : today
                  ? t['today']!
                  : '$daysLeft${t['daysLeft']}',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}


