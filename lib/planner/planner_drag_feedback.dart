import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Keeps a dragged preview just up-left of the finger (its lower right corner a few dp past it)
/// and inside the screen near the edges.
///
/// Use [anchor] as the `dragAnchorStrategy` (it records the pointer) and feed
/// [PlannerDragFeedback] with the same [PlannerDragPointer]; call [update] from
/// `onDragUpdate`.
class PlannerDragPointer extends ValueNotifier<Offset> {
  PlannerDragPointer() : super(Offset.zero);

  Offset anchor(Draggable<Object> draggable, BuildContext context, Offset p) {
    value = p;
    return Offset.zero;
  }

  void update(Offset global) => value = global;
}

/// How far the preview's lower right corner reaches past the finger, so the
/// finger rests on that corner and most of the preview stays visible.
const double plannerDragReach = 10;

/// Top-left of a [size] preview for a finger at [pointer]: just up-left of the
/// finger, clamped into [screen] with [margin].
Offset plannerDragOrigin(
  Offset pointer,
  Size size,
  Size screen, {
  double margin = 4,
}) {
  final x = pointer.dx - size.width + plannerDragReach;
  final y = pointer.dy - size.height + plannerDragReach;
  return Offset(
    x.clamp(margin, (screen.width - size.width - margin).clamp(margin, 1e9)),
    y.clamp(margin, (screen.height - size.height - margin).clamp(margin, 1e9)),
  );
}

class PlannerDragFeedback extends StatelessWidget {
  const PlannerDragFeedback({
    super.key,
    required this.pointer,
    required this.size,
    required this.child,
  });

  final PlannerDragPointer pointer;
  final Size size;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    return SizedBox(
      width: size.width,
      height: size.height,
      child: ValueListenableBuilder<Offset>(
        valueListenable: pointer,
        builder: (context, p, child) {
          // The overlay places this box's top-left at the finger.
          final origin = plannerDragOrigin(p, size, screen);
          return Transform.translate(offset: origin - p, child: child);
        },
        child: child,
      ),
    );
  }
}

/// Desktop: a drag that starts as soon as the mouse moves, without the long
/// press touch needs. Mouse only, so a finger on the same widget still
/// scrolls; wrap it around the touch [LongPressDraggable].
class PlannerMouseDraggable<T extends Object> extends Draggable<T> {
  const PlannerMouseDraggable({
    super.key,
    required super.child,
    required super.feedback,
    super.data,
    super.childWhenDragging,
    super.dragAnchorStrategy,
    super.onDragStarted,
    super.onDragUpdate,
    super.onDragEnd,
    super.maxSimultaneousDrags,
  });

  @override
  MultiDragGestureRecognizer createRecognizer(
    GestureMultiDragStartCallback onStart,
  ) => ImmediateMultiDragGestureRecognizer(
    supportedDevices: const {PointerDeviceKind.mouse},
  )..onStart = onStart;
}
