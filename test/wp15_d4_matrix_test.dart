import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/schedule_item.dart';
import 'package:matrixflow_native/schedule_time.dart';
import 'package:matrixflow_native/screens/planner_screen.dart';
import 'package:matrixflow_native/storage.dart';

import 'wp15_c2_test_support.dart';
import 'wp15_d4_accessibility_test.dart' show tabTo, press, focusedScheduleKey;
import '../tool/wp15_d4_fixture.dart' show d4Fixture;

Future<void> pumpMatrix(
  WidgetTester tester, {
  Store? store,
  StoreSnapshot? snapshot,
  Size size = const Size(390, 850),
  double scale = 3,
  Brightness brightness = Brightness.light,
  ScheduleCivilDate? date,
  String zone = c1Zone,
  PlannerView view = PlannerView.day,
  Locale locale = const Locale('en'),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      supportedLocales: const [Locale('en'), Locale('zh'), Locale('ja')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(
        useMaterial3: true,
        brightness: brightness,
        platform: TargetPlatform.windows,
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: PlannerScreen(
        store: store,
        snapshot: snapshot,
        initialDate: date ?? ScheduleCivilDate(2026, 9, 30),
        initialView: view,
        displayTimeZoneId: zone,
        now: () => DateTime.utc(2026, 9, 30),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'manual fixtures use valid v3 imports and preserve absolute endpoints',
    (tester) async {
      final store = await c2Store(items: []);
      for (final fold in [false, true]) {
        final fixture = d4Fixture(fold: fold);
        final plan = store.previewImport(fixture, 'overwrite');
        expect((await store.applyImport(plan)).success, isTrue);
        expect(
          store.scheduleItems.map((item) => item.toJson()).toList(),
          fixture['scheduleItems'],
        );
        expect(store.tasks, hasLength(2));
        expect(
          store.tasks.every(
            (task) =>
                task.plannedDate != null &&
                task.deadline != null &&
                task.reminderAt != null,
          ),
          isTrue,
        );
      }
      await c2Finish(tester, store);
    },
  );
  for (final brightness in Brightness.values) {
    for (final width in [320.0, 390.0]) {
      for (final scale in [2.0, 3.0]) {
        testWidgets(
          '$brightness ${width}px ${scale}x form, picker and consent are reachable',
          (tester) async {
            final semantics = tester.ensureSemantics();
            final store = await c2Store();
            final before = c2Library(store);
            await pumpMatrix(
              tester,
              store: store,
              size: Size(width, 850),
              scale: scale,
              brightness: brightness,
            );
            await tabTo(tester, 'schedule-add');
            await press(tester, LogicalKeyboardKey.enter);
            await tabTo(tester, 'schedule-create-event');
            await press(tester, LogicalKeyboardKey.enter);
            await c2Text(tester, 'schedule-editor-title', 'Accessible event');
            await tabTo(tester, 'schedule-editor-choose-association');
            await press(tester, LogicalKeyboardKey.enter);
            await tabTo(tester, 'schedule-editor-association-home');
            await press(tester, LogicalKeyboardKey.enter);
            await c2Text(tester, 'schedule-editor-start-time', '01:00');
            await c2Text(tester, 'schedule-editor-end-time', '02:00');
            await tabTo(tester, 'schedule-editor-review');
            await press(tester, LogicalKeyboardKey.enter);
            expect(focusedScheduleKey(), 'schedule-editor-allow-overlap');
            expect(
              tester
                  .getRect(c2Key('schedule-editor-allow-overlap'))
                  .overlaps(Offset.zero & Size(width, 850)),
              isTrue,
            );
            await press(tester, LogicalKeyboardKey.space);
            await tabTo(tester, 'schedule-editor-save');
            final data = tester
                .getSemantics(c2Key('schedule-editor-save'))
                .getSemanticsData();
            expect(data.hasAction(SemanticsAction.tap), isTrue);
            expect(data.hasFlag(SemanticsFlag.isFocused), isTrue);
            expect(
              tester
                  .getRect(c2Key('schedule-editor-save'))
                  .overlaps(Offset.zero & Size(width, 850)),
              isTrue,
            );
            // Escape from review must keep an explicit choice about this draft.
            await press(tester, LogicalKeyboardKey.escape);
            await tabTo(tester, 'schedule-editor-discard');
            await press(tester, LogicalKeyboardKey.enter);
            expect(c2Library(store), before);
            expect(tester.takeException(), isNull);
            await c2Finish(tester, store);
            semantics.dispose();
          },
        );
      }
    }
  }

  testWidgets(
    'date picker Escape, day/week, today and both directions preserve library',
    (tester) async {
      final store = await c2Store();
      final before = c2Library(store);
      await pumpMatrix(tester, store: store, scale: 2);
      await tabTo(tester, 'schedule-date');
      await press(tester, LogicalKeyboardKey.enter);
      expect(find.byType(DatePickerDialog), findsOneWidget);
      await press(tester, LogicalKeyboardKey.escape);
      expect(find.byType(DatePickerDialog), findsNothing);
      expect(focusedScheduleKey(), 'schedule-date');
      await tabTo(tester, 'schedule-next');
      await press(tester, LogicalKeyboardKey.enter);
      expect(c2Key('schedule-day-2026-10-01'), findsOneWidget);
      await tabTo(tester, 'schedule-mode-week');
      await press(tester, LogicalKeyboardKey.enter);
      expect(c2Key('schedule-day-2026-09-28'), findsOneWidget);
      await tabTo(tester, 'schedule-next', reverse: true);
      await press(tester, LogicalKeyboardKey.enter);
      expect(c2Key('schedule-day-2026-10-05'), findsOneWidget);
      await tabTo(tester, 'schedule-today');
      await press(tester, LogicalKeyboardKey.enter);
      await tabTo(tester, 'schedule-mode-day');
      await press(tester, LogicalKeyboardKey.enter);
      expect(c2Key('schedule-day-2026-09-30'), findsOneWidget);
      expect(c2Library(store), before);
      expect(tester.takeException(), isNull);
      await c2Finish(tester, store);
    },
  );

  for (final month in [3, 11]) {
    testWidgets(
      'DST $month and midnight semantics distinguish both actual endpoints',
      (tester) async {
        final handle = tester.ensureSemantics();
        final date = ScheduleCivilDate(2026, month, month == 3 ? 8 : 1);
        const zone = 'America/New_York';
        int at(ScheduleCivilDate day, int hour) =>
            resolveWallTime(ScheduleWallTime(day, hour: hour, minute: 0), zone);
        final next = date.addDays(1);
        final items = [
          c1Event('ends', at(date.addDays(-1), 23), at(date, 0), zone: zone),
          c1Event('cross', at(date, 23), at(next, 0), zone: zone),
          ScheduleItem.timeBlock(
            id: 'last-ms',
            taskId: 'done',
            startAt: at(next, 0) - 1,
            endAt: at(next, 0),
            timeZoneId: zone,
          ),
        ];
        await pumpMatrix(
          tester,
          snapshot: c1Snapshot(items: items),
          date: date,
          zone: zone,
          brightness: Brightness.dark,
        );
        if (month == 3) {
          expect(find.text('2:00'), findsNothing);
          expect(find.text('3:00'), findsOneWidget);
        } else {
          expect(find.text('1:00'), findsNWidgets(2));
        }
        final day = month == 3 ? '2026-03-08' : '2026-11-01';
        final tomorrow = month == 3 ? '2026-03-09' : '2026-11-02';
        expect(c2Key('schedule-item-$day-ends'), findsNothing);
        await tabTo(tester, 'schedule-item-$day-cross');
        var label = tester
            .getSemantics(c2Key('schedule-semantics-$day-cross'))
            .getSemanticsData()
            .label;
        expect(label, contains('End: $tomorrow 00:00'));
        await tabTo(tester, 'schedule-item-$day-last-ms');
        label = tester
            .getSemantics(c2Key('schedule-semantics-$day-last-ms'))
            .getSemanticsData()
            .label;
        expect(label, contains('Completed'));
        expect(label, contains('23:59:59.999'));
        expect(
          tester
              .getRect(c2Key('schedule-item-$day-last-ms'))
              .overlaps(Offset.zero & const Size(390, 850)),
          isTrue,
        );
        expect(tester.takeException(), isNull);
        handle.dispose();
      },
    );
  }
}
