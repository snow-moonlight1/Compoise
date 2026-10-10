import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models.dart';
import '../schedule_time.dart';
import '../theme.dart';
import '../widgets/schedule_layout.dart';
import 'planner_labels.dart';

/// Bottom sheet of unscheduled tasks, grouped by quadrant.
class PlannerTaskPool extends StatefulWidget {
  const PlannerTaskPool({
    super.key,
    required this.controller,
    required this.minSize,
    required this.tasks,
    required this.t,
    required this.zone,
    required this.writable,
    required this.onAdd,
    required this.onDragStarted,
    required this.onDragUpdate,
    required this.onDragEnd,
    this.addFocus,
    this.boardLabel,
    this.onBoard,
    this.onAddToQuadrant,
    this.onOpenTask,
    this.addEnabled = true,
    this.highlightTaskId,
    this.highlightToken = 0,
  });

  final DraggableScrollableController controller;
  final double minSize;
  final List<Task> tasks;
  final Map<String, String> t;
  final String zone;
  final bool writable;
  final FocusNode? addFocus;
  final String? boardLabel;
  final VoidCallback? onBoard;
  final ValueChanged<int>? onAddToQuadrant;
  final ValueChanged<Task>? onOpenTask;
  final bool addEnabled;
  final VoidCallback onAdd;
  final ValueChanged<Task> onDragStarted;
  final void Function(Task task, Offset global) onDragUpdate;
  final void Function(Task task, DraggableDetails details) onDragEnd;
  final String? highlightTaskId;

  /// Bumps when the same task should be revealed again.
  final int highlightToken;

  @override
  State<PlannerTaskPool> createState() => _PlannerTaskPoolState();
}

class _PlannerTaskPoolState extends State<PlannerTaskPool> {
  int _quadrant = qDo;
  List<double>? _snaps;
  double? _snapMin;
  final _highlightKey = GlobalKey();
  bool _expandRetry = false;

