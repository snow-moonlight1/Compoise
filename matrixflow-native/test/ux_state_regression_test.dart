import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/screens/matrix_screen.dart';
import 'package:matrixflow_native/storage.dart';
import 'package:matrixflow_native/widgets/quadrant_pane.dart';
import 'package:matrixflow_native/widgets/quadrant_transition_layout.dart';
import 'package:matrixflow_native/widgets/task_exit.dart';
import 'package:matrixflow_native/widgets/task_list_view.dart';
import 'package:provider/provider.dart';

import 'helpers.dart';

/// Regression for the 2026-09-19 state-crossing counterexamples (R1–R5).
/// Promoted from `test/review/ux_state_review_probe.dart`.
void main() {
  Future<Store> setup(
    WidgetTester tester, {
    bool desktop = false,
    bool list = true,
  }) async {
    await tester.binding.setSurfaceSize(
      desktop ? const Size(1280, 900) : const Size(390, 844),
    );
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final (store, _) = await makeStore(
      settings: AppSettings()..viewMode = list ? ViewMode.list : ViewMode.grid,
    );
    store.addTasks([store.newTask('Review task', quadrant: qDo)]);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: store,
        child: MaterialApp(
          theme: ThemeData(
            platform: desktop ? TargetPlatform.windows : TargetPlatform.android,
          ),
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          supportedLocales: const [Locale('en'), Locale('zh'), Locale('ja')],
          home: const MatrixHome(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return store;
  }

  Future<void> finish(WidgetTester tester, Store store) async {
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  }

  Future<void> startExit(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('list-quadrant-header-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('focus-back-btn')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('R1: selecting a quadrant during list exit restores opacity', (
    tester,
  ) async {
    final store = await setup(tester);
    await startExit(tester);
    await tester.tap(find.byKey(const ValueKey('focus-card-2')));
    await tester.pumpAndSettle();
    final fade = tester.widget<FadeTransition>(
      find
          .descendant(
            of: find.byType(QuadrantTransitionLayout),
            matching: find.byType(FadeTransition),
          )
          .first,
    );
    expect(
      fade.opacity.value,
      1,
      reason: 'A new focus target must cancel the outgoing fade',
    );
    await finish(tester, store);
  });

  testWidgets(
    'R2: opening desktop detail during list exit still completes exit',
    (tester) async {
      final store = await setup(tester, desktop: true);
      await startExit(tester);
      await tester.tap(find.text('Review task'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('edit-title')), findsOneWidget);
      expect(
        find.byType(TaskListView),
        findsOneWidget,
        reason: 'Reparenting the transition for the sidebar must not lose exit completion',
      );
      await finish(tester, store);
    },
  );

  testWidgets('R3: entering Q2 preserves a pending completion snapshot', (
    tester,
  ) async {
    final store = await setup(tester, list: false);
    store.updateSettings((s) => s..hideCompleted = true);
    await tester.pumpAndSettle();
    final q1State = tester.state<State<QuadrantPane>>(
      find.byKey(const ValueKey('q-pane-1')),
    );
    await tester.tap(find.byKey(ValueKey('complete-${store.tasks.single.id}')));
    await tester.pump();
    expect(find.text('Review task'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('quadrant-header-2')));
    await tester.pump();
    expect(
      find.text('Review task'),
      findsOneWidget,
      reason: 'At transition frame zero the completion snapshot must still be visible',
    );
    expect(
      identical(
        q1State,
        tester.state<State<QuadrantPane>>(
          find.byKey(const ValueKey('q-pane-1')),
        ),
      ),
      isTrue,
      reason: 'Q1 pane State must survive the Stack reorder when Q2 is focused',
    );
    await finish(tester, store);
  });

  testWidgets('R5: reduced-motion list exit does not setState during build', (
    tester,
  ) async {
    final store = await setup(tester);
    store.updateSettings((s) => s..reduceMotion = true);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('list-quadrant-header-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('focus-back-btn')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(TaskListView), findsOneWidget);
    await finish(tester, store);
  });

  test('R4: exit retention follows reordered live tasks', () {
    final cache = ExitRetention<String>(onChange: () {});
    addTearDown(cache.dispose);
    List<String> sync(List<String> items) => cache
        .sync(
          items: items,
          epochKey: 'same-board',
          idOf: (item) => item,
          keepIfMissing: (_) => false,
          reduceMotion: false,
        )
        .map((entry) => entry.item)
        .toList();
    expect(sync(['A', 'B']), ['A', 'B']);
    expect(
      sync(['B', 'A']),
      ['B', 'A'],
      reason: 'Live ordering must not be frozen by animation retention',
    );
  });

  Future<void> toggleViewByKeyboard(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
  }

  testWidgets(
    'S1: toggling view twice during list exit still returns to the list',
    (tester) async {
      final store = await setup(tester, desktop: true);
      await startExit(tester);
      await toggleViewByKeyboard(tester);
      expect(store.settings.viewMode, ViewMode.grid);
      await tester.pump(const Duration(milliseconds: 30));
      await toggleViewByKeyboard(tester);
      expect(store.settings.viewMode, ViewMode.list);
      await tester.pumpAndSettle();
      expect(
        find.byType(TaskListView),
        findsOneWidget,
        reason: 'Switching modes must not stop the only exit completion signal',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(TaskListView), findsOneWidget);
      expect(tester.takeException(), isNull);
      await finish(tester, store);
    },
  );

  test('R4: exiting snapshots stay at last index while live rows reorder', () {
    final cache = ExitRetention<String>(onChange: () {});
    addTearDown(cache.dispose);
    List<ExitEntry<String>> sync(List<String> items) => cache.sync(
      items: items,
      epochKey: 'same-board',
      idOf: (item) => item,
      keepIfMissing: (_) => true,
      reduceMotion: false,
    );
    expect(sync(['A', 'B', 'C']).map((e) => e.item), ['A', 'B', 'C']);
    final withExit = sync(['A', 'C']);
    expect(withExit.map((e) => e.item).toList(), ['A', 'B', 'C']);
    expect(withExit.map((e) => e.exiting).toList(), [false, true, false]);
    final reordered = sync(['C', 'A']);
    expect(reordered.map((e) => e.item).toList(), ['C', 'B', 'A']);
    expect(reordered.map((e) => e.exiting).toList(), [false, true, false]);
  });
}
