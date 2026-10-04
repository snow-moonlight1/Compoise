// WP19-R prototype screen tests: the interactions the demo claims, the
// layout it must survive, and proof that a session cannot reach the library.
//
// Renders are Flutter widget renders driven by the real screen, not device
// screenshots; docs/WP19_R_NOTES.md keeps that boundary explicit.
import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/experiments/wp19_dev_mode/wp19_dev_data.dart';
import 'package:matrixflow_native/experiments/wp19_dev_mode/wp19_dev_mode_app.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _captureBoundary = ValueKey('capture-boundary');

/// Product-shaped library, so a stray write would be visible as a changed key.
const _seededLibrary = <String, Object>{
  'matrixflow-tasks': '[{"id":"real-1","boardId":"b","title":"真任务"}]',
  'matrixflow-boards': '[{"id":"b","name":"真实项目"}]',
  'matrixflow-settings': '{"language":"zh"}',
  'matrixflow-save-pointer': 'slot-a',
};

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(_seededLibrary);
  });

  // Rows can sit below the fold in a 360 dp viewport, so a page target is
  // centred before it is tapped; a blind tap would warn and land elsewhere.
  // Dialog buttons have no scrollable ancestor and are tapped as-is.
  Future<void> tapAt(WidgetTester tester, Finder finder, String label) async {
    if (find
        .ancestor(of: finder, matching: find.byType(Scrollable))
        .evaluate()
        .isNotEmpty) {
      await Scrollable.ensureVisible(
        finder.evaluate().single,
        alignment: 0.5,
      );
      await tester.pumpAndSettle();
    }
    final center = tester.getCenter(finder);
    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    expect(
      center.dx > 0 &&
          center.dx < size.width &&
          center.dy > 0 &&
          center.dy < size.height,
      isTrue,
      reason: '$label at $center is not tappable inside $size',
    );
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Key key) =>
      tapAt(tester, find.byKey(key), '$key');

  Future<void> tapText(WidgetTester tester, String text) =>
      tapAt(tester, find.text(text), text);

  Future<void> tapMode(WidgetTester tester, String label) =>
      tapText(tester, label);



  Future<void> open(
    WidgetTester tester, {
    Size viewport = const Size(360, 780),
    bool devMode = true,
  }) async {
    tester.view.physicalSize = viewport;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const RepaintBoundary(
        key: _captureBoundary,
        child: Wp19DevModeApp(),
      ),
    );
    await tester.pumpAndSettle();
    if (!devMode) {
      await tapMode(tester, '普通模式（现状）');
    }
  }

  testWidgets('development lens shows the wait, ordinary mode does not', (
    tester,
  ) async {
    await open(tester);

    // The blocked ship step says what it waits for.
    expect(find.textContaining('等待：干净安装验收'), findsOneWidget);
    expect(find.textContaining('完成后解锁'), findsWidgets);
    // Two-way wait is called out instead of being offered as work.
    expect(find.text('循环等待'), findsWidgets);

    await open(tester, devMode: false);
    // The same rows in the product's own grouping carry no dependency text.
    expect(find.textContaining('等待：'), findsNothing);
    expect(find.text('循环等待'), findsNothing);
    expect(find.textContaining('谁挡住谁'), findsNothing);
  });

  testWidgets('complete, undo and the session line stay in memory', (
    tester,
  ) async {
    await open(tester);

    await tap(tester, const Key('wp19r-toggle-r-pipeline'));
    expect(find.textContaining('本会话：意图 1'), findsOneWidget);
    expect(find.textContaining('写清数据升级与回退步骤'), findsWidgets);

    await tap(tester, const Key('wp19r-undo'));
    expect(find.textContaining('本会话：意图 0'), findsOneWidget);
  });

  testWidgets('batch completion confirms, records one intent, undoes as one', (
    tester,
  ) async {
    await open(tester);

    await tap(tester, const Key('wp19r-select-r-pipeline'));
    expect(find.textContaining('已选 1'), findsOneWidget);

    await tap(tester, const Key('wp19r-batch'));
    // The confirmation names what the batch unlocks before anything changes.
    expect(find.textContaining('批量操作记为一条意图'), findsOneWidget);
    await tap(tester, const Key('wp19r-batch-confirm'));

    expect(find.textContaining('本会话：意图 1'), findsOneWidget);
    await tap(tester, const Key('wp19r-undo'));
    expect(find.textContaining('本会话：意图 0'), findsOneWidget);
    expect(find.byKey(const Key('wp19r-select-r-pipeline')), findsOneWidget);
  });

  testWidgets('export presents reviewable experiment state only', (tester) async {
    await open(tester);
    await tap(tester, const Key('wp19r-toggle-r-pipeline'));

    await tap(tester, const Key('wp19r-export'));
    expect(find.text('实验状态（JSON，可直接审查）'), findsOneWidget);
    expect(find.textContaining('wp19r.dev-experiment/1'), findsOneWidget);
    expect(find.textContaining('memory-only'), findsOneWidget);
    expect(find.textContaining('"kind": "complete"'), findsOneWidget);
    // Not a backup: the product shell keys must not appear.
    expect(find.textContaining('aiConfig'), findsNothing);
    expect(find.textContaining('scheduleItems'), findsNothing);

    await tap(tester, const Key('wp19r-export-close'));
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('removing a task from the session is explicit and reversible', (
    tester,
  ) async {
    await open(tester);

    await tap(tester, const Key('wp19r-more-r-website'));
    expect(find.text('只影响本会话的合成任务，产品库没有这份数据。'), findsOneWidget);
    await tap(tester, const Key('wp19r-remove-r-website'));

    expect(find.byKey(const Key('wp19r-row-r-website')), findsNothing);
    expect(find.textContaining('本会话：意图 1'), findsOneWidget);

    await tap(tester, const Key('wp19r-undo'));
    expect(find.byKey(const Key('wp19r-row-r-website')), findsOneWidget);
  });

  testWidgets('leaving discards the session and reloads the same fixture', (
    tester,
  ) async {
    await open(tester);
    await tap(tester, const Key('wp19r-toggle-r-pipeline'));

    await tap(tester, const Key('wp19r-leave'));
    expect(find.textContaining('将丢弃：意图 1 条'), findsOneWidget);
    await tap(tester, const Key('wp19r-leave-cancel'));
    expect(find.textContaining('本会话：意图 1'), findsOneWidget);

    await tap(tester, const Key('wp19r-leave'));
    await tap(tester, const Key('wp19r-leave-confirm'));
    expect(find.text('已退出原型'), findsOneWidget);
    expect(find.textContaining('写入产品库 0 次'), findsOneWidget);

    await tap(tester, const Key('wp19r-reload'));
    expect(find.textContaining('本会话：意图 0'), findsOneWidget);
    expect(find.text('已重新载入同一份合成数据'), findsOneWidget);
  });

  testWidgets('phase and project filters narrow the lens only', (tester) async {
    await open(tester);

    await tap(tester, const Key('wp19r-phase-build'));
    expect(find.byKey(const Key('wp19r-row-r-pipeline')), findsOneWidget);
    expect(find.byKey(const Key('wp19r-row-r-tag')), findsNothing);
    // The phase control belongs to the lens; ordinary mode ignores it.
    await tapMode(tester, '普通模式（现状）');
    expect(find.byKey(const Key('wp19r-row-r-tag')), findsOneWidget);

    await tapMode(tester, '开发视角');
    expect(find.byKey(const Key('wp19r-row-r-tag')), findsNothing);

    await tap(tester, const Key('wp19r-board-p-daily'));
    expect(find.byKey(const Key('wp19r-row-r-pipeline')), findsNothing);
    expect(find.byKey(const Key('wp19r-row-d-refactor')), findsOneWidget);

    await tap(tester, const Key('wp19r-phase-build'));
    await tap(tester, const Key('wp19r-phase-design'));
    // The daily project has no design work, and the list says so out loud.
    expect(find.text('当前筛选没有任务'), findsOneWidget);
    expect(find.byKey(const Key('wp19r-row-d-refactor')), findsNothing);
  });

  // Each combination gets its own case: the screen keeps its state between
  // pumps, so reusing one case would cancel the toggles out and quietly
  // capture the same picture four times.
  for (final dark in [false, true]) {
    for (final large in [false, true]) {
      final tag = '${dark ? 'dark' : 'light'}_${large ? '200' : '100'}';
      testWidgets('narrow phone stays laid out and tappable ($tag)', (
        tester,
      ) async {
        await open(tester, viewport: const Size(360, 780));
        if (dark) await tap(tester, const Key('wp19r-theme'));
        if (large) await tap(tester, const Key('wp19r-font'));

        final scaffoldContext = tester.element(find.byType(Scaffold));
        expect(
          Theme.of(scaffoldContext).brightness,
          dark ? Brightness.dark : Brightness.light,
        );
        expect(
          MediaQuery.textScalerOf(scaffoldContext).scale(10),
          closeTo(large ? 20 : 10, 0.01),
        );
        expect(tester.takeException(), isNull, reason: tag);
        expect(find.textContaining('本会话：意图 0'), findsOneWidget);

        // A row action must still be hit-testable at this size.
        await tap(tester, const Key('wp19r-toggle-r-pipeline'));
        expect(find.textContaining('本会话：意图 1'), findsOneWidget);

        await _capture(tester, 'phone_360_$tag.png');
      });
    }
  }

  testWidgets('confirm and export dialogs fit a 200% phone screen', (
    tester,
  ) async {
    await open(tester, viewport: const Size(360, 780));
    await tap(tester, const Key('wp19r-font'));
    await tap(tester, const Key('wp19r-select-r-pipeline'));
    await tap(tester, const Key('wp19r-select-r-changelog'));
    await tap(tester, const Key('wp19r-batch'));
    expect(find.textContaining('批量操作记为一条意图'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _capture(tester, 'phone_360_light_200_batch_dialog.png');
    await tap(tester, const Key('wp19r-batch-cancel'));

    await tap(tester, const Key('wp19r-export'));
    expect(find.textContaining('wp19r.dev-experiment/1'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _capture(tester, 'phone_360_light_200_export_dialog.png');
    await tap(tester, const Key('wp19r-export-close'));
  });

  testWidgets('desktop width shows both grouping summaries without overflow', (
    tester,
  ) async {
    await open(tester, viewport: const Size(1100, 900));
    expect(tester.takeException(), isNull);
    expect(find.textContaining('可开始'), findsWidgets);
    await _capture(tester, 'desktop_1100_light_100.png');

    await tapMode(tester, '普通模式（现状）');
    expect(tester.takeException(), isNull);
    await _capture(tester, 'desktop_1100_light_normal_mode.png');
  });

  testWidgets('keyboard reaches the controls and space completes work', (
    tester,
  ) async {
    await open(tester, viewport: const Size(900, 1200));

    final visited = <String>{};
    String? focused;
    for (var step = 0; step < 60 && focused?.startsWith('wp19r-toggle-') != true; step++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      focused = _focusedPrototypeKey(tester);
      if (focused != null) visited.add(focused);
    }
    expect(
      focused,
      startsWith('wp19r-toggle-'),
      reason: 'traversal reached: $visited',
    );
    // The header controls take focus first, so the screen works one-handed.
    expect(visited, containsAll(['wp19r-undo', 'wp19r-export', 'wp19r-leave']));

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(find.textContaining('本会话：意图 1'), findsOneWidget);
  });

  testWidgets('a session never touches the seeded product library', (
    tester,
  ) async {
    await open(tester);
    await tap(tester, const Key('wp19r-toggle-r-pipeline'));
    await tap(tester, const Key('wp19r-select-r-changelog'));
    expect(find.textContaining('已选 1'), findsOneWidget);
    await tap(tester, const Key('wp19r-batch'));
    await tap(tester, const Key('wp19r-batch-confirm'));
    await tap(tester, const Key('wp19r-undo'));

    final after = await tester.runAsync(() async {
      final prefs = await SharedPreferences.getInstance();
      return {
        'keys': prefs.getKeys().toList()..sort(),
        'values': {
          for (final key in prefs.getKeys()) key: prefs.get(key),
        },
      };
    });
    expect(after!['keys'], _seededLibrary.keys.toList()..sort());
    expect(after['values'], equals(_seededLibrary));
  });

  test('the fixture really is the small session the notes describe', () {
    final session = buildWp19Session();
    expect(session.tasks.length, 13);
  });
}

String? _focusedPrototypeKey(WidgetTester tester) {
  final context = tester.binding.focusManager.primaryFocus?.context;
  if (context is! Element) return null;
  String? found;
  context.visitAncestorElements((element) {
    if (found != null) return false;
    final key = element.widget.key;
    if (key is ValueKey<String> && key.value.startsWith('wp19r')) {
      found = key.value;
    }
    return found == null;
  });
  return found;
}

/// Writes a render of the whole screen when WP19R_OUT points at this package's
/// private root; the default suite never touches the filesystem.
Future<void> _capture(WidgetTester tester, String name) async {
  final dir = Platform.environment['WP19R_OUT'];
  if (dir == null || dir.isEmpty) return;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_captureBoundary),
    );
    final image = await boundary.toImage(pixelRatio: 2.0);
    final bytes = await image.toByteData(format: ImageByteFormat.png);
    Directory('$dir/render').createSync(recursive: true);
    File('$dir/render/$name')
        .writeAsBytesSync(bytes!.buffer.asUint8List(), flush: true);
    image.dispose();
  });
}
