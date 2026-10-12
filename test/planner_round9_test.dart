import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:compoise/screens/planner_screen.dart';

import 'wp15_c2_test_support.dart';

void main() {
  const size = Size(400, 800);

  testWidgets('the today button is round, bottom right, clear of the "+"', (
    tester,
  ) async {
    final store = await c2Store(items: [c1Items().first]);
    await c2Pump(tester, store, size: size);
    final fab = tester.getRect(c2Key('schedule-today'));
    final add = tester.getRect(c2Key('schedule-add'));
    expect(fab.width, fab.height);
    expect(fab.width, closeTo(56, 0.5));
    expect(size.width - fab.right, inInclusiveRange(20, 24));
    expect(add.top - fab.bottom, greaterThanOrEqualTo(10));
    expect(fab.right, greaterThan(size.width - 32));
    expect(fab.overlaps(add), isFalse);
    expect(fab.bottom, lessThanOrEqualTo(add.top));
    expect(find.text('T'), findsOneWidget);
    // While the pool is open the button steps aside.
    await tester.tap(find.textContaining('Task pool'));
    await tester.pumpAndSettle();
    expect(c2Key('schedule-today'), findsNothing);
    await c2Finish(tester, store);
  });

  testWidgets('in the week view the button goes to this week, mode kept', (
    tester,
  ) async {
    final store = await c2Store(items: []);
    await c2Pump(tester, store, size: size, view: PlannerView.week);
    expect(c2Key('schedule-today'), findsOneWidget);
    await c2Tap(tester, c2Key('schedule-today'));
    expect(c2Key('schedule-today'), findsNothing);
    expect(c2Key('schedule-week-rows'), findsOneWidget);
    await c2Finish(tester, store);
  });

  testWidgets('the week view has no week-number row', (tester) async {
    final store = await c2Store(items: []);
    await c2Pump(tester, store, size: size, view: PlannerView.week);
    expect(find.textContaining('Week '), findsNothing);
    final scroll = tester.getRect(c2Key('schedule-scroll'));
    final rows = tester.getRect(c2Key('schedule-week-rows'));
    expect(rows.top, closeTo(scroll.top, 0.5));
    final end = tester.getRect(c2Key('schedule-week-axis-end'));
    expect(end.bottom, closeTo(size.height, 0.5));
    await c2Finish(tester, store);
  });

  testWidgets('the pool opens to about a third; tapping empty space folds it', (
    tester,
  ) async {
    final store = await c2Store(items: [c1Items().first]);
    await c2Pump(tester, store, size: size);
    await tester.tap(find.textContaining('Task pool'));
    await tester.pumpAndSettle();
    final top = tester.getTopLeft(c2Key('schedule-pool-tab-1')).dy;
    final share = 1 - (top - 44 * 0 - 56) / size.height;
    expect(share, inInclusiveRange(0.30, 0.37));
    // Empty content area (timeline gap near the top-left of the grid).
    await tester.tapAt(const Offset(200, 330));
    await tester.pumpAndSettle();
    expect(find.text('Task pool'), findsNothing);
    expect(find.textContaining('Task pool · '), findsOneWidget);
    await c2Finish(tester, store);
  });

  testWidgets('a tap on a block still selects it while the pool folds', (
    tester,
  ) async {
    final store = await c2Store(items: [c1Items().first]);
    await c2Pump(tester, store, size: size);
    await c2Tap(tester, c2Key('schedule-item-2026-09-30-block'));
    await tester.tap(find.textContaining('Task pool'));
    await tester.pumpAndSettle();
    // Block is under the open pool? Bring it into the visible area first.
    final block = c2Key('schedule-item-2026-09-30-block');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Task pool'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(block);
    await tester.pumpAndSettle();
    final r = tester.getRect(block);
    if (r.center.dy < 520) {
      await tester.tapAt(r.center);
      await tester.pumpAndSettle();
      expect(c2Key('schedule-detail'), findsOneWidget);
      expect(find.text('Task pool'), findsNothing);
    }
    await c2Finish(tester, store);
  });
}
