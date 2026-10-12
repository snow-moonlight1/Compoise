import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/screens/matrix_screen.dart';
import 'package:matrixflow_native/storage.dart';
import 'package:matrixflow_native/theme.dart';
import 'package:matrixflow_native/widgets/input_sheet.dart';
import 'package:matrixflow_native/widgets/task_card.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'wp15_c2_test_support.dart';

ThemeData _theme(String skin) {
  final base = ThemeData(useMaterial3: true);
  return switch (skin) {
    'comic' => applyComicOutline(base),
    'neu' => applyNeumorphic(base),
    _ => base,
  };
}

Future<Store> _store() async {
  SharedPreferences.setMockInitialValues({
    'matrixflow-has-seen-onboarding': true,
    'matrixflow-boards': jsonEncode([
      Board(id: 'b', name: 'Synthetic board', createdAt: 1).toJson(),
    ]),
    'matrixflow-tasks': jsonEncode([
      for (var i = 0; i < 3; i++)
        Task(
          id: 'T$i',
          boardId: 'b',
          title: 'Task $i',
          quadrant: 1,
          createdAt: i + 1,
          urgencyMode: UrgencyMode.manual,
        ).toJson(),
    ]),
  });
  final store = Store();
  await store.init();
  return store;
}

Future<void> _done(WidgetTester tester, Store store) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.runAsync(() => store.flush(waitForReminders: false));
  store.dispose();
  await tester.pump();
}

Widget _app(Store store, String skin, Widget home) =>
    ChangeNotifierProvider.value(
      value: store,
      child: MaterialApp(
        theme: _theme(skin),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('en'), Locale('zh'), Locale('ja')],
        home: home,
      ),
    );

List<BoxDecoration> _decorations(Finder inside) => [
  for (final e
      in find
          .descendant(of: inside, matching: find.byType(DecoratedBox))
          .evaluate())
    if ((e.widget as DecoratedBox).decoration is BoxDecoration)
      (e.widget as DecoratedBox).decoration as BoxDecoration,
];

