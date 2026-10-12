// Round 15: rounded comic menus, right-aligned desktop toolbar, resizable side
// pool, skinned Day | Week control.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/theme.dart';
import 'package:matrixflow_native/widgets/home_actions.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'foundation_regression_test.dart' as fixture;
import 'helpers.dart';
import 'wp15_c2_test_support.dart';

const _desk = Size(1400, 900);

void main() {
  for (final comic in [true, false]) {
    testWidgets('desktop More panel clips to the dialog shape: comic=$comic', (
      tester,
    ) async {
      final (store, _) = await makeStore(
        boards: [Board(id: 'b1', name: 'Board', createdAt: 1)],
      );
      await tester.pumpWidget(
        fixture.app(
          store,
          Builder(
            builder: (outer) {
              final base = ThemeData(platform: TargetPlatform.windows);
              return Theme(
                data: comic ? applyComicOutline(base) : base,
                child: Builder(
                  builder: (context) => TextButton(
                    onPressed: () => showHomeMore(context),
                    child: const Text('go'),
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      final dialog = tester.widget<Dialog>(find.byType(Dialog));
      expect(dialog.clipBehavior, comic ? Clip.antiAlias : Clip.none);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    });
  }

  testWidgets('desktop toolbar: Today and Day | Week sit at the right', (
    tester,
  ) async {
    final store = await c2Store();
    await c2Pump(tester, store, size: _desk, platform: TargetPlatform.windows);
    final pool = tester.getRect(c2Key('schedule-pool-docked'));
    final week = tester.getRect(c2Key('schedule-mode-week'));
    final today = tester.getRect(c2Key('schedule-today-button'));
    expect(pool.left - week.right, inInclusiveRange(4, 24));
    expect(today.right, lessThan(week.left));
    expect(week.left - today.right, lessThan(80));
    await c2Finish(tester, store);
  });

  testWidgets('side pool edge drags wider, clamps, and is remembered', (
    tester,
  ) async {
    final store = await c2Store();
    await c2Pump(tester, store, size: _desk, platform: TargetPlatform.windows);
    double width() => tester.getRect(c2Key('schedule-pool-docked')).width;
    expect(width(), closeTo(400, 1));
    final handle = c2Key('schedule-pool-resize');
    final g = await tester.startGesture(
      tester.getCenter(handle),
      kind: PointerDeviceKind.mouse,
    );
    await g.moveBy(const Offset(-40, 0));
    await g.moveBy(const Offset(-60, 0));
    await g.up();
    await tester.pumpAndSettle();
    // Follows the mouse once past the drag slop.
    expect(width(), greaterThan(450));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getDouble('compoise-planner-dock-width'), closeTo(width(), 1));
    // Way past the limits: stops at 280 and at 560 (half of 1400 is 700).
    await tester.drag(handle, const Offset(800, 0));
    await tester.pumpAndSettle();
    expect(width(), closeTo(280, 1));
    await tester.drag(handle, const Offset(-900, 0));
    await tester.pumpAndSettle();
    expect(width(), closeTo(560, 1));
    // A fresh page starts at the remembered width.
    await tester.pumpWidget(const SizedBox());
    await c2Pump(tester, store, size: _desk, platform: TargetPlatform.windows);
    await tester.pumpAndSettle();
    expect(width(), closeTo(560, 1));
    await c2Finish(tester, store);
  });

  for (final skin in ['default', 'comic', 'neu']) {
    testWidgets('Day | Week control in $skin', (tester) async {
      final store = await c2Store();
      await c2Pump(
        tester,
        store,
        size: _desk,
        platform: TargetPlatform.windows,
        skin: skin,
      );
      if (skin == 'default') {
        expect(find.byType(ChoiceChip), findsNWidgets(2));
        expect(c2Key('schedule-mode-segments'), findsNothing);
      } else {
        expect(find.byType(ChoiceChip), findsNothing);
        final track = tester.widget<Container>(c2Key('schedule-mode-segments'));
        final trackDeco = track.decoration! as BoxDecoration;
        BoxDecoration selected() =>
            tester
                    .widget<Container>(
                      find.descendant(
                        of: c2Key('schedule-mode-day'),
                        matching: find.byType(Container),
                      ),
                    )
                    .decoration!
                as BoxDecoration;
        if (skin == 'neu') {
          // Groove under, the selected half raised.
          expect(trackDeco.boxShadow ?? const [], isEmpty);
          expect(selected().boxShadow, isNotEmpty);
        } else {
          expect((trackDeco.border! as Border).top.width, 2);
          expect((selected().border! as Border).top.width, 2);
        }
        await tester.tap(c2Key('schedule-mode-week'));
        await tester.pumpAndSettle();
        expect(c2Key('schedule-week-rows'), findsOneWidget);
      }
      await c2Finish(tester, store);
    });
  }
}
