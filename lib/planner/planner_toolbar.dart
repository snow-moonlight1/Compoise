import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'planner_day_timeline.dart' show plannerPageMargin;
import 'planner_view.dart';

/// One-row planner chrome. Zone and board filter live in the menu.
///
/// Previous and next stay beside the date so keyboard tests can still reach
/// them, but they are narrow enough that day, week, and today stay on screen.
class PlannerToolbar extends StatelessWidget {
  const PlannerToolbar({
    super.key,
    required this.t,
    required this.dateLabel,
    required this.view,
    required this.canPrevious,
    required this.canNext,
    required this.zoneLabel,
    required this.filterLabel,
    required this.onPrevious,
    required this.onNext,
    required this.onPickDate,
    required this.onView,
    required this.onFilter,
    this.onZone,
    this.onBack,
    this.onGuide,
    this.onToday,
    this.todayInView = true,
  });

  final Map<String, String> t;
  final String dateLabel;
  final PlannerView view;
  final bool canPrevious;
  final bool canNext;
  final String zoneLabel;
  final String filterLabel;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback onPickDate;

  /// Only when the viewed day or week does not contain today.
  final ValueChanged<PlannerView> onView;
  final VoidCallback onFilter;
  final VoidCallback? onZone;

  /// Back to the task board; null when the page is not pushed over it.
  final VoidCallback? onBack;
  final VoidCallback? onGuide;

  /// Desktop only: a "Today" button in the bar (phones use the round 今
  /// button). Null hides it; disabled while today is already in view.
  final VoidCallback? onToday;
  final bool todayInView;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final previousTip =
        t[view == PlannerView.day
            ? 'schedulePreviousDay'
            : 'schedulePreviousWeek']!;
    final nextTip =
        t[view == PlannerView.day ? 'scheduleNextDay' : 'scheduleNextWeek']!;
    final scale = math.max(
      1.0,
      MediaQuery.textScalerOf(context).scale(14) / 14,
    );
    return Material(
      color: theme.scaffoldBackgroundColor,
      child: SizedBox(
        height: math.min(56 * scale, 72),
        width: double.infinity,
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Arrows only where there is room; on a phone a sideways swipe on
            // the day, the date strip and the date picker move around.
            final arrows =
                constraints.maxWidth >= 480 || onToday != null;
            final shrink = scale > 1.3 || constraints.maxWidth < 360;
            final row = Row(
              mainAxisSize: shrink ? MainAxisSize.min : MainAxisSize.max,
              children: [
                const SizedBox(width: plannerPageMargin - 8),
                if (onBack != null)
                  IconButton(
                    key: const ValueKey('schedule-back'),
                    tooltip: t['scheduleNavTasks'],
                    visualDensity: VisualDensity.compact,
                    onPressed: onBack,
                    icon: const Icon(Icons.arrow_back),
                  ),
                PopupMenuButton<String>(
                  key: const ValueKey('schedule-menu'),
                  tooltip: t['scheduleMenu'],
                  icon: const Icon(Icons.menu),
                  popUpAnimationStyle: MediaQuery.disableAnimationsOf(context)
                      ? AnimationStyle.noAnimation
                      : AnimationStyle(
                          curve: Curves.easeOutCubic,
                          reverseCurve: Curves.easeInCubic,
                          duration: const Duration(milliseconds: 180),
                          reverseDuration: const Duration(milliseconds: 120),
                        ),
                  onSelected: (value) {
                    if (value == 'zone') onZone?.call();
                    if (value == 'filter') onFilter();
                    if (value == 'guide') onGuide?.call();
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem<String>(
                      value: 'zone',
                      enabled: onZone != null,
                      child: Text(
                        zoneLabel,
                        key: const ValueKey('schedule-zone-switch'),
                      ),
                    ),
                    PopupMenuItem<String>(
                      value: 'filter',
                      child: Text(
                        filterLabel,
                        key: const ValueKey('schedule-filter'),
                      ),
                    ),
                    if (onGuide != null)
                      PopupMenuItem<String>(
                        value: 'guide',
                        child: Text(
                          t['scheduleGuideReplay']!,
                          key: const ValueKey('schedule-guide-replay'),
                        ),
                      ),
                  ],
                ),
                _group(shrink, [
                  if (arrows)
                    _step(
                      key: const ValueKey('schedule-previous'),
                      tooltip: previousTip,
                      onPressed: canPrevious ? onPrevious : null,
                      icon: Icons.chevron_left,
                    ),
                  _fit(
                    shrink,
                    TextButton(
                      key: const ValueKey('schedule-date'),
                      onPressed: onPickDate,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _fit(
                            shrink,
                            Text(
                              dateLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const Icon(Icons.arrow_drop_down),
                        ],
                      ),
                    ),
                  ),
                  if (arrows)
                    _step(
                      key: const ValueKey('schedule-next'),
                      tooltip: nextTip,
                      onPressed: canNext ? onNext : null,
                      icon: Icons.chevron_right,
                    ),
                ]),
                if (onToday != null)
                  _fit(
                    shrink,
                    TextButton(
                      key: const ValueKey('schedule-today-button'),
                      onPressed: todayInView ? null : onToday,
                      child: Text(t['today']!, maxLines: 1),
                    ),
                  ),
                _chip(
                  const ValueKey('schedule-mode-day'),
                  t['scheduleDayShort']!,
                  view == PlannerView.day,
                  () => onView(PlannerView.day),
                ),
                _chip(
                  const ValueKey('schedule-mode-week'),
                  t['scheduleWeekShort']!,
                  view == PlannerView.week,
                  () => onView(PlannerView.week),
                ),
                const SizedBox(width: plannerPageMargin - 8),
              ],
            );
            // Very large text: shrink the row rather than clip it.
            return shrink
                ? FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: row,
                  )
                : row;
          },
        ),
      ),
    );
  }

  Widget _group(bool shrink, List<Widget> children) => shrink
      ? Row(mainAxisSize: MainAxisSize.min, children: children)
      : Expanded(child: Row(children: children));

  Widget _fit(bool shrink, Widget child) =>
      shrink ? child : Flexible(child: child);

  Widget _chip(Key key, String label, bool selected, VoidCallback onTap) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: ChoiceChip(
          key: key,
          label: Text(label),
          selected: selected,
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 2),
          showCheckmark: false,
          onSelected: (_) => onTap(),
        ),
      );

  Widget _step({
    required Key key,
    required String tooltip,
    required VoidCallback? onPressed,
    required IconData icon,
  }) {
    return IconButton(
      key: key,
      tooltip: tooltip,
      onPressed: onPressed,
      iconSize: 22,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 40, height: 40),
      icon: Icon(icon),
    );
  }
}
