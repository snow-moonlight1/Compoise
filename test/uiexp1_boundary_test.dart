import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/neumorphic_demo.dart' as demo;

void main() {
  test('production libraries do not import the experiment', () {
    final hits = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final norm = entity.path.replaceAll('\\', '/');
      if (norm.contains('/lib/experiments/neumorphic/')) continue;
      final text = entity.readAsStringSync();
      if (text.contains('experiments/neumorphic')) hits.add(norm);
    }
    expect(hits, isEmpty);
  });

  test('pubspec and the production entry stay free of the experiment', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final main = File('lib/main.dart').readAsStringSync();
    expect(pubspec.contains('neumorphic'), isFalse);
    expect(main.contains('experiments/neumorphic'), isFalse);
    expect(main.contains('Future<void> main('), isTrue);
  });

  test('demo entry points at the gallery and stays callable', () {
    final source = File('tool/neumorphic_demo.dart').readAsStringSync();
    expect(source.contains('experiments/neumorphic/neumorphic.dart'), isTrue);
    expect(source.contains('void main('), isTrue);
    expect(demo.main, isA<void Function()>());
  });
}
