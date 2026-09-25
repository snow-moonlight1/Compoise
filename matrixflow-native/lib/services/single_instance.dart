import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'reminder_service.dart';

/// Command-line prefix carrying a notification [ReminderPayload].
const String kSingleInstanceNotificationArgument =
    '--matrixflow-notification-payload=';

/// Reads the notification task payload from a Windows launch argument list.
ReminderPayload? notificationPayloadFromArguments(List<String> args) {
  for (final arg in args) {
    if (!arg.startsWith(kSingleInstanceNotificationArgument)) continue;
    final raw = arg.substring(kSingleInstanceNotificationArgument.length);
    return ReminderPayload.deserialize(_decodeArgument(raw));
  }
  return null;
}

String _decodeArgument(String raw) {
  if (!raw.contains('%')) return raw;
  try {
    return Uri.decodeComponent(raw);
  } catch (_) {
    return raw;
  }
}

/// Restores the running window and, when present, delivers the task payload.
void dispatchSingleInstanceActivation(
  List<String> args, {
  required void Function() restoreWindow,
  required void Function(ReminderPayload payload) deliverPayload,
}) {
  restoreWindow();
  final payload = notificationPayloadFromArguments(args);
  if (payload != null && payload.taskId.isNotEmpty) {
    deliverPayload(payload);
  }
}

/// Listens for command lines forwarded by later Windows launches.
class SingleInstanceController {
  static const MethodChannel _channel = MethodChannel(
    'matrixflow/single_instance',
  );

  static bool get _platformEnabled {
    if (kIsWeb) return false;
    if (defaultTargetPlatform != TargetPlatform.windows) return false;
    try {
      if (Platform.environment.containsKey('FLUTTER_TEST')) return false;
    } catch (_) {}
    return true;
  }

  /// [onActivated] receives every later launch, including those with no payload.
  /// The primary process's own arguments are delivered only when they carry a
  /// notification payload.
  static Future<void> install({
    List<String> initialArguments = const [],
    void Function(List<String> args)? onActivated,
  }) async {
    final initialPayload = notificationPayloadFromArguments(initialArguments);
    if (initialPayload != null && initialPayload.taskId.isNotEmpty) {
      onActivated?.call(initialArguments);
    }
    if (!_platformEnabled || onActivated == null) return;

    _channel.setMethodCallHandler((call) async {
      if (call.method != 'onSecondInstance') return;
      onActivated(_argumentList(call.arguments));
    });

    for (var attempt = 0; attempt < 20; attempt++) {
      try {
        final pending = await _channel.invokeMethod<dynamic>('listen');
        if (pending is List) {
          for (final item in pending) {
            onActivated(_argumentList(item));
          }
        }
        return;
      } on MissingPluginException {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
  }

  static List<String> _argumentList(Object? value) {
    if (value is! List) return const [];
    return value.map((item) => '$item').toList();
  }
}

/// Visible for tests that want the encoded form used on the command line.
String encodeNotificationPayloadArgument(ReminderPayload payload) {
  return '$kSingleInstanceNotificationArgument${Uri.encodeComponent(jsonEncode(payload.toJson()))}';
}
