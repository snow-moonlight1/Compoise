import 'package:flutter/material.dart';

/// Shows one of [children] and slides + fades to another when [index] changes.
///
/// Every child stays mounted (like an `IndexedStack`), so each page keeps its
/// own state; pages that are off screen are only laid out, not painted or hit.
/// With "reduce motion" the switch is immediate.
class TabSlider extends StatefulWidget {
  const TabSlider({
    super.key,
    required this.index,
    required this.children,
    this.duration = const Duration(milliseconds: 250),
  });

  final int index;
  final List<Widget> children;
  final Duration duration;

  @override
  State<TabSlider> createState() => _TabSliderState();
}

class _TabSliderState extends State<TabSlider>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  late double _from = widget.index.toDouble();
  late double _to = widget.index.toDouble();

  double get _pos {
    final t = Curves.easeOutCubic.transform(_controller.value);
    return _from + (_to - _from) * t;
  }

  @override
  void didUpdateWidget(TabSlider old) {
    super.didUpdateWidget(old);
    if (widget.index == old.index) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
      _from = _to = widget.index.toDouble();
      return;
    }
    _from = _pos;
    _to = widget.index.toDouble();
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final pos = _pos;
          final moving = _controller.isAnimating;
          return Stack(
            fit: StackFit.expand,
            children: [
              for (var i = 0; i < widget.children.length; i++)
                Offstage(
                  offstage: (i - pos).abs() >= 1,
                  child: IgnorePointer(
                    ignoring: moving || i != widget.index,
                    child: Opacity(
                      opacity: (1 - (i - pos).abs()).clamp(0.0, 1.0),
                      child: FractionalTranslation(
                        translation: Offset(i - pos, 0),
                        child: widget.children[i],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
