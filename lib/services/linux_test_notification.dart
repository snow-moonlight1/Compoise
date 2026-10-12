import 'dart:async';
import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Linux has no scheduled reminder backend; the settings test button talks to
/// the desktop's notification service (org.freedesktop.Notifications) once,
/// so it can report honestly whether anything was shown.
///
/// Returns false when there is no session bus, no notification service, or
/// the service rejects the request.
Future<bool> sendLinuxTestNotification({
  required String title,
  required String body,
  FlutterLocalNotificationsPlugin? plugin,
}) async {
  if (plugin == null && !_sessionBusLikelyReachable()) return false;
  final outcome = Completer<bool>();
  // The D-Bus client connects lazily; a connection failure can surface outside
  // the awaited call, so the whole attempt runs in its own guarded zone.
  runZonedGuarded(
    () async {
      final shown = await _send(title: title, body: body, plugin: plugin);
      if (!outcome.isCompleted) outcome.complete(shown);
    },
    (_, _) {
      if (!outcome.isCompleted) outcome.complete(false);
    },
  );
  return outcome.future.timeout(
    const Duration(seconds: 8),
    onTimeout: () => false,
  );
}

bool _sessionBusLikelyReachable() {
  final env = Platform.environment;
  final address = env['DBUS_SESSION_BUS_ADDRESS'];
  if (address != null && address.isNotEmpty) return true;
  final runtime = env['XDG_RUNTIME_DIR'];
  return runtime != null && File('$runtime/bus').existsSync();
}

Future<bool> _send({
  required String title,
  required String body,
  FlutterLocalNotificationsPlugin? plugin,
}) async {
  try {
    final notifications = plugin ?? FlutterLocalNotificationsPlugin();
    final ready = await notifications
        .initialize(
          const InitializationSettings(
            linux: LinuxInitializationSettings(defaultActionName: 'Open'),
          ),
        )
        .timeout(const Duration(seconds: 5));
    if (ready == false) return false;
    await notifications
        .show(
          0x7E57,
          title,
          body,
          const NotificationDetails(linux: LinuxNotificationDetails()),
        )
        .timeout(const Duration(seconds: 5));
    return true;
  } catch (_) {
    return false;
  }
}
