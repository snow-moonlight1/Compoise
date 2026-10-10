import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../widgets/schedule_layout.dart';
import 'planner_labels.dart';
import 'schedule_drag.dart';

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

/// Full-width day grid. Horizontal movement scrolls parallel lanes only.
class PlannerDayTimeline extends StatelessWidget {
  const PlannerDayTimeline({
    super.key,
    required this.day,
    required this.scale,
    required this.vertical,
    required this.horizontal,
    required this.block,
    required this.moreTemplate,
    required this.nowLabel,
    required this.hover,
    this.onGridTap,
    this.onScheduleDrop,
    this.onPoolMove,
    this.onPoolAccept,
    this.now,
  });

  final ScheduleDayLayout day;
  final double scale;
  final ScrollController vertical;
  final ScrollController horizontal;
  final Widget Function(SchedulePlacement placement) block;
  final String moreTemplate;
  final String nowLabel;
  final ValueListenable<PlannerHover?> hover;
  final ValueChanged<double>? onGridTap;
  final void Function(ScheduleDragPayload payload, double dy)? onScheduleDrop;
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
        const minLane = 96.0;
        final laneViewport = math.max(0.0, constraints.maxWidth - axisWidth);
        final fits = day.laneCount * minLane * scale <= laneViewport;
        final laneWidth = fits
            ? (day.laneCount == 0 ? laneViewport : laneViewport / day.laneCount)
            : minLane * scale;
        final contentWidth = math.max(laneViewport, laneWidth * day.laneCount);
        final onPoolMove = this.onPoolMove;
        final onPoolAccept = this.onPoolAccept;
        final grid = _Grid(
          day: day,
          theme: theme,
          axisWidth: axisWidth,
          laneWidth: laneWidth,
          contentWidth: contentWidth,
          laneViewport: laneViewport,
          fits: fits,
          moreTemplate: moreTemplate,
          nowLabel: nowLabel,
          now: now,
          hover: hover,
          horizontal: horizontal,
          onGridTap: onGridTap,
          block: block,
        );
        return KeyedSubtree(
          key: ValueKey('schedule-day-$dateLabel'),
          child: SingleChildScrollView(
            key: const ValueKey('schedule-scroll'),
            controller: vertical,
            child: Builder(
              builder: (dropContext) {
                if (onScheduleDrop == null && onPoolAccept == null) {
                  return grid;
                }
                return DragTarget<Object>(
                  key: ValueKey('schedule-drop-$dateLabel'),
                  onWillAcceptWithDetails: (details) =>
                      details.data is ScheduleDragPayload ||
                      details.data is String,
                  onMove: (details) {
                    final move = onPoolMove;
                    if (move == null || details.data is! String) return;
                    final box = dropContext.findRenderObject() as RenderBox?;
                    if (box == null || !box.attached || !box.hasSize) return;
                    move(_dropY(box, details.offset, day.axisHeight));
                  },
                  onLeave: (_) => onPoolMove?.call(-1),
                  onAcceptWithDetails: (details) {
                    final box =
                        dropContext.findRenderObject() as RenderBox?;
                    if (box == null || !box.attached || !box.hasSize) return;
                    final y = _dropY(box, details.offset, day.axisHeight);
                    final data = details.data;
                    if (data is ScheduleDragPayload) {
                      onScheduleDrop?.call(data, y);
                    } else if (data is String) {
                      onPoolAccept?.call(data, y);
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
    required this.laneWidth,
    required this.contentWidth,
    required this.laneViewport,
    required this.fits,
    required this.moreTemplate,
    required this.nowLabel,
    required this.horizontal,
    required this.block,
    required this.hover,
    this.onGridTap,
    this.now,
  });

  final ScheduleDayLayout day;
  final ThemeData theme;
  final double axisWidth;
  final double laneWidth;
  final double contentWidth;
  final double laneViewport;
  final bool fits;
  final String moreTemplate;
  final String nowLabel;
  final ScrollController horizontal;
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
                                  scheduleAxisLabel(
                                    tick.instant,
                                    day.timeZoneId,
                                  ),
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
                  child: SingleChildScrollView(
                    key: const ValueKey('schedule-horizontal'),
                    controller: horizontal,
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: contentWidth,
                      height: day.height,
                      child: Stack(
                        children: [
                          if (onGridTap != null)
                            Positioned.fill(
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTapUp: (details) {
                                  if (details.localPosition.dy < 0 ||
                                      details.localPosition.dy >=
                                          day.axisHeight) {
                                    return;
                                  }
                                  onGridTap!(details.localPosition.dy);
                                },
                              ),
                            ),
                          for (final placement in day.placements)
                            Positioned(
                              top: placement.top,
                              left: placement.lane * laneWidth + 2,
                              width: math.max(0, laneWidth - 4),
                              height: math.max(0, placement.height - 2),
                              child: block(placement),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
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
            ListenableBuilder(
              listenable: horizontal,
              builder: (context, _) {
                final scroll = horizontal.positions.length == 1
                    ? horizontal.offset
                    : 0.0;
                final hidden = fits
                    ? const <SchedulePlacement>[]
                    : day.placements
                          .where(
                            (placement) =>
                                placement.lane * laneWidth + 8 >=
                                scroll + laneViewport,
                          )
                          .toList();
                if (hidden.isEmpty) return const SizedBox.shrink();
                hidden.sort((a, b) => a.top.compareTo(b.top));
                final anchor = hidden.first;
                return Stack(
                  children: [
                    Positioned(
                      top: 0,
                      bottom: 0,
                      right: 0,
                      width: 28,
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                theme.scaffoldBackgroundColor.withValues(
                                  alpha: 0,
                                ),
                                theme.scaffoldBackgroundColor,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: anchor.top.clamp(0, math.max(0, day.height - 36)),
                      right: 4,
                      child: ExcludeFocus(
                        child: TextButton(
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: const Size(0, 32),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          backgroundColor: theme.colorScheme.surface,
                        ),
                        onPressed: () {
                          if (horizontal.positions.length != 1) return;
                          final target = (anchor.lane * laneWidth).clamp(
                            0.0,
                            horizontal.position.maxScrollExtent,
                          );
                          horizontal.animateTo(
                            target,
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeOut,
                          );
                        },
                        child: Text(plannerCounted(moreTemplate, hidden.length)),
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
            if (hint.isNotEmpty)
              Text(hint, style: theme.textTheme.labelSmall),
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
