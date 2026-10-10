import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../schedule_time.dart';
import '../widgets/schedule_layout.dart';
import 'planner_labels.dart';
import 'schedule_drag.dart';

/// Vertical week. A horizontal drag changes week. A node opens that day.
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
      child: SingleChildScrollView(
        key: const ValueKey('schedule-scroll'),
        controller: widget.vertical,
        child: Column(
          children: [
            _header(theme),
            Stack(
              children: [
                Positioned(
                  left: 75,
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
                    for (final day in widget.days) _row(day, theme, today),
                  ],
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Text(
                widget.t['scheduleWeekHint']!,
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(ThemeData theme) {
    final ids = <String>{};
    final done = <String>{};
    for (final day in widget.days) {
      for (final placement in day.placements) {
        ids.add(placement.entry.item.id);
        if (placement.entry.completed) done.add(placement.entry.item.id);
      }
    }
    final number = widget.days.isEmpty
        ? 1
        : plannerIsoWeek(widget.days.first.date);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            Text(
              plannerFilled(widget.t['scheduleWeekNumber']!, {'n': '$number'}),
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(width: 16),
            Text(
              plannerFilled(widget.t['scheduleWeekTotal']!, {
                'n': '${ids.length}',
                'done': '${done.length}',
              }),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
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
    final hours =
        day.placements.fold<int>(
          0,
          (sum, placement) =>
              sum + placement.slice.endAt - placement.slice.startAt,
        ) /
        Duration.millisecondsPerHour;
    final summary = plannerWeekSummary(
      t['scheduleWeekItems']!,
      day.placements.length,
      hours,
      t,
    );
    final row = Padding(
      key: ValueKey('schedule-day-$label'),
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      child: Column(
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
            padding: const EdgeInsets.only(left: 92, top: 2),
            child: InkWell(
              onTap: onOpenDay,
              canRequestFocus: false,
              child: Text(summary, style: theme.textTheme.bodySmall),
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

  Widget _chips(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final fit = math.max(1, (width / (140 * scale)).floor());
    final hidden = math.max(0, day.placements.length - fit);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: math.max(40, 28 * scale + 12),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final placement in day.placements)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: SizedBox(
                      width: math.max(108, 120 * math.min(scale, 2)),
                      height: math.max(36, 24 * scale + 8),
                      child: block(day, placement),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (hidden > 0)
          InkWell(
            onTap: onOpenDay,
            canRequestFocus: false,
            child: Text(
              plannerCounted(t['scheduleMoreCount']!, hidden),
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
      ],
    );
  }
}
