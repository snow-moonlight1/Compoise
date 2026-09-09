import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../storage.dart';
import 'input_sheet.dart';
import 'task_card.dart';

/// One quadrant column: header (dot, title, count, clear) + drag target list.
class QuadrantPane extends StatefulWidget {
  final int quadrant;
  final bool selecting;
  final Set<String> selectedIds;
  final Set<String> expandedIds;
  final ValueChanged<String>? onSelect;
  final ValueChanged<String>? onToggleExpand;
  final ValueChanged<String>? onEnsureExpanded;

  const QuadrantPane({
    super.key,
    required this.quadrant,
    this.selecting = false,
    this.selectedIds = const {},
    this.expandedIds = const {},
    this.onSelect,
    this.onToggleExpand,
    this.onEnsureExpanded,
  });

  @override
  State<QuadrantPane> createState() => _QuadrantPaneState();
}

class _QuadrantPaneState extends State<QuadrantPane> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<Store>();
    final t = store.t;
    final theme = Theme.of(context);
    final q = widget.quadrant;
    final tasks = store.tasksIn(q);
    final accent = Color(quadrantColors[q]!);
    final titleKey = switch (q) {
      qDo => 'q1',
      qPlan => 'q2',
      qDelegate => 'q3',
      _ => 'q4',
    };

    return DragTarget<Task>(
      onWillAcceptWithDetails:
          (details) =>
              !widget.selecting && details.data.boardId == store.activeBoardId,
      onMove: (_) {
        if (!_hovering) setState(() => _hovering = true);
      },
      onLeave: (_) {
        if (_hovering) setState(() => _hovering = false);
      },
      onAcceptWithDetails: (details) {
        setState(() => _hovering = false);
        store.moveTask(details.data.id, q);
      },
      builder: (context, candidate, _) {
        final highlighted = _hovering || candidate.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color:
                highlighted
                    ? theme.colorScheme.primary.withValues(alpha: 0.06)
                    : theme.colorScheme.onSurface.withValues(
                      alpha: isDark(theme) ? 0.04 : 0.03,
                    ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              width: highlighted ? 2 : 1,
              color:
                  highlighted
                      ? theme.colorScheme.primary.withValues(alpha: 0.55)
                      : theme.colorScheme.onSurface.withValues(alpha: 0.06),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 6, 4, 2),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        t[titleKey]!,
                        maxLines: 2,
                        overflow: TextOverflow.visible,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          height: 1.2,
                        ),
                      ),
                    ),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      transitionBuilder:
                          (child, anim) =>
                              ScaleTransition(scale: anim, child: child),
                      child: Container(
                        key: ValueKey(tasks.length),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.08,
                          ),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '${tasks.length}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    if (tasks.isNotEmpty)
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: t['clearQuadrant'],
                        icon: Icon(
                          Icons.delete_sweep_outlined,
                          size: 16,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.45,
                          ),
                        ),
                        onPressed: () => _confirmClear(context, store, q),
                      ),
                  ],
                ),
              ),
              Expanded(
                child:
                    tasks.isEmpty
                        ? Center(
                          child: Text(
                            t['empty']!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontStyle: FontStyle.italic,
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.35,
                              ),
                            ),
                          ),
                        )
                        : ListView.builder(
                          key: PageStorageKey('${store.activeBoardId}-$q'),
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          padding: const EdgeInsets.fromLTRB(8, 2, 8, 80),
                          itemCount: tasks.length,
                          itemBuilder: (context, i) {
                            final task = tasks[i];
                            return LongPressDraggable<Task>(
                              key: ValueKey(task.id),
                              maxSimultaneousDrags: widget.selecting ? 0 : 1,
                              data: task,
                              feedback: _dragFeedback(context, task),
                              dragAnchorStrategy: pointerDragAnchorStrategy,
                              childWhenDragging: Opacity(
                                opacity: 0.35,
                                child: _card(context, task, i),
                              ),
                              child: _card(context, task, i),
                            );
                          },
                        ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _card(BuildContext context, Task task, int index) {
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
      onEdit: () => showTaskEditSheet(context, task),
      onDelete: () => _confirmDelete(context, task),
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

  Future<void> _confirmClear(BuildContext context, Store store, int q) async {
    final t = store.t;
    final boardId = store.activeBoardId;
    final ok = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: Text(t['clearQuadrantTitle']!),
            content: Text(t['confirmClearQuadrant']!),
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
    if (ok == true && context.mounted) store.clearQuadrant(q, boardId: boardId);
  }

  Future<void> _confirmDelete(BuildContext context, Task task) async {
    final store = context.read<Store>();
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
    if (ok == true && context.mounted) store.deleteTask(task.id);
  }

  Future<void> _decomposeSingle(BuildContext context, Task task) =>
      showBatchDecomposeSheet(context, [task], autoStart: true);
  bool isDark(ThemeData theme) => theme.brightness == Brightness.dark;
}
