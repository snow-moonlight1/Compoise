import 'package:flutter/material.dart';

import '../models.dart';
import '../widgets/schedule_layout.dart';
import 'planner_format.dart';
import 'planner_skin.dart';

/// Small floating bar for the selected block: its time and length, plus edit
/// and delete icons. The block itself already shows the title.
class PlannerDetailCard extends StatelessWidget {
  const PlannerDetailCard({
    super.key,
    required this.entry,
    required this.zone,
    required this.language,
    required this.t,
    required this.writable,
    required this.onEdit,
    required this.onDelete,
  });

  final ScheduleEntry entry;
  final String zone;
  final Language language;
  final Map<String, String> t;
  final bool writable;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = entry.item;
    final skin = PlannerSkin.of(context);
    final bar = Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 4, 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              '${plannerClock(item.startAt, zone)}–'
              '${plannerClock(item.endAt, zone)} · '
              '${plannerDuration(item.startAt, item.endAt, t)}',
              key: const ValueKey('schedule-detail-range'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge,
            ),
          ),
          if (writable) ...[
            IconButton(
              key: const ValueKey('schedule-detail-edit'),
              tooltip: t['scheduleEditorEdit'],
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined),
            ),
            IconButton(
              key: const ValueKey('schedule-detail-delete'),
              tooltip: t['scheduleEditorDelete'],
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ],
      ),
    );
    if (!skin.plain) {
      // Comic / neumorphic: the bar is a drawn pill, not a Material shadow.
      return DecoratedBox(
        key: const ValueKey('schedule-detail'),
        decoration: skin.surface(
          BoxDecoration(
            color: theme.colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(28),
          ),
        ),
        child: ClipRRect(borderRadius: BorderRadius.circular(26), child: bar),
      );
    }
    return Material(
      key: const ValueKey('schedule-detail'),
      color: theme.colorScheme.surfaceContainerHigh,
      elevation: 4,
      borderRadius: BorderRadius.circular(28),
      clipBehavior: Clip.antiAlias,
      child: bar,
    );
  }
}

String plannerFilledZone(String template, String zone) =>
    template.replaceAll('{zone}', zone);
