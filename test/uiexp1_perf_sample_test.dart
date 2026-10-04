import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/experiments/neumorphic/neumorphic.dart';

import 'uiexp1_harness.dart';

Future<int> _pumpFrames(WidgetTester tester) async {
  final watch = Stopwatch()..start();
  await tester.fling(find.byType(ListView), const Offset(0, -500), 2000);
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  watch.stop();
  return watch.elapsedMicroseconds;
}

int _shadowLayers(WidgetTester tester) {
  var count = 0;
  for (final box in tester.widgetList<DecoratedBox>(
    find.byType(DecoratedBox),
  )) {
    final decoration = box.decoration;
    if (decoration is BoxDecoration && decoration.boxShadow != null) {
      count += decoration.boxShadow!.length;
    }
  }
  return count;
}

void main() {
  testWidgets('shadow sample scrolls and records frame time', (tester) async {
    final previous = debugDisableShadows;
    debugDisableShadows = false;
    try {
      Widget list({required bool neumorphic}) {
        return ListView.builder(
          itemCount: 40,
          itemBuilder: (context, index) => neumorphic
              ? NeuButton(
                  label: '保存 $index',
                  role: NeuRole.primary,
                  onPressed: () {},
                )
              : FilledButton(onPressed: () {}, child: Text('保存 $index')),
        );
      }

      Future<({int micros, int shadows, double pixels})> sample({
        required bool neumorphic,
        required bool highContrast,
      }) async {
        await pumpUiexp(
          tester,
          size: const Size(400, 320),
          highContrast: highContrast,
          home: Scaffold(body: list(neumorphic: neumorphic)),
        );
        final micros = await _pumpFrames(tester);
        final pixels = tester
            .state<ScrollableState>(find.byType(Scrollable))
            .position
            .pixels;
        return (micros: micros, shadows: _shadowLayers(tester), pixels: pixels);
      }

      final material = await sample(neumorphic: false, highContrast: false);
      final neu = await sample(neumorphic: true, highContrast: false);
      final quiet = await sample(neumorphic: true, highContrast: true);

      expect(material.pixels, greaterThan(0));
      expect(neu.pixels, greaterThan(0));
      expect(quiet.pixels, greaterThan(0));
      expect(neu.shadows, greaterThan(0));
      expect(quiet.shadows, 0);

      final report = [
        'widget-test software frames, debugDisableShadows=false',
        'viewport=400x320 items=40 fling plus 20 frames',
        'material_micros=${material.micros} material_shadow_layers=${material.shadows} material_pixels=${material.pixels}',
        'neumorphic_micros=${neu.micros} neumorphic_shadow_layers=${neu.shadows} neumorphic_pixels=${neu.pixels}',
        'high_contrast_micros=${quiet.micros} high_contrast_shadow_layers=${quiet.shadows} high_contrast_pixels=${quiet.pixels}',
        '',
      ].join('\n');
      final out = File(
        '${uiexp1PrivateRoot().path}${Platform.pathSeparator}perf-sample.txt',
      );
      out.writeAsStringSync(report);
    } finally {
      debugDisableShadows = previous;
    }
  });
}
