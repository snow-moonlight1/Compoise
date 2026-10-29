import 'package:flutter/material.dart';

import '../models.dart';
import '../ui/motion_policy.dart';

/// Shared drag-to-reorder behavior for task lists.
///
/// A list is split into groups (one per quadrant) and each group into slots:
/// slot `i` is the gap above row `i`, slot `rows.length` the gap below the
/// last row. While a task is dragged over a row, the upper half claims the
/// slot above it and the lower half the slot below it; the claimed slot opens
/// a gap (the rows below slide down) that shows exactly where the drop lands.
/// Near the top or bottom edge of the list it scrolls, faster the closer the
/// pointer is to the edge.
mixin DropSlotHost<W extends StatefulWidget> on State<W> {
  int? dropGroup;
  int? dropSlot;
  double dropGapHeight = 0;
  bool _dropReleasePending = false;
  EdgeDraggingAutoScroller? _autoScroller;
  ScrollableState? _autoScrollable;

  /// The list's scroll controller, for edge auto-scroll.
  ScrollController get dropScrollController;

  bool acceptsDrop(Task task);

  /// True when dropping [dragged] at [slot] would leave it where it is.
  bool dropSlotIsNoop(Task dragged, int group, int slot);

  /// Drop of [task] on [group]; [slot] null means header/blank area.
  void dropAt(Task task, int group, int? slot);

  /// Pointer is over [group] (for a section highlight).
  void onDropHover(int group) {}

  /// Pointer left every target of this list.
  void onDropHoverEnd() {}

  void claimDropSlot(Task dragged, int group, int slot, double height) {
    _dropReleasePending = false;
    final noop = dropSlotIsNoop(dragged, group, slot);
    final g = noop ? null : group;
    final s = noop ? null : slot;
    final gap = noop ? dropGapHeight : height.clamp(32.0, 64.0).toDouble();
    if (g != dropGroup || s != dropSlot || gap != dropGapHeight) {
      setState(() {
        dropGroup = g;
        dropSlot = s;
        dropGapHeight = gap;
      });
    }
    onDropHover(group);
  }

  /// Header or blank area: no exact slot.
  void clearDropSlot() {
    _dropReleasePending = false;
    if (dropGroup != null || dropSlot != null) {
      setState(() {
        dropGroup = null;
        dropSlot = null;
      });
    }
  }

  /// Moving from one target to the next reports leave before the next move;
  /// wait a frame so the gap does not close and reopen in between.
  void releaseDropSlot() {
    _dropReleasePending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_dropReleasePending) return;
      clearDropSlot();
      stopDragAutoScroll();
      onDropHoverEnd();
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  /// Scrolls the list when [global] (the pointer) is near its top or bottom
  /// edge. Speed grows as the pointer gets closer to, or past, the edge.
  void dragAutoScroll(Offset global) {
    final controller = dropScrollController;
    if (!controller.hasClients || controller.positions.length != 1) return;
    final scrollable = controller.position.context;
    if (scrollable is! ScrollableState) return;
    if (!identical(scrollable, _autoScrollable)) {
      _autoScroller?.stopAutoScroll();
      _autoScrollable = scrollable;
      _autoScroller = EdgeDraggingAutoScroller(scrollable, velocityScalar: 12);
    }
    // The edge zone is half this height (40px); overlap with the viewport
    // edge sets the speed.
    _autoScroller!.startAutoScrollIfNecessary(
      Rect.fromCenter(center: global, width: 1, height: 80),
    );
  }

  void stopDragAutoScroll() => _autoScroller?.stopAutoScroll();

  void _finish(Task task, int group, int? slot) {
    stopDragAutoScroll();
    clearDropSlot();
    onDropHoverEnd();
    dropAt(task, group, slot);
  }

  /// Zero-height until it is the claimed slot; then it opens and keeps the
  /// slot while the pointer is inside it.
  Widget dropGapTarget(int group, int slot) {
    final reduce = MotionPolicy.reduceMotionOf(context);
    return DragTarget<Task>(
      onWillAcceptWithDetails: (d) => acceptsDrop(d.data),
      onMove: (d) {
        claimDropSlot(d.data, group, slot, dropGapHeight);
        dragAutoScroll(d.offset);
      },
      onLeave: (_) => releaseDropSlot(),
      onAcceptWithDetails: (d) => _finish(d.data, group, slot),
      builder: (context, _, __) => AnimatedContainer(
        key: ValueKey('drop-gap-$group-$slot'),
        duration: reduce ? Duration.zero : MotionPolicy.dropGap,
        curve: Curves.easeOutCubic,
        height: dropGroup == group && dropSlot == slot ? dropGapHeight : 0,
      ),
    );
  }

  /// Row [index] of [group]: upper half claims the slot above, lower half
  /// the slot below.
  Widget dropRowTarget(int group, int index, Widget row) {
    BuildContext? rowContext;
    return DragTarget<Task>(
      onWillAcceptWithDetails: (d) => acceptsDrop(d.data),
      onMove: (d) {
        // The feedback is anchored at the pointer, so offset is the pointer.
        dragAutoScroll(d.offset);
        final box = rowContext?.findRenderObject();
        if (box is! RenderBox || !box.hasSize) return;
        final local = box.globalToLocal(d.offset);
        final slot = local.dy < box.size.height / 2 ? index : index + 1;
        claimDropSlot(d.data, group, slot, box.size.height);
      },
      onLeave: (_) => releaseDropSlot(),
      onAcceptWithDetails: (d) =>
          _finish(d.data, group, dropGroup == group ? dropSlot : null),
      builder: (context, _, __) {
        rowContext = context;
        return row;
      },
    );
  }

  /// Gap above row [index], the row, and after the last row its trailing gap.
  Widget dropSlotRow(int group, int index, int count, Widget row) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      dropGapTarget(group, index),
      dropRowTarget(group, index, row),
      if (index == count - 1) dropGapTarget(group, count),
    ],
  );

  @override
  void dispose() {
    _autoScroller?.stopAutoScroll();
    super.dispose();
  }
}
