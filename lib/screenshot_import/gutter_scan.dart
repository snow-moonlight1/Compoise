import 'dart:math' as math;
import 'dart:typed_data';

/// Image-side evidence only. OCR glyphs never supply a checkbox state.
final class GutterMark {
  const GutterMark(this.box, this.fill);
  final List<double> box;
  final double fill;
  bool get checked => fill > 0.5;
}

/// Bounded, linear connected-component scan of the left quarter of a bitmap.
/// The capture module checks dimensions before allocating/decoding this bitmap.
/// Thresholds and isolation gaps follow wp17r2/tools/wp17r2lib.py.
List<GutterMark> scanGutter(Uint8List rgba, int width, int height) {
  if (width <= 0 ||
      height <= 0 ||
      width > 4096 ||
      height > 8192 ||
      width * height > 12 * 1024 * 1024 ||
      rgba.length != width * height * 4) {
    throw const FormatException('invalid bounded bitmap');
  }
  final gutter = width ~/ 4;
  if (gutter == 0) return [];
  final gray = Uint8List(gutter * height);
  final histogram = List<int>.filled(256, 0);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < gutter; x++) {
      final p = (y * width + x) * 4;
      final alpha = rgba[p + 3];
      final luminance =
          (299 * rgba[p] + 587 * rgba[p + 1] + 114 * rgba[p + 2] + 500) ~/ 1000;
      final value = (luminance * alpha + 255 * (255 - alpha) + 127) ~/ 255;
      gray[y * gutter + x] = value;
      histogram[value]++;
    }
  }
  var cumulative = 0;
  var background = 0;
  for (; background < 255; background++) {
    cumulative += histogram[background];
    if (cumulative > gray.length ~/ 2) break;
  }
  final ink = Uint8List(gray.length);
  for (var p = 0; p < gray.length; p++) {
    ink[p] = (gray[p] - background).abs() > 40 ? 1 : 0;
  }
  final visited = Uint8List(ink.length);
  final queue = Int32List(ink.length);
  final marks = <GutterMark>[];
  for (var start = 0; start < ink.length; start++) {
    if (ink[start] == 0 || visited[start] != 0) continue;
    var head = 0;
    var tail = 1;
    queue[0] = start;
    visited[start] = 1;
    var x0 = start % gutter;
    var x1 = x0;
    var y0 = start ~/ gutter;
    var y1 = y0;
    void visit(int p) {
      if (ink[p] != 0 && visited[p] == 0) {
        visited[p] = 1;
        queue[tail++] = p;
      }
    }

    while (head < tail) {
      final p = queue[head++];
      final x = p % gutter;
      final y = p ~/ gutter;
      x0 = math.min(x0, x);
      x1 = math.max(x1, x);
      y0 = math.min(y0, y);
      y1 = math.max(y1, y);
      if (x > 0) visit(p - 1);
      if (x + 1 < gutter) visit(p + 1);
      if (y > 0) visit(p - gutter);
      if (y + 1 < height) visit(p + gutter);
    }
    // R2 uses exclusive x1 and adds one, so keep its measured box convention.
    final bw = x1 - x0 + 2;
    final bh = y1 - y0 + 1;
    if (bw < .022 * width ||
        bw > .075 * width ||
        bh < .022 * width ||
        bh > .075 * width ||
        math.max(bw, bh) > 1.6 * math.min(bw, bh)) {
      continue;
    }
    final gap = math.max(6, (.35 * bw).round());
    var isolated = true;
    for (var y = y0; y <= y1 && isolated; y++) {
      for (var x = x1 + 2; x < math.min(gutter, x1 + 2 + gap); x++) {
        if (ink[y * gutter + x] != 0) isolated = false;
      }
      if (x0 - gap > 0) {
        for (var x = math.max(0, x0 - gap); x < x0; x++) {
          if (ink[y * gutter + x] != 0) isolated = false;
        }
      }
    }
    if (!isolated) continue;
    if (marks.length == 2048) {
      throw const FormatException('too many gutter marks');
    }
    marks.add(
      GutterMark([
        x0.toDouble(),
        y0.toDouble(),
        bw.toDouble(),
        bh.toDouble(),
      ], (tail / (bw * bh) * 1000).round() / 1000),
    );
  }
  marks.sort((a, b) {
    final vertical = a.box[1].compareTo(b.box[1]);
    return vertical != 0 ? vertical : a.box[0].compareTo(b.box[0]);
  });
  return marks;
}
