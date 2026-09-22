import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/screens/matrix_screen.dart';
import 'package:matrixflow_native/storage.dart';
import 'package:matrixflow_native/widgets/quadrant_transition_layout.dart';
import 'package:matrixflow_native/widgets/task_exit.dart';
import 'package:matrixflow_native/widgets/task_list_view.dart';
import 'package:provider/provider.dart';

import '../helpers.dart';

void main() {
  Future<Store> setup(WidgetTester tester, {bool list = true}) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final (store, _) = await makeStore(
      settings: AppSettings()..viewMode = list ? ViewMode.list : ViewMode.grid,
    );
    store.addTasks([store.newTask('Review task', quadrant: qDo)]);
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: store,
      child: MaterialApp(
        theme: ThemeData(platform: TargetPlatform.windows),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('en'), Locale('zh'), Locale('ja')],
        home: const MatrixHome(),
      ),
    ));
    await tester.pumpAndSettle();
    return store;
  }

  Future<void> finish(WidgetTester tester, Store store) async {
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  }

  Future<void> enter(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('list-quadrant-header-1')));
    await tester.pumpAndSettle();
  }

  Future<void> startExit(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('focus-back-btn')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
  }

  Future<void> toggleByKeyboard(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
  }

  testWidgets('S1: two view shortcuts during exit still return to list', (tester) async {
    final store = await setup(tester);
    await enter(tester);
    await startExit(tester);
    await toggleByKeyboard(tester);
    expect(store.settings.viewMode, ViewMode.grid);
    await tester.pump(const Duration(milliseconds: 30));
    await toggleByKeyboard(tester);
    expect(store.settings.viewMode, ViewMode.list);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    final returnedToList = find.byType(TaskListView).evaluate().length == 1;
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    final escapeReturnedToList = find.byType(TaskListView).evaluate().length == 1;
    // Keep checking both navigation paths after automatic list recovery.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    final systemBackRecovered = find.byType(TaskListView).evaluate().length == 1;
    await finish(tester, store);
    expect(systemBackRecovered, isTrue);
    expect(escapeReturnedToList, isTrue,
        reason: 'Windows Escape must not leave an exit with no running animation');
    expect(returnedToList, isTrue,
        reason: 'Switching modes must not stop the only exit completion signal');
    expect(tester.takeException(), isNull);
  });

  testWidgets('S2: 20 exit-refocus-exit cycles settle without stale callbacks', (tester) async {
    final store = await setup(tester);
    for (var i = 0; i < 20; i++) {
      await enter(tester);
      await startExit(tester);
      await tester.tap(find.byKey(ValueKey('focus-card-${2 + i % 3}')));
      await tester.pump();
      await tester.pump(Duration(milliseconds: 5 + i * 3));
      await tester.tap(find.byKey(const ValueKey('focus-back-btn')));
      await tester.pumpAndSettle();
      expect(find.byType(TaskListView), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    await finish(tester, store);
  });

  testWidgets('S3: backing out before the first fade tick returns to list', (tester) async {
    final store = await setup(tester);
    await tester.tap(find.byKey(const ValueKey('list-quadrant-header-1')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('focus-back-btn')));
    await tester.pumpAndSettle();
    expect(find.byType(TaskListView), findsOneWidget);
    expect(tester.takeException(), isNull);
    await finish(tester, store);
  });

  testWidgets('S4: system back twice during exit releases the transition', (tester) async {
    final store = await setup(tester);
    await enter(tester);
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(TaskListView), findsOneWidget);
    expect(tester.takeException(), isNull);
    await finish(tester, store);
  });

  testWidgets('S5: recreated exiting layout reports completion exactly once', (tester) async {
    final (store, _) = await makeStore();
    var done = 0;
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: store,
      child: MaterialApp(home: Scaffold(body: QuadrantTransitionLayout(
        focusedQuadrant: qDo,
        viewMode: ViewMode.list,
        fadeOutOnly: true,
        onFocusQuadrant: (_) {},
        onExitFocus: () {},
        onFadeOutDone: () => done++,
      ))),
    ));
    await tester.pumpAndSettle();
    expect(done, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('S6: exit cache undo cancels timer and honors new order', (tester) async {
    var ticks = 0;
    final cache = ExitRetention<String>(onChange: () => ticks++);
    List<ExitEntry<String>> sync(List<String> items, {String epoch = 'a'}) => cache.sync(
      items: items, epochKey: epoch, idOf: (s) => s,
      keepIfMissing: (_) => true, reduceMotion: false,
    );
    sync(['A', 'B', 'C']);
    sync(['C', 'A']);
    await tester.pump(const Duration(milliseconds: 100));
    expect(sync(['B', 'C', 'A']).map((e) => e.item), ['B', 'C', 'A']);
    await tester.pump(const Duration(milliseconds: 400));
    expect(ticks, 0);
    sync(['C']);
    expect(sync(['D'], epoch: 'b').map((e) => e.item), ['D']);
    await tester.pump(const Duration(milliseconds: 400));
    expect(ticks, 0);
    cache.dispose();
  });

  testWidgets('S7: detail resize removes and recreates an exiting layout safely', (tester) async {
    final store = await setup(tester);
    await enter(tester);
    await startExit(tester);
    await tester.tap(find.text('Review task'));
    await tester.pump();
    await tester.binding.setSurfaceSize(const Size(600, 900));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('edit-title')), findsOneWidget);
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    await tester.pumpAndSettle();
    expect(find.byType(TaskListView), findsOneWidget);
    expect(tester.takeException(), isNull);
    await finish(tester, store);
  });

  testWidgets('S8: Escape immediately finishes an active exit, then focus works again', (tester) async {
    final store = await setup(tester);
    await enter(tester);
    await startExit(tester);
    expect(find.byType(TaskListView), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byType(TaskListView), findsOneWidget);
    await tester.pumpAndSettle();
    await enter(tester);
    await startExit(tester);
    await tester.pumpAndSettle();
    expect(find.byType(TaskListView), findsOneWidget);
    expect(tester.takeException(), isNull);
    await finish(tester, store);
  });

  testWidgets('S9: mode change during component fade reports completion once', (tester) async {
    final (store, _) = await makeStore();
    var mode = ViewMode.list;
    var exiting = false;
    var done = 0;
    late StateSetter update;
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: store,
      child: MaterialApp(home: Scaffold(body: StatefulBuilder(
        builder: (context, setState) {
          update = setState;
          return QuadrantTransitionLayout(
            focusedQuadrant: qDo, viewMode: mode, fadeOutOnly: exiting,
            onFocusQuadrant: (_) {}, onExitFocus: () {},
            onFadeOutDone: () => done++,
          );
        },
      ))),
    ));
    await tester.pumpAndSettle();
    update(() => exiting = true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    update(() => mode = ViewMode.grid);
    await tester.pumpAndSettle();
    expect(done, 1);
    update(() { mode = ViewMode.list; exiting = false; });
    await tester.pumpAndSettle();
    expect(done, 1, reason: 'Old completion must not fire into the next focus session');
    final fade = tester.widget<FadeTransition>(find.descendant(
      of: find.byType(QuadrantTransitionLayout), matching: find.byType(FadeTransition),
    ).first);
    expect(fade.opacity.value, 1);
    update(() => exiting = true);
    await tester.pumpAndSettle();
    expect(done, 2);
    expect(tester.takeException(), isNull);
    await finish(tester, store);
  });
}
