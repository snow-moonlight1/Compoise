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
  }) async {
    final gesture = await tester.startGesture(start);
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    for (var i = 1; i <= 12; i++) {
      await gesture.moveTo(Offset.lerp(start, end, i / 12)!);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pump(const Duration(milliseconds: 300));
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
        );
        expect(_ids(store, qPlan), [x.id]);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
