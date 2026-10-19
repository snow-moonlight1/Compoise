// A small in-memory WebDAV server behind package:http's MockClient. It speaks
// the subset the sync transport uses and can be told to misbehave like the
// servers seen in the wild.
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class FakeDavServer {
  FakeDavServer({
    this.root = '/dav/',
    this.username = 'user',
    this.password = 'secret',
  }) {
    folders.add(root);
  }

  final String root;
  final String username;
  String password;

  /// Decoded absolute paths.
  final Map<String, Uint8List> files = {};
  final Set<String> folders = {};
  final Map<String, int> _etags = {};
  int _counter = 0;

  /// Status for PUT into a missing folder; real servers use 409, 404 or 403.
  int missingParentStatus = 409;
  bool honourIfNoneMatch = true;

  /// Hrefs as full URLs instead of absolute paths.
  bool absoluteHrefs = false;
  bool omitEtags = false;

  /// Answers queued for the next requests of a method, then normal service.
  final Map<String, List<http.Response>> faults = {};
  final List<String> log = [];

  MockClient get client => MockClient(handle);

  void failNext(String method, http.Response response) =>
      (faults[method] ??= []).add(response);

  Future<http.Response> handle(http.Request request) async {
    final path = Uri.decodeFull(request.url.path);
    log.add('${request.method} $path');
    final queued = faults[request.method];
    if (queued != null && queued.isNotEmpty) return queued.removeAt(0);
    final expected =
        'Basic ${base64Encode(utf8.encode('$username:$password'))}';
    if (request.headers['Authorization'] != expected) {
      return http.Response('', 401);
    }
    switch (request.method) {
      case 'PROPFIND':
        return _propfind(request, path);
      case 'GET':
        final bytes = files[path];
        return bytes == null
            ? http.Response('', 404)
            : http.Response.bytes(bytes, 200);
      case 'PUT':
        if (!folders.contains(_parent(path))) {
          return http.Response('', missingParentStatus);
        }
        if (honourIfNoneMatch &&
            request.headers['If-None-Match'] == '*' &&
            files.containsKey(path)) {
          return http.Response('', 412);
        }
        final existed = files.containsKey(path);
        files[path] = request.bodyBytes;
        _etags[path] = ++_counter;
        return http.Response('', existed ? 204 : 201);
      case 'MKCOL':
        final folder = path.endsWith('/') ? path : '$path/';
        if (folders.contains(folder)) return http.Response('', 405);
        if (!folders.contains(_parent(folder))) return http.Response('', 409);
        folders.add(folder);
        return http.Response('', 201);
      case 'DELETE':
        if (files.remove(path) == null) return http.Response('', 404);
        return http.Response('', 204);
    }
    return http.Response('', 405);
  }

  static String _parent(String path) {
    final trimmed = path.endsWith('/')
        ? path.substring(0, path.length - 1)
        : path;
    return trimmed.substring(0, trimmed.lastIndexOf('/') + 1);
  }

  String _href(String path) {
    final encoded = Uri(path: path).toString();
    return absoluteHrefs ? 'https://dav.example.com$encoded' : encoded;
  }

  http.Response _propfind(http.Request request, String path) {
    final folder = path.endsWith('/') ? path : '$path/';
    if (!folders.contains(folder)) return http.Response('', 404);
    if (request.headers['Depth'] != '1') return http.Response('', 400);
    final body = StringBuffer(
      '<?xml version="1.0" encoding="utf-8"?>'
      '<D:multistatus xmlns:D="DAV:">',
    );
    void entry(String href, {bool collection = false, String? file}) {
      body.write('<D:response><D:href>${_href(href)}</D:href><D:propstat>');
      body.write('<D:prop><D:resourcetype>');
      if (collection) body.write('<D:collection/>');
      body.write('</D:resourcetype>');
      if (file != null) {
        if (!omitEtags) {
          body.write('<D:getetag>"${_etags[file]}"</D:getetag>');
        }
        body.write(
          '<D:getcontentlength>${files[file]!.length}</D:getcontentlength>'
          '<D:getlastmodified>Mon, 01 Jan 2025 00:00:0${_etags[file]! % 10} GMT'
          '</D:getlastmodified>',
        );
      }
      body.write('</D:prop><D:status>HTTP/1.1 200 OK</D:status></D:propstat>');
      if (file == null) {
        body.write(
          '<D:propstat><D:prop><D:getetag/></D:prop>'
          '<D:status>HTTP/1.1 404 Not Found</D:status></D:propstat>',
        );
      }
      body.write('</D:response>');
    }

    entry(folder, collection: true);
    for (final child in folders) {
      if (child != folder && _parent(child) == folder) {
        entry(child, collection: true);
      }
    }
    for (final file in files.keys) {
      if (_parent(file) == folder) entry(file, file: file);
    }
    body.write('</D:multistatus>');
    return http.Response(
      body.toString(),
      207,
      headers: {'content-type': 'application/xml; charset=utf-8'},
    );
  }
}
