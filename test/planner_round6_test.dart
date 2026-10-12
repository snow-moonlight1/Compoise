import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:compoise/models.dart';
import 'package:compoise/storage.dart';
import 'package:compoise/widgets/input_sheet.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'wp15_c2_test_support.dart';

void main() {
  testWidgets('switching the add mode changes colour only, never the size', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'compoise-has-seen-onboarding': true,
    });
    final store = Store();
    await store.init();
    await tester.binding.setSurfaceSize(const Size(360, 800));
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: store,
        child: const MaterialApp(
          home: Scaffold(
            body: InputSheet(initialMode: InputModePref.single, embedded: true),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final chips = find.byType(ChoiceChip);
    expect(chips, findsNWidgets(3));
    List<Rect> rects() => [
      for (var i = 0; i < 3; i++) tester.getRect(chips.at(i)),
    ];
    final before = rects();
    final sheet = tester.getSize(find.byType(InputSheet)).height;
    // Same row, equal widths.
    expect(before[0].top, before[2].top);
    expect(before[0].width, closeTo(before[2].width, 0.01));
    for (var i = 0; i < 3; i++) {
      await tester.tap(chips.at(i));
      await tester.pump();
      expect(rects(), before, reason: 'mode $i');
      await tester.pumpAndSettle();
      expect(rects(), before, reason: 'mode $i settled');
      expect(tester.widget<ChoiceChip>(chips.at(i)).selected, isTrue);
      expect(find.byIcon(Icons.check), findsNothing);
    }
    expect(sheet, greaterThan(0));
    await tester.binding.setSurfaceSize(null);
    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
    await tester.pump();
  });

  testWidgets('the pool dots and counts glide while it opens', (tester) async {
    final store = await c2Store();
    await c2Pump(tester, store, size: const Size(400, 800));
    final dot = c2Key('schedule-pool-dot-1');
    final count = c2Key('schedule-pool-count-1');
    final folded = tester.getTopLeft(dot);
    final foldedCount = tester.getTopLeft(count);
    await tester.tap(find.textContaining('Task pool'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    // Mid-way the shared dot and count are still on screen...
    expect(dot, findsOneWidget);
    expect(count, findsOneWidget);
    final mid = tester.getTopLeft(dot);
    await tester.pumpAndSettle();
    final opened = tester.getTopLeft(dot);
    final openedCount = tester.getTopLeft(count);
    // ...and have moved from the bar to the quadrant tab.
    expect(opened, isNot(folded));
    expect(openedCount, isNot(foldedCount));
    expect(mid.dy, lessThan(folded.dy));
    expect(mid.dy, greaterThan(opened.dy));
    // At rest the count sits on its tab, not in the old bar slot.
    final tab = tester.getRect(c2Key('schedule-pool-tab-1'));
    expect(tab.contains(opened + const Offset(4, 4)), isTrue);
    expect(tab.contains(openedCount + const Offset(2, 8)), isTrue);
    await c2Finish(tester, store);
  });

  testWidgets('with reduced motion the pool switches without a glide', (
    tester,
  ) async {
    final store = await c2Store();
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await c2Pump(tester, store, size: const Size(400, 800));
    await tester.tap(find.textContaining('Task pool'));
    await tester.pump();
    await tester.pump();
    expect(tester.getRect(c2Key('schedule-pool-tab-1')).top, lessThan(800));
    await c2Finish(tester, store);
  });

  testWidgets('block text is centred vertically and one line when short', (
    tester,
  ) async {
    final store = await c2Store(
      items: [
        c1Event('tall', c1At(30, 1), c1At(30, 4)),
        c1Event('short', c1At(30, 6), c1At(30, 6, minute: 15)),
      ],
    );
    await c2Pump(tester, store, size: const Size(400, 800));
    await tester.pumpAndSettle();
    final block = tester.getRect(c2Key('schedule-item-2026-09-30-tall'));
    final text = tester.getRect(
      find.descendant(
        of: c2Key('schedule-item-2026-09-30-tall'),
        matching: find.textContaining('tall'),
      ),
    );
    expect(text.left, lessThan(block.left + 40), reason: 'left aligned');
    expect(text.center.dy, lessThan(block.center.dy + 1));
    // Title and time together are centred.
    final times = tester.getRect(
      find.descendant(
        of: c2Key('schedule-item-2026-09-30-tall'),
        matching: find.textContaining(':'),
      ),
    );
    expect((text.top + times.bottom) / 2, closeTo(block.center.dy, 4));
    // A short block never overflows.
    expect(tester.takeException(), isNull);
    await c2Finish(tester, store);
  });
}
