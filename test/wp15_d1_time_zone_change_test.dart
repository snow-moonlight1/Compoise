import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/planner/schedule_edit_session.dart';
import 'package:matrixflow_native/platform/device_time_zone.dart';
import 'package:matrixflow_native/platform/device_time_zone_controller.dart';
import 'package:matrixflow_native/schedule_item.dart';
import 'package:matrixflow_native/schedule_time.dart';
import 'package:matrixflow_native/screens/planner_screen.dart';
import 'package:matrixflow_native/storage.dart';

import 'wp15_c2_test_support.dart';

class FakeZoneSource implements DeviceTimeZoneSource {
  FakeZoneSource(this.reading);

  DeviceTimeZoneReading reading;
  int reads = 0;
  Completer<void>? firstReadGate;

  @override
  Future<DeviceTimeZoneReading> read() async {
    reads++;
    final captured = reading;
    if (reads == 1) await firstReadGate?.future;
    return captured;
  }
}

const _shanghai = DeviceTimeZoneReading(
  platform: DeviceTimeZonePlatform.android,
  identity: 'Asia/Shanghai',
);
const _tokyo = DeviceTimeZoneReading(
  platform: DeviceTimeZonePlatform.android,
  identity: 'Asia/Tokyo',
);
const _newYork = DeviceTimeZoneReading(
  platform: DeviceTimeZonePlatform.android,
  identity: 'America/New_York',
);
const _unreadable = DeviceTimeZoneReading.unreadable(
  DeviceTimeZonePlatform.android,
);

DeviceTimeZoneController controllerFor(
  FakeZoneSource source, {
  Stream<void>? changes,
}) => DeviceTimeZoneController(
  source: source,
  changeEvents: changes ?? const Stream<void>.empty(),
  observeLifecycle: true,
);

