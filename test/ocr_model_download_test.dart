import 'dart:io';

import 'package:compoise/ocr/ocr_model_download.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late Directory dir;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('ocr-models-');
    OcrModels.directoryOverride = () async => dir;
  });
  tearDown(() {
    OcrModels.directoryOverride = null;
    dir.deleteSync(recursive: true);
  });

  test('the model set is pinned and mirrored', () {
    expect(OcrModels.files, hasLength(5));
    expect(OcrModels.totalBytes, 10717392);
    for (final f in OcrModels.files) {
      expect(f.sha256, matches(RegExp(r'^[0-9a-f]{64}$')));
      final urls = OcrModels.urlsFor(f.name);
      expect(urls, hasLength(3));
      expect(urls.every((u) => u.startsWith('https://')), isTrue);
      expect(urls.every((u) => u.contains('ocr-models-v1')), isTrue);
    }
  });

  test('tampered or failing mirrors are rejected and leave nothing', () async {
    final tried = <String>[];
    final client = MockClient((request) async {
      tried.add(request.url.host);
      if (tried.length.isOdd) return http.Response('nope', 404);
      return http.Response('not the model', 200);
    });
    await expectLater(
      OcrModels.download(client: client),
      throwsA(isA<OcrModelDownloadException>()),
    );
    expect(tried.toSet(), hasLength(3));
    expect(await OcrModels.isInstalled(), isFalse);
    final left = dir.listSync(recursive: true).whereType<File>();
    expect(left, isEmpty);
  });
}