  @override
  void initState() {
    super.initState();
    final id = widget.highlightTaskId;
    if (id != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _reveal(id);
      });
    }
  }

  @override
  void didUpdateWidget(PlannerTaskPool oldWidget) {
    super.didUpdateWidget(oldWidget);
    final id = widget.highlightTaskId;
    if (id != null &&
        (id != oldWidget.highlightTaskId ||
            widget.highlightToken != oldWidget.highlightToken)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _reveal(id);
      });
    }
  }

  List<Task> _of(int quadrant) => [
    for (final task in widget.tasks)
      if (task.quadrant == quadrant) task,
  ];

  void _reveal(String taskId) {
    Task? task;
    for (final item in widget.tasks) {
      if (item.id == taskId) {
        task = item;
        break;
      }
    }
    if (task == null) return;
    _select(task.quadrant);
    _expandFull();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _highlightKey.currentContext;
      if (target == null) return;
      Scrollable.ensureVisible(target, alignment: 0.2);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final skin = NeumorphicSkin.maybeOf(context);
    // A fresh list every build makes the sheet treat snaps as changed and
    // spring shut, which cancels a tap or a highlight that was opening it.
    if (_snaps == null || _snapMin != widget.minSize) {
      _snapMin = widget.minSize;
      _snaps = [widget.minSize, 0.5, 0.92];
    }
    return DraggableScrollableSheet(
      controller: widget.controller,
      initialChildSize: widget.minSize,
      minChildSize: widget.minSize,
      maxChildSize: 0.92,
      snap: true,
      snapSizes: _snaps,
      builder: (context, scrollController) {
        return Material(
          color: skin?.canvas ?? theme.colorScheme.surface,
          elevation: skin == null ? 3 : 0,
          shadowColor: skin?.darkShadow ?? theme.colorScheme.shadow,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
          ),
          clipBehavior: Clip.antiAlias,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final height = constraints.maxHeight;
              final scale = math.max(
                1.0,
                MediaQuery.textScalerOf(context).scale(14) / 14,
              );
              final compact = height < 140;
              final headerH = math.min(
                compact ? 72.0 : math.max(88.0, 40 * scale + 48),
                height,
              );
              final chipH = compact
                  ? 0.0
                  : math.min(
                      64 * scale,
                      math.max(0.0, height - headerH - 96),
                    );
              return Column(
                children: [
                  SizedBox(
                    height: headerH,
                    width: constraints.maxWidth,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _expandFull,
                      onVerticalDragUpdate: (details) =>
                          _dragSheet(details.primaryDelta),
                      child: compact
                          ? FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: SizedBox(
                                width: constraints.maxWidth,
                                child: _bar(theme, expanded: false),
                              ),
                            )
                          : _bar(theme, expanded: true),
                    ),
                  ),
                  // This slot stays put. Inserting it only while open used to
                  // dispose the page underneath and cancel the sheet animation.
                  SizedBox(
                    height: chipH,
                    child: chipH == 0
                        ? const SizedBox.shrink()
                        : ListView(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            children: [
                              for (final quadrant in allQuadrants)
                                _quadrantChip(theme, quadrant),
                            ],
                          ),
                  ),
                  Expanded(
                    // One list keeps the sheet controller. Moving that
                    // controller onto another page detaches it and cancels
                    // the open animation.
                    child: GestureDetector(
                      onHorizontalDragEnd: (details) {
                        final velocity = details.primaryVelocity ?? 0;
                        if (velocity.abs() < 250) return;
                        final index = allQuadrants.indexOf(_quadrant);
                        final next = velocity < 0 ? index + 1 : index - 1;
                        if (next < 0 || next >= allQuadrants.length) return;
                        _select(allQuadrants[next]);
                      },
                      child: _taskList(
                        theme,
                        _quadrant,
                        _of(_quadrant),
                        scrollController,
                      ),
                    ),
                  ),
                  if (!compact) _dots(theme),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _quadrantChip(ThemeData theme, int quadrant) {
    final selected = quadrant == _quadrant;
    final color = Color(quadrantColors[quadrant]!);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Material(
        color: selected
            ? color.withValues(alpha: 0.16)
            : theme.colorScheme.surface,
        shape: StadiumBorder(
          side: BorderSide(
            color: selected ? color : theme.colorScheme.outlineVariant,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            _select(quadrant);
            _expandFull();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                Text(widget.t['q$quadrant']!, maxLines: 1, softWrap: false),
                const SizedBox(width: 8),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
                    ),
                    child: Text(
                      '${_of(quadrant).length}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _dots(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final quadrant in allQuadrants)
            InkWell(
              onTap: () => _select(quadrant),
              canRequestFocus: false,
              customBorder: const CircleBorder(),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: quadrant == _quadrant
                        ? Color(quadrantColors[quadrant]!)
                        : theme.colorScheme.outlineVariant,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _expandFull() {
    if (!widget.controller.isAttached) {
      if (_expandRetry) return;
      _expandRetry = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _expandRetry = false;
        if (mounted) _expandFull();
      });
      return;
    }
    widget.controller.animateTo(
      0.92,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOut,
    );
  }

  void _select(int quadrant) {
    if (_quadrant == quadrant) return;
    setState(() => _quadrant = quadrant);
  }

  void _dragSheet(double? delta) {
    if (delta == null || !widget.controller.isAttached) return;
    final height = widget.controller.pixelsToSize(delta);
    widget.controller.jumpTo(
      (widget.controller.size - height).clamp(widget.minSize, 0.92),
    );
  }

  Widget _bar(ThemeData theme, {required bool expanded}) {
    final counts = {
      for (final quadrant in allQuadrants) quadrant: _of(quadrant).length,
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  expanded
                      ? widget.t['schedulePool']!
                      : plannerCounted(
                          widget.t['schedulePoolCount']!,
                          widget.tasks.length,
                        ),
                  style: theme.textTheme.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                ),
                if (!expanded)
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final quadrant in allQuadrants)
                        GestureDetector(
                          onTap: () {
                            _select(quadrant);
                            _expandFull();
                          },
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: Color(quadrantColors[quadrant]!),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text('${counts[quadrant]}'),
                              const SizedBox(width: 8),
                            ],
                          ),
                        ),
                    ],
                    ),
                  )
                else if (widget.boardLabel != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: InkWell(
                      onTap: widget.onBoard,
                      canRequestFocus: false,
                      borderRadius: BorderRadius.circular(8),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: theme.colorScheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          child: Text(
                            widget.boardLabel!,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.onSecondaryContainer,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          widget.writable
              ? (expanded
                    ? TextButton.icon(
                        key: const ValueKey('schedule-add'),
                        focusNode: widget.addFocus,
                        onPressed: widget.addEnabled ? widget.onAdd : null,
                        icon: const Icon(Icons.add),
                        label: Text(widget.t['schedulePoolAdd']!),
                      )
                    : IconButton(
                        key: const ValueKey('schedule-add'),
                        focusNode: widget.addFocus,
                        tooltip: widget.t['schedulePoolAdd'],
                        onPressed: widget.addEnabled ? widget.onAdd : null,
                        icon: const Icon(Icons.add),
                      ))
              : const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _taskList(
    ThemeData theme,
    int quadrant,
    List<Task> tasks,
    ScrollController? controller,
  ) {
    final add = widget.onAddToQuadrant == null
        ? const SizedBox(height: 12)
        : Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: OutlinedButton.icon(
                onPressed: widget.addEnabled
                    ? () => widget.onAddToQuadrant!(quadrant)
                    : null,
                icon: const Icon(Icons.add),
                label: Text(
                  plannerFilled(widget.t['schedulePoolAddQuadrant']!, {
                    'quadrant': widget.t['q$quadrant']!,
                  }),
                ),
              ),
            ),
          );
    return ListView(
      controller: controller,
      children: [
        for (final task in tasks) _card(theme, task),
        add,
      ],
    );
  }

  Widget _card(ThemeData theme, Task task) {
    final local = task.deadline == null
        ? null
        : scheduleLocalTime(task.deadline!, widget.zone);
    final deadline = local == null
        ? widget.t['scheduleNoDeadline']!
        : '${widget.t['deadline']}: ${scheduleDateLabel(ScheduleCivilDate(local.year, local.month, local.day))}';
    final highlighted = task.id == widget.highlightTaskId;
    final body = DecoratedBox(
      key: highlighted ? _highlightKey : null,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: highlighted ? theme.colorScheme.primary : Colors.transparent,
          width: 2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          children: [
            Icon(Icons.drag_handle, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${task.title}\n$deadline',
                maxLines: 3,
                overflow: TextOverflow.fade,
              ),
            ),
          ],
        ),
      ),
    );
    if (!widget.writable) return body;
    return LongPressDraggable<String>(
      key: ValueKey('schedule-pool-${task.id}'),
      data: task.id,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text('${task.title}\n$deadline'),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.35, child: body),
      onDragStarted: () => widget.onDragStarted(task),
      onDragUpdate: (details) =>
          widget.onDragUpdate(task, details.globalPosition),
      onDragEnd: (details) => widget.onDragEnd(task, details),
      child: widget.onOpenTask == null
          ? body
          : GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => widget.onOpenTask!(task),
              child: body,
            ),
    );
  }
}
