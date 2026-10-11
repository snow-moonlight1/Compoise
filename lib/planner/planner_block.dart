import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../quadrant.dart';
import '../ui/platform_ui_policy.dart';
import '../widgets/schedule_layout.dart';
import 'planner_format.dart';
import 'schedule_edit_session.dart';

typedef PlannerDragBuilder =
    Widget Function(ScheduleEditMode mode, Widget child, {Key? key});

/// Extra room above and below a selected block for the round edge handles.
/// It keeps each handle's 48 dp touch target inside the block's own bounds.
const double plannerHandleReach = 24;

/// One schedule item on the day grid or, compact, in the week list.
///
/// Touch: tap selects (round handles appear on both edges), long-press then
/// drag moves the whole block, dragging a handle changes start or end.
/// Desktop: the top and bottom edges show a resize cursor and can be dragged
/// right away. Every drag snaps to 15 minutes and shows the time live.
class PlannerBlock extends StatefulWidget {
  const PlannerBlock({
    super.key,
    required this.placement,
    required this.dateLabel,
    required this.zone,
    required this.t,
    required this.writable,
    required this.selected,
    required this.pixelsPerHour,
    required this.concurrent,
    required this.onTap,
    required this.onChange,
    required this.scrollOffset,
    required this.onDragGlobal,
    required this.drag,
    this.compact = false,
  });

  final SchedulePlacement placement;
  final String dateLabel;
  final String zone;
  final Map<String, String> t;
  final bool writable;
  final bool selected;
  final double pixelsPerHour;

  /// Number of other items that share time with this one.
  final int concurrent;
  final VoidCallback onTap;

  /// Commits a drag: mode plus a 15-minute-snapped delta in minutes.
  final void Function(ScheduleEditMode mode, int deltaMinutes) onChange;
  final double Function() scrollOffset;
  final ValueChanged<Offset> onDragGlobal;
  final PlannerDragBuilder drag;
  final bool compact;

  @override
  State<PlannerBlock> createState() => _PlannerBlockState();
}

class _PlannerBlockState extends State<PlannerBlock> {
  ScheduleEditMode? _mode;
  double _dy = 0;
  double _raw = 0;
  bool _focused = false;
  double _scrollAtStart = 0;

  int get _minutes {
    final raw = _dy / widget.pixelsPerHour * 60;
    return (raw / 15).round() * 15;
  }

  int get _startAt => widget.placement.slice.startAt;
  int get _endAt => widget.placement.slice.endAt;

  /// Proposed start and end for the live drag, clamped to a 15 minute minimum.
  (int, int) get _proposal {
    final delta = _minutes * Duration.millisecondsPerMinute;
    const min = 15 * Duration.millisecondsPerMinute;
    return switch (_mode) {
      ScheduleEditMode.move => (_startAt + delta, _endAt + delta),
      ScheduleEditMode.resizeStart => (
        math.min(_startAt + delta, _endAt - min),
        _endAt,
      ),
      ScheduleEditMode.resizeEnd => (
        _startAt,
        math.max(_endAt + delta, _startAt + min),
      ),
      _ => (_startAt, _endAt),
    };
  }

  void _begin(ScheduleEditMode mode) {
    _scrollAtStart = widget.scrollOffset();
    _raw = 0;
    setState(() {
      _mode = mode;
      _dy = 0;
    });
    HapticFeedback.selectionClick();
  }

  /// [raw] is the finger travel; scrolling under the finger (auto-scroll near
  /// the edges) adds to it so the block follows the grid, not the screen.
  void _update(double raw, Offset global) {
    _raw = raw;
    widget.onDragGlobal(global);
    setState(() => _dy = _raw + (widget.scrollOffset() - _scrollAtStart));
  }

  void _end() {
    final mode = _mode;
    final minutes = _minutes;
    setState(() {
      _mode = null;
      _dy = 0;
    });
    if (mode != null && minutes != 0) widget.onChange(mode, minutes);
  }

  void _cancel() => setState(() {
    _mode = null;
    _dy = 0;
  });

