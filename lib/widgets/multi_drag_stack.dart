import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../models.dart';

/// True while several selected tasks are being dragged as one stack, so the
/// selected cards left on the board can dim like the single-drag ghost.
final ValueNotifier<bool> multiDragActive = ValueNotifier<bool>(false);

/// Drag feedback for a multi-selection: the cards gather under the finger
/// like a phone home-screen multi-app drag. The top card follows the pointer;
/// the cards behind trail a little, like a small train, and settle back onto
/// the stack when the pointer stops. A badge shows how many tasks move.
class MultiDragStack extends StatefulWidget {
  const MultiDragStack({
    super.key,
    required this.tasks,
    required this.cardBuilder,
    this.badgeColor,
  });

  /// Pressed task first; at most three cards are drawn.
  final List<Task> tasks;
  final Widget Function(BuildContext context, Task task) cardBuilder;
  final Color? badgeColor;

  static const visibleCards = 3;

  @override
  State<MultiDragStack> createState() => _MultiDragStackState();
}

class _MultiDragStackState extends State<MultiDragStack>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  Duration _elapsed = Duration.zero;
  Offset? _lead;
  final List<Offset> _trail = [];

  static const _gather = Duration(milliseconds: 260);

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick)..start();
  }

  void _tick(Duration now) {
    final dt = (now - _last).inMicroseconds / 1e6;
    _last = now;
    _elapsed = now;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final lead = box.localToGlobal(Offset.zero);
    _lead = lead;
    final count =
        math.min(widget.tasks.length, MultiDragStack.visibleCards) - 1;
    while (_trail.length < count) {
      _trail.add(lead);
    }
    // Each car chases the one in front with exponential easing, so a fast
    // move stretches the train and a pause folds it back together.
    final k = 1 - math.exp(-18 * dt.clamp(0, 0.1));
    var front = lead;
    for (var i = 0; i < _trail.length; i++) {
      _trail[i] = Offset.lerp(_trail[i], front, k)!;
      front = _trail[i];
    }
    setState(() {});
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gather = Curves.easeOutBack.transform(
      (_elapsed.inMicroseconds / _gather.inMicroseconds).clamp(0.0, 1.0),
    );
    final shown = widget.tasks.take(MultiDragStack.visibleCards).toList();
    final children = <Widget>[];
    for (var i = shown.length - 1; i >= 0; i--) {
      var offset = Offset(6.0 * i, 6.0 * i);
      if (i > 0 && _lead != null && i - 1 < _trail.length) {
        offset += _trail[i - 1] - _lead!;
      }
      // Cards fan out at the start and fold onto the stack.
      offset += Offset(0, 28.0 * i * (1 - gather));
      children.add(
        Transform.translate(
          offset: offset,
          child: Transform.rotate(
            angle: i == 0 ? 0 : (i.isOdd ? -0.04 : 0.04) * gather,
            child: widget.cardBuilder(context, shown[i]),
          ),
        ),
      );
    }
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ...children,
        Positioned(
          right: -10,
          top: -10,
          child: Transform.scale(
            scale: gather.clamp(0.0, 1.2),
            child: Container(
              key: const ValueKey('multi-drag-count'),
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              padding: const EdgeInsets.symmetric(horizontal: 6),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: widget.badgeColor ?? theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${widget.tasks.length}',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
