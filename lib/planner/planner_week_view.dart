import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../schedule_time.dart';
import '../widgets/schedule_layout.dart';
import 'planner_day_timeline.dart' show plannerPageMargin;
import 'planner_format.dart' show plannerClock, plannerDuration;
import 'planner_labels.dart';
import 'planner_skin.dart';
import 'schedule_drag.dart';

/// Vertical week; it scrolls up and down only. A horizontal drag changes week. A node opens that day.
class PlannerWeekView extends StatefulWidget {
  const PlannerWeekView({
    super.key,
    required this.days,
    required this.today,
    required this.scale,
    required this.vertical,
    required this.t,
    required this.block,
    required this.onOpenDay,
    required this.onWeek,
    required this.dropKey,
    this.onScheduleDrop,
    this.bottomInset = 0,
  });

  final List<ScheduleDayLayout> days;
  final ScheduleCivilDate today;
  final double scale;
  final ScrollController vertical;
  final Map<String, String> t;
  final Widget Function(ScheduleDayLayout day, SchedulePlacement placement)
  block;
  final ValueChanged<ScheduleCivilDate> onOpenDay;
  final ValueChanged<int> onWeek;
  final GlobalKey Function(String dateLabel) dropKey;
  final void Function(ScheduleDragPayload payload, ScheduleCivilDate date)?
  onScheduleDrop;

  /// Pixels covered by the collapsed task pool, so Sunday stays above it.
  final double bottomInset;

  @override
  State<PlannerWeekView> createState() => _PlannerWeekViewState();
}

class _PlannerWeekViewState extends State<PlannerWeekView> {
  double _drag = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = scheduleDateLabel(widget.today);
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (_) => _drag = 0,
      onHorizontalDragUpdate: (details) => _drag += details.delta.dx,
      onHorizontalDragEnd: (_) {
        if (_drag <= -48) widget.onWeek(1);
        if (_drag >= 48) widget.onWeek(-1);
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final inset = math.max(0.0, widget.bottomInset) + 8;
          final lineColor = PlannerSkin.of(context).hairline(theme);
          // Circles are one slot apart, the first half a slot under the top
          // gap. A day with many labels grows its own row and the page scrolls.
          final slot = plannerWeekSlot(constraints.maxHeight, 0, inset);
          return CustomScrollView(
            key: const ValueKey('schedule-scroll'),
            controller: widget.vertical,
            slivers: [
              SliverToBoxAdapter(
                child: Column(
                  key: const ValueKey('schedule-week-rows'),
                  children: [
                    // The line starts at the first circle's centre: nothing
                    // runs above it. It continues below the last circle to
                    // the bottom of the page.
                    const SizedBox(height: plannerWeekTopGap),
                    for (var i = 0; i < widget.days.length; i++)
                      _row(widget.days[i], theme, today, slot, first: i == 0),
                    CustomPaint(
                      key: const ValueKey('schedule-week-axis-end'),
                      painter: PlannerWeekAxisPainter(
                        x: plannerWeekAxisX(),
                        from: 0,
                        to: null,
                        color: lineColor,
                      ),
                      child: SizedBox(
                        width: double.infinity,
                        height: slot / 2 + inset,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _row(
    ScheduleDayLayout day,
    ThemeData theme,
    String today,
    double minHeight, {
    required bool first,
  }) {
    return _DayRow(
      day: day,
      theme: theme,
      scale: widget.scale,
      t: widget.t,
      today: scheduleDateLabel(day.date) == today,
      minHeight: minHeight,
      first: first,
      block: widget.block,
      onOpenDay: () => widget.onOpenDay(day.date),
      dropKey: widget.dropKey(scheduleDateLabel(day.date)),
      onScheduleDrop: widget.onScheduleDrop,
    );
  }
}

class _DayRow extends StatelessWidget {
  const _DayRow({
    required this.day,
    required this.theme,
    required this.scale,
    required this.t,
    required this.today,
    required this.minHeight,
    required this.first,
    required this.block,
    required this.onOpenDay,
    required this.dropKey,
    this.onScheduleDrop,
  });

  final ScheduleDayLayout day;
  final ThemeData theme;
  final double scale;
  final Map<String, String> t;
  final bool today;
  final double minHeight;
  final bool first;
  final Widget Function(ScheduleDayLayout day, SchedulePlacement placement)
  block;
  final VoidCallback onOpenDay;
  final GlobalKey dropKey;
  final void Function(ScheduleDragPayload payload, ScheduleCivilDate date)?
  onScheduleDrop;

  @override
  Widget build(BuildContext context) {
    final label = scheduleDateLabel(day.date);
    final weekday =
        t['scheduleWeekday${DateTime.utc(day.date.year, day.date.month, day.date.day).weekday}']!;
    final total = day.placements.fold<int>(
      0,
      (sum, placement) => sum + placement.slice.endAt - placement.slice.startAt,
    );
    final summary = day.placements.isEmpty
        ? t['scheduleWeekEmpty']!
        : plannerFilled(t['scheduleWeekTimeTotal']!, {
            'duration': plannerDuration(0, total, t),
          });
    final content = Padding(
      key: ValueKey('schedule-day-$label'),
      padding: const EdgeInsets.fromLTRB(
        plannerPageMargin,
        plannerWeekRowPad,
        plannerPageMargin,
        plannerWeekRowPad,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: plannerWeekdayWidth,
            child: InkWell(
              onTap: onOpenDay,
              canRequestFocus: false,
              child: Text(
                weekday,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.fade,
                style: theme.textTheme.bodySmall,
              ),
            ),
          ),
          _node(context, theme),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _chips(context),
                InkWell(
                  onTap: onOpenDay,
                  canRequestFocus: false,
                  child: Padding(
                    padding: EdgeInsets.only(
                      top: day.placements.isEmpty ? 0 : 4,
                    ),
                    child: Text(
                      summary,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    // Rows are at least one slot tall and keep the circle in the middle of the
    // row, so with little content the circles fall on the eighths.
    final row = ConstrainedBox(
      constraints: BoxConstraints(minHeight: minHeight),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                key: ValueKey('schedule-week-axis-$label'),
                painter: PlannerWeekAxisPainter(
                  x: plannerWeekAxisX(),
                  from: 0,
                  fromCentre: first,
                  to: null,
                  color: PlannerSkin.of(context).hairline(theme),
                ),
              ),
            ),
          ),
          content,
        ],
      ),
    );
    if (onScheduleDrop == null) return row;
    return KeyedSubtree(
      key: dropKey,
      child: DragTarget<ScheduleDragPayload>(
        key: ValueKey('schedule-drop-$label'),
        onWillAcceptWithDetails: (_) => true,
        onAcceptWithDetails: (details) =>
            onScheduleDrop!(details.data, day.date),
        // The day under the finger is tinted: the row is the drop target, and
        // the tint reads even with the preview up-left of the finger.
        builder: (context, candidates, rejected) => DecoratedBox(
          // Always present, so the row (and a label being dragged inside it)
          // keeps its place in the tree when the tint switches on.
          decoration: BoxDecoration(
            color: candidates.isEmpty
                ? null
                : theme.colorScheme.primary.withValues(alpha: 0.12),
          ),
          child: row,
        ),
      ),
    );
  }

  Widget _node(BuildContext context, ThemeData theme) {
    final skin = PlannerSkin.of(context);
    final color = today
        ? theme.colorScheme.primary
        : theme.colorScheme.surfaceContainerHighest;
    // Neumorphic: today is sunk with an accent number, the rest are raised.
    final sunk = skin.neu != null && today;
    final ink = sunk
        ? theme.colorScheme.primary
        : today
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.onSurface;
    final base = BoxDecoration(color: color, shape: BoxShape.circle);
    return InkWell(
      onTap: onOpenDay,
      canRequestFocus: false,
      customBorder: const CircleBorder(),
      child: Container(
        key: ValueKey('schedule-week-node-${scheduleDateLabel(day.date)}'),
        width: plannerNodeSize,
        height: plannerNodeSize,
        alignment: Alignment.center,
        decoration: skin.plain
            ? base
            : skin.surface(base, raised: !sunk, selected: today),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            '${day.date.day}',
            style: theme.textTheme.titleMedium?.copyWith(color: ink),
          ),
        ),
      ),
    );
  }

  /// Labels are as wide as their text (up to the row) and sit side by side;
  /// a label that does not fit the line wraps to the next one.
  Widget _chips(BuildContext context) {
    if (day.placements.isEmpty) return const SizedBox.shrink();
    final style = theme.textTheme.labelMedium;
    final scaler = MediaQuery.textScalerOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final full = constraints.maxWidth;
        return Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final placement in day.placements)
              SizedBox(
                width: plannerChipWidth(
                  '${plannerClock(placement.slice.startAt, day.timeZoneId)} '
                  '${placement.entry.title}',
                  style,
                  scaler,
                  full,
                ),
                height: math.max(40, 24 * scale + 12),
                child: block(day, placement),
              ),
          ],
        );
      },
    );
  }
}

