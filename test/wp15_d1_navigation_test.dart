import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/platform/device_time_zone.dart';
import 'package:matrixflow_native/platform/device_time_zone_controller.dart';
import 'package:matrixflow_native/screens/matrix_screen.dart';
import 'package:matrixflow_native/screens/planner_screen.dart';
import 'package:matrixflow_native/storage.dart';
import 'package:matrixflow_native/widgets/task_detail_panel.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'wp15_c2_test_support.dart';

Widget app(Store store, Widget child, {double scale = 1}) =>
    ChangeNotifierProvider.value(
      value: store,
      child: MaterialApp(
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('en'), Locale('zh'), Locale('ja')],
        builder: (context, inner) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: inner!,
        ),
        home: child,
      ),
    );

Task alpha() => Task(
  id: 'Alpha',
  boardId: 'b',
  title: 'Alpha',
  quadrant: 1,
  createdAt: 1,
  urgencyMode: UrgencyMode.manual,
  subtasks: [SubTask(id: 's', title: 'Child')],
  plannedDate: DateTime.utc(2026, 9, 29).millisecondsSinceEpoch,
  deadline: DateTime.utc(2026, 9, 30, 23, 59, 59).millisecondsSinceEpoch,
);

/// The page owns a periodic save timer, so every test drops the widget tree and
/// disposes the store inside the body; the teardown only covers early failures.
void disposeStore(Store store) {
  try {
    store.dispose();
  } on FlutterError catch (error) {
    if (!error.toString().contains('disposed')) rethrow;
  }
}

Future<Store> seeded(
  List<Task> tasks, {
  Future<bool> Function(String key, String value)? writer,
}) async {
  SharedPreferences.setMockInitialValues({
    'matrixflow-has-seen-onboarding': true,
    'matrixflow-boards': jsonEncode([
      Board(id: 'b', name: 'Synthetic board', createdAt: 1).toJson(),
    ]),
    'matrixflow-tasks': jsonEncode(tasks.map((task) => task.toJson()).toList()),
  });
  final store = Store(saveWriter: writer);
  await store.init();
  addTearDown(() => disposeStore(store));
  return store;
}

Future<void> finish(WidgetTester tester, Store store) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.runAsync(() => store.flush(waitForReminders: false));
  store.dispose();
  await tester.pump();
}

/// Answers the platform channel the way Android or the Windows runner would.
void mockDeviceTimeZone({String platform = 'android', String? identity}) {
  const channel = MethodChannel(deviceTimeZoneChannelName);
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        channel,
        (call) async => call.method == 'systemZone'
            ? {'platform': platform, 'identity': identity}
            : null,
      );
  addTearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );
}

