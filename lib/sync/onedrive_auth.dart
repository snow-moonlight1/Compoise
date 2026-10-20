/// Microsoft account sign-in for OneDrive: the authorization code flow with
/// PKCE against the personal-account endpoint. There is no client secret;
/// the client id below is public and identifies the Compoise registration.
///
/// The browser does the sign-in. On the desktop it is sent back to a
/// one-time server on 127.0.0.1; on Android to the `com.compoise.app://oauth`
/// address the app registers. See `oauth_browser.dart`.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'sync_http.dart';
import 'sync_remote.dart';

/// Application (client) id of the "Compoise" app registration, which allows
/// personal Microsoft accounts only. Not a secret.
const oneDriveClientId = 'c64036dd-cb8c-4d3e-bbb1-7d56e18df824';

/// The personal-account (consumers) endpoint of the Microsoft identity
/// platform.
final oneDriveAuthority = Uri.parse(
  'https://login.microsoftonline.com/consumers/oauth2/v2.0/',
);

/// The app folder only; `offline_access` for the refresh token, and the two
/// sign-in scopes for the account name shown in settings.
const oneDriveScopes =
    'Files.ReadWrite.AppFolder offline_access openid profile';

/// Registered redirect for the Android app.
const oneDriveAndroidRedirect = 'com.compoise.app://oauth';

