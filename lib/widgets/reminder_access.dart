import 'package:flutter/material.dart';
import 'app_notice.dart';
import 'package:provider/provider.dart';

import '../storage.dart';

Future<void> showReminderAccessFeedback(BuildContext context) async {
  final status = await requestReminderAccess();
  if (!context.mounted) return;
  final t = context.read<Store>().t;
  if (status == ReminderPermissionStatus.denied ||
      status == ReminderPermissionStatus.unsupported) {
    showAppNotice(
      context,
      t['notifPermissionDenied'] ??
          'Notification permission denied; reminder is saved but may not fire',
    );
  } else if (status == ReminderPermissionStatus.inexactOnly) {
    showAppNotice(
      context,
      t['exactAlarmRestricted'] ??
          'Exact alarms restricted; reminder may be delayed',
    );
  }
}
