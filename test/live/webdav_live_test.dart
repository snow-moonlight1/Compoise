// Opt-in check against a real WebDAV server. Skipped unless these are set:
//
//   COMPOISE_WEBDAV_URL       for example https://dav.jianguoyun.com/dav/
//   COMPOISE_WEBDAV_USER
//   COMPOISE_WEBDAV_PASSWORD  坚果云 needs an app password here
//
// It works in a fresh folder named Compoise-test-<random> and deletes the
// files it wrote; the empty folder stays behind.
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:compoise/sync/sync_remote.dart';
import 'package:compoise/sync/webdav_remote.dart';
import 'package:flutter_test/flutter_test.dart';

import '../sync_fakes.dart';

void main() {
  final env = Platform.environment;
  final url = env['COMPOISE_WEBDAV_URL'];
  final user = env['COMPOISE_WEBDAV_USER'];
  final password = env['COMPOISE_WEBDAV_PASSWORD'];
  final skip = url == null || user == null || password == null
      ? 'set COMPOISE_WEBDAV_URL, _USER and _PASSWORD to run'
      : null;
  final folder = 'Compoise-test-${Random().nextInt(1 << 32).toRadixString(36)}';

  WebDavRemote remote() => WebDavRemote(
    baseUrl: normalizeWebDavUrl(url!)!,
    username: user!,
    password: password!,
    folder: folder,
  );

  test('file operations', () async {
    final dav = remote();
    addTearDown(dav.close);
    expect(await dav.list(), isEmpty);
    final bytes = Uint8List.fromList(utf8.encode('hello'));
    await dav.create('vault.json', bytes);
    await expectLater(
      dav.create('vault.json', bytes),
      throwsA(
        isA<SyncRemoteException>().having(
          (error) => error.kind,
          'kind',
          SyncRemoteFailure.conflict,
        ),
      ),
    );
    final first = (await dav.list()).single;
    expect(first.name, 'vault.json');
    await dav.write('vault.json', Uint8List.fromList(utf8.encode('changed')));
    final second = (await dav.list()).single;
    expect(second.version, isNot(first.version));
    expect(utf8.decode(await dav.read('vault.json')), 'changed');
    await dav.delete('vault.json');
    await dav.delete('vault.json');
    expect(await dav.list(), isEmpty);
  }, skip: skip);

  test(
    'two devices sync',
    () async {
      final clock = TestClock();
      final a = Device(remote(), name: 'A', clock: clock.call);
      final b = Device(remote(), name: 'B', clock: clock.call);
      await a.load();
      await b.load();
      addTearDown(() async {
        for (final entry in await a.remote.list()) {
          await a.remote.delete(entry.name);
        }
      });
      a.host.addTask('t1', 'Live task');
      expect(
        await a.engine.createVault(
          a.remote,
          provider: 'webdav',
          password: 'pw',
        ),
        isNotNull,
      );
      expect(
        await b.engine.joinVault(b.remote, provider: 'webdav', password: 'pw'),
        isNotNull,
      );
      expect(b.host.task('t1').title, 'Live task');
      b.host.edit('t1', (task) => task.title = 'Edited on B');
      await b.engine.sync();
      await a.engine.sync();
      expect(a.host.task('t1').title, 'Edited on B');
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
