import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:matrixflow_native/screenshot_import/screenshot_backend.dart';
import 'package:matrixflow_native/screenshot_import/screenshot_capture.dart';
import 'package:matrixflow_native/screenshot_import/screenshot_saf.dart';

import 'support/wp17_i3a_fixtures.dart' as f;

void main() {
  const enabled = bool.fromEnvironment('WP17_SAF_DEVICE');
  if (!enabled) {
    test(
      'Android SAF device smoke requires WP17_SAF_DEVICE',
      () {},
      skip: true,
    );
    return;
  }
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'actual ACTION_OPEN_DOCUMENT selection and owned-cache cleanup with injected OCR',
    (tester) async {
      expect(Platform.isAndroid, true);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Text('WP17 SAF synthetic PNG test')),
        ),
      );
      await tester.runAsync(() async {
        final cache = await getTemporaryDirectory();
        final unrelated = File(
          '${cache.path}/file_picker/wp17-i3b-sentinel.txt',
        );
        await unrelated.parent.create(recursive: true);
        await unrelated.writeAsString('synthetic sentinel');
        final leftover = Directory(
          '${cache.path}/wp17-screenshot-import/session-00000000-0000-0000-0000-000000000000',
        );
        await leftover.create(recursive: true);
        await File('${leftover.path}/image-0.png').writeAsBytes(f.png());
        final backend = LocalScreenshotBackend(
          android: true,
          saf: ScreenshotSaf(),
          availability: () async => null,
          capture: ScreenshotCapture.withRecognizer(
            recognize: (path, token) async =>
                f.result(path, [f.line('Synthetic task', 38, 138)]),
          ),
        );
        try {
          expect(await backend.availability(), isNull);
          expect(await leftover.exists(), false);
          // Static coordination marker only; never print URIs, paths or OCR data.
          debugPrint('WP17_SAF_PICK_READY');
          final result = await backend.capture((done, total) {});
          expect(result.cancelled, false);
          expect(result.error, isNull);
          expect(result.batch!.images.length, 3);
          expect(result.batch!.images.where((image) => image.failed).length, 1);
          expect(
            result.batch!.images.singleWhere((image) => image.failed).error,
            'screenshotImportSafPng',
          );
          expect(result.batch!.duplicates.length, 1);
          expect(result.batch!.canSubmit, false);
          final owned = Directory('${cache.path}/wp17-screenshot-import');
          expect(await owned.list().toList(), isEmpty);
          expect(await unrelated.readAsString(), 'synthetic sentinel');
          debugPrint('WP17_SAF_CANCEL_READY');
          final cancelled = await backend.capture((done, total) {});
          expect(cancelled.cancelled, true);
          expect(cancelled.batch, isNull);
          expect(await owned.list().toList(), isEmpty);
          // Dispose while the real system picker is pending. The bridge closes
          // the activity it launched and prevents a late selection from escaping.
          debugPrint('WP17_SAF_DISPOSE_READY');
          final pending = backend.capture((done, total) {});
          await Future<void>.delayed(const Duration(seconds: 2));
          await backend.dispose();
          expect((await pending).cancelled, true);
          expect(await owned.list().toList(), isEmpty);
          debugPrint('WP17_SAF_DISPOSE_DONE');
        } finally {
          await backend.dispose();
          await unrelated.delete();
        }
      });
    },
  );
}
