import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/screens/matrix_screen.dart';
import 'package:matrixflow_native/shortcuts.dart';
import 'package:matrixflow_native/storage.dart';
import 'package:provider/provider.dart';

import 'helpers.dart';

Widget wrapApp(Store store, Widget home) {
  return ChangeNotifierProvider.value(
    value: store,
    child: MaterialApp(
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('en'), Locale('zh'), Locale('ja')],
      home: home,
    ),
  );
}

void main() {
  testWidgets('WP26-A-N: showShortcutsHelpDialog displays all key bindings', (
    tester,
  ) async {
    final (store, _) = await makeStore();

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder:
              (context) => ElevatedButton(
                onPressed: () => showShortcutsHelpDialog(context, store.t),
                child: const Text('Help'),
              ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Help'));
    await tester.pumpAndSettle();

    // Verify shortcuts help modal
    expect(find.text(store.t['shortcutsHelp']!), findsOneWidget);
    expect(find.text('Ctrl + K'), findsNothing);
    expect(find.text('Ctrl + N'), findsOneWidget);
    expect(find.text('Ctrl + F'), findsOneWidget);
    expect(find.text('Esc'), findsOneWidget);

    // Tap close button
    await tester.tap(find.text(store.t['close']!));
    await tester.pumpAndSettle();
    expect(find.text(store.t['shortcutsHelp']!), findsNothing);

    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets(
    'WP26-A-N: text editing in TextField takes priority and does not trigger global shortcuts',
    (tester) async {
      final (store, _) = await makeStore(
        boards: [Board(id: 'b1', name: 'Main Board', createdAt: 1000)],
      );

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: store,
          child: MaterialApp(
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            supportedLocales: const [Locale('en'), Locale('zh'), Locale('ja')],
            home: Scaffold(
              body: Column(
                children: [
                  const Expanded(child: MatrixHome()),
                  const TextField(key: ValueKey('test-text-field')),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Focus the test text field
      await tester.tap(find.byKey(const ValueKey('test-text-field')));
      await tester.pumpAndSettle();

      // Press Ctrl+N while in TextField - should NOT open new task input modal
      await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
      await tester.pumpAndSettle();

      // No modal sheet opened because text field is focused
      expect(find.text(store.t['modeManual'] ?? 'Standard'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      store.dispose();
    },
  );
}
