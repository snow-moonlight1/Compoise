import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/ocr/ocr_runtime.dart';

void main() {
  test('cancelled batch retains one result per input without opening native code', () async {
    final token = OcrCancellationToken()..cancel();
    final results = await OcrRuntime(assetsRoot: 'unused').recognizeFiles(
      ['a.png', 'b.png'],
      cancellation: token,
    );
    expect(results.map((result) => result.path), ['a.png', 'b.png']);
    expect(results.every((result) => result.error == 'cancelled'), isTrue);
  });

  test('rejects batch larger than the bounded decode queue', () async {
    final runtime = OcrRuntime(assetsRoot: 'unused');
    await expectLater(runtime.recognizeFiles(List.filled(21, 'a.png')), throwsArgumentError);
  });

  final libraryPath = Platform.environment['WP17_OCR_TEST_LIBRARY'];
  final assetsRoot = Platform.environment['WP17_OCR_TEST_ASSETS'];
  final enabled = libraryPath != null && assetsRoot != null;

  test('native library returns a per-image error for unreadable PNG', () async {
    final result = (await OcrRuntime(
      assetsRoot: assetsRoot!,
      libraryPath: libraryPath!,
    ).recognizeFiles(['missing-wp17-i1.png'])).single;
    expect(result.succeeded, isFalse);
    expect(result.lines, isEmpty);
    expect(result.error, contains('cannot open image'));
  }, skip: !enabled);

  test('native call reproduces R2 text and boxes on synthetic screenshots', () async {
    final root = Directory.current.path;
    final samples = '$root/docs/evidence/wp17r2/samples/images';
    final raw = jsonDecode(File(
      '$root/docs/evidence/wp17r2/results/win/raw/ncnn-cpu-t4/all.json',
    ).readAsStringSync()) as Map<String, dynamic>;
    final reference = {
      for (final image in raw['images'] as List<dynamic>)
        File((image as Map<String, dynamic>)['path'] as String).uri.pathSegments.last:
            image,
    };
    final paths = [
      '$samples/zh_light_base.png',
      '$samples/en_light_base.png',
      '$samples/ja_light_base.png',
    ];
    final results = await OcrRuntime(
      assetsRoot: assetsRoot!,
      libraryPath: libraryPath!,
    ).recognizeFiles(paths);
    expect(results.length, paths.length);
    for (final result in results) {
      expect(result.error, isNull, reason: result.path);
      final expected = reference[File(result.path).uri.pathSegments.last]
          as Map<String, dynamic>;
      final lines = expected['lines'] as List<dynamic>;
      expect(result.width, expected['width']);
      expect(result.height, expected['height']);
      expect(result.lines.length, lines.length);
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i] as Map<String, dynamic>;
        expect(result.lines[i].text, line['text']);
        final box = line['box'] as List<dynamic>;
        for (var j = 0; j < 4; j++) {
          expect(result.lines[i].box[j], closeTo((box[j] as num).toDouble(), 1));
        }
      }
    }
  }, skip: !enabled);
}
