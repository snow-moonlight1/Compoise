// Microsoft sign-in for OneDrive: PKCE, the sign-in page address, the token
// bundle, the token endpoint's errors, and the browser round trip through a
// real loopback server.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:compoise/screens/settings_sync.dart';
import 'package:compoise/sync/oauth_browser.dart';
import 'package:compoise/sync/onedrive_auth.dart';
import 'package:compoise/sync/sync_provider.dart';
import 'package:compoise/sync/sync_remote.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'onedrive_fake.dart';

Future<SyncRemoteException> _remoteFailure(Future<Object?> future) async {
  try {
    await future;
  } on SyncRemoteException catch (error) {
    return error;
  }
  fail('no SyncRemoteException');
}

Future<OneDriveSignInError> _signInFailure(Future<Object?> future) async {
  try {
    await future;
  } on OneDriveSignInException catch (error) {
    return error.kind;
  }
  fail('no OneDriveSignInException');
}

void main() {
  group('PKCE and the sign-in page', () {
    test('the challenge is the RFC 7636 S256 value', () {
      expect(
        pkceChallenge('dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk'),
        'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
      );
    });

    test('random tokens are URL-safe and long enough', () {
      final token = randomUrlToken();
      expect(token, matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
      expect(randomUrlToken(), isNot(token));
    });

    test('the page asks the consumer endpoint for the app folder only', () {
      final url = OneDriveAuth().authorizeUrl(
        redirectUri: 'http://localhost:1234',
        state: 'st',
        codeChallenge: 'ch',
      );
      expect(url.host, 'login.microsoftonline.com');
      expect(url.path, '/consumers/oauth2/v2.0/authorize');
      expect(url.queryParameters, {
        'client_id': oneDriveClientId,
        'response_type': 'code',
        'redirect_uri': 'http://localhost:1234',
        'response_mode': 'query',
        'scope': 'Files.ReadWrite.AppFolder offline_access openid profile',
        'state': 'st',
        'code_challenge': 'ch',
        'code_challenge_method': 'S256',
        'prompt': 'select_account',
      });
    });
  });

  group('token bundle', () {
    test('round-trips and knows when the access token is stale', () {
      final now = DateTime(2026, 10, 20, 12);
      final tokens = OneDriveTokens(
        refreshToken: 'r',
        accessToken: 'a',
        expiresAt: now.add(const Duration(minutes: 30)).millisecondsSinceEpoch,
      );
      final back = OneDriveTokens.decode(tokens.encode())!;
      expect(back.refreshToken, 'r');
      expect(back.accessToken, 'a');
      expect(back.expiresAt, tokens.expiresAt);
      expect(back.usableAt(now), isTrue);
      expect(back.usableAt(now.add(const Duration(minutes: 26))), isFalse);
      expect(
        const OneDriveTokens(refreshToken: 'r').usableAt(now),
        isFalse,
        reason: 'no access token',
      );
    });

    test('anything else is not a bundle', () {
      for (final text in [
        null,
        '',
        'a WebDAV password',
        '{}',
        jsonEncode({'format': 1, 'kind': 'onedrive'}),
        jsonEncode({'format': 2, 'kind': 'onedrive', 'refreshToken': 'r'}),
      ]) {
        expect(OneDriveTokens.decode(text), isNull, reason: '$text');
      }
    });

    test('the account comes from the ID token', () {
      final account = OneDriveAccount.fromIdToken(
        fakeIdToken(id: 'abc', account: 'me@outlook.com'),
      );
      expect(account.id, 'abc');
      expect(account.label, 'me@outlook.com');
      for (final broken in [null, 42, 'x', 'a.%%%.c', 'a.bm90IGpzb24.c']) {
        final empty = OneDriveAccount.fromIdToken(broken);
        expect(empty.id, isNull);
        expect(empty.label, isNull);
      }
    });
  });

  group('token endpoint', () {
    test('redeems a code with the verifier and computes the expiry', () async {
      final now = DateTime(2026, 10, 20, 12);
      final graph = FakeGraphServer(now: () => now);
      final auth = OneDriveAuth(client: graph.client, now: () => now);
      const verifier = 'verifier-verifier-verifier-verifier-verifier';
      final code = graph.issueCode(
        challenge: pkceChallenge(verifier),
        redirectUri: 'http://localhost:1',
      );
      final result = await auth.redeem(
        code: code,
        redirectUri: 'http://localhost:1',
        verifier: verifier,
      );
      expect(result.account.label, 'me@outlook.com');
      expect(result.account.id, 'user-1');
      expect(graph.accessTokens, contains(result.tokens.accessToken));
      expect(graph.refreshTokens, contains(result.tokens.refreshToken));
      expect(
        result.tokens.expiresAt,
        now.add(const Duration(hours: 1)).millisecondsSinceEpoch,
      );
      final sent = graph.tokenRequests.single;
      expect(sent['grant_type'], 'authorization_code');
      expect(sent['code_verifier'], verifier);
      expect(sent.containsKey('client_secret'), isFalse);
    });

    test('a wrong verifier is refused', () async {
      final graph = FakeGraphServer();
      final code = graph.issueCode(
        challenge: pkceChallenge('right'),
        redirectUri: 'http://localhost:1',
      );
      final error = await _remoteFailure(
        OneDriveAuth(client: graph.client).redeem(
          code: code,
          redirectUri: 'http://localhost:1',
          verifier: 'wrong',
        ),
      );
      expect(error.kind, SyncRemoteFailure.auth);
    });

    test(
      'refreshing keeps the old refresh token when none is returned',
      () async {
        final graph = FakeGraphServer()..rotateRefreshTokens = false;
        final tokens = graph.tokens();
        final result = await OneDriveAuth(
          client: graph.client,
        ).refresh(tokens.refreshToken);
        expect(result.tokens.refreshToken, tokens.refreshToken);
        expect(result.tokens.accessToken, isNot(tokens.accessToken));
      },
    );

    test('failures are classified and labelled without personal data', () {
      final expired = tokenFailure(400, 'invalid_grant', [70008]);
      expect(expired.kind, SyncRemoteFailure.auth);
      expect(expired.message, 'login: HTTP 400 invalid_grant AADSTS70008');
      expect(
        syncErrorLabel(expired),
        'remote auth (login: HTTP 400 invalid_grant AADSTS70008)',
      );
      expect(
        tokenFailure(400, 'interaction_required', null).kind,
        SyncRemoteFailure.auth,
      );
      expect(
        tokenFailure(400, 'invalid_request', null).kind,
        SyncRemoteFailure.protocol,
      );
      expect(
        tokenFailure(400, 'temporarily_unavailable', null).kind,
        SyncRemoteFailure.server,
      );
      expect(tokenFailure(503, null, null).kind, SyncRemoteFailure.server);
      final limited = tokenFailure(429, null, null, const Duration(seconds: 7));
      expect(limited.kind, SyncRemoteFailure.rateLimited);
      expect(limited.retryAfter, const Duration(seconds: 7));
      expect(
        tokenFailure(400, 'Some Address <a@b.c>', null).message,
        'login: HTTP 400',
      );
    });

    test('network failures and broken answers', () async {
      final offline = OneDriveAuth(
        client: _client((_) => throw const SocketException('offline')),
      );
      expect(
        (await _remoteFailure(offline.refresh('r'))).kind,
        SyncRemoteFailure.network,
      );
      final garbled = OneDriveAuth(
        client: _client((_) async => http.Response('<html>', 200)),
      );
      expect(
        (await _remoteFailure(garbled.refresh('r'))).kind,
        SyncRemoteFailure.protocol,
      );
    });
  });

  group('browser round trip', () {
    test('approving returns tokens; other states are ignored', () async {
      final graph = FakeGraphServer();
      final browser = FakeBrowser(graph);
      final attempt = await browser.authorizer().begin(donePage: 'done');
      expect(attempt.browserOpened, isTrue);
      expect(attempt.url, browser.opened);
      final page = attempt.url.queryParameters;
      expect(page['redirect_uri'], 'http://localhost:53682');
      expect(page['code_challenge_method'], 'S256');
      // A redirect from an earlier attempt.
      browser.listener!.deliver(
        Uri.parse('http://localhost:53682/?code=old&state=other'),
      );
      browser.approve(account: 'second@outlook.com', id: 'user-2');
      final result = await attempt.result;
      expect(result.account.label, 'second@outlook.com');
      expect(result.account.id, 'user-2');
      expect(graph.redeemCount, 1);
      expect(browser.listener!.closed, isTrue);
    });

    test('declining, cancelling and waiting too long', () async {
      final graph = FakeGraphServer();
      final browser = FakeBrowser(graph);
      var attempt = await browser.authorizer().begin(donePage: 'done');
      browser.deny();
      expect(await _signInFailure(attempt.result), OneDriveSignInError.denied);

      attempt = await browser.authorizer().begin(donePage: 'done');
      attempt.cancel();
      expect(
        await _signInFailure(attempt.result),
        OneDriveSignInError.cancelled,
      );
      expect(browser.listener!.closed, isTrue);

      attempt = await browser
          .authorizer(timeout: const Duration(milliseconds: 20))
          .begin(donePage: 'done');
      expect(
        await _signInFailure(attempt.result),
        OneDriveSignInError.timedOut,
      );

      attempt = await browser.authorizer().begin(donePage: 'done');
      browser.listener!.deliver(
        Uri.parse(
          'http://localhost:53682/?error=server_error'
          '&state=${attempt.url.queryParameters['state']}',
        ),
      );
      expect(await _signInFailure(attempt.result), OneDriveSignInError.failed);
      expect(graph.redeemCount, 0);
    });

    test('a browser that does not open still leaves the link', () async {
      final browser = FakeBrowser(FakeGraphServer())..opens = false;
      final attempt = await browser.authorizer().begin(donePage: 'done');
      expect(attempt.browserOpened, isFalse);
      expect(attempt.url.queryParameters['client_id'], oneDriveClientId);
      attempt.cancel();
      await expectLater(
        attempt.result,
        throwsA(isA<OneDriveSignInException>()),
      );
    });

    test(
      'the loopback server hands the answer over and shows a page',
      () async {
        final graph = FakeGraphServer();
        Future<void>? browserDone;
        final authorizer = BrowserOneDriveAuthorizer(
          listen: (page) => LoopbackRedirectListener.bind(donePage: page),
          auth: () => OneDriveAuth(client: graph.client),
          open: (url) async {
            // The "browser": Microsoft approves and redirects back.
            final page = url.queryParameters;
            final redirect = Uri.parse(page['redirect_uri']!);
            expect(redirect.host, 'localhost');
            expect(redirect.path, '');
            final code = graph.issueCode(
              challenge: page['code_challenge']!,
              redirectUri: page['redirect_uri']!,
            );
            browserDone = (() async {
              final client = HttpClient();
              final local = redirect.replace(host: '127.0.0.1');
              final miss = await client.getUrl(
                local.replace(path: '/favicon.ico'),
              );
              expect((await miss.close()).statusCode, 404);
              final request = await client.getUrl(
                local.replace(
                  path: '/',
                  queryParameters: {'code': code, 'state': page['state']!},
                ),
              );
              final response = await request.close();
              expect(response.statusCode, 200);
              final html = await response.transform(utf8.decoder).join();
              expect(html, contains('Signed in &amp; done'));
              client.close();
            })();
            return true;
          },
        );
        final attempt = await authorizer.begin(donePage: 'Signed in & done');
        final result = await attempt.result;
        await browserDone;
        expect(result.account.label, 'me@outlook.com');
        // The server is gone once the answer arrived.
        final port = Uri.parse(
          attempt.url.queryParameters['redirect_uri']!,
        ).port;
        await expectLater(
          Socket.connect(InternetAddress.loopbackIPv4, port),
          throwsA(isA<SocketException>()),
        );
      },
    );
  });

  group('error wording', () {
    test('sign-in outcomes and OneDrive failures read plainly', () {
      final t = <String, String>{
        'syncOnedriveDenied': 'denied',
        'syncOnedriveTimedOut': 'timeout',
        'syncOnedriveSignInFailed': 'failed',
        'syncErrorAuth': 'webdav auth',
        'syncErrorAuthOnedrive': 'onedrive auth',
        'syncErrorQuota': 'quota',
        'syncErrorGeneric': 'generic',
      };
      expect(
        syncErrorText(
          const OneDriveSignInException(OneDriveSignInError.denied),
          t,
        ),
        'denied',
      );
      expect(
        syncErrorText(
          const OneDriveSignInException(OneDriveSignInError.timedOut),
          t,
        ),
        'timeout',
      );
      const auth = SyncRemoteException(SyncRemoteFailure.auth);
      expect(syncErrorText(auth, t), 'webdav auth');
      expect(
        syncErrorText(auth, t, kind: SyncProviderKind.onedrive),
        'onedrive auth',
      );
      expect(
        syncErrorText(
          const SyncRemoteException(SyncRemoteFailure.quota),
          t,
          kind: SyncProviderKind.onedrive,
        ),
        'quota',
      );
      expect(
        syncErrorLabel(
          const OneDriveSignInException(
            OneDriveSignInError.failed,
            'invalid_request',
          ),
        ),
        'sign-in failed invalid_request',
      );
    });
  });
}

http.Client _client(Future<http.Response> Function(http.Request) handler) =>
    _FnClient(handler);

class _FnClient extends http.BaseClient {
  _FnClient(this.handler);

  final Future<http.Response> Function(http.Request) handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await handler(request as http.Request);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
    );
  }
}
