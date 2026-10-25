import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:compoise/models.dart';
import 'package:compoise/storage.dart';
import 'package:compoise/widgets/input_sheet.dart';

/// Unsent text in the add-task sheet survives a tap outside the sheet, is
/// cleared after the task is added, and survives an app restart.
void main() {
  Future<Store> makeStore([Map<String, Object> extra = const {}]) async {
    SharedPreferences.setMockInitialValues({
      'compoise-has-seen-onboarding': true,
      ...extra,
    });
    final store = Store(reminders: InMemoryReminderService());
    await store.init();
    return store;
  }

  Widget host(Store store) => ChangeNotifierProvider.value(
    value: store,
    child: MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              key: const ValueKey('open'),
              onPressed: () => showModalBottomSheet<List<Task>>(
                context: context,
                isScrollControlled: true,
                builder: (_) => ChangeNotifierProvider.value(
                  value: store,
                  child: const InputSheet(initialMode: InputModePref.single),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );

  final step = find.byKey(const ValueKey('task-step-0'));

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('open')));
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
  }

  Future<void> tapOutside(WidgetTester tester) async {
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  }

  String stepText(WidgetTester tester) =>
      tester.widget<TextField>(step).controller!.text;

  Future<void> finish(WidgetTester tester, Store store) async {
    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
    await tester.pump();
  }

  testWidgets('tap outside keeps the text for next time', (tester) async {
    final store = await makeStore();
    await tester.pumpWidget(host(store));
    await open(tester);
    await tester.enterText(step, '写周报');
    await tapOutside(tester);
    expect(find.byType(InputSheet), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(InputDraft.key), '写周报');
    await open(tester);
    expect(stepText(tester), '写周报');
    expect(store.tasks, isEmpty);
    await finish(tester, store);
  });

  testWidgets('a successful add clears the draft', (tester) async {
    final store = await makeStore();
    await tester.pumpWidget(host(store));
    await open(tester);
    await tester.enterText(step, '买牛奶');
    await tester.tap(find.byKey(const ValueKey('submit-tasks')));
    for (
      var i = 0;
      i < 20 && find.byType(InputSheet).evaluate().isNotEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
    expect(store.tasks.single.title, '买牛奶');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(InputDraft.key), isNull);
    await open(tester);
    expect(stepText(tester), isEmpty);
    await finish(tester, store);
  });

  testWidgets('clearing the text stores nothing', (tester) async {
    final store = await makeStore({InputDraft.key: '旧草稿'});
    await tester.pumpWidget(host(store));
    await open(tester);
    expect(stepText(tester), '旧草稿');
    await tester.enterText(step, '');
    await tapOutside(tester);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(InputDraft.key), isNull);
    await finish(tester, store);
  });

  testWidgets('draft survives a store reload and is not in backups', (
    tester,
  ) async {
    final store = await makeStore({InputDraft.key: '给妈妈打电话'});
    expect(store.exportJson(), isNot(contains('给妈妈打电话')));
    await tester.pumpWidget(host(store));
    await open(tester);
    expect(stepText(tester), '给妈妈打电话');
    await finish(tester, store);
  });

  testWidgets('Enter in a step keeps the keyboard up', (tester) async {
    final store = await makeStore();
    await tester.pumpWidget(host(store));
    await open(tester);
    await tester.enterText(step, '写方案');
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.textInput,
      (call) async {
        calls.add(call.method);
        return null;
      },
    );
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pumpAndSettle();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.textInput,
      null,
    );
    expect(find.byKey(const ValueKey('task-step-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('parent-title')), findsOneWidget);
    final second = tester.widget<TextField>(
      find.byKey(const ValueKey('task-step-1')),
    );
    expect(second.focusNode!.hasFocus, isTrue);
    expect(calls, isNot(contains('TextInput.hide')));
    await finish(tester, store);
  });
}
