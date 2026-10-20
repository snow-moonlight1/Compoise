/// OneDrive transport over Microsoft Graph, limited to the app folder
/// (`Apps/Compoise` in the user's OneDrive). The app cannot see any other
/// file in the drive.
///
/// Files are addressed by path below the special `approot` folder, which
/// OneDrive creates on first use. Downloads follow the pre-authenticated
/// link Graph redirects to, without the access token; uploads above a few
/// megabytes go through an upload session.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../diagnostics/app_log.dart';
import 'onedrive_auth.dart';
import 'sync_http.dart';
import 'sync_remote.dart';

/// Called with the new token bundle after a refresh, to keep it in secure
/// storage.
typedef OneDriveTokenSaver = Future<void> Function(String secret);

class OneDriveRemote implements SyncRemote {
  OneDriveRemote({
    required OneDriveTokens? tokens,
    required this.saveTokens,
    http.Client? client,
    OneDriveAuth? auth,
    DateTime Function()? now,
    Uri? root,
    this.timeout = const Duration(seconds: 60),
    this.simpleUploadLimit = 4 * 1024 * 1024,
    this.chunkSize = 10 * 320 * 1024,
  }) : _tokens = tokens,
       _client = client ?? http.Client(),
       _now = now ?? DateTime.now,
       root = root ?? defaultRoot {
    _auth = auth ?? OneDriveAuth(client: _client, now: _now);
  }

  static final defaultRoot = Uri.parse(
    'https://graph.microsoft.com/v1.0/me/drive/special/approot',
  );

  final OneDriveTokenSaver saveTokens;
  final http.Client _client;
  final DateTime Function() _now;
  late final OneDriveAuth _auth;

  /// The app folder.
  final Uri root;
  final Duration timeout;

  /// Larger files use an upload session.
  final int simpleUploadLimit;

  /// Upload session fragment; Graph wants multiples of 320 KiB.
  final int chunkSize;

  OneDriveTokens? _tokens;
  Future<String>? _refreshing;

  @override
  String get label => 'onedrive';

  Uri _item(String name, [String tail = '']) =>
      Uri.parse('$root:/${Uri.encodeComponent(name)}$tail');

  Uri get _children => Uri.parse(
    '$root/children?\$select=name,eTag,cTag,size,file,lastModifiedDateTime'
    '&\$top=200',
  );

  // --- tokens ---

  Future<String> _accessToken({bool refresh = false}) {
    final tokens = _tokens;
    if (tokens == null) {
      throw const SyncRemoteException(
        SyncRemoteFailure.auth,
        'onedrive: not signed in',
      );
    }
    if (!refresh && tokens.usableAt(_now())) {
      return Future.value(tokens.accessToken!);
    }
    return _refreshing ??= _refresh(
      tokens,
    ).whenComplete(() => _refreshing = null);
  }

  Future<String> _refresh(OneDriveTokens tokens) async {
    final result = await _auth.refresh(tokens.refreshToken);
    _tokens = result.tokens;
    try {
      await saveTokens(result.tokens.encode());
    } catch (error) {
      // The old refresh token usually keeps working; the next refresh
      // tries to save again.
      AppLog.warn(
        'sync',
        'Saving the OneDrive sign-in failed: ${error.runtimeType}',
      );
    }
    return result.tokens.accessToken!;
  }

  // --- requests ---

  Future<http.Response> _send(
    String method,
    Uri uri, {
    String? token,
    Map<String, String> headers = const {},
    List<int>? body,
  }) {
    final request = http.Request(method, uri)..followRedirects = false;
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    request.headers.addAll(headers);
    if (body != null) request.bodyBytes = body;
    return sendSyncRequest(_client, request, timeout);
  }

  /// A Graph request with the access token, refreshed once when Graph
  /// rejects it.
  Future<http.Response> _graph(
    String method,
    Uri uri, {
    Map<String, String> headers = const {},
    List<int>? body,
  }) async {
    final response = await _send(
      method,
      uri,
      token: await _accessToken(),
      headers: headers,
      body: body,
    );
    if (response.statusCode != 401) return response;
    return _send(
      method,
      uri,
      token: await _accessToken(refresh: true),
      headers: headers,
      body: body,
    );
  }

