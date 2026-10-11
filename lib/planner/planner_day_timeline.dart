import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../widgets/schedule_layout.dart';
import 'planner_block.dart' show plannerHandleReach;

/// Side margin shared by the strip, the grid and the week list.
const plannerPageMargin = 12.0;

/// Pointer Y on the day grid, clamped onto the axis. The grid is taller than
/// the axis so the last items stay reachable; a drop in that padding still
/// belongs to the last slot instead of being swallowed.
double _dropY(RenderBox box, Offset global, double axisHeight) {
  final y = box.globalToLocal(global).dy;
  final limit = math.max(0.0, axisHeight - 1);
  if (y < 0) return 0;
  if (y > limit) return limit;
  return y;
}

/// A snapped pool-drag preview painted on the day grid.
class PlannerHover {
  const PlannerHover({
    required this.top,
    required this.height,
    required this.label,
    this.hint = '',
  });

  final double top;
  final double height;
  final String label;
  final String hint;
}

/// Full-width day grid. Parallel blocks share the width; only vertical scroll.
class PlannerDayTimeline extends StatelessWidget {
  const PlannerDayTimeline({
    super.key,
    required this.day,
    required this.scale,
    required this.vertical,
    required this.block,
    required this.nowLabel,
    required this.hover,
    this.onGridTap,
    this.selectedId,
    this.emptyLabel,
    this.onPoolMove,
    this.onPoolAccept,
    this.now,
  });

