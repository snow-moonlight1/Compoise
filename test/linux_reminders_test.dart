import 'dart:async';
import 'dart:io';
import 'package:compoise/models.dart';
import 'package:compoise/services/linux_autostart.dart';
import 'package:compoise/services/reminder_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Plugin implements FlutterLocalNotificationsPlugin {
  final shown = <int>[];
  final bodies = <String?>[];
  @override
  dynamic noSuchMethod(Invocation call) {
    if (call.memberName == #show) {
      shown.add(call.positionalArguments[0] as int);
      bodies.add(call.positionalArguments[2] as String?);
    }
    if (call.memberName == #initialize) return Future<bool?>.value(true);
    return Future<void>.value();
  }
}

class _BrokenBusPlugin extends _Plugin {
  @override
  dynamic noSuchMethod(Invocation call) {
    if (call.memberName == #initialize) {
      Timer.run(() => throw StateError('Synthetic disconnected bus'));
      return Future<bool?>.value(true);
    }
    return super.noSuchMethod(call);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test('asynchronous Linux bus failures do not escape the backend', () async {
    final service = FlutterLocalNotificationsReminderService(
      plugin: _BrokenBusPlugin(), ledgerStore: InMemoryReminderLedgerStore());
    await service.init();
    await Future<void>.delayed(Duration.zero);
    expect(await service.probePermission(), ReminderPermissionStatus.unsupported);
  });

  test(
    'Linux uses in-app timers, replaces edits and cancels before delivery',
    () async {
      final plugin = _Plugin();
      final service = FlutterLocalNotificationsReminderService(
        plugin: plugin,
        ledgerStore: InMemoryReminderLedgerStore(),
      );
      service.setInitializedForTest(true);
      var now = DateTime(2026, 10, 19);
      service.clock = () => now;
      final callbacks = <void Function()>[];
      service.createTimer = (delay, callback) {
        callbacks.add(callback);
        return Timer(const Duration(days: 1), () {});
      };
      Future<ReminderScheduleResult> schedule(int ms) =>
          service.scheduleReminder(
            boardId: 'b',
            taskId: 'task',
            title: 'Synthetic',
            triggerAtMs: ms,
          );
      final first = await schedule(now.millisecondsSinceEpoch + 1000);
      expect(first.status, ReminderScheduleStatus.scheduledInApp);
      await schedule(now.millisecondsSinceEpoch + 2000);
      callbacks.first();
      await Future<void>.delayed(Duration.zero);
      expect(plugin.shown, isEmpty);
      await service.cancelReminder('task');
      callbacks.last();
      await Future<void>.delayed(Duration.zero);
      expect(plugin.shown, isEmpty);
      await service.cancelAll();
      expect(service.activeTimerCount, 0);
    },
  );

  test(
    'missed parent and child reminders are summarized once across restarts',
    () async {
      final plugin = _Plugin();
      final now = DateTime(2026, 10, 19);
      final task = Task(
        id: 'task',
        boardId: 'b',
        title: 'Synthetic',
        quadrant: 2,
        createdAt: 0,
        reminderAt: now
            .subtract(const Duration(days: 1))
            .millisecondsSinceEpoch,
        subtasks: [
          SubTask(
            id: 's',
            title: 'Step',
            reminderAt: now
                .subtract(const Duration(hours: 1))
                .millisecondsSinceEpoch,
          ),
        ],
      );
      Future<void> boot() async {
        final service = FlutterLocalNotificationsReminderService(
          plugin: plugin,
          ledgerStore: InMemoryReminderLedgerStore(),
        );
        service.clock = () => now;
        service.setInitializedForTest(true);
        await service.rescheduleAllFuture([task]);
      }

      await boot();
      expect(plugin.shown, hasLength(1));
      expect(plugin.bodies.single, contains('2'));
      await boot();
      expect(plugin.shown, hasLength(1));
    },
  );

  test(
    'autostart is opt-in, quotes paths, and only removes its own entry',
    () async {
      final dir = await Directory.systemTemp.createTemp('compoise-autostart-');
      addTearDown(() => dir.delete(recursive: true));
      final setting = LinuxAutostart(
        config: dir,
        executable: '/opt/Compoise Test/compoise',
      );
      expect(await setting.isEnabled(), isFalse);
      await setting.setEnabled(true);
      expect(
        await setting.file.readAsString(),
        contains('Exec="/opt/Compoise Test/compoise"'),
      );
      final unrelated = File('${setting.file.parent.path}/other.desktop');
      await unrelated.writeAsString('untouched');
      await setting.setEnabled(false);
      expect(await setting.isEnabled(), isFalse);
      expect(await unrelated.readAsString(), 'untouched');
    },
  );
}
