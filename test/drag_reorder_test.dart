import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:compoise/models.dart';
import 'package:compoise/screens/matrix_screen.dart';
import 'package:compoise/storage.dart';
import 'package:compoise/task_order.dart';
import 'package:compoise/theme.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'helpers.dart';
import 'widget_regression_test.dart' show setup, viewport;

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

Task _task(String id, String board, int quadrant) =>
    Task(id: id, boardId: board, title: id, quadrant: quadrant, createdAt: 1);

List<String> _ids(Store store, int q) =>
    store.tasksIn(q).map((t) => t.id).toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('dropAnchor', () {
    test('returns the row at the slot, skipping moving rows', () {
      expect(dropAnchor(['a', 'b', 'c'], 0, {}), 'a');
      expect(dropAnchor(['a', 'b', 'c'], 1, {'b'}), 'c');
      expect(dropAnchor(['a', 'b', 'c'], 2, {'c'}), isNull);
      expect(dropAnchor(['a', 'b', 'c'], 3, {}), isNull);
    });
  });

  group('Store.placeTasks', () {
    Future<Store> make() async {
      final (store, _) = await makeStore(
        boards: [Board(id: 'b1', name: 'One', createdAt: 1)],
        tasks: [
          _task('a', 'b1', qDo),
          _task('b', 'b1', qDo),
          _task('c', 'b1', qDo),
          _task('x', 'b1', qPlan),
          _task('y', 'b1', qPlan),
        ],
      );
      addTearDown(store.dispose);
      return store;
    }

    test('reorders within a quadrant and persists', () async {
      final store = await make();
      expect(store.placeTasks(['c'], qDo, beforeId: 'a'), isTrue);
      expect(_ids(store, qDo), ['c', 'a', 'b']);
      expect(store.placeTasks(['c'], qDo), isTrue);
      expect(_ids(store, qDo), ['a', 'b', 'c']);
      expect((await store.flush()).success, isTrue);
      final reloaded = Store();
      addTearDown(reloaded.dispose);
      await reloaded.init();
      expect(_ids(reloaded, qDo), ['a', 'b', 'c']);
      expect(_ids(reloaded, qPlan), ['x', 'y']);
    });

    test('unchanged order saves nothing', () async {
      final store = await make();
      expect((await store.flush()).success, isTrue);
      final revision = store.lastSaveResult.revision;
      expect(store.placeTasks(['b'], qDo, beforeId: 'c'), isFalse);
      expect(store.placeTasks(['c'], qDo), isFalse);
      expect((await store.flush()).success, isTrue);
      expect(store.lastSaveResult.revision, revision);
    });

    test('inserts into another quadrant at the exact slot', () async {
      final store = await make();
      store.placeTasks(['x'], qDo, beforeId: 'b');
      expect(_ids(store, qDo), ['a', 'x', 'b', 'c']);
      expect(_ids(store, qPlan), ['y']);
      final x = store.tasks.firstWhere((t) => t.id == 'x');
      expect(x.quadrant, qDo);
      expect(x.urgencyMode, UrgencyMode.manual);
    });

    test('a stack keeps its order and lands together', () async {
      final store = await make();
      store.placeTasks(['y', 'a'], qPlan, beforeId: 'x');
      expect(_ids(store, qPlan), ['y', 'a', 'x']);
      expect(_ids(store, qDo), ['b', 'c']);
    });

    test('empty target quadrant and other boards', () async {
      final store = await make();
      store.placeTasks(['a'], qDelegate);
      expect(_ids(store, qDelegate), ['a']);
      expect(store.placeTasks(['missing'], qDo), isFalse);
    });

    test('moveTask still puts a cross-quadrant drop at the top', () async {
      final store = await make();
      store.moveTask('y', qDo);
      expect(_ids(store, qDo).first, 'y');
    });
  });

  Future<void> drag(
    WidgetTester tester,
    Offset start,
    Offset end, {
    void Function()? midway,
    bool mouse = false,
    Duration hold = const Duration(milliseconds: 300),
  }) async {
    final gesture = await tester.startGesture(
      start,
      kind: mouse ? PointerDeviceKind.mouse : PointerDeviceKind.touch,
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    for (var i = 1; i <= 12; i++) {
      await gesture.moveTo(Offset.lerp(start, end, i / 12)!);
      await tester.pump(const Duration(milliseconds: 16));
    }
    for (
      var t = Duration.zero;
      t < hold;
      t += const Duration(milliseconds: 50)
    ) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    midway?.call();
    await gesture.up();
    await tester.pumpAndSettle();
  }

  double openGap(WidgetTester tester) {
    var total = 0.0;
    for (final e
        in find
            .byWidgetPredicate(
              (w) =>
                  w is AnimatedContainer &&
                  w.key is ValueKey<String> &&
                  (w.key as ValueKey<String>).value.startsWith('drop-gap-'),
            )
            .evaluate()) {
      total += e.size?.height ?? 0;
    }
    return total;
  }

  for (final skin in _Skin.values) {
    for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
      final touch = platform == TargetPlatform.android;
      testWidgets('drag reorders within and across quadrants '
          '(${skin.name}, ${platform.name})', (tester) async {
        viewport(tester, touch ? const Size(390, 844) : const Size(1280, 800));
        final store = await setup(tester);
        final a = store.newTask('row alpha');
        final b = store.newTask('row beta');
        final c = store.newTask('row gamma');
        final x = store.newTask('plan xray', quadrant: qPlan);
        store.addTasks([a, b, c, x]);
        await tester.pumpWidget(_app(store, platform, skin));
        await tester.pumpAndSettle();
        final before = _ids(store, qDo);
        expect(before.length, 3);

        // Same quadrant: last row onto the upper half of the first row.
        final last = store.tasksIn(qDo).last;
        final first = store.tasksIn(qDo).first;
        final firstRect = tester.getRect(find.text(first.title));
        await drag(
          tester,
          tester.getCenter(find.text(last.title)),
          Offset(firstRect.center.dx, firstRect.top + 1),
          midway: () => expect(openGap(tester), greaterThan(20)),
          mouse: !touch,
        );
        expect(_ids(store, qDo), [last.id, before[0], before[1]]);
        expect(openGap(tester), 0);

        // Other quadrant: between the first and second rows.
        final rows = store.tasksIn(qDo);
        final r0 = tester.getRect(find.text(rows[0].title));
        await drag(
          tester,
          tester.getCenter(find.text('plan xray')),
          Offset(r0.center.dx, r0.bottom - 1),
          midway: () => expect(openGap(tester), greaterThan(20)),
          mouse: !touch,
        );
        expect(_ids(store, qDo), [rows[0].id, x.id, rows[1].id, rows[2].id]);
        expect(store.tasksIn(qPlan), isEmpty);

        // Header of another quadrant: still goes to the top.
        await drag(
          tester,
          tester.getCenter(find.text('plan xray')),
          tester.getCenter(
            find.byKey(const ValueKey('quadrant-header-$qPlan')),
          ),
          mouse: !touch,
        );
        expect(_ids(store, qPlan), [x.id]);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });

      testWidgets('focused quadrant reorders; collapsed card drop goes to top '
          '(${skin.name}, ${platform.name})', (tester) async {
        viewport(tester, touch ? const Size(390, 844) : const Size(1280, 800));
        final store = await setup(tester);
        final y = store.newTask('plan yoke', quadrant: qPlan);
        store.addTasks([
          store.newTask('row alpha'),
          store.newTask('row beta'),
          store.newTask('row gamma'),
          y,
        ]);
        await tester.pumpWidget(_app(store, platform, skin));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(ValueKey('quadrant-header-$qDo')));
        await tester.pumpAndSettle();
        final before = _ids(store, qDo);
        final rows = store.tasksIn(qDo);
        final firstRect = tester.getRect(find.text(rows.first.title));
        await drag(
          tester,
          tester.getCenter(find.text(rows.last.title)),
          Offset(firstRect.center.dx, firstRect.top + 1),
          midway: () => expect(openGap(tester), greaterThan(20)),
          mouse: !touch,
        );
        expect(_ids(store, qDo), [before[2], before[0], before[1]]);

        await drag(
          tester,
          tester.getCenter(find.text(rows.first.title)),
          tester.getCenter(find.byKey(ValueKey('focus-card-$qPlan'))),
          mouse: !touch,
        );
        expect(_ids(store, qPlan), [before[0], y.id]);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });

      testWidgets('list mode reorders, inserts across sections, header = top '
          '(${skin.name}, ${platform.name})', (tester) async {
        viewport(tester, touch ? const Size(390, 844) : const Size(1280, 800));
        final store = await setup(tester);
        final x = store.newTask('plan xray', quadrant: qPlan);
        final y = store.newTask('plan yoke', quadrant: qPlan);
        store.addTasks([
          store.newTask('row alpha'),
          store.newTask('row beta'),
          store.newTask('row gamma'),
          x,
          y,
        ]);
        store.setViewMode(ViewMode.list);
        await tester.pumpWidget(_app(store, platform, skin));
        await tester.pumpAndSettle();
        final before = _ids(store, qDo);
        final rows = store.tasksIn(qDo);
        final firstRect = tester.getRect(find.text(rows.first.title));
        await drag(
          tester,
          tester.getCenter(find.text(rows.last.title)),
          Offset(firstRect.center.dx, firstRect.top + 1),
          midway: () => expect(openGap(tester), greaterThan(20)),
          mouse: !touch,
        );
        expect(_ids(store, qDo), [before[2], before[0], before[1]]);

        final r0 = tester.getRect(find.text(store.tasksIn(qDo).first.title));
        final planFirst = store.tasksIn(qPlan).first;
        await drag(
          tester,
          tester.getCenter(find.text(planFirst.title)),
          Offset(r0.center.dx, r0.bottom - 1),
          midway: () => expect(openGap(tester), greaterThan(20)),
          mouse: !touch,
        );
        expect(_ids(store, qDo)[1], planFirst.id);

        final planLeft = store.tasksIn(qPlan).single;
        await drag(
          tester,
          tester.getCenter(find.text(store.tasksIn(qDo).last.title)),
          tester.getCenter(find.byKey(ValueKey('list-quadrant-header-$qPlan'))),
          mouse: !touch,
        );
        expect(_ids(store, qPlan), [before[1], planLeft.id]);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });

      for (final list in [false, true]) {
        testWidgets('dragging near the bottom edge scrolls '
            '(${list ? 'list' : 'grid'}, ${skin.name}, ${platform.name})', (
          tester,
        ) async {
          viewport(
            tester,
            touch ? const Size(390, 844) : const Size(1280, 800),
          );
          final store = await setup(tester);
          store.addTasks([
            for (var i = 0; i < 30; i++) store.newTask('long row $i'),
          ]);
          if (list) store.setViewMode(ViewMode.list);
          await tester.pumpWidget(_app(store, platform, skin));
          await tester.pumpAndSettle();
          final listFinder = find.byKey(
            PageStorageKey(
              list
                  ? '${store.activeBoardId}-task-list-view'
                  : '${store.activeBoardId}-$qDo',
            ),
          );
          final scrollable = tester.state<ScrollableState>(
            find
                .descendant(of: listFinder, matching: find.byType(Scrollable))
                .first,
          );
          expect(scrollable.position.pixels, 0);
          final rect = tester.getRect(listFinder);
          final firstId = _ids(store, qDo).first;
          final start = tester.getCenter(find.text('long row 0').first);
          final dragged = store.tasks.firstWhere((t) => t.id == firstId);
          // Near the edge, then right on it: faster the closer it gets.
          final gesture = await tester.startGesture(
            start,
            kind: touch ? PointerDeviceKind.touch : PointerDeviceKind.mouse,
          );
          await tester.pump(
            kLongPressTimeout + const Duration(milliseconds: 50),
          );
          await gesture.moveTo(Offset(start.dx, rect.bottom - 30));
          for (var i = 0; i < 10; i++) {
            await tester.pump(const Duration(milliseconds: 50));
          }
          final slow = scrollable.position.pixels;
          expect(slow, greaterThan(0));
          await gesture.moveTo(Offset(start.dx, rect.bottom - 2));
          for (var i = 0; i < 10; i++) {
            await tester.pump(const Duration(milliseconds: 50));
          }
          final fast = scrollable.position.pixels - slow;
          expect(fast, greaterThan(slow));
          // Back to the middle: scrolling stops.
          await gesture.moveTo(Offset(start.dx, rect.center.dy));
          await tester.pump(const Duration(milliseconds: 200));
          final stopped = scrollable.position.pixels;
          for (var i = 0; i < 6; i++) {
            await tester.pump(const Duration(milliseconds: 50));
          }
          expect(scrollable.position.pixels, stopped);
          await gesture.up();
          await tester.pumpAndSettle();
          // It lands lower down, where the pointer ended after scrolling.
          expect(_ids(store, qDo).indexOf(dragged.id), greaterThan(0));
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          // Rows built while scrolling still run their entrance timers.
          await tester.pump(const Duration(seconds: 1));
        });
      }
    }
  }
}
