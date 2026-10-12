import 'package:flutter/widgets.dart';

/// Sideways swipe over the day grid: left = next day, right = previous day.
///
/// Only the horizontal recognizer lives here, so the grid's own vertical
/// scroll, the handle drags (vertical), long-press moves and the pool's
/// drag-and-drop keep working. Two-finger pinches are ignored.
class PlannerDaySwipe extends StatefulWidget {
  const PlannerDaySwipe({
    super.key,
    required this.child,
    required this.onSwipe,
  });

  final Widget child;

  /// +1 for the next day, -1 for the previous day.
  final ValueChanged<int> onSwipe;

  @override
  State<PlannerDaySwipe> createState() => _PlannerDaySwipeState();
}

class _PlannerDaySwipeState extends State<PlannerDaySwipe> {
  static const _distance = 64.0;
  static const _velocity = 500.0;
  final _pointers = <int>{};
  bool _multi = false;
  double _dx = 0;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (e) {
        _pointers.add(e.pointer);
        if (_pointers.length > 1) _multi = true;
      },
      onPointerUp: (e) {
        _pointers.remove(e.pointer);
        if (_pointers.isEmpty) _multi = false;
      },
      onPointerCancel: (e) {
        _pointers.remove(e.pointer);
        if (_pointers.isEmpty) _multi = false;
      },
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: (_) => _dx = 0,
        onHorizontalDragUpdate: (d) => _dx += d.delta.dx,
        onHorizontalDragEnd: (d) {
          if (_multi) return;
          final v = d.primaryVelocity ?? 0;
          if (_dx <= -_distance || (v <= -_velocity && _dx < -16)) {
            widget.onSwipe(1);
          } else if (_dx >= _distance || (v >= _velocity && _dx > 16)) {
            widget.onSwipe(-1);
          }
        },
        child: widget.child,
      ),
    );
  }
}
