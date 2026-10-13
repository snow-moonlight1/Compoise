import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:compoise/l10n.dart';
import 'package:compoise/models.dart';
import 'package:compoise/planner/planner_guide.dart';
import 'package:compoise/screens/onboarding_screen.dart';
import 'package:compoise/screens/settings_screen.dart';
import 'package:compoise/services/desktop_shell_service.dart';
import 'package:compoise/storage.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'foundation_regression_test.dart' as fixture;
import 'helpers.dart';
import 'planner_test_support.dart';

class _Counting extends InMemoryReminderService {
  _Counting() : super(permission: ReminderPermissionStatus.unknown);
  int calls = 0;

  @override
  Future<ReminderScheduleResult> scheduleReminder({
    required String boardId,
    required String taskId,
    String? subtaskId,
    required String title,
    String? body,
    required int triggerAtMs,
    bool sound = true,
    bool vibrate = true,
    bool recordRetry = true,
    bool userInitiated = false,
  }) {
    calls++;
    return super.scheduleReminder(
      boardId: boardId,
      taskId: taskId,
      subtaskId: subtaskId,
      title: title,
      body: body,
      triggerAtMs: triggerAtMs,
      sound: sound,
      vibrate: vibrate,
      recordRetry: recordRetry,
      userInitiated: userInitiated,
    );
  }
}

const _desk = Size(1200, 900);

