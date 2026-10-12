import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:compoise/schedule_time.dart';
import 'package:compoise/screens/planner_screen.dart';
import 'package:compoise/storage.dart';

import 'wp15_c2_test_support.dart';
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
          '$brightness ${width}px ${scale}x the plain edit form stays reachable',
          (tester) async {
            final store = await c2Store();
            final before = c2Library(store);
            await pumpMatrix(
              tester,
              store: store,
              size: Size(width, 850),
              scale: scale,
              brightness: brightness,
            );
            await tester.tap(c2Key('schedule-add'));
            await tester.pumpAndSettle();
            expect(c2Key('schedule-editor'), findsOneWidget);
            final screen = Offset.zero & Size(width, 850);
            await tester.ensureVisible(c2Key('schedule-editor-save'));
            await tester.pumpAndSettle();
            expect(
              tester.getRect(c2Key('schedule-editor-save')).overlaps(screen),
              isTrue,
            );
            await tester.tap(c2Key('schedule-editor-cancel'));
            await tester.pumpAndSettle();
            expect(c2Library(store), before);
            expect(tester.takeException(), isNull);
            await c2Finish(tester, store);
          },
        );
      }
    }
  }

}
