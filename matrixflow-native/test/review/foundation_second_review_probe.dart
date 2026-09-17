// Explicit review probes. Synthetic data only; no real application is launched.
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/storage.dart';
import 'package:matrixflow_native/screens/matrix_screen.dart';
import 'package:matrixflow_native/screens/search_screen.dart';
import 'package:matrixflow_native/screens/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import '../foundation_regression_test.dart' as fixture;

class DelayedSchedulePlugin implements FlutterLocalNotificationsPlugin {
  final entered = Completer<void>();
  final release = Completer<void>();
  final Set<int> pending = {};
  @override
  dynamic noSuchMethod(Invocation call) {
    if (call.memberName == #zonedSchedule) {
      final id = call.positionalArguments.first as int;
      if (!entered.isCompleted) entered.complete();
      return release.future.then((_) {
        pending.add(id);
      });
    }
    if (call.memberName == #cancel) {
      pending.remove(call.positionalArguments.first);
    }
    if (call.memberName == #cancelAll) pending.clear();
    return Future<void>.value();
  }
}

class LaunchPlugin implements FlutterLocalNotificationsPlugin {
  @override
  dynamic noSuchMethod(Invocation call) {
    if (call.memberName == #initialize) return Future<bool>.value(true);
    if (call.memberName == #getNotificationAppLaunchDetails) {
      return Future<NotificationAppLaunchDetails>.value(
        NotificationAppLaunchDetails(
          true,
          notificationResponse: NotificationResponse(
            notificationResponseType:
                NotificationResponseType.selectedNotification,
            payload: ReminderPayload(boardId: 'b', taskId: 'Alpha').serialize(),
          ),
        ),
      );
    }
    return Future<void>.value();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    tz.initializeTimeZones();
    ReminderService.resetForTest(InMemoryReminderService());
  });
  tearDown(() {
    ReminderService.resetForTest();
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('S01 F06 cancel while native schedule is already in flight', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final plugin = DelayedSchedulePlugin();
    final service = FlutterLocalNotificationsReminderService(plugin: plugin)
      ..setInitializedForTest(true);
    final scheduling = service.scheduleReminder(
      boardId: 'b',
      taskId: 'Alpha',
      title: 'Synthetic',
      triggerAtMs: DateTime.now().millisecondsSinceEpoch + 3600000,
    );
    await tester.pump();
    expect(plugin.entered.isCompleted, isTrue);
    final cancellation = service.cancelReminder('Alpha');
    plugin.release.complete();
    await Future.wait([scheduling, cancellation]);
    debugDefaultTargetPlatformOverride = null;
    expect(
      plugin.pending,
      isEmpty,
      reason: 'A cancelled task must not remain in native pending schedules',
    );
  });

  testWidgets(
    'S02 F09 production bootstrap callback must deliver cold launch once to navigation',
    (tester) async {
      final service = FlutterLocalNotificationsReminderService(
        plugin: LaunchPlugin(),
      );
      ReminderService.resetForTest(service);
      // Production main initializes without a navigation callback; the first frame attaches it.
      await service.init();
      final delivered = <ReminderPayload>[];
      service.onNotificationSelected = delivered.add;
      expect(delivered.map((p) => p.taskId), ['Alpha']);
    },
  );

  testWidgets(
    'S03 F12 dirty search sidebar survives page back until discard is confirmed',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 950));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final store = await fixture.seeded([fixture.sample('Alpha')]);
      await tester.pumpWidget(
        fixture.app(
          store,
          Builder(
            builder:
                (context) => Scaffold(
                  body: TextButton(
                    onPressed:
                        () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => const SearchScreen(),
                          ),
                        ),
                    child: const Text('Open search'),
                  ),
                ),
          ),
        ),
      );
      await tester.tap(find.text('Open search'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Alpha').first);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('edit-title')),
        'unsaved draft',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('search-back-btn')));
      await tester.pumpAndSettle();
      final dialogs = find.byType(AlertDialog).evaluate().length;
      final drafts = find.byKey(const ValueKey('edit-title')).evaluate().length;
      await fixture.settle(tester, store);
      expect(dialogs, 1);
      expect(drafts, 1);
    },
  );

  testWidgets(
    'S04 F16 changing key while discovering must reject old model response',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      SharedPreferences.setMockInitialValues({
        'matrixflow-has-seen-onboarding': true,
      });
      final ai = fixture.DiscoveryAI();
      final store = Store(aiService: ai);
      await store.init();
      store.updateAIConfig(
        AIConfig(apiKey: 'synthetic-old', model: 'chosen-model'),
      );
      await tester.pumpWidget(fixture.app(store, const SettingsScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('refresh-models-btn')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('api-key-input')),
        'synthetic-new',
      );
      await tester.pump();
      ai.pending.complete(['obsolete-model']);
      await tester.pump();
      final selectedModel = store.aiConfig.model;
      await tester.pumpWidget(const SizedBox());
      store.dispose();
      expect(selectedModel, 'chosen-model');
    },
  );

  testWidgets(
    'S05 F12 shrinking dirty matrix sidebar must preserve usable layout',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 950));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final store = await fixture.seeded([fixture.sample('Alpha')]);
      await tester.pumpWidget(fixture.app(store, const MatrixHome()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Alpha').first);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('edit-title')),
        'unsaved draft',
      );
      await tester.pump();
      await tester.binding.setSurfaceSize(const Size(360, 800));
      await tester.pumpAndSettle();
      final layoutError = tester.takeException();
      final text =
          tester
              .widget<TextField>(find.byKey(const ValueKey('edit-title')))
              .controller!
              .text;
      await fixture.settle(tester, store);
      expect(layoutError, isNull);
      expect(text, 'unsaved draft');
    },
  );

  testWidgets(
    'S06 F06 cancelling all must invalidate an active restore traversal',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      final plugin = DelayedSchedulePlugin();
      final service = FlutterLocalNotificationsReminderService(plugin: plugin)
        ..setInitializedForTest(true);
      final when = DateTime.now().millisecondsSinceEpoch + 3600000;
      final tasks = [
        fixture.sample('Alpha')..reminderAt = when,
        fixture.sample('Beta')..reminderAt = when,
      ];
      final restore = service.rescheduleAllFuture(tasks);
      await tester.pump();
      expect(plugin.entered.isCompleted, isTrue);
      final cancel = service.cancelAll();
      plugin.release.complete();
      await Future.wait([restore, cancel]);
      debugDefaultTargetPlatformOverride = null;
      expect(
        plugin.pending,
        isEmpty,
        reason:
            'A startup/import traversal must not revive reminders after clear',
      );
    },
  );

  testWidgets('S07 F19 child completion target must also be at least 48 dp', (
    tester,
  ) async {
    final store = await fixture.seeded([
      fixture.sample('Alpha', subs: [SubTask(id: 's', title: 'Child')]),
    ]);
    await tester.pumpWidget(fixture.app(store, const MatrixHome()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('expand-Alpha')));
    await tester.pumpAndSettle();
    final size = tester.getSize(
      find.byKey(const ValueKey('task-subtask-check-s')),
    );
    await fixture.settle(tester, store);
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));
  });
}
