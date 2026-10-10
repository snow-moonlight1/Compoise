import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Smallest scale applied when pulling a one-character last line back up.
///
/// Below this, a real second line stays a second line.
const double kOrphanSqueezeMinScale = 0.82;

/// True when [text] lays out to two or more lines and the last of those lines
/// is a single grapheme. That is the "一个字掉到下一行" case.
bool lastLineIsSingleGrapheme({
  required String text,
  required List<ui.TextBox> boxes,
  required TextPosition Function(Offset offset) positionAt,
}) {
  if (text.isEmpty || boxes.length < 2) return false;
  var lastTop = boxes.first.top;
  for (final box in boxes) {
    if (box.top > lastTop) lastTop = box.top;
  }
  ui.TextBox? first;
  for (final box in boxes) {
    if ((box.top - lastTop).abs() > 1.5) continue;
    if (first == null || box.left < first.left) first = box;
  }
  if (first == null) return false;
  final pos = positionAt(
    Offset(first.left + 0.5, (first.top + first.bottom) / 2),
  );
  if (pos.offset < 0 || pos.offset >= text.length) return false;
  return text.substring(pos.offset).trim().characters.length == 1;
}

/// Lays a label out a little wider, then scales it back, so a single trailing
/// character stays on the previous line.
///
/// Comic outline fits more glyphs because its buttons use less horizontal
/// padding. Neumorphic cards keep a shadow margin, so the same title is
/// narrower. This pulls that one character back up instead of clipping the
/// shadow or shrinking a paragraph that really needs another line.
class OrphanSqueeze extends SingleChildRenderObjectWidget {
  const OrphanSqueeze({
    super.key,
    required super.child,
    this.minScale = kOrphanSqueezeMinScale,
  });

  final double minScale;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderOrphanSqueeze(minScale: minScale);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderOrphanSqueeze renderObject,
  ) {
    renderObject.minScale = minScale;
  }
}

class RenderOrphanSqueeze extends RenderShiftedBox {
  RenderOrphanSqueeze({RenderBox? child, required double minScale})
    : _minScale = minScale,
      super(child);

  double _minScale;
  double get minScale => _minScale;
  set minScale(double value) {
    if (value == _minScale) return;
    _minScale = value;
    markNeedsLayout();
  }

  double _scale = 1;
  Offset _origin = Offset.zero;

  bool _subtreeHasOrphan(RenderObject node) {
    if (node is RenderParagraph) {
      try {
        final text = node.text.toPlainText();
        if (text.isEmpty) return false;
        final boxes = node.getBoxesForSelection(
          TextSelection(baseOffset: 0, extentOffset: text.length),
        );
        if (lastLineIsSingleGrapheme(
          text: text,
          boxes: boxes,
          positionAt: node.getPositionForOffset,
        )) {
          return true;
        }
      } catch (_) {
        return false;
      }
    }
    var found = false;
    node.visitChildren((child) {
      if (!found && _subtreeHasOrphan(child)) found = true;
    });
    return found;
  }

  BoxConstraints _wider(BoxConstraints constraints, double scale) {
    final maxWidth = constraints.maxWidth / scale;
    final maxHeight = constraints.hasBoundedHeight
        ? math.max(constraints.maxHeight / scale, constraints.maxHeight)
        : double.infinity;
    return BoxConstraints(
      minWidth: 0,
      maxWidth: maxWidth.isFinite ? maxWidth : double.infinity,
      minHeight: 0,
      maxHeight: maxHeight,
    );
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      _scale = 1;
      _origin = Offset.zero;
      return;
    }
    _scale = 1;
    _origin = Offset.zero;
    if (!constraints.hasBoundedWidth || constraints.maxWidth <= 0) {
      child.layout(constraints, parentUsesSize: true);
      size = constraints.constrain(child.size);
      _origin = Alignment.center.alongSize(size) -
          Alignment.center.alongSize(child.size);
      return;
    }

    child.layout(constraints, parentUsesSize: true);
    if (_subtreeHasOrphan(child) && minScale < 1) {
      var lo = minScale;
      var hi = 1.0;
      var fitted = false;
      if (!_fits(child, constraints, minScale)) {
        lo = 1;
      } else {
        fitted = true;
        for (var i = 0; i < 8; i++) {
          final mid = (lo + hi) / 2;
          if (_fits(child, constraints, mid)) {
            lo = mid;
            fitted = true;
          } else {
            hi = mid;
          }
        }
      }
      if (fitted && lo < 0.999) {
        _scale = lo;
        child.layout(_wider(constraints, _scale), parentUsesSize: true);
      } else {
        _scale = 1;
        child.layout(constraints, parentUsesSize: true);
      }
    }

    final visual = Size(child.size.width * _scale, child.size.height * _scale);
    size = constraints.constrain(visual);
    final slack = Size(
      math.max(0, size.width - visual.width),
      math.max(0, size.height - visual.height),
    );
    _origin = Alignment.center.alongSize(slack);
  }

  bool _fits(RenderBox child, BoxConstraints constraints, double scale) {
    child.layout(_wider(constraints, scale), parentUsesSize: true);
    return !_subtreeHasOrphan(child);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    if (_scale == 1) {
      context.paintChild(child, offset + _origin);
      return;
    }
    final transform = Matrix4.identity()
      ..translate(_origin.dx, _origin.dy)
      ..scale(_scale, _scale, 1);
    context.pushTransform(needsCompositing, offset, transform, (
      context,
      offset,
    ) {
      context.paintChild(child, offset);
    });
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final child = this.child;
    if (child == null) return false;
    final transform = Matrix4.identity()
      ..translate(_origin.dx, _origin.dy)
      ..scale(_scale, _scale, 1);
    return result.addWithPaintTransform(
      transform: transform,
      position: position,
      hitTest: (BoxHitTestResult result, Offset transformed) {
        return child.hitTest(result, position: transformed);
      },
    );
  }
}
