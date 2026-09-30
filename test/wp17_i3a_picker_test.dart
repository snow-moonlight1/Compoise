import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/ocr/ocr_runtime.dart';
import 'package:matrixflow_native/screenshot_import/screenshot_capture.dart';

void main() {
  test(
    'desktop picker requests multiple PNG paths with no data/stream/compression',
    () async {
      final picker = _Picker();
      FilePicker? previous;
      try {
        previous = FilePicker.platform;
      } catch (_) {}
      FilePicker.platform = picker;
      addTearDown(() {
        if (previous != null) FilePicker.platform = previous;
      });
      for (final platform in [TargetPlatform.windows, TargetPlatform.linux]) {
        final selected = await pickScreenshotPngFiles(platform: platform);
        expect(selected!.map((file) => file.name), ['second.png', 'first.png']);
      }
      expect(picker.calls, 2);
    },
  );

  test(
    'mobile privacy gate rejects before calling the unbounded disk-caching picker',
    () async {
      final picker = _Picker();
      FilePicker? previous;
      try {
        previous = FilePicker.platform;
      } catch (_) {}
      FilePicker.platform = picker;
      addTearDown(() {
        debugDefaultTargetPlatformOverride = null;
        if (previous != null) FilePicker.platform = previous;
      });
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final capture = ScreenshotCapture.withRecognizer(
        recognize: (path, _) async =>
            OcrImageResult(path: path, width: 0, height: 0, lines: const []),
      );
      final output = await capture.pickAndCapture();
      expect(output.batch, isNull);
      expect(output.error, contains('caches originals and logs URIs'));
      expect(picker.calls, 0);
    },
  );
}

class _Picker extends FilePicker {
  int calls = 0;
  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    calls++;
    expect(type, FileType.custom);
    expect(allowedExtensions, ['png']);
    expect(allowMultiple, isTrue);
    expect(withData, isFalse);
    expect(withReadStream, isFalse);
    expect(allowCompression, isFalse);
    return FilePickerResult([
      PlatformFile(name: 'second.png', size: 1, path: '/second.png'),
      PlatformFile(name: 'first.png', size: 1, path: '/first.png'),
    ]);
  }
}
