import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/planner/planner_drag_feedback.dart';
import 'package:matrixflow_native/schedule_time.dart';
import 'package:matrixflow_native/widgets/schedule_layout.dart';
import 'package:matrixflow_native/widgets/tab_slider.dart';

import 'wp15_c2_test_support.dart';

void main() {
  const screen = Size(400, 800);
  const box = Size(200, 56);

  test('the drag preview sits up and left of the finger', () {
    final o = plannerDragOrigin(const Offset(300, 500), box, screen);
    expect(o.dx + box.width, lessThan(300));
    expect(o.dy + box.height, lessThan(500));
  });

  test(
    'near the left or top edge the preview stays on screen, above the finger',
    () {
      final left = plannerDragOrigin(const Offset(20, 500), box, screen);
      expect(left.dx, greaterThanOrEqualTo(8));
      expect(left.dy + box.height, lessThan(500));
      expect(left.dx + box.width, lessThanOrEqualTo(screen.width - 8));
      final top = plannerDragOrigin(const Offset(300, 10), box, screen);
      expect(top.dy, greaterThanOrEqualTo(8));
      final corner = plannerDragOrigin(const Offset(399, 799), box, screen);
      expect(corner.dx + box.width, lessThanOrEqualTo(screen.width));
      expect(corner.dy + box.height, lessThanOrEqualTo(screen.height));
    },
  );

  testWidgets(
    'a task dragged from the pool is previewed up-left of the finger',
    (tester) async {
      final store = await c2Store();
      await c2Pump(tester, store, size: const Size(400, 800));
      await tester.tap(find.textContaining('Task pool'));
      await tester.pumpAndSettle();
      await tester.tap(c2Key('schedule-pool-tab-2'));
      await tester.pumpAndSettle();
      final card = c2Key('schedule-pool-outline');
      final start = tester.getCenter(card);
      final g = await tester.startGesture(start);
      await tester.pump(const Duration(milliseconds: 700));
      await g.moveBy(const Offset(0, -150));
      await tester.pump();
      final finger = tester.getCenter(card) + const Offset(0, 0);
      final feedback = find.byType(PlannerDragFeedback);
      expect(feedback, findsOneWidget);
      final inner = tester.getRect(
        find.descendant(of: feedback, matching: find.byType(Material)).first,
      );
      final p = start + const Offset(0, -150);
      expect(inner.bottom, lessThan(p.dy));
      expect(inner.left, greaterThanOrEqualTo(0));
      expect(inner.top, greaterThanOrEqualTo(0));
      expect(finger, isNotNull);
      await g.up();
      await tester.pumpAndSettle();
      await c2Finish(tester, store);
    },
  );

  testWidgets('tab slider keeps state, slides, and obeys reduce motion', (
    tester,
  ) async {
    Widget host(int i, {bool reduce = false}) => MediaQuery(
      data: MediaQueryData(disableAnimations: reduce),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 300,
            height: 200,
            child: TabSlider(
              index: i,
              children: const [
                _Counter(key: ValueKey('a')),
                _Counter(key: ValueKey('b')),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpWidget(host(0));
    await tester.tap(find.byKey(const ValueKey('a')));
    await tester.pump();
    expect(find.text('1'), findsOneWidget);
    await tester.pumpWidget(host(1));
    await tester.pump(const Duration(milliseconds: 60));
    // Mid-way both pages are on screen, offset by the slide.
    final a = tester.getTopLeft(find.byKey(const ValueKey('a'))).dx;
    final b = tester.getTopLeft(find.byKey(const ValueKey('b'))).dx;
    expect(a, lessThan(0));
    expect(b, greaterThan(0));
    expect(b, lessThan(300));
    await tester.pumpAndSettle();
    await tester.pumpWidget(host(0));
    await tester.pumpAndSettle();
    expect(find.text('1'), findsOneWidget, reason: 'state kept');
    // Reduced motion: no in-between frame.
    await tester.pumpWidget(host(1, reduce: true));
    await tester.pump();
    expect(tester.getTopLeft(find.byKey(const ValueKey('b'))).dx, 0);
  });

  test('stepping a day or a week crosses month, year and leap day', () {
    expect(
      scheduleDateLabel(ScheduleCivilDate(2026, 12, 31).addDays(1)),
      scheduleDateLabel(ScheduleCivilDate(2027, 1, 1)),
    );
    expect(
      scheduleDateLabel(ScheduleCivilDate(2027, 1, 1).addDays(-1)),
      scheduleDateLabel(ScheduleCivilDate(2026, 12, 31)),
    );
    expect(
      scheduleDateLabel(ScheduleCivilDate(2028, 2, 28).addDays(1)),
      scheduleDateLabel(ScheduleCivilDate(2028, 2, 29)),
    );
    expect(
      scheduleDateLabel(ScheduleCivilDate(2026, 10, 28).addDays(7)),
      scheduleDateLabel(ScheduleCivilDate(2026, 11, 4)),
    );
    // A DST change day is still one civil day.
    expect(
      scheduleDateLabel(ScheduleCivilDate(2026, 3, 8).addDays(1)),
      scheduleDateLabel(ScheduleCivilDate(2026, 3, 9)),
    );
  });

  testWidgets('back closes the dialog, then the selection, then the pool', (
    tester,
  ) async {
    final store = await c2Store(items: [c1Items().first]);
    await c2Pump(tester, store, size: const Size(400, 800));
    const block = 'schedule-item-2026-09-30-block';
    await c2Tap(tester, c2Key(block));
    expect(c2Key('schedule-detail'), findsOneWidget);
    await c2Tap(tester, c2Key('schedule-detail-edit'));
    expect(c2Key('schedule-editor'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(c2Key('schedule-editor'), findsNothing);
    // Selection is still there; back drops it without leaving the page.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(c2Key('schedule-detail'), findsNothing);
    expect(c2Key('schedule-scroll'), findsOneWidget);
    await c2Finish(tester, store);
  });

  testWidgets('a drag cannot carry a block past the ends of the day', (
    tester,
  ) async {
    final store = await c2Store(
      items: [c1Event('late', c1At(30, 22), c1At(30, 23))],
    );
    await c2Pump(tester, store, size: const Size(400, 800));
    await tester.pumpAndSettle();
    final key = c2Key('schedule-item-2026-09-30-late');
    await tester.ensureVisible(key);
    await tester.pumpAndSettle();
    final g = await tester.startGesture(tester.getCenter(key));
    await tester.pump(const Duration(milliseconds: 700));
    await g.moveBy(const Offset(0, 40));
    await tester.pump();
    await g.moveBy(const Offset(0, 40));
    await tester.pump();
    await g.moveBy(const Offset(0, 600));
    await tester.pump();
    final time = tester.widgetList<Text>(c2Key('schedule-drag-time'));
    expect(time.single.data, contains('23:00'));
    expect(time.single.data, anyOf(contains('24:00'), contains('0:00')));
    await g.up();
    await tester.pumpAndSettle();
    await c2Finish(tester, store);
  });

  // Sweep: every state at every awkward size/scale/theme renders without
  // overflow or exceptions.
  for (final size in [
    const Size(360, 640),
    const Size(320, 568),
    const Size(800, 360), // landscape phone
    const Size(1200, 900),
    const Size(500, 700), // narrowed desktop window
  ]) {
    for (final scale in [1.0, 1.3, 2.0]) {
      for (final dark in [false, true]) {
        testWidgets('sweep ${size.width.toInt()}x${size.height.toInt()} '
            '@$scale ${dark ? 'dark' : 'light'}', (tester) async {
          final store = await c2Store(
            items: [
              c1Items().first,
              c1Event('x', c1At(30, 1), c1At(30, 3)),
              c1Event('y', c1At(30, 2), c1At(30, 4)),
              c1Event('z', c1At(30, 9), c1At(30, 9, minute: 15)),
            ],
          );
          await c2Pump(tester, store, size: size, scale: scale, dark: dark);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'day');
          await tester.tap(find.textContaining('Task pool'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'pool open');
          await tester.tap(c2Key('schedule-pool-tab-2'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'pool tab');
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
          await c2Tap(tester, c2Key('schedule-mode-week'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'week');
          await c2Tap(tester, c2Key('schedule-mode-day'));
          await tester.pumpAndSettle();
          await c2Tap(tester, c2Key('schedule-item-2026-09-30-x'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'selected');
          await c2Tap(tester, c2Key('schedule-detail-edit'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'editor');
          await c2Finish(tester, store);
        });
      }
    }
  }
}

class _Counter extends StatefulWidget {
  const _Counter({super.key});
  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int n = 0;
  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () => setState(() => n++),
    child: Center(child: Text('$n')),
  );
}