Future<void> openHomeMore(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('more-btn')));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => ReminderService.resetForTest(InMemoryReminderService()));
  tearDown(() => ReminderService.resetForTest());

  testWidgets('the home more menu offers the schedule beside screenshot import', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 950));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = await seeded([alpha()]);
    await tester.pumpWidget(app(store, const MatrixHome()));
    await tester.pumpAndSettle();
    await openHomeMore(tester);
    expect(find.byKey(const ValueKey('more-schedule')), findsOneWidget);
    expect(find.byKey(const ValueKey('more-screenshot-import')), findsOneWidget);
    expect(find.text(store.t['scheduleOpen']!), findsOneWidget);
    await finish(tester, store);
  });

  testWidgets(
    'the home entry asks for a zone when the platform cannot answer',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 950));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final store = await seeded([alpha()]);
      await tester.pumpWidget(app(store, const MatrixHome()));
      await tester.pumpAndSettle();
      await openHomeMore(tester);
      await tester.tap(find.byKey(const ValueKey('more-schedule')));
      await tester.pumpAndSettle();

      expect(find.byType(PlannerScreen), findsOneWidget);
      expect(
        find.byKey(const ValueKey('schedule-zone-required')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('schedule-scroll')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('schedule-zone-choose')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('schedule-zone-search')),
        'Asia/Shanghai',
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('schedule-zone-option-Asia/Shanghai')),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('schedule-scroll')), findsOneWidget);
      expect(find.textContaining('Asia/Shanghai'), findsWidgets);
      await finish(tester, store);
    },
  );

  testWidgets('the home entry uses the zone the platform reports', (
    tester,
  ) async {
    mockDeviceTimeZone(identity: 'Asia/Shanghai');
    await tester.binding.setSurfaceSize(const Size(1400, 950));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = await seeded([alpha()]);
    await tester.pumpWidget(app(store, const MatrixHome()));
    await tester.pumpAndSettle();
    await openHomeMore(tester);
    await tester.tap(find.byKey(const ValueKey('more-schedule')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('schedule-scroll')), findsOneWidget);
    expect(
      find.text('${store.t['scheduleZoneDevice']}: Asia/Shanghai'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('schedule-zone-required')), findsNothing);
    await finish(tester, store);
  });

  testWidgets('a parent task detail schedules a new block for that task', (
    tester,
  ) async {
    mockDeviceTimeZone(identity: 'Asia/Shanghai');
    await tester.binding.setSurfaceSize(const Size(1400, 950));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = await seeded([alpha()]);
    await tester.pumpWidget(app(store, const MatrixHome()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alpha').first);
    await tester.pumpAndSettle();
    expect(find.byType(TaskDetailPanel), findsOneWidget);
    expect(find.byKey(const ValueKey('edit-schedule-entry')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('edit-schedule-entry')));
    await tester.pumpAndSettle();

    expect(find.byType(PlannerScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('schedule-editor')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('schedule-editor-choose-association')),
        matching: find.textContaining('Alpha'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Task dates (reference only)'), findsOneWidget);
    await c2Tap(tester, c2Key('schedule-editor-cancel'));
    await finish(tester, store);
  });

  testWidgets('a pending detail draft is saved before the schedule opens', (
    tester,
  ) async {
    mockDeviceTimeZone(identity: 'Asia/Shanghai');
    await tester.binding.setSurfaceSize(const Size(1400, 950));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = await seeded([alpha()]);
    await tester.pumpWidget(app(store, const MatrixHome()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alpha').first);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('edit-title')),
      'Alpha renamed',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('edit-schedule-entry')));
    await tester.pumpAndSettle();

    expect(store.tasks.single.title, 'Alpha renamed');
    expect(find.byType(PlannerScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('schedule-editor')), findsOneWidget);
    await c2Tap(tester, c2Key('schedule-editor-cancel'));
    await finish(tester, store);
  });

  testWidgets('a failed save keeps the draft and never opens the schedule', (
    tester,
  ) async {
    var failWrites = false;
    final store = await seeded(
      [alpha()],
      writer: (key, value) async {
        if (failWrites) return false;
        return (await SharedPreferences.getInstance()).setString(key, value);
      },
    );
    addTearDown(() => disposeStore(store));
    await tester.binding.setSurfaceSize(const Size(1400, 950));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(app(store, const MatrixHome()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alpha').first);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('edit-title')),
      'Alpha renamed',
    );
    await tester.pumpAndSettle();

    failWrites = true;
    await tester.tap(find.byKey(const ValueKey('edit-schedule-entry')));
    await tester.pumpAndSettle();

    expect(find.byType(PlannerScreen), findsNothing);
    expect(find.byType(TaskDetailPanel), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(TaskDetailPanel),
        matching: find.text(
          store.persistenceError ?? store.t['storageWriteError']!,
        ),
      ),
      findsOneWidget,
    );
    expect(store.tasks.single.title, 'Alpha renamed');
    await finish(tester, store);
  });

  testWidgets('a deleted parent task reports the missing target', (
    tester,
  ) async {
    final store = await c2Store();
    addTearDown(() => disposeStore(store));
    final controller = DeviceTimeZoneController(
      source: _FixedSource('Asia/Shanghai'),
      changeEvents: const Stream<void>.empty(),
      observeLifecycle: false,
      listenPlatformChanges: false,
    );
    addTearDown(controller.dispose);
    await controller.refresh();
    await tester.pumpWidget(
      app(
        store,
        PlannerScreen(
          store: store,
          timeZoneController: controller,
          initialTaskId: 'ghost',
          startTimeBlock: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(store.t['scheduleTaskMissing']!), findsOneWidget);
    expect(find.byKey(const ValueKey('schedule-editor')), findsNothing);
    await finish(tester, store);
  });

  testWidgets('a library that needs recovery states it instead of a grid', (
    tester,
  ) async {
    final store = await c2Store(recovery: true);
    addTearDown(() => disposeStore(store));
    await tester.pumpWidget(
      app(
        store,
        PlannerScreen(
          store: store,
          displayTimeZoneId: 'Asia/Shanghai',
          initialTaskId: 'outline',
          startTimeBlock: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(store.t['scheduleRecovery']!), findsOneWidget);
    expect(find.byKey(const ValueKey('schedule-scroll')), findsNothing);
    expect(find.byKey(const ValueKey('schedule-editor')), findsNothing);
    await finish(tester, store);
  });

  testWidgets('child rows offer no schedule entry', (tester) async {
    mockDeviceTimeZone(identity: 'Asia/Shanghai');
    await tester.binding.setSurfaceSize(const Size(1400, 950));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = await seeded([alpha()]);
    await tester.pumpWidget(app(store, const MatrixHome()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alpha').first);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('edit-schedule-entry')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('subtask-item-s')),
        matching: find.byKey(const ValueKey('edit-schedule-entry')),
      ),
      findsNothing,
    );
    await finish(tester, store);
  });

  testWidgets('a narrow sheet with large text can still schedule', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = await seeded([alpha()]);
    final task = store.tasks.single;
    await tester.pumpWidget(
      app(
        store,
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showTaskDetailSheet(context, task),
              child: const Text('open detail'),
            ),
          ),
        ),
        scale: 3,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open detail'));
    await tester.pumpAndSettle();
    expect(find.byType(TaskDetailPanel), findsOneWidget);

    await c2Tap(tester, c2Key('edit-schedule-entry'));
    expect(find.byType(TaskDetailPanel), findsNothing);
    expect(find.byType(PlannerScreen), findsOneWidget);
    await finish(tester, store);
  });
}

class _FixedSource implements DeviceTimeZoneSource {
  _FixedSource(this.identity);

  final String identity;

  @override
  Future<DeviceTimeZoneReading> read() async => DeviceTimeZoneReading(
    platform: DeviceTimeZonePlatform.android,
    identity: identity,
  );
}
