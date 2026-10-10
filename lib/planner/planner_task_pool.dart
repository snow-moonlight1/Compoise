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
  final void Function(Task task, Offset global) onDragEnd;

  @override
  State<PlannerTaskPool> createState() => _PlannerTaskPoolState();
}

class _PlannerTaskPoolState extends State<PlannerTaskPool> {
  int _quadrant = qDo;
  bool _expanded = false;
  final _page = PageController();
  final _lists = List<ScrollController>.generate(4, (_) => ScrollController());

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onSheet);
  }

  @override
  void didUpdateWidget(PlannerTaskPool oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_onSheet);
    widget.controller.addListener(_onSheet);
  }

  void _onSheet() {
    if (!widget.controller.isAttached) return;
    final expanded = widget.controller.size > widget.minSize + 0.04;
    if (expanded == _expanded) return;
    setState(() => _expanded = expanded);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onSheet);
    _page.dispose();
    for (final list in _lists) {
      list.dispose();
    }
    super.dispose();
  }

  List<Task> _of(int quadrant) => [
    for (final task in widget.tasks)
      if (task.quadrant == quadrant) task,
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final skin = NeumorphicSkin.maybeOf(context);
    return DraggableScrollableSheet(
      controller: widget.controller,
      initialChildSize: widget.minSize,
      minChildSize: widget.minSize,
      maxChildSize: 0.92,
      snap: true,
      snapSizes: [widget.minSize, 0.5, 0.92],
      builder: (context, scrollController) {
        final surface = Material(
          color: skin?.canvas ?? theme.colorScheme.surface,
          elevation: skin == null ? 3 : 0,
          shadowColor: skin?.darkShadow ?? theme.colorScheme.shadow,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
          ),
          clipBehavior: Clip.antiAlias,
          child: _expanded
              ? _expandedBody(theme, scrollController)
              : _collapsed(theme, scrollController),
        );
        return surface;
      },
    );
  }

  Widget _collapsed(ThemeData theme, ScrollController scrollController) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return ListView(
          controller: scrollController,
          padding: EdgeInsets.zero,
          children: [
            SizedBox(
              height: 72,
              width: constraints.maxWidth,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _expandHalf,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    width: constraints.maxWidth,
                    child: _bar(theme, expanded: false),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _expandedBody(ThemeData theme, ScrollController scrollController) {
    final scale = math.max(
      1.0,
      MediaQuery.textScalerOf(context).scale(14) / 14,
    );
    return Column(
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragUpdate: (details) => _dragSheet(details.primaryDelta),
          child: _bar(theme, expanded: true),
        ),
        SizedBox(
          height: 48 * scale,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            children: [
              for (final quadrant in allQuadrants)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(
                    label: Text(
                      '${widget.t['scheduleQuadrant$quadrant']} ${_of(quadrant).length}',
                    ),
                    selected: _quadrant == quadrant,
                    onSelected: (_) => _select(quadrant),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: PageView(
            controller: _page,
            onPageChanged: (index) =>
                setState(() => _quadrant = allQuadrants[index]),
            children: [
              for (final quadrant in allQuadrants)
                _taskList(
                  theme,
                  quadrant,
                  _of(quadrant),
                  quadrant == _quadrant
                      ? scrollController
                      : _lists[allQuadrants.indexOf(quadrant)],
                ),
            ],
          ),
        ),
        _dots(theme),
      ],
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
                        ? theme.colorScheme.primary
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

  void _expandHalf() {
    if (!widget.controller.isAttached) return;
    widget.controller.animateTo(
      0.5,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  void _select(int quadrant) {
    setState(() => _quadrant = quadrant);
    final index = allQuadrants.indexOf(quadrant);
    if (_page.hasClients) {
      _page.animateToPage(
        index,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    }
  }

  void _dragSheet(double? delta) {
    if (delta == null || !widget.controller.isAttached) return;
    final height = widget.controller.pixelsToSize(delta);
    widget.controller.jumpTo(
      (widget.controller.size - height).clamp(widget.minSize, 0.92),
    );
  }

  Widget _bar(ThemeData theme, {required bool expanded}) {
    final counts = {for (final quadrant in allQuadrants) quadrant: _of(quadrant).length};
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
                              _expandHalf();
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
                    'quadrant': widget.t['scheduleQuadrant$quadrant']!,
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
    final deadline = task.deadline == null
        ? widget.t['scheduleNoDeadline']!
        : '${widget.t['deadline']}: ${scheduleDateLabel(ScheduleCivilDate(
            scheduleLocalTime(task.deadline!, widget.zone).year,
            scheduleLocalTime(task.deadline!, widget.zone).month,
            scheduleLocalTime(task.deadline!, widget.zone).day,
          ))}';
    final body = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
          const SizedBox(width: 8),
          DecoratedBox(
            decoration: BoxDecoration(
              color: Color(
                quadrantColors[task.quadrant] ?? quadrantColors[qEliminate]!,
              ).withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(widget.t['scheduleDefaultLength']!),
            ),
          ),
        ],
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
          constraints: const BoxConstraints(maxWidth: 240),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              '${task.title}\n${widget.t['scheduleDefaultLength']}',
            ),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.35, child: body),
      onDragStarted: () => widget.onDragStarted(task),
      onDragUpdate: (details) =>
          widget.onDragUpdate(task, details.globalPosition),
      onDragEnd: (details) => widget.onDragEnd(task, details.offset),
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
