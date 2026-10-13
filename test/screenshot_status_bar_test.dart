// Real screenshot import: plain list lines are kept and included by default;
// only the phone status bar (time, signal, battery) is skipped.
//
// The OCR lines in test/fixtures/screenshots/*.ocr.json were recorded from the
// PNGs next to them with the shipped PP-OCRv5 models. To re-record (or run the
// live OCR leg) on Linux:
//
//   COMPOISE_OCR_LIB=/path/to/libcompoise_ocr.so \
//   COMPOISE_OCR_MODELS=~/.local/share/com.compoise.app/ocr-models/v1 \
//   flutter test test/screenshot_status_bar_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:compoise/import_preview/draft_model.dart';
import 'package:compoise/ocr/ocr_runtime.dart';
import 'package:compoise/screenshot_import/gutter_scan.dart';
import 'package:compoise/screenshot_import/screenshot_adapter.dart';

const _dir = 'test/fixtures/screenshots';
const _tasks = ['周五前提交季度报告', '给妈妈打电话', '预约牙医检查', '买牛奶和鸡蛋'];

Future<OcrImageResult> _ocr(String name) async {
  final png = '$_dir/$name.png';
  final recorded = File('$_dir/$name.ocr.json');
  final lib = Platform.environment['COMPOISE_OCR_LIB'];
  final models = Platform.environment['COMPOISE_OCR_MODELS'];
  if (lib != null && models != null) {
    final live = (await OcrRuntime(
      assetsRoot: models,
      libraryPath: lib,
    ).recognizeFiles([png])).single;
    expect(live.error, isNull);
    recorded.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'width': live.width,
        'height': live.height,
        'lines': [
          for (final line in live.lines)
            {'text': line.text, 'box': line.box, 'score': line.score},
        ],
      }),
    );
    return live;
  }
  return OcrImageResult.fromJson(
    png,
    jsonDecode(recorded.readAsStringSync()) as Map<String, dynamic>,
  );
}

Future<List<GutterMark>> _marks(String name) async {
  final codec = await ui.instantiateImageCodec(
    File('$_dir/$name.png').readAsBytesSync(),
  );
  final frame = await codec.getNextFrame();
  final image = frame.image;
  final pixels = await image.toByteData(
    format: ui.ImageByteFormat.rawStraightRgba,
  );
  final marks = scanGutter(
    pixels!.buffer.asUint8List(),
    image.width,
    image.height,
  );
  image.dispose();
  codec.dispose();
  return marks;
}

Future<DraftImage> _import(WidgetTester tester, String name) async {
  late Map<String, dynamic> wire;
  await tester.runAsync(() async {
    wire = const ScreenshotDraftAdapter().adapt(
      id: name,
      result: await _ocr(name),
      marks: await _marks(name),
    );
  });
  return DraftBatch.fromJson({
    'schema': 'wp17r2-draft/1',
    'images': [wire],
  }).images.single;
}

void main() {
  testWidgets('a plain Chinese list imports every line, included', (
    tester,
  ) async {
    final image = await _import(tester, 'zh-plain-list');
    expect(image.tasks.map((task) => task.title), _tasks);
    expect(image.tasks.every((task) => !task.excluded), isTrue);
  });

  testWidgets('the status bar is skipped, list lines are included', (
    tester,
  ) async {
    final image = await _import(tester, 'zh-list-with-status-bar');
    final included = image.tasks.where((task) => !task.excluded).toList();
    expect(included.map((task) => task.title), _tasks);
    final skipped = image.tasks.where((task) => task.excluded).toList();
    expect(skipped, isNotEmpty);
    for (final task in skipped) {
      expect(task.reviewReasons, ['dropped chrome']);
    }
    expect(skipped.map((task) => task.title).join(' '), contains('9:41'));
  });
}
