import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/experiments/neumorphic/neumorphic.dart';

import 'uiexp1_harness.dart';

Future<void> _shot(
  WidgetTester tester, {
  required String name,
  required Size size,
  required double textScale,
  required Locale locale,
  required NeuScene scene,
  bool highContrast = false,
  bool reduceMotion = false,
  Brightness brightness = Brightness.light,
}) async {
  await pumpUiexp(
    tester,
    size: size,
    textScale: textScale,
    locale: locale,
    highContrast: highContrast,
    reduceMotion: reduceMotion,
    brightness: brightness,
    home: RepaintBoundary(
      key: const Key('uiexp1-shot'),
      child: NeuGallery(initialScene: scene),
    ),
  );
  await tester.pump();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const Key('uiexp1-shot')),
  );
  final bytes = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  });
  final dir = Directory(
    '${uiexp1PrivateRoot().path}${Platform.pathSeparator}shots',
  );
  dir.createSync(recursive: true);
  final file = File('${dir.path}${Platform.pathSeparator}$name.png');
  file.writeAsBytesSync(bytes!);
  expect(file.lengthSync(), greaterThan(1000));
}

void main() {
  testWidgets('writes synthetic comparison shots outside the worktree', (
    tester,
  ) async {
    final previous = debugDisableShadows;
    debugDisableShadows = false;
    try {
      await _shot(
        tester,
        name: 'compare-light-800-zh',
        size: const Size(800, 1100),
        textScale: 1,
        locale: const Locale('zh'),
        scene: NeuScene.note,
      );
      await _shot(
        tester,
        name: 'narrow-320-zh',
        size: const Size(320, 900),
        textScale: 1,
        locale: const Locale('zh'),
        scene: NeuScene.single,
      );
      await _shot(
        tester,
        name: 'narrow-390-en-scale2',
        size: const Size(390, 900),
        textScale: 2,
        locale: const Locale('en'),
        scene: NeuScene.steps,
      );
      await _shot(
        tester,
        name: 'narrow-320-ja-dark',
        size: const Size(320, 900),
        textScale: 1,
        locale: const Locale('ja'),
        scene: NeuScene.note,
        brightness: Brightness.dark,
      );
      await _shot(
        tester,
        name: 'narrow-390-zh-contrast',
        size: const Size(390, 900),
        textScale: 1,
        locale: const Locale('zh'),
        scene: NeuScene.note,
        highContrast: true,
      );
      await _shot(
        tester,
        name: 'narrow-320-zh-scale3-motion',
        size: const Size(320, 980),
        textScale: 3,
        locale: const Locale('zh'),
        scene: NeuScene.note,
        reduceMotion: true,
      );
    } finally {
      debugDisableShadows = previous;
    }
  });
}
