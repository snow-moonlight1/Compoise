import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/screens/completed_screen.dart';
import 'package:matrixflow_native/screens/search_screen.dart';
import 'package:matrixflow_native/storage.dart';
import 'package:matrixflow_native/task_filter.dart';
import 'package:matrixflow_native/task_query.dart';
import 'package:provider/provider.dart';

import 'helpers.dart';

Widget wrapPlatform(Store store, Widget home, TargetPlatform platform) {
  return ChangeNotifierProvider.value(
    value: store,
    child: MaterialApp(
      theme: ThemeData(useMaterial3: true, platform: platform),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('en'), Locale('zh'), Locale('ja')],
      home: home,
    ),
  );
}

void expectNoHorizontalFilterTrack(WidgetTester tester) {
  expect(
    find.byWidgetPredicate(
      (widget) =>
          widget is SingleChildScrollView &&
          widget.scrollDirection == Axis.horizontal,
    ),
    findsNothing,
  );
}

void main() {
  Future<void> pumpSearch(
    WidgetTester tester,
    Store store, {
    required TargetPlatform platform,
    Size size = const Size(390, 844),
    double textScale = 1,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(textScale),
        ),
        child: wrapPlatform(
          store,
          SearchScreen(initialBoardId: store.activeBoardId),
          platform,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openFilter(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('filter-open-btn')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('filter-panel')), findsOneWidget);
  }

  test('UX03: dimension count treats all-boards as one non-default axis', () {
    expect(const TaskFilterCriteria().searchDimensionCount, 0);
    expect(
      const TaskFilterCriteria(
        scope: TaskScopeFilter.allBoards,
      ).searchDimensionCount,
      1,
    );
    expect(
      const TaskFilterCriteria(
        scope: TaskScopeFilter.allBoards,
        quadrant: 1,
        status: TaskStatusFilter.incomplete,
        date: TaskDateFilter.noDate,
      ).searchDimensionCount,
      4,
    );
    expect(
      const TaskFilterCriteria(
        scope: TaskScopeFilter.allBoards,
        status: TaskStatusFilter.completed,
      ).archiveDimensionCount,
      1,
    );
    expect(resolveBoardName(
      boards: [Board(id: 'gone', name: 'Kept', createdAt: 1)],
      boardId: 'missing',
      unknownLabel: 'Unknown board',
    ), 'Unknown board');
  });

  testWidgets('UX03: Android search has bottom filter chrome and no chip track', (
    tester,
  ) async {
    final (store, _) = await makeStore();
    store.addTasks([store.newTask('Alpha', quadrant: qDo)]);
    await pumpSearch(tester, store, platform: TargetPlatform.android);
    expect(find.byKey(const ValueKey('filter-open-btn')), findsOneWidget);
    expect(find.byKey(const ValueKey('clear-filters-btn')), findsOneWidget);
    expect(find.byKey(const ValueKey('filter-scope-current')), findsNothing);
    expect(
      find.textContaining(
        store.t['currentBoardNamed']!.split('{name}').first,
      ),
      findsOneWidget,
    );
    expectNoHorizontalFilterTrack(tester);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('UX03: draft edits do not apply until Apply; cancel discards', (
    tester,
  ) async {
    final (store, _) = await makeStore();
    final homeId = store.activeBoardId;
    store.createBoard('Second');
    final other = store.boards.firstWhere((b) => b.name == 'Second');
    store.setActiveBoard(homeId);
    store.addTasks([
      Task(
        id: 'other-task',
        boardId: other.id,
        title: 'Other Board Task',
        quadrant: qDo,
        createdAt: 1,
      ),
    ]);
    store.addTasks([store.newTask('Home Task', quadrant: qDo)]);
    await pumpSearch(tester, store, platform: TargetPlatform.android);
    expect(find.text('Home Task'), findsOneWidget);
    expect(find.text('Other Board Task'), findsNothing);

    await openFilter(tester);
    await tester.tap(find.byKey(const ValueKey('filter-scope-all')));
    await tester.pumpAndSettle();
    expect(find.text('Other Board Task'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('filter-reset-btn')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('filter-apply-btn')));
    await tester.pumpAndSettle();
    expect(find.text('Other Board Task'), findsNothing);
    expect(find.byKey(const ValueKey('filter-panel')), findsNothing);

    await openFilter(tester);
    await tester.tap(find.byKey(const ValueKey('filter-scope-all')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('filter-apply-btn')));
    await tester.pumpAndSettle();
    expect(find.text('Other Board Task'), findsOneWidget);
    expect(
      find.text(store.t['filterCount']!.replaceAll('{n}', '1')),
      findsOneWidget,
    );

    await tester.enterText(find.byKey(const ValueKey('search-input')), 'Home');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('clear-filters-btn')));
    await tester.pumpAndSettle();
    expect(find.text('Other Board Task'), findsNothing);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('search-input')))
          .controller!
          .text,
      'Home',
    );
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('UX03: reset only clears draft; dismiss keeps applied filters', (
    tester,
  ) async {
    final (store, _) = await makeStore();
    store.addTasks([
      store.newTask('Q1 Item', quadrant: qDo),
      store.newTask('Q2 Item', quadrant: qPlan),
    ]);
    await pumpSearch(tester, store, platform: TargetPlatform.windows, size: const Size(1200, 900));
    await openFilter(tester);
    await tester.ensureVisible(find.byKey(const ValueKey('filter-q-1')));
    await tester.tap(find.byKey(const ValueKey('filter-q-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('filter-apply-btn')));
    await tester.pumpAndSettle();
    expect(find.text('Q1 Item'), findsOneWidget);
    expect(find.text('Q2 Item'), findsNothing);

    await openFilter(tester);
    await tester.tap(find.byKey(const ValueKey('filter-reset-btn')));
    await tester.pumpAndSettle();
    expect(find.text('Q2 Item'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('filter-cancel-btn')));
    await tester.pumpAndSettle();
    expect(find.text('Q1 Item'), findsOneWidget);
    expect(find.text('Q2 Item'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('UX03: Windows filter panel is vertical and reaches last date', (
    tester,
  ) async {
    final (store, _) = await makeStore();
    store.addTasks([store.newTask('Dated', quadrant: qDo)]);
    await pumpSearch(
      tester,
      store,
      platform: TargetPlatform.windows,
      size: const Size(1200, 900),
    );
    await openFilter(tester);
    expectNoHorizontalFilterTrack(tester);
    await tester.ensureVisible(find.byKey(const ValueKey('filter-date-nodate')));
    await tester.tap(find.byKey(const ValueKey('filter-date-nodate')));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('filter-panel')), findsNothing);
    expect(find.text('Dated'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('UX03: empty results expose clear filters and keyword actions', (
    tester,
  ) async {
    final (store, _) = await makeStore();
    store.addTasks([store.newTask('Milk', quadrant: qDo)]);
    await pumpSearch(tester, store, platform: TargetPlatform.android);
    await tester.enterText(find.byKey(const ValueKey('search-input')), 'xyz');
    await tester.pumpAndSettle();
    await openFilter(tester);
    await tester.ensureVisible(find.byKey(const ValueKey('filter-status-incomplete')));
    await tester.tap(find.byKey(const ValueKey('filter-status-incomplete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('filter-apply-btn')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('empty-results-hint')), findsOneWidget);
    expect(find.byKey(const ValueKey('empty-clear-filters-btn')), findsOneWidget);
    expect(find.byKey(const ValueKey('empty-clear-keyword-btn')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('empty-clear-keyword-btn')));
    await tester.pumpAndSettle();
    expect(find.text('Milk'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('UX03: archive uses scope panel without status filters', (
    tester,
  ) async {
    final (store, _) = await makeStore();
    final homeId = store.activeBoardId;
    store.createBoard('Board Two');
    final other = store.boards.firstWhere((b) => b.name == 'Board Two');
    store.setActiveBoard(homeId);
    store.addTasks([
      store.newTask('Done Home', quadrant: qDo)..completed = true,
      Task(
        id: 'done-other',
        boardId: other.id,
        title: 'Done Other',
        quadrant: qPlan,
        createdAt: 2,
        completed: true,
      ),
    ]);
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      wrapPlatform(
        store,
        CompletedScreen(initialBoardId: store.activeBoardId),
        TargetPlatform.android,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Done Home'), findsOneWidget);
    expect(find.text('Done Other'), findsNothing);
    expect(find.byKey(const ValueKey('completed-scope-all')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('filter-open-btn')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('completed-scope-all')), findsOneWidget);
    expect(find.byKey(const ValueKey('filter-status-incomplete')), findsNothing);
    expectNoHorizontalFilterTrack(tester);
    await tester.tap(find.byKey(const ValueKey('completed-scope-all')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('filter-apply-btn')));
    await tester.pumpAndSettle();
    expect(find.text('Done Other'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('UX03: subtask hits and 200% text avoid horizontal overflow', (
    tester,
  ) async {
    final (store, _) = await makeStore();
    final parent = store.newTask('Parent Feature', quadrant: qDo)
      ..subtasks = [
        SubTask(id: 'sub-1', title: 'Nested hit', completed: false),
      ];
    store.addTasks([parent]);
    await pumpSearch(
      tester,
      store,
      platform: TargetPlatform.android,
      textScale: 2,
    );
    await tester.enterText(find.byKey(const ValueKey('search-input')), 'Nested');
    await tester.pumpAndSettle();
    expect(find.text('Nested hit'), findsOneWidget);
    expect(find.textContaining('Parent Feature'), findsWidgets);
    expectNoHorizontalFilterTrack(tester);
    expect(tester.takeException(), isNull);
    final check = tester.getSize(
      find.byKey(ValueKey('search-check-hit-${parent.id}:sub-1')),
    );
    expect(check.width, greaterThanOrEqualTo(48));
    expect(check.height, greaterThanOrEqualTo(48));
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('UX03: layout resize keeps applied filters and keyword', (
    tester,
  ) async {
    final (store, _) = await makeStore();
    store.addTasks([
      store.newTask('Keep Me', quadrant: qDo),
      store.newTask('Hide Me', quadrant: qPlan),
    ]);
    await pumpSearch(
      tester,
      store,
      platform: TargetPlatform.windows,
      size: const Size(1200, 900),
    );
    await tester.enterText(find.byKey(const ValueKey('search-input')), 'Keep');
    await tester.pumpAndSettle();
    await openFilter(tester);
    await tester.ensureVisible(find.byKey(const ValueKey('filter-q-1')));
    await tester.tap(find.byKey(const ValueKey('filter-q-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('filter-apply-btn')));
    await tester.pumpAndSettle();
    await tester.binding.setSurfaceSize(const Size(640, 720));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('search-input')))
          .controller!
          .text,
      'Keep',
    );
    expect(find.text('Keep Me'), findsOneWidget);
    expect(find.text('Hide Me'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });
}
