import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models.dart';
import '../schedule_time.dart';
import '../theme.dart';
import '../widgets/schedule_layout.dart';
import 'planner_drag_feedback.dart';
import 'planner_guide_flag.dart';
import 'planner_labels.dart';

/// Height of the pool when it is opened with a tap, as a share of the page.
/// A third of the screen: enough for two or three cards while most of
/// the timeline stays visible.
const double plannerPoolOpenSize = 0.33;
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
    _pointer.dispose();
    for (final c in _scrolls.values) {
      c.dispose();
    }
    super.dispose();
  }

  List<Task> _of(int quadrant) => [
    for (final task in widget.tasks)
      if (task.quadrant == quadrant) task,
  ];

  final _pointer = PlannerDragPointer();

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
              final width = constraints.maxWidth;
              final attached = widget.controller.isAttached;
              final parentH =
                  height /
                  math.max(
                    attached ? widget.controller.size : widget.minSize,
                    0.0001,
                  );
              final collapsedPx = widget.minSize * parentH;
              final openPx = plannerPoolOpenSize * parentH;
              final end = collapsedPx + (openPx - collapsedPx) * 0.7;
              // 0 = folded bar, 1 = opened. One number drives the fade between
              // the two headers and the glide of the dots and counts.
              var p = end <= collapsedPx
                  ? 0.0
                  : ((height - collapsedPx) / (end - collapsedPx)).clamp(
                      0.0,
                      1.0,
                    );
              p = _reduceMotion
                  ? (p >= 0.5 ? 1.0 : 0.0)
                  : Curves.easeInOut.transform(p);
              final headerH = math.max(56.0, 28 * scale + 28);
              final tabsH = 44 * scale;
              final spots = _spots(theme, width, headerH, tabsH, scale);
              final bodyH = math.max(height, headerH + tabsH + 160);
              return Stack(
                children: [
                  // Opened layout: always laid out at full size and revealed
                  // by the sheet, so nothing re-flows while it grows.
                  Offstage(
                    offstage: p == 0,
                    child: IgnorePointer(
                      ignoring: p < 0.5,
                      child: Opacity(
                        opacity: p,
                        child: OverflowBox(
                          alignment: Alignment.topCenter,
                          minHeight: bodyH,
                          maxHeight: bodyH,
                          child: _opened(
                            theme,
                            scrollController,
                            width,
                            headerH,
                            tabsH,
                            spots,
                            focusAdd: p >= 0.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (p < 1)
                    IgnorePointer(
                      ignoring: p >= 0.5,
                      child: Opacity(
                        opacity: 1 - p,
                        child: _folded(theme, width, spots, focusAdd: p < 0.5),
                      ),
                    ),
                  // Shared dots and counts: the same widgets slide from the
                  // folded bar to their quadrant tab.
                  IgnorePointer(
                    child: Stack(
                      children: [
                        for (final spot in spots)
                          ..._spotWidgets(theme, spot, p),
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

  double _textWidth(String text, TextStyle? style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final w = painter.width.ceilToDouble();
    painter.dispose();
    return w;
  }

  TextStyle? _countStyle(ThemeData theme) => theme.textTheme.labelMedium;

  TextStyle? _tabStyle(ThemeData theme) =>
      theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600);

  /// Where each quadrant's dot and count sit folded and opened. The tab and the
  /// folded bar reserve exactly these slots, so the glide starts and ends on
  /// the real layout.
  List<_PoolSpot> _spots(
    ThemeData theme,
    double width,
    double headerH,
    double tabsH,
    double scale,
  ) {
    final result = <_PoolSpot>[];
    var x = 16.0;
    final cell = width / allQuadrants.length;
    for (var i = 0; i < allQuadrants.length; i++) {
      final q = allQuadrants[i];
      final count = '${_of(q).length}';
      final countW = _textWidth(count, _countStyle(theme));
      final labelW = _textWidth(
        widget.t['scheduleQuadrant$q']!,
        _tabStyle(theme),
      );
      final content = _dotSlot + labelW + 4 + countW;
      final f = math.min(1.0, (cell - 8) / content);
      final left = i * cell + (cell - content * f) / 2;
      result.add(
        _PoolSpot(
          quadrant: q,
          count: count,
          countW: countW,
          labelW: labelW,
          foldDot: Offset(x, _foldDotsY),
          foldCount: Offset(x + _dotSlot, _foldDotsY),
          openDot: Offset(left, headerH + tabsH / 2),
          openCount: Offset(
            left + (_dotSlot + labelW + 4) * f,
            headerH + tabsH / 2,
          ),
        ),
      );
      x += _dotSlot + countW + 10;
    }
    return result;
  }

  static const _dotSlot = 12.0;
  static const _foldDotsY = 52.0;

  List<Widget> _spotWidgets(ThemeData theme, _PoolSpot spot, double p) {
    final color = Color(quadrantColors[spot.quadrant]!);
    final dot = Offset.lerp(spot.foldDot, spot.openDot, p)!;
    final count = Offset.lerp(spot.foldCount, spot.openCount, p)!;
    return [
      Positioned(
        key: ValueKey('schedule-pool-dot-${spot.quadrant}'),
        left: dot.dx,
        top: dot.dy - 4,
        child: Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      ),
      Positioned(
        key: ValueKey('schedule-pool-count-${spot.quadrant}'),
        left: count.dx,
        top: count.dy - 10,
        height: 20,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            spot.count,
            maxLines: 1,
            softWrap: false,
            style: _countStyle(theme)?.copyWith(color: color),
          ),
        ),
      ),
    ];
  }

  /// Folded bar: handle, "Task pool · N", and the round "+". The dots and
  /// counts are drawn by the shared layer; only their tap areas live here.
  Widget _folded(
    ThemeData theme,
    double width,
    List<_PoolSpot> spots, {
    required bool focusAdd,
  }) {
    return SizedBox(
      height: 72,
      width: width,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggle,
              onVerticalDragUpdate: (d) => _dragSheet(d.primaryDelta),
              onVerticalDragEnd: (d) => _settle(d.primaryVelocity ?? 0),
            ),
          ),
          Positioned(
            top: 6,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
          Positioned(
            top: 14,
            left: 16,
            right: 64,
            height: 28,
            child: IgnorePointer(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  plannerCounted(
                    widget.t['schedulePoolCount']!,
                    widget.tasks.length,
                  ),
                  style: theme.textTheme.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                ),
              ),
            ),
          ),
          for (final spot in spots)
            Positioned(
              left: spot.foldDot.dx,
              top: _foldDotsY - 12,
              width: _dotSlot + spot.countW + 10,
              height: 24,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  _select(spot.quadrant, animate: false);
                  _expand(plannerPoolOpenSize);
                },
              ),
            ),
          if (widget.writable)
            Positioned(
              right: 8,
              top: 12,
              child: IconButton.filledTonal(
                key: const ValueKey('schedule-add'),
                focusNode: focusAdd ? widget.addFocus : null,
                tooltip: widget.t['schedulePoolAdd'],
                onPressed: widget.addEnabled ? widget.onAdd : null,
                icon: const Icon(Icons.add),
              ),
            ),
        ],
      ),
    );
  }

  Widget _opened(
    ThemeData theme,
    ScrollController scrollController,
    double width,
    double headerH,
    double tabsH,
    List<_PoolSpot> spots, {
    required bool focusAdd,
  }) {
    return Column(
      children: [
        // The sheet reports its size only while its own scroll controller is
        // in use. The pages scroll with their own controllers, so this
        // zero-height anchor keeps the sheet controller attached.
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
          width: width,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggle,
            onVerticalDragUpdate: (d) => _dragSheet(d.primaryDelta),
            onVerticalDragEnd: (d) => _settle(d.primaryVelocity ?? 0),
            child: _bar(theme, focusAdd: focusAdd),
          ),
        ),
        SizedBox(height: tabsH, child: _tabs(theme, width, spots)),
        if (_showTabHint)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Row(
              children: [
                Icon(Icons.swipe, size: 16, color: theme.colorScheme.primary),
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
  }

  Widget _tabs(ThemeData theme, double width, List<_PoolSpot> spots) {
    return Stack(
      children: [
        Row(
          children: [
            for (final quadrant in allQuadrants)
              Expanded(child: _tab(theme, quadrant, spots)),
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

  Widget _tab(ThemeData theme, int quadrant, List<_PoolSpot> spots) {
    final spot = spots.firstWhere((e) => e.quadrant == quadrant);
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
                  // Room for the shared dot and count drawn above.
                  const SizedBox(width: _dotSlot),
                  Text(
                    widget.t['scheduleQuadrant$quadrant']!,
                    maxLines: 1,
                    softWrap: false,
                    style: _tabStyle(theme)?.copyWith(
                      color: selected
                          ? color
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  SizedBox(width: 4 + spot.countW),
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
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
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

  /// Opened title row: "Task pool", the board tag and "+ Add".
  Widget _bar(ThemeData theme, {required bool focusAdd}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    widget.t['schedulePool']!,
                    style: theme.textTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                  ),
                ),
                if (widget.boardLabel != null) ...[
                  const SizedBox(width: 8),
                  _boardTag(theme),
                ],
              ],
            ),
          ),
          if (widget.writable)
            TextButton.icon(
              key: const ValueKey('schedule-add'),
              focusNode: focusAdd ? widget.addFocus : null,
              onPressed: widget.addEnabled ? widget.onAdd : null,
              icon: const Icon(Icons.add),
              label: Text(widget.t['schedulePoolAdd']!),
            )
          else
            const SizedBox(width: 48),
        ],
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
      dragAnchorStrategy: _pointer.anchor,
      feedback: PlannerDragFeedback(
        pointer: _pointer,
        size: const Size(220, 56),
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              task.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.35, child: body),
      onDragStarted: () => widget.onDragStarted(task),
      onDragUpdate: (details) {
        _pointer.update(details.globalPosition);
        widget.onDragUpdate(task, details.globalPosition);
      },
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

class _PoolSpot {
  const _PoolSpot({
    required this.quadrant,
    required this.count,
    required this.countW,
    required this.labelW,
    required this.foldDot,
    required this.foldCount,
    required this.openDot,
    required this.openCount,
  });
  final int quadrant;
  final String count;
  final double countW;
  final double labelW;
  final Offset foldDot;
  final Offset foldCount;
  final Offset openDot;
  final Offset openCount;
}
