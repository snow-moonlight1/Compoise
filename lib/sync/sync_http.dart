/// HTTP plumbing shared by the cloud transports: network failures become
/// [SyncRemoteException]s and `Retry-After` is read the same way everywhere.
library;

import 'dart:async';
import 'dart:io'
    show HandshakeException, HttpDate, HttpException, SocketException;

import 'package:http/http.dart' as http;

import 'sync_remote.dart';

/// Sends [request] and reads the whole answer. Connection problems and
/// timeouts throw [SyncRemoteFailure.network], with the method, host and the
/// system's reason in the message (never the path, query or headers).
///
/// A connection that breaks before any answer arrives is tried once more
/// after [retryDelay]: servers often drop a kept-alive connection just as the
/// client reuses it. Timeouts and TLS failures are not retried.
Future<http.Response> sendSyncRequest(
  http.Client client,
  http.Request request,
  Duration timeout, {
  Duration retryDelay = const Duration(milliseconds: 500),
}) async {
  String reason(String message) =>
      '${request.method} ${request.url.host}: $message';
  var current = request;
  for (var attempt = 0; ; attempt++) {
    final http.StreamedResponse streamed;
    try {
      streamed = await client.send(current).timeout(timeout);
    } on TimeoutException {
      throw SyncRemoteException(SyncRemoteFailure.network, reason('timeout'));
    } on HandshakeException catch (error) {
      throw SyncRemoteException(
        SyncRemoteFailure.network,
        reason(error.message),
      );
    } on Exception catch (error) {
      final message = _connectionFailure(error);
      if (message == null) rethrow;
      if (attempt == 0) {
        await Future<void>.delayed(retryDelay);
        current = _copy(request);
        continue;
      }
      throw SyncRemoteException(SyncRemoteFailure.network, reason(message));
    }
    try {
      return await http.Response.fromStream(streamed).timeout(timeout);
    } on TimeoutException {
      throw SyncRemoteException(SyncRemoteFailure.network, reason('timeout'));
    } on Exception catch (error) {
      final message = _connectionFailure(error);
      if (message == null) rethrow;
      throw SyncRemoteException(SyncRemoteFailure.network, reason(message));
    }
  }
}

String? _connectionFailure(Exception error) => switch (error) {
  SocketException(:final message) => message.isEmpty ? 'socket' : message,
  HttpException(:final message) => message,
  http.ClientException(:final message) => message,
  _ => null,
};

http.Request _copy(http.Request original) =>
    http.Request(original.method, original.url)
      ..followRedirects = original.followRedirects
      ..maxRedirects = original.maxRedirects
      ..persistentConnection = original.persistentConnection
      ..headers.addAll(original.headers)
      ..bodyBytes = original.bodyBytes;

/// A `Retry-After` header in seconds or as an HTTP date, capped at an hour.
Duration? parseRetryAfter(String? header, {DateTime? now}) {
  if (header == null) return null;
  const cap = Duration(hours: 1);
  final seconds = int.tryParse(header.trim());
  if (seconds != null) {
    return seconds <= 0
        ? Duration.zero
        : (seconds > cap.inSeconds ? cap : Duration(seconds: seconds));
  }
  try {
    final wait = HttpDate.parse(
      header,
    ).difference((now ?? DateTime.now()).toUtc());
    if (wait.isNegative) return Duration.zero;
    return wait > cap ? cap : wait;
  } on HttpException {
    return null;
  } on FormatException {
    return null;
  }
}
