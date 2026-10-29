import 'package:flutter/material.dart';
import '../ui/danger_button_style.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../storage.dart';
import '../theme.dart';
import '../ui/orphan_squeeze.dart';
import '../ui/motion_policy.dart';
import 'batch_decompose_sheet.dart';
import 'task_detail_panel.dart';
import 'task_card.dart';
import 'task_exit.dart';
import 'multi_drag_stack.dart';
import '../planner/planner_drag_feedback.dart';
import '../ui/platform_ui_policy.dart';
import '../task_order.dart';
import 'drop_slot.dart';

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

  /// Multi-select: the selected stack was dropped on quadrant [q].
  final ValueChanged<int>? onMoveSelected;

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
    this.onMoveSelected,
  });

  @override
  State<QuadrantPane> createState() => _QuadrantPaneState();
}

class _QuadrantPaneState extends State<QuadrantPane>
    with DropSlotHost<QuadrantPane> {
  bool _hovering = false;
  ScrollController? _internalScrollController;
  bool _scrollToTopAnimating = false;
  int _scrollToTopGeneration = 0;

  /// Drag reorder: ids of the shown rows, top to bottom.
  List<String> _rowIds = const [];

  @override
  ScrollController get dropScrollController => _scrollController;

  @override
  bool acceptsDrop(Task task) {
    final store = context.read<Store>();
    return (!widget.selecting || widget.selectedIds.contains(task.id)) &&
        task.boardId == store.activeBoardId;
  }

  @override
  bool dropSlotIsNoop(Task dragged, int group, int slot) {
    if (widget.selecting || dragged.quadrant != widget.quadrant) return false;
    // Both slots next to the dragged row mean "stay": open no gap.
    final own = _rowIds.indexOf(dragged.id);
    return own != -1 && (slot == own || slot == own + 1);
  }

  @override
  void onDropHover(int group) {
    if (!_hovering) setState(() => _hovering = true);
  }

  @override
  void onDropHoverEnd() {
    if (_hovering) setState(() => _hovering = false);
  }

  @override
  void dropAt(Task task, int group, int? slot) {
    final store = context.read<Store>();
    final q = widget.quadrant;
    if (slot == null) {
      if (widget.selecting) {
        HapticFeedback.mediumImpact();
        widget.onMoveSelected?.call(q);
        _scrollToTopIfNeeded();
        return;
      }
      if (task.quadrant != q) {
        HapticFeedback.mediumImpact();
        store.moveTask(task.id, q);
        _scrollToTopIfNeeded();
      }
      return;
    }
    final ids = widget.selecting
        ? [
            for (final t in store.visibleTasks)
              if (widget.selectedIds.contains(t.id)) t.id,
          ]
        : [task.id];
    HapticFeedback.mediumImpact();
    store.placeTasks(
      ids,
      q,
      beforeId: dropAnchor(_rowIds, slot, ids.toSet()),
    );
    if (widget.selecting) widget.onMoveSelected?.call(q);
  }

  /// Short-lived display snapshots of rows that just left [Store.tasksIn]
  /// (completed while hiding completed, auto-completed parent, filter change).
  late final ExitRetention<Task> _exitRetention = ExitRetention<Task>(
    onChange: _onExitRetentionTick,
  );

  void _onExitRetentionTick() {
    if (mounted) setState(() {});
  }

  ScrollController get _scrollController =>
      widget.scrollController ??
      (_internalScrollController ??= ScrollController());

  @override
  void dispose() {
    _exitRetention.dispose();
    _internalScrollController?.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reduce motion switched on while the post-drop scroll-to-top is still
    // running: finish at the top on the next frame instead of letting the
    // ~250ms scroll tween out.
    if (_scrollToTopAnimating && MotionPolicy.reduceMotionOf(context)) {
      final generation = _scrollToTopGeneration;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            !_scrollToTopAnimating ||
            generation != _scrollToTopGeneration ||
            !MotionPolicy.reduceMotionNow(context)) {
          return;
        }
        _scrollToTopAnimating = false;
        _scrollToTopGeneration++;
        final controller = _scrollController;
        if (controller.hasClients && controller.offset != 0) {
          controller.jumpTo(0);
        }
      });
    }
  }

  void _scrollToTopIfNeeded() {
    // Decide reduce-motion at the drop: under reduced motion the list jumps to
    // the top instead of tweening, so moving a task never leaves a long scroll
    // animation running.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_scrollController.hasClients || _scrollController.offset <= 0) {
        return;
      }
      if (MotionPolicy.reduceMotionNow(context)) {
        _scrollController.jumpTo(0);
      } else {
        final generation = ++_scrollToTopGeneration;
        _scrollToTopAnimating = true;
        _scrollController.animateTo(
          0,
          duration: MotionPolicy.scrollToTop,
          curve: Curves.easeOut,
        ).whenComplete(() {
          if (generation == _scrollToTopGeneration) {
            _scrollToTopAnimating = false;
          }
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<Store>();
    final t = store.t;
    final theme = Theme.of(context);
    final q = widget.quadrant;
    final live = store.tasksIn(q);
    final entries = _exitRetention.sync(
      items: live,
      epochKey: '${store.activeBoardId}#${store.boardEpoch(store.activeBoardId)}',
      idOf: (task) => task.id,
      keepIfMissing:
          (task) => store.tasks.any(
            (t) =>
                t.id == task.id &&
                t.boardId == store.activeBoardId &&
                t.quadrant == q,
          ),
      reduceMotion: MotionPolicy.reduceMotionOf(context),
    );
    _rowIds = [for (final entry in entries) entry.item.id];
    final accent = Color(quadrantColors[q]!);
    final titleKey = switch (q) {
      qDo => 'q1',
      qPlan => 'q2',
      qDelegate => 'q3',
      _ => 'q4',
    };

    return DragTarget<Task>(
      onWillAcceptWithDetails: (details) => acceptsDrop(details.data),
      onMove: (details) {
        // Header or blank area: no exact slot, the drop goes to the top.
        clearDropSlot();
        onDropHover(q);
        dragAutoScroll(details.offset);
      },
      onLeave: (_) {
        clearDropSlot();
        stopDragAutoScroll();
        onDropHoverEnd();
      },
      onAcceptWithDetails: (details) {
        stopDragAutoScroll();
        clearDropSlot();
        onDropHoverEnd();
        dropAt(details.data, q, null);
      },
      builder: (context, candidate, _) {
        final highlighted = _hovering || candidate.isNotEmpty;
        return AnimatedContainer(
          duration: MotionPolicy.hoverHighlight,
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: highlighted
                ? accent.withValues(alpha: 0.10)
                : Colors.transparent,
            border: highlighted
                ? Border.all(
                    color: accent.withValues(alpha: 0.55),
                    width: 1.5,
                  )
                : null,
          ),
          child: LayoutBuilder(
            builder: (context, box) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // A very short pane (large text in a narrow split) clips the
              // header instead of overflowing the column.
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: box.maxHeight),
                child: ClipRect(
              child: InkWell(
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
                        child: OrphanSqueeze(
                          child: Text(
                            t[titleKey]!,
                            // Long English titles at 360dp with 1.3x
                            // system text need a third line.
                            maxLines: 3,
                            overflow: TextOverflow.visible,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              height: 1.2,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${live.length}',
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
                ),
              ),
              Expanded(
                child:
                    entries.isEmpty
                        ? Center(
                          child: Text(
                            t['empty']!,
                            style: theme.textTheme.bodySmall?.copyWith(
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
                          padding: theme.extension<NeumorphicSkin>() == null
                              ? const EdgeInsets.fromLTRB(4, 2, 4, 16)
                              : const EdgeInsets.fromLTRB(4, 2, 4, 8),
                          itemCount: entries.length,
                          itemBuilder: (context, i) {
                            final entry = entries[i];
                            final task = entry.item;
                            final draggable = _draggable(
                              context,
                              store,
                              task,
                              i,
                              exiting: entry.exiting,
                            );
                            final row = ExitingRow(
                              key: ValueKey('exit-${task.id}'),
                              exiting: entry.exiting,
                              child: draggable,
                            );
                            return KeyedSubtree(
                              key: ValueKey('slot-row-${task.id}'),
                              child: dropSlotRow(q, i, entries.length, row),
                            );
                          },
                        ),
              ),
            ],
          ),
          ),
        );
      },
    );
  }

  /// One widget tree for every row, so selecting a card never remounts it.
  /// Outside multi-select: long press drags the single card (as before).
  /// Selected cards in multi-select drag together as one stack. Touch: long
  /// press first. Desktop mouse: press and drag right away.
  Widget _draggable(
    BuildContext context,
    Store store,
    Task task,
    int index, {
    required bool exiting,
  }) {
    final multi =
        widget.selecting && !exiting && widget.selectedIds.contains(task.id);
    final card = _card(context, task, index);
    final child = ValueListenableBuilder<bool>(
      valueListenable: multiDragActive,
      builder: (context, active, card) => AnimatedOpacity(
        opacity: multi && active ? 0.35 : 1,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        child: card,
      ),
      child: card,
    );
    final Widget feedback = multi
        ? MultiDragStack(
            tasks: [
              task,
              ...store.visibleTasks.where(
                (t) => t.id != task.id && widget.selectedIds.contains(t.id),
              ),
            ],
            cardBuilder: _dragFeedback,
          )
        : _dragFeedback(context, task);
    void started() {
      HapticFeedback.lightImpact();
      if (multi) multiDragActive.value = true;
    }

    void ended(DraggableDetails _) {
      if (multi) multiDragActive.value = false;
    }

    final touch = LongPressDraggable<Task>(
      key: ValueKey(task.id),
      maxSimultaneousDrags: (widget.selecting && !multi) || exiting ? 0 : 1,
      data: task,
      hapticFeedbackOnStart: true,
      onDragStarted: started,
      onDragEnd: ended,
      onDraggableCanceled: (_, __) => HapticFeedback.selectionClick(),
      feedback: feedback,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      childWhenDragging: multi ? child : Opacity(opacity: 0.35, child: child),
      child: child,
    );
    final desktop = !PlatformUiPolicy.of(context).isTouchLayout;
    return PlannerMouseDraggable<Task>(
      maxSimultaneousDrags: multi && desktop ? 1 : 0,
      data: task,
      onDragStarted: started,
      onDragEnd: ended,
      feedback: feedback,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      childWhenDragging: child,
      child: touch,
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
                style: dangerButtonStyle(context),
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
