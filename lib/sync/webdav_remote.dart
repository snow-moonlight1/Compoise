/// WebDAV transport: a folder named `Compoise` under the address the user
/// enters, for example a NAS, Nextcloud or 坚果云.
///
/// Only five verbs are used: PROPFIND (depth 1) to list, GET, PUT, MKCOL and
/// DELETE. Nothing depends on locking, moves or server-side copies, which
/// small servers often get wrong.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import 'sync_http.dart';
import 'sync_remote.dart';

/// The non-secret half of a WebDAV connection. The password lives in secure
/// storage.
class WebDavSettings {
  const WebDavSettings({required this.url, required this.username});

  /// The server address, normalized by [normalizeWebDavUrl].
  final String url;
  final String username;

  Map<String, dynamic> toJson() => {'url': url, 'username': username};

  static WebDavSettings? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final url = raw['url'];
    final username = raw['username'];
    if (url is! String || username is! String) return null;
    if (normalizeWebDavUrl(url) == null) return null;
    return WebDavSettings(url: url, username: username);
  }
}

/// Returns the address with a trailing slash, or null when it is not an
/// http(s) URL with a host. Query strings, fragments and inline credentials
/// are refused: they would travel with every file request.
Uri? normalizeWebDavUrl(String input) {
  final uri = Uri.tryParse(input.trim());
  if (uri == null ||
      (uri.scheme != 'https' && uri.scheme != 'http') ||
      uri.host.isEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      uri.userInfo.isNotEmpty) {
    return null;
  }
  final path = uri.path.endsWith('/') ? uri.path : '${uri.path}/';
  return uri.replace(path: path);
}

/// True for plain http to a host that is not obviously on the local network.
/// The settings page warns before saving such an address.
bool isInsecureWebDavUrl(Uri uri) {
  if (uri.scheme != 'http') return false;
  final host = uri.host;
  if (host == 'localhost' || host.endsWith('.local')) return false;
  final parts = host.split('.').map(int.tryParse).toList();
  if (parts.length == 4 && parts.every((part) => part != null)) {
    final a = parts[0]!, b = parts[1]!;
    if (a == 10 || a == 127) return false;
    if (a == 192 && b == 168) return false;
    if (a == 172 && b >= 16 && b <= 31) return false;
  }
  return true;
}

class WebDavRemote implements SyncRemote {
  WebDavRemote({
    required Uri baseUrl,
    required String username,
    required String password,
    http.Client? client,
    this.folder = 'Compoise',
    this.timeout = const Duration(seconds: 60),
  }) : _base = normalizeWebDavUrl(baseUrl.toString()) ?? baseUrl,
       _auth = 'Basic ${base64Encode(utf8.encode('$username:$password'))}',
       _client = client ?? http.Client(),
       _ownsClient = client == null;

  final Uri _base;
  final String _auth;
  final http.Client _client;
  final bool _ownsClient;
  final String folder;
  final Duration timeout;

  @override
  String get label => 'webdav';

  Uri get folderUri => _base.resolve('${Uri.encodeComponent(folder)}/');

  Uri _fileUri(String name) => folderUri.resolve(Uri.encodeComponent(name));

  void close() {
    if (_ownsClient) _client.close();
  }

  Future<http.Response> _send(
    String method,
    Uri uri, {
    Map<String, String> headers = const {},
    List<int>? body,
  }) async {
    final request = http.Request(method, uri)
      ..followRedirects = false
      ..headers['Authorization'] = _auth
      ..headers.addAll(headers);
    if (body != null) request.bodyBytes = body;
    return sendSyncRequest(_client, request, timeout);
  }

  static SyncRemoteException _failure(http.Response response, String what) {
    final status = response.statusCode;
    final retryAfter = parseRetryAfter(response.headers['retry-after']);
    final kind = switch (status) {
      401 => SyncRemoteFailure.auth,
      403 => SyncRemoteFailure.forbidden,
      404 || 410 => SyncRemoteFailure.notFound,
      413 || 507 => SyncRemoteFailure.quota,
      429 => SyncRemoteFailure.rateLimited,
      503 when retryAfter != null => SyncRemoteFailure.rateLimited,
      >= 500 && < 600 => SyncRemoteFailure.server,
      _ => SyncRemoteFailure.protocol,
    };
    return SyncRemoteException(kind, '$what: HTTP $status', retryAfter);
  }

  static const _propfindBody =
      '<?xml version="1.0" encoding="utf-8"?>'
      '<d:propfind xmlns:d="DAV:"><d:prop>'
      '<d:resourcetype/><d:getetag/><d:getlastmodified/>'
      '<d:getcontentlength/>'
      '</d:prop></d:propfind>';

