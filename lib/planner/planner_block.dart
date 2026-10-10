import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../quadrant.dart';
import '../schedule_item.dart';
import '../storage.dart';
import '../widgets/schedule_layout.dart';
import 'schedule_edit_session.dart';

typedef PlannerDragBuilder =
    Widget Function(ScheduleEditMode mode, Widget child, {Key? key});

/// One schedule record. The full UTC description stays in semantics.
class PlannerBlock extends StatelessWidget {
  const PlannerBlock({
    super.key,
    required this.placement,
    required this.dateLabel,
    required this.zone,
    required this.t,
    required this.liveStore,
    required this.adjusting,
    required this.onOpen,
    required this.onHandle,
    required this.drag,
    this.compact = false,
  });

  final SchedulePlacement placement;
  final String dateLabel;
  final String zone;
  final Map<String, String> t;
  final Store? liveStore;
  final bool adjusting;
  final VoidCallback onOpen;
  final void Function(ScheduleEditMode mode) onHandle;
  final PlannerDragBuilder drag;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final entry = placement.entry;
    final slice = placement.slice;
    final theme = Theme.of(context);
    final isBlock = entry.item.kind == ScheduleItemKind.timeBlock;
    final continuation = [
      if (slice.continuesBefore) t['scheduleContinuesBefore']!,
      if (slice.continuesAfter) t['scheduleContinuesAfter']!,
    ].join(' · ');
    final semantics =
        '${plannerEntryLabel(entry, t)} · '
        '${t['scheduleStart']}: ${scheduleInstantLabel(slice.startAt, zone)} · '
        '${t['scheduleEnd']}: ${scheduleInstantLabel(slice.endAt, zone)}'
        '${continuation.isEmpty ? '' : ' · $continuation'}';
    final visible = compact
        ? '${scheduleAxisLabel(slice.startAt, zone)} ${entry.title}'
        : [
            entry.title,
            '${scheduleAxisLabel(slice.startAt, zone)} – '
                '${scheduleAxisLabel(slice.endAt, zone)}',
            if (!isBlock && entry.taskTitle != null)
              '${t['scheduleTask']}: ${entry.taskTitle}',
            if (entry.completed) t['completed']!,
            if (continuation.isNotEmpty) continuation,
          ].join('\n');
    final accent = entry.quadrant == null
        ? theme.colorScheme.secondary
        : Color(quadrantColors[entry.quadrant] ?? quadrantColors[qEliminate]!);
    final card = MergeSemantics(
      key: ValueKey('schedule-semantics-$dateLabel-${entry.item.id}'),
      child: Semantics(
        label: semantics,
        child: Builder(
          builder: (context) => OutlinedButton(
            key: ValueKey('schedule-item-$dateLabel-${entry.item.id}'),
            style: OutlinedButton.styleFrom(
              padding: EdgeInsets.fromLTRB(0, compact ? 2 : 6, 8, compact ? 2 : 6),
              minimumSize: compact ? Size.zero : null,
              tapTargetSize: compact
                  ? MaterialTapTargetSize.shrinkWrap
                  : MaterialTapTargetSize.padded,
              alignment: Alignment.centerLeft,
              overlayColor: const Color(0x00000000),
              foregroundColor: entry.completed
                  ? theme.colorScheme.onSurfaceVariant
                  : theme.colorScheme.onSurface,
              backgroundColor: accent.withValues(alpha: entry.completed ? 0.1 : 0.18),
              side: BorderSide(color: accent.withValues(alpha: 0.45)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: onOpen,
            onFocusChange: (focused) {
              if (!focused) return;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (context.mounted) {
                  Scrollable.ensureVisible(
                    context,
                    alignment: 0.15,
                    duration: const Duration(milliseconds: 150),
                  );
                }
              });
            },
            child: ExcludeSemantics(
              child: ClipRect(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(width: 4, color: accent),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        visible,
                        maxLines: compact ? 1 : null,
                        overflow: TextOverflow.fade,
                        softWrap: !compact,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (liveStore == null) return card;
    final moving = drag(
      ScheduleEditMode.move,
      card,
      key: ValueKey('schedule-drag-$dateLabel-${entry.item.id}'),
    );
    if (compact) return moving;
    if (!adjusting) {
      return Stack(
        children: [
          Positioned.fill(child: moving),
          _edge(ScheduleEditMode.resizeStart),
          _edge(ScheduleEditMode.resizeEnd),
        ],
      );
    }
    final handleHeight =
        48.0 * math.max(1.0, MediaQuery.textScalerOf(context).scale(14) / 14);
    return Stack(
      children: [
        Positioned(
          top: handleHeight,
          bottom: handleHeight,
          left: 0,
          right: 0,
          child: moving,
        ),
        for (final mode in [
          ScheduleEditMode.resizeStart,
          ScheduleEditMode.resizeEnd,
        ])
          Positioned(
            top: mode == ScheduleEditMode.resizeStart ? 0 : null,
            bottom: mode == ScheduleEditMode.resizeEnd ? 0 : null,
            left: 0,
            right: 0,
            height: handleHeight,
            child: drag(
              mode,
              OutlinedButton(
                key: ValueKey(
                  'schedule-handle-$dateLabel-${entry.item.id}-${mode.name}',
                ),
                onPressed: () => onHandle(mode),
                child: Text(
                  t[mode == ScheduleEditMode.resizeStart
                      ? 'scheduleEditorResizeStart'
                      : 'scheduleEditorResizeEnd']!,
                ),
              ),
              key: ValueKey(
                'schedule-handle-drag-$dateLabel-${entry.item.id}-${mode.name}',
              ),
            ),
          ),
      ],
    );
  }

  Widget _edge(ScheduleEditMode mode) {
    return Positioned(
      top: mode == ScheduleEditMode.resizeStart ? 0 : null,
      bottom: mode == ScheduleEditMode.resizeEnd ? 0 : null,
      left: 0,
      right: 0,
      height: 18,
      child: drag(
        mode,
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onOpen,
          child: const SizedBox(width: double.infinity, height: 18),
        ),
      ),
    );
  }
}

String plannerEntryLabel(ScheduleEntry entry, Map<String, String> t) => [
  t[entry.item.kind == ScheduleItemKind.timeBlock
      ? 'scheduleTimeBlock'
      : 'scheduleEvent']!,
  entry.title,
  entry.boardName ?? t['unknownBoard']!,
  if (entry.taskTitle != null) '${t['scheduleTask']}: ${entry.taskTitle}',
  if (entry.quadrant != null) 'Q${entry.quadrant} · ${t['q${entry.quadrant}Short']}',
  if (entry.taskTitle != null)
    '${t['scheduleTask']}: ${t[entry.completed ? 'completed' : 'incomplete']}',
].join(' · ');