void main() {
  testWidgets('neumorphic pool cards are separate raised cards, text whole', (
    tester,
  ) async {
    final store = await c2Store();
    await c2Pump(tester, store, size: const Size(400, 800), skin: 'neu');
    await tester.tap(find.textContaining('Task pool'));
    await tester.pumpAndSettle();
    await tester.tap(c2Key('schedule-pool-tab-2'));
    await tester.pumpAndSettle();
    final card = c2Key('schedule-pool-outline');
    expect(
      _decorations(card).any((d) => d.boxShadow?.length == 2),
      isTrue,
      reason: 'raised, not sunk',
    );
    final rect = tester.getRect(
      find.descendant(of: card, matching: find.byType(DecoratedBox)).first,
    );
    // Margin keeps the shadow away from the screen edge and its neighbours.
    expect(rect.left, greaterThanOrEqualTo(16));
    expect(rect.right, lessThanOrEqualTo(400 - 16));
    final text = tester.getRect(
      find.descendant(of: card, matching: find.text('Draft outline')),
    );
    expect(
      rect.contains(text.topLeft) && rect.contains(text.bottomRight),
      isTrue,
    );
    // The Add button is whole: its label sits inside the button.
    final add = tester.getRect(c2Key('schedule-add'));
    final label = tester.getRect(
      find.descendant(of: c2Key('schedule-add'), matching: find.text('Add')),
    );
    expect(
      add.contains(label.topLeft) && add.contains(label.bottomRight),
      isTrue,
    );
    expect(add.height, greaterThanOrEqualTo(label.height));
    await c2Finish(tester, store);
  });

  testWidgets('comic pool cards keep both side borders inside the screen', (
    tester,
  ) async {
    final store = await c2Store();
    await c2Pump(tester, store, size: const Size(400, 800), skin: 'comic');
    await tester.tap(find.textContaining('Task pool'));
    await tester.pumpAndSettle();
    await tester.tap(c2Key('schedule-pool-tab-2'));
    await tester.pumpAndSettle();
    final rect = tester.getRect(
      find
          .descendant(
            of: c2Key('schedule-pool-outline'),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    expect(rect.left, greaterThanOrEqualTo(12));
    expect(rect.right, lessThanOrEqualTo(400 - 12));
    expect(
      _decorations(c2Key('schedule-pool-outline')).any((d) => d.border != null),
      isTrue,
    );
    await c2Finish(tester, store);
  });

  testWidgets('neumorphic title field keeps its text centred', (tester) async {
    final store = await c2Store(
      items: [c1Event('x', c1At(30, 1), c1At(30, 3))],
    );
    await c2Pump(tester, store, size: const Size(400, 800), skin: 'neu');
    await c2Tap(tester, c2Key('schedule-item-2026-09-30-x'));
    await c2Tap(tester, c2Key('schedule-detail-edit'));
    final field = c2Key('schedule-editor-title');
    final input = tester.widget<TextField>(
      find.descendant(of: field, matching: find.byType(TextField)),
    );
    expect(input.textAlignVertical, TextAlignVertical.center);
    final padding = input.decoration!.contentPadding! as EdgeInsets;
    expect(padding.top, padding.bottom);
    await tester.enterText(
      find.descendant(of: field, matching: find.byType(TextField)),
      '',
    );
    await tester.pump();
    final hint = find.descendant(of: field, matching: find.byType(Text));
    if (hint.evaluate().isNotEmpty) {
      expect(
        tester.getCenter(hint.first).dy,
        closeTo(tester.getCenter(field).dy, 4),
      );
    }
    await c2Finish(tester, store);
  });

  for (final skin in ['default', 'comic', 'neu']) {
    testWidgets('add panel in $skin: short batch label, spaced hint, low box', (
      tester,
    ) async {
      final store = await _store();
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _app(
          store,
          skin,
          const Scaffold(
            body: InputSheet(initialMode: InputModePref.single, embedded: true),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Batch add'), findsOneWidget);
      expect(find.text('Batch independent tasks'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('batch-mode')));
      await tester.pumpAndSettle();
      final hint = tester.getRect(
        find.text('Each non-empty line becomes a separate task.'),
      );
      final box = tester.getRect(find.byKey(const ValueKey('task-input')));
      expect(box.top - hint.bottom, greaterThanOrEqualTo(8));
      expect(box.height, lessThanOrEqualTo(110));
      expect(tester.takeException(), isNull);
      await _done(tester, store);
    });
  }

  testWidgets('neumorphic mode switch: both selected tabs look the same', (
    tester,
  ) async {
    final store = await _store();
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app(store, 'neu', const MatrixHome()));
    await tester.pumpAndSettle();
    List<BoxShadow> shadows() => [
      for (final d in _decorations(
        find.byKey(const ValueKey('home-tab-tasks')),
      ))
        ...?d.boxShadow,
      for (final d in _decorations(find.byKey(const ValueKey('schedule-btn'))))
        ...?d.boxShadow,
    ];
    final first = shadows();
    expect(first, hasLength(1));
    // Left-right symmetric: no horizontal offset, so no lopsided edge.
    expect(first.single.offset.dx, 0);
    await tester.tap(find.byKey(const ValueKey('schedule-btn')));
    await tester.pumpAndSettle();
    final second = shadows();
    expect(second, hasLength(1));
    expect(second.single.offset, first.single.offset);
    expect(second.single.blurRadius, first.single.blurRadius);
    await _done(tester, store);
  });

  testWidgets(
    'home task rows: comic is inset with a line, neu cards are close',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var store = await _store();
      await tester.pumpWidget(_app(store, 'comic', const MatrixHome()));
      await tester.pumpAndSettle();
      final cards = find.byType(TaskCard);
      expect(cards, findsWidgets);
      expect(
        tester
            .getRect(
              find.descendant(of: cards.first, matching: find.text('Task 0')),
            )
            .left,
        greaterThanOrEqualTo(24),
      );
      await _done(tester, store);

      store = await _store();
      await tester.pumpWidget(_app(store, 'neu', const MatrixHome()));
      await tester.pumpAndSettle();
      final a = tester.getRect(find.byType(TaskCard).at(0));
      final b = tester.getRect(find.byType(TaskCard).at(1));
      // Faces are 10dp apart (was 32).
      expect((b.top - a.bottom).abs(), lessThanOrEqualTo(12));
      await _done(tester, store);
    },
  );
}
