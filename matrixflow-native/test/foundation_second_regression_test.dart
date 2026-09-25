import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/ai_service.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/screens/completed_screen.dart';
import 'package:matrixflow_native/screens/search_screen.dart';
import 'package:matrixflow_native/screens/matrix_screen.dart';
import 'package:matrixflow_native/screens/settings_screen.dart';
import 'package:matrixflow_native/storage.dart';
import 'package:matrixflow_native/widgets/task_detail_panel.dart';
import 'foundation_regression_test.dart' as fixture;
import 'review/foundation_second_review_probe.dart' as review;

class SnapshotDiscovery extends fixture.DiscoveryAI {
  AIConfig? received;
  @override
  Future<List<String>> fetchModels({
    required AIConfig config,
    bool forceRefresh = false,
    AICancellation? cancellation,
  }) {
    received = config;
    return pending.future;
  }
}

class RecoveringPlugin extends fixture.RecordingPlugin {
  bool failing = true;
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (failing && invocation.memberName == #zonedSchedule) {
      return Future<void>.error(StateError('Synthetic failure'));
    }
    return super.noSuchMethod(invocation);
  }
}

class PayloadPlugin extends review.LaunchPlugin {
  PayloadPlugin(this.payload);
  final ReminderPayload payload;
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #getNotificationAppLaunchDetails) {
      return Future.value(
        NotificationAppLaunchDetails(
          true,
          notificationResponse: NotificationResponse(
            notificationResponseType:
                NotificationResponseType.selectedNotification,
            payload: payload.serialize(),
          ),
        ),
      );
    }
    return super.noSuchMethod(invocation);
  }
}

