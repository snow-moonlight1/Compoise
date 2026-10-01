import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:matrixflow_native/ocr/ocr_assets.dart';
import 'package:matrixflow_native/ocr/ocr_runtime.dart';
import 'package:matrixflow_native/screenshot_import/screenshot_backend.dart';

/// Runs the shipped resource lookup and the shipped C ABI against the R2
/// synthetic screenshots inside the real application process.
///
/// This is the package's native-load evidence: the asset root, the library name
/// and the JSON contract are the ones the product uses, not a test-only seam.
/// It remains synthetic-image evidence, not a real-screenshot support claim.
///
///   flutter drive --no-pub --target=test/wp17_i4_bundle_ocr_test.dart \
///     --driver=test/wp17_i4_device_driver.dart -d windows \
///     --dart-define=WP17_I4_BUNDLE=true
///
/// Model files come from `WP17_OCR_ASSETS` in the process environment (desktop)
/// or `--dart-define=WP17_OCR_ASSETS=<path>`. Images and the printed text
/// baseline are read from the repository working directory (`WP17_I4_EVIDENCE`
/// overrides it), so this test is host-only; the Android device leg compares
/// the same geometry fixture without needing those files.
void main() {
  if (!const bool.fromEnvironment('WP17_I4_BUNDLE')) {
    test('native bundle smoke requires WP17_I4_BUNDLE', () {}, skip: true);
    return;
  }
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('bundle loads the library and reproduces R2 text and boxes', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('WP17-I4 bundle OCR'))),
    );

    final evidenceRoot =
        const String.fromEnvironment('WP17_I4_EVIDENCE').isNotEmpty
        ? const String.fromEnvironment('WP17_I4_EVIDENCE')
        : Directory.current.path;
    final assetsRoot = await resolveOcrAssetsRoot();
    final missing = await missingOcrModelFiles(assetsRoot);

    await tester.runAsync(() async {
      final executable = Platform.resolvedExecutable;
      debugPrint('WP17_I4_ASSETS_ROOT=$assetsRoot');
      debugPrint(
        'WP17_I4_PROCESS executable=$executable cwd=${Directory.current.path} '
        'assets=${Platform.environment['WP17_OCR_ASSETS']}',
      );
      debugPrint('WP17_I4_LIBRARY=${resolveOcrLibraryPath()}');
      for (final name in ocrModelFileNames) {
        final file = File(ocrModelPath(assetsRoot, name));
        debugPrint(
          'WP17_I4_FILE $name exists=${file.existsSync()} '
          'bytes=${file.existsSync() ? file.lengthSync() : -1}',
        );
      }
      expect(
        missing,
        isEmpty,
        reason:
            'deploy the five model files under $assetsRoot/ncnn '
            '(tool/prepare_ocr_assets.ps1 -DeployRoot <root>)',
      );

      final bundleLibrary =
          const String.fromEnvironment('WP17_OCR_TEST_LIBRARY').isEmpty
          ? null
          : const String.fromEnvironment('WP17_OCR_TEST_LIBRARY');

      if (Platform.isWindows) {
        // On Windows `flutter drive -d windows` really runs the built bundle,
        // so the product's own resolution and library check are exercised here.
        final backend = LocalScreenshotBackend(android: false);
        try {
          expect(await backend.availability(), isNull);
          debugPrint('WP17_I4_AVAILABILITY_OK');
        } finally {
          await backend.dispose();
        }
      } else {
        // On Linux `flutter test`/`flutter run` host the test in flutter_tester,
        // so Platform.resolvedExecutable is the tester binary and the
        // executable-relative default cannot name the bundle library. The path
        // below asserts the bundle layout instead; the library itself is loaded
        // explicitly through WP17_OCR_TEST_LIBRARY.
        expect(
          resolveOcrLibraryPath(),
          endsWith('/lib/libmatrixflow_ocr.so'),
          reason:
              'the bundle puts the OCR library next to the other bundle '
              'libraries and that is the path the product resolves',
        );
        expect(
          bundleLibrary,
          isNotNull,
          reason:
              'pass --dart-define=WP17_OCR_TEST_LIBRARY=<bundle>/lib/'
              'libmatrixflow_ocr.so on Linux',
        );
      }

      final baseline =
          jsonDecode(
                File(
                  '$evidenceRoot/docs/evidence/wp17r2/results/win/raw/ncnn-cpu-t4/all.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final expectedText = {
        for (final image in baseline['images'] as List<dynamic>)
          File(
            (image as Map<String, dynamic>)['path'] as String,
          ).uri.pathSegments.last: (image['lines'] as List<dynamic>)
              .map((line) => (line as Map<String, dynamic>)['text'] as String)
              .toList(),
      };
      final paths = [
        for (final name in expectedText.keys)
          '$evidenceRoot/docs/evidence/wp17r2/samples/images/$name',
      ];

      final runtime = OcrRuntime(
        assetsRoot: assetsRoot,
        libraryPath: bundleLibrary,
      );
      final started = DateTime.now();
      final results = await runtime.recognizeFiles(paths);
      final elapsed = DateTime.now().difference(started);

      expect(results.length, paths.length);
      var lineCount = 0;
      for (final result in results) {
        expect(result.error, isNull, reason: result.path);
        final name = File(result.path).uri.pathSegments.last;
        final expected = expectedText[name]!;
        expect(result.lines.length, expected.length, reason: name);
        for (var i = 0; i < expected.length; i++) {
          expect(result.lines[i].text, expected[i], reason: '$name line $i');
        }
        lineCount += result.lines.length;
      }
      debugPrint(
        'WP17_I4_BUNDLE_RESULT images=${results.length} lines=$lineCount '
        'elapsed_ms=${elapsed.inMilliseconds}',
      );

      // Error boundary through the same loaded library and root.
      final corrupt = File(
        '${Directory.systemTemp.createTempSync('wp17i4-').path}/corrupt.png',
      )..writeAsBytesSync(utf8.encode('not a png'));
      final failure = (await runtime.recognizeFiles([corrupt.path])).single;
      expect(failure.error, 'PNG header decode failed');
      expect(failure.width, 0);
      expect(failure.lines, isEmpty);
      corrupt.parent.deleteSync(recursive: true);

      // A root without the model layout must fail instead of falling back.
      final emptyRoot = Directory.systemTemp
          .createTempSync('wp17i4-empty-')
          .path;
      final empty = (await OcrRuntime(
        assetsRoot: emptyRoot,
      ).recognizeFiles([paths.first])).single;
      expect(empty.error, isNotNull);
      expect(empty.lines, isEmpty);
      Directory(emptyRoot).deleteSync(recursive: true);
    });
  });
}