void main() {
  testWidgets('guide content is centred, no block of empty space', (
    tester,
  ) async {
    for (final size in [const Size(400, 800), const Size(1400, 900)]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showPlannerGuide(
                context,
                dictOf(Language.en),
                markSeen: false,
              ),
              child: const Text('go'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      final page = tester.getRect(
        find.byKey(const ValueKey('schedule-guide-page-0')),
      );
      final icon = tester.getRect(
        find.descendant(
          of: find.byKey(const ValueKey('schedule-guide-page-0')),
          matching: find.byType(Icon),
        ),
      );
      final texts = find.descendant(
        of: find.byKey(const ValueKey('schedule-guide-page-0')),
        matching: find.byType(Text),
      );
      final bottom = tester.getRect(texts.last).bottom;
      // Equal room above and below the content.
      expect((icon.top - page.top) - (page.bottom - bottom), closeTo(0, 10));
      expect(icon.top - page.top, lessThan(80));
      final dialog = tester.getRect(
        find
            .descendant(
              of: find.byKey(const ValueKey('schedule-guide')),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(dialog.width, lessThanOrEqualTo(440 + 1));
      expect(dialog.center.dx, closeTo(size.width / 2, 1));
      expect(dialog.center.dy, closeTo(size.height / 2, 1));
      await tester.pumpWidget(const SizedBox.shrink());
    }
    await tester.binding.setSurfaceSize(null);
  });

  group('Windows settings', () {
    Future<Store> pump(WidgetTester tester, ReminderService service) async {
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      ReminderService.instance = service;
      final (store, _) = await makeStore(
        boards: [Board(id: 'b1', name: 'Board', createdAt: 1)],
      );
      await tester.pumpWidget(fixture.app(store, const SettingsScreen()));
      await tester.pumpAndSettle();
      return store;
    }

    testWidgets('one click, one test toast; no permission check button', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      DesktopShellService.debugIsDesktopOverride = true;
      try {
        final service = _Counting();
        final store = await pump(tester, service);
        final button = find.byKey(const ValueKey('test-windows-notif-btn'));
        await tester.scrollUntilVisible(
          button,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(
          find.byKey(const ValueKey('check-permissions-btn')),
          findsNothing,
        );
        // The test button has the row to itself.
        final row = tester.getRect(
          find.ancestor(of: button, matching: find.byType(Row)).first,
        );
        expect(tester.getRect(button).width, closeTo(row.width, 1));
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(service.calls, 1);
        await tester.pumpWidget(const SizedBox());
        store.dispose();
      } finally {
        debugDefaultTargetPlatformOverride = null;
        DesktopShellService.debugIsDesktopOverride = null;
      }
    });

    testWidgets('a phone keeps the permission check', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        final store = await pump(tester, InMemoryReminderService());
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('check-permissions-btn')),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(
          find.byKey(const ValueKey('check-permissions-btn')),
          findsOneWidget,
        );
        await tester.pumpWidget(const SizedBox());
        store.dispose();
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  test('a Windows toast carries the body once (no repeated subtitle)', () {
    final details = FlutterLocalNotificationsReminderService().debugDetails(
      body: 'Compoise test notification',
    );
    expect(details.windows?.subtitle, isNull);
  });

  testWidgets('wide window: the tutorial stays a readable column', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'compoise-has-seen-onboarding': true,
    });
    final store = Store();
    await store.init();
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: store,
        child: MaterialApp(
          theme: ThemeData(platform: TargetPlatform.windows),
          home: const OnboardingScreen(isReviewMode: true),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final box = tester.getRect(find.byKey(const ValueKey('onboarding-width')));
    expect(box.width, lessThanOrEqualTo(680));
    expect(box.center.dx, closeTo(800, 1));
    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
  });

  testWidgets('wide desktop: pool is a side panel; phone keeps the sheet', (
    tester,
  ) async {
    final store = await c2Store();
    await c2Pump(tester, store, size: _desk, platform: TargetPlatform.windows);
    expect(c2Key('schedule-pool-docked'), findsOneWidget);
    expect(find.byType(DraggableScrollableSheet), findsNothing);
    expect(c2Key('schedule-today-button'), findsOneWidget);
    expect(c2Key('schedule-previous'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await c2Pump(tester, store, size: const Size(400, 800));
    expect(c2Key('schedule-pool-docked'), findsNothing);
    expect(find.byType(DraggableScrollableSheet), findsOneWidget);
    expect(c2Key('schedule-today-button'), findsNothing);
    await c2Finish(tester, store);
  });

  testWidgets('desktop keys: arrows, T, D/W, Ctrl+N, Esc, Delete', (
    tester,
  ) async {
    final store = await c2Store(items: [c1Items().first]);
    await c2Pump(tester, store, size: _desk, platform: TargetPlatform.windows);
    expect(c2Key('schedule-day-2026-09-30'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(c2Key('schedule-day-2026-10-01'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(c2Key('schedule-day-2026-09-30'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
    await tester.pumpAndSettle();
    expect(find.text('Sep 28–Oct 4'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.pumpAndSettle();
    expect(c2Key('schedule-day-2026-09-30'), findsOneWidget);
    // Select, Esc clears it.
    await c2Tap(tester, c2Key('schedule-item-2026-09-30-block'));
    expect(c2Key('schedule-detail'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(c2Key('schedule-detail'), findsNothing);
    // Delete asks first.
    await c2Tap(tester, c2Key('schedule-item-2026-09-30-block'));
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    // Ctrl+N opens a new item.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(c2Key('schedule-editor'), findsOneWidget);
    await c2Tap(tester, c2Key('schedule-editor-cancel'));
    await c2Finish(tester, store);
  });

  testWidgets(
    'desktop mouse: double click empty grid creates, right click a block',
    (tester) async {
      final store = await c2Store(items: [c1Items().first]);
      await c2Pump(
        tester,
        store,
        size: _desk,
        platform: TargetPlatform.windows,
      );
      final block = c2Key('schedule-item-2026-09-30-block');
      await tester.ensureVisible(block);
      await tester.pumpAndSettle();
      final rect = tester.getRect(block);
      // Right click: edit / delete menu.
      final mouse = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await mouse.down(rect.center);
      await mouse.up();
      await tester.pumpAndSettle();
      expect(c2Key('schedule-menu-edit'), findsOneWidget);
      expect(c2Key('schedule-menu-delete'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      // Double click well below the block: a new item at that time.
      final empty = Offset(rect.center.dx, rect.bottom + 120);
      final click = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await click.down(empty);
      await click.up();
      await tester.pump(const Duration(milliseconds: 80));
      await click.down(empty);
      await click.up();
      await tester.pumpAndSettle();
      expect(c2Key('schedule-editor'), findsOneWidget);
      await c2Tap(tester, c2Key('schedule-editor-cancel'));
      // A single click never creates.
      await click.down(empty + const Offset(0, 60));
      await click.up();
      await tester.pumpAndSettle();
      expect(c2Key('schedule-editor'), findsNothing);
      await c2Finish(tester, store);
    },
  );

  testWidgets('task detail opens as a centred dialog on desktop', (
    tester,
  ) async {
    final store = await c2Store();
    await c2Pump(
      tester,
      store,
      size: _desk,
      platform: TargetPlatform.windows,
      provide: true,
    );
    await tester.tap(c2Key('schedule-pool-tab-2'));
    await tester.pumpAndSettle();
    await tester.tap(c2Key('schedule-pool-outline'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('task-detail-dialog')), findsOneWidget);
    expect(
      tester
          .getRect(
            find
                .descendant(
                  of: find.byKey(const ValueKey('task-detail-dialog')),
                  matching: find.byType(Material),
                )
                .first,
          )
          .width,
      lessThanOrEqualTo(560),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await c2Finish(tester, store);
  });
}
