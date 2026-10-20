/// HTTP plumbing shared by the cloud transports: network failures become
/// [SyncRemoteException]s and `Retry-After` is read the same way everywhere.
library;

import 'dart:async';
import 'dart:io'
    show HandshakeException, HttpDate, HttpException, SocketException;

import 'package:http/http.dart' as http;

import 'sync_remote.dart';

/// Sends [request] and reads the whole answer. Connection problems and
/// timeouts throw [SyncRemoteFailure.network].
Future<http.Response> sendSyncRequest(
  http.Client client,
  http.BaseRequest request,
  Duration timeout,
) async {
  try {
    final streamed = await client.send(request).timeout(timeout);
    return await http.Response.fromStream(streamed).timeout(timeout);
  } on TimeoutException {
    throw const SyncRemoteException(SyncRemoteFailure.network, 'timeout');
  } on SocketException catch (error) {
    throw SyncRemoteException(SyncRemoteFailure.network, error.message);
  } on HandshakeException catch (error) {
    throw SyncRemoteException(SyncRemoteFailure.network, error.message);
  } on HttpException catch (error) {
    throw SyncRemoteException(SyncRemoteFailure.network, error.message);
  } on http.ClientException catch (error) {
    throw SyncRemoteException(SyncRemoteFailure.network, error.message);
  }
}

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