  @override
  Widget build(BuildContext context) {
    final entry = widget.placement.entry;
    final slice = widget.placement.slice;
    final theme = Theme.of(context);
    final t = widget.t;
    final zone = widget.zone;
    final accent = entry.quadrant == null
        ? theme.colorScheme.secondary
        : Color(quadrantColors[entry.quadrant] ?? quadrantColors[qEliminate]!);
    final range =
        '${plannerClock(slice.startAt, zone)}–${plannerClock(slice.endAt, zone)}';
    final semantics = [
      entry.title,
      range,
      if (entry.taskTitle != null && entry.taskTitle != entry.title)
        '${t['scheduleTask']}: ${entry.taskTitle}',
      if (entry.completed) t['completed']!,
      if (widget.concurrent > 0)
        plannerCountedBadge(t['scheduleOverlapBadge']!, widget.concurrent),
    ].join(' · ');
    final card = _card(theme, accent, range, semantics);
    if (!widget.writable) return card;
    if (widget.compact) {
      return widget.drag(
        ScheduleEditMode.move,
        card,
        key: ValueKey('schedule-drag-${widget.dateLabel}-${entry.item.id}'),
      );
    }
    final desktop = PlatformUiPolicy.of(context).isDesktop;
    final selected = widget.selected;
    final reach = selected ? plannerHandleReach : 0.0;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (_mode != null) _preview(theme, accent, reach),
        Positioned.fill(
          key: const ValueKey('card'),
          top: reach,
          bottom: reach,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            onLongPressStart: (_) => _begin(ScheduleEditMode.move),
            onLongPressMoveUpdate: (d) =>
                _update(d.offsetFromOrigin.dy, d.globalPosition),
            onLongPressEnd: (_) => _end(),
            onLongPressCancel: _cancel,
            child: Opacity(opacity: _mode == null ? 1 : 0.55, child: card),
          ),
        ),
        if (desktop || selected) ...[
          _edge(ScheduleEditMode.resizeStart, reach, desktop, selected),
          _edge(ScheduleEditMode.resizeEnd, reach, desktop, selected),
        ],
        if (_mode != null) _bubble(theme, reach),
      ],
    );
  }

  Widget _card(ThemeData theme, Color accent, String range, String semantics) {
    final entry = widget.placement.entry;
    final slice = widget.placement.slice;
    final t = widget.t;
    final compact = widget.compact;
    final tall = widget.placement.height >= 64;
    final textColor = entry.completed
        ? theme.colorScheme.onSurfaceVariant
        : theme.colorScheme.onSurface;
    final body = compact
        ? Text(
            '${plannerClock(slice.startAt, widget.zone)} ${entry.title}',
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(color: textColor),
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Text(
                entry.title,
                maxLines: tall ? 2 : 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: textColor,
                  decoration: entry.completed
                      ? TextDecoration.lineThrough
                      : null,
                ),
              ),
              Text(
                range,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (widget.concurrent > 0 && tall)
                Row(
                  children: [
                    Icon(
                      Icons.view_week_outlined,
                      size: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 2),
                    Expanded(
                      child: Text(
                        plannerCountedBadge(
                          t['scheduleOverlapBadge']!,
                          widget.concurrent,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          );
    final selected = widget.selected;
    final content = DecoratedBox(
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          accent.withValues(alpha: entry.completed ? 0.08 : 0.16),
          theme.colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: selected ? accent : accent.withValues(alpha: 0.35),
          width: selected ? 2 : 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 4, color: accent),
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: compact ? 4 : 3,
                ),
                child: ClipRect(child: body),
              ),
            ),
          ],
        ),
      ),
    );
    return Semantics(
      key: ValueKey('schedule-semantics-${widget.dateLabel}-${entry.item.id}'),
      container: true,
      button: true,
      focusable: true,
      focused: _focused,
      selected: selected,
      label: semantics,
      onTap: widget.onTap,
      child: ExcludeSemantics(
        child: InkWell(
          key: ValueKey('schedule-item-${widget.dateLabel}-${entry.item.id}'),
          onTap: widget.onTap,
          onFocusChange: (value) => setState(() => _focused = value),
          borderRadius: BorderRadius.circular(8),
          child: content,
        ),
      ),
    );
  }

  /// Ghost of the proposed placement, painted over the grid while dragging.
  Widget _preview(ThemeData theme, Color accent, double reach) {
    final (start, end) = _proposal;
    final pph = widget.pixelsPerHour;
    final top = reach + (start - _startAt) / Duration.millisecondsPerHour * pph;
    final bottom = reach - (end - _endAt) / Duration.millisecondsPerHour * pph;
    return Positioned(
      key: const ValueKey('preview'),
      top: top,
      bottom: bottom,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: accent, width: 2),
          ),
        ),
      ),
    );
  }

  Widget _bubble(ThemeData theme, double reach) {
    final (start, end) = _proposal;
    final pph = widget.pixelsPerHour;
    final top = reach + (start - _startAt) / Duration.millisecondsPerHour * pph;
    return Positioned(
      key: const ValueKey('bubble'),
      top: top - 30,
      left: 8,
      child: IgnorePointer(
        child: Material(
          color: theme.colorScheme.inverseSurface,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Text(
              '${plannerClock(start, widget.zone)} – ${plannerClock(end, widget.zone)}',
              key: const ValueKey('schedule-drag-time'),
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onInverseSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _edge(
    ScheduleEditMode mode,
    double reach,
    bool desktop,
    bool selected,
  ) {
    final isStart = mode == ScheduleEditMode.resizeStart;
    final edge = widget
        .t[isStart ? 'scheduleEditorResizeStart' : 'scheduleEditorResizeEnd']!;
    final gesture = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragStart: (_) => _begin(mode),
      onVerticalDragUpdate: (d) => _update(_raw + d.delta.dy, d.globalPosition),
      onVerticalDragEnd: (_) => _end(),
      onVerticalDragCancel: _cancel,
      child: selected
          ? Stack(
              alignment: Alignment.center,
              children: [
                Semantics(
                  label: edge,
                  child: _Handle(color: Theme.of(context).colorScheme.primary),
                ),
              ],
            )
          : const SizedBox.expand(),
    );
    final key = ValueKey(
      'schedule-handle-${widget.dateLabel}-${widget.placement.entry.item.id}-${mode.name}',
    );
    if (selected) {
      // 48 dp tall, centered on the edge: half inside the reach area, half
      // inside the block.
      return Positioned(
        key: ValueKey('edge-${mode.name}'),
        top: isStart ? 0 : null,
        bottom: isStart ? null : 0,
        left: 0,
        right: 0,
        height: 2 * reach,
        child: KeyedSubtree(key: key, child: gesture),
      );
    }
    return Positioned(
      key: ValueKey('edge-${mode.name}'),
      top: isStart ? 0 : null,
      bottom: isStart ? null : 0,
      left: 0,
      right: 0,
      height: 10,
      child: MouseRegion(
        key: key,
        cursor: SystemMouseCursors.resizeUpDown,
        child: gesture,
      ),
    );
  }
}

class _Handle extends StatelessWidget {
  const _Handle({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 3),
        boxShadow: const [BoxShadow(blurRadius: 3, color: Color(0x33000000))],
      ),
    );
  }
}

String plannerCountedBadge(String template, int n) =>
    template.replaceAll('{n}', '$n');