  static SyncRemoteException _failure(http.Response response, String what) {
    final status = response.statusCode;
    final retryAfter = parseRetryAfter(response.headers['retry-after']);
    final kind = switch (status) {
      401 => SyncRemoteFailure.auth,
      403 => SyncRemoteFailure.forbidden,
      404 || 410 => SyncRemoteFailure.notFound,
      409 || 412 => SyncRemoteFailure.conflict,
      413 || 507 => SyncRemoteFailure.quota,
      429 || 509 => SyncRemoteFailure.rateLimited,
      503 when retryAfter != null => SyncRemoteFailure.rateLimited,
      423 || (>= 500 && < 600) => SyncRemoteFailure.server,
      _ => SyncRemoteFailure.protocol,
    };
    final code = _errorCode(response);
    return SyncRemoteException(
      kind,
      code == null ? '$what: HTTP $status' : '$what: HTTP $status $code',
      retryAfter,
    );
  }

  /// Graph's error code, for example `quotaLimitReached`.
  static String? _errorCode(http.Response response) {
    try {
      final json = jsonDecode(utf8.decode(response.bodyBytes));
      final code = json is Map && json['error'] is Map
          ? json['error']['code']
          : null;
      return code is String && RegExp(r'^[A-Za-z_]{1,40}$').hasMatch(code)
          ? code
          : null;
    } on FormatException {
      return null;
    }
  }

  static Map<dynamic, dynamic> _json(http.Response response, String what) {
    try {
      final json = jsonDecode(utf8.decode(response.bodyBytes));
      if (json is Map) return json;
    } on FormatException {
      // Reported below.
    }
    throw SyncRemoteException(SyncRemoteFailure.protocol, '$what: not JSON');
  }

  static bool _ok(int status) => status == 200 || status == 201;

  // --- operations ---

  @override
  Future<List<RemoteEntry>> list() async {
    final entries = <RemoteEntry>[];
    Uri? next = _children;
    for (var page = 0; next != null; page++) {
      if (page >= 100) {
        throw const SyncRemoteException(
          SyncRemoteFailure.protocol,
          'list: too many pages',
        );
      }
      final response = await _graph('GET', next);
      // The app folder appears with the first upload.
      if (response.statusCode == 404 && page == 0) return const [];
      if (response.statusCode != 200) throw _failure(response, 'list');
      final json = _json(response, 'list');
      final value = json['value'];
      if (value is! List) {
        throw const SyncRemoteException(
          SyncRemoteFailure.protocol,
          'list: no value',
        );
      }
      for (final item in value) {
        if (item is! Map || item['file'] is! Map) continue;
        final name = item['name'];
        if (name is! String || name.isEmpty) continue;
        final size = item['size'];
        final version =
            item['eTag'] ??
            item['cTag'] ??
            '${item['lastModifiedDateTime']}/${item['size']}';
        entries.add(
          RemoteEntry(
            name: name,
            version: '$version',
            size: size is num ? size.toInt() : null,
          ),
        );
      }
      final link = json['@odata.nextLink'];
      next = link is String ? Uri.tryParse(link) : null;
      // The token only ever goes to Graph itself.
      if (next != null && (next.scheme != 'https' || next.host != root.host)) {
        throw const SyncRemoteException(
          SyncRemoteFailure.protocol,
          'list: foreign next link',
        );
      }
    }
    return entries;
  }

  @override
  Future<Uint8List> read(String name) async {
    final response = await _graph('GET', _item(name, ':/content'));
    final status = response.statusCode;
    if (status == 200) return response.bodyBytes;
    if (status < 300 || status >= 400) throw _failure(response, 'read');
    final location = response.headers['location'];
    final target = location == null ? null : Uri.tryParse(location);
    if (target == null || target.scheme != 'https') {
      throw const SyncRemoteException(
        SyncRemoteFailure.protocol,
        'read: bad redirect',
      );
    }
    // A pre-authenticated, short-lived link: no access token.
    final download = await _send('GET', target);
    if (download.statusCode == 200) return download.bodyBytes;
    final failure = _failure(download, 'download');
    // A refused download link is the link's problem, not the sign-in's.
    if (failure.kind == SyncRemoteFailure.auth ||
        failure.kind == SyncRemoteFailure.forbidden) {
      throw SyncRemoteException(
        SyncRemoteFailure.server,
        failure.message,
        failure.retryAfter,
      );
    }
    throw failure;
  }

