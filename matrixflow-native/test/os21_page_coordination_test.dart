import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrixflow_native/ai_service.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/screens/completed_screen.dart';
import 'package:matrixflow_native/screens/matrix_screen.dart';
import 'package:matrixflow_native/screens/search_screen.dart';
import 'package:matrixflow_native/screens/settings_screen.dart';
import 'package:matrixflow_native/storage.dart';
import 'package:matrixflow_native/ui/platform_ui_policy.dart';
import 'package:matrixflow_native/widgets/date_edit_fields.dart';
import 'package:matrixflow_native/widgets/task_detail_panel.dart';
import 'package:matrixflow_native/widgets/task_edit_draft.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// OS21 / F18: pages orchestrate display and input only. These cover the
/// ownership that moved out of the widgets — the edit draft, the detail session
/// shared by the three pages, the subtask dialog's controllers, and the
/// settings model-list request once the page is gone.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('edit draft owns its own dirty and save rules', () {
    test('a save keeps whatever the Store changed for fields left alone', () {
      final loaded = _task(notesMarkdown: 'old notes');
      final draft = TaskEditDraft(loaded, onChanged: () {});
      draft.titleController.text = 'Renamed here';

      final live = _task(
        notesMarkdown: 'written from a list',
      )..completed = true;
      final saved = draft.applyTo(live);

      expect(saved.title, 'Renamed here');
      expect(saved.notesMarkdown, 'written from a list');
      expect(saved.completed, isTrue);
      draft.dispose();
    });

    test('putting every field back leaves nothing to discard', () {
      final loaded = _task(deadline: endOfCivilDayMs(DateTime(2030, 5, 6)));
      final draft = TaskEditDraft(loaded, onChanged: () {});
      expect(draft.isDirty, isFalse);

      draft.titleController.text = 'Edited';
      draft.quadrant = qPlan;
      draft.reminderAt = 123456;
      expect(draft.isDirty, isTrue);

      draft.titleController.text = loaded.title;
      draft.quadrant = loaded.quadrant;
      draft.reminderAt = loaded.reminderAt;
      expect(draft.isDirty, isFalse);
      draft.dispose();
    });

    test('a child completed elsewhere survives a draft that edited its sibling',
        () {
      final loaded = _task(subtasks: [
        SubTask(id: 's1', title: 'Untouched'),
        SubTask(id: 's2', title: 'Touched'),
      ]);
      final draft = TaskEditDraft(loaded, onChanged: () {});
      draft.subtasks.firstWhere((sub) => sub.id == 's2').title = 'Renamed';

      final live = _task(subtasks: [
        SubTask(id: 's1', title: 'Untouched', completed: true, completedAt: 7),
        SubTask(id: 's2', title: 'Touched'),
      ]);
      final merged = draft.applyTo(live).subtasks;

      expect(merged.firstWhere((sub) => sub.id == 's1').completed, isTrue);
      expect(merged.firstWhere((sub) => sub.id == 's1').completedAt, 7);
      expect(merged.firstWhere((sub) => sub.id == 's2').title, 'Renamed');
      draft.dispose();
    });

    test('a close that was already decided stops looking like a draft', () {
      final loaded = _task();
      var changes = 0;
      final draft = TaskEditDraft(loaded, onChanged: () => changes++);

      draft.titleController.text = 'Edited';
      expect(draft.isDirty, isTrue);
      expect(changes, 1);

      draft.markDiscarding();
      expect(draft.isDirty, isFalse);
      draft.load(_task(title: 'Next task'));
      expect(draft.isDirty, isFalse);
      draft.titleController.text = 'Edited again';
      expect(draft.isDirty, isTrue);
      draft.dispose();
    });

    test('the subtask composer hands over a row and clears itself', () {
      final draft = TaskEditDraft(_task(), onChanged: () {});
      expect(draft.takeNewSubtask(), isNull);

      draft.newSubtaskController.text = '  A child  ';
      final added = draft.takeNewSubtask();
      expect(added!.title, 'A child');
      expect(draft.subtasks.single.title, 'A child');
      expect(draft.newSubtaskController.text, isEmpty);
      expect(draft.isDirty, isTrue);
      draft.dispose();
    });
  });

  group('detail editing commits only finished input', () {
    testWidgets('Ctrl+Enter during composition waits, then saves', (
      tester,
    ) async {
      final store = await _store([_seed('Alpha')]);
      var closed = false;
      await _surface(tester, const Size(1200, 1600));
      await tester.pumpWidget(
        _panelHost(
          store,
          TaskDetailPanel(
            task: store.tasks.single,
            onClose: () => closed = true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.showKeyboard(find.byKey(const ValueKey('edit-title')));
      final title = _controller(tester, 'edit-title');
      const composing = '输入中';
      title.value = TextEditingValue(
        text: composing,
        selection: const TextSelection.collapsed(offset: 3),
        composing: const TextRange(start: 0, end: 3),
      );
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('save-task')));
      await tester.pumpAndSettle();
      await _sendCtrlEnter(tester);
      expect(store.tasks.single.title, 'Alpha');
      expect(closed, isFalse);

      title.value = const TextEditingValue(
        text: composing,
        selection: TextSelection.collapsed(offset: 3),
      );
      await tester.pump();
      await _sendCtrlEnter(tester);
      await tester.pumpAndSettle();
      expect(store.tasks.single.title, composing);
      expect(closed, isTrue);
      await _finish(tester, store);
    });

    testWidgets('repeated subtask dialogs release their text controllers', (
      tester,
    ) async {
      final store = await _store([
        _seed('Alpha')
          ..subtasks = [SubTask(id: 'child-1', title: 'Child')],
      ]);
      await _surface(tester, const Size(1200, 1600));
      await tester.pumpWidget(
        _panelHost(store, TaskDetailPanel(task: store.tasks.single)),
      );
      await tester.pumpAndSettle();

      for (var round = 0; round < 3; round++) {
        await _openChildDialog(tester, 'child-1');
        final title = _controller(tester, 'subtask-edit-title');
        final notes = _controller(tester, 'subtask-edit-notes');
        await tester.tap(find.byKey(const ValueKey('subtask-cancel-btn')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('subtask-edit-title')),
          findsNothing,
          reason: 'round $round',
        );
        // Touching a released notifier is a debug-mode error, which is how
        // this pins down that the dialog let go of both fields.
        expect(
          () => title.addListener(_noop),
          throwsA(isA<Error>()),
          reason: 'round $round',
        );
        expect(
          () => notes.addListener(_noop),
          throwsA(isA<Error>()),
          reason: 'round $round',
        );
      }
      expect(tester.takeException(), isNull);
      expect(store.tasks.single.subtasks.single.title, 'Child');
      await _finish(tester, store);
    });

    testWidgets('a saved child edit is what the next dialog shows', (
      tester,
    ) async {
      final store = await _store([
        _seed('Alpha')
          ..subtasks = [SubTask(id: 'child-1', title: 'Child')],
      ]);
      await _surface(tester, const Size(1200, 1600));
      await tester.pumpWidget(
        _panelHost(store, TaskDetailPanel(task: store.tasks.single)),
      );
      await tester.pumpAndSettle();

      await _openChildDialog(tester, 'child-1');
      await tester.enterText(
        find.byKey(const ValueKey('subtask-edit-title')),
        'Renamed child',
      );
      await tester.tap(find.byKey(const ValueKey('subtask-save-btn')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('save-task')));
      await tester.pumpAndSettle();
      expect(store.tasks.single.subtasks.single.title, 'Renamed child');

      await tester.pumpWidget(
        _panelHost(store, TaskDetailPanel(task: store.tasks.single)),
      );
      await tester.pumpAndSettle();
      await _openChildDialog(tester, 'child-1');
      expect(_controller(tester, 'subtask-edit-title').text, 'Renamed child');
      await tester.tap(find.byKey(const ValueKey('subtask-cancel-btn')));
      await tester.pumpAndSettle();
      await _finish(tester, store);
    });
  });

  group('every page hosts the detail the same way', () {
    testWidgets('search and completed match the main screen width rule', (
      tester,
    ) async {
      for (final width in [1400.0, 900.0]) {
        final expected = PlatformUiPolicy(
          platform: TargetPlatform.windows,
        ).canShowSideDetail(width);
        final hosts = {
          'matrix': (Store store) => const MatrixHome(),
          'search': (Store store) => const SearchScreen(),
          'completed': (Store store) => const CompletedScreen(),
        };
        for (final entry in hosts.entries) {
          final store = await _store([_seed('Alpha')]);
          if (entry.key == 'completed') {
            store.tasks.single.completed = true;
            store.notifyListeners();
          }
          await _surface(tester, Size(width, 1200));
          await tester.pumpWidget(_host(store, entry.value(store)));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Alpha').first);
          await tester.pumpAndSettle();

          final panel = find.byType(TaskDetailPanel);
          expect(panel, findsOneWidget, reason: entry.key);
          final shown = tester.getSize(panel).width;
          expect(
            shown > PlatformUiPolicy.sideDetailWidth,
            isNot(expected),
            reason: '${entry.key} at $width',
          );
          if (expected) {
            expect(shown, PlatformUiPolicy.sideDetailWidth, reason: entry.key);
          }
          await _finish(tester, store);
        }
      }
    });

    testWidgets('switching rows in search asks before dropping a draft', (
      tester,
    ) async {
      final store = await _store([_seed('Alpha'), _seed('Beta')]);
      await _surface(tester, const Size(1400, 1200));
      await tester.pumpWidget(_host(store, const SearchScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Alpha').first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('edit-title')), 'draft');
      await tester.pump();
      await tester.tap(find.text('Beta').first);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.tap(find.text('Keep Editing'));
      await tester.pumpAndSettle();
      expect(
        _controller(tester, 'edit-title').text,
        'draft',
        reason: 'the draft stays where it was',
      );

      await tester.tap(find.text('Beta').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(_controller(tester, 'edit-title').text, 'Beta');
      expect(
        store.tasks.firstWhere((task) => task.id == 'alpha').title,
        'Alpha',
      );
      await _finish(tester, store);
    });
  });

  group('settings requests end with the page', () {
    testWidgets('a reply that lands after the page is gone changes nothing', (
      tester,
    ) async {
      final gates = <Completer<http.Response>>[];
      final service = AIService(
        client: MockClient((request) async {
          final gate = Completer<http.Response>();
          gates.add(gate);
          return gate.future;
        }),
      );
      addTearDown(service.close);
      final store = await _store([], aiService: service);
      await _surface(tester, const Size(900, 2400));
      await tester.pumpWidget(_host(store, _pushSettings()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open settings'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('api-key-input')),
        'synthetic-value',
      );
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(gates, hasLength(1));

      await tester.pageBack();
      await tester.pumpAndSettle();
      gates.first.complete(_modelsNamed('late-model'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('late-model'), findsNothing);
      await _finish(tester, store);
    });
  });
}

Widget _pushSettings() => Builder(
  builder:
      (context) => Scaffold(
        body: TextButton(
          onPressed:
              () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const SettingsScreen(),
                ),
              ),
          child: const Text('Open settings'),
        ),
      ),
);

Task _seed(String title) => Task(
  id: title.toLowerCase(),
  boardId: 'board-default',
  title: title,
  quadrant: qDo,
  createdAt: 1,
);

Task _task({
  String title = 'Alpha',
  String? notesMarkdown,
  int? deadline,
  List<SubTask> subtasks = const [],
}) => Task(
  id: 't1',
  boardId: 'b',
  title: title,
  quadrant: qDo,
  createdAt: 1,
  notesMarkdown: notesMarkdown,
  deadline: deadline,
  subtasks: subtasks,
);

http.Response _modelsNamed(String id) => http.Response(
  jsonEncode({
    'data': [
      {'id': id},
    ],
  }),
  200,
);

Future<Store> _store(List<Task> tasks, {AIService? aiService}) async {
  SharedPreferences.setMockInitialValues({
    'matrixflow-has-seen-onboarding': true,
  });
  final store = Store(aiService: aiService);
  await store.init();
  for (final task in tasks) {
    task.boardId = store.activeBoardId;
  }
  store.addTasks(tasks);
  return store;
}

Widget _host(Store store, Widget child) => ChangeNotifierProvider.value(
  value: store,
  child: MaterialApp(locale: const Locale('en'), home: child),
);

/// A bare editor needs a Scaffold ancestor, which the pages bring themselves.
Widget _panelHost(Store store, Widget editor) => _host(
  store,
  Scaffold(body: editor),
);

Future<void> _surface(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

Future<void> _finish(WidgetTester tester, Store store) async {
  // Disposing here rather than in a tearDown: the store's deadline timer is
  // still pending when the framework checks for leaks otherwise.
  await tester.pumpWidget(const SizedBox.shrink());
  store.dispose();
  await tester.pump();
}

Future<void> _sendCtrlEnter(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
}

Future<void> _openChildDialog(WidgetTester tester, String childId) async {
  final row = find.byKey(ValueKey('subtask-item-$childId'));
  await tester.ensureVisible(row);
  await tester.tap(row);
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('subtask-edit-title')), findsOneWidget);
}

void _noop() {}

TextEditingController _controller(WidgetTester tester, String key) =>
    tester.widget<TextField>(find.byKey(ValueKey(key))).controller!;
