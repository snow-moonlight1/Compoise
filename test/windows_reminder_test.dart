import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/screens/matrix_screen.dart';
import 'package:matrixflow_native/screens/settings_screen.dart';
import 'package:matrixflow_native/services/desktop_shell_service.dart';
import 'package:matrixflow_native/storage.dart';
import 'package:provider/provider.dart';

import 'helpers.dart';

Widget buildTestApp(Store store, Widget child) {
  return ChangeNotifierProvider<Store>.value(
    value: store,
    child: MaterialApp(
      locale: const Locale('zh'),
      supportedLocales: const [Locale('en'), Locale('zh'), Locale('ja')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: child,
    ),
  );
}

void main() {
  setUp(() {
    DesktopShellService.instance.resetForTest();
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    DesktopShellService.instance.resetForTest();
    ReminderService.resetForTest();
  });

  group('WP25-N-Windows: FlutterLocalNotificationsReminderService on Windows', () {
    test('Windows platform permission checks and active timer scheduling', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        final service = FlutterLocalNotificationsReminderService();
        service.setInitializedForTest(true);

        // OS17: the plugin cannot query Windows notification settings, so the
        // service reports unknown rather than claiming the reminders work.
        expect(await service.checkPermission(), equals(ReminderPermissionStatus.unknown));
        expect(
          await service.requestPermission(),
          equals(ReminderPermissionStatus.unknown),
        );

        final now = DateTime.now().millisecondsSinceEpoch;
        final futureTime = now + 60000; // 1 minute in future

        // Scheduling future reminder registers an in-process Timer for Windows tray keep-alive
        await service.scheduleReminder(
          boardId: 'b1',
          taskId: 'task-win-1',
          title: 'Windows Reminder',
          body: 'Tray keep-alive alert',
          triggerAtMs: futureTime,
        );

        expect(service.activeTimerCount, equals(1));

        // Rescheduling replaces timer
        await service.scheduleReminder(
          boardId: 'b1',
          taskId: 'task-win-1',
          title: 'Windows Reminder Updated',
          triggerAtMs: futureTime + 10000,
        );
        expect(service.activeTimerCount, equals(1));

        // Scheduling second task increases timer count
        await service.scheduleReminder(
          boardId: 'b1',
          taskId: 'task-win-2',
          title: 'Second Reminder',
          triggerAtMs: futureTime + 20000,
        );
        expect(service.activeTimerCount, equals(2));

        // Canceling first reminder removes its timer
        await service.cancelReminder('task-win-1');
        expect(service.activeTimerCount, equals(1));

        // Canceling all clears all timers
        await service.cancelAll();
        expect(service.activeTimerCount, equals(0));
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  group('WP25-N-Windows: Notification tap & tray restore deep-linking in MatrixHome', () {
    testWidgets('notification click restores window from tray, switches board, and opens task detail', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      DesktopShellService.debugIsDesktopOverride = true;
      try {
        tester.view.physicalSize = const Size(1200, 800);
        tester.view.devicePixelRatio = 1.0;

        final board1 = Board(id: 'b1', name: 'Work', createdAt: 0);
        final board2 = Board(id: 'b2', name: 'Personal', createdAt: 0);
        final subtask = SubTask(id: 'sub-1', title: 'Prepare slides');
        final taskOnB2 = Task(
          id: 't-target',
          boardId: 'b2',
          title: 'Presentation',
          quadrant: qDo,
          createdAt: 0,
          subtasks: [subtask],
        );

        final (store, _) = await makeStore(
          boards: [board1, board2],
          tasks: [taskOnB2],
        );
        store.setActiveBoard('b1');

        final inMemoryReminder = InMemoryReminderService();
        ReminderService.instance = inMemoryReminder;

        await tester.pumpWidget(buildTestApp(store, const MatrixHome()));
        await tester.pumpAndSettle();

        // Simulate application minimized / hidden to tray
        await DesktopShellService.instance.hideWindowToTray();
        expect(DesktopShellService.instance.isWindowVisible, isFalse);

        // Simulate user clicking toast notification for subtask on Board 2
        const payload = ReminderPayload(
          boardId: 'b2',
          taskId: 't-target',
          subtaskId: 'sub-1',
        );

        // Trigger notification tap callback
        DesktopShellService.instance.restoreWindow();
        ReminderService.instance.onNotificationSelected?.call(payload);
        await tester.pumpAndSettle();

        // Window is restored to visible
        expect(DesktopShellService.instance.isWindowVisible, isTrue);

        // Active board is switched to b2
        expect(store.activeBoardId, equals('b2'));

        // Task detail panel is opened with target task
        expect(find.byKey(const ValueKey('edit-title')), findsOneWidget);
        expect(find.text('Presentation'), findsWidgets);

        // Subtask is expanded and visible
        expect(find.text('Prepare slides'), findsWidgets);

        await tester.pumpWidget(const SizedBox());
        store.dispose();
      } finally {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        debugDefaultTargetPlatformOverride = null;
        DesktopShellService.debugIsDesktopOverride = null;
      }
    });

    testWidgets('notification click for deleted task displays friendly notice without crash', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      DesktopShellService.debugIsDesktopOverride = true;
      try {
        tester.view.physicalSize = const Size(1200, 800);
        tester.view.devicePixelRatio = 1.0;

        final (store, _) = await makeStore(
          boards: [Board(id: 'b1', name: 'Work', createdAt: 0)],
          tasks: [],
        );

        final inMemoryReminder = InMemoryReminderService();
        ReminderService.instance = inMemoryReminder;

        await tester.pumpWidget(buildTestApp(store, const MatrixHome()));
        await tester.pumpAndSettle();

        // Simulate notification tap for non-existent task
        const payload = ReminderPayload(
          boardId: 'b1',
          taskId: 'non-existent-task',
        );

        DesktopShellService.instance.restoreWindow();
        ReminderService.instance.onNotificationSelected?.call(payload);
        await tester.pumpAndSettle();

        // Notice message displayed
        expect(find.text(store.t['taskNotFound']!), findsOneWidget);

        await tester.pumpWidget(const SizedBox());
        store.dispose();
      } finally {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        debugDefaultTargetPlatformOverride = null;
        DesktopShellService.debugIsDesktopOverride = null;
      }
    });
  });

  group('WP25-N-Windows: SettingsScreen Windows Notification Guide and Test Button', () {
    testWidgets('displays Windows guide tile, dialog with 3 sections, test button, and permission check', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      DesktopShellService.debugIsDesktopOverride = true;
      try {
        tester.view.physicalSize = const Size(800, 1200);
        tester.view.devicePixelRatio = 1.0;

        final (store, _) = await makeStore();
        // OS17: Windows cannot report a notification state, so the fake platform
        // answers unknown and the settings dialog must say so.
        final inMemoryReminder = InMemoryReminderService(
          permission: ReminderPermissionStatus.unknown,
        );
        ReminderService.instance = inMemoryReminder;

        await tester.pumpWidget(buildTestApp(store, const SettingsScreen()));
        await tester.pumpAndSettle();

        // Scroll to Windows Reminder Guide Tile
        final guideTile = find.byKey(const ValueKey('windows-reminder-guide-tile'));
        await tester.scrollUntilVisible(
          guideTile,
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();

        expect(guideTile, findsOneWidget);

        // Tap guide tile to open dialog
        await tester.tap(guideTile);
        await tester.pumpAndSettle();

        // Verify all 3 Windows guide sections are presented
        expect(find.text(store.t['windowsReminderGuideTitle']!), findsOneWidget);
        expect(find.text(store.t['windowsGuideTrayTitle']!), findsOneWidget);
        expect(find.text(store.t['windowsGuideFocusTitle']!), findsOneWidget);
        expect(find.text(store.t['windowsGuideActionCenterTitle']!), findsOneWidget);

        // Close dialog
        await tester.tap(find.text(store.t['confirm']!));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);

        // Check Permissions Button
        final permBtn = find.byKey(const ValueKey('check-permissions-btn'));
        expect(permBtn, findsOneWidget);
        await tester.tap(permBtn);
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.text(store.t['permissionUnknown']!), findsOneWidget);

        await tester.tap(find.text(store.t['confirm']!));
        await tester.pumpAndSettle();

        // Verify Test Notification Button is present
        final testBtn = find.byKey(const ValueKey('test-windows-notif-btn'));
        expect(testBtn, findsOneWidget);

        // Tap test notification button
        await tester.tap(testBtn);
        await tester.pumpAndSettle();

        // Test notification scheduled in service
        expect(inMemoryReminder.scheduled.length, equals(1));
        // OS17 appends the real permission state to the honest result text.
        expect(
          find.textContaining(store.t['testNotificationSent']!),
          findsOneWidget,
        );

        await tester.pumpWidget(const SizedBox());
        store.dispose();
      } finally {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        debugDefaultTargetPlatformOverride = null;
        DesktopShellService.debugIsDesktopOverride = null;
      }
    });
  });
}