  @override
  Future<List<RemoteEntry>> list() async {
    final response = await _send(
      'PROPFIND',
      folderUri,
      headers: const {
        'Depth': '1',
        'Content-Type': 'application/xml; charset=utf-8',
      },
      body: utf8.encode(_propfindBody),
    );
    if (response.statusCode == 404) return const [];
    if (response.statusCode != 207) throw _failure(response, 'list');
    try {
      return parsePropfind(
        utf8.decode(response.bodyBytes, allowMalformed: true),
        folderUri,
      );
    } on XmlException catch (error) {
      throw SyncRemoteException(SyncRemoteFailure.protocol, error.message);
    } on FormatException catch (error) {
      throw SyncRemoteException(SyncRemoteFailure.protocol, error.message);
    }
  }

  @override
  Future<Uint8List> read(String name) async {
    final response = await _send('GET', _fileUri(name));
    if (response.statusCode != 200) throw _failure(response, 'read');
    return response.bodyBytes;
  }

  Future<http.Response> _put(String name, Uint8List bytes, bool create) =>
      _send(
        'PUT',
        _fileUri(name),
        headers: {
          'Content-Type': 'application/octet-stream',
          if (create) 'If-None-Match': '*',
        },
        body: bytes,
      );

  static bool _done(int status) =>
      status == 200 || status == 201 || status == 204;

  Future<void> _store(
    String name,
    Uint8List bytes, {
    bool create = false,
  }) async {
    var response = await _put(name, bytes, create);
    // A missing folder answers 409 on most servers, 404 or 403 on a few.
    if (response.statusCode == 409 ||
        response.statusCode == 404 ||
        response.statusCode == 403) {
      if (!await _makeFolder()) throw _failure(response, 'write');
      response = await _put(name, bytes, create);
    }
    if (_done(response.statusCode)) return;
    if (create && response.statusCode == 412) {
      throw SyncRemoteException(SyncRemoteFailure.conflict, name);
    }
    throw _failure(response, 'write');
  }

  /// True when the folder was created now; false when it already existed,
  /// so the failure that led here had another cause.
  Future<bool> _makeFolder() async {
    final response = await _send('MKCOL', folderUri);
    if (response.statusCode == 201) return true;
    if (response.statusCode == 405) return false;
    if (response.statusCode == 409) {
      // The parent of the folder is missing: the address itself is wrong.
      throw const SyncRemoteException(
        SyncRemoteFailure.notFound,
        'mkcol: base folder missing',
      );
    }
    throw _failure(response, 'mkcol');
  }

  @override
  Future<void> write(String name, Uint8List bytes) => _store(name, bytes);

  @override
  Future<void> create(String name, Uint8List bytes) async {
    // Not every server honours If-None-Match on PUT, so look first. The
    // engine reads the result back, which catches a lost race either way.
    final existing = await list();
    if (existing.any((entry) => entry.name == name)) {
      throw SyncRemoteException(SyncRemoteFailure.conflict, name);
    }
    await _store(name, bytes, create: true);
  }

  @override
  Future<void> delete(String name) async {
    final response = await _send('DELETE', _fileUri(name));
    if (_done(response.statusCode) || response.statusCode == 404) return;
    throw _failure(response, 'delete');
  }
}

/// Files directly inside [folder] from a depth-1 PROPFIND answer. The folder
/// itself and sub-collections are skipped.
List<RemoteEntry> parsePropfind(String body, Uri folder) {
  final document = XmlDocument.parse(body);
  final folderPath = _trimSlash(Uri.decodeFull(folder.path));
  final entries = <RemoteEntry>[];
  for (final response in document.descendantElements.where(
    (element) => element.localName == 'response',
  )) {
    final href = _child(response, 'href')?.innerText.trim();
    if (href == null || href.isEmpty) continue;
    final path = _trimSlash(Uri.decodeFull(folder.resolve(href).path));
    final slash = path.lastIndexOf('/');
    if (path == folderPath || slash < 0) continue;
    if (path.substring(0, slash) != folderPath) continue;
    final name = path.substring(slash + 1);
    if (name.isEmpty) continue;
    XmlElement? prop;
    for (final propstat in response.childElements.where(
      (element) => element.localName == 'propstat',
    )) {
      final status = _child(propstat, 'status')?.innerText ?? '';
      if (RegExp(r'\s200\b').hasMatch(status)) prop = _child(propstat, 'prop');
    }
    if (prop == null) continue;
    final type = _child(prop, 'resourcetype');
    if (type != null && _child(type, 'collection') != null) continue;
    final etag = _child(prop, 'getetag')?.innerText.trim();
    final modified = _child(prop, 'getlastmodified')?.innerText.trim();
    final size = int.tryParse(
      _child(prop, 'getcontentlength')?.innerText.trim() ?? '',
    );
    entries.add(
      RemoteEntry(
        name: name,
        version: etag != null && etag.isNotEmpty
            ? etag
            : 'm:${modified ?? ''}|${size ?? ''}',
        size: size,
      ),
    );
  }
  return entries;
}

XmlElement? _child(XmlElement parent, String localName) {
  for (final element in parent.childElements) {
    if (element.localName == localName) return element;
  }
  return null;
}

String _trimSlash(String path) =>
    path.endsWith('/') ? path.substring(0, path.length - 1) : path;
