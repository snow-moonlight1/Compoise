import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/screens/completed_screen.dart';
import 'package:matrixflow_native/screens/matrix_screen.dart';
import 'package:matrixflow_native/screens/settings_screen.dart';
import 'package:matrixflow_native/shortcuts.dart';
import 'package:matrixflow_native/storage.dart';
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

void main() {
  Future<void> pumpHome(
    WidgetTester tester,
    Store store, {
    required TargetPlatform platform,
    Size size = const Size(390, 844),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(wrapPlatform(store, const MatrixHome(), platform));
    await tester.pumpAndSettle();
  }

  testWidgets('UX02: Android home has bottom actions and no desktop chrome', (
    tester,
  ) async {
    final (store, _) = await makeStore();
    await pumpHome(tester, store, platform: TargetPlatform.android);
    expect(find.byKey(const ValueKey('search-btn')), findsOneWidget);
    expect(find.byKey(const ValueKey('add-task-btn')), findsOneWidget);
    expect(find.byKey(const ValueKey('more-btn')), findsOneWidget);
    expect(find.byKey(const ValueKey('board-picker-btn')), findsOneWidget);
    expect(find.byKey(const ValueKey('completed-btn')), findsNothing);
    expect(find.textContaining('Ctrl'), findsNothing);
    expect(find.textContaining('⌘'), findsNothing);
    expect(find.byKey(const ValueKey('completion-rate-text')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('UX02: Windows home has top actions and on-demand composer', (
    tester,
  ) async {
    final (store, _) = await makeStore();
    await pumpHome(
      tester,
      store,
      platform: TargetPlatform.windows,
      size: const Size(1200, 900),
    );
    expect(find.byKey(const ValueKey('search-btn')), findsOneWidget);
    expect(find.byKey(const ValueKey('add-task-btn')), findsOneWidget);
    expect(find.byKey(const ValueKey('more-btn')), findsOneWidget);
    expect(find.byKey(const ValueKey('task-step-0')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('add-task-btn')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('task-step-0')), findsOneWidget);
    expect(find.textContaining('⌘'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('UX02: more panel reaches completed and settings in two steps', (
    tester,
  ) async {
    final (store, _) = await makeStore();
    await pumpHome(tester, store, platform: TargetPlatform.android);
    await tester.tap(find.byKey(const ValueKey('more-btn')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('more-panel')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('completed-btn')));
    await tester.pumpAndSettle();
    expect(find.byType(CompletedScreen), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('completed-back-btn')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('more-btn')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('more-settings-btn')));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('UX02: empty board cannot enter selection', (tester) async {
    final (store, _) = await makeStore();
    await pumpHome(tester, store, platform: TargetPlatform.windows);
    await tester.tap(find.byKey(const ValueKey('more-btn')));
    await tester.pumpAndSettle();
    final select = tester.widget<ListTile>(
      find.byKey(const ValueKey('select-tasks-btn')),
    );
    expect(select.enabled, isFalse);
    expect(find.byKey(const ValueKey('completion-rate-text')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets(
    'UX02: completion rate is opt-in, persisted, and home-more only',
    (tester) async {
      final (store, _) = await makeStore();
      expect(store.settings.showCompletionRate, isFalse);
      store.addTasks([
        store.newTask('Done')..completed = true,
        store.newTask('Open', quadrant: 2),
      ]);
      await pumpHome(tester, store, platform: TargetPlatform.windows);
      await tester.tap(find.byKey(const ValueKey('more-btn')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('completion-rate-text')), findsNothing);
      Navigator.of(
        tester.element(find.byKey(const ValueKey('more-panel'))),
      ).pop();
      await tester.pumpAndSettle();

      store.updateSettings((s) => s..showCompletionRate = true);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('more-btn')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('completion-rate-text')),
        findsOneWidget,
      );
      expect(find.textContaining('2'), findsWidgets);
      Navigator.of(
        tester.element(find.byKey(const ValueKey('more-panel'))),
      ).pop();
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('more-btn')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('completed-btn')));
      await tester.pumpAndSettle();
      expect(find.byType(CompletedScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('completion-rate-text')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    },
  );

  testWidgets('UX02: missing backup field stays off and settings can enable', (
    tester,
  ) async {
    final (store, _) = await makeStore();
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      wrapPlatform(store, const SettingsScreen(), TargetPlatform.windows),
    );
    await tester.pumpAndSettle();
    final rateToggle = find.byKey(
      const ValueKey('show-completion-rate-toggle'),
    );
    await tester.dragUntilVisible(
      rateToggle,
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
    expect(store.settings.showCompletionRate, isFalse);
    await tester.tap(rateToggle);
    await tester.pumpAndSettle();
    expect(store.settings.showCompletionRate, isTrue);
    final shortcuts = find.byKey(const ValueKey('shortcuts-help-tile'));
    await tester.scrollUntilVisible(
      shortcuts,
      300,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('settings-list')),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down,
        ),
      ),
    );
    expect(shortcuts, findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('UX02: Android settings hide desktop shortcuts and tray', (
    tester,
  ) async {
    final (store, _) = await makeStore();
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      wrapPlatform(store, const SettingsScreen(), TargetPlatform.android),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('shortcuts-help-tile')), findsNothing);
    expect(find.text(store.t['closeToTray']!), findsNothing);
    expect(find.textContaining('⌘'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('UX02: Ctrl+Shift+V does not toggle view; Ctrl+Shift+L does', (
    tester,
  ) async {
    final (store, _) = await makeStore();
    await pumpHome(
      tester,
      store,
      platform: TargetPlatform.windows,
      size: const Size(1200, 900),
    );
    expect(store.settings.viewMode, ViewMode.grid);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await tester.pumpAndSettle();
    expect(store.settings.viewMode, ViewMode.grid);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await tester.pumpAndSettle();
    expect(store.settings.viewMode, ViewMode.list);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  test('UX02: shortcut help metadata uses Ctrl and not command palette', () {
    expect(
      shortcutHelpItems.any((item) => item.keys.contains('Ctrl + N')),
      isTrue,
    );
    expect(
      shortcutHelpItems.any((item) => item.keys.contains('Ctrl + K')),
      isFalse,
    );
    expect(shortcutHelpItems.any((item) => item.keys.contains('⌘')), isFalse);
    expect(
      shortcutHelpItems.any((item) => item.keys.contains('Ctrl + Shift + V')),
      isFalse,
    );
    expect(
      shortcutHelpItems.any((item) => item.keys.contains('Ctrl + Shift + L')),
      isTrue,
    );
  });
}
