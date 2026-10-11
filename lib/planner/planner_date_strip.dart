import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models.dart';
import '../schedule_time.dart';
import '../widgets/schedule_layout.dart';
import 'planner_labels.dart';

/// Monday-to-Sunday numbers for the day view. The weeks sit in a page view that
/// follows the finger and snaps to whole weeks: a small nudge settles back, a
/// real swipe moves one week. Dots mark days that have items, in every week.
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

  /// Labels (`yyyy-mm-dd`) of every day with items, in any week.
  final Set<String> marked;
  final Map<String, String> t;
  final Language language;
  final ValueChanged<ScheduleCivilDate> onSelect;

  /// +1 / -1 when the strip settles on another week.
  final ValueChanged<int> onWeek;

  @override
  State<PlannerDateStrip> createState() => _PlannerDateStripState();
}

class _PlannerDateStripState extends State<PlannerDateStrip> {
  static const _origin = 5000;
  late final ScheduleCivilDate _base = widget.monday;
  late final PageController _pages = PageController(initialPage: _origin);
  int _page = _origin;
  bool _moving = false;

  int _pageOf(ScheduleCivilDate monday) {
    final a = DateTime.utc(_base.year, _base.month, _base.day);
    final b = DateTime.utc(monday.year, monday.month, monday.day);
    return _origin + b.difference(a).inDays ~/ 7;
  }

  @override
  void didUpdateWidget(PlannerDateStrip old) {
    super.didUpdateWidget(old);
    final target = _pageOf(widget.monday);
    if (target == _page) return;
    // The page changed for another reason (today, picker, a swipe on the day).
    _page = target;
    if (!_pages.hasClients) return;
    if ((target - (_pages.page ?? target)).abs() <= 1.01 &&
        !MediaQuery.disableAnimationsOf(context)) {
      _moving = true;
      _pages
          .animateToPage(
            target,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
          )
          .whenComplete(() => _moving = false);
    } else {
      _pages.jumpToPage(target);
    }
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = scheduleDateLabel(widget.selected);
    return SizedBox(
      height:
          82 * math.max(1.0, MediaQuery.textScalerOf(context).scale(14) / 14),
      child: PageView.builder(
        key: const ValueKey('schedule-strip'),
        controller: _pages,
        onPageChanged: (page) {
          if (_moving || page == _page) return;
          final delta = page - _page;
          _page = page;
          widget.onWeek(delta.sign);
        },
        itemBuilder: (context, page) {
          final monday = _base.addDays(7 * (page - _origin));
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                for (var index = 0; index < 7; index++)
                  Expanded(child: _day(theme, monday, index, selected)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _day(
    ThemeData theme,
    ScheduleCivilDate monday,
    int index,
    String selectedLabel,
  ) {
    final date = monday.addDays(index);
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
              color: marked
                  ? theme.colorScheme.primary
                  : const Color(0x00000000),
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }
}