Future<void> pumpPlanner(
  WidgetTester tester,
  Store store,
  DeviceTimeZoneController controller,
) async {
  await tester.binding.setSurfaceSize(const Size(1200, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(useMaterial3: true, platform: TargetPlatform.windows),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('en'), Locale('zh'), Locale('ja')],
      home: PlannerScreen(
        store: store,
        timeZoneController: controller,
        initialDate: ScheduleCivilDate(2026, 9, 30),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openZoneMenu(WidgetTester tester) async {
  if (find.byType(PopupMenuItem<String>).evaluate().isNotEmpty) {
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
  }
  await tester.tap(find.byKey(const ValueKey('schedule-menu')));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'a change during a pending read is refreshed before callers complete',
    () async {
      final source = FakeZoneSource(_shanghai)
        ..firstReadGate = Completer<void>();
      final controller = controllerFor(source);
      addTearDown(controller.dispose);
      final first = controller.refresh();
      source.reading = _tokyo;
      final second = controller.refresh();
      source.firstReadGate!.complete();
      await Future.wait([first, second]);
      expect(source.reads, 2);
      expect(controller.displayIanaId, 'Asia/Tokyo');
    },
  );

  test('a refresh resolves the device zone and reports it', () async {
    final source = FakeZoneSource(_shanghai);
    final controller = controllerFor(source);
    addTearDown(controller.dispose);
    expect(controller.displayIanaId, isNull);
    await controller.refresh();
    expect(controller.deviceIanaId, 'Asia/Shanghai');
    expect(controller.displayIanaId, 'Asia/Shanghai');
    expect(controller.followsDeviceZone, isTrue);

    source.reading = _unreadable;
    await controller.refresh();
    expect(controller.displayIanaId, isNull);
    expect(controller.problem, DeviceTimeZoneProblem.unavailable);
  });

  test(
    'a user choice wins until it is cleared and rejects unknown ids',
    () async {
      final source = FakeZoneSource(_shanghai);
      final controller = controllerFor(source);
      addTearDown(controller.dispose);
      await controller.refresh();

      expect(controller.chooseIana('Not/AZone'), isFalse);
      expect(controller.displayIanaId, 'Asia/Shanghai');
      expect(controller.chooseIana('Europe/Berlin'), isTrue);
      expect(controller.selectedIanaId, 'Europe/Berlin');
      expect(controller.displayIanaId, 'Europe/Berlin');
      expect(controller.followsDeviceZone, isFalse);

      // A later device reading, including a broken one, does not drop the choice.
      source.reading = _tokyo;
      await controller.refresh();
      expect(controller.displayIanaId, 'Europe/Berlin');
      source.reading = _unreadable;
      await controller.refresh();
      expect(controller.displayIanaId, 'Europe/Berlin');

      controller.useDeviceZone();
      expect(controller.selectedIanaId, isNull);
      expect(controller.displayIanaId, isNull);
    },
  );

  test('a platform change event re-reads the device zone', () async {
    final source = FakeZoneSource(_shanghai);
    final changes = StreamController<void>.broadcast();
    addTearDown(changes.close);
    final controller = controllerFor(source, changes: changes.stream);
    addTearDown(controller.dispose);
    await controller.refresh();
    final readsBefore = source.reads;
    expect(controller.displayIanaId, 'Asia/Shanghai');

    source.reading = _tokyo;
    changes.add(null);
    await pumpEventQueue();
    expect(source.reads, greaterThan(readsBefore));
    expect(controller.displayIanaId, 'Asia/Tokyo');
  });

  test('a resolved app re-reads the device zone', () async {
    final source = FakeZoneSource(_shanghai);
    final controller = controllerFor(source);
    addTearDown(controller.dispose);
    await controller.refresh();
    final readsBefore = source.reads;

    source.reading = _tokyo;
    controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await pumpEventQueue();
    expect(source.reads, greaterThan(readsBefore));
    expect(controller.displayIanaId, 'Asia/Tokyo');
  });

  testWidgets('the page re-renders in the changed zone and rewrites nothing', (
    tester,
  ) async {
    final store = await c2Store();
    final before = c2Library(store);
    final source = FakeZoneSource(_shanghai);
    final controller = controllerFor(source);
    addTearDown(controller.dispose);
    await controller.refresh();
    await pumpPlanner(tester, store, controller);
    expect(find.textContaining('0:30'), findsOneWidget);
    await _openZoneMenu(tester);
    expect(find.textContaining('Asia/Shanghai'), findsWidgets);

    source.reading = _tokyo;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.textContaining('1:30'), findsOneWidget);
    await _openZoneMenu(tester);
    expect(find.textContaining('Asia/Tokyo'), findsWidgets);
    expect(c2Library(store), before);

    // A zone whose day window excludes the record shows the day as empty
    // instead of leaving a stale entry behind.
    source.reading = _newYork;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text(store.t['scheduleEmpty']!), findsNothing);
    expect(find.byKey(const ValueKey('schedule-scroll')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('schedule-item-2026-09-30-block')),
      findsNothing,
    );
    expect(c2Library(store), before);
    await c2Finish(tester, store);
  });

  testWidgets(
    'an open form keeps its record zone and wall time across a zone change',
    (tester) async {
      final store = await c2Store();
      final before = c2Library(store);
      final source = FakeZoneSource(_shanghai);
      final controller = controllerFor(source);
      addTearDown(controller.dispose);
      await controller.refresh();
      await pumpPlanner(tester, store, controller);

      await c2Tap(tester, c2Key('schedule-add'));
      await c2Tap(tester, c2Key('schedule-create-timeBlock'));
      await c2Text(tester, 'schedule-editor-start-time', '10:00');
      expect(
        tester
            .widget<TextFormField>(c2Key('schedule-editor-zone'))
            .initialValue,
        'Asia/Shanghai',
      );

      source.reading = _tokyo;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(c2Key('schedule-editor-zone'))
            .initialValue,
        'Asia/Shanghai',
      );
      expect(
        tester
            .widget<TextFormField>(c2Key('schedule-editor-start-time'))
            .initialValue,
        '10:00',
      );
      await c2Tap(tester, c2Key('schedule-editor-cancel'));
      expect(c2Library(store), before);
      await c2Finish(tester, store);
    },
  );

  test(
    'a DST fold or gap in the opened form is not re-resolved by a zone change',
    () async {
      final store = await c2Store();
      addTearDown(store.dispose);
      final before = jsonEncode(store.captureSnapshot().scheduleItems);
      final session = ScheduleEditSession.create(
        store,
        ScheduleItemKind.timeBlock,
        'America/New_York',
        ScheduleCivilDate(2026, 11, 1),
      )..taskId = 'outline';
      session.start.date = '2026-11-01';
      session.start.time = '01:30';
      final candidates = session.start.candidates(session.timeZoneId);
      expect(candidates, hasLength(2));
      session.start.offset = candidates.last.offset;
      final resolved = session.start.resolve(session.timeZoneId);
      expect(session.timeZoneId, 'America/New_York');
      expect(session.start.resolve(session.timeZoneId), resolved);
      expect(session.start.candidates(session.timeZoneId), hasLength(2));

      final gap = ScheduleEditSession.create(
        store,
        ScheduleItemKind.timeBlock,
        'America/New_York',
        ScheduleCivilDate(2026, 3, 8),
      )..taskId = 'outline';
      gap.start.date = '2026-03-08';
      gap.start.time = '02:30';
      expect(gap.start.candidates(gap.timeZoneId), isEmpty);
      expect(
        () => gap.start.resolve(gap.timeZoneId),
        throwsA(
          isA<ScheduleTimeException>().having(
            (error) => error.reason,
            'reason',
            ScheduleTimeError.gap,
          ),
        ),
      );
      expect(jsonEncode(store.captureSnapshot().scheduleItems), before);
    },
  );
}
