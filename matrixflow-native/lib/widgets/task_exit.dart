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

    // 1. Refresh snapshots and fold the previous order into the new one.
    // Iterating a copy: _remove mutates _order while we walk it.
    final merged = <String>[];
    for (final id in _order.toList()) {
      if (present.contains(id)) {
        // Reappeared (undo / un-check / restored): cancel a pending exit.
        _timers.remove(id)?.cancel();
        merged.add(id);
        continue;
      }
      final snapshot = _items[id];
      if (snapshot == null || !keepIfMissing(snapshot)) {
        // Deleted, cleared or imported away: leave immediately, no snapshot.
        _remove(id);
        continue;
      }
      _timers.putIfAbsent(
        id,
        () => Timer(MotionPolicy.exitHold + MotionPolicy.exitCollapse, () {
          _remove(id);
          onChange();
        }),
      );
      merged.add(id);
    }

    // 2. Insert current items; new ones take their current index.
    final seen = merged.toSet();
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      final id = idOf(item);
      _items[id] = item;
      if (seen.contains(id)) continue;
      merged.insert(i.clamp(0, merged.length), id);
      seen.add(id);
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
    return IgnorePointer(
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
    );
  }
}
