import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/screens/completed_screen.dart';
import 'package:matrixflow_native/screens/matrix_screen.dart';
import 'package:matrixflow_native/screens/settings_screen.dart';
import 'package:matrixflow_native/storage.dart';
import 'package:matrixflow_native/widgets/animated_task_title.dart';
import 'package:matrixflow_native/widgets/task_detail_panel.dart';
import 'package:matrixflow_native/widgets/task_exit.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';

Widget wrapApp(
  Store store, {
  Size size = const Size(360, 800),
  bool systemReduceMotion = false,
}) {
  return ChangeNotifierProvider.value(
    value: store,
    child: MaterialApp(
      theme: ThemeData(useMaterial3: true, platform: TargetPlatform.android),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('en'), Locale('zh'), Locale('ja')],
      home: MediaQuery(
        data: MediaQueryData(size: size, disableAnimations: systemReduceMotion),
        child: const MatrixHome(),
      ),
    ),
  );
}

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

void main() {
  Future<Store> pumpMatrix(
    WidgetTester tester, {
    Size size = const Size(360, 800),
    bool systemReduceMotion = false,
    AppSettings? settings,
    required List<Task> Function(Store store) seed,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final (store, _) = await makeStore(settings: settings);
    store.addTasks(seed(store));
    await tester.pumpWidget(
      wrapApp(store, size: size, systemReduceMotion: systemReduceMotion),
    );
    await tester.pumpAndSettle();
    return store;
  }

  StrikeThroughPainter painterFor(WidgetTester tester, String taskId) {
    final paint = tester.widget<CustomPaint>(
      find.byKey(ValueKey('task-strike-$taskId')),
    );
    return paint.foregroundPainter as StrikeThroughPainter;
  }

  double strikeProgress(WidgetTester tester, String taskId) =>
      painterFor(tester, taskId).progress;

  /// ExitingRow is always in the tree (constant structure); only rows whose
  /// [ExitingRow.exiting] is true are short-lived snapshots.
  Finder exitingRows() => find.byWidgetPredicate(
    (widget) => widget is ExitingRow && widget.exiting,
  );

  test('UX06: reduceMotion persists in v2 and is stripped from v1', () {
    expect(AppSettings().reduceMotion, isFalse);
    final on = AppSettings()..reduceMotion = true;
    expect(on.toJson()['reduceMotion'], isTrue);
    expect(on.toJson(targetVersion: 1).containsKey('reduceMotion'), isFalse);
    expect(AppSettings.fromJson({}).reduceMotion, isFalse);
    expect(AppSettings.fromJson(on.toJson()).reduceMotion, isTrue);
  });

  test(
    'UX06: reduceMotion round-trips through the store and storage',
    () async {
      final (store, _) = await makeStore();
      expect(store.settings.reduceMotion, isFalse);
      store.updateSettings((s) => s..reduceMotion = true);
      expect(store.settings.reduceMotion, isTrue);
      await store.flush();
      final prefs = await SharedPreferences.getInstance();
      final saved =
          jsonDecode(prefs.getString('matrixflow-settings')!)
              as Map<String, dynamic>;
      expect(saved['reduceMotion'], isTrue);
      final reloaded = Store();
      await reloaded.init();
      expect(reloaded.settings.reduceMotion, isTrue);
      reloaded.dispose();
      store.dispose();
    },
  );

  testWidgets('UX06: strikethrough grows over successive frames', (
    tester,
  ) async {
    final store = await pumpMatrix(
      tester,
      seed: (store) => [store.newTask('Draw me', quadrant: qDo)],
    );
    final id = store.tasks.first.id;
    expect(strikeProgress(tester, id), 0.0);

    await tester.tap(find.byKey(ValueKey('complete-$id')));
    await tester.pump();
    final start = strikeProgress(tester, id);
    await tester.pump(const Duration(milliseconds: 80));
    final mid = strikeProgress(tester, id);
    await tester.pump(const Duration(milliseconds: 80));
    final late = strikeProgress(tester, id);
    await tester.pump(const Duration(milliseconds: 80));
    final done = strikeProgress(tester, id);

    expect(start, lessThan(mid));
    expect(mid, lessThan(late));
    expect(late, lessThan(done));
    expect(done, 1.0);
    expect(painterFor(tester, id).drawnLength, greaterThan(0));
    expect(store.tasks.first.completed, isTrue);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('UX06: only visible wrapped lines are struck', (tester) async {
    final long = List.generate(
      20,
      (i) => 'line $i 中文混排 Compoise text',
    ).join(' ');
    final store = await pumpMatrix(
      tester,
      size: const Size(320, 720),
      seed: (store) => [store.newTask(long, quadrant: qDo)],
    );
    final id = store.tasks.first.id;
    await tester.tap(find.byKey(ValueKey('complete-$id')));
    await tester.pumpAndSettle();

    final painter = painterFor(tester, id);
    expect(painter.boxes, isNotEmpty);
    expect(painter.lineCount, lessThanOrEqualTo(3));
    final width = tester.getSize(find.byKey(ValueKey('task-title-$id'))).width;
    for (final box in painter.boxes) {
      expect(box.left, greaterThanOrEqualTo(-1));
      expect(box.right, lessThanOrEqualTo(width + 1));
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('UX06: already completed tasks load at the final state', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final (store, _) = await makeStore();
    final task = store.newTask('Already done', quadrant: qDo)..completed = true;
    store.addTasks([task]);
    await tester.pumpWidget(wrapApp(store));
    await tester.pump();
    // First frame: no replay of a strikethrough that "happened" before.
    expect(strikeProgress(tester, task.id), 1.0);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    store.dispose();
  });

  testWidgets('UX06: reduce motion jumps to the final state', (tester) async {
    final store = await pumpMatrix(
      tester,
      settings: AppSettings()..reduceMotion = true,
      seed: (store) => [store.newTask('Instant', quadrant: qDo)],
    );
    final id = store.tasks.first.id;
    await tester.tap(find.byKey(ValueKey('complete-$id')));
    await tester.pump();
    expect(strikeProgress(tester, id), 1.0);
    expect(store.tasks.first.completed, isTrue);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets(
    'UX06: platform reduce-animation request also skips the animation',
    (tester) async {
      final store = await pumpMatrix(
        tester,
        systemReduceMotion: true,
        seed: (store) => [store.newTask('System', quadrant: qDo)],
      );
      final id = store.tasks.first.id;
      await tester.tap(find.byKey(ValueKey('complete-$id')));
      await tester.pump();
      expect(strikeProgress(tester, id), 1.0);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    },
  );

  testWidgets('UX06: hideCompleted exits after the strikethrough', (
    tester,
  ) async {
    final store = await pumpMatrix(
      tester,
      settings: AppSettings()..hideCompleted = true,
      seed: (store) => [store.newTask('Leave me', quadrant: qDo)],
    );
    final id = store.tasks.first.id;
    await tester.tap(find.byKey(ValueKey('complete-$id')));
    await tester.pump();

    // Business truth is already saved, independently of the animation.
    expect(store.tasks.single.completed, isTrue);
    await store.flush();
    final prefs = await SharedPreferences.getInstance();
    final saved =
        jsonDecode(prefs.getString('matrixflow-tasks')!) as List<dynamic>;
    expect((saved.first as Map<String, dynamic>)['completed'], isTrue);

    // The row is still on screen as a non-interactive snapshot.
    expect(find.text('Leave me'), findsOneWidget);
    expect(exitingRows(), findsOneWidget);
    // Entering the exit state must not re-inflate the row and replay its
    // entrance fade: the row keeps full opacity while it starts to leave.
    final entrance = find.descendant(
      of: find.byKey(ValueKey('stagger-$id')),
      matching: find.byType(Opacity),
    );
    expect(tester.widget<Opacity>(entrance).opacity, 1.0);

    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    expect(find.text('Leave me'), findsNothing);
    expect(store.tasks.single.completed, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('UX06: deleting a task drops its exit snapshot at once', (
    tester,
  ) async {
    final store = await pumpMatrix(
      tester,
      settings: AppSettings()..hideCompleted = true,
      seed: (store) => [store.newTask('Gone', quadrant: qDo)],
    );
    final id = store.tasks.first.id;
    await tester.tap(find.byKey(ValueKey('complete-$id')));
    await tester.pump();
    expect(exitingRows(), findsOneWidget);

    store.deleteTask(id);
    await tester.pumpAndSettle();
    expect(find.text('Gone'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('UX06: un-completing cancels a pending exit', (tester) async {
    final store = await pumpMatrix(
      tester,
      settings: AppSettings()..hideCompleted = true,
      seed: (store) => [store.newTask('Back again', quadrant: qDo)],
    );
    final id = store.tasks.first.id;
    await tester.tap(find.byKey(ValueKey('complete-$id')));
    await tester.pump();
    expect(exitingRows(), findsOneWidget);

    store.setParentCompleted(store.tasks.first, false);
    await tester.pump();
    expect(exitingRows(), findsNothing);
    expect(find.text('Back again'), findsOneWidget);

    // The line retracts instead of staying drawn.
    await tester.pump(const Duration(milliseconds: 120));
    expect(strikeProgress(tester, id), lessThan(1.0));
    await tester.pumpAndSettle();
    expect(strikeProgress(tester, id), 0.0);
    expect(store.tasks.single.completed, isFalse);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('UX06: one tap performs one business write', (tester) async {
    final store = await pumpMatrix(
      tester,
      seed: (store) => [store.newTask('One write', quadrant: qDo)],
    );
    final id = store.tasks.first.id;
    await tester.tap(find.byKey(ValueKey('complete-$id')));
    await tester.pumpAndSettle();
    expect(store.tasks.single.completed, isTrue);
    expect(store.tasks.single.completedAt, isNotNull);
    expect(find.byType(TaskDetailPanel), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('UX06: disposing mid-exit leaves no stale timer', (tester) async {
    final store = await pumpMatrix(
      tester,
      settings: AppSettings()..hideCompleted = true,
      seed: (store) => [store.newTask('Kill me', quadrant: qDo)],
    );
    final id = store.tasks.first.id;
    await tester.tap(find.byKey(ValueKey('complete-$id')));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
    store.dispose();
  });

  testWidgets('UX06: restoring from the archive leaves with feedback', (
    tester,
  ) async {
    final (store, _) = await makeStore();
    final task = store.newTask('Restored', quadrant: qDo)..completed = true;
    store.addTasks([task]);
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      wrapPlatform(store, const CompletedScreen(), TargetPlatform.android),
    );
    await tester.pumpAndSettle();
    expect(find.text('Restored'), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('completed-restore-${task.id}')));
    await tester.pump();
    // The data is already restored; the row only leaves after a visible beat.
    expect(store.tasks.single.completed, isFalse);
    expect(exitingRows(), findsOneWidget);

    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    expect(find.text('Restored'), findsNothing);
    expect(store.tasks.single.completed, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('UX06: settings expose the reduce animation switch', (
    tester,
  ) async {
    final (store, _) = await makeStore();
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      wrapPlatform(store, const SettingsScreen(), TargetPlatform.windows),
    );
    await tester.pumpAndSettle();
    final toggle = find.byKey(const ValueKey('reduce-motion-toggle'));
    await tester.dragUntilVisible(
      toggle,
      find.descendant(
        of: find.byKey(const ValueKey('settings-list')),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down,
        ),
      ),
      const Offset(0, -240),
    );
    await tester.pumpAndSettle();
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(store.settings.reduceMotion, isTrue);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });
}
