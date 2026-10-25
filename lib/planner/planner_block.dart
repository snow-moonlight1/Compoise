import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../quadrant.dart';
import '../ui/platform_ui_policy.dart';
import '../widgets/schedule_layout.dart';
import 'planner_format.dart';
import 'planner_skin.dart';
import 'schedule_edit_session.dart';

typedef PlannerDragBuilder =
    Widget Function(
      ScheduleEditMode mode,
      Widget child, {
      Key? key,
      Size? size,
    });

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
    this.onContextMenu,
    this.compact = false,
    this.dayStart,
    this.dayEnd,
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

  /// Right click (desktop): edit / delete menu at the pointer.
  final ValueChanged<Offset>? onContextMenu;
  final bool compact;

  /// The day's window; a drag never carries the block outside it.
  final int? dayStart;
  final int? dayEnd;

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
    var minutes = (raw / 15).round() * 15;
    final ws = widget.dayStart;
    final we = widget.dayEnd;
    if (ws == null || we == null || _mode == null) return minutes;
    const ms = Duration.millisecondsPerMinute;
    const min = 15;
    final s = _startAt ~/ ms;
    final e = _endAt ~/ ms;
    final (lo, hi) = switch (_mode!) {
      ScheduleEditMode.move => (ws ~/ ms - s, we ~/ ms - e),
      ScheduleEditMode.resizeStart => (ws ~/ ms - s, e - min - s),
      ScheduleEditMode.resizeEnd => (s + min - e, we ~/ ms - e),
      _ => (minutes, minutes),
    };
    if (lo <= hi) minutes = minutes.clamp(lo, hi);
    return minutes;
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

  double _pressY = 0;
  bool _hovered = false;

  /// Desktop: pointer cursor and a light tint under the mouse.
  Widget _hoverable(ThemeData theme, Widget card) => MouseRegion(
    cursor: SystemMouseCursors.click,
    onEnter: (_) => setState(() => _hovered = true),
    onExit: (_) => setState(() => _hovered = false),
    child: DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: _hovered
            ? theme.colorScheme.onSurface.withValues(alpha: 0.06)
            : const Color(0x00000000),
      ),
      child: card,
    ),
  );

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
      // The drag preview is this very label at the same size.
      return LayoutBuilder(
        builder: (context, box) => widget.drag(
          ScheduleEditMode.move,
          card,
          key: ValueKey('schedule-drag-${widget.dateLabel}-${entry.item.id}'),
          size: Size(box.maxWidth, box.maxHeight),
        ),
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
            onSecondaryTapUp: widget.onContextMenu == null
                ? null
                : (d) => widget.onContextMenu!(d.globalPosition),
            onLongPressStart: (_) => _begin(ScheduleEditMode.move),
            onLongPressMoveUpdate: (d) =>
                _update(d.offsetFromOrigin.dy, d.globalPosition),
            onLongPressEnd: (_) => _end(),
            onLongPressCancel: _cancel,
            child: desktop
                // Desktop mouse: press and drag moves at once, no long press.
                // Mouse only, so a touch screen still scrolls the timeline.
                ? GestureDetector(
                    supportedDevices: const {PointerDeviceKind.mouse},
                    onVerticalDragStart: (d) {
                      _pressY = d.globalPosition.dy;
                      _begin(ScheduleEditMode.move);
                    },
                    onVerticalDragUpdate: (d) => _update(
                      d.globalPosition.dy - _pressY,
                      d.globalPosition,
                    ),
                    onVerticalDragEnd: (_) => _end(),
                    onVerticalDragCancel: _cancel,
                    child: Opacity(
                      opacity: _mode == null ? 1 : 0.55,
                      child: _hoverable(theme, card),
                    ),
                  )
                : Opacity(opacity: _mode == null ? 1 : 0.55, child: card),
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
        ? Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${plannerClock(slice.startAt, widget.zone)} ${entry.title}',
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(color: textColor),
            ),
          )
        : LayoutBuilder(
            builder: (context, box) {
              // A very short block shows one line, "title time"; otherwise the
              // text sits left-aligned and centred vertically.
              final k = MediaQuery.textScalerOf(context).scale(14) / 14;
              // Drop the extras that do not fit instead of overflowing.
              var titleLines = tall ? 2 : 1;
              var badge = widget.concurrent > 0 && tall;
              double need() => (20.0 * titleLines + 16 + (badge ? 16 : 0)) * k;
              if (need() > box.maxHeight) badge = false;
              if (need() > box.maxHeight) titleLines = 1;
              if (box.maxHeight < 40 || need() > box.maxHeight) {
                return Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${entry.title}  $range',
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: textColor,
                    ),
                  ),
                );
              }
              return Align(
                alignment: Alignment.centerLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      entry.title,
                      maxLines: titleLines,
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
                    if (badge)
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
                ),
              );
            },
          );
    final selected = widget.selected;
    final skin = PlannerSkin.of(context);
    final content = DecoratedBox(
      decoration: skin.surface(
        BoxDecoration(
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
        selected: selected,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(skin.comic != null ? 6 : 7),
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
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${widget.placement.entry.title}  '
                '${plannerClock(start, widget.zone)}–${plannerClock(end, widget.zone)}',
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium,
              ),
            ),
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
    final skin = PlannerSkin.of(context);
    final base = BoxDecoration(
      color: theme.colorScheme.surface,
      shape: BoxShape.circle,
      border: Border.all(color: color, width: 3),
      boxShadow: const [BoxShadow(blurRadius: 3, color: Color(0x33000000))],
    );
    return Container(
      width: 20,
      height: 20,
      // Same ring in every skin; only the shadow follows it.
      decoration: skin.plain
          ? base
          : skin.surface(base).copyWith(border: base.border),
    );
  }
}

String plannerCountedBadge(String template, int n) =>
    template.replaceAll('{n}', '$n');
