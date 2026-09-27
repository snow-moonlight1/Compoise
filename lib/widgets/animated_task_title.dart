import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../ui/motion_policy.dart';

/// Paints one growing (or retracting) strikethrough segment per visible text
/// line fragment.
///
/// The segments come from [TextPainter.getBoxesForSelection] on the laid-out
/// paragraph, so they cover the real glyph extents after wrapping, ellipsis
/// truncation and BiDi splitting. Line length is never estimated from the
/// character count or an average glyph width.
class StrikeThroughPainter extends CustomPainter {
  const StrikeThroughPainter({
    required this.boxes,
    required this.progress,
    this.color = const Color(0xCC94A3B8),
    this.thickness = 1.6,
  });

  /// Visible line fragments, in reading order.
  final List<ui.TextBox> boxes;

  /// 0 = not drawn, 1 = full line width.
  final double progress;

  final Color color;
  final double thickness;

  /// Number of distinct visible lines (fragments sharing a top belong to one).
  int get lineCount => boxes.map((b) => b.top.round()).toSet().length;

  /// Total length currently drawn, exposed for animation assertions.
  double get drawnLength {
    final p = progress.clamp(0.0, 1.0);
    var total = 0.0;
    for (final b in boxes) {
      total += (b.right - b.left) * p;
    }
    return total;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final p = progress.clamp(0.0, 1.0);
    if (p <= 0 || boxes.isEmpty) return;
    final paint =
        Paint()
          ..color = color
          ..strokeWidth = thickness
          ..style = PaintingStyle.stroke;
    for (final box in boxes) {
      final width = (box.right - box.left) * p;
      if (width <= 0.5) continue;
      final y = box.top + (box.bottom - box.top) / 2;
      canvas.drawLine(Offset(box.left, y), Offset(box.left + width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant StrikeThroughPainter old) {
    if (old.progress != progress ||
        old.color != color ||
        old.thickness != thickness ||
        old.boxes.length != boxes.length) {
      return true;
    }
    for (var i = 0; i < boxes.length; i++) {
      if (old.boxes[i] != boxes[i]) return true;
    }
    return false;
  }
}

/// Title text with a per-line strikethrough animation driven by [completed].
///
/// Contract (UX06):
/// * Layout and painting use the same [TextPainter] parameters as the rendered
///   [Text], so the segments follow the real wrapped/ellipsised glyphs.
/// * The first build never animates: an already completed task shows the final
///   state, and only a *change* of [completed] on a mounted widget plays.
/// * The animation is interruptible and reversible (rapid taps retarget the
///   single controller instead of queueing).
/// * With reduced motion (app setting OR platform request) the widget jumps
///   straight to the final state and never waits on a timer.
class AnimatedStrikeThroughText extends StatefulWidget {
  const AnimatedStrikeThroughText({
    super.key,
    required this.text,
    required this.completed,
    this.style,
    this.textKey,
    this.strikeKey,
    this.maxLines,
    this.overflow = TextOverflow.clip,
    this.textAlign = TextAlign.start,
    this.textDirection,
    this.locale,
    this.softWrap = true,
    this.strikeColor = const Color(0xCC94A3B8),
    this.strikeThickness = 1.6,
  });

  final String text;

  /// Drives the animation. Only changes of this flag while mounted animate.
  final bool completed;

  final TextStyle? style;

  /// Key of the inner [Text], so existing finders keep working.
  final Key? textKey;

  /// Key of the [CustomPaint] that owns the painter (animation assertions).
  final Key? strikeKey;

  final int? maxLines;
  final TextOverflow overflow;
  final TextAlign textAlign;
  final TextDirection? textDirection;
  final Locale? locale;
  final bool softWrap;
  final Color strikeColor;
  final double strikeThickness;

  @override
  State<AnimatedStrikeThroughText> createState() =>
      _AnimatedStrikeThroughTextState();
}

class _AnimatedStrikeThroughTextState
    extends State<AnimatedStrikeThroughText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: MotionPolicy.strikethrough,
  );

  List<ui.TextBox> _boxes = const [];

  /// Cache identity for [_boxes]. It carries the [TextScaler] itself, not
  /// `scaler.scale(1.0)`: two non-linear scalers can agree at 1 dp and still
  /// lay out a 16 dp glyph at different widths.
  (String, TextStyle, int?, TextOverflow, Locale?, TextDirection, double, TextScaler)?
  _layoutKey;

  @override
  void initState() {
    super.initState();
    // Initial state is terminal: entering a screen with completed tasks must
    // not replay every strikethrough.
    _controller.value = widget.completed ? 1.0 : 0.0;
  }

  @override
  void didUpdateWidget(covariant AnimatedStrikeThroughText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.completed == widget.completed) return;
    if (MotionPolicy.reduceMotionNow(context)) {
      _controller.value = widget.completed ? 1.0 : 0.0;
    } else if (widget.completed) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<ui.TextBox> _lineBoxes({
    required TextStyle style,
    required TextDirection direction,
    required TextScaler scaler,
    required double maxWidth,
  }) {
    final key = (
      widget.text,
      style,
      widget.maxLines,
      widget.overflow,
      widget.locale,
      direction,
      maxWidth,
      scaler,
    );
    if (_layoutKey == key) return _boxes;
    if (widget.text.isEmpty || !maxWidth.isFinite) {
      _layoutKey = key;
      _boxes = const [];
      return _boxes;
    }
    final painter = TextPainter(
      text: TextSpan(text: widget.text, style: style),
      textAlign: widget.textAlign,
      textDirection: direction,
      maxLines: widget.maxLines,
      ellipsis: widget.overflow == TextOverflow.ellipsis ? '…' : null,
      locale: widget.locale,
      textScaler: scaler,
    );
    List<ui.TextBox> boxes;
    try {
      painter.layout(maxWidth: maxWidth);
      final selection = TextSelection(
        baseOffset: 0,
        extentOffset: widget.text.length,
      );
      boxes =
          painter
              .getBoxesForSelection(selection)
              .where((box) => box.right > box.left)
              .toList();
    } finally {
      painter.dispose();
    }
    _boxes = boxes;
    _layoutKey = key;
    return _boxes;
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MotionPolicy.reduceMotionOf(context);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final raw = reduceMotion
            ? (widget.completed ? 1.0 : 0.0)
            : _controller.value;
        return _buildText(context, Curves.easeOut.transform(raw));
      },
    );
  }

  Widget _buildText(BuildContext context, double progress) {
    final direction = widget.textDirection ?? Directionality.of(context);
    final base = DefaultTextStyle.of(context).style;
    final style = widget.style == null ? base : base.merge(widget.style);
    final scaler = MediaQuery.textScalerOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final boxes = _lineBoxes(
          style: style,
          direction: direction,
          scaler: scaler,
          maxWidth: constraints.maxWidth,
        );
        return CustomPaint(
          key: widget.strikeKey,
          foregroundPainter: StrikeThroughPainter(
            boxes: boxes,
            progress: progress,
            color: widget.strikeColor,
            thickness: widget.strikeThickness,
          ),
          child: Text(
            widget.text,
            key: widget.textKey,
            style: widget.style,
            maxLines: widget.maxLines,
            overflow: widget.overflow,
            textAlign: widget.textAlign,
            textDirection: direction,
            locale: widget.locale,
            softWrap: widget.softWrap,
          ),
        );
      },
    );
  }
}