  final String? emptyLabel;
  final ScheduleDayLayout day;
  final double scale;
  final ScrollController vertical;
  final Widget Function(SchedulePlacement placement) block;
  final String nowLabel;
  final ValueListenable<PlannerHover?> hover;
  final ValueChanged<double>? onGridTap;
  final String? selectedId;
  final void Function(double dy)? onPoolMove;
  final void Function(String taskId, double dy)? onPoolAccept;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final axisWidth = 44.0 * scale;
    final dateLabel = scheduleDateLabel(day.date);
    return LayoutBuilder(
      builder: (context, constraints) {
        // Same side margin as the rest of the page; lanes never scroll sideways.
        final laneViewport = math.max(
          0.0,
          constraints.maxWidth - axisWidth - 2 * plannerPageMargin,
        );
        final onPoolMove = this.onPoolMove;
        final onPoolAccept = this.onPoolAccept;
        final gridCore = _Grid(
          day: day,
          theme: theme,
          axisWidth: axisWidth,
          laneViewport: laneViewport,
          nowLabel: nowLabel,
          now: now,
          hover: hover,
          onGridTap: onGridTap,
          block: block,
          selectedId: selectedId,
          emptyLabel: emptyLabel,
        );
        final grid = Padding(
          padding: const EdgeInsets.symmetric(horizontal: plannerPageMargin),
          child: gridCore,
        );
        return KeyedSubtree(
          key: ValueKey('schedule-day-$dateLabel'),
          child: SingleChildScrollView(
            key: const ValueKey('schedule-scroll'),
            controller: vertical,
            child: Builder(
              builder: (dropContext) {
                if (onPoolAccept == null) {
                  return grid;
                }
                return DragTarget<Object>(
                  key: ValueKey('schedule-drop-$dateLabel'),
                  onWillAcceptWithDetails: (details) => details.data is String,
                  onMove: (details) {
                    final move = onPoolMove;
                    if (move == null || details.data is! String) return;
                    final box = dropContext.findRenderObject() as RenderBox?;
                    if (box == null || !box.attached || !box.hasSize) return;
                    move(_dropY(box, details.offset, day.axisHeight));
                  },
                  onLeave: (_) => onPoolMove?.call(-1),
                  onAcceptWithDetails: (details) {
                    final box = dropContext.findRenderObject() as RenderBox?;
                    if (box == null || !box.attached || !box.hasSize) return;
                    final y = _dropY(box, details.offset, day.axisHeight);
                    final data = details.data;
                    if (data is String) {
                      onPoolAccept.call(data, y);
                    }
                  },
                  builder: (context, candidates, rejected) => grid,
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({
    required this.day,
    required this.theme,
    required this.axisWidth,
    required this.laneViewport,
    required this.nowLabel,
    required this.block,
    required this.hover,
    this.onGridTap,
    this.selectedId,
    this.emptyLabel,
    this.now,
  });

  final String? selectedId;
  final String? emptyLabel;
  final ScheduleDayLayout day;
  final ThemeData theme;
  final double axisWidth;
  final double laneViewport;
  final String nowLabel;
  final Widget Function(SchedulePlacement placement) block;
  final ValueChanged<double>? onGridTap;
  final ValueListenable<PlannerHover?> hover;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final nowTop = _nowTop();
    return SizedBox(
      height: day.height,
      child: Stack(
        children: [
          for (final tick in day.ticks) ...[
            Positioned(
              top: tick.top,
              left: axisWidth,
              right: 0,
              child: Divider(
                height: 1,
                color: theme.colorScheme.outlineVariant,
              ),
            ),
            if (tick.instant != day.window.endAt &&
                tick.top + day.pixelsPerHour / 2 < day.axisHeight)
              Positioned(
                top: tick.top + day.pixelsPerHour / 2,
                left: axisWidth,
                right: 0,
                child: Divider(
                  height: 1,
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.4,
                  ),
                ),
              ),
          ],
          if (nowTop != null)
            Positioned(
              top: nowTop,
              left: axisWidth,
              right: 0,
              child: Semantics(
                label:
                    '$nowLabel ${scheduleAxisLabel(now!.millisecondsSinceEpoch, day.timeZoneId)}',
                child: Container(height: 2, color: theme.colorScheme.error),
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: axisWidth,
                height: day.height,
                child: Stack(
                  children: [
                    if (nowTop != null)
                      Positioned(
                        top: math.max(0, nowTop - 10),
                        left: 0,
                        width: axisWidth,
                        child: ExcludeSemantics(
                          child: Text(
                            scheduleAxisLabel(
                              now!.millisecondsSinceEpoch,
                              day.timeZoneId,
                            ),
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.fade,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.error,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    for (final tick in day.ticks)
                      if (tick.instant != day.window.endAt &&
                          (nowTop == null || (tick.top - nowTop).abs() > 14))
                        Positioned(
                          top: math.max(0, tick.top - 8),
                          left: 0,
                          width: axisWidth,
                          child: Semantics(
                            label: tick.label,
                            child: ExcludeSemantics(
                              child: Text(
                                scheduleAxisLabel(tick.instant, day.timeZoneId),
                                maxLines: 1,
                                softWrap: false,
                                overflow: TextOverflow.fade,
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                          ),
                        ),
                  ],
                ),
              ),
              Expanded(
                child: SizedBox(
                  width: laneViewport,
                  height: day.height,
                  child: Stack(
                    children: [
                      if (onGridTap != null)
                        Positioned.fill(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTapUp: (details) {
                              if (details.localPosition.dy < 0 ||
                                  details.localPosition.dy >= day.axisHeight) {
                                return;
                              }
                              onGridTap!(details.localPosition.dy);
                            },
                          ),
                        ),
                      for (final placement in [
                        ...day.placements.where(
                          (p) => p.entry.item.id != selectedId,
                        ),
                        ...day.placements.where(
                          (p) => p.entry.item.id == selectedId,
                        ),
                      ])
                        Positioned(
                          top:
                              placement.top -
                              (placement.entry.item.id == selectedId
                                  ? plannerHandleReach
                                  : 0),
                          left:
                              placement.lane *
                                  (laneViewport / placement.lanes) +
                              2,
                          width: math.max(
                            0,
                            laneViewport / placement.lanes - 4,
                          ),
                          height:
                              math.max(0, placement.height - 2) +
                              (placement.entry.item.id == selectedId
                                  ? 2 * plannerHandleReach
                                  : 0),
                          child: block(placement),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (emptyLabel != null && day.placements.isEmpty)
            Positioned(
              top: math.min(day.height / 3, 240),
              left: axisWidth + 16,
              right: 16,
              child: IgnorePointer(
                child: Text(
                  emptyLabel!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ListenableBuilder(
            listenable: hover,
            builder: (context, _) {
              final preview = hover.value;
              if (preview == null) return const SizedBox.shrink();
              return Stack(
                children: [
                  Positioned(
                    top: preview.top,
                    left: axisWidth + 4,
                    right: 8,
                    height: preview.height,
                    child: IgnorePointer(
                      child: _Placeholder(
                        label: preview.label,
                        hint: preview.hint,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  double? _nowTop() {
    final instant = now;
    if (instant == null) return null;
    final ms = instant.millisecondsSinceEpoch;
    if (ms < day.window.startAt || ms >= day.window.endAt) return null;
    return (ms - day.window.startAt) /
        Duration.millisecondsPerHour *
        day.pixelsPerHour;
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.label, this.hint = ''});

  final String label;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CustomPaint(
      painter: _DashPainter(theme.colorScheme.primary),
      child: Container(
        alignment: Alignment.topLeft,
        padding: const EdgeInsets.all(6),
        color: theme.colorScheme.primary.withValues(alpha: 0.08),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.labelMedium),
            if (hint.isNotEmpty) Text(hint, style: theme.textTheme.labelSmall),
          ],
        ),
      ),
    );
  }
}

class _DashPainter extends CustomPainter {
  const _DashPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(8)),
      );
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(metric.extractPath(distance, distance + 5), paint);
        distance += 9;
      }
    }
  }

  @override
  bool shouldRepaint(_DashPainter oldDelegate) => oldDelegate.color != color;
}
