// The OneDrive transport against an in-memory Graph app folder: listing with
// pages, downloads without the token, plain and session uploads, token
// refresh and rotation, error mapping, and two engines syncing.
import 'dart:convert';
import 'dart:io' show SocketException;
import 'dart:typed_data';

import 'package:compoise/sync/onedrive_auth.dart';
import 'package:compoise/sync/onedrive_remote.dart';
import 'package:compoise/sync/sync_remote.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'onedrive_fake.dart';
import 'sync_fakes.dart';

Uint8List _bytes(String text) => Uint8List.fromList(utf8.encode(text));

class _Rig {
  _Rig({bool expired = false, this.simpleUploadLimit = 4 * 1024 * 1024}) {
    remote = build(graph.tokens(expired: expired));
  }

  final graph = FakeGraphServer();
  final int simpleUploadLimit;
  final List<String> saved = [];
  late OneDriveRemote remote;

  OneDriveRemote build(OneDriveTokens? tokens) => OneDriveRemote(
    tokens: tokens,
    saveTokens: (secret) async => saved.add(secret),
    client: graph.client,
    simpleUploadLimit: simpleUploadLimit,
    chunkSize: 4,
  );
}

Future<SyncRemoteException> _failure(Future<Object?> operation) async {
  try {
    await operation;
  } on SyncRemoteException catch (error) {
    return error;
  }
  fail('no SyncRemoteException');
}

http.Response _error(int status, String code, [Map<String, String>? headers]) =>
    http.Response(
      jsonEncode({
        'error': {'code': code},
      }),
      status,
      headers: headers ?? const {},
    );

