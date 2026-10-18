// ignore_for_file: invalid_use_of_visible_for_testing_member

/// Run under a test D-Bus session (scripts/tests/linux_desktop_bus.py).
/// Uses only synthetic in-memory preferences; never touches a user's library.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'package:compoise/models.dart';
import 'package:compoise/services/desktop_shell_windows.dart';
import 'package:compoise/services/desktop_shell_service.dart';
import 'package:compoise/services/reminder_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final output = Platform.environment['COMPOISE_LINUX_SMOKE_RESULT'];
  if (!Platform.isLinux || output == null) exit(2);
  SharedPreferences.setMockInitialValues({
    'compoise-settings': jsonEncode({'language': 'en'}),
  });
  final facts = <String, dynamic>{};
  try {
    await ensureWindowsWindowManager();
    final shell = DesktopShellService.instance;
    final settings = await shell.applySettings(
      closeToTray: true,
      globalShortcut: '',
      language: Language.en,
    );
    facts['trayInitialized'] = settings.tray.succeeded;
    facts['closeToTrayEffective'] = settings.closeToTrayEffective;
    final hidden = await shell.hideWindowToTray();
    facts['hidden'] = hidden.succeeded && !await windowManager.isVisible();
    shell.restoreWindow();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    facts['restored'] = await windowManager.isVisible();
    final reminders = FlutterLocalNotificationsReminderService(
      ledgerStore: InMemoryReminderLedgerStore(),
    );
    await reminders.init();
    final now = DateTime.now().millisecondsSinceEpoch;
    final scheduled = await reminders.scheduleReminder(
      boardId: 'synthetic',
      taskId: 'future',
      title: 'Synthetic scheduled reminder',
      triggerAtMs: now + 1500,
    );
    facts['inAppSchedule'] =
        scheduled.status == ReminderScheduleStatus.scheduledInApp;
    var delivered = false;
    for (var attempt = 0; attempt < 40; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(
        FlutterLocalNotificationsReminderService.linuxDeliveredKey,
      );
      if (raw != null &&
          (jsonDecode(raw) as Map)['${generateNotificationId('future')}'] ==
              now + 1500) {
        delivered = true;
        break;
      }
    }
    facts['scheduledDeliveryRecorded'] = delivered;
    final tasks = [
      Task(
        id: 'future',
        boardId: 'synthetic',
        title: 'Synthetic',
        quadrant: 2,
        createdAt: 1,
        reminderAt: now + 1500,
      ),
      Task(
        id: 'missed',
        boardId: 'synthetic',
        title: 'Synthetic missed',
        quadrant: 2,
        createdAt: 1,
        reminderAt: now - 3600000,
      ),
    ];
    await reminders.rescheduleAllFuture(tasks);
    await reminders.rescheduleAllFuture(tasks);
    facts['timersSettled'] = reminders.activeTimerCount == 0;
    await reminders.cancelAll();
    await shell.exitApplication();
    facts['passed'] = facts.values.every((v) => v == true);
  } catch (e) {
    facts['passed'] = false;
    facts['errorType'] = '${e.runtimeType}';
  }
  await File(output).writeAsString(jsonEncode(facts));
  exit(facts['passed'] == true ? 0 : 1);
}
