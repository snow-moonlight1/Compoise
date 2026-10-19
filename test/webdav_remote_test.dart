// The WebDAV transport against an in-memory server: listing, folder
// creation, conditional create, error mapping and two engines syncing.
import 'dart:convert';
import 'dart:io' show SocketException;
import 'dart:typed_data';

import 'package:compoise/sync/sync_remote.dart';
import 'package:compoise/sync/webdav_remote.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'sync_fakes.dart';
import 'webdav_fake.dart';

Uint8List _bytes(String text) => Uint8List.fromList(utf8.encode(text));

WebDavRemote _remote(FakeDavServer server, {String? password}) => WebDavRemote(
  baseUrl: Uri.parse('https://dav.example.com/dav'),
  username: server.username,
  password: password ?? server.password,
  client: server.client,
);

Future<SyncRemoteFailure?> _failureOf(Future<Object?> operation) async {
  try {
    await operation;
    return null;
  } on SyncRemoteException catch (error) {
    return error.kind;
  }
}

void main() {
  group('addresses', () {
    test('normalizes to a trailing slash and refuses odd parts', () {
      expect(
        normalizeWebDavUrl(' https://dav.jianguoyun.com/dav ').toString(),
        'https://dav.jianguoyun.com/dav/',
      );
      expect(
        normalizeWebDavUrl('http://192.168.1.5:5005').toString(),
        'http://192.168.1.5:5005/',
      );
      for (final bad in [
        'ftp://host/dav',
        'dav.example.com',
        'https://host/dav?x=1',
        'https://user:pw@host/dav',
        'https://host/dav#frag',
        '',
      ]) {
        expect(normalizeWebDavUrl(bad), isNull, reason: bad);
      }
    });

    test('plain http is flagged unless it stays on the local network', () {
      bool insecure(String url) => isInsecureWebDavUrl(Uri.parse(url));
      expect(insecure('https://example.com/dav'), isFalse);
      expect(insecure('http://192.168.0.2/dav'), isFalse);
      expect(insecure('http://10.1.2.3/dav'), isFalse);
      expect(insecure('http://172.20.0.1/dav'), isFalse);
      expect(insecure('http://nas.local/dav'), isFalse);
      expect(insecure('http://localhost:8080/'), isFalse);
      expect(insecure('http://example.com/dav'), isTrue);
      expect(insecure('http://172.40.0.1/dav'), isTrue);
    });
  });

  group('operations', () {
    test(
      'a missing folder lists empty and is created on first write',
      () async {
        final server = FakeDavServer();
        final remote = _remote(server);
        expect(await remote.list(), isEmpty);
        await remote.write('vault.json', _bytes('{}'));
        expect(server.folders, contains('/dav/Compoise/'));
        expect(
          server.log,
          containsAllInOrder([
            'PUT /dav/Compoise/vault.json',
            'MKCOL /dav/Compoise/',
            'PUT /dav/Compoise/vault.json',
          ]),
        );
        final entries = await remote.list();
        expect(entries.single.name, 'vault.json');
        expect(entries.single.size, 2);
        expect(utf8.decode(await remote.read('vault.json')), '{}');
      },
    );

    for (final status in [404, 403]) {
      test('folder creation also follows a $status answer', () async {
        final server = FakeDavServer()..missingParentStatus = status;
        await _remote(server).write('dev-abcdefgh.cps', _bytes('x'));
        expect(server.files.keys, ['/dav/Compoise/dev-abcdefgh.cps']);
      });
    }

    test('a wrong base folder is reported, not created', () async {
      final server = FakeDavServer();
      final remote = WebDavRemote(
        baseUrl: Uri.parse('https://dav.example.com/missing/deeper'),
        username: server.username,
        password: server.password,
        client: server.client,
      );
      expect(
        await _failureOf(remote.write('vault.json', _bytes('{}'))),
        SyncRemoteFailure.notFound,
      );
    });

    test('versions change with content; sub-folders are skipped', () async {
      final server = FakeDavServer()..absoluteHrefs = true;
      final remote = _remote(server);
      await remote.write('dev-aaaaaaaa.cps', _bytes('one'));
      server.folders.add('/dav/Compoise/old stuff/');
      final first = (await remote.list()).single.version;
      await remote.write('dev-aaaaaaaa.cps', _bytes('two'));
      final second = await remote.list();
      expect(second.map((entry) => entry.name), ['dev-aaaaaaaa.cps']);
      expect(second.single.version, isNot(first));
    });

    test('without ETags the version falls back to date and size', () async {
      final server = FakeDavServer()..omitEtags = true;
      final remote = _remote(server);
      await remote.write('vault.json', _bytes('{}'));
      expect((await remote.list()).single.version, startsWith('m:'));
    });

    test(
      'create refuses an existing file, with or without If-None-Match',
      () async {
        for (final honour in [true, false]) {
          final server = FakeDavServer()..honourIfNoneMatch = honour;
          final remote = _remote(server);
          await remote.create('vault.json', _bytes('first'));
          expect(
            await _failureOf(remote.create('vault.json', _bytes('second'))),
            SyncRemoteFailure.conflict,
          );
          expect(
            utf8.decode(server.files['/dav/Compoise/vault.json']!),
            'first',
          );
        }
      },
    );

    test('create maps a lost race (412) to conflict', () async {
      final server = FakeDavServer();
      final remote = _remote(server);
      await remote.write('other.txt', _bytes('x'));
      server.failNext('PUT', http.Response('', 412));
      expect(
        await _failureOf(remote.create('vault.json', _bytes('{}'))),
        SyncRemoteFailure.conflict,
      );
    });

    test('deleting a missing file succeeds', () async {
      final server = FakeDavServer();
      final remote = _remote(server);
      await remote.write('dev-aaaaaaaa.cps', _bytes('x'));
      await remote.delete('dev-aaaaaaaa.cps');
      await remote.delete('dev-aaaaaaaa.cps');
      expect(server.files, isEmpty);
      expect(
        await _failureOf(remote.read('dev-aaaaaaaa.cps')),
        SyncRemoteFailure.notFound,
      );
    });

    test('HTTP answers map to failure kinds', () async {
      final server = FakeDavServer();
      final remote = _remote(server);
      Future<SyncRemoteException> failWith(http.Response response) async {
        server.failNext('PROPFIND', response);
        try {
          await remote.list();
        } on SyncRemoteException catch (error) {
          return error;
        }
        throw StateError('no failure');
      }

      expect(
        (await failWith(http.Response('', 401))).kind,
        SyncRemoteFailure.auth,
      );
      expect(
        (await failWith(http.Response('', 403))).kind,
        SyncRemoteFailure.forbidden,
      );
      expect(
        (await failWith(http.Response('', 507))).kind,
        SyncRemoteFailure.quota,
      );
      final limited = await failWith(
        http.Response('', 429, headers: {'retry-after': '120'}),
      );
      expect(limited.kind, SyncRemoteFailure.rateLimited);
      expect(limited.retryAfter, const Duration(minutes: 2));
      final busy = await failWith(
        http.Response('', 503, headers: {'retry-after': '99999'}),
      );
      expect(busy.kind, SyncRemoteFailure.rateLimited);
      expect(busy.retryAfter, const Duration(hours: 1));
      expect(
        (await failWith(http.Response('', 502))).kind,
        SyncRemoteFailure.server,
      );
      expect(
        (await failWith(http.Response('', 302))).kind,
        SyncRemoteFailure.protocol,
      );
      expect(
        (await failWith(http.Response('<not xml', 207))).kind,
        SyncRemoteFailure.protocol,
      );
    });

    test('a wrong password is an auth failure', () async {
      final server = FakeDavServer();
      expect(
        await _failureOf(_remote(server, password: 'nope').list()),
        SyncRemoteFailure.auth,
      );
    });

    test('socket errors are network failures', () async {
      final remote = WebDavRemote(
        baseUrl: Uri.parse('https://dav.example.com/dav/'),
        username: 'u',
        password: 'p',
        client: MockClient((_) async => throw const SocketException('down')),
      );
      expect(await _failureOf(remote.list()), SyncRemoteFailure.network);
    });

    test('a slow server times out as a network failure', () async {
      final remote = WebDavRemote(
        baseUrl: Uri.parse('https://dav.example.com/dav/'),
        username: 'u',
        password: 'p',
        timeout: const Duration(milliseconds: 20),
        client: MockClient((_) async {
          await Future<void>.delayed(const Duration(seconds: 1));
          return http.Response('', 207);
        }),
      );
      expect(await _failureOf(remote.list()), SyncRemoteFailure.network);
    });
  });

  group('PROPFIND parsing', () {
    test('handles prefixes, default namespaces and encoded hrefs', () {
      const body = '''<?xml version="1.0"?>
<multistatus xmlns="DAV:">
  <response><href>/remote.php/dav/files/me/Compoise/</href>
    <propstat><prop><resourcetype><collection/></resourcetype></prop>
    <status>HTTP/1.1 200 OK</status></propstat></response>
  <response><href>/remote.php/dav/files/me/Compoise/vault.json</href>
    <propstat><prop><resourcetype/><getetag>"abc"</getetag>
    <getcontentlength>12</getcontentlength></prop>
    <status>HTTP/1.1 200 OK</status></propstat></response>
  <response><href>/remote.php/dav/files/me/Compoise/a%20b.txt</href>
    <propstat><prop><getetag>W/"x"</getetag></prop>
    <status>HTTP/1.1 200 OK</status></propstat></response>
  <response><href>/remote.php/dav/files/me/Elsewhere/vault.json</href>
    <propstat><prop><getetag>"no"</getetag></prop>
    <status>HTTP/1.1 200 OK</status></propstat></response>
  <response><href>/remote.php/dav/files/me/Compoise/gone.cps</href>
    <propstat><prop><getetag/></prop>
    <status>HTTP/1.1 404 Not Found</status></propstat></response>
</multistatus>''';
      final entries = parsePropfind(
        body,
        Uri.parse(
          'https://cloud.example.com/remote.php/dav/files/me/Compoise/',
        ),
      );
      expect(entries.map((entry) => entry.name), ['vault.json', 'a b.txt']);
      expect(entries.first.version, '"abc"');
      expect(entries.first.size, 12);
    });
  });

  test('two devices sync through one WebDAV folder', () async {
    final server = FakeDavServer();
    final clock = TestClock();
    final first = Device(_remote(server), name: 'First', clock: clock.call);
    final second = Device(_remote(server), name: 'Second', clock: clock.call);
    await first.load();
    await second.load();
    first.host.addTask('t1', 'Written on the first device');
    expect(
      await first.engine.createVault(
        first.remote,
        provider: 'webdav',
        password: 'correct horse',
      ),
      isNotNull,
    );
    expect(
      await second.engine.joinVault(
        second.remote,
        provider: 'webdav',
        password: 'correct horse',
      ),
      isNotNull,
    );
    expect(second.host.task('t1').title, 'Written on the first device');
    second.host.edit('t1', (task) => task.completed = true);
    await second.engine.sync();
    await first.engine.sync();
    expect(first.host.task('t1').completed, isTrue);
    expect(
      server.files.keys.where((path) => path.endsWith('.cps')),
      hasLength(2),
    );
    // Encrypted files do not contain the task text.
    for (final bytes in server.files.values) {
      expect(
        latin1.decode(bytes, allowInvalid: true),
        isNot(contains('Written')),
      );
    }
  });
}
