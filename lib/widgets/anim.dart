import 'package:flutter/material.dart';

import '../ui/motion_policy.dart';

/// Fade + slide-up entrance, delayed by [index] * 45ms. Plays once per
/// element (state is kept as long as the widget key stays stable).
/// When motion is reduced the child is shown at its final state immediately:
/// no queued delay, no fade.
class StaggerIn extends StatefulWidget {
  final int index;
  final Widget child;
  const StaggerIn({super.key, required this.index, required this.child});

  @override
  State<StaggerIn> createState() => _StaggerInState();
}

class _StaggerInState extends State<StaggerIn> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: MotionPolicy.entranceFade,
  );
  late final Animation<double> _fade =
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);

  bool _resolved = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_resolved) return;
    _resolved = true;
    if (MotionPolicy.reduceMotionNow(context)) {
      _controller.value = 1;
      return;
    }
    Future.delayed(
      MotionPolicy.entranceStep * widget.index.clamp(0, 12),
      _start,
    );
  }

  void _start() {
    if (!mounted) return;
    if (MotionPolicy.reduceMotionNow(context)) {
      _controller.value = 1;
      return;
    }
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Reduced motion switched on while the stagger delay / fade is still
    // running: land on the fully-visible terminal frame instead of waiting out
    // the remaining entrance. The one-shot nature is preserved (we never
    // re-forward once completed).
    if (MotionPolicy.reduceMotionOf(context) && !_controller.isCompleted) {
      _controller.value = 1;
    }
    return AnimatedBuilder(
      animation: _fade,
      builder: (context, child) => Opacity(
        opacity: _fade.value,
        child: Transform.translate(
          offset: Offset(0, 14 * (1 - _fade.value)),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}

/// Per-line strikethrough for completed titles (follows each wrapped line).
class StrikeThrough extends StatelessWidget {
  final Widget child;
  final bool crossed;
  final Color color;
  const StrikeThrough({
    super.key,
    required this.child,
    required this.crossed,
    this.color = const Color(0xCC94A3B8),
  });

  @override
  Widget build(BuildContext context) {
    final child = this.child;
    if (child is Text) {
      final base = child.style ?? DefaultTextStyle.of(context).style;
      return Text(
        child.data ?? '',
        key: child.key,
        maxLines: child.maxLines,
        overflow: child.overflow,
        softWrap: child.softWrap,
        textAlign: child.textAlign,
        textDirection: child.textDirection,
        locale: child.locale,
        style: base.copyWith(
          decoration:
              crossed ? TextDecoration.lineThrough : TextDecoration.none,
          decorationColor: crossed ? color : base.decorationColor,
          decorationThickness: crossed ? 1.6 : base.decorationThickness,
        ),
      );
    }
    return DefaultTextStyle.merge(
      style: TextStyle(
        decoration: crossed ? TextDecoration.lineThrough : TextDecoration.none,
        decorationColor: color,
      ),
      child: child,
    );
  }
}
