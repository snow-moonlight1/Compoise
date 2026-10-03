import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/screenshot_import/gutter_scan.dart';

import 'support/wp17_i3a_fixtures.dart';

void main() {
  test('compact transfer retains R2 checkbox geometry and checked state', () {
    for (final dark in [false, true]) {
      final rgba = bitmap(dark: dark);
      final compact = gutterLuminance(rgba, 400, 400);
      expect(compact.length, 400 * 400 ~/ 4);
      final marks = scanGutterLuminance(compact, 400, 400);
      expect(marks.map((m) => m.box), [
        [12.0, 140.0, 17.0, 16.0],
        [40.0, 200.0, 17.0, 16.0],
      ]);
      expect(marks.map((m) => m.checked), [false, true]);
      // Right-side text has no bearing on image-side checkbox evidence.
      for (var y = 0; y < 400; y++) {
        rgba.fillRange((y * 400 + 100) * 4, (y + 1) * 400 * 4, 0);
      }
      expect(gutterLuminance(rgba, 400, 400), compact);
    }
  });

  test(
    'straight alpha is composited on white and odd-width gutter is exact',
    () {
      final rgba = Uint8List(7 * 3 * 4);
      for (var i = 0; i < rgba.length; i += 4) {
        rgba[i] = 255;
        rgba[i + 3] = 128;
      }
      expect(gutterLuminance(rgba, 7, 3), [165, 165, 165]);
      rgba[3] = 0;
      expect(gutterLuminance(rgba, 7, 3).first, 255);
      expect(scanGutterLuminance(Uint8List(0), 3, 2), isEmpty);
    },
  );

  test('compact scanner rejects length and dimension boundary violations', () {
    for (final dimensions in [(0, 1), (4097, 1), (1, 8193), (4096, 3073)]) {
      expect(
        () => scanGutterLuminance(Uint8List(0), dimensions.$1, dimensions.$2),
        throwsFormatException,
      );
    }
    expect(
      () => scanGutterLuminance(Uint8List(3), 8, 2),
      throwsFormatException,
    );
    expect(() => gutterLuminance(Uint8List(3), 1, 1), throwsFormatException);
  });
}
