import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:compoise/ocr/ocr_runtime.dart';
import 'package:compoise/screenshot_import/screenshot_capture.dart';
import 'package:compoise/screenshot_import/screenshot_saf.dart';
import 'package:flutter/services.dart';

import 'support/screenshot_fixtures.dart';

// Xiaomi and many other phones save screenshots as JPG. The JPEG fixtures are
// the Chinese reference screenshot re-encoded with ImageMagick at quality 90
// (baseline and progressive).
const _png = 'test/fixtures/ocr-evaluation/samples/images/zh_light_base.png';
const _jpg = 'test/fixtures/screenshots/zh_light_base.jpg';
const _progressive = 'test/fixtures/screenshots/zh_light_base_progressive.jpg';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final raw =
      jsonDecode(
            File(
              'test/fixtures/ocr-evaluation/results/win/raw/ncnn-cpu-t4/all.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final expected = (raw['images'] as List)
      .cast<Map<String, dynamic>>()
      .firstWhere(
        (image) => (image['path'] as String).endsWith('zh_light_base.png'),
      );

  Future<List<(String, bool, String?)>> draft(String path) async {
    final capture = ScreenshotCapture.withRecognizer(
      recognize: (p, _) async => OcrImageResult.fromJson(p, expected),
    );
    final batch = (await capture.captureFiles([picked(File(path))])).batch!;
    expect(batch.images.single.error, isNull, reason: path);
    return [
      for (final task in batch.activeTasks)
        (task.title, task.checked, task.dueText),
    ];
  }

  test('JPEG screenshots (baseline and progressive) give the PNG draft, '
      'including the gutter checkbox marks', () async {
    final fromPng = await draft(_png);
    expect(fromPng, isNotEmpty);
    expect(fromPng.any((task) => task.$2), isTrue);
    expect(await draft(_jpg), fromPng);
    expect(await draft(_progressive), fromPng);
  });

  test('.jpeg extension is accepted and the picker offers JPG', () async {
    final temp = await Directory.systemTemp.createTemp('jpeg-ext-');
    addTearDown(() => temp.delete(recursive: true));
    final copy = await File(_jpg).copy('${temp.path}/Screenshot.JPEG');
    expect(await draft(copy.path), await draft(_png));
    expect(screenshotExtensions, containsAll(['png', 'jpg', 'jpeg']));
  });

  test('JPEG size limits and broken headers fail per image', () async {
    final temp = await Directory.systemTemp.createTemp('jpeg-bad-');
    addTearDown(() => temp.delete(recursive: true));
    Uint8List sof(int width, int height) => Uint8List.fromList([
      0xff, 0xd8, // SOI
      0xff, 0xe0, 0x00, 0x04, 0x00, 0x00, // APP0 stub
      0xff, 0xc0, 0x00, 0x0b, 0x08, //
      height >> 8, height & 0xff, width >> 8, width & 0xff, //
      0x01, 0x01, 0x11, 0x00,
      0xff, 0xd9,
    ]);
    final wide = await File(
      '${temp.path}/wide.jpg',
    ).writeAsBytes(sof(5000, 100));
    final truncated = await File(
      '${temp.path}/cut.jpg',
    ).writeAsBytes([0xff, 0xd8, 0xff, 0xe0, 0x00]);
    var calls = 0;
    final capture = ScreenshotCapture.withRecognizer(
      recognize: (p, _) async {
        calls++;
        return result(p, []);
      },
    );
    final batch = (await capture.captureFiles([
      picked(wide),
      picked(truncated),
    ])).batch!;
    expect(batch.images[0].error, contains('4096×8192'));
    expect(batch.images[1].error, contains('Invalid JPEG'));
    expect(calls, 0);
  });

  test('Android SAF keeps the staged file type in the name', () async {
    const channel = MethodChannel('test/saf-jpeg');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'pick') return {'session': 's', 'count': 1};
          return {'path': '/cache/session/image-0.jpg', 'bytes': 10};
        });
    final saf = ScreenshotSaf(channel: channel);
    await saf.pick();
    expect((await saf.load(0)).name, 'image-0.jpg');
  });

  final library = Platform.environment['WP17_OCR_TEST_LIBRARY'];
  final assets = Platform.environment['WP17_OCR_TEST_ASSETS'];
  test(
    'native OCR reads the JPEG screenshot the same as the PNG',
    () async {
      final capture = ScreenshotCapture(
        runtime: OcrRuntime(assetsRoot: assets!, libraryPath: library!),
      );
      Future<List<String>> titles(String path) async {
        final batch = (await capture.captureFiles([picked(File(path))])).batch!;
        expect(batch.images.single.error, isNull, reason: path);
        return batch.activeTasks.map((task) => task.title).toList();
      }

      final png = await titles(_png);
      expect(png, isNotEmpty);
      expect(await titles(_jpg), png);
      expect(await titles(_progressive), png);
    },
    skip: library == null || assets == null,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
