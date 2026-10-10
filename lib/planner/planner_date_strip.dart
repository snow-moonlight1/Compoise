import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models.dart';
import '../schedule_time.dart';
import '../widgets/schedule_layout.dart';
import 'planner_labels.dart';

/// Monday-to-Sunday numbers for the day view. A horizontal drag moves a week.
class PlannerDateStrip extends StatefulWidget {
  const PlannerDateStrip({
    super.key,
    required this.monday,
    required this.selected,
    required this.marked,
    required this.t,
    required this.language,
    required this.onSelect,
    required this.onWeek,
  });

  final ScheduleCivilDate monday;
  final ScheduleCivilDate selected;
  final Set<String> marked;
  final Map<String, String> t;
  final Language language;
  final ValueChanged<ScheduleCivilDate> onSelect;
  final ValueChanged<int> onWeek;

  @override
  State<PlannerDateStrip> createState() => _PlannerDateStripState();
}

class _PlannerDateStripState extends State<PlannerDateStrip> {
  double _drag = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = scheduleDateLabel(widget.selected);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: (_) => _drag = 0,
      onHorizontalDragUpdate: (details) => _drag += details.delta.dx,
      onHorizontalDragEnd: (_) {
        if (_drag <= -48) widget.onWeek(1);
        if (_drag >= 48) widget.onWeek(-1);
      },
      child: SizedBox(
        height:
            82 *
            math.max(1.0, MediaQuery.textScalerOf(context).scale(14) / 14),
        child: Row(
          children: [
            for (var index = 0; index < 7; index++)
              Expanded(child: _day(theme, index, selected)),
          ],
        ),
      ),
    );
  }

  Widget _day(ThemeData theme, int index, String selectedLabel) {
    final date = widget.monday.addDays(index);
    final label = scheduleDateLabel(date);
    final selected = label == selectedLabel;
    final marked = widget.marked.contains(label);
    final color = selected
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.onSurface;
    final weekday = plannerWeekdayMark(widget.t, widget.language, index + 1);
    return InkWell(
      onTap: () => widget.onSelect(date),
      canRequestFocus: false,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            weekday,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.fade,
            style: theme.textTheme.labelSmall?.copyWith(
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? theme.colorScheme.primary : null,
                shape: BoxShape.circle,
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '${date.day}',
                  style: theme.textTheme.titleMedium?.copyWith(color: color),
                ),
              ),
            ),
          ),
          const SizedBox(height: 2),
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: marked ? theme.colorScheme.primary : const Color(0x00000000),
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }
}
