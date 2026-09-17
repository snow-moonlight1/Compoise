import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../storage.dart';
import 'anim.dart';

export '../deadline_policy.dart' show calendarDaysLeft, isDeadlineUrgent;

class TaskCard extends StatelessWidget {
  final Task task;
  final int entranceIndex;
  final VoidCallback onChanged;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onDecompose;
  final VoidCallback onDecomposeStart; // signals busy state externally
  final bool selecting;
  final bool selected;
  final VoidCallback? onSelect;
  final bool expanded;
  final VoidCallback? onToggleExpand;
  final VoidCallback? onEnsureExpanded;

  const TaskCard({
    super.key,
    required this.task,
    required this.entranceIndex,
    required this.onChanged,
    required this.onEdit,
    required this.onDelete,
    required this.onDecompose,
    required this.onDecomposeStart,
    this.selecting = false,
    this.selected = false,
    this.onSelect,
    this.expanded = false,
    this.onToggleExpand,
    this.onEnsureExpanded,
  });

  @override
  Widget build(BuildContext context) {
    final store = context.read<Store>();
    final t = store.t;
    final theme = Theme.of(context);
    final daysLeft =
        task.deadline == null ? null : calendarDaysLeft(task.deadline!);

    final disableAnimations =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    return StaggerIn(
      key: ValueKey('stagger-${task.id}'),
      index: entranceIndex,
      child: Dismissible(
        key: ValueKey('dismiss-${task.id}'),
        direction:
            selecting ? DismissDirection.none : DismissDirection.horizontal,
        movementDuration:
            disableAnimations
                ? Duration.zero
                : const Duration(milliseconds: 200),
        resizeDuration:
            disableAnimations
                ? Duration.zero
                : const Duration(milliseconds: 200),
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
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: selecting ? onSelect : onEdit,
            onSecondaryTapDown:
                selecting
                    ? null
                    : (details) =>
                        _showContextMenu(context, details.globalPosition),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    label: t['markTaskComplete'],
                    button: true,
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: GestureDetector(
                        key: ValueKey('complete-${task.id}'),
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          store.setParentCompleted(task, !task.completed);
                          onChanged();
                        },
                        child: Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: Checkbox(
                              value: task.completed,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                              onChanged: (_) {
                                store.setParentCompleted(task, !task.completed);
                                onChanged();
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(
                        top: 13,
                        right: 8,
                        bottom: 8,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: StrikeThrough(
                                  crossed: task.completed,
                                  child: Text(
                                    task.title,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodyLarge?.copyWith(
                                      fontSize: 16,
                                      height: 1.4,
                                      fontWeight: FontWeight.w500,
                                      color:
                                          task.completed
                                              ? theme.colorScheme.onSurface
                                                  .withValues(alpha: 0.38)
                                              : (theme.brightness ==
                                                      Brightness.light
                                                  ? const Color(0xFF242A32)
                                                  : null),
                                    ),
                                  ),
                                ),
                              ),
                              if (task.isLongTerm &&
                                  !task.hasSubtasks &&
                                  !selecting)
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
                                          ? theme.colorScheme.onSurface
                                              .withValues(alpha: 0.38)
                                          : theme.colorScheme.primary,
                                ),
                              ],
                            ],
                          ),
                          if (task.subtasks.isNotEmpty) _expandToggle(t, theme),
                          if (expanded)
                            GestureDetector(
                              onTap: () {},
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ..._subtasks(context, t, theme),
                                  if (!selecting && !task.completed)
                                    _addSubtaskField(context, t, theme),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _expandToggle(Map<String, String> t, ThemeData theme) {
    final done = task.subtasks.where((sub) => sub.completed).length;
    final label = (t['subtaskProgress'] ?? 'Subtasks {done}/{total}')
        .replaceAll('{done}', '$done')
        .replaceAll('{total}', '${task.subtasks.length}');
    return Semantics(
      button: true,
      label: expanded ? t['collapseSubtasks'] : t['expandSubtasks'],
      child: InkWell(
        key: ValueKey('expand-${task.id}'),
        onTap: onToggleExpand,
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
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
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
    );
  }

  List<Widget> _subtasks(
    BuildContext context,
    Map<String, String> t,
    ThemeData theme,
  ) {
    if (task.subtasks.isEmpty) return [];
    final thresholdDays = context.read<Store>().settings.urgencyThresholdDays;
    return [
      const SizedBox(height: 4),
      Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Column(
          children: [
            for (final sub in task.subtasks)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    SizedBox(
                      width: 48,
                      height: 48,
                      child: GestureDetector(
                        key: ValueKey('task-subtask-check-${sub.id}'),
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          context.read<Store>().setSubtaskCompleted(
                            task.id,
                            sub.id,
                            !sub.completed,
                          );
                          onChanged();
                        },
                        child: Checkbox(
                          value: sub.completed,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                          onChanged: (_) {
                            context.read<Store>().setSubtaskCompleted(
                              task.id,
                              sub.id,
                              !sub.completed,
                            );
                            onChanged();
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          StrikeThrough(
                            crossed: sub.completed,
                            child: Text(
                              sub.title,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color:
                                    sub.completed
                                        ? theme.colorScheme.onSurface
                                            .withValues(alpha: 0.38)
                                        : null,
                              ),
                            ),
                          ),
                          if (sub.deadline != null) ...[
                            const SizedBox(height: 2),
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
                        ],
                      ),
                    ),
                    if (sub.reminderAt != null) ...[
                      const SizedBox(width: 4),
                      Icon(
                        Icons.notifications_active_outlined,
                        size: 12,
                        color:
                            sub.completed
                                ? theme.colorScheme.onSurface.withValues(
                                  alpha: 0.38,
                                )
                                : theme.colorScheme.primary,
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    ];
  }

  Widget _addSubtaskField(
    BuildContext context,
    Map<String, String> t,
    ThemeData theme,
  ) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, top: 4),
      child: _AddSubtaskField(
        hintText: t['addSubtask']!,
        onSubmit: (text) {
          context.read<Store>().appendSubtasks(task.id, [
            SubTask(id: newId(), title: text),
          ]);
          onEnsureExpanded?.call();
          onChanged();
        },
      ),
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

class _AddSubtaskField extends StatefulWidget {
  final String hintText;
  final ValueChanged<String> onSubmit;
  const _AddSubtaskField({required this.hintText, required this.onSubmit});

  @override
  State<_AddSubtaskField> createState() => _AddSubtaskFieldState();
}

class _AddSubtaskFieldState extends State<_AddSubtaskField> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      decoration: InputDecoration(
        hintText: widget.hintText,
        prefixIcon: const Icon(Icons.add, size: 16),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      style: Theme.of(context).textTheme.bodySmall,
      onSubmitted: (value) {
        final text = value.trim();
        if (text.isEmpty) return;
        widget.onSubmit(text);
        _controller.clear();
      },
    );
  }
}