  @override
  Future<void> write(String name, Uint8List bytes) =>
      _upload(name, bytes, replace: true);

  @override
  Future<void> create(String name, Uint8List bytes) =>
      _upload(name, bytes, replace: false);

  Future<void> _upload(
    String name,
    Uint8List bytes, {
    required bool replace,
  }) async {
    final what = replace ? 'write' : 'create';
    final behavior = replace ? 'replace' : 'fail';
    if (bytes.length > simpleUploadLimit) {
      return _uploadSession(name, bytes, what, behavior);
    }
    final uri = _item(
      name,
      ':/content?@microsoft.graph.conflictBehavior=$behavior',
    );
    Future<http.Response> put() => _graph(
      'PUT',
      uri,
      headers: const {'Content-Type': 'application/octet-stream'},
      body: bytes,
    );
    var response = await put();
    if (response.statusCode == 404) {
      await _ensureFolder();
      response = await put();
    }
    if (!_ok(response.statusCode)) throw _failure(response, what);
  }

  /// Asks for the app folder, which makes OneDrive create it.
  Future<void> _ensureFolder() async {
    final response = await _graph('GET', root);
    if (response.statusCode != 200) throw _failure(response, 'folder');
  }

  Future<void> _uploadSession(
    String name,
    Uint8List bytes,
    String what,
    String behavior,
  ) async {
    final request = utf8.encode(
      jsonEncode({
        'item': {'@microsoft.graph.conflictBehavior': behavior},
      }),
    );
    Future<http.Response> open() => _graph(
      'POST',
      _item(name, ':/createUploadSession'),
      headers: const {'Content-Type': 'application/json'},
      body: request,
    );
    var response = await open();
    if (response.statusCode == 404) {
      await _ensureFolder();
      response = await open();
    }
    if (!_ok(response.statusCode)) throw _failure(response, what);
    final raw = _json(response, what)['uploadUrl'];
    final uploadUrl = raw is String ? Uri.tryParse(raw) : null;
    if (uploadUrl == null || uploadUrl.scheme != 'https') {
      throw SyncRemoteException(SyncRemoteFailure.protocol, '$what: no url');
    }
    try {
      var start = 0;
      while (true) {
        final end = min(start + chunkSize, bytes.length);
        // The upload link is pre-authenticated: no access token.
        final part = await _send(
          'PUT',
          uploadUrl,
          headers: {'Content-Range': 'bytes $start-${end - 1}/${bytes.length}'},
          body: Uint8List.sublistView(bytes, start, end),
        );
        if (_ok(part.statusCode)) return;
        if (part.statusCode != 202) throw _failure(part, what);
        final next = _nextRange(part) ?? end;
        if (next <= start || next >= bytes.length) {
          throw SyncRemoteException(
            SyncRemoteFailure.protocol,
            '$what: upload stalled',
          );
        }
        start = next;
      }
    } catch (_) {
      // Best effort: an abandoned session expires on its own.
      unawaited(
        _send('DELETE', uploadUrl).then((_) {}, onError: (Object _) {}),
      );
      rethrow;
    }
  }

  static int? _nextRange(http.Response response) {
    try {
      final json = jsonDecode(utf8.decode(response.bodyBytes));
      final ranges = json is Map ? json['nextExpectedRanges'] : null;
      if (ranges is! List || ranges.isEmpty || ranges.first is! String) {
        return null;
      }
      return int.tryParse((ranges.first as String).split('-').first);
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> delete(String name) async {
    final response = await _graph('DELETE', _item(name));
    final status = response.statusCode;
    if (status == 204 || status == 200 || status == 404) return;
    throw _failure(response, 'delete');
  }
}
