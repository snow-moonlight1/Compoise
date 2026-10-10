import 'package:flutter/widgets.dart';

/// Observes a two-finger pinch without joining the one-finger drag arena.
/// Pinching in (fingers together) calls [onPinchIn]. Spreading calls [onPinchOut].
class PlannerPinch extends StatefulWidget {
  const PlannerPinch({
    super.key,
    required this.child,
    this.onPinchIn,
    this.onPinchOut,
  });

  final Widget child;
  final VoidCallback? onPinchIn;
  final VoidCallback? onPinchOut;

  @override
  State<PlannerPinch> createState() => _PlannerPinchState();
}

class _PlannerPinchState extends State<PlannerPinch> {
  final _points = <int, Offset>{};
  double? _start;
  bool _fired = false;

  void _remember(PointerEvent event) {
    _points[event.pointer] = event.position;
  }

  double _span() {
    final values = _points.values.toList();
    return (values[0] - values[1]).distance;
  }

  void _down(PointerDownEvent event) {
    _remember(event);
    if (_points.length == 2) {
      _start = _span();
      _fired = false;
    } else {
      _start = null;
    }
  }

  void _move(PointerMoveEvent event) {
    if (!_points.containsKey(event.pointer)) return;
    _remember(event);
    if (_points.length < 2 || _fired) return;
    _start ??= _span();
    final start = _start;
    if (start == null || start < 1) return;
    final ratio = _span() / start;
    if (ratio < 0.82) {
      _fired = true;
      widget.onPinchIn?.call();
    } else if (ratio > 1.18) {
      _fired = true;
      widget.onPinchOut?.call();
    }
  }

  void _up(PointerEvent event) {
    _points.remove(event.pointer);
    if (_points.length < 2) {
      _start = null;
      _fired = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: _up,
      onPointerCancel: _up,
      child: widget.child,
    );
  }
}
