import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/screenshot_import/screenshot_backend.dart';
import 'package:matrixflow_native/screenshot_import/screenshot_capture.dart';
import 'package:matrixflow_native/screenshot_import/screenshot_saf.dart';
import 'package:matrixflow_native/ocr/ocr_runtime.dart';

import 'support/wp17_i3a_fixtures.dart' as f;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('wp17-i3b-');
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test(
    'ordered per-image failures, progress and immediate release, duplicates retained as hints',
    () async {
      final released = <int>[], progress = <int>[];
      final capture = ScreenshotCapture.withRecognizer(
        recognize: (path, token) async =>
            f.result(path, [f.line('Task', 38, 138)]),
      );
      final result = await capture.captureSources(
        3,
        load: (index) async {
          if (index > 0) expect(released, contains(index - 1));
          if (index == 1) {
            throw const ScreenshotInputFailure('screenshotImportSafFileLimit');
          }
          final file = await File(
            '${directory.path}/image-$index.png',
          ).writeAsBytes(f.png());
          return f.picked(file);
        },
        release: (index) async {
          released.add(index);
          final file = File('${directory.path}/image-$index.png');
          if (await file.exists()) await file.delete();
        },
        onProgress: (done, total) {
          expect(total, 3);
          progress.add(done);
        },
      );
      expect(progress, [1, 2, 3]);
      expect(released, [0, 1, 2]);
      expect(directory.listSync(), isEmpty);
      expect(result.batch!.images.map((image) => image.id), [
        'image-1',
        'image-2',
        'image-3',
      ]);
      expect(result.batch!.images[1].error, 'screenshotImportSafFileLimit');
      expect(result.batch!.duplicates.length, 1);
      expect(result.batch!.canSubmit, false);
    },
  );

  test(
    'cancel during native work waits for its finish before release and suppresses draft',
    () async {
      final entered = Completer<void>(), gate = Completer<void>();
      var released = false;
      final file = await File(
        '${directory.path}/image.png',
      ).writeAsBytes(f.png());
      final capture = ScreenshotCapture.withRecognizer(
        recognize: (path, token) async {
          entered.complete();
          await gate.future;
          expect(await file.exists(), true);
          return f.result(path, [f.line('Task', 38, 138)]);
        },
      );
      final pending = capture.captureSources(
        2,
        load: (i) async {
          expect(i, 0);
          return f.picked(file);
        },
        release: (i) async {
          released = true;
          await file.delete();
        },
      );
      await entered.future;
      capture.dispose();
      expect(released, false);
      gate.complete();
      expect((await pending).cancelled, true);
      expect(released, true);
    },
  );

  test('cleanup failure cannot return a usable draft', () async {
    final file = await File(
      '${directory.path}/image.png',
    ).writeAsBytes(f.png());
    final capture = ScreenshotCapture.withRecognizer(
      recognize: (path, token) async => f.result(path, []),
    );
    await expectLater(
      capture.captureSources(
        1,
        load: (_) async => f.picked(file),
        release: (_) async => throw StateError('cleanup'),
      ),
      throwsStateError,
    );
  });

  test(
    'absent local models and second availability check prevent opening picker',
    () async {
      var picks = 0;
      final capture = ScreenshotCapture.withRecognizer(
        recognize: (p, t) async => f.result(p, []),
        picker: () async {
          picks++;
          return [];
        },
      );
      final backend = LocalScreenshotBackend(
        android: false,
        runtime: OcrRuntime(assetsRoot: '${directory.path}/absent'),
        capture: capture,
      );
      expect(await backend.availability(), 'ModelsMissing');
      expect(
        (await backend.capture((a, b) {})).error,
        'screenshotImportModelsMissing',
      );
      expect(picks, 0);
      await backend.dispose();
    },
  );

  test('dispose during availability cannot open a late picker', () async {
    final entered = Completer<void>(), gate = Completer<String?>();
    var picks = 0;
    final backend = LocalScreenshotBackend(
      android: false,
      availability: () {
        entered.complete();
        return gate.future;
      },
      capture: ScreenshotCapture.withRecognizer(
        recognize: (p, t) async => f.result(p, []),
        picker: () async {
          picks++;
          return null;
        },
      ),
    );
    final pending = backend.capture((a, b) {});
    await entered.future;
    final disposing = backend.dispose();
    gate.complete(null);
    expect((await pending).cancelled, true);
    await disposing;
    expect(picks, 0);
  });

  test(
    'SAF channel stages individually; close failure keeps ownership for retry',
    () async {
      const channel = MethodChannel('wp17-i3b-test');
      final calls = <String>[];
      var fail = true;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.method);
            if (call.method == 'pick') {
              return {'session': 'synthetic', 'count': 2};
            }
            if (call.method == 'stage') {
              return {'error': 'screenshotImportSafPng'};
            }
            if (call.method == 'close' && fail) {
              throw PlatformException(code: 'cleanup');
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final saf = ScreenshotSaf(channel: channel);
      await saf.initialize();
      expect(await saf.pick(), 2);
      await expectLater(saf.load(0), throwsA(isA<ScreenshotInputFailure>()));
      await saf.release(0);
      await expectLater(saf.close(), throwsA(isA<PlatformException>()));
      fail = false;
      await saf.close();
      await saf.close();
      expect(calls, ['cleanup', 'pick', 'stage', 'release', 'close', 'close']);
    },
  );
  test(
    'native missing after readable model check still prevents picker',
    () async {
      final models = Directory('${directory.path}/ncnn');
      await models.create();
      for (final name in [
        'ppocrv5_dict.txt',
        'PP_OCRv5_mobile_det.ncnn.param',
        'PP_OCRv5_mobile_det.ncnn.bin',
        'PP_OCRv5_mobile_rec.ncnn.param',
        'PP_OCRv5_mobile_rec.ncnn.bin',
      ]) {
        await File('${models.path}/$name').writeAsString('synthetic');
      }
      var picks = 0;
      final backend = LocalScreenshotBackend(
        android: false,
        runtime: OcrRuntime(
          assetsRoot: directory.path,
          libraryPath: '${directory.path}/missing.dll',
        ),
        capture: ScreenshotCapture.withRecognizer(
          recognize: (p, t) async => f.result(p, []),
          picker: () async {
            picks++;
            return null;
          },
        ),
      );
      expect(await backend.availability(), 'NativeMissing');
      expect(
        (await backend.capture((a, b) {})).error,
        'screenshotImportNativeMissing',
      );
      expect(picks, 0);
      await backend.dispose();
    },
  );
  test(
    'untrusted source count is bounded before allocation or reads',
    () async {
      var reads = 0;
      final capture = ScreenshotCapture.withRecognizer(
        recognize: (p, t) async => f.result(p, []),
      );
      final result = await capture.captureSources(
        1000000000,
        load: (i) async {
          reads++;
          throw StateError('unreachable');
        },
        release: (i) async {},
      );
      expect(result.error, contains('10 PNG'));
      expect(reads, 0);
    },
  );
}
