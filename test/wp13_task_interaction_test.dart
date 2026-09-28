import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/storage.dart';
import 'package:matrixflow_native/widgets/input_sheet.dart';
import 'package:matrixflow_native/widgets/task_detail_panel.dart';
import 'package:matrixflow_native/widgets/task_edit_draft.dart';
import 'package:matrixflow_native/widgets/task_tags_editor.dart';

Future<Store> _store() async {
  SharedPreferences.setMockInitialValues({
    'matrixflow-has-seen-onboarding': true,
  });
  final store = Store();
  await store.init();
  return store;
}

Widget _host(Store store, Widget body) => ChangeNotifierProvider.value(
  value: store,
  child: MaterialApp(home: Scaffold(body: body)),
);

Future<void> _finish(WidgetTester tester, Store store) async {
  await tester.pumpWidget(const SizedBox.shrink());
  store.dispose();
  await tester.pump();
}

void main() {
  test('tag draft keeps concurrent additions and restores on cancel', () {
    final opened = Task(
      id: 'tagged',
      boardId: '',
      title: 'Plan',
      quadrant: qDo,
      createdAt: 0,
      tags: ['original'],
    );
    final draft = TaskEditDraft(opened, onChanged: () {});
    draft.tags = ['local'];
    expect(draft.isDirty, isTrue);
    final concurrent = Task.fromJson(opened.toJson())
      ..tags = ['original', 'remote']
      ..notesMarkdown = 'saved elsewhere';
    final merged = draft.applyTo(concurrent);
    expect(merged.tags, ['remote', 'local']);
    expect(merged.notesMarkdown, 'saved elsewhere');
    draft.load(opened);
    expect(draft.tags, ['original']);
    expect(draft.isDirty, isFalse);
    draft.dispose();
  });

  testWidgets('detail uses the real tag editor and shows saved tags', (
    tester,
  ) async {
    final store = await _store();
    final task = store.newTask('Tagged work')..tags = ['planning'];
    store.addTasks([task]);
    await tester.pumpWidget(_host(store, TaskDetailPanel(task: task)));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('task-tags-summary')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('more-properties-btn')));
    await tester.pumpAndSettle();
    expect(find.byType(TaskTagsEditor), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('task-tag-input')));
    await tester.enterText(
      find.byKey(const ValueKey('task-tag-input')),
      'release',
    );
    await tester.tap(find.byKey(const ValueKey('task-tag-add')));
    await tester.pump();
    expect(find.text('release'), findsWidgets);
    expect(store.tasks.single.tags, ['planning']);
    await tester.tap(find.byKey(const ValueKey('save-task')));
    await tester.runAsync(() => store.flush(waitForReminders: false));
    await tester.pump();
    expect(store.tasks.single.tags, ['planning', 'release']);
    await _finish(tester, store);
  });

  testWidgets('failed write keeps the input draft and retry saves once', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'matrixflow-has-seen-onboarding': true,
    });
    final prefs = await SharedPreferences.getInstance();
    var rejectPointer = false;
    final store = Store(
      reminders: InMemoryReminderService(),
      saveWriter: (key, value) async {
        if (rejectPointer && key == SaveProtocol.pointerKey) return false;
        return prefs.setString(key, value);
      },
    );
    await store.init();
    await store.flush();
    await tester.pumpWidget(
      _host(
        store,
        const InputSheet(initialMode: InputModePref.single, embedded: true),
      ),
    );
    rejectPointer = true;
    final row = find.byKey(const ValueKey('task-step-0'));
    await tester.enterText(row, 'retry this task');
    await tester.tap(find.byKey(const ValueKey('submit-tasks')));
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      if (find.text(store.t['storageWriteError']!).evaluate().isNotEmpty) break;
    }
    expect(find.text(store.t['storageWriteError']!), findsWidgets);
    expect(tester.widget<TextField>(row).controller!.text, 'retry this task');
    expect(store.tasks, hasLength(1));

    rejectPointer = false;
    await tester.tap(find.byKey(const ValueKey('submit-tasks')));
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      if (tester.widget<TextField>(row).controller!.text.isEmpty) break;
    }
    expect(tester.widget<TextField>(row).controller!.text, isEmpty);
    expect(store.tasks, hasLength(1));
    expect(store.persistenceError, isNull);
    await _finish(tester, store);
  });

  testWidgets('one row saves a plain task without a parent title', (
    tester,
  ) async {
    final store = await _store();
    await tester.pumpWidget(
      _host(
        store,
        const InputSheet(initialMode: InputModePref.single, embedded: true),
      ),
    );
    await tester.enterText(find.byKey(const ValueKey('task-step-0')), '买牛奶');
    await tester.tap(find.byKey(const ValueKey('submit-tasks')));
    await tester.pumpAndSettle();
    expect(store.tasks, hasLength(1));
    expect(store.tasks.single.title, '买牛奶');
    expect(store.tasks.single.subtasks, isEmpty);
    await _finish(tester, store);
  });

  testWidgets('Enter adds a step, keeps the first item and omits blank rows', (
    tester,
  ) async {
    final store = await _store();
    await tester.pumpWidget(
      _host(
        store,
        const InputSheet(initialMode: InputModePref.single, embedded: true),
      ),
    );
    final first = find.byKey(const ValueKey('task-step-0'));
    await tester.enterText(first, '写方案');
    await tester.showKeyboard(first);
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('task-step-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('parent-title')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('parent-title')), '新项目');
    await tester.enterText(find.byKey(const ValueKey('task-step-1')), '联调');
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('submit-tasks')));
    await tester.pumpAndSettle();
    expect(store.tasks, hasLength(1));
    expect(store.tasks.single.title, '新项目');
    expect(store.tasks.single.subtasks.map((s) => s.title), ['写方案', '联调']);
    await _finish(tester, store);
  });

  testWidgets('pasted lines follow the selected mode', (tester) async {
    final store = await _store();
    await tester.pumpWidget(
      _host(
        store,
        const InputSheet(initialMode: InputModePref.single, embedded: true),
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey('task-step-0')),
      '第一步\n\n第二步',
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('task-step-2')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('submit-tasks')));
    await tester.pumpAndSettle();
    expect(store.tasks.single.subtasks.map((s) => s.title), ['第一步', '第二步']);

    await tester.tap(find.byKey(const ValueKey('batch-mode')));
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('task-input')), '甲\n\n乙');
    await tester.tap(find.byKey(const ValueKey('submit-tasks')));
    await tester.pumpAndSettle();
    expect(store.tasks, hasLength(3));
    expect(
      store.tasks.where((task) => task.subtasks.isEmpty).map((t) => t.title),
      containsAll(['甲', '乙']),
    );
    await _finish(tester, store);
  });

  testWidgets('middle caret, IME composition and blank-row backspace', (
    tester,
  ) async {
    final store = await _store();
    await tester.pumpWidget(
      _host(
        store,
        const InputSheet(initialMode: InputModePref.single, embedded: true),
      ),
    );
    final first = find.byKey(const ValueKey('task-step-0'));
    await tester.enterText(first, '开始结束');
    await tester.showKeyboard(first);
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '开始\n结束',
        selection: TextSelection.collapsed(offset: 3),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(first).controller!.text, '开始');
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('task-step-1')))
          .controller!
          .text,
      '结束',
    );

    final second = find.byKey(const ValueKey('task-step-1'));
    await tester.showKeyboard(second);
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '日本語',
        selection: TextSelection.collapsed(offset: 3),
        composing: TextRange(start: 0, end: 3),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('submit-tasks')));
    await tester.pump();
    expect(store.tasks, isEmpty);
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pump();
    expect(find.byKey(const ValueKey('task-step-2')), findsNothing);
    await tester.showKeyboard(second);
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '日本語',
        selection: TextSelection.collapsed(offset: 3),
        composing: TextRange(start: 3, end: 3),
      ),
    );
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('task-step-2')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('task-step-2')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('submit-tasks')));
    await tester.pumpAndSettle();
    expect(store.tasks.single.subtasks.map((s) => s.title), ['开始', '日本語']);
    await _finish(tester, store);
  });

  testWidgets('time cancel and long notes keep the main draft', (tester) async {
    final store = await _store();
    final task = store.newTask('旧标题\n保留原样')
      ..notesMarkdown = List.filled(30, '备注').join('\n')
      ..subtasks = [SubTask(id: 'child', title: '步骤')];
    store.addTasks([task]);
    await tester.pumpWidget(_host(store, TaskDetailPanel(task: task)));
    await tester.pumpAndSettle();
    expect(find.text('旧标题\n保留原样'), findsOneWidget);
    expect(find.byKey(const ValueKey('subtask-item-child')), findsOneWidget);
    expect(find.byKey(const ValueKey('edit-notes')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('edit-notes-entry')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('edit-notes')))
          .controller!
          .text,
      task.notesMarkdown,
    );
    await tester.tap(find.text(store.t['cancel']!).last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('edit-time-btn')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('deadline-tomorrow')));
    await tester.tap(find.text(store.t['cancel']!).last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('save-task')));
    await tester.pumpAndSettle();
    expect(store.tasks.single.deadline, isNull);
    expect(store.tasks.single.notesMarkdown, task.notesMarkdown);
    expect(store.tasks.single.title, '旧标题\n保留原样');
    await _finish(tester, store);
  });

  testWidgets('412 dp dark layout at 200% text keeps task actions usable', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(412, 915));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = await _store();
    Widget scaled(Widget body) => ChangeNotifierProvider.value(
      value: store,
      child: MaterialApp(
        theme: ThemeData.dark(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(body: body),
      ),
    );
    await tester.pumpWidget(
      scaled(
        const InputSheet(initialMode: InputModePref.single, embedded: true),
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey('task-step-0')),
      '第一步\n第二步',
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('submit-tasks')), findsOneWidget);

    final task = store.newTask('父任务')
      ..notesMarkdown = List.filled(20, '长备注').join('\n')
      ..subtasks = [SubTask(id: 'one', title: '子步骤')]
      ..tags = ['release'];
    store.addTasks([task]);
    await tester.pumpWidget(scaled(TaskDetailPanel(task: task)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('save-task')), findsOneWidget);
    expect(find.byKey(const ValueKey('subtask-item-one')), findsOneWidget);
    await _finish(tester, store);
  });
}
