import 'package:flutter/material.dart';

/// Keeps a dragged preview up and to the left of the finger so the thumb never
/// covers it, and inside the screen near the edges. With no room on the left it
/// is pushed in from the edge but stays above the finger.
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

/// Gap between the finger and the preview's lower right corner.
const double plannerDragGap = 12;

/// Top-left of a [size] preview for a finger at [pointer]: up-left of the
/// finger; below it only when there is no room above, then clamped into [screen] with [margin].
Offset plannerDragOrigin(
  Offset pointer,
  Size size,
  Size screen, {
  double margin = 8,
}) {
  var x = pointer.dx - size.width - plannerDragGap;
  var y = pointer.dy - size.height - plannerDragGap;
  if (y < margin) y = pointer.dy + plannerDragGap * 3;
  x = x.clamp(margin, (screen.width - size.width - margin).clamp(margin, 1e9));
  y = y.clamp(
    margin,
    (screen.height - size.height - margin).clamp(margin, 1e9),
  );
  return Offset(x, y);
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