void main() {
  review.main();

  for (final phase in ['before', 'after']) {
    testWidgets('SR01 cancel $phase native scheduling leaves nothing pending', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      final plugin = review.DelayedSchedulePlugin();
      plugin.release.complete();
      final service = FlutterLocalNotificationsReminderService(plugin: plugin)
        ..setInitializedForTest(true);
      final schedule = service.scheduleReminder(
        boardId: 'b',
        taskId: 'Alpha',
        title: 'Synthetic',
        triggerAtMs: DateTime.now().millisecondsSinceEpoch + 3600000,
      );
      if (phase == 'after') await schedule;
      final cancel = service.cancelReminder('Alpha');
      await Future.wait([schedule, cancel]);
      expect(plugin.pending, isEmpty);
      if (phase == 'before') expect(plugin.entered.isCompleted, isFalse);
      debugDefaultTargetPlatformOverride = null;
    });
  }

  for (final operation in ['clear', 'overwrite']) {
    testWidgets('SR01 Store $operation invalidates active production restore', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      final store = await fixture.seeded([]);
      final when = DateTime.now().millisecondsSinceEpoch + 3600000;
      final old = [
        fixture.sample('Alpha')..reminderAt = when,
        fixture.sample('Beta')..reminderAt = when,
      ];
      store.debugReplaceTasks(old);
      final plugin = review.DelayedSchedulePlugin();
      final service = FlutterLocalNotificationsReminderService(plugin: plugin)
        ..setInitializedForTest(true);
      ReminderService.resetForTest(service);
      final restore = service.rescheduleAllFuture(old);
      await tester.pump();
      expect(plugin.entered.isCompleted, isTrue);
      if (operation == 'clear') {
        store.clearBoard('b');
      } else {
        store.importData({
          'version': 2,
          'boards': [Board(id: 'b', name: 'Synthetic', createdAt: 1).toJson()],
          'tasks': [(fixture.sample('Gamma')..reminderAt = when).toJson()],
        }, 'overwrite');
      }
      plugin.release.complete();
      await restore;
      await tester.pumpAndSettle();
      expect(
        plugin.pending,
        operation == 'clear' ? isEmpty : {generateNotificationId('Gamma')},
      );
      await service.cancelAll();
      store.dispose();
      debugDefaultTargetPlatformOverride = null;
    });
  }

  testWidgets('SR01 concurrent additive restore retains both batches', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final when = DateTime.now().millisecondsSinceEpoch + 3600000;
    final plugin = review.DelayedSchedulePlugin();
    final service = FlutterLocalNotificationsReminderService(plugin: plugin)
      ..setInitializedForTest(true);
    final first = service.rescheduleAllFuture([
      fixture.sample('Alpha')..reminderAt = when,
      fixture.sample('Beta')..reminderAt = when,
    ]);
    await tester.pump();
    final second = service.rescheduleAllFuture([
      fixture.sample('Gamma')..reminderAt = when,
    ]);
    plugin.release.complete();
    await Future.wait([first, second]);
    expect(
      plugin.pending,
      {'Alpha', 'Beta', 'Gamma'}.map(generateNotificationId).toSet(),
    );
    await service.cancelAll();
    debugDefaultTargetPlatformOverride = null;
  });

  for (final field in ['url', 'protocol', 'model']) {
    testWidgets(
      'SR04 $field edits invalidate discovery and preserve its snapshot',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1000, 2200));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final ai = SnapshotDiscovery();
        final store = Store(aiService: ai);
        await store.init();
        store.updateAIConfig(
          AIConfig(
            provider: 'custom',
            apiKey: 'synthetic',
            model: 'chosen-model',
          ),
        );
        await tester.pumpWidget(fixture.app(store, const SettingsScreen()));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('refresh-models-btn')));
        await tester.pump();
        final original = ai.received!.toJson();
        if (field == 'protocol') {
          tester
              .widget<DropdownButton<AIProtocol>>(
                find.byKey(const ValueKey('protocol-selector')),
              )
              .onChanged!(AIProtocol.anthropic);
        } else {
          await tester.enterText(
            find.byKey(
              ValueKey(field == 'url' ? 'base-url-input' : 'model-input'),
            ),
            field == 'url' ? 'https://synthetic.invalid/v1' : 'manual-model',
          );
        }
        await tester.pump();
        expect(ai.received!.toJson(), original);
        ai.pending.complete(['obsolete-model']);
        await tester.pumpAndSettle();
        expect(
          store.aiConfig.model,
          field == 'model' ? 'manual-model' : 'chosen-model',
        );
        expect(
          find.byKey(const ValueKey('refresh-models-btn')),
          findsOneWidget,
        );
        await fixture.settle(tester, store);
      },
    );
  }

  for (final completed in [false, true]) {
    for (final systemBack in [false, true]) {
      testWidgets(
        'SR03 ${completed ? 'completed' : 'search'} ${systemBack ? 'system' : 'button'} back guards draft',
        (tester) async {
          await tester.binding.setSurfaceSize(const Size(1400, 950));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final task = fixture.sample('Alpha')..completed = completed;
          final store = await fixture.seeded([task]);
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
                                builder:
                                    (_) =>
                                        completed
                                            ? const CompletedScreen()
                                            : const SearchScreen(),
                              ),
                            ),
                        child: const Text('Open'),
                      ),
                    ),
              ),
            ),
          );
          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Alpha').first);
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byKey(const ValueKey('edit-title')),
            'draft',
          );
          await tester.pump();
          if (systemBack) {
            await tester.binding.handlePopRoute();
          } else {
            await tester.tap(
              find.byKey(
                ValueKey(completed ? 'completed-back-btn' : 'search-back-btn'),
              ),
            );
          }
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsOneWidget);
          expect(find.byKey(const ValueKey('edit-title')), findsOneWidget);
          await fixture.settle(tester, store);
        },
      );
    }
    testWidgets(
      'SR05 ${completed ? 'completed' : 'search'} resizes preserve draft both ways',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1400, 950));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final store = await fixture.seeded([
          fixture.sample('Alpha')..completed = completed,
        ]);
        await tester.pumpWidget(
          fixture.app(
            store,
            completed ? const CompletedScreen() : const SearchScreen(),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Alpha').first);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('edit-title')),
          'draft',
        );
        for (final size in [const Size(360, 800), const Size(1400, 950)]) {
          await tester.binding.setSurfaceSize(size);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(
            tester
                .widget<TextField>(find.byKey(const ValueKey('edit-title')))
                .controller!
                .text,
            'draft',
          );
        }
        await tester.tap(find.byKey(const ValueKey('save-task')));
        await tester.pumpAndSettle();
        expect(store.tasks.single.title, 'draft');
        await fixture.settle(tester, store);
      },
    );
  }

  for (final sub in [null, 'child']) {
    testWidgets(
      'SR02 cold launch locates parent and child $sub after first frame exactly once',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1400, 950));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final store = await fixture.seeded([
          fixture.sample('Alpha', subs: [SubTask(id: 'child', title: 'Child')]),
        ]);
        final service = FlutterLocalNotificationsReminderService(
          plugin: PayloadPlugin(
            ReminderPayload(boardId: 'b', taskId: 'Alpha', subtaskId: sub),
          ),
        );
        ReminderService.resetForTest(service);
        await service.init();
        await tester.pumpWidget(fixture.app(store, const MatrixHome()));
        await tester.pumpAndSettle();
        final panel = tester.widget<TaskDetailPanel>(
          find.byType(TaskDetailPanel),
        );
        expect(panel.task.id, 'Alpha');
        expect(panel.highlightSubtaskId, sub);
        final repeated = <ReminderPayload>[];
        service.onNotificationSelected = repeated.add;
        expect(repeated, isEmpty);
        await fixture.settle(tester, store);
      },
    );
  }

  testWidgets('SR06 child checkbox edge completes without opening detail', (
    tester,
  ) async {
    final store = await fixture.seeded([
      fixture.sample('Alpha', subs: [SubTask(id: 'child', title: 'Child')]),
    ]);
    await tester.pumpWidget(fixture.app(store, const MatrixHome()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('expand-Alpha')));
    await tester.pumpAndSettle();
    final rect = tester.getRect(
      find.byKey(const ValueKey('task-subtask-check-child')),
    );
    await tester.tapAt(rect.topLeft + const Offset(2, 2));
    await tester.pumpAndSettle();
    expect(store.tasks.single.subtasks.single.completed, isTrue);
    expect(find.byType(TaskDetailPanel), findsNothing);
    await fixture.settle(tester, store);
  });

  testWidgets(
    'SR07 saving a reminder exposes production failure and successful retry clears it',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final plugin = RecoveringPlugin();
      final service = FlutterLocalNotificationsReminderService(plugin: plugin)
        ..setInitializedForTest(true);
      ReminderService.resetForTest(service);
      final store = await fixture.seeded([fixture.sample('Alpha')]);
      await tester.pumpWidget(fixture.app(store, const MatrixHome()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Alpha').first);
      await tester.pumpAndSettle();
      final quick = find.byKey(const ValueKey('reminder-quick-tomorrow-9'));
      await tester.ensureVisible(quick);
      await tester.tap(quick);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('save-task')));
      await tester.pumpAndSettle();
      expect(store.tasks.single.reminderAt, isNotNull);
      expect(
        find.byKey(const ValueKey('reminder-schedule-failure')),
        findsOneWidget,
      );
      expect(service.scheduleFailures.value.values.single.taskId, 'Alpha');
      expect(plugin.calls.where((c) => c == #show), isEmpty);
      plugin.failing = false;
      await tester.tap(find.byKey(const ValueKey('retry-reminders')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('reminder-schedule-failure')),
        findsNothing,
      );
      expect(service.scheduleFailures.value, isEmpty);
      expect(plugin.calls.where((c) => c == #zonedSchedule), isNotEmpty);
      await fixture.settle(tester, store);
      debugDefaultTargetPlatformOverride = null;
    },
  );
}
