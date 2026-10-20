/// The platform half of the browser sign-in: opening the system browser and
/// receiving the redirect it is sent back with.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'onedrive_auth.dart';

/// A one-time web server on the loopback address. Microsoft accepts any
/// port for the registered `http://localhost` redirect of a desktop app.
class LoopbackRedirectListener implements OAuthRedirectListener {
  LoopbackRedirectListener._(this._servers, this._page) {
    for (final server in _servers) {
      server.listen(_serve, onError: (Object _) {});
    }
  }

  /// Listens on 127.0.0.1 and, when available, ::1 on the same port, since
  /// the browser may resolve `localhost` to either.
  static Future<LoopbackRedirectListener> bind({
    required String donePage,
  }) async {
    final v4 = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final servers = [v4];
    try {
      servers.add(await HttpServer.bind(InternetAddress.loopbackIPv6, v4.port));
    } on SocketException {
      // No IPv6 loopback on this machine.
    }
    return LoopbackRedirectListener._(servers, donePage);
  }

  final List<HttpServer> _servers;
  final String _page;
  final _redirects = StreamController<Uri>.broadcast();
  bool _closed = false;

  int get port => _servers.first.port;

  @override
  String get redirectUri => 'http://localhost:$port';

  @override
  Stream<Uri> get redirects => _redirects.stream;

  Future<void> _serve(HttpRequest request) async {
    final params = request.uri.queryParameters;
    final answer =
        request.method == 'GET' &&
        request.uri.path == '/' &&
        (params.containsKey('code') || params.containsKey('error'));
    final response = request.response;
    if (!answer) {
      response.statusCode = HttpStatus.notFound;
      await response.close().catchError((Object _) {});
      return;
    }
    final text = const HtmlEscape().convert(_page);
    response.headers
      ..contentType = ContentType.html
      ..set(HttpHeaders.cacheControlHeader, 'no-store');
    response.write(
      '<!doctype html><html><head><meta charset="utf-8">'
      '<meta name="viewport" content="width=device-width">'
      '<title>Compoise</title></head>'
      '<body style="font-family:sans-serif;margin:3em;line-height:1.6">'
      '<p>$text</p></body></html>',
    );
    await response.close().catchError((Object _) {});
    if (!_closed) _redirects.add(request.uri);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    for (final server in _servers) {
      await server.close(force: true);
    }
    await _redirects.close();
  }
}

/// The Android activity receives `com.compoise.app://oauth?...` and hands it
/// over through this channel. It also opens the browser.
const oauthChannel = MethodChannel('compoise/oauth');

class AndroidRedirectListener implements OAuthRedirectListener {
  AndroidRedirectListener._();

  static Future<AndroidRedirectListener> start() async {
    final listener = AndroidRedirectListener._();
    // A redirect left over from an earlier attempt, for example one the
    // app was restarted with, cannot be redeemed any more.
    await oauthChannel.invokeMethod<String>('takeRedirect');
    oauthChannel.setMethodCallHandler((call) async {
      if (call.method == 'redirect') await listener._take();
    });
    return listener;
  }

  final _redirects = StreamController<Uri>.broadcast();
  bool _closed = false;

  @override
  String get redirectUri => oneDriveAndroidRedirect;

  @override
  Stream<Uri> get redirects => _redirects.stream;

  Future<void> _take() async {
    final raw = await oauthChannel.invokeMethod<String>('takeRedirect');
    final uri = raw == null ? null : Uri.tryParse(raw);
    if (uri != null && !_closed) _redirects.add(uri);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    oauthChannel.setMethodCallHandler(null);
    await _redirects.close();
  }
}

/// Opens [url] in the default browser. False when no browser could be
/// started; the sign-in dialog then offers the link for copying.
Future<bool> openInSystemBrowser(Uri url) async {
  final link = url.toString();
  try {
    if (Platform.isAndroid) {
      return await oauthChannel.invokeMethod<bool>('open', {'url': link}) ??
          false;
    }
    if (Platform.isWindows) {
      // No shell in between, so the & in the address stays intact.
      await Process.start('rundll32', [
        'url.dll,FileProtocolHandler',
        link,
      ], mode: ProcessStartMode.detached);
      return true;
    }
    if (Platform.isMacOS) {
      await Process.start('open', [link], mode: ProcessStartMode.detached);
      return true;
    }
    await Process.start('xdg-open', [link], mode: ProcessStartMode.detached);
    return true;
  } on ProcessException {
    return false;
  } on PlatformException {
    return false;
  } on MissingPluginException {
    return false;
  }
}

/// The real sign-in for this platform.
OneDriveAuthorizer platformOneDriveAuthorizer() => BrowserOneDriveAuthorizer(
  listen: (donePage) async => Platform.isAndroid
      ? await AndroidRedirectListener.start()
      : await LoopbackRedirectListener.bind(donePage: donePage),
  open: openInSystemBrowser,
);
