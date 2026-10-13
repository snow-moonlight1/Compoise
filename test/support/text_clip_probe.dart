import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// One piece of text that does not fit where it is drawn.
class TextClip {
  TextClip(this.text, this.reason, this.rect);
  final String text;
  final String reason;
  final Rect rect;
  @override
  String toString() => '"$text" $reason @ ${rect.topLeft}';
}

/// Walks every [RenderParagraph] on screen and reports text that is cut:
/// laid out shorter than its glyphs, cut by maxLines without an ellipsis,
/// or drawn past the vertical edge of an enclosing clip.
///
/// Ellipsized or faded text is a deliberate single-line truncation and is
/// not reported.
List<TextClip> findTextClips(WidgetTester tester) {
  final out = <TextClip>[];
  final screen =
      Offset.zero & tester.view.physicalSize / tester.view.devicePixelRatio;
  void visit(RenderObject node) {
    if (node is RenderParagraph && node.attached && node.hasSize) {
      _check(node, screen, out);
    }
    node.visitChildren(visit);
  }

  for (final view in tester.binding.renderViews) {
    visit(view);
  }
  return out;
}

void _check(RenderParagraph p, Rect screen, List<TextClip> out) {
  final text = p.text.toPlainText().trim();
  if (text.isEmpty || p.size.isEmpty) return;
  final rect = MatrixUtils.transformRect(
    p.getTransformTo(null),
    Offset.zero & p.size,
  );
  if (!rect.overlaps(screen)) return;
  final soft =
      p.overflow == TextOverflow.ellipsis || p.overflow == TextOverflow.fade;
  if (p.didExceedMaxLines && !soft) {
    out.add(TextClip(text, 'exceeds maxLines', rect));
    return;
  }
  final needed = p.getMaxIntrinsicHeight(p.size.width);
  if (p.size.height + 0.5 < needed && !soft) {
    out.add(TextClip(text, 'height ${p.size.height} < $needed', rect));
    return;
  }
  RenderObject? node = p.parent;
  while (node != null) {
    if (node is RenderAbstractViewport || node is RenderSliver) return;
    if ((node is RenderClipRect ||
            node is RenderClipRRect ||
            node is RenderClipPath) &&
        (node as RenderBox).hasSize) {
      final clip = MatrixUtils.transformRect(
        node.getTransformTo(null),
        Offset.zero & node.size,
      );
      if (rect.top < clip.top - 0.5 || rect.bottom > clip.bottom + 0.5) {
        out.add(TextClip(text, 'outside clip $clip', rect));
      }
      return;
    }
    node = node.parent;
  }
}
