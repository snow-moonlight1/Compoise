import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/widgets/quadrant_transition_layout.dart';
import 'package:matrixflow_native/widgets/task_exit.dart';
import 'package:provider/provider.dart';

import 'helpers.dart';

void main() {
  testWidgets('OS13: exiting row drops focus and cannot be reactivated', (
    tester,
  ) async {
    final rowFocus = FocusNode();
    final safeFocus = FocusNode();
    addTearDown(rowFocus.dispose);
    addTearDown(safeFocus.dispose);
    var exiting = false;
    var rowActions = 0;
    var safeActions = 0;
    var escapes = 0;
    late StateSetter change;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, set) {
            change = set;
            return Shortcuts(
              shortcuts: const {
                SingleActivator(LogicalKeyboardKey.escape): _EscapeIntent(),
              },
              child: Actions(
                actions: {
                  _EscapeIntent: CallbackAction<_EscapeIntent>(
                    onInvoke: (_) {
                      escapes++;
                      return null;
                    },
                  ),
                },
                child: Scaffold(
                  body: Column(
                    children: [
                      ExitingRow(
                        exiting: exiting,
                        child: TextButton(
                          focusNode: rowFocus,
                          onPressed: () => rowActions++,
                          child: const Text('Outgoing'),
                        ),
                      ),
                      TextButton(
                        focusNode: safeFocus,
                        onPressed: () => safeActions++,
                        child: const Text('Safe'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
    rowFocus.requestFocus();
    await tester.pump();
    expect(rowFocus.hasFocus, isTrue);
    final outgoingCenter = tester.getCenter(find.text('Outgoing'));

    change(() => exiting = true);
    await tester.pump();
    expect(rowFocus.hasFocus, isFalse);
    rowFocus.requestFocus();
    await tester.pump();
    expect(rowFocus.hasFocus, isFalse);
    for (final key in [LogicalKeyboardKey.space, LogicalKeyboardKey.enter]) {
      await tester.sendKeyEvent(key);
      await tester.pump();
    }
    await tester.tapAt(outgoingCenter);
    await tester.pump();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.down(outgoingCenter);
    await mouse.up();
    await mouse.removePointer();
    await tester.pump();
    expect(rowActions, 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(rowFocus.hasFocus, isFalse);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(rowFocus.hasFocus, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(escapes, 1);
    expect(rowActions, 0);

    change(() => exiting = false);
    await tester.pump();
    expect(rowFocus.hasFocus, isFalse);
    rowFocus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(rowActions, 1);
    safeFocus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(safeActions, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('OS13: hidden panes lose focus without losing their State', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final (store, _) = await makeStore(
      settings: AppSettings()..viewMode = ViewMode.grid,
    );
    int? focused;
    late StateSetter change;
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: store,
        child: MaterialApp(
          home: StatefulBuilder(
            builder: (context, set) {
              change = set;
              return Scaffold(
                body: QuadrantTransitionLayout(
                  focusedQuadrant: focused,
                  viewMode: ViewMode.grid,
                  onFocusQuadrant: (q) => set(() => focused = q),
                  onExitFocus: () => set(() => focused = null),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final q1State = tester.state(find.byKey(const ValueKey('q-pane-1')));
    final q1Header = find.byKey(const ValueKey('quadrant-header-1'));
    final q1Focus = Focus.of(
      tester.element(
        find.descendant(of: q1Header, matching: find.byType(Text)).first,
      ),
    );
    q1Focus.requestFocus();
    await tester.pump();
    expect(q1Focus.hasFocus, isTrue);

    change(() => focused = 2);
    await tester.pump();
    expect(q1Focus.hasFocus, isFalse);
    q1Focus.requestFocus();
    await tester.pump();
    expect(q1Focus.hasFocus, isFalse);
    expect(
      identical(q1State, tester.state(find.byKey(const ValueKey('q-pane-1')))),
      isTrue,
    );
    await tester.pumpAndSettle();
    expect(focused, 2);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(focused, 2);

    final q1CardFocus = Focus.of(tester.element(find.descendant(
      of: find.byKey(const ValueKey('focus-card-1')),
      matching: find.byType(Text),
    ).last));
    q1CardFocus.requestFocus();
    await tester.pump();
    expect(q1CardFocus.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(focused, 1);

    change(() => focused = 3);
    await tester.pump(const Duration(milliseconds: 50));
    change(() => focused = null);
    await tester.pumpAndSettle();
    q1Focus.requestFocus();
    await tester.pump();
    expect(q1Focus.hasFocus, isTrue);
    expect(
      identical(q1State, tester.state(find.byKey(const ValueKey('q-pane-1')))),
      isTrue,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
  });

  testWidgets('OS13: canceling exit keeps a draft and GlobalKey State', (
    tester,
  ) async {
    final draftKey = GlobalKey<_DraftRowState>();
    var exiting = false;
    late StateSetter change;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, set) {
            change = set;
            return Scaffold(
              body: ExitingRow(
                exiting: exiting,
                child: _DraftRow(key: draftKey),
              ),
            );
          },
        ),
      ),
    );
    final originalState = draftKey.currentState;
    await tester.enterText(find.byType(TextField), 'unfinished draft');
    await tester.pump();
    change(() => exiting = true);
    await tester.pump();
    expect(draftKey.currentState, same(originalState));
    expect(draftKey.currentState!.focusNode.hasFocus, isFalse);
    change(() => exiting = false);
    await tester.pump();
    expect(draftKey.currentState, same(originalState));
    expect(find.text('unfinished draft'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _EscapeIntent extends Intent {
  const _EscapeIntent();
}

class _DraftRow extends StatefulWidget {
  const _DraftRow({super.key});

  @override
  State<_DraftRow> createState() => _DraftRowState();
}

class _DraftRowState extends State<_DraftRow> {
  final focusNode = FocusNode();
  final controller = TextEditingController();

  @override
  void dispose() {
    focusNode.dispose();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      TextField(focusNode: focusNode, controller: controller);
}
