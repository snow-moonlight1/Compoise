import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../storage.dart';
import 'input_sheet.dart';
import 'task_card.dart';

/// List view presentation of tasks grouped by quadrant sections.
/// Reuses the same TaskCard items, callbacks, DragTarget, and store mutations.
class TaskListView extends StatefulWidget {
  final bool selecting;
  final Set<String> selectedIds;
  final Set<String> expandedIds;
  final ValueChanged<String>? onSelect;
  final ValueChanged<String>? onToggleExpand;
  final ValueChanged<String>? onEnsureExpanded;
  final ValueChanged<int>? onQuadrantTap;
  final ValueChanged<Task>? onEdit;

  const TaskListView({
    super.key,
    this.selecting = false,
    this.selectedIds = const {},
    this.expandedIds = const {},
    this.onSelect,
    this.onToggleExpand,
    this.onEnsureExpanded,
    this.onQuadrantTap,
    this.onEdit,
  });

  @override
  State<TaskListView> createState() => _TaskListViewState();
}

class _TaskListViewState extends State<TaskListView> {
  int? _hoveringQuadrant;

  void _showMovedNotice(BuildContext context, String taskTitle, int targetQ) {
    final store = context.read<Store>();
    final qName = store.t['q$targetQ'] ?? 'Q$targetQ';
    final msg = (store.t['taskMoved'] ?? 'Moved to {quadrant}').replaceAll(
      '{quadrant}',
      qName,
    );
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(milliseconds: 1400)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<Store>();
    final t = store.t;
    final theme = Theme.of(context);

    return ListView(
      key: PageStorageKey('${store.activeBoardId}-task-list-view'),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 32),
      children: [
        for (final q in allQuadrants) ...[
          _buildQuadrantSection(context, store, t, theme, q),
          if (q != allQuadrants.last)
            Divider(
              height: 16,
              thickness: 1,
              color:
                  theme.brightness == Brightness.light
                      ? const Color(0xFFE5E9F0)
                      : theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
        ],
      ],
    );
  }

  Widget _buildQuadrantSection(
    BuildContext context,
    Store store,
    Map<String, String> t,
    ThemeData theme,
    int q,
  ) {
    final tasks = store.tasksIn(q);
    final accent = Color(quadrantColors[q]!);
    final titleKey = switch (q) {
      qDo => 'q1',
      qPlan => 'q2',
      qDelegate => 'q3',
      _ => 'q4',
    };
    final isHovered = _hoveringQuadrant == q;

    return DragTarget<Task>(
      onWillAcceptWithDetails:
          (details) =>
              !widget.selecting && details.data.boardId == store.activeBoardId,
      onMove: (_) {
        if (_hoveringQuadrant != q) {
          setState(() => _hoveringQuadrant = q);
        }
      },
      onLeave: (_) {
        if (_hoveringQuadrant == q) {
          setState(() => _hoveringQuadrant = null);
        }
      },
      onAcceptWithDetails: (details) {
        setState(() => _hoveringQuadrant = null);
        final task = details.data;
        if (task.quadrant != q) {
          HapticFeedback.mediumImpact();
          store.moveTask(task.id, q);
          _showMovedNotice(context, task.title, q);
        }
      },
      builder: (context, candidate, _) {
        final highlighted = isHovered || candidate.isNotEmpty;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color:
                highlighted
                    ? accent.withValues(alpha: 0.10)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border:
                highlighted
                    ? Border.all(
                      color: accent.withValues(alpha: 0.55),
                      width: 1.5,
                    )
                    : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Quadrant Section Header
              InkWell(
                key: ValueKey('list-quadrant-header-$q'),
                borderRadius: BorderRadius.circular(6),
                onTap: () => widget.onQuadrantTap?.call(q),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: accent,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          t[titleKey]!,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${tasks.length}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: accent,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (widget.onQuadrantTap != null) ...[
                        const SizedBox(width: 6),
                        Icon(
                          Icons.open_in_full,
                          size: 15,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.45,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              // Tasks or Empty State
              if (tasks.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Text(
                    t['noTasksInQuadrant'] ?? t['empty'] ?? 'No tasks',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontStyle: FontStyle.italic,
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.35,
                      ),
                    ),
                  ),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: tasks.length,
                  itemBuilder: (context, i) {
                    final task = tasks[i];
                    return LongPressDraggable<Task>(
                      key: ValueKey('list-drag-${task.id}'),
                      maxSimultaneousDrags: widget.selecting ? 0 : 1,
                      data: task,
                      hapticFeedbackOnStart: true,
                      onDragStarted: () => HapticFeedback.lightImpact(),
                      onDraggableCanceled:
                          (_, __) => HapticFeedback.selectionClick(),
                      feedback: _dragFeedback(context, task),
                      dragAnchorStrategy: pointerDragAnchorStrategy,
                      childWhenDragging: Opacity(
                        opacity: 0.35,
                        child: _taskCard(context, store, task, i),
                      ),
                      child: _taskCard(context, store, task, i),
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _taskCard(BuildContext context, Store store, Task task, int index) {
    return TaskCard(
      key: ValueKey(task.id),
      task: task,
      entranceIndex: index,
      selecting: widget.selecting,
      selected: widget.selectedIds.contains(task.id),
      expanded: widget.expandedIds.contains(task.id),
      onSelect: () => widget.onSelect?.call(task.id),
      onToggleExpand: () => widget.onToggleExpand?.call(task.id),
      onEnsureExpanded: () => widget.onEnsureExpanded?.call(task.id),
      onChanged: () {},
      onEdit: () {
        if (widget.onEdit != null) {
          widget.onEdit!(task);
        } else {
          showTaskEditSheet(context, task);
        }
      },
      onDelete: () => _confirmDelete(context, store, task),
      onDecompose: () => _decomposeSingle(context, task),
      onDecomposeStart: () {},
    );
  }

  Widget _dragFeedback(BuildContext context, Task task) {
    final theme = Theme.of(context);
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(16),
      color: theme.cardTheme.color ?? theme.colorScheme.surface,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 260),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Text(
          task.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    Store store,
    Task task,
  ) async {
    final t = store.t;
    final ok = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: Text(t['deleteTaskTitle']!),
            content: Text(t['deleteTaskConfirm']!),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(t['cancel']!),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                ),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(t['confirm']!),
              ),
            ],
          ),
    );
    if (ok == true && context.mounted) {
      store.deleteTask(task.id);
    }
  }

  Future<void> _decomposeSingle(BuildContext context, Task task) =>
      showBatchDecomposeSheet(context, [task], autoStart: true);
}
