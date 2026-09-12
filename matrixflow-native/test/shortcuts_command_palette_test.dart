import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/screens/completed_screen.dart';
import 'package:matrixflow_native/screens/matrix_screen.dart';
import 'package:matrixflow_native/shortcuts.dart';
import 'package:matrixflow_native/storage.dart';
import 'package:matrixflow_native/widgets/command_palette.dart';
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
  testWidgets('WP26-A-N: command-palette-btn opens CommandPaletteDialog with commands', (tester) async {
    final (store, _) = await makeStore(
      boards: [
        Board(id: 'b1', name: 'Work Board', createdAt: 1000),
        Board(id: 'b2', name: 'Personal Board', createdAt: 1000),
      ],
      tasks: [
        Task(id: 't1', boardId: 'b1', title: 'Buy groceries', quadrant: 1, createdAt: 1000),
      ],
    );

    await tester.pumpWidget(wrapApp(store, const MatrixHome()));
    await tester.pumpAndSettle();

    // Verify command palette button exists in header
    final paletteBtn = find.byKey(const ValueKey('command-palette-btn'));
    expect(paletteBtn, findsOneWidget);

    // Tap command palette button
    await tester.tap(paletteBtn);
    await tester.pumpAndSettle();

    // Verify CommandPaletteDialog is open
    expect(find.byType(CommandPaletteDialog), findsOneWidget);
    expect(find.byKey(const ValueKey('command-palette-input')), findsOneWidget);

    // Verify command items appear
    expect(find.widgetWithText(InkWell, store.t['commandNewTask']!), findsOneWidget);
    expect(find.widgetWithText(InkWell, store.t['commandSearch']!), findsOneWidget);
    expect(find.widgetWithText(InkWell, store.t['commandCompleted']!), findsOneWidget);

    // Test Esc closes palette
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(CommandPaletteDialog), findsNothing);

    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('WP26-A-N: Ctrl+K triggers command palette and typing filters commands', (tester) async {
    final (store, _) = await makeStore(
      boards: [Board(id: 'b1', name: 'Main Board', createdAt: 1000)],
      tasks: [
        Task(id: 't1', boardId: 'b1', title: 'Fix bug', quadrant: 1, createdAt: 1000),
      ],
    );

    await tester.pumpWidget(wrapApp(store, const MatrixHome()));
    await tester.pumpAndSettle();

    // Simulate Ctrl+K
    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await tester.pumpAndSettle();

    expect(find.byType(CommandPaletteDialog), findsOneWidget);

    // Type query in input to filter
    await tester.enterText(
      find.byKey(const ValueKey('command-palette-input')),
      store.t['commandCompleted']!,
    );
    await tester.pumpAndSettle();

    // Completed command tile should be visible
    final completedTile = find.widgetWithText(InkWell, store.t['commandCompleted']!);
    expect(completedTile, findsOneWidget);

    // Tap on completed command -> navigates to CompletedScreen
    await tester.tap(completedTile);
    await tester.pumpAndSettle();

    expect(find.byType(CompletedScreen), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('WP26-A-N: command palette searches tasks across boards and opens detail', (tester) async {
    final (store, _) = await makeStore(
      boards: [
        Board(id: 'b1', name: 'Board 1', createdAt: 1000),
        Board(id: 'b2', name: 'Board 2', createdAt: 1000),
      ],
      tasks: [
        Task(
          id: 't-unique-alpha',
          boardId: 'b2',
          title: 'Unique Alpha Mission',
          quadrant: 2,
          createdAt: 1000,
          subtasks: [
            SubTask(id: 'st-beta', title: 'Subtask Beta Mission', completed: false),
          ],
        ),
      ],
    );

    await tester.pumpWidget(wrapApp(store, const MatrixHome()));
    await tester.pumpAndSettle();

    // Open command palette
    await tester.tap(find.byKey(const ValueKey('command-palette-btn')));
    await tester.pumpAndSettle();

    // Search for "Beta Mission" (a subtask on Board 2)
    await tester.enterText(
      find.byKey(const ValueKey('command-palette-input')),
      'Beta Mission',
    );
    await tester.pumpAndSettle();

    // Should find matched subtask tile
    final subtaskTile = find.widgetWithText(InkWell, 'Subtask Beta Mission');
    expect(subtaskTile, findsOneWidget);
    expect(find.text('Board 2 / Unique Alpha Mission'), findsOneWidget);

    // Tap matched task
    await tester.tap(subtaskTile);
    await tester.pumpAndSettle();

    // Board should have switched to Board 2 and palette dismissed
    expect(store.activeBoardId, 'b2');
    expect(find.byType(CommandPaletteDialog), findsNothing);

    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('WP26-A-N: showShortcutsHelpDialog displays all key bindings', (tester) async {
    final (store, _) = await makeStore();

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
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
    expect(find.text('Ctrl + K'), findsOneWidget);
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

  testWidgets('WP26-A-N: arrow keys navigate and Enter executes command in palette', (tester) async {
    final (store, _) = await makeStore(
      boards: [Board(id: 'b1', name: 'Main Board', createdAt: 1000)],
    );

    await tester.pumpWidget(wrapApp(store, const MatrixHome()));
    await tester.pumpAndSettle();

    // Open command palette
    await tester.tap(find.byKey(const ValueKey('command-palette-btn')));
    await tester.pumpAndSettle();

    // Type "focus" to filter focus commands
    await tester.enterText(
      find.byKey(const ValueKey('command-palette-input')),
      'Q1',
    );
    await tester.pumpAndSettle();

    expect(find.widgetWithText(InkWell, store.t['commandFocusQ1']!), findsOneWidget);

    // Hit Enter to execute first selected command (Focus Q1)
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    // Palette should close, and focus back button should appear in header
    expect(find.byType(CommandPaletteDialog), findsNothing);
    expect(find.byKey(const ValueKey('focus-back-btn')), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('WP26-A-N: text editing in TextField takes priority and does not trigger global shortcuts', (tester) async {
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
  });
}
