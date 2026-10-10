import 'dart:math' as math;

import 'package:flutter/material.dart';

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
    required this.onToday,
    required this.onView,
    required this.onFilter,
    this.onZone,
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
  final VoidCallback onToday;
  final ValueChanged<PlannerView> onView;
  final VoidCallback onFilter;
  final VoidCallback? onZone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final previousTip = t[view == PlannerView.day
        ? 'schedulePreviousDay'
        : 'schedulePreviousWeek']!;
    final nextTip = t[view == PlannerView.day
        ? 'scheduleNextDay'
        : 'scheduleNextWeek']!;
    final scale = math.max(
      1.0,
      MediaQuery.textScalerOf(context).scale(14) / 14,
    );
    return Material(
      color: theme.scaffoldBackgroundColor,
      child: SizedBox(
        height: 56 * scale,
        width: double.infinity,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PopupMenuButton<String>(
                key: const ValueKey('schedule-menu'),
                tooltip: t['scheduleMenu'],
                icon: const Icon(Icons.menu),
                onSelected: (value) {
                  if (value == 'zone') onZone?.call();
                  if (value == 'filter') onFilter();
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
                ],
              ),
              _step(
                key: const ValueKey('schedule-previous'),
                tooltip: previousTip,
                onPressed: canPrevious ? onPrevious : null,
                icon: Icons.chevron_left,
              ),
              TextButton.icon(
                key: const ValueKey('schedule-date'),
                onPressed: onPickDate,
                iconAlignment: IconAlignment.end,
                icon: const Icon(Icons.arrow_drop_down),
                label: Text(dateLabel),
              ),
              _step(
                key: const ValueKey('schedule-next'),
                tooltip: nextTip,
                onPressed: canNext ? onNext : null,
                icon: Icons.chevron_right,
              ),
              const SizedBox(width: 4),
              ChoiceChip(
                key: const ValueKey('schedule-mode-day'),
                label: Text(t['scheduleDayShort']!),
                selected: view == PlannerView.day,
                onSelected: (_) => onView(PlannerView.day),
              ),
              const SizedBox(width: 4),
              ChoiceChip(
                key: const ValueKey('schedule-mode-week'),
                label: Text(t['scheduleWeekShort']!),
                selected: view == PlannerView.week,
                onSelected: (_) => onView(PlannerView.week),
              ),
              const SizedBox(width: 4),
              TextButton(
                key: const ValueKey('schedule-today'),
                onPressed: onToday,
                child: Text(t['today']!),
              ),
            ],
          ),
        ),
      ),
    );
  }

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
      constraints: const BoxConstraints.tightFor(width: 32, height: 32),
      icon: Icon(icon),
    );
  }
}
