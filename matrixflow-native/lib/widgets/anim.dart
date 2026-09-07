import 'package:flutter/material.dart';

/// Fade + slide-up entrance, delayed by [index] * 45ms. Plays once per
/// element (state is kept as long as the widget key stays stable).
class StaggerIn extends StatefulWidget {
  final int index;
  final Widget child;
  const StaggerIn({super.key, required this.index, required this.child});

  @override
  State<StaggerIn> createState() => _StaggerInState();
}

class _StaggerInState extends State<StaggerIn> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 260));
  late final Animation<double> _fade =
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: widget.index.clamp(0, 12) * 45), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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

/// Animated strikethrough bar over completed titles (mirrors the web card).
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
    return TweenAnimationBuilder<double>(
      tween: Tween(end: crossed ? 1.0 : 0.0),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      builder: (context, value, text) {
        return Stack(
          alignment: Alignment.centerLeft,
          children: [
            text!,
            // Bar sweeps from 0 to full width of the text box.
            Positioned.fill(
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: value,
                  child: Container(height: 1.8, color: color),
                ),
              ),
            ),
          ],
        );
      },
      child: child,
    );
  }
}
