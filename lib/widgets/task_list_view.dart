import 'package:flutter/material.dart';
import '../ui/danger_button_style.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../storage.dart';
import '../ui/motion_policy.dart';
import '../task_order.dart';
import 'batch_decompose_sheet.dart';
import 'drop_slot.dart';
import 'task_detail_panel.dart';
import 'task_card.dart';
import 'task_exit.dart';

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
  final void Function(Task task, String subtaskId)? onEditSubtask;

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
    this.onEditSubtask,
  });

  @override
  State<TaskListView> createState() => _TaskListViewState();
}

class _TaskListViewState extends State<TaskListView>
    with DropSlotHost<TaskListView> {
  int? _hoveringQuadrant;
  int _hoverTicket = 0;
  final ScrollController _scroll = ScrollController();

  /// Drag reorder: ids of the shown rows of each section, top to bottom.
  final Map<int, List<String>> _rowIds = {};

  @override
  ScrollController get dropScrollController => _scroll;

  @override
  bool acceptsDrop(Task task) =>
      !widget.selecting &&
      task.boardId == context.read<Store>().activeBoardId;

  @override
  bool dropSlotIsNoop(Task dragged, int group, int slot) {
    if (dragged.quadrant != group) return false;
    final own = (_rowIds[group] ?? const []).indexOf(dragged.id);
    return own != -1 && (slot == own || slot == own + 1);
  }

  @override
  void onDropHover(int group) => _claimHover(group);

  @override
  void onDropHoverEnd() {
    _hoverTicket++;
    if (_hoveringQuadrant != null) setState(() => _hoveringQuadrant = null);
  }

  @override
  void dropAt(Task task, int group, int? slot) {
    final store = context.read<Store>();
    if (slot == null) {
      _acceptDrop(context, store, group, task);
      return;
    }
    HapticFeedback.mediumImpact();
    store.placeTasks(
      [task.id],
      group,
      beforeId: dropAnchor(_rowIds[group] ?? const [], slot, {task.id}),
    );
  }

  /// One exit cache per quadrant section; rows are snapshots, never written back.
  final Map<int, ExitRetention<Task>> _retention = {};

  ExitRetention<Task> _retentionFor(int q) => _retention.putIfAbsent(
    q,
    () => ExitRetention<Task>(
      onChange: () {
        if (mounted) setState(() {});
      },
    ),
  );

  @override
  void dispose() {
    for (final entry in _retention.values) {
      entry.dispose();
    }
    _retention.clear();
    _scroll.dispose();
    super.dispose();
  }

  /// DragTarget reports leave before the next target's move. A later claim
  /// in the same gesture cancels the clear so the section highlight does not
  /// flicker while the pointer crosses rows.
  void _claimHover(int quadrant) {
    _hoverTicket++;
    if (_hoveringQuadrant != quadrant) {
      setState(() => _hoveringQuadrant = quadrant);
    }
  }

  void _releaseHover(int quadrant) {
    final ticket = _hoverTicket;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || ticket != _hoverTicket || _hoveringQuadrant != quadrant) {
        return;
      }
      setState(() => _hoveringQuadrant = null);
    });
  }

  void _acceptDrop(BuildContext context, Store store, int quadrant, Task task) {
    _hoverTicket++;
    setState(() => _hoveringQuadrant = null);
    if (task.quadrant != quadrant) {
      HapticFeedback.mediumImpact();
      store.moveTask(task.id, quadrant);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<Store>();
    final t = store.t;
    final theme = Theme.of(context);

    return CustomScrollView(
      key: PageStorageKey('${store.activeBoardId}-task-list-view'),
      controller: _scroll,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 32),
          sliver: SliverMainAxisGroup(
            slivers: [
              for (final q in allQuadrants) ...[
                ..._quadrantSlivers(context, store, t, theme, q),
                if (q != allQuadrants.last)
                  SliverToBoxAdapter(
                    child: Divider(
                      height: 16,
                      thickness: 1,
                      color: theme.brightness == Brightness.light
                          ? const Color(0xFFE5E9F0)
                          : theme.colorScheme.outlineVariant.withValues(
                              alpha: 0.5,
                            ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _quadrantSlivers(
    BuildContext context,
    Store store,
    Map<String, String> t,
    ThemeData theme,
    int q,
  ) {
    final live = store.tasksIn(q);
    final entries = _retentionFor(q).sync(
      items: live,
      epochKey:
          'list-${store.activeBoardId}#${store.boardEpoch(store.activeBoardId)}',
      idOf: (task) => task.id,
      keepIfMissing: (task) => store.tasks.any(
        (t) =>
            t.id == task.id &&
            t.boardId == store.activeBoardId &&
            t.quadrant == q,
      ),
      reduceMotion: MotionPolicy.reduceMotionOf(context),
    );
    _rowIds[q] = [for (final entry in entries) entry.item.id];
    final accent = Color(quadrantColors[q]!);
    final titleKey = switch (q) {
      qDo => 'q1',
      qPlan => 'q2',
      qDelegate => 'q3',
      _ => 'q4',
    };
    final header = _dropShell(
      context: context,
      store: store,
      quadrant: q,
      accent: accent,
      outlined: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            key: ValueKey('list-quadrant-header-$q'),
            borderRadius: BorderRadius.circular(6),
            onTap: () => widget.onQuadrantTap?.call(q),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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
                        fontWeight: FontWeight.w600,
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
                      '${live.length}',
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
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text(
                t['noTasksInQuadrant'] ?? t['empty'] ?? 'No tasks',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.35),
                ),
              ),
            ),
        ],
      ),
    );

    return [
      SliverToBoxAdapter(child: header),
      if (entries.isNotEmpty)
        SliverList.builder(
          itemCount: entries.length,
          itemBuilder: (context, i) {
            final entry = entries[i];
            final task = entry.item;
            final draggable = LongPressDraggable<Task>(
              key: ValueKey('list-drag-${task.id}'),
              maxSimultaneousDrags: widget.selecting || entry.exiting ? 0 : 1,
              data: task,
              hapticFeedbackOnStart: true,
              onDragStarted: () => HapticFeedback.lightImpact(),
              onDraggableCanceled: (_, __) => HapticFeedback.selectionClick(),
              feedback: _dragFeedback(context, task),
              dragAnchorStrategy: pointerDragAnchorStrategy,
              childWhenDragging: Opacity(
                opacity: 0.35,
                child: _taskCard(context, store, task, i),
              ),
              child: _taskCard(context, store, task, i),
            );
            return ExitingRow(
              key: ValueKey('list-exit-${task.id}'),
              exiting: entry.exiting,
              child: dropSlotRow(
                q,
                i,
                entries.length,
                _dropShell(
                  context: context,
                  store: store,
                  quadrant: q,
                  accent: accent,
                  outlined: false,
                  target: false,
                  child: draggable,
                ),
              ),
            );
          },
        ),
    ];
  }

  Widget _dropShell({
    required BuildContext context,
    required Store store,
    required int quadrant,
    required Color accent,
    required bool outlined,
    required Widget child,
    bool target = true,
  }) {
    Widget decorated(bool candidate) => AnimatedContainer(
      duration: MotionPolicy.hoverHighlight,
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: _hoveringQuadrant == quadrant || candidate
            ? accent.withValues(alpha: 0.10)
            : Colors.transparent,
        borderRadius: outlined ? BorderRadius.circular(8) : null,
        border: outlined && (_hoveringQuadrant == quadrant || candidate)
            ? Border.all(color: accent.withValues(alpha: 0.55), width: 1.5)
            : null,
      ),
      child: child,
    );
    // A row: the slot targets around it handle the drop.
    if (!target) return decorated(false);
    // Section header: no exact slot, the drop goes to the top.
    return DragTarget<Task>(
      onWillAcceptWithDetails: (details) => acceptsDrop(details.data),
      onMove: (details) {
        clearDropSlot();
        _claimHover(quadrant);
        dragAutoScroll(details.offset);
      },
      onLeave: (_) {
        stopDragAutoScroll();
        _releaseHover(quadrant);
      },
      onAcceptWithDetails: (details) {
        stopDragAutoScroll();
        clearDropSlot();
        _acceptDrop(context, store, quadrant, details.data);
      },
      builder: (context, candidate, _) => decorated(candidate.isNotEmpty),
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
      rowLayout: TaskRowLayout.hierarchical,
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
      onEditSubtask: widget.onEditSubtask == null
          ? null
          : (id) => widget.onEditSubtask!(task, id),
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
      builder: (dialogContext) => AlertDialog(
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
    if (ok == true && context.mounted) {
      store.deleteTask(task.id);
    }
  }

  Future<void> _decomposeSingle(BuildContext context, Task task) =>
      showBatchDecomposeSheet(context, [task], autoStart: true);
}
