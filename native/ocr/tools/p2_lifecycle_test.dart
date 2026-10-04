// Opt-in only: flutter test --no-pub native/ocr/tools/p2_lifecycle_test.dart
// Requires P2_OCR_LIBRARY/P2_OCR_ASSETS. Real PNG decode/native calls; no Store.
import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/ocr/ocr_runtime.dart';
import 'package:matrixflow_native/screenshot_import/screenshot_capture.dart';

void main() {
  final library = Platform.environment['P2_OCR_LIBRARY'];
  final assets = Platform.environment['P2_OCR_ASSETS'];
  final enabled = library != null && assets != null;
  final sample = File(
    '${Directory.current.path}/docs/evidence/wp17r2/samples/images/zh_light_base.png',
  );
  PlatformFile picked(File file) => PlatformFile(
    name: file.uri.pathSegments.last,
    path: file.path,
    size: file.lengthSync(),
  );

  for (final dispose in [false, true]) {
    test(
      'real OCR finishes during ${dispose ? 'dispose' : 'cancel'}; rebuilt capture recovers',
      () async {
        final runtime = OcrRuntime(assetsRoot: assets!, libraryPath: library!);
        late ScreenshotCapture capture;
        Timer? timer;
        var started = 0;
        var finished = 0;
        capture = ScreenshotCapture.withRecognizer(
          recognize: (path, token) async {
            started++;
            // Queue the real call before scheduling cancellation. A successful
            // first result below proves it entered native work before cancel.
            final pending = runtime.recognizeFiles([path], cancellation: token);
            timer = Timer(const Duration(milliseconds: 100), () {
              if (dispose) {
                capture.dispose();
              } else {
                capture.cancel();
              }
            });
            final result = (await pending).single;
            expect(result.succeeded, isTrue);
            finished++;
            return result;
          },
        );
        try {
          final cancelled = await capture.captureFiles([
            picked(sample),
            picked(sample),
          ]);
          expect(cancelled.cancelled, isTrue);
          expect(cancelled.batch, isNull);
          expect(started, 1);
          expect(finished, 1);
        } finally {
          timer?.cancel();
          capture.dispose();
        }
        final reopened = ScreenshotCapture(runtime: runtime);
        try {
          final recovered = await reopened.captureFiles([picked(sample)]);
          expect(recovered.cancelled, isFalse);
          expect(recovered.batch!.images.single.failed, isFalse);
          expect(recovered.batch!.activeTasks, isNotEmpty);
          expect(recovered.batch!.canSubmit, isFalse);
        } finally {
          reopened.dispose();
        }
      },
      skip: !enabled,
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }
}
