import 'dart:async';

import 'package:flutter/material.dart';

import '../ui/motion_policy.dart';

/// One row of a list that may still be showing a snapshot of a task that has
/// already left the underlying query.
class ExitEntry<T> {
  const ExitEntry(this.item, {this.exiting = false});

  final T item;

  /// True while the row is only a short-lived display snapshot.
  final bool exiting;
}

typedef ExitIdOf<T> = String Function(T item);

/// Keeps a short-lived *display snapshot* of rows that just vanished from a
/// query so the completion strikethrough can finish before the row leaves.
///
/// Rules (UX06, plan 5.2):
/// * Read-only: the real task state is already persisted by the store; the
///   timer callback never writes a task back.
/// * A row is retained only while [keepIfMissing] reports the underlying task
///   still exists, so delete / clear board / import drop it at once.
/// * Changing [epochKey] (board switch, import, generation bump) clears
///   everything; so does [dispose].
/// * Undo or un-completing makes the row reappear in [items], which cancels
///   its pending exit.
/// * Reduced motion retains nothing: no waiting on a hide timer.
class ExitRetention<T> {
  ExitRetention({required this.onChange, this.enabled = true});

  final VoidCallback onChange;
  final bool enabled;

  String? _epochKey;
  final List<String> _order = <String>[];
  final Map<String, T> _items = <String, T>{};
  final Map<String, Timer> _timers = <String, Timer>{};

  bool get isEmpty => _order.isEmpty;

  void dispose() => clear();

  void clear() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    _order.clear();
    _items.clear();
  }

  /// Merges [items] with rows that are still leaving, preserving positions.
  List<ExitEntry<T>> sync({
    required List<T> items,
    required String epochKey,
    required ExitIdOf<T> idOf,
    required bool Function(T item) keepIfMissing,
    required bool reduceMotion,
  }) {
    if (!enabled || reduceMotion) {
      clear();
      return [for (final item in items) ExitEntry<T>(item)];
    }
    if (_epochKey != epochKey) {
      clear();
      _epochKey = epochKey;
    }

    final present = <String>{for (final item in items) idOf(item)};
    final liveIds = [for (final item in items) idOf(item)];

    // Drop snapshots that no longer exist; cancel a pending exit if the
    // row reappeared (undo / un-check / restore).
    for (final id in _order.toList()) {
      if (present.contains(id)) {
        _timers.remove(id)?.cancel();
        continue;
      }
      final snapshot = _items[id];
      if (snapshot == null || !keepIfMissing(snapshot)) {
        _remove(id);
      }
    }

    final exiting = <String>[
      for (final id in _order)
        if (!present.contains(id)) id,
    ];
    for (final id in exiting) {
      _timers.putIfAbsent(
        id,
        () => Timer(MotionPolicy.exitHold + MotionPolicy.exitCollapse, () {
          _remove(id);
          onChange();
        }),
      );
    }

    // Live rows follow the current query order. Exiting snapshots are
    // re-inserted at their last visual index so a reorder of still-present
    // items is not frozen by the retention cache.
    final merged = List<String>.from(liveIds);
    for (final id in exiting) {
      merged.insert(_order.indexOf(id).clamp(0, merged.length), id);
    }

    for (final item in items) {
      _items[idOf(item)] = item;
    }

    _order
      ..clear()
      ..addAll(merged);

    return [
      for (final id in _order)
        ExitEntry<T>(_items[id] as T, exiting: !present.contains(id)),
    ];
  }

  void _remove(String id) {
    _timers.remove(id)?.cancel();
    _order.remove(id);
    _items.remove(id);
  }
}

/// Wraps a list row so it can leave with visible feedback: it holds still for
/// the strikethrough, then collapses and fades out.
///
/// The wrapper is always in the tree with a constant structure and only flips
/// [exiting], so the row's own element (and its entrance/strikethrough state)
/// survives the transition instead of being re-inflated. While leaving, hit
/// testing, focus and semantics are excluded so the snapshot can never be
/// operated on or announced twice.
class ExitingRow extends StatefulWidget {
  const ExitingRow({
    super.key,
    required this.exiting,
    required this.child,
  });

  final bool exiting;
  final Widget child;

  @override
  State<ExitingRow> createState() => _ExitingRowState();
}

class _ExitingRowState extends State<ExitingRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: MotionPolicy.exitCollapse,
    value: 1,
  );
  Timer? _hold;

  @override
  void didUpdateWidget(covariant ExitingRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.exiting == oldWidget.exiting) return;
    _hold?.cancel();
    _hold = null;
    if (widget.exiting) {
      _hold = Timer(MotionPolicy.exitHold, () {
        if (!mounted) return;
        _controller.reverse();
      });
    } else {
      // Came back (undo / un-check / restore): cancel a pending collapse.
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _hold?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The enclosing scope receives focus on exit. Returning rows become
    // traversable again without stealing the user's current focus.
    return ExcludeFocus(
      excluding: widget.exiting,
      child: IgnorePointer(
      ignoring: widget.exiting,
      child: ExcludeSemantics(
        excluding: widget.exiting,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) => SizeTransition(
            sizeFactor: _controller,
            axisAlignment: -1,
            child: Opacity(
              opacity: _controller.value.clamp(0.0, 1.0),
              child: child,
            ),
          ),
          child: widget.child,
        ),
      ),
      ),
    );
  }
}
