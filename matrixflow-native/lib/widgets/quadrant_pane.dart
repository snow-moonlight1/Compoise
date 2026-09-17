import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  final VoidCallback? onQuadrantTap;
  final ValueChanged<Task>? onEdit;
  final void Function(Task task, String subtaskId)? onEditSubtask;
  final bool isFocused;
  final ScrollController? scrollController;
  final TaskRowLayout? rowLayout;

  const QuadrantPane({
    super.key,
    required this.quadrant,
    this.selecting = false,
    this.selectedIds = const {},
    this.expandedIds = const {},
    this.onSelect,
    this.onToggleExpand,
    this.onEnsureExpanded,
    this.onQuadrantTap,
    this.onEdit,
    this.onEditSubtask,
    this.isFocused = false,
    this.scrollController,
    this.rowLayout,
  });

  @override
  State<QuadrantPane> createState() => _QuadrantPaneState();
}

class _QuadrantPaneState extends State<QuadrantPane> {
  bool _hovering = false;
  ScrollController? _internalScrollController;

  ScrollController get _scrollController =>
      widget.scrollController ??
      (_internalScrollController ??= ScrollController());

  @override
  void dispose() {
    _internalScrollController?.dispose();
    super.dispose();
  }

  void _scrollToTopIfNeeded() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients && _scrollController.offset > 0) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showMovedNotice(
    BuildContext context,
    String title,
    int targetQuadrant,
  ) {
    final t = context.read<Store>().t;
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
          content: Text('$title: $msg'),
          duration: const Duration(milliseconds: 1800),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

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
        final task = details.data;
        if (task.quadrant != q) {
          HapticFeedback.mediumImpact();
          store.moveTask(task.id, q);
          _scrollToTopIfNeeded();
          _showMovedNotice(context, task.title, q);
        }
      },
      builder: (context, candidate, _) {
        final highlighted = _hovering || candidate.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color:
                highlighted
                    ? accent.withValues(alpha: 0.10)
                    : Colors.transparent,
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
              InkWell(
                key: ValueKey('quadrant-header-$q'),
                onTap: widget.onQuadrantTap,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 8, 4),
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
                            fontWeight: FontWeight.w600,
                            height: 1.2,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${tasks.length}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.55,
                          ),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (widget.onQuadrantTap != null) ...[
                        const SizedBox(width: 4),
                        Icon(
                          widget.isFocused
                              ? Icons.close_fullscreen
                              : Icons.open_in_full,
                          size: 14,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.45,
                          ),
                        ),
                      ],
                    ],
                  ),
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
                          controller: _scrollController,
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          padding: const EdgeInsets.fromLTRB(4, 2, 4, 16),
                          itemCount: tasks.length,
                          itemBuilder: (context, i) {
                            final task = tasks[i];
                            return LongPressDraggable<Task>(
                              key: ValueKey(task.id),
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
      rowLayout:
          widget.rowLayout ??
          (widget.isFocused
              ? TaskRowLayout.hierarchical
              : TaskRowLayout.matrixCompact),
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
      onEditSubtask:
          widget.onEditSubtask == null
              ? null
              : (id) => widget.onEditSubtask!(task, id),
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
