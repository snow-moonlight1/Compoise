import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:compoise/planner/planner_guide_flag.dart';

import 'wp15_c2_test_support.dart';

void main() {
  testWidgets(
    'tapping the pool opens about a quarter of the page, not all of it',
    (tester) async {
      final store = await c2Store();
      await c2Pump(tester, store, size: const Size(400, 800));
      await tester.tap(find.textContaining('Task pool'));
      await tester.pumpAndSettle();
      final top = tester.getTopLeft(c2Key('schedule-pool-tab-1')).dy;
      // Header and tabs sit near the top of a sheet that is ~30% of the page.
      expect(top, greaterThan(800 * 0.66));
      expect(top, lessThan(800 * 0.8));
      // A second tap folds it down again.
      await tester.tap(find.text('Task pool'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Task pool · '), findsOneWidget);
      await c2Finish(tester, store);
    },
  );

  testWidgets('a task that already has a schedule item stays in the pool', (
    tester,
  ) async {
    final store = await c2Store(); // 'outline' is linked by the time block
    await c2Pump(tester, store, size: const Size(400, 800));
    await tester.tap(find.textContaining('Task pool'));
    await tester.pumpAndSettle();
    await tester.tap(c2Key('schedule-pool-tab-2'));
    await tester.pumpAndSettle();
    expect(c2Key('schedule-pool-outline'), findsOneWidget);
    expect(find.byIcon(Icons.event_available), findsOneWidget);
    await c2Finish(tester, store);
  });

  testWidgets(
    'quadrants slide with the page, tabs follow, the hint shows once',
    (tester) async {
      final store = await c2Store();
      await tester.runAsync(
        () => PlannerGuideFlags.mark(PlannerGuideFlags.tabHintKey, false),
      );
      await c2Pump(tester, store, size: const Size(400, 800));
      await tester.tap(find.textContaining('Task pool'));
      await tester.pumpAndSettle();
      expect(c2Key('schedule-tab-hint'), findsOneWidget);
      // Swipe from the first quadrant to the second: it animates, so halfway
      // through both pages are partly on screen.
      final pages = c2Key('schedule-pool-pages');
      final gesture = await tester.startGesture(tester.getCenter(pages));
      await gesture.moveBy(const Offset(-60, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(-200, 0));
      await tester.pump();
      final mid = tester.widget<PageView>(pages).controller!.page!;
      expect(mid, greaterThan(0.1));
      expect(mid, lessThan(1.0));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(tester.widget<PageView>(pages).controller!.page, 1.0);
      expect(c2Key('schedule-tab-hint'), findsNothing);
      expect(c2Key('schedule-pool-outline'), findsOneWidget);
      await c2Finish(tester, store);
    },
  );

  testWidgets('tapping a tab animates to that quadrant', (tester) async {
    final store = await c2Store();
    await c2Pump(tester, store, size: const Size(400, 800));
    await tester.tap(find.textContaining('Task pool'));
    await tester.pumpAndSettle();
    await tester.tap(c2Key('schedule-pool-tab-3'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final page = tester
        .widget<PageView>(c2Key('schedule-pool-pages'))
        .controller!
        .page!;
    expect(page, greaterThan(0));
    expect(page, lessThan(2.0));
    await tester.pumpAndSettle();
    expect(
      tester.widget<PageView>(c2Key('schedule-pool-pages')).controller!.page,
      2.0,
    );
    await c2Finish(tester, store);
  });
}
