import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/planner/planner_week_view.dart';
import 'package:matrixflow_native/screens/planner_screen.dart';

import 'wp15_c2_test_support.dart';

void main() {
  const size = Size(400, 800);

  testWidgets('swiping the day grid changes the day, with the motion', (
    tester,
  ) async {
    final store = await c2Store(items: [c1Items().first]);
    await c2Pump(tester, store, size: size);
    expect(c2Key('schedule-day-2026-09-30'), findsOneWidget);
    await tester.fling(c2Key('schedule-scroll'), const Offset(-300, 0), 900);
    await tester.pump(const Duration(milliseconds: 60));
    // Mid-transition: the page is moving, not swapped instantly.
    expect(c2Key('schedule-motion'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(c2Key('schedule-day-2026-10-01'), findsOneWidget);
    await tester.fling(c2Key('schedule-scroll'), const Offset(300, 0), 900);
    await tester.pumpAndSettle();
    await tester.fling(c2Key('schedule-scroll'), const Offset(300, 0), 900);
    await tester.pumpAndSettle();
    expect(c2Key('schedule-day-2026-09-29'), findsOneWidget);
    await c2Finish(tester, store);
  });

  testWidgets('"back to today" only shows away from today', (tester) async {
    final store = await c2Store(items: []);
    final today = DateTime.now();
    await c2Pump(tester, store, size: size);
    // The fixture opens on 2026-09-30; unless that is today, the pill shows.
    final onToday = today.year == 2026 && today.month == 9 && today.day == 30;
    expect(c2Key('schedule-today'), onToday ? findsNothing : findsOneWidget);
    if (!onToday) {
      expect(find.text('Back to today'), findsOneWidget);
      await c2Tap(tester, c2Key('schedule-today'));
      expect(c2Key('schedule-today'), findsNothing);
      // The same pill is not on screen while viewing today's week either.
      await tester.tap(c2Key('schedule-mode-week'));
      await tester.pumpAndSettle();
      expect(c2Key('schedule-today'), findsNothing);
    }
    await c2Finish(tester, store);
  });

  testWidgets('a small nudge on the date strip does not jump a week', (
    tester,
  ) async {
    final store = await c2Store(items: []);
    await c2Pump(tester, store, size: size);
    final strip = c2Key('schedule-strip');
    final g = await tester.startGesture(tester.getCenter(strip));
    await g.moveBy(const Offset(24, 0));
    await tester.pump();
    await g.moveBy(const Offset(24, 0));
    await tester.pump();
    // It follows the finger...
    expect(tester.widget<PageView>(strip).controller!.page!, lessThan(5000));
    await g.up();
    await tester.pumpAndSettle();
    // ...and settles back on the same week.
    expect(c2Key('schedule-day-2026-09-30'), findsOneWidget);
    // A real swipe moves one week.
    await tester.fling(strip, const Offset(-300, 0), 1200);
    await tester.pumpAndSettle();
    expect(c2Key('schedule-day-2026-10-07'), findsOneWidget);
    await c2Finish(tester, store);
  });

  testWidgets('week labels are as wide as their text and share a line', (
    tester,
  ) async {
    final store = await c2Store(
      items: [
        c1Event('a', c1At(30, 1), c1At(30, 2)),
        c1Event('b', c1At(30, 3), c1At(30, 4)),
      ],
    );
    // The test font is very wide, so give the row room for two labels.
    await c2Pump(
      tester,
      store,
      size: const Size(640, 800),
      view: PlannerView.week,
    );
    final a = tester.getRect(c2Key('schedule-item-2026-09-30-a'));
    final b = tester.getRect(c2Key('schedule-item-2026-09-30-b'));
    expect((a.top - b.top).abs(), lessThan(1));
    expect(a.right, lessThan(b.left));
    expect(a.width, lessThan(200), reason: 'not stretched to the line');
    await c2Finish(tester, store);
  });

  testWidgets('the week axis goes through every circle centre', (tester) async {
    final store = await c2Store(items: []);
    await c2Pump(tester, store, size: size, view: PlannerView.week);
    expect(plannerWeekAxisX(), 12 + 48 + 20);
    final axis = tester.getTopLeft(c2Key('schedule-week-axis-2026-09-28')).dx;
    final painter =
        tester
                .widget<CustomPaint>(c2Key('schedule-week-axis-2026-09-28'))
                .painter!
            as PlannerWeekAxisPainter;
    for (final d in ['2026-09-28', '2026-09-30', '2026-10-04']) {
      final node = tester.getCenter(c2Key('schedule-week-node-$d'));
      expect(axis + painter.x, closeTo(node.dx, 0.01));
    }
    await c2Finish(tester, store);
  });

  testWidgets('the week axis and the day grid reach the pool bar', (
    tester,
  ) async {
    final store = await c2Store(items: [c1Items().first]);
    await c2Pump(tester, store, size: size, view: PlannerView.week);
    final fill = tester.getRect(c2Key('schedule-week-axis-end'));
    expect(fill.bottom, closeTo(size.height, 0.5));
    await c2Tap(tester, c2Key('schedule-mode-day'));
    await tester.pumpAndSettle();
    final scroll = tester.getRect(c2Key('schedule-scroll'));
    expect(scroll.bottom, closeTo(size.height, 0.5));
    await c2Finish(tester, store);
  });

  testWidgets('the line starts at the first circle and runs on past the last', (
    tester,
  ) async {
    final store = await c2Store(items: []);
    await c2Pump(tester, store, size: size, view: PlannerView.week);
    final days = [
      '2026-09-28',
      '2026-09-29',
      '2026-09-30',
      '2026-10-01',
      '2026-10-02',
      '2026-10-03',
      '2026-10-04',
    ];
    final ys = [
      for (final d in days) tester.getCenter(c2Key('schedule-week-node-$d')).dy,
    ];
    final d = ys[1] - ys[0];
    expect(d, greaterThan(40));
    for (var i = 1; i < 7; i++) {
      expect(ys[i] - ys[i - 1], closeTo(d, 0.5), reason: 'gap $i');
    }
    // The first row draws its line from the circle's centre: nothing above.
    final first = c2Key('schedule-week-axis-${days.first}');
    final painter =
        tester.widget<CustomPaint>(first).painter! as PlannerWeekAxisPainter;
    expect(painter.fromCentre, isTrue);
    expect(tester.getRect(first).center.dy, closeTo(ys.first, 0.5));
    // Later rows are drawn whole; the last circle is followed by line down to
    // the pool bar.
    final second =
        tester
                .widget<CustomPaint>(c2Key('schedule-week-axis-${days[1]}'))
                .painter!
            as PlannerWeekAxisPainter;
    expect(second.fromCentre, isFalse);
    final end = tester.getRect(c2Key('schedule-week-axis-end'));
    expect(end.top, greaterThan(ys.last));
    expect(end.top - ys.last, closeTo(d / 2, 1));
    expect(end.bottom, closeTo(size.height, 0.5));
    await c2Finish(tester, store);
  });

  testWidgets('a crowded day grows its row and the page scrolls', (
    tester,
  ) async {
    final store = await c2Store(
      items: [
        for (var i = 0; i < 12; i++)
          c1Event('e$i', c1At(30, i), c1At(30, i + 1)),
      ],
    );
    await c2Pump(
      tester,
      store,
      size: const Size(360, 640),
      view: PlannerView.week,
    );
    final tall = tester.getSize(c2Key('schedule-day-2026-09-30')).height;
    final empty = tester.getSize(c2Key('schedule-day-2026-09-28')).height;
    expect(tall, greaterThan(empty));
    await c2Finish(tester, store);
  });
}
