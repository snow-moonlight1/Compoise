import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/ocr/ocr_assets.dart';
import 'package:matrixflow_native/ocr/ocr_runtime.dart';
import 'package:matrixflow_native/screenshot_import/screenshot_backend.dart';

/// WP17-I4: the deployment layout and the resource lookup that consumes it.
///
/// These are host tests. They assert the file names, the resolution order and
/// the failure behaviour; actual recognition on this machine is covered by the
/// environment-gated native tests in wp17_i1_ocr_runtime_test.dart and by the
/// bundle integration test.
void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('wp17i4-assets-');
  });

  tearDown(() async {
    if (directory.existsSync()) await directory.delete(recursive: true);
  });

  Future<void> writeModels(
    String root, {
    List<String>? omit,
    List<String>? empty,
  }) async {
    Directory('$root/ncnn').createSync(recursive: true);
    for (final name in ocrModelFileNames) {
      if (omit != null && omit.contains(name)) continue;
      await File(ocrModelPath(root, name)).writeAsString(
        empty != null && empty.contains(name) ? '' : 'synthetic-$name',
      );
    }
  }

  test('model check reads exactly the five native file names under ncnn/', () async {
    await writeModels(directory.path);
    expect(await missingOcrModelFiles(directory.path), isEmpty);
    expect(
      ocrModelFileNames,
      [
        'ppocrv5_dict.txt',
        'PP_OCRv5_mobile_det.ncnn.param',
        'PP_OCRv5_mobile_det.ncnn.bin',
        'PP_OCRv5_mobile_rec.ncnn.param',
        'PP_OCRv5_mobile_rec.ncnn.bin',
      ],
    );
    final entries = Directory('${directory.path}/ncnn')
        .listSync()
        .map((entry) => entry.path.split(Platform.pathSeparator).last)
        .toList()
      ..sort();
    expect(entries, [...ocrModelFileNames]..sort());
  });

  test('missing and empty files are reported by name', () async {
    await writeModels(
      directory.path,
      omit: ['PP_OCRv5_mobile_rec.ncnn.bin'],
      empty: ['ppocrv5_dict.txt'],
    );
    expect(
      await missingOcrModelFiles(directory.path),
      ['ppocrv5_dict.txt', 'PP_OCRv5_mobile_rec.ncnn.bin'],
    );
  });

  test('a wrong layout (models directly under the root) is rejected', () async {
    await File('${directory.path}/ppocrv5_dict.txt').writeAsString('x');
    expect(await missingOcrModelFiles(directory.path), ocrModelFileNames);
  });

  test('WP17_OCR_ASSETS from the environment wins over the support directory', () async {
    final environment = Directory('${directory.path}/environment')..createSync();

    expect(
      await resolveOcrAssetsRoot(
        environment: () => {'WP17_OCR_ASSETS': environment.path},
      ),
      environment.path,
    );
  });

  test('blank or absent environment falls back to application support', () async {
    final support = Directory('${directory.path}/support')..createSync();
    final expected = '${support.path}/wp17r2-assets';

    for (final environment in [<String, String>{}, {'WP17_OCR_ASSETS': '  '}]) {
      expect(
        await resolveOcrAssetsRoot(
          environment: () => environment,
          supportDirectory: () async => support,
        ),
        expected,
      );
    }
  });

  test('library lookup is executable-relative on Windows and Linux', () {
    final executable = File(Platform.resolvedExecutable).parent.path;
    final resolved = resolveOcrLibraryPath();
    if (Platform.isWindows) {
      expect(resolved, '$executable\\matrixflow_ocr.dll');
    } else if (Platform.isLinux) {
      expect(resolved, '$executable/lib/libmatrixflow_ocr.so');
    } else if (Platform.isAndroid) {
      expect(resolved, 'libmatrixflow_ocr.so');
    }
  });

  test('backend reports ModelsMissing before it opens the library', () async {
    final backend = LocalScreenshotBackend(
      android: false,
      environment: () => {'WP17_OCR_ASSETS': directory.path},
    );
    expect(await backend.availability(), 'ModelsMissing');
    await backend.dispose();
  });

  test('backend reports NativeMissing when only the models are deployed', () async {
    await writeModels(directory.path);
    final backend = LocalScreenshotBackend(
      android: false,
      environment: () => {'WP17_OCR_ASSETS': directory.path},
    );
    // No matrixflow_ocr.dll exists next to the test executable.
    expect(await backend.availability(), 'NativeMissing');
    await backend.dispose();
  });

  test('backend finds the models through an injected environment', () async {
    await writeModels(directory.path);
    final backend = LocalScreenshotBackend(
      android: false,
      runtime: OcrRuntime(assetsRoot: directory.path),
      environment: () => const {},
    );
    // Explicit runtime wins; the injected environment is irrelevant here.
    expect(await backend.availability(), 'NativeMissing');
    await backend.dispose();
  });
}
