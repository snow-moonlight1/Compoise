import 'dart:convert';
import 'dart:io';

import 'package:compoise/models.dart';
import 'package:compoise/services/app_update.dart';
import 'package:compoise/services/update_check.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

ReleaseVersion v(String s) => ReleaseVersion.parse(s)!;

StoredPackage pkg(String version, {bool complete = true, String? name}) =>
    StoredPackage(
      version: version,
      fileName: name ?? 'compoise-$version-android-arm64-v8a.apk',
      sha256: 'x',
      complete: complete,
    );

class _FakeInstaller extends UpdateInstaller {
  const _FakeInstaller();
  @override
  Future<List<String>> abis() async => const ['arm64-v8a', 'armeabi-v7a'];
}

void main() {
  group('versions', () {
    test('version and build compare', () {
      expect(isNewerRelease(v('1.2.2'), v('1.2.1+5')), isTrue);
      expect(isNewerRelease(v('1.2.1'), v('1.2.1+5')), isFalse);
      expect(isNewerRelease(v('1.2.1+6'), v('1.2.1+5')), isTrue);
      expect(isNewerRelease(v('1.2.1+5'), v('1.2.1+5')), isFalse);
      expect(isNewerRelease(v('1.10.0'), v('1.9.9+40')), isTrue);
      expect(isSameRelease(v('1.2.2'), v('1.2.2+6')), isTrue);
    });
  });

  group('asset selection', () {
    test('android prefers the device ABI, then universal', () {
      expect(
        updateAssetName(UpdateTarget.android, '1.2.2', abis: ['arm64-v8a']),
        'compoise-1.2.2-android-arm64-v8a.apk',
      );
      expect(
        updateAssetName(UpdateTarget.android, '1.2.2', abis: ['armeabi-v7a']),
        'compoise-1.2.2-android-armeabi-v7a.apk',
      );
      expect(
        updateAssetName(UpdateTarget.android, '1.2.2', abis: ['x86_64']),
        'compoise-1.2.2-android-universal.apk',
      );
      expect(
        updateAssetName(UpdateTarget.windows, '1.2.2'),
        'compoise-1.2.2-windows-x64-setup.exe',
      );
      expect(updateAssetName(UpdateTarget.none, '1.2.2'), isNull);
    });

    test('falls back when the release lacks the preferred file', () {
      const names = [
        'compoise-1.2.2-android-universal.apk',
        'compoise-1.2.2-windows-x64-setup.exe',
      ];
      expect(
        pickAvailableAsset('compoise-1.2.2-android-arm64-v8a.apk', names),
        'compoise-1.2.2-android-universal.apk',
      );
      expect(
        pickAvailableAsset('compoise-1.2.2-windows-arm64-setup.exe', names),
        'compoise-1.2.2-windows-x64-setup.exe',
      );
      expect(pickAvailableAsset('other.apk', const []), isNull);
    });

    test('reads SHA256SUMS.txt', () {
      final h = 'a' * 64;
      final sums = parseSha256Sums('$h  one.apk\n${'B' * 64} *two.exe\njunk\n');
      expect(sums, {'one.apk': h, 'two.exe': 'b' * 64});
    });
  });

  group('package retention', () {
    test('launch deletes installed or older packages only', () {
      expect(shouldDiscardOnLaunch(null, v('1.2.1+5')), isFalse);
      expect(shouldDiscardOnLaunch(pkg('1.2.1'), v('1.2.1+5')), isTrue);
      expect(shouldDiscardOnLaunch(pkg('1.2.0'), v('1.2.1+5')), isTrue);
      expect(shouldDiscardOnLaunch(pkg('1.2.2'), v('1.2.1+5')), isFalse);
      expect(shouldDiscardOnLaunch(pkg('junk'), v('1.2.1+5')), isTrue);
    });

    test('update plan', () {
      final cur = v('1.2.0+4');
      final latest = v('1.2.2');
      const name = 'compoise-1.2.2-android-arm64-v8a.apk';
      UpdatePlan plan(StoredPackage? s) =>
          planUpdate(stored: s, current: cur, latest: latest, fileName: name);
      expect(plan(null), const UpdatePlan(UpdateStep.download));
      // Verified latest package: install, no download.
      expect(plan(pkg('1.2.2')), const UpdatePlan(UpdateStep.install));
      // Partial latest package: resume.
      expect(
        plan(pkg('1.2.2', complete: false)),
        const UpdatePlan(UpdateStep.resume),
      );
      // Older package than the latest: quietly replaced.
      expect(
        plan(pkg('1.2.1')),
        const UpdatePlan(UpdateStep.download, discardStored: true),
      );
      // Same version, other file (ABI changed): replaced.
      expect(
        plan(pkg('1.2.2', name: 'compoise-1.2.2-android-universal.apk')),
        const UpdatePlan(UpdateStep.download, discardStored: true),
      );
      expect(
        planUpdate(
          stored: pkg('1.2.2'),
          current: v('1.2.2+6'),
          latest: latest,
          fileName: name,
        ),
        const UpdatePlan(UpdateStep.upToDate, discardStored: true),
      );
    });
  });

  group('package store', () {
    late Directory tmp;
    late UpdatePackageStore store;
    final body = utf8.encode('apk-bytes-' * 100);
    final hash = sha256.convert(body).toString();
    const name = 'compoise-1.2.2-android-arm64-v8a.apk';
    final url = Uri.parse('https://example.test/$name');

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('compoise-update-');
      store = UpdatePackageStore(Directory('${tmp.path}/updates'));
    });
    tearDown(() => tmp.delete(recursive: true));

    List<String> files() => store.dir.existsSync()
        ? (store.dir.listSync().map((e) => e.uri.pathSegments.last).toList()
            ..sort())
        : [];

    test('downloads, verifies and keeps one package', () async {
      await store.dir.create(recursive: true);
      File('${store.dir.path}/old-1.2.1.apk').writeAsStringSync('old');
      final progress = <int>[];
      final file = await store.download(
        client: MockClient((_) async => http.Response.bytes(body, 200)),
        url: url,
        fileName: name,
        version: '1.2.2',
        sha256: hash,
        onProgress: (r, _) => progress.add(r),
      );
      expect(file.readAsBytesSync(), body);
      expect(files(), [name, 'package.json']);
      expect(progress.last, body.length);
      final stored = await store.read();
      expect(stored!.complete, isTrue);
      expect(await store.verify(stored), isTrue);
    });

    test('resumes a partial download', () async {
      await store.dir.create(recursive: true);
      store.partFor(name).writeAsBytesSync(body.sublist(0, 300));
      String? range;
      await store.download(
        client: MockClient.streaming((req, _) async {
          range = req.headers['Range'];
          return http.StreamedResponse(
            Stream.value(body.sublist(300)),
            206,
            contentLength: body.length - 300,
          );
        }),
        url: url,
        fileName: name,
        version: '1.2.2',
        sha256: hash,
      );
      expect(range, 'bytes=300-');
      expect(store.fileFor(name).readAsBytesSync(), body);
    });

    test('a damaged download leaves nothing behind', () async {
      await expectLater(
        store.download(
          client: MockClient((_) async => http.Response('broken', 200)),
          url: url,
          fileName: name,
          version: '1.2.2',
          sha256: hash,
        ),
        throwsA(
          isA<UpdateException>().having(
            (e) => e.failure,
            'failure',
            UpdateFailure.damaged,
          ),
        ),
      );
      expect(files(), isEmpty);
    });

    test('a cut connection keeps the partial file to resume', () async {
      await expectLater(
        store.download(
          client: MockClient.streaming(
            (_, __) async => http.StreamedResponse(
              () async* {
                yield body.sublist(0, 200);
                throw const SocketException('cut');
              }(),
              200,
              contentLength: body.length,
            ),
          ),
          url: url,
          fileName: name,
          version: '1.2.2',
          sha256: hash,
        ),
        throwsA(isA<UpdateException>()),
      );
      expect(store.partFor(name).lengthSync(), 200);
      expect((await store.read())!.complete, isFalse);
    });

    test('launch tidy deletes an installed package', () async {
      await store.download(
        client: MockClient((_) async => http.Response.bytes(body, 200)),
        url: url,
        fileName: name,
        version: '1.2.2',
        sha256: hash,
      );
      expect(
        await tidyUpdatePackages(store: store, currentVersion: '1.2.1+5'),
        isNotNull,
      );
      expect(files(), isNotEmpty);
      expect(
        await tidyUpdatePackages(store: store, currentVersion: '1.2.2+6'),
        isNull,
      );
      expect(files(), isEmpty);
    });

    test('updater installs a ready package without the network', () async {
      await store.download(
        client: MockClient((_) async => http.Response.bytes(body, 200)),
        url: url,
        fileName: name,
        version: '1.2.2',
        sha256: hash,
      );
      final updater = AppUpdater(
        client: MockClient((_) async => throw const SocketException('offline')),
        store: store,
        installer: const _FakeInstaller(),
        target: UpdateTarget.android,
        currentVersion: '1.2.0+4',
      );
      expect(await updater.hasReadyPackage(v('1.2.2')), isTrue);
      final file = await updater.prepare(tag: 'v1.2.2', version: v('1.2.2'));
      expect(file.path, store.fileFor(name).path);
    });

    test('an older package is replaced by the latest quietly', () async {
      const oldName = 'compoise-1.2.1-android-arm64-v8a.apk';
      final oldBody = utf8.encode('old');
      await store.download(
        client: MockClient((_) async => http.Response.bytes(oldBody, 200)),
        url: url,
        fileName: oldName,
        version: '1.2.1',
        sha256: sha256.convert(oldBody).toString(),
      );
      final requested = <String>[];
      final updater = AppUpdater(
        client: MockClient((req) async {
          requested.add(req.url.pathSegments.last);
          if (req.url.path.endsWith(checksumsFileName)) {
            return http.Response('$hash  $name\n', 200);
          }
          return http.Response.bytes(body, 200);
        }),
        store: store,
        installer: const _FakeInstaller(),
        target: UpdateTarget.android,
        currentVersion: '1.2.0+4',
      );
      final file = await updater.prepare(tag: 'v1.2.2', version: v('1.2.2'));
      expect(file.readAsBytesSync(), body);
      expect(requested, [checksumsFileName, name]);
      expect(files(), [name, 'package.json']);
    });
  });

  group('parent auto-complete default', () {
    test('on for new installs and an old unchosen false', () {
      expect(AppSettings().autoCompleteParent, isTrue);
      expect(AppSettings.fromJson({}).autoCompleteParent, isTrue);
      expect(
        AppSettings.fromJson({'autoCompleteParent': false}).autoCompleteParent,
        isTrue,
      );
    });

    test('an explicit choice is kept', () {
      final off = AppSettings.fromJson({
        'autoCompleteParent': false,
        'autoCompleteParentChosen': true,
      });
      expect(off.autoCompleteParent, isFalse);
      final again = AppSettings.fromJson(off.toJson());
      expect(again.autoCompleteParent, isFalse);
      expect(again.autoCompleteParentChosen, isTrue);
    });
  });
}
