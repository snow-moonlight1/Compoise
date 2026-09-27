import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../storage.dart';

Future<void> showReminderAccessFeedback(BuildContext context) async {
  final status = await requestReminderAccess();
  if (!context.mounted) return;
  final t = context.read<Store>().t;
  if (status == ReminderPermissionStatus.denied ||
      status == ReminderPermissionStatus.unsupported) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          t['notifPermissionDenied'] ??
              'Notification permission denied; reminder is saved but may not fire',
        ),
      ),
    );
  } else if (status == ReminderPermissionStatus.inexactOnly) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          t['exactAlarmRestricted'] ??
              'Exact alarms restricted; reminder may be delayed',
        ),
      ),
    );
  }
}
