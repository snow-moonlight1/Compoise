import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/planner/planner_skin.dart';

import 'wp15_c2_test_support.dart';

BoxDecoration? _decorationOf(WidgetTester tester, Finder inside) {
  final boxes = find.descendant(
    of: inside,
    matching: find.byType(DecoratedBox),
  );
  for (final e in boxes.evaluate()) {
    final d = (e.widget as DecoratedBox).decoration;
    if (d is BoxDecoration && d.borderRadius != null) return d;
  }
  return null;
}

void main() {
  const block = 'schedule-item-2026-09-30-block';

  for (final skin in ['default', 'comic', 'neu']) {
    for (final dark in [false, true]) {
      final name = '$skin ${dark ? 'dark' : 'light'}';

      testWidgets('planner states render in $name', (tester) async {
        final store = await c2Store(
          items: [
            c1Items().first,
            c1Event('x', c1At(30, 1), c1At(30, 3)),
            c1Event('y', c1At(30, 2), c1At(30, 4)),
          ],
        );
        for (final size in [const Size(400, 800), const Size(360, 640)]) {
          await c2Pump(tester, store, size: size, dark: dark, skin: skin);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'day');
          expect(c2Key('schedule-today'), findsOneWidget);
          // Selected block + selection bar.
          await c2Tap(tester, c2Key('schedule-item-2026-09-30-x'));
          expect(c2Key('schedule-detail'), findsOneWidget);
          expect(tester.takeException(), isNull, reason: 'selected');
          await c2Tap(tester, c2Key('schedule-detail-edit'));
          expect(c2Key('schedule-editor'), findsOneWidget);
          expect(tester.takeException(), isNull, reason: 'editor');
          await c2Tap(tester, c2Key('schedule-editor-cancel'));
          await tester.tap(find.textContaining('Task pool'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'pool');
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
          await c2Tap(tester, c2Key('schedule-mode-week'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'week');
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        }
        await c2Finish(tester, store);
      });
    }
  }

  testWidgets('blocks, bar and button use the active skin', (tester) async {
    final store = await c2Store(items: [c1Items().first]);
    BoxDecoration? decoration(String key) => _decorationOf(tester, c2Key(key));

    // Default: thin accent outline, no shadow (unchanged).
    await c2Pump(tester, store, size: const Size(400, 800));
    final plain = decoration(block)!;
    expect((plain.border! as Border).top.width, lessThanOrEqualTo(1));
    expect(plain.boxShadow, anyOf(isNull, isEmpty));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    // Comic: 2dp outline in the ink edge colour, no shadow.
    await c2Pump(tester, store, size: const Size(400, 800), skin: 'comic');
    await tester.pumpAndSettle();
    final comic = decoration(block)!;
    expect((comic.border! as Border).top.width, 2);
    expect(comic.boxShadow, anyOf(isNull, isEmpty));
    final ctx = tester.element(c2Key(block));
    expect(PlannerSkin.of(ctx).comic, isNotNull);
    await c2Tap(tester, c2Key(block));
    expect((decoration(block)!.border! as Border).top.width, 3);
    expect(
      (tester.widget<DecoratedBox>(c2Key('schedule-detail')).decoration
              as BoxDecoration)
          .border,
      isNotNull,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    // Neumorphic: shadow pair, no outline.
    await c2Pump(tester, store, size: const Size(400, 800), skin: 'neu');
    await tester.pumpAndSettle();
    final neu = decoration(block)!;
    expect(neu.boxShadow, hasLength(2));
    expect(neu.border, isNull);
    await c2Tap(tester, c2Key(block));
    expect(
      (tester.widget<DecoratedBox>(c2Key('schedule-detail')).decoration
              as BoxDecoration)
          .boxShadow,
      hasLength(2),
    );
    await c2Finish(tester, store);
  });

  testWidgets('today button and tab switch follow the skin', (tester) async {
    final store = await c2Store(items: []);
    await c2Pump(tester, store, size: const Size(400, 800), skin: 'comic');
    await tester.pumpAndSettle();
    final today = find.descendant(
      of: c2Key('schedule-today'),
      matching: find.byType(DecoratedBox),
    );
    final decorations = [
      for (final e in today.evaluate()) (e.widget as DecoratedBox).decoration,
    ].whereType<BoxDecoration>();
    expect(
      decorations.any((d) => d.shape == BoxShape.circle && d.border != null),
      isTrue,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await c2Pump(tester, store, size: const Size(400, 800), skin: 'neu');
    await tester.pumpAndSettle();
    final neu = [
      for (final e
          in find
              .descendant(
                of: c2Key('schedule-today'),
                matching: find.byType(DecoratedBox),
              )
              .evaluate())
        (e.widget as DecoratedBox).decoration,
    ].whereType<BoxDecoration>();
    expect(neu.any((d) => d.boxShadow?.length == 2), isTrue);
    await c2Finish(tester, store);
  });
}