void main() {
  group('operations', () {
    test(
      'a missing app folder lists empty and the first upload makes it',
      () async {
        final rig = _Rig();
        expect(await rig.remote.list(), isEmpty);
        await rig.remote.write('vault.json', _bytes('{"v":1}'));
        expect(rig.graph.folderExists, isTrue);
        final entries = await rig.remote.list();
        expect(entries.single.name, 'vault.json');
        expect(entries.single.size, 7);
        expect(utf8.decode(await rig.remote.read('vault.json')), '{"v":1}');
      },
    );

    test('rewriting changes the version; folders are not listed', () async {
      final rig = _Rig();
      rig.graph.subfolders.add('stray folder');
      await rig.remote.write('dev-aaaaaaaa.cps', _bytes('one'));
      final before = (await rig.remote.list()).single.version;
      await rig.remote.write('dev-aaaaaaaa.cps', _bytes('two'));
      final after = await rig.remote.list();
      expect(after.single.version, isNot(before));
      expect(utf8.decode(rig.graph.files['dev-aaaaaaaa.cps']!), 'two');
    });

    test('downloads follow the link without the access token', () async {
      final rig = _Rig();
      rig.graph.putFile('vault.json', 'hello');
      expect(utf8.decode(await rig.remote.read('vault.json')), 'hello');
      expect(rig.graph.tokenLeaks, 0);
      expect(rig.graph.log, contains('GET download.example.com/vault.json'));
    });

    test('reading a missing file is notFound', () async {
      final rig = _Rig()..graph.folderExists = true;
      expect(
        (await _failure(rig.remote.read('vault.json'))).kind,
        SyncRemoteFailure.notFound,
      );
    });

    test(
      'create refuses an existing file; delete ignores a missing one',
      () async {
        final rig = _Rig();
        await rig.remote.create('vault.json', _bytes('first'));
        final error = await _failure(
          rig.remote.create('vault.json', _bytes('x')),
        );
        expect(error.kind, SyncRemoteFailure.conflict);
        expect(error.message, 'create: HTTP 409 nameAlreadyExists');
        expect(utf8.decode(rig.graph.files['vault.json']!), 'first');
        await rig.remote.delete('vault.json');
        await rig.remote.delete('vault.json');
        expect(rig.graph.files, isEmpty);
      },
    );

    test('an upload into a missing folder asks for the folder first', () async {
      final rig = _Rig()..graph.uploadsCreateFolder = false;
      await rig.remote.write('vault.json', _bytes('x'));
      expect(rig.graph.folderExists, isTrue);
      expect(rig.graph.files.keys, ['vault.json']);
    });

    test('listing follows next links, but only to Graph', () async {
      final rig = _Rig();
      for (var i = 0; i < 5; i++) {
        rig.graph.putFile('dev-0000000$i.cps', '$i');
      }
      rig.graph.pageSize = 2;
      final names = [for (final entry in await rig.remote.list()) entry.name];
      expect(names, hasLength(5));
      expect(names.toSet(), hasLength(5));

      rig.graph.foreignNextLink = true;
      expect(
        (await _failure(rig.remote.list())).kind,
        SyncRemoteFailure.protocol,
      );
    });

    test('large files go through an upload session in pieces', () async {
      final rig = _Rig(simpleUploadLimit: 8);
      final payload = _bytes('0123456789abcdefghij');
      await rig.remote.write('dev-aaaaaaaa.cps', payload);
      expect(rig.graph.files['dev-aaaaaaaa.cps'], payload);
      expect(rig.graph.ranges.first, 'bytes 0-3/20');
      expect(rig.graph.ranges.last, 'bytes 16-19/20');
      expect(rig.graph.ranges, hasLength(5));
      expect(rig.graph.tokenLeaks, 0);

      final error = await _failure(
        rig.remote.create('dev-aaaaaaaa.cps', payload),
      );
      expect(error.kind, SyncRemoteFailure.conflict);
    });

    test('a failed piece cancels the upload session', () async {
      final rig = _Rig(simpleUploadLimit: 8);
      rig.graph.failNext('chunk', _error(500, 'generalException'));
      final error = await _failure(
        rig.remote.write('dev-aaaaaaaa.cps', _bytes('0123456789')),
      );
      expect(error.kind, SyncRemoteFailure.server);
      await Future<void>.delayed(Duration.zero);
      expect(
        rig.graph.log.where((line) => line.startsWith('DELETE upload')),
        hasLength(1),
      );
      expect(rig.graph.files, isEmpty);
    });
  });

  group('tokens', () {
    test(
      'a stale access token is refreshed once and the new one saved',
      () async {
        final rig = _Rig(expired: true);
        await rig.remote.list();
        await rig.remote.list();
        expect(rig.graph.refreshCount, 1);
        final saved = OneDriveTokens.decode(rig.saved.single)!;
        expect(rig.graph.refreshTokens, contains(saved.refreshToken));
        expect(rig.graph.accessTokens, contains(saved.accessToken));
      },
    );

    test('parallel requests share one refresh', () async {
      final rig = _Rig(expired: true);
      await Future.wait([rig.remote.list(), rig.remote.list()]);
      expect(rig.graph.refreshCount, 1);
    });

    test(
      'a rejected access token is refreshed and the request repeated',
      () async {
        final rig = _Rig();
        rig.graph.putFile('vault.json', 'x');
        rig.graph.expireAccessTokens();
        expect(utf8.decode(await rig.remote.read('vault.json')), 'x');
        expect(rig.graph.refreshCount, 1);
        expect(rig.saved, hasLength(1));
      },
    );

    test('a revoked sign-in is an auth failure and nothing is saved', () async {
      final rig = _Rig();
      rig.graph.revokeSignIn();
      final error = await _failure(rig.remote.list());
      expect(error.kind, SyncRemoteFailure.auth);
      expect(error.message, 'login: HTTP 400 invalid_grant AADSTS70008');
      expect(rig.saved, isEmpty);
    });

    test('Graph refusing even a fresh token is an auth failure', () async {
      final rig = _Rig();
      rig.graph
        ..failNext('list', _error(401, 'InvalidAuthenticationToken'))
        ..failNext('list', _error(401, 'InvalidAuthenticationToken'));
      expect((await _failure(rig.remote.list())).kind, SyncRemoteFailure.auth);
      expect(rig.graph.refreshCount, 1);
    });

    test('no bundle means signing in again', () async {
      final rig = _Rig();
      final remote = rig.build(null);
      expect((await _failure(remote.list())).kind, SyncRemoteFailure.auth);
    });

    test('a failed save does not fail the request', () async {
      final graph = FakeGraphServer();
      final remote = OneDriveRemote(
        tokens: graph.tokens(expired: true),
        saveTokens: (_) async => throw StateError('keyring locked'),
        client: graph.client,
      );
      expect(await remote.list(), isEmpty);
    });
  });

  group('errors', () {
    test('statuses map to failure kinds', () async {
      final cases = <http.Response, SyncRemoteFailure>{
        _error(403, 'accessDenied'): SyncRemoteFailure.forbidden,
        _error(507, 'quotaLimitReached'): SyncRemoteFailure.quota,
        _error(429, 'activityLimitReached', {'retry-after': '12'}):
            SyncRemoteFailure.rateLimited,
        _error(503, 'serviceNotAvailable', {'retry-after': '5'}):
            SyncRemoteFailure.rateLimited,
        _error(503, 'serviceNotAvailable'): SyncRemoteFailure.server,
        _error(423, 'resourceLocked'): SyncRemoteFailure.server,
        _error(400, 'invalidRequest'): SyncRemoteFailure.protocol,
      };
      for (final entry in cases.entries) {
        final rig = _Rig();
        rig.graph.failNext('write', entry.key);
        final error = await _failure(
          rig.remote.write('vault.json', _bytes('x')),
        );
        expect(error.kind, entry.value, reason: '${entry.key.statusCode}');
      }
      final rig = _Rig();
      rig.graph.failNext(
        'list',
        _error(429, 'activityLimitReached', {'retry-after': '12'}),
      );
      final limited = await _failure(rig.remote.list());
      expect(limited.retryAfter, const Duration(seconds: 12));
      expect(limited.message, 'list: HTTP 429 activityLimitReached');
    });

    test(
      'a refused download link is temporary, not a sign-in problem',
      () async {
        final rig = _Rig();
        rig.graph.putFile('vault.json', 'x');
        rig.graph.failNext('download', http.Response('', 401));
        expect(
          (await _failure(rig.remote.read('vault.json'))).kind,
          SyncRemoteFailure.server,
        );
      },
    );

    test('network failures and non-JSON answers', () async {
      final graph = FakeGraphServer();
      final offline = OneDriveRemote(
        tokens: graph.tokens(),
        saveTokens: (_) async {},
        client: MockClient((_) async => throw const SocketException('down')),
      );
      expect((await _failure(offline.list())).kind, SyncRemoteFailure.network);
      final rig = _Rig()..graph.folderExists = true;
      rig.graph.failNext('list', http.Response('<html>', 200));
      expect(
        (await _failure(rig.remote.list())).kind,
        SyncRemoteFailure.protocol,
      );
    });
  });

  test('two devices sync through one app folder', () async {
    final graph = FakeGraphServer();
    final clock = TestClock();
    OneDriveRemote remote() => OneDriveRemote(
      tokens: graph.tokens(expired: true),
      saveTokens: (_) async {},
      client: graph.client,
    );
    final first = Device(remote(), name: 'First', clock: clock.call);
    final second = Device(remote(), name: 'Second', clock: clock.call);
    await first.load();
    await second.load();
    first.host.addTask('t1', 'Written on the first device');
    expect(
      await first.engine.createVault(
        first.remote,
        provider: 'onedrive',
        password: 'correct horse',
      ),
      isNotNull,
    );
    expect(
      await second.engine.joinVault(
        second.remote,
        provider: 'onedrive',
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
      graph.files.keys.where((name) => name.endsWith('.cps')),
      hasLength(2),
    );
    expect(graph.tokenLeaks, 0);
  });
}
