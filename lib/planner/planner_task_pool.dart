import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models.dart';
import '../schedule_time.dart';
import '../theme.dart';
import '../widgets/schedule_layout.dart';
import 'planner_guide_flag.dart';
import 'planner_labels.dart';

/// Height of the pool when it is opened with a tap, as a share of the page.
/// Between a quarter and three tenths of the screen: enough for two or three cards while most of
/// the timeline stays visible.
const double plannerPoolOpenSize = 0.3;
const double plannerPoolHalfSize = 0.55;
const double plannerPoolMaxSize = 0.92;

/// Bottom sheet of tasks, grouped by quadrant, one swipeable page each.
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
    this.scheduledIds = const {},
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

  /// Tasks that already have a schedule item; they stay in the pool, tagged.
  final Set<String> scheduledIds;
  final Map<String, String> t;
  final String zone;
  final bool writable;
  final FocusNode? addFocus;

  /// Shown only while a board filter is active.
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
  final _pages = PageController();
  final _scrolls = {for (final q in allQuadrants) q: ScrollController()};
  int _quadrant = qDo;
  List<double>? _snaps;
  double? _snapMin;
  final _highlightKey = GlobalKey();
  bool _expandRetry = false;
  bool _showTabHint = false;

  @override
  void initState() {
    super.initState();
    PlannerGuideFlags.seen(PlannerGuideFlags.tabHintKey).then((seen) {
      if (mounted && !seen) setState(() => _showTabHint = true);
    });
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

  @override
  void dispose() {
    _pages.dispose();
    for (final c in _scrolls.values) {
      c.dispose();
    }
    super.dispose();
  }

  List<Task> _of(int quadrant) => [
    for (final task in widget.tasks)
      if (task.quadrant == quadrant) task,
  ];

  bool get _reduceMotion => MediaQuery.disableAnimationsOf(context);

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
    _expand(plannerPoolHalfSize);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _highlightKey.currentContext;
      if (target == null) return;
      Scrollable.ensureVisible(target, alignment: 0.2);
    });
  }

  void _dismissTabHint() {
    if (!_showTabHint) return;
    setState(() => _showTabHint = false);
    PlannerGuideFlags.mark(PlannerGuideFlags.tabHintKey);
  }

  void _select(int quadrant, {bool animate = true}) {
    final index = allQuadrants.indexOf(quadrant);
    if (_pages.hasClients && index >= 0) {
      if (animate && !_reduceMotion) {
        _pages.animateToPage(
          index,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        );
      } else {
        _pages.jumpToPage(index);
      }
    }
    if (_quadrant != quadrant) setState(() => _quadrant = quadrant);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final skin = NeumorphicSkin.maybeOf(context);
    // A fresh list every build makes the sheet treat snaps as changed and
    // spring shut, which cancels a tap or a highlight that was opening it.
    if (_snaps == null || _snapMin != widget.minSize) {
      _snapMin = widget.minSize;
      _snaps = [
        widget.minSize,
        math.max(plannerPoolOpenSize, widget.minSize + 0.05),
        plannerPoolHalfSize,
        plannerPoolMaxSize,
      ];
    }
    return DraggableScrollableSheet(
      controller: widget.controller,
      initialChildSize: widget.minSize,
      minChildSize: widget.minSize,
      maxChildSize: plannerPoolMaxSize,
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
                compact ? 72.0 : math.max(56.0, 28 * scale + 28),
                height,
              );
              final tabsH = compact
                  ? 0.0
                  : math.min(44 * scale, math.max(0.0, height - headerH - 56));
              return Column(
                children: [
                  // The sheet reports its size only while its own scroll
                  // controller is in use. The pages scroll with their own
                  // controllers, so this zero-height anchor keeps the sheet
                  // controller attached; it never scrolls.
                  SizedBox(
                    height: 0,
                    child: SingleChildScrollView(
                      controller: scrollController,
                      physics: const NeverScrollableScrollPhysics(),
                      child: const SizedBox.shrink(),
                    ),
                  ),
                  SizedBox(
                    height: headerH,
                    width: constraints.maxWidth,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _toggle,
                      onVerticalDragUpdate: (details) =>
                          _dragSheet(details.primaryDelta),
                      onVerticalDragEnd: (details) =>
                          _settle(details.primaryVelocity ?? 0),
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
                  SizedBox(
                    height: tabsH,
                    child: tabsH == 0
                        ? const SizedBox.shrink()
                        : _tabs(theme, constraints.maxWidth),
                  ),
                  if (!compact && _showTabHint)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                      child: Row(
                        children: [
                          Icon(
                            Icons.swipe,
                            size: 16,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              widget.t['scheduleTabHint']!,
                              key: const ValueKey('schedule-tab-hint'),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: PageView(
                      key: const ValueKey('schedule-pool-pages'),
                      controller: _pages,
                      onPageChanged: (index) {
                        _dismissTabHint();
                        setState(() => _quadrant = allQuadrants[index]);
                      },
                      children: [
                        for (final q in allQuadrants)
                          _taskList(theme, q, _of(q), _scrolls[q]!),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _tabs(ThemeData theme, double width) {
    return Stack(
      children: [
        Row(
          children: [
            for (final quadrant in allQuadrants)
              Expanded(child: _tab(theme, quadrant)),
          ],
        ),
        // The underline follows the page while it is being swiped.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 3,
          child: AnimatedBuilder(
            animation: _pages,
            builder: (context, _) {
              final page = _pages.hasClients && _pages.position.haveDimensions
                  ? (_pages.page ?? 0.0)
                  : allQuadrants.indexOf(_quadrant).toDouble();
              final color = Color.lerp(
                Color(quadrantColors[allQuadrants[page.floor().clamp(0, 3)]]!),
                Color(quadrantColors[allQuadrants[page.ceil().clamp(0, 3)]]!),
                page - page.floor(),
              )!;
              return Align(
                alignment: Alignment(-1 + 2 * page / 3, 0),
                child: FractionallySizedBox(
                  widthFactor: 0.25,
                  child: Center(
                    child: Container(
                      width: 36,
                      height: 3,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _tab(ThemeData theme, int quadrant) {
    final selected = quadrant == _quadrant;
    final color = Color(quadrantColors[quadrant]!);
    return InkWell(
      key: ValueKey('schedule-pool-tab-$quadrant'),
      onTap: () {
        _dismissTabHint();
        _select(quadrant);
        if (_isCollapsed) _expand(plannerPoolOpenSize);
      },
      canRequestFocus: false,
      child: Semantics(
        selected: selected,
        button: true,
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.t['scheduleQuadrant$quadrant']!,
                    maxLines: 1,
                    softWrap: false,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: selected
                          ? color
                          : theme.colorScheme.onSurfaceVariant,
                      fontWeight: selected ? FontWeight.w700 : null,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${_of(quadrant).length}',
                    style: theme.textTheme.labelSmall?.copyWith(color: color),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool get _isCollapsed =>
      widget.controller.isAttached &&
      widget.controller.size <= widget.minSize + 0.02;

  void _toggle() {
    if (_isCollapsed || !widget.controller.isAttached) {
      _expand(plannerPoolOpenSize);
    } else {
      _animate(widget.minSize);
    }
  }

  void _expand(double size) {
    if (!widget.controller.isAttached) {
      if (_expandRetry) return;
      _expandRetry = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _expandRetry = false;
        if (mounted) _expand(size);
      });
      return;
    }
    _animate(math.max(size, widget.minSize));
  }

  void _animate(double size) {
    if (_reduceMotion) {
      widget.controller.jumpTo(size);
      return;
    }
    widget.controller.animateTo(
      size,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOut,
    );
  }

  void _dragSheet(double? delta) {
    if (delta == null || !widget.controller.isAttached) return;
    final height = widget.controller.pixelsToSize(delta);
    widget.controller.jumpTo(
      (widget.controller.size - height).clamp(
        widget.minSize,
        plannerPoolMaxSize,
      ),
    );
  }

  /// Settles on the nearest of the four heights, nudged by the fling.
  void _settle(double velocity) {
    if (!widget.controller.isAttached) return;
    final snaps = _snaps!;
    final nudge = velocity.abs() > 300 ? (velocity < 0 ? 0.12 : -0.12) : 0.0;
    final target = widget.controller.size + nudge;
    var best = snaps.first;
    for (final s in snaps) {
      if ((s - target).abs() < (best - target).abs()) best = s;
    }
    _animate(best);
  }

  Widget _bar(ThemeData theme, {required bool expanded}) {
    final counts = {
      for (final quadrant in allQuadrants) quadrant: _of(quadrant).length,
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 8, 4),
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
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
                          ),
                          if (expanded && widget.boardLabel != null) ...[
                            const SizedBox(width: 8),
                            _boardTag(theme),
                          ],
                        ],
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
                                    _select(quadrant, animate: false);
                                    _expand(plannerPoolOpenSize);
                                  },
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 8,
                                        height: 8,
                                        decoration: BoxDecoration(
                                          color: Color(
                                            quadrantColors[quadrant]!,
                                          ),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Text('${counts[quadrant]}'),
                                      const SizedBox(width: 10),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                if (widget.writable)
                  (expanded
                      ? TextButton.icon(
                          key: const ValueKey('schedule-add'),
                          focusNode: widget.addFocus,
                          onPressed: widget.addEnabled ? widget.onAdd : null,
                          icon: const Icon(Icons.add),
                          label: Text(widget.t['schedulePoolAdd']!),
                        )
                      : IconButton.filledTonal(
                          key: const ValueKey('schedule-add'),
                          focusNode: widget.addFocus,
                          tooltip: widget.t['schedulePoolAdd'],
                          onPressed: widget.addEnabled ? widget.onAdd : null,
                          icon: const Icon(Icons.add),
                        ))
                else
                  const SizedBox(width: 48),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _boardTag(ThemeData theme) => Flexible(
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
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: Text(
            widget.boardLabel!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSecondaryContainer,
            ),
          ),
        ),
      ),
    ),
  );

  Widget _taskList(
    ThemeData theme,
    int quadrant,
    List<Task> tasks,
    ScrollController controller,
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
      padding: const EdgeInsets.only(top: 4),
      children: [for (final task in tasks) _card(theme, task), add],
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
    final scheduled = widget.scheduledIds.contains(task.id);
    final color = Color(
      quadrantColors[task.quadrant] ?? quadrantColors[qEliminate]!,
    );
    final body = DecoratedBox(
      key: highlighted ? _highlightKey : null,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: highlighted ? theme.colorScheme.primary : Colors.transparent,
          width: 2,
        ),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 32,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Icon(
                Icons.drag_indicator,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge,
                    ),
                    Text(
                      deadline,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (scheduled)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Icon(
                    Icons.event_available,
                    size: 18,
                    color: theme.colorScheme.primary,
                    semanticLabel: widget.t['schedulePoolScheduled'],
                  ),
                ),
            ],
          ),
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
            child: Text(task.title, maxLines: 2),
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
