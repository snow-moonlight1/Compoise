import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../schedule_time.dart';
import '../widgets/schedule_layout.dart';
import 'planner_day_timeline.dart' show plannerPageMargin;
import 'planner_format.dart' show plannerClock, plannerDuration;
import 'planner_labels.dart';
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
          final scale = widget.scale;
          final headerH = 56 * scale;
          final inset = math.max(0.0, widget.bottomInset) + 8;
          final lineColor = theme.colorScheme.outlineVariant;
          // Seven circles split the axis into eight equal parts: circle i sits
          // at i/8 of the visible height. A day with many labels grows its
          // own row and the page scrolls instead.
          final slot = plannerWeekSlot(constraints.maxHeight, headerH, inset);
          return CustomScrollView(
            key: const ValueKey('schedule-scroll'),
            controller: widget.vertical,
            slivers: [
              SliverToBoxAdapter(
                child: SizedBox(
                  height: headerH,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _header(theme),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          key: const ValueKey('schedule-week-axis'),
                          painter: PlannerWeekAxisPainter(
                            x: plannerWeekAxisX(),
                            from: 0,
                            to: null,
                            color: lineColor,
                          ),
                        ),
                      ),
                    ),
                    Column(
                      key: const ValueKey('schedule-week-rows'),
                      children: [
                        SizedBox(height: slot / 2),
                        for (var i = 0; i < widget.days.length; i++)
                          _row(widget.days[i], theme, today, slot),
                        SizedBox(height: slot / 2 + inset),
                      ],
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

  Widget _header(ThemeData theme) {
    final number = widget.days.isEmpty
        ? 1
        : plannerIsoWeek(widget.days.first.date);
    return Padding(
      padding: const EdgeInsets.fromLTRB(plannerPageMargin, 4, 16, 8),
      child: Text(
        plannerFilled(widget.t['scheduleWeekNumber']!, {'n': '$number'}),
        style: theme.textTheme.titleSmall,
      ),
    );
  }

  Widget _row(
    ScheduleDayLayout day,
    ThemeData theme,
    String today,
    double minHeight,
  ) {
    return _DayRow(
      day: day,
      theme: theme,
      scale: widget.scale,
      t: widget.t,
      today: scheduleDateLabel(day.date) == today,
      minHeight: minHeight,
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
          _node(theme),
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
      child: Center(heightFactor: 1, child: content),
    );
    if (onScheduleDrop == null) return row;
    return KeyedSubtree(
      key: dropKey,
      child: DragTarget<ScheduleDragPayload>(
        key: ValueKey('schedule-drop-$label'),
        onWillAcceptWithDetails: (_) => true,
        onAcceptWithDetails: (details) =>
            onScheduleDrop!(details.data, day.date),
        builder: (context, candidates, rejected) => row,
      ),
    );
  }

  Widget _node(ThemeData theme) {
    final color = today
        ? theme.colorScheme.primary
        : theme.colorScheme.surfaceContainerHighest;
    final ink = today
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.onSurface;
    return InkWell(
      onTap: onOpenDay,
      canRequestFocus: false,
      customBorder: const CircleBorder(),
      child: Container(
        key: ValueKey('schedule-week-node-${scheduleDateLabel(day.date)}'),
        width: plannerNodeSize,
        height: plannerNodeSize,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
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
double plannerWeekSlot(double viewport, double header, double inset) =>
    math.max(0.0, viewport - header - inset) / 8;

/// Vertical hairline at [x] from [from] down to [to] (the bottom when null).
class PlannerWeekAxisPainter extends CustomPainter {
  const PlannerWeekAxisPainter({
    required this.x,
    required this.from,
    required this.to,
    required this.color,
  });

  final double x;
  final double from;
  final double? to;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(
      Offset(x, from),
      Offset(x, to ?? size.height),
      Paint()
        ..color = color
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(PlannerWeekAxisPainter old) =>
      old.x != x || old.from != from || old.to != to || old.color != color;
}
