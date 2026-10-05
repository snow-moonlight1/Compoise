import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrixflow_native/ui/songti_font.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SongtiFonts.loaded = false;
    SongtiFonts.directoryOverride = null;
    SongtiFonts.loaderOverride = null;
    SongtiFonts.installedOverride = null;
    SongtiFonts.licenseTextOverride = null;
  });

  tearDown(() {
    SongtiFonts.loaded = false;
    SongtiFonts.directoryOverride = null;
    SongtiFonts.loaderOverride = null;
    SongtiFonts.installedOverride = null;
    SongtiFonts.licenseTextOverride = null;
  });

  test('a download page is not treated as a font', () {
    final html = Uint8List.fromList('<html>missing</html>'.codeUnits);
    expect(SongtiFonts.looksLikeFont(html, minBytes: 4), isFalse);
    final otto = Uint8List(4)..setRange(0, 4, [0x4F, 0x54, 0x54, 0x4F]);
    expect(SongtiFonts.looksLikeFont(otto, minBytes: 4), isTrue);
  });

  test('a valid file is kept and handed to the loader', () async {
    final root = await Directory.systemTemp.createTemp('songti-ok');
    addTearDown(() => root.delete(recursive: true));
    SongtiFonts.directoryOverride = () async => root;
    final seen = <int>[];
    SongtiFonts.loaderOverride = (bytes) async => seen.add(bytes.length);

    final payload = Uint8List(32)..setRange(0, 4, [0x4F, 0x54, 0x54, 0x4F]);
    final client = MockClient(
      (request) async => http.Response.bytes(payload, 200),
    );
    addTearDown(client.close);

    await SongtiFonts.download(client: client, minBytes: payload.length);

    expect(seen, [payload.length]);
    expect(SongtiFonts.loaded, isTrue);
    final saved = File(
      '${root.path}${Platform.pathSeparator}fonts${Platform.pathSeparator}${SongtiFonts.fileName}',
    );
    expect(saved.existsSync(), isTrue);
    expect(saved.lengthSync(), payload.length);
    final license = File(
      '${root.path}${Platform.pathSeparator}fonts${Platform.pathSeparator}OFL.txt',
    );
    expect(license.existsSync(), isTrue);
    expect(license.readAsStringSync(), contains('SIL OPEN FONT LICENSE'));
  });

  test('a bad reply is skipped and the next address is used', () async {
    final root = await Directory.systemTemp.createTemp('songti-retry');
    addTearDown(() => root.delete(recursive: true));
    SongtiFonts.directoryOverride = () async => root;
    SongtiFonts.loaderOverride = (_) async {};

    final payload = Uint8List(16)..setRange(0, 4, [0x4F, 0x54, 0x54, 0x4F]);
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      if (calls == 1) {
        return http.Response.bytes(
          Uint8List.fromList('<html></html>'.codeUnits),
          200,
        );
      }
      return http.Response.bytes(payload, 200);
    });
    addTearDown(client.close);

    await SongtiFonts.download(client: client, minBytes: payload.length);

    expect(calls, SongtiFonts.urls.length == 1 ? 1 : 2);
    expect(SongtiFonts.loaded, isTrue);
    final part = File(
      '${root.path}${Platform.pathSeparator}fonts${Platform.pathSeparator}${SongtiFonts.fileName}.part',
    );
    expect(part.existsSync(), isFalse);
  });

  test('an install override does not look at the disk', () async {
    SongtiFonts.installedOverride = false;
    expect(await SongtiFonts.isInstalled(), isFalse);
  });
}
