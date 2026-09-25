import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/screens/matrix_screen.dart';
import 'package:matrixflow_native/storage.dart';
import 'package:matrixflow_native/widgets/task_list_view.dart';
import 'package:provider/provider.dart';

import 'helpers.dart';

Widget wrapApp(Store store, {Size size = const Size(390, 844)}) {
  return ChangeNotifierProvider.value(
    value: store,
    child: MaterialApp(
      theme: ThemeData(useMaterial3: true, platform: TargetPlatform.android),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('en'), Locale('zh'), Locale('ja')],
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: const MatrixHome(),
      ),
    ),
  );
}

void main() {
  Future<Store> pumpMatrix(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    AppSettings? settings,
    required List<Task> Function(Store store) seed,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final (store, _) = await makeStore(settings: settings);
    store.addTasks(seed(store));
    await tester.pumpWidget(wrapApp(store, size: size));
    await tester.pumpAndSettle();
    return store;
  }

  Rect paneRect(WidgetTester tester, int q) =>
      tester.getRect(find.byKey(ValueKey('q-pane-$q')));

  Finder focusMarker() => find.byKey(const ValueKey('focus-view-active'));

  testWidgets('UX07: entering Q2 grows from its own matrix cell', (
    tester,
  ) async {
    final store = await pumpMatrix(
      tester,
      seed:
          (store) => [
            store.newTask('A', quadrant: qDo),
            store.newTask('B', quadrant: qPlan),
          ],
    );
    final initial = paneRect(tester, qPlan);
    await tester.tap(find.byKey(const ValueKey('quadrant-header-2')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 96)); // ~30% of 320ms
    final mid = paneRect(tester, qPlan);
    // Top-right cell grows leftwards into the main area, continuously.
    expect(mid.left, lessThan(initial.left));
    expect(mid.width, greaterThan(initial.width));
    expect(mid.left, greaterThan(0)); // still mid-flight, not teleported
    await tester.pumpAndSettle();
    final end = paneRect(tester, qPlan);
    // Content area has a 4dp outer padding.
    expect(end.left, lessThanOrEqualTo(5));
    expect(end.width, greaterThan(mid.width));
    expect(find.byKey(const ValueKey('focus-card-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('focus-card-3')), findsOneWidget);
    expect(find.byKey(const ValueKey('focus-card-4')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('UX07: exiting returns every quadrant to its matrix cell', (
    tester,
  ) async {
    final store = await pumpMatrix(
      tester,
      seed: (store) => [store.newTask('B', quadrant: qPlan)],
    );
    final initial = paneRect(tester, qPlan);
    await tester.tap(find.byKey(const ValueKey('quadrant-header-2')));
    await tester.pumpAndSettle();
    final focused = paneRect(tester, qPlan);
    await tester.tap(find.byKey(const ValueKey('focus-back-btn')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 84)); // ~30% of 280ms
    final mid = paneRect(tester, qPlan);
    expect(mid.left, greaterThan(focused.left));
    expect(mid.width, lessThan(focused.width));
    expect(mid.left, lessThan(initial.left));
    await tester.pumpAndSettle();
    final settled = paneRect(tester, qPlan);
    expect(settled.left, closeTo(initial.left, 1));
    expect(settled.top, closeTo(initial.top, 1));
    expect(settled.width, closeTo(initial.width, 1));
    expect(settled.height, closeTo(initial.height, 1));
    expect(focusMarker(), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('UX07: backing out at 30% still lands exactly on the matrix', (
    tester,
  ) async {
    final store = await pumpMatrix(
      tester,
      seed: (store) => [store.newTask('A', quadrant: qDo)],
    );
    final initial = paneRect(tester, qDo);
    await tester.tap(find.byKey(const ValueKey('quadrant-header-1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 96));
    // Reverse mid-animation: geometry must redirect, not restart.
    await tester.tap(find.byKey(const ValueKey('focus-back-btn')));
    await tester.pumpAndSettle();
    final settled = paneRect(tester, qDo);
    expect(settled.left, closeTo(initial.left, 1));
    expect(settled.width, closeTo(initial.width, 1));
    expect(settled.top, closeTo(initial.top, 1));
    expect(settled.height, closeTo(initial.height, 1));
    expect(focusMarker(), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('UX07: switching focus moves both panes continuously', (
    tester,
  ) async {
    final store = await pumpMatrix(
      tester,
      seed:
          (store) => [
            store.newTask('A', quadrant: qDo),
            store.newTask('C', quadrant: qDelegate),
          ],
    );
    await tester.tap(find.byKey(const ValueKey('quadrant-header-1')));
    await tester.pumpAndSettle();
    // Collapsed quadrants render as cards; the card shares the region rect.
    final cardQ3 = tester.getRect(find.byKey(const ValueKey('focus-card-3')));
    final mainQ1 = paneRect(tester, qDo);
    await tester.tap(find.byKey(const ValueKey('focus-card-3')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90)); // ~30% of 300ms
    final midQ3 = paneRect(tester, qDelegate);
    final midQ1 = paneRect(tester, qDo);
    // Q3 is growing from its card slot, Q1 is shrinking toward a card.
    expect(midQ3.width, greaterThan(cardQ3.width));
    expect(midQ3.width, lessThan(mainQ1.width));
    expect(midQ1.width, lessThan(mainQ1.width));
    await tester.pumpAndSettle();
    final endQ3 = paneRect(tester, qDelegate);
    expect(endQ3.left, lessThanOrEqualTo(5));
    expect(find.byKey(const ValueKey('focus-card-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('focus-card-3')), findsNothing);
    expect(find.text('C'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('UX07: reduce motion jumps to the focused layout', (
    tester,
  ) async {
    final store = await pumpMatrix(
      tester,
      settings: AppSettings()..reduceMotion = true,
      seed: (store) => [store.newTask('B', quadrant: qPlan)],
    );
    await tester.tap(find.byKey(const ValueKey('quadrant-header-2')));
    await tester.pump();
    final end = paneRect(tester, qPlan);
    expect(end.left, lessThanOrEqualTo(5));
    expect(focusMarker(), findsOneWidget);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('UX07: 100 interrupted enter/exit cycles leak nothing', (
    tester,
  ) async {
    final store = await pumpMatrix(
      tester,
      seed: (store) => [store.newTask('A', quadrant: qDo)],
    );
    for (var i = 0; i < 100; i++) {
      await tester.tap(find.byKey(const ValueKey('quadrant-header-1')));
      await tester.pump(const Duration(milliseconds: 120));
      await tester.pump(const Duration(milliseconds: 120)); // entry ~37% in
      await tester.tap(find.byKey(const ValueKey('focus-back-btn')));
      await tester.pumpAndSettle(); // interrupted exit redirected to the end
    }
    await tester.pumpAndSettle();
    expect(focusMarker(), findsNothing);
    expect(tester.takeException(), isNull);
    final settled = paneRect(tester, qDo);
    expect(settled.left, lessThanOrEqualTo(5));
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('UX07: scroll offset survives a focus round trip', (
    tester,
  ) async {
    final store = await pumpMatrix(
      tester,
      size: const Size(390, 640),
      seed:
          (store) => [
            for (var i = 0; i < 20; i++)
              store.newTask('Task $i', quadrant: qDo),
          ],
    );
    ScrollPosition position() =>
        tester
            .state<ScrollableState>(
              find.descendant(
                of: find.byKey(const ValueKey('q-pane-1')),
                matching: find.byType(Scrollable),
              ),
            )
            .position;
    await tester.drag(
      find.byKey(const ValueKey('q-pane-1')),
      const Offset(0, -160),
    );
    await tester.pumpAndSettle();
    final before = position().pixels;
    expect(before, greaterThan(0));

    await tester.tap(find.byKey(const ValueKey('quadrant-header-1')));
    await tester.pumpAndSettle();
    expect(position().pixels, closeTo(before, 2));

    await tester.tap(find.byKey(const ValueKey('focus-back-btn')));
    await tester.pumpAndSettle();
    expect(position().pixels, closeTo(before, 2));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('UX07: task rows are inert during the transition only', (
    tester,
  ) async {
    final store = await pumpMatrix(
      tester,
      seed: (store) => [store.newTask('Task A', quadrant: qDo)],
    );
    await tester.tap(find.byKey(const ValueKey('quadrant-header-1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 96));
    await tester.tap(find.text('Task A'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('edit-title')), findsNothing);

    await tester.tap(find.text('Task A'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('edit-title')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('UX07: list mode enters with the overlay and returns to list', (
    tester,
  ) async {
    final store = await pumpMatrix(
      tester,
      settings: AppSettings()..viewMode = ViewMode.list,
      seed:
          (store) => [
            for (var i = 0; i < 20; i++)
              store.newTask('Task $i', quadrant: qDo),
          ],
    );
    expect(find.byType(TaskListView), findsOneWidget);
    // The list is one scrollable. Quadrant sections are slivers inside it.
    ScrollPosition position() =>
        tester
            .stateList<ScrollableState>(
              find.descendant(
                of: find.byType(TaskListView),
                matching: find.byType(Scrollable),
              ),
            )
            .first
            .position;
    // Scroll down so the last section header is reachable, then focus it.
    await tester.drag(find.byType(TaskListView), const Offset(0, -800));
    await tester.pumpAndSettle();
    final before = position().pixels;
    expect(before, greaterThan(0));

    await tester.tap(find.byKey(const ValueKey('list-quadrant-header-3')));
    await tester.pumpAndSettle();
    expect(focusMarker(), findsOneWidget);
    expect(find.byType(TaskListView), findsNothing);

    await tester.tap(find.byKey(const ValueKey('focus-back-btn')));
    await tester.pumpAndSettle();
    // Back in list mode with the original scroll position, not the matrix.
    expect(find.byType(TaskListView), findsOneWidget);
    expect(focusMarker(), findsNothing);
    expect(position().pixels, closeTo(before, 2));
    expect(tester.takeException(), isNull);
    // Rows built by the restored scroll offset queue a one-shot entrance
    // delay. Flush it before the binding checks for pending timers.
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('UX07: view mode switch while focused exits focus first', (
    tester,
  ) async {
    final store = await pumpMatrix(
      tester,
      seed: (store) => [store.newTask('A', quadrant: qDo)],
    );
    await tester.tap(find.byKey(const ValueKey('quadrant-header-1')));
    await tester.pumpAndSettle();
    expect(focusMarker(), findsOneWidget);

    store.toggleViewMode();
    await tester.pumpAndSettle();
    expect(focusMarker(), findsNothing);
    expect(find.byType(TaskListView), findsOneWidget);
    expect(find.byKey(const ValueKey('focus-back-btn')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });
}
