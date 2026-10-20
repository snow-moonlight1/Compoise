// An in-memory Microsoft identity platform and Graph app folder behind
// package:http's MockClient, plus a browser the test drives. It speaks the
// subset the OneDrive transport and sign-in use.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:compoise/sync/onedrive_auth.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _root = '/v1.0/me/drive/special/approot';

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

http.Response _graphError(int status, String code) => _json({
  'error': {'code': code, 'message': 'fake'},
}, status);

String fakeIdToken({String? id, String? account}) {
  String part(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${part({'alg': 'none'})}.${part({if (id != null) 'oid': id, if (account != null) 'preferred_username': account, 'name': 'Test User'})}.sig';
}

class _Code {
  _Code(this.challenge, this.redirectUri, this.account, this.id);
  final String challenge;
  final String redirectUri;
  final String account;
  final String id;
}

class _Session {
  _Session(this.name, this.behavior);
  final String name;
  final String behavior;
  final BytesBuilder received = BytesBuilder();
}

class FakeGraphServer {
  FakeGraphServer({DateTime Function()? now}) : now = now ?? DateTime.now;

  final DateTime Function() now;

  /// Files in the app folder by name.
  final Map<String, Uint8List> files = {};
  final Set<String> subfolders = {};
  final Map<String, int> _etags = {};
  bool folderExists = false;

  /// When false, uploads into a missing app folder answer 404 until the
  /// folder is requested.
  bool uploadsCreateFolder = true;
  int pageSize = 200;

  /// A next link to another host, which the client must refuse.
  bool foreignNextLink = false;

  final Set<String> accessTokens = {};
  final Set<String> refreshTokens = {};
  final Map<String, _Code> _codes = {};
  final Map<String, _Session> _sessions = {};
  bool rotateRefreshTokens = true;
  int refreshCount = 0;
  int redeemCount = 0;
  int _counter = 0;

  /// Requests to the download and upload links that carried a token.
  int tokenLeaks = 0;

  /// Answers queued for operations ('token', 'list', 'read', 'download',
  /// 'write', 'session', 'chunk', 'delete', 'folder'), then normal service.
  final Map<String, List<http.Response>> faults = {};
  final List<String> log = [];
  final List<Map<String, String>> tokenRequests = [];

  MockClient get client => MockClient(handle);

  void failNext(String operation, http.Response response) =>
      (faults[operation] ??= []).add(response);

  String _next(String prefix) => '$prefix-${++_counter}';

  String issueAccessToken() {
    final token = _next('access');
    accessTokens.add(token);
    return token;
  }

  String issueRefreshToken() {
    final token = _next('refresh');
    refreshTokens.add(token);
    return token;
  }

  /// A signed-in token bundle, as secure storage would hold it.
  OneDriveTokens tokens({bool expired = false}) => OneDriveTokens(
    refreshToken: issueRefreshToken(),
    accessToken: issueAccessToken(),
    expiresAt: now()
        .add(expired ? const Duration(minutes: -1) : const Duration(hours: 1))
        .millisecondsSinceEpoch,
  );

  /// Graph stops accepting every access token issued so far.
  void expireAccessTokens() => accessTokens.clear();

  /// The user revoked the app, or the refresh token aged out.
  void revokeSignIn() {
    accessTokens.clear();
    refreshTokens.clear();
  }

  /// The sign-in page approves and returns this code.
  String issueCode({
    required String challenge,
    required String redirectUri,
    String account = 'me@outlook.com',
    String id = 'user-1',
  }) {
    final code = _next('code');
    _codes[code] = _Code(challenge, redirectUri, account, id);
    return code;
  }

  void putFile(String name, String text) {
    folderExists = true;
    files[name] = Uint8List.fromList(utf8.encode(text));
    _etags[name] = ++_counter;
  }

  Map<String, Object?> _item(String name) => {
    'name': name,
    'eTag': '"{etag-${_etags[name]}},1"',
    'size': files[name]!.length,
    'file': {'mimeType': 'application/octet-stream'},
  };

  http.Response? _fault(String operation) {
    final queued = faults[operation];
    if (queued != null && queued.isNotEmpty) return queued.removeAt(0);
    return null;
  }

  Future<http.Response> handle(http.Request request) async {
    final url = request.url;
    log.add('${request.method} ${url.host}${url.path}');
    if (url.host == 'login.microsoftonline.com') return _token(request);
    if (url.host == 'download.example.com') return _download(request);
    if (url.host == 'upload.example.com') return _chunk(request);
    if (url.host != 'graph.microsoft.com') return http.Response('', 404);
    final path = url.path;
    final operation = switch (request.method) {
      'GET' when path == _root => 'folder',
      'GET' when path == '$_root/children' => 'list',
      'GET' => 'read',
      'PUT' => 'write',
      'POST' => 'session',
      'DELETE' => 'delete',
      _ => 'other',
    };
    final fault = _fault(operation);
    if (fault != null) return fault;
    final auth = request.headers['authorization'] ?? '';
    if (!auth.startsWith('Bearer ') ||
        !accessTokens.contains(auth.substring(7))) {
      return _graphError(401, 'InvalidAuthenticationToken');
    }
    if (path == _root) {
      folderExists = true;
      return _json({'name': 'Compoise', 'folder': {}});
    }
    if (path == '$_root/children') return _children(url);
    if (!path.startsWith('$_root:/')) return _graphError(400, 'invalidRequest');
    final rest = path.substring(_root.length + 2);
    if (rest.endsWith(':/content')) {
      final name = rest.substring(0, rest.length - ':/content'.length);
      return request.method == 'GET'
          ? _read(name)
          : _write(name, request, url.queryParameters);
    }
    if (rest.endsWith(':/createUploadSession')) {
      final name = rest.substring(
        0,
        rest.length - ':/createUploadSession'.length,
      );
      return _startSession(name, request);
    }
    if (request.method == 'DELETE') {
      if (files.remove(rest) == null) return _graphError(404, 'itemNotFound');
      return http.Response('', 204);
    }
    return _graphError(400, 'invalidRequest');
  }

  http.Response _children(Uri url) {
    if (!folderExists) return _graphError(404, 'itemNotFound');
    final names = [...subfolders, ...files.keys]..sort();
    final start = int.tryParse(url.queryParameters[r'$skiptoken'] ?? '') ?? 0;
    final page = names.skip(start).take(pageSize).toList();
    final end = start + page.length;
    return _json({
      'value': [
        for (final name in page)
          if (subfolders.contains(name))
            {
              'name': name,
              'eTag': 'folder',
              'folder': {'childCount': 0},
            }
          else
            _item(name),
      ],
      if (end < names.length)
        '@odata.nextLink': foreignNextLink
            ? 'https://evil.example.com/next?\$skiptoken=$end'
            : 'https://graph.microsoft.com$_root/children?\$skiptoken=$end',
    });
  }

  http.Response _read(String name) {
    if (!files.containsKey(name)) return _graphError(404, 'itemNotFound');
    return http.Response(
      '',
      302,
      headers: {
        'location':
            'https://download.example.com/${Uri.encodeComponent(name)}'
            '?tempauth=${_next('link')}',
      },
    );
  }

  http.Response _download(http.Request request) {
    if (request.headers.containsKey('authorization')) tokenLeaks++;
    final fault = _fault('download');
    if (fault != null) return fault;
    final name = Uri.decodeComponent(request.url.pathSegments.single);
    final bytes = files[name];
    if (bytes == null) return http.Response('', 404);
    return http.Response.bytes(bytes, 200);
  }

  http.Response _write(
    String name,
    http.Request request,
    Map<String, String> query,
  ) {
    if (!folderExists) {
      if (!uploadsCreateFolder) return _graphError(404, 'itemNotFound');
      folderExists = true;
    }
    final behavior = query['@microsoft.graph.conflictBehavior'] ?? 'replace';
    if (behavior == 'fail' && files.containsKey(name)) {
      return _graphError(409, 'nameAlreadyExists');
    }
    final existed = files.containsKey(name);
    files[name] = Uint8List.fromList(request.bodyBytes);
    _etags[name] = ++_counter;
    return _json(_item(name), existed ? 200 : 201);
  }

  http.Response _startSession(String name, http.Request request) {
    if (!folderExists) {
      if (!uploadsCreateFolder) return _graphError(404, 'itemNotFound');
      folderExists = true;
    }
    final body = jsonDecode(request.body) as Map;
    final behavior =
        (body['item'] as Map)['@microsoft.graph.conflictBehavior'] as String;
    final id = _next('session');
    _sessions[id] = _Session(name, behavior);
    return _json({
      'uploadUrl': 'https://upload.example.com/$id',
      'expirationDateTime': '2030-01-01T00:00:00Z',
    });
  }

  /// Content-Range headers the upload link received, in order.
  final List<String> ranges = [];

  http.Response _chunk(http.Request request) {
    if (request.headers.containsKey('authorization')) tokenLeaks++;
    final id = request.url.pathSegments.single;
    if (request.method == 'DELETE') {
      _sessions.remove(id);
      return http.Response('', 204);
    }
    final fault = _fault('chunk');
    if (fault != null) return fault;
    final session = _sessions[id];
    if (session == null) return _graphError(404, 'itemNotFound');
    final range = request.headers['content-range']!;
    ranges.add(range);
    final match = RegExp(r'^bytes (\d+)-(\d+)/(\d+)$').firstMatch(range)!;
    final start = int.parse(match[1]!);
    final total = int.parse(match[3]!);
    if (start != session.received.length) {
      return _graphError(416, 'invalidRange');
    }
    session.received.add(request.bodyBytes);
    if (session.received.length < total) {
      return _json({
        'nextExpectedRanges': ['${session.received.length}-'],
      }, 202);
    }
    _sessions.remove(id);
    if (session.behavior == 'fail' && files.containsKey(session.name)) {
      return _graphError(409, 'nameAlreadyExists');
    }
    files[session.name] = session.received.takeBytes();
    _etags[session.name] = ++_counter;
    return _json(_item(session.name), 201);
  }

  Future<http.Response> _token(http.Request request) async {
    final fault = _fault('token');
    if (fault != null) return fault;
    final fields = request.bodyFields;
    tokenRequests.add(fields);
    if (request.url.path != '/consumers/oauth2/v2.0/token' ||
        fields['client_id'] != oneDriveClientId ||
        !(fields['scope'] ?? '').contains('Files.ReadWrite.AppFolder')) {
      return _json({'error': 'invalid_request'}, 400);
    }
    String account = 'me@outlook.com';
    String id = 'user-1';
    switch (fields['grant_type']) {
      case 'authorization_code':
        final code = _codes.remove(fields['code']);
        if (code == null ||
            code.redirectUri != fields['redirect_uri'] ||
            pkceChallenge(fields['code_verifier'] ?? '') != code.challenge) {
          return _json({
            'error': 'invalid_grant',
            'error_codes': [70000],
          }, 400);
        }
        redeemCount++;
        account = code.account;
        id = code.id;
      case 'refresh_token':
        final token = fields['refresh_token'];
        if (!refreshTokens.contains(token)) {
          return _json({
            'error': 'invalid_grant',
            'error_codes': [70008],
          }, 400);
        }
        refreshCount++;
        if (rotateRefreshTokens) refreshTokens.remove(token);
      default:
        return _json({'error': 'unsupported_grant_type'}, 400);
    }
    final rotate =
        fields['grant_type'] == 'authorization_code' || rotateRefreshTokens;
    return _json({
      'token_type': 'Bearer',
      'scope': oneDriveScopes,
      'expires_in': 3600,
      'access_token': issueAccessToken(),
      if (rotate) 'refresh_token': issueRefreshToken(),
      'id_token': fakeIdToken(id: id, account: account),
    });
  }
}

/// Stands in for the redirect listener of a real sign-in.
class FakeRedirectListener implements OAuthRedirectListener {
  final _redirects = StreamController<Uri>.broadcast();
  bool closed = false;

  @override
  String get redirectUri => 'http://localhost:53682';

  @override
  Stream<Uri> get redirects => _redirects.stream;

  void deliver(Uri uri) {
    if (!closed) _redirects.add(uri);
  }

  @override
  Future<void> close() async {
    closed = true;
    await _redirects.close();
  }
}

/// A browser the test drives: it records the sign-in page and answers the
/// way Microsoft's would.
class FakeBrowser {
  FakeBrowser(this.graph);

  final FakeGraphServer graph;
  FakeRedirectListener? listener;
  Uri? opened;
  bool opens = true;

  OneDriveAuthorizer authorizer({
    Duration timeout = const Duration(minutes: 10),
  }) => BrowserOneDriveAuthorizer(
    listen: (_) async => listener = FakeRedirectListener(),
    open: (url) async {
      opened = url;
      return opens;
    },
    auth: () => OneDriveAuth(client: graph.client, now: graph.now),
    timeout: timeout,
  );

  Map<String, String> get _page => opened!.queryParameters;

  Uri _back(Map<String, String> params) =>
      Uri.parse(_page['redirect_uri']!).replace(queryParameters: params);

  /// Signs in as [account] and allows access.
  void approve({String account = 'me@outlook.com', String id = 'user-1'}) {
    final code = graph.issueCode(
      challenge: _page['code_challenge']!,
      redirectUri: _page['redirect_uri']!,
      account: account,
      id: id,
    );
    listener!.deliver(_back({'code': code, 'state': _page['state']!}));
  }

  void deny() => listener!.deliver(
    _back({'error': 'access_denied', 'state': _page['state']!}),
  );
}