String _base64Url(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

/// A random URL-safe string from [bytes] random bytes.
String randomUrlToken([Random? random, int bytes = 32]) {
  final source = random ?? Random.secure();
  return _base64Url(List<int>.generate(bytes, (_) => source.nextInt(256)));
}

/// The S256 PKCE challenge for [verifier].
String pkceChallenge(String verifier) =>
    _base64Url(sha256.convert(ascii.encode(verifier)).bytes);

/// What secure storage keeps for OneDrive. The refresh token is the part
/// that matters; the access token is kept to avoid a refresh on every start.
class OneDriveTokens {
  const OneDriveTokens({
    required this.refreshToken,
    this.accessToken,
    this.expiresAt,
  });

  final String refreshToken;
  final String? accessToken;

  /// When [accessToken] expires, in epoch milliseconds.
  final int? expiresAt;

  /// True when the access token is still good for [margin] after [now].
  bool usableAt(DateTime now, {Duration margin = const Duration(minutes: 5)}) {
    final token = accessToken;
    final expires = expiresAt;
    if (token == null || token.isEmpty || expires == null) return false;
    return now.add(margin).millisecondsSinceEpoch < expires;
  }

  String encode() => jsonEncode({
    'format': 1,
    'kind': 'onedrive',
    'refreshToken': refreshToken,
    if (accessToken != null) 'accessToken': accessToken,
    if (expiresAt != null) 'expiresAt': expiresAt,
  });

  /// Null for anything that is not a token bundle, for example a WebDAV
  /// password left behind by an older setup.
  static OneDriveTokens? decode(String? text) {
    if (text == null || text.isEmpty) return null;
    Object? raw;
    try {
      raw = jsonDecode(text);
    } on FormatException {
      return null;
    }
    if (raw is! Map || raw['format'] != 1 || raw['kind'] != 'onedrive') {
      return null;
    }
    final refresh = raw['refreshToken'];
    if (refresh is! String || refresh.isEmpty) return null;
    final access = raw['accessToken'];
    final expires = raw['expiresAt'];
    return OneDriveTokens(
      refreshToken: refresh,
      accessToken: access is String ? access : null,
      expiresAt: expires is int ? expires : null,
    );
  }
}

/// Who signed in, read from the ID token. Both parts are optional: the
/// sign-in still works without them.
class OneDriveAccount {
  const OneDriveAccount({this.id, this.label});

  /// Stable for the same account and app.
  final String? id;

  /// Usually the e-mail address.
  final String? label;

  /// The claims of an ID token the token endpoint returned over TLS. The
  /// signature is not checked: the token is only used for display and to
  /// notice a different account.
  static OneDriveAccount fromIdToken(Object? idToken) {
    if (idToken is! String) return const OneDriveAccount();
    final parts = idToken.split('.');
    if (parts.length < 2) return const OneDriveAccount();
    try {
      final claims = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      if (claims is! Map) return const OneDriveAccount();
      String? text(String key) {
        final value = claims[key];
        return value is String && value.trim().isNotEmpty ? value.trim() : null;
      }

      return OneDriveAccount(
        id: text('oid') ?? text('sub'),
        label: text('preferred_username') ?? text('email') ?? text('name'),
      );
    } on FormatException {
      return const OneDriveAccount();
    }
  }
}

/// The answer of the token endpoint.
class OneDriveTokenResult {
  const OneDriveTokenResult({required this.tokens, required this.account});

  final OneDriveTokens tokens;
  final OneDriveAccount account;
}

/// The token endpoint: redeeming the sign-in code and refreshing.
class OneDriveAuth {
  OneDriveAuth({
    http.Client? client,
    this.clientId = oneDriveClientId,
    Uri? authority,
    this.scopes = oneDriveScopes,
    this.timeout = const Duration(seconds: 30),
    DateTime Function()? now,
  }) : _client = client ?? http.Client(),
       authority = authority ?? oneDriveAuthority,
       _now = now ?? DateTime.now;

  final http.Client _client;
  final String clientId;
  final Uri authority;
  final String scopes;
  final Duration timeout;
  final DateTime Function() _now;

  /// The page the browser opens. `select_account` lets someone with several
  /// Microsoft accounts pick the right one.
  Uri authorizeUrl({
    required String redirectUri,
    required String state,
    required String codeChallenge,
  }) => authority
      .resolve('authorize')
      .replace(
        queryParameters: {
          'client_id': clientId,
          'response_type': 'code',
          'redirect_uri': redirectUri,
          'response_mode': 'query',
          'scope': scopes,
          'state': state,
          'code_challenge': codeChallenge,
          'code_challenge_method': 'S256',
          'prompt': 'select_account',
        },
      );

  Future<OneDriveTokenResult> redeem({
    required String code,
    required String redirectUri,
    required String verifier,
  }) => _token({
    'grant_type': 'authorization_code',
    'code': code,
    'redirect_uri': redirectUri,
    'code_verifier': verifier,
  });

  /// Microsoft may return a new refresh token; callers must keep it.
  Future<OneDriveTokenResult> refresh(String refreshToken) => _token({
    'grant_type': 'refresh_token',
    'refresh_token': refreshToken,
  }, previousRefresh: refreshToken);

  Future<OneDriveTokenResult> _token(
    Map<String, String> fields, {
    String? previousRefresh,
  }) async {
    final request = http.Request('POST', authority.resolve('token'))
      ..followRedirects = false
      ..bodyFields = {'client_id': clientId, 'scope': scopes, ...fields};
    final response = await sendSyncRequest(_client, request, timeout);
    Object? json;
    try {
      json = jsonDecode(utf8.decode(response.bodyBytes, allowMalformed: true));
    } on FormatException {
      json = null;
    }
    final body = json is Map ? json : const {};
    if (response.statusCode == 200) {
      final access = body['access_token'];
      final refresh = body['refresh_token'] ?? previousRefresh;
      if (access is! String || access.isEmpty || refresh is! String) {
        throw const SyncRemoteException(
          SyncRemoteFailure.protocol,
          'token: HTTP 200 incomplete',
        );
      }
      final expiresIn = switch (body['expires_in']) {
        final num value => value.toInt(),
        final String value => int.tryParse(value) ?? 3600,
        _ => 3600,
      };
      return OneDriveTokenResult(
        tokens: OneDriveTokens(
          refreshToken: refresh,
          accessToken: access,
          expiresAt: _now()
              .add(Duration(seconds: expiresIn))
              .millisecondsSinceEpoch,
        ),
        account: OneDriveAccount.fromIdToken(body['id_token']),
      );
    }
    throw tokenFailure(
      response.statusCode,
      body['error'],
      body['error_codes'],
      parseRetryAfter(response.headers['retry-after']),
    );
  }
}

/// Classifies a refused token request. The message keeps only the status,
/// the OAuth error code and the first AADSTS number, which help diagnose
/// without naming the account.
SyncRemoteException tokenFailure(
  int status,
  Object? error,
  Object? codes, [
  Duration? retryAfter,
]) {
  final code = error is String && RegExp(r'^[a-z_]{1,40}$').hasMatch(error)
      ? error
      : null;
  final number = codes is List && codes.isNotEmpty && codes.first is int
      ? codes.first as int
      : null;
  final kind = switch (status) {
    429 => SyncRemoteFailure.rateLimited,
    >= 500 => SyncRemoteFailure.server,
    _ => switch (code) {
      'invalid_grant' ||
      'interaction_required' ||
      'login_required' ||
      'consent_required' ||
      'invalid_client' ||
      'unauthorized_client' => SyncRemoteFailure.auth,
      'temporarily_unavailable' => SyncRemoteFailure.server,
      _ => SyncRemoteFailure.protocol,
    },
  };
  final detail = [
    'token: HTTP $status',
    if (code != null) code,
    if (number != null) 'AADSTS$number',
  ].join(' ');
  return SyncRemoteException(kind, detail, retryAfter);
}

enum OneDriveSignInError {
  /// The user closed the wait; not shown as an error.
  cancelled,

  /// The user declined the permission request.
  denied,

  /// Nothing came back within the time limit.
  timedOut,

  /// The sign-in page reported an error, or the answer was incomplete.
  failed,
}

class OneDriveSignInException implements Exception {
  const OneDriveSignInException(this.kind, [this.detail = '']);

  final OneDriveSignInError kind;

  /// An OAuth error code such as `access_denied`; never personal data.
  final String detail;

  @override
  String toString() => 'OneDriveSignInException(${kind.name}) $detail';
}

/// Where the browser is sent back to after the sign-in page.
abstract class OAuthRedirectListener {
  /// The `redirect_uri` for this attempt.
  String get redirectUri;

  /// Every address the browser returns to while listening.
  Stream<Uri> get redirects;

  Future<void> close();
}

/// Starts listening. [donePage] is the text the desktop browser shows once
/// it has handed the answer back.
typedef OAuthRedirectListenerFactory =
    Future<OAuthRedirectListener> Function(String donePage);

/// Opens [url] in the user's browser; false when that failed.
typedef BrowserOpener = Future<bool> Function(Uri url);

/// One sign-in in progress.
class OneDriveSignIn {
  OneDriveSignIn._(this.url, this.browserOpened, this.result, this._cancel);

  /// The sign-in page, offered for copying when no browser opened.
  final Uri url;
  final bool browserOpened;

  /// The tokens, or a [OneDriveSignInException] / [SyncRemoteException].
  final Future<OneDriveTokenResult> result;
  final Completer<void> _cancel;

  /// Stops waiting; [result] fails with [OneDriveSignInError.cancelled].
  void cancel() {
    if (!_cancel.isCompleted) _cancel.complete();
  }
}

abstract class OneDriveAuthorizer {
  /// Opens the sign-in page in the browser and waits for the answer.
  Future<OneDriveSignIn> begin({required String donePage});
}

class BrowserOneDriveAuthorizer implements OneDriveAuthorizer {
  BrowserOneDriveAuthorizer({
    required this.listen,
    required this.open,
    OneDriveAuth Function()? auth,
    this.timeout = const Duration(minutes: 10),
    Random? random,
  }) : _auth = auth ?? OneDriveAuth.new,
       _random = random ?? Random.secure();

  final OAuthRedirectListenerFactory listen;
  final BrowserOpener open;
  final OneDriveAuth Function() _auth;
  final Duration timeout;
  final Random _random;

  @override
  Future<OneDriveSignIn> begin({required String donePage}) async {
    final listener = await listen(donePage);
    final auth = _auth();
    final verifier = randomUrlToken(_random);
    final state = randomUrlToken(_random, 16);
    final url = auth.authorizeUrl(
      redirectUri: listener.redirectUri,
      state: state,
      codeChallenge: pkceChallenge(verifier),
    );
    final cancel = Completer<void>();
    final result = _finish(listener, auth, state, verifier, cancel.future);
    bool opened;
    try {
      opened = await open(url);
    } catch (_) {
      opened = false;
    }
    return OneDriveSignIn._(url, opened, result, cancel);
  }

  Future<OneDriveTokenResult> _finish(
    OAuthRedirectListener listener,
    OneDriveAuth auth,
    String state,
    String verifier,
    Future<void> cancelled,
  ) async {
    final answer = Completer<Map<String, String>>();
    // Answers to an earlier attempt carry another state and are ignored.
    final subscription = listener.redirects.listen((uri) {
      final params = uri.queryParameters;
      if (params['state'] == state && !answer.isCompleted) {
        answer.complete(params);
      }
    });
    final timer = Timer(timeout, () {
      if (!answer.isCompleted) {
        answer.completeError(
          const OneDriveSignInException(OneDriveSignInError.timedOut),
        );
      }
    });
    unawaited(
      cancelled.then((_) {
        if (!answer.isCompleted) {
          answer.completeError(
            const OneDriveSignInException(OneDriveSignInError.cancelled),
          );
        }
      }),
    );
    try {
      final params = await answer.future;
      final error = params['error'];
      if (error != null) {
        throw OneDriveSignInException(
          error == 'access_denied'
              ? OneDriveSignInError.denied
              : OneDriveSignInError.failed,
          RegExp(r'^[a-z_]{1,40}$').hasMatch(error) ? error : '',
        );
      }
      final code = params['code'];
      if (code == null || code.isEmpty) {
        throw const OneDriveSignInException(OneDriveSignInError.failed, 'code');
      }
      return await auth.redeem(
        code: code,
        redirectUri: listener.redirectUri,
        verifier: verifier,
      );
    } finally {
      // Cleanup does not hold up the answer.
      timer.cancel();
      unawaited(subscription.cancel());
      unawaited(listener.close());
    }
  }
}
