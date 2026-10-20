import 'dart:async';
import 'dart:io' show HandshakeException, SocketException;

import 'package:compoise/sync/sync_http.dart';
import 'package:compoise/sync/sync_remote.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Future<SyncRemoteException> _failure(Future<Object?> future) async {
  try {
    await future;
  } on SyncRemoteException catch (error) {
    return error;
  }
  fail('expected a SyncRemoteException');
}

http.Request _post() =>
    http.Request('POST', Uri.parse('https://login.example.com/token?x=secret'))
      ..headers['Authorization'] = 'Bearer abc'
      ..bodyFields = {'grant_type': 'refresh_token'};

void main() {
  test('a connection dropped before any answer is sent once more', () async {
    final seen = <http.Request>[];
    final client = MockClient((request) async {
      seen.add(request);
      if (seen.length == 1) {
        throw http.ClientException('Connection closed before full header');
      }
      return http.Response('ok', 200);
    });
    final response = await sendSyncRequest(
      client,
      _post(),
      const Duration(seconds: 5),
      retryDelay: Duration.zero,
    );
    expect(response.body, 'ok');
    expect(seen, hasLength(2));
    final again = seen.last;
    expect(again.method, 'POST');
    expect(again.url, seen.first.url);
    expect(again.headers['authorization'], 'Bearer abc');
    expect(again.headers['content-type'], startsWith('application/x-www'));
    expect(again.body, 'grant_type=refresh_token');
  });

  test('a second drop is a network failure naming method and host', () async {
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      throw const SocketException('Connection reset by peer');
    });
    final error = await _failure(
      sendSyncRequest(
        client,
        _post(),
        const Duration(seconds: 5),
        retryDelay: Duration.zero,
      ),
    );
    expect(calls, 2);
    expect(error.kind, SyncRemoteFailure.network);
    expect(error.message, 'POST login.example.com: Connection reset by peer');
    expect(error.message, isNot(contains('secret')));
    expect(error.message, isNot(contains('token')));
  });

  test('timeouts and TLS failures are not retried', () async {
    var calls = 0;
    final slow = MockClient((_) {
      calls++;
      return Completer<http.Response>().future;
    });
    final timedOut = await _failure(
      sendSyncRequest(
        slow,
        http.Request('GET', Uri.parse('https://dav.example.com/a')),
        const Duration(milliseconds: 20),
        retryDelay: Duration.zero,
      ),
    );
    expect(calls, 1);
    expect(timedOut.kind, SyncRemoteFailure.network);
    expect(timedOut.message, 'GET dav.example.com: timeout');

    calls = 0;
    final tls = MockClient((_) async {
      calls++;
      throw const HandshakeException('CERTIFICATE_VERIFY_FAILED');
    });
    final refused = await _failure(
      sendSyncRequest(
        tls,
        http.Request('GET', Uri.parse('https://dav.example.com/a')),
        const Duration(seconds: 5),
        retryDelay: Duration.zero,
      ),
    );
    expect(calls, 1);
    expect(refused.kind, SyncRemoteFailure.network);
  });

  test('other errors pass through untouched', () async {
    final client = MockClient((_) async => throw StateError('bug'));
    await expectLater(
      sendSyncRequest(
        client,
        http.Request('GET', Uri.parse('https://dav.example.com/a')),
        const Duration(seconds: 5),
      ),
      throwsStateError,
    );
  });
}
