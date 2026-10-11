import 'package:flutter/material.dart';

import '../models.dart';
import '../widgets/schedule_layout.dart';
import 'planner_format.dart';

/// Bottom detail panel of the selected schedule item: title, task, quadrant,
/// date and time, length. Edit and delete are icon buttons at the top right.
/// Time-zone names appear only when the item was made in another zone.
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
    final quadrant = entry.quadrant;
    final color = quadrant == null
        ? null
        : Color(quadrantColors[quadrant] ?? quadrantColors[qEliminate]!);
    final showTask = entry.taskTitle != null && entry.taskTitle != entry.title;
    return Material(
      key: const ValueKey('schedule-detail'),
      color: theme.colorScheme.surfaceContainerHigh,
      elevation: 6,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 4, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      entry.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                    if (showTask)
                      Text(
                        '${t['scheduleTask']}: ${entry.taskTitle}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (color != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: color),
                            ),
                            child: Text(
                              t['scheduleQuadrant$quadrant']!,
                              style: theme.textTheme.labelMedium,
                            ),
                          ),
                        Text(
                          plannerDuration(item.startAt, item.endAt, t),
                          style: theme.textTheme.labelLarge,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      plannerRangeLabel(item, zone, language, t),
                      key: const ValueKey('schedule-detail-range'),
                      style: theme.textTheme.bodyMedium,
                    ),
                    if (item.timeZoneId != zone)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          plannerFilledZone(
                            t['scheduleTzNote']!,
                            item.timeZoneId,
                          ),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (writable) ...[
              IconButton(
                key: const ValueKey('schedule-detail-delete'),
                tooltip: t['scheduleEditorDelete'],
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline),
              ),
              IconButton(
                key: const ValueKey('schedule-detail-edit'),
                tooltip: t['scheduleEditorEdit'],
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String plannerFilledZone(String template, String zone) =>
    template.replaceAll('{zone}', zone);
