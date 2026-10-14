import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:compoise/models.dart';
import 'package:compoise/screens/matrix_screen.dart';
import 'package:compoise/storage.dart';
import 'package:compoise/theme.dart';
import 'package:compoise/widgets/multi_drag_stack.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'widget_regression_test.dart' show setup, viewport, enterSelectMode;

enum _Skin { material, comic, neumorphic }

Widget _app(Store store, TargetPlatform platform, _Skin skin) =>
    ChangeNotifierProvider.value(
      value: store,
      child: MaterialApp(
        theme: buildTheme(
          Brightness.light,
          store.settings.themeColor,
          platform: platform,
          comicOutline: skin == _Skin.comic,
          neumorphic: skin == _Skin.neumorphic,
        ),
        locale: Locale(store.settings.language.name),
        supportedLocales: const [Locale('en'), Locale('zh'), Locale('ja')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: const MatrixHome(),
      ),
    );

void main() {
  for (final skin in _Skin.values) {
    for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
      final touch = platform == TargetPlatform.android;
      testWidgets(
        'multi-select ${touch ? 'long-press' : 'mouse'} drag moves the '
        'selected stack (${skin.name})',
        (tester) async {
          viewport(
            tester,
            touch ? const Size(390, 844) : const Size(1280, 800),
          );
          final store = await setup(tester);
          final a = store.newTask('stack alpha');
          final b = store.newTask('stack beta', quadrant: qPlan);
          final c = store.newTask('stay put');
          store.addTasks([a, b, c]);
          await tester.pumpWidget(_app(store, platform, skin));
          await tester.pumpAndSettle();
          await enterSelectMode(tester);
          if (touch) {
            expect(find.byKey(const ValueKey('more-btn')), findsNothing);
          }
          await tester.tap(find.text('stack alpha'));
          await tester.pumpAndSettle();
          if (touch) {
            expect(find.byTooltip(store.t['editTask']!), findsNothing);
            expect(find.text(store.t['editTask']!), findsNothing);
          }
          await tester.tap(find.text('stack beta'));
          await tester.pumpAndSettle();
          // The bar no longer offers move or group.
          expect(find.byKey(const ValueKey('batch-move-btn')), findsNothing);
          expect(find.textContaining('Group'), findsNothing);

          final start = tester.getCenter(find.text('stack alpha'));
          final target = tester.getCenter(
            find.byKey(const ValueKey('q-pane-3')),
          );
          final TestGesture gesture;
          if (touch) {
            gesture = await tester.startGesture(start);
            await tester.pump(
              kLongPressTimeout + const Duration(milliseconds: 50),
            );
          } else {
            gesture = await tester.startGesture(
              start,
              kind: PointerDeviceKind.mouse,
            );
          }
          for (var i = 1; i <= 10; i++) {
            await gesture.moveTo(Offset.lerp(start, target, i / 10)!);
            await tester.pump(const Duration(milliseconds: 16));
          }
          expect(find.byType(MultiDragStack), findsOneWidget);
          expect(
            find.descendant(
              of: find.byKey(const ValueKey('multi-drag-count')),
              matching: find.text('2'),
            ),
            findsOneWidget,
          );
          expect(multiDragActive.value, isTrue);
          await gesture.up();
          await tester.pumpAndSettle();

          final byTitle = {for (final t in store.tasks) t.title: t.quadrant};
          expect(byTitle['stack alpha'], qDelegate);
          expect(byTitle['stack beta'], qDelegate);
          expect(byTitle['stay put'], isNot(qDelegate));
          expect(multiDragActive.value, isFalse);
          // Dropping ends multi-select.
          expect(
            find.byKey(const ValueKey('exit-selection-btn')),
            findsNothing,
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }

  testWidgets('unselected cards cannot be dragged while selecting', (
    tester,
  ) async {
    viewport(tester, const Size(390, 844));
    final store = await setup(tester);
    final a = store.newTask('picked');
    final b = store.newTask('not picked');
    store.addTasks([a, b]);
    await tester.pumpWidget(
      _app(store, TargetPlatform.android, _Skin.neumorphic),
    );
    await tester.pumpAndSettle();
    await enterSelectMode(tester);
    await tester.tap(find.text('picked'));
    await tester.pumpAndSettle();
    final start = tester.getCenter(find.text('not picked'));
    final gesture = await tester.startGesture(start);
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await gesture.moveTo(
      tester.getCenter(find.byKey(const ValueKey('q-pane-3'))),
    );
    await tester.pump();
    expect(find.byType(MultiDragStack), findsNothing);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(store.tasks.every((t) => t.quadrant == qDo), isTrue);
    await tester.pumpWidget(const SizedBox());
  });
}
