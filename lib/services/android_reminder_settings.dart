import 'package:flutter/services.dart';

class AndroidReminderStatus {
  const AndroidReminderStatus({
    required this.notifications,
    required this.exactAlarms,
    required this.background,
    required this.autoStartAvailable,
    this.autoStart,
  });
  final bool notifications;
  final bool exactAlarms;
  final bool background;
  // Null means the manufacturer does not expose a readable state.
  final bool? autoStart;
  final bool autoStartAvailable;
  bool get granted => notifications && exactAlarms && background;
}

class AndroidReminderSettings {
  const AndroidReminderSettings();
  static const channel = MethodChannel('compoise/reminder_settings');

  Future<AndroidReminderStatus?> status() async {
    try {
      final values = await channel.invokeMapMethod<String, dynamic>('status');
      if (values == null) return null;
      return AndroidReminderStatus(
        notifications: values['notifications'] == true,
        exactAlarms: values['exactAlarms'] == true,
        background: values['background'] == true,
        autoStartAvailable: values['autoStartAvailable'] == true,
        autoStart: values['autoStart'] is bool
            ? values['autoStart'] as bool
            : null,
      );
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// Completes when the user returns, not merely when Settings is launched.
  Future<bool> open(String setting) async {
    try {
      return await channel.invokeMethod<bool>('open', {'setting': setting}) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
