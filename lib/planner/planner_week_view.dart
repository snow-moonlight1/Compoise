import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../schedule_time.dart';
import '../widgets/schedule_layout.dart';
import 'planner_day_timeline.dart' show plannerPageMargin;
import 'planner_format.dart' show plannerDuration;
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
          final rowHeight = 72 * scale;
          return SingleChildScrollView(
            key: const ValueKey('schedule-scroll'),
            controller: widget.vertical,
            child: Column(
              children: [
                SizedBox(
                  height: headerH,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _header(theme),
                  ),
                ),
                Stack(
                  children: [
                    Positioned(
                      left: plannerPageMargin + 8 + 48 + 19,
                      top: 8,
                      bottom: 8,
                      child: IgnorePointer(
                        child: Container(
                          width: 2,
                          color: theme.colorScheme.outlineVariant,
                        ),
                      ),
                    ),
                    Column(
                      children: [
                        for (final day in widget.days)
                          ConstrainedBox(
                            constraints: BoxConstraints(minHeight: rowHeight),
                            child: _row(day, theme, today),
                          ),
                      ],
                    ),
                  ],
                ),
                SizedBox(height: inset),
              ],
            ),
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

  Widget _row(ScheduleDayLayout day, ThemeData theme, String today) {
    return _DayRow(
      day: day,
      theme: theme,
      scale: widget.scale,
      t: widget.t,
      today: scheduleDateLabel(day.date) == today,
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
      (sum, placement) =>
          sum + placement.slice.endAt - placement.slice.startAt,
    );
    final summary = day.placements.isEmpty
        ? t['scheduleWeekEmpty']!
        : plannerFilled(t['scheduleWeekTimeTotal']!, {
            'duration': plannerDuration(0, total, t),
          });
    final row = Padding(
      key: ValueKey('schedule-day-$label'),
      padding: const EdgeInsets.fromLTRB(plannerPageMargin, 6, plannerPageMargin, 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 48,
                child: InkWell(
                  onTap: onOpenDay,
                  canRequestFocus: false,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      weekday,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.fade,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ),
              ),
              _node(theme),
              const SizedBox(width: 8),
              Expanded(child: _chips(context)),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 48 + 40 + 8, top: 2),
            child: InkWell(
              onTap: onOpenDay,
              canRequestFocus: false,
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
        width: 40,
        height: 40,
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

  /// Labels wrap onto as many lines as the day needs; nothing scrolls sideways
  /// and nothing is folded into "+N".
  Widget _chips(BuildContext context) {
    if (day.placements.isEmpty) return const SizedBox(height: 40);
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 6.0;
        final full = constraints.maxWidth;
        final perRow = math.max(
          1,
          ((full + gap) / (150 * math.min(scale, 1.5) + gap)).floor(),
        );
        final width = (full - (perRow - 1) * gap) / perRow;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final placement in day.placements)
              SizedBox(
                width: width,
                height: math.max(40, 24 * scale + 12),
                child: block(day, placement),
              ),
          ],
        );
      },
    );
  }
}