/// Text width plus the block's bar, border and padding, capped at [max].
double plannerChipWidth(
  String text,
  TextStyle? style,
  TextScaler scaler,
  double max,
) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    textScaler: scaler,
    maxLines: 1,
  )..layout();
  final width = painter.width.ceilToDouble() + 4 + 2 + 12 + 2;
  painter.dispose();
  return math.min(max, width);
}

const plannerWeekdayWidth = 48.0;
const plannerNodeSize = 40.0;
const plannerWeekRowPad = 6.0;

/// Horizontal centre of every day circle; the axis line uses the same value.
double plannerWeekAxisX() =>
    plannerPageMargin + plannerWeekdayWidth + plannerNodeSize / 2;

/// Height of one eighth of the axis: the visible week area under the header,
/// above the pool bar.
///
/// The first circle sits half a slot under [plannerWeekTopGap]; seven circles
/// are one slot apart; half a slot of line is left under the last one.
double plannerWeekSlot(double viewport, double header, double inset) =>
    math.max(0.0, viewport - header - inset - plannerWeekTopGap) / 7.5;

/// Space between the header and the first row.
const plannerWeekTopGap = 8.0;

/// Vertical hairline at [x] from [from] down to [to] (the bottom when null).
class PlannerWeekAxisPainter extends CustomPainter {
  const PlannerWeekAxisPainter({
    required this.x,
    required this.from,
    this.fromCentre = false,
    required this.to,
    required this.color,
  });

  final double x;
  final double from;

  /// Start at the vertical middle of the painted box (the first circle).
  final bool fromCentre;
  final double? to;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(
      Offset(x, fromCentre ? size.height / 2 : from),
      Offset(x, to ?? size.height),
      Paint()
        ..color = color
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(PlannerWeekAxisPainter old) =>
      old.x != x ||
      old.from != from ||
      old.fromCentre != fromCentre ||
      old.to != to ||
      old.color != color;
}
