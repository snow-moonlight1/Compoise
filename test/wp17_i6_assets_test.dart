import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/ocr/ocr_assets.dart';
import 'package:matrixflow_native/screenshot_import/screenshot_backend.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'optional bundle precedes support; explicit environment still wins',
    () async {
      expect(
        await resolveOcrAssetsRoot(
          environment: () => {},
          bundledDirectory: () async => '/private/bundle',
          supportDirectory: () async =>
              throw StateError('should not open support'),
        ),
        '/private/bundle',
      );
      expect(
        await resolveOcrAssetsRoot(
          environment: () => {'WP17_OCR_ASSETS': '/explicit'},
          bundledDirectory: () async =>
              throw StateError('should not unpack assets'),
        ),
        '/explicit',
      );
    },
  );
  test(
    'Linux bundle discovery is local and does not create missing files',
    () async {
      final root = Directory.systemTemp.createTempSync('wp17i6-layout-');
      addTearDown(() => root.deleteSync(recursive: true));
      final executable = '${root.path}/matrixflow_native';
      expect(
        await bundledOcrAssetsRoot(executable: executable, android: false),
        isNull,
      );
      expect(root.listSync(), isEmpty);
      final assets = Directory('${root.path}/data/wp17-ocr')
        ..createSync(recursive: true);
      File('${assets.path}/bundle-manifest.json').writeAsStringSync('{}');
      expect(
        await bundledOcrAssetsRoot(executable: executable, android: false),
        assets.path,
      );
    },
  );
  const channel = MethodChannel('com.matrixflow/ocr_assets');
  test(
    'Android uses APK-local bridge and propagates verification failure',
    () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'prepare');
        return '/private/apk-assets';
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      expect(await bundledOcrAssetsRoot(android: true), '/private/apk-assets');
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => throw PlatformException(code: 'OCR_ASSETS'),
      );
      await expectLater(
        bundledOcrAssetsRoot(android: true),
        throwsA(isA<PlatformException>()),
      );
    },
  );
}
