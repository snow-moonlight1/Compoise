import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/storage.dart';
import 'package:matrixflow_native/widgets/task_detail_panel.dart';
import 'package:matrixflow_native/widgets/task_edit_draft.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// RF07: what counts as unfinished text input, and what happens to a subtask
/// that was typed but never added.
///
/// The IME rules came from review probe RF-R05, which stays in
/// `test/review/os_final_review_probe.dart` and is migrated here as the default
/// regression. The composer lifecycle is the scenario the review asked for:
/// text in the "add subtask" row when the editor saves, closes, switches task
/// or deletes.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('only an open composition counts as unfinished input', () {
    bool pending(TextRange composing) {
      final controller = TextEditingController.fromValue(
        TextEditingValue(
          text: '已完成输入',
          selection: const TextSelection.collapsed(offset: 5),
          composing: composing,
        ),
      );
      addTearDown(controller.dispose);
      return hasPendingImeComposition(controller);
    }

    test('RF-R05 finished input leaves a collapsed range, not a composition', () {
      expect(pending(const TextRange(start: 5, end: 5)), isFalse);
      expect(pending(const TextRange(start: 0, end: 0)), isFalse);
    });

    test('an absent composition never holds a commit back', () {
      expect(pending(TextRange.empty), isFalse);
    });

    test('a range that still holds text is an open composition', () {
      expect(pending(const TextRange(start: 0, end: 3)), isTrue);
      expect(pending(const TextRange(start: 2, end: 5)), isTrue);
    });
  });

  group('a typed-but-not-added subtask belongs to the draft', () {
    test('typing without pressing add makes the draft dirty', () {
      final draft = TaskEditDraft(_task(), onChanged: () {});
      expect(draft.isDirty, isFalse);

      draft.newSubtaskController.text = '买牛奶';
      expect(draft.hasPendingSubtask, isTrue);
      expect(draft.isDirty, isTrue);
      draft.dispose();
    });

    test('the composer reports through the same callback as the fields', () {
      var changes = 0;
      final draft = TaskEditDraft(_task(), onChanged: () => changes++);
      draft.newSubtaskController.text = 'Add milk';
      expect(changes, 1);
      draft.dispose();
    });

    test('whitespace in the composer is not something to keep', () {
      final draft = TaskEditDraft(_task(), onChanged: () {});
      draft.newSubtaskController.text = '   ';
      expect(draft.hasPendingSubtask, isFalse);
      expect(draft.isDirty, isFalse);
      expect(draft.takeNewSubtask(), isNull);
      draft.dispose();
    });

    test('switching to another task drops the previous composer, quietly', () {
      var changes = 0;
      final draft = TaskEditDraft(
        _task(title: 'Alpha'),
        onChanged: () => changes++,
      );
      draft.newSubtaskController.text = 'belongs to Alpha';
      expect(changes, 1);

      draft.load(_task(title: 'Beta'));
      expect(draft.newSubtaskController.text, isEmpty);
      expect(draft.hasPendingSubtask, isFalse);
      expect(draft.isDirty, isFalse);
      // Only the user's own keystroke was reported: refilling the fields for the
      // next task must not look like an edit to it.
      expect(changes, 1);
      draft.dispose();
    });

    test('a discarded draft stops counting the composer as a change', () {
      final draft = TaskEditDraft(_task(), onChanged: () {});
      draft.newSubtaskController.text = 'A child';
      draft.markDiscarding();
      expect(draft.isDirty, isFalse);
      draft.dispose();
    });

    test('the flushed composer row still merges field by field', () {
      final draft = TaskEditDraft(
        _task(
          notesMarkdown: 'old notes',
          subtasks: [SubTask(id: 's1', title: 'Untouched')],
        ),
        onChanged: () {},
      );
      draft.newSubtaskController.text = 'A child';
      draft.titleController.text = 'Renamed here';
      expect(draft.takeNewSubtask(), isNotNull);

      final live = _task(
        notesMarkdown: 'written from a list',
        subtasks: [
          SubTask(
            id: 's1',
            title: 'Untouched',
            completed: true,
            completedAt: 7,
          ),
        ],
      );
      final saved = draft.applyTo(live);

      expect(saved.title, 'Renamed here');
      expect(
        saved.notesMarkdown,
        'written from a list',
        reason: 'a field the draft never touched follows the Store',
      );
      expect(saved.subtasks, hasLength(2));
      expect(saved.subtasks.firstWhere((sub) => sub.id == 's1').completed, isTrue);
      expect(
        saved.subtasks.firstWhere((sub) => sub.id == 's1').completedAt,
        7,
      );
      expect(
        saved.subtasks.firstWhere((sub) => sub.id != 's1').title,
        'A child',
      );
      draft.dispose();
    });
  });

  group('commit paths respect the composition state', () {
    testWidgets('a finished Chinese title saves without another key press', (
      tester,
    ) async {
      final store = await _store([_seed('Alpha')]);
      var closed = false;
      await _surface(tester, const Size(1200, 1600));
      await _showEditor(tester, store, onClose: () => closed = true);

      final title = _controller(tester, 'edit-title');
      await tester.showKeyboard(find.byKey(const ValueKey('edit-title')));
      // What a CJK keyboard leaves behind once the candidate is accepted.
      title.value = const TextEditingValue(
        text: '已完成输入',
        selection: TextSelection.collapsed(offset: 5),
        composing: TextRange(start: 5, end: 5),
      );
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('save-task')));
      await tester.pumpAndSettle();
      expect(store.tasks.single.title, '已完成输入');
      expect(closed, isTrue);
      await _finish(tester, store);
    });

    testWidgets('an open composition still holds the save back', (tester) async {
      final store = await _store([_seed('Alpha')]);
      var closed = false;
      await _surface(tester, const Size(1200, 1600));
      await _showEditor(tester, store, onClose: () => closed = true);

      final title = _controller(tester, 'edit-title');
      await tester.showKeyboard(find.byKey(const ValueKey('edit-title')));
      title.value = const TextEditingValue(
        text: '输入中',
        selection: TextSelection.collapsed(offset: 3),
        composing: TextRange(start: 0, end: 3),
      );
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('save-task')));
      await tester.pumpAndSettle();
      expect(store.tasks.single.title, 'Alpha');
      expect(closed, isFalse);

      // The platform closing the composition is enough: the same tap now saves.
      title.value = const TextEditingValue(
        text: '输入中',
        selection: TextSelection.collapsed(offset: 3),
        composing: TextRange(start: 3, end: 3),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('save-task')));
      await tester.pumpAndSettle();
      expect(store.tasks.single.title, '输入中');
      expect(closed, isTrue);
      await _finish(tester, store);
    });

    testWidgets('the composer adds a finished Japanese subtask', (tester) async {
      final store = await _store([_seed('Alpha')]);
      await _surface(tester, const Size(1200, 1600));
      await _showEditor(tester, store);

      final composer = _controller(tester, 'edit-new-subtask');
      await tester.showKeyboard(find.byKey(const ValueKey('edit-new-subtask')));
      composer.value = const TextEditingValue(
        text: '牛乳を買う',
        selection: TextSelection.collapsed(offset: 5),
        composing: TextRange(start: 5, end: 5),
      );
      await tester.pump();
      await tester.ensureVisible(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();
      expect(composer.text, isEmpty, reason: 'add takes the row over');
      expect(store.tasks.single.subtasks, isEmpty);

      await tester.tap(find.byKey(const ValueKey('save-task')));
      await tester.pumpAndSettle();
      expect(store.tasks.single.subtasks.single.title, '牛乳を買う');
      await _finish(tester, store);
    });

    testWidgets('Enter adds the composer text once nothing is composing', (
      tester,
    ) async {
      final store = await _store([_seed('Alpha')]);
      await _surface(tester, const Size(1200, 1600));
      await _showEditor(tester, store);

      await tester.enterText(
        find.byKey(const ValueKey('edit-new-subtask')),
        'Add milk',
      );
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(
        _controller(tester, 'edit-new-subtask').text,
        isEmpty,
        reason: 'Enter adds the row and empties the composer',
      );

      await tester.tap(find.byKey(const ValueKey('save-task')));
      await tester.pumpAndSettle();
      expect(store.tasks.single.subtasks.single.title, 'Add milk');
      await _finish(tester, store);
    });

    testWidgets('an open composition in the composer blocks every commit', (
      tester,
    ) async {
      final store = await _store([_seed('Alpha')]);
      var closed = false;
      await _surface(tester, const Size(1200, 1600));
      await _showEditor(tester, store, onClose: () => closed = true);

      final composer = _controller(tester, 'edit-new-subtask');
      await tester.showKeyboard(find.byKey(const ValueKey('edit-new-subtask')));
      composer.value = const TextEditingValue(
        text: 'gounyuu',
        selection: TextSelection.collapsed(offset: 7),
        composing: TextRange(start: 0, end: 7),
      );
      await tester.pump();
      await tester.ensureVisible(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();
      expect(composer.text, 'gounyuu');

      await tester.tap(find.byKey(const ValueKey('save-task')));
      await tester.pumpAndSettle();
      expect(store.tasks.single.subtasks, isEmpty);
      expect(
        store.tasks.single.title,
        'Alpha',
        reason: 'raw pinyin is never written and a blocked save stays open',
      );
      expect(closed, isFalse);
      await _finish(tester, store);
    });

    testWidgets('the child editor waits for its notes field too', (
      tester,
    ) async {
      final store = await _store([
        _seed('Alpha')..subtasks = [SubTask(id: 'child-1', title: 'Child')],
      ]);
      await _surface(tester, const Size(1200, 1600));
      await _showEditor(tester, store);
      final row = find.byKey(const ValueKey('subtask-item-child-1'));
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      await tester.tap(row);
      await tester.pumpAndSettle();

      final notes = _controller(tester, 'subtask-edit-notes');
      await tester.showKeyboard(
        find.byKey(const ValueKey('subtask-edit-notes')),
      );
      notes.value = const TextEditingValue(
        text: 'gounyuu',
        selection: TextSelection.collapsed(offset: 7),
        composing: TextRange(start: 0, end: 7),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('subtask-save-btn')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('subtask-edit-title')),
        findsOneWidget,
        reason: 'the dialog stays open while the notes are still composing',
      );

      notes.value = const TextEditingValue(
        text: '牛乳を買う',
        selection: TextSelection.collapsed(offset: 5),
        composing: TextRange(start: 5, end: 5),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('subtask-save-btn')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('save-task')));
      await tester.pumpAndSettle();
      expect(store.tasks.single.subtasks.single.notesMarkdown, '牛乳を買う');
      await _finish(tester, store);
    });
  });

  group('closing with only a typed subtask never loses it silently', () {
    testWidgets('close asks, and keeping the draft editing preserves the text', (
      tester,
    ) async {
      final store = await _store([_seed('Alpha')]);
      var closed = false;
      await _surface(tester, const Size(1200, 1600));
      await _showEditor(tester, store, onClose: () => closed = true);

      await tester.enterText(
        find.byKey(const ValueKey('edit-new-subtask')),
        '买牛奶',
      );
      await tester.pump();
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Keep Editing'));
      await tester.pumpAndSettle();
      expect(closed, isFalse);
      expect(
        _controller(tester, 'edit-new-subtask').text,
        '买牛奶',
        reason: 'a cancelled close must not eat what was typed',
      );
      await _finish(tester, store);
    });

    testWidgets('discarding writes nothing at all', (tester) async {
      final store = await _store([_seed('Alpha')]);
      var closed = false;
      await _surface(tester, const Size(1200, 1600));
      await _showEditor(tester, store, onClose: () => closed = true);

      await tester.enterText(
        find.byKey(const ValueKey('edit-new-subtask')),
        '买牛奶',
      );
      await tester.pump();
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Discard'));
      await tester.pumpAndSettle();

      expect(closed, isTrue);
      expect(store.tasks.single.subtasks, isEmpty);
      await _finish(tester, store);
    });

    testWidgets('saving writes the typed subtask as a real row', (tester) async {
      final store = await _store([_seed('Alpha')]);
      var closed = false;
      await _surface(tester, const Size(1200, 1600));
      await _showEditor(tester, store, onClose: () => closed = true);

      await tester.enterText(
        find.byKey(const ValueKey('edit-new-subtask')),
        '  买牛奶  ',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('save-task')));
      await tester.pumpAndSettle();

      expect(closed, isTrue);
      expect(store.tasks.single.subtasks, hasLength(1));
      expect(store.tasks.single.subtasks.single.title, '买牛奶');
      await _finish(tester, store);
    });

    testWidgets('deleting the task drops the pending subtask with it', (
      tester,
    ) async {
      final store = await _store([_seed('Alpha'), _seed('Beta')]);
      var closed = false;
      await _surface(tester, const Size(1200, 1600));
      await _showEditor(tester, store, onClose: () => closed = true);

      await tester.enterText(
        find.byKey(const ValueKey('edit-new-subtask')),
        '买牛奶',
      );
      await tester.pump();
      await tester.tap(find.byTooltip('Delete Task'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
      await tester.pumpAndSettle();

      expect(closed, isTrue);
      expect(store.tasks, hasLength(1));
      expect(store.tasks.single.title, 'Beta');
      expect(store.tasks.single.subtasks, isEmpty);
      await _finish(tester, store);
    });
  });

  group('a kept-alive editor switches tasks without carrying text over', () {
    testWidgets('switching asks first, then shows an empty composer', (
      tester,
    ) async {
      final store = await _store([_seed('Alpha'), _seed('Beta')]);
      await _surface(tester, const Size(1200, 1600));
      await tester.pumpWidget(_host(store, _SessionPage(store: store)));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('open-alpha')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('edit-new-subtask')),
        'belongs to Alpha',
      );
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('open-beta')));
      await tester.pumpAndSettle();
      expect(
        find.text('Discard changes?'),
        findsOneWidget,
        reason: 'the un-added subtask is an unsaved change',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Discard'));
      await tester.pumpAndSettle();

      expect(_controller(tester, 'edit-title').text, 'Beta');
      expect(_controller(tester, 'edit-new-subtask').text, isEmpty);
      expect(store.tasks.firstWhere((t) => t.id == 'beta').subtasks, isEmpty);
      expect(store.tasks.firstWhere((t) => t.id == 'alpha').subtasks, isEmpty);

      // Saving the newly opened task must not resurrect the dropped text.
      await tester.tap(find.byKey(const ValueKey('save-task')));
      await tester.pumpAndSettle();
      expect(store.tasks.firstWhere((t) => t.id == 'beta').subtasks, isEmpty);
      await _finish(tester, store);
    });

    testWidgets('keeping the draft editing leaves the switch undone', (
      tester,
    ) async {
      final store = await _store([_seed('Alpha'), _seed('Beta')]);
      await _surface(tester, const Size(1200, 1600));
      await tester.pumpWidget(_host(store, _SessionPage(store: store)));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('open-alpha')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('edit-new-subtask')),
        'belongs to Alpha',
      );
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('open-beta')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Keep Editing'));
      await tester.pumpAndSettle();

      expect(
        _controller(tester, 'edit-title').text,
        'Alpha',
        reason: 'the editor stays on the task the text belongs to',
      );
      expect(_controller(tester, 'edit-new-subtask').text, 'belongs to Alpha');
      expect(store.tasks.firstWhere((t) => t.id == 'beta').subtasks, isEmpty);
      await _finish(tester, store);
    });

    testWidgets('saving keeps the subtask on the task that was edited', (
      tester,
    ) async {
      final store = await _store([_seed('Alpha'), _seed('Beta')]);
      await _surface(tester, const Size(1200, 1600));
      await tester.pumpWidget(_host(store, _SessionPage(store: store)));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('open-alpha')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('edit-new-subtask')),
        '买牛奶',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('save-task')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('open-beta')));
      await tester.pumpAndSettle();

      expect(
        store.tasks.firstWhere((t) => t.id == 'alpha').subtasks.single.title,
        '买牛奶',
      );
      expect(store.tasks.firstWhere((t) => t.id == 'beta').subtasks, isEmpty);
      await _finish(tester, store);
    });
  });
}

Future<Store> _store(List<Task> tasks) async {
  SharedPreferences.setMockInitialValues({
    'matrixflow-has-seen-onboarding': true,
  });
  final store = Store();
  await store.init();
  for (final task in tasks) {
    task.boardId = store.activeBoardId;
  }
  store.addTasks(tasks);
  return store;
}

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
  List<SubTask> subtasks = const [],
}) => Task(
  id: 't1',
  boardId: 'b',
  title: title,
  quadrant: qDo,
  createdAt: 1,
  notesMarkdown: notesMarkdown,
  subtasks: subtasks,
);

Future<void> _surface(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

Widget _host(Store store, Widget child) => ChangeNotifierProvider.value(
  value: store,
  child: MaterialApp(locale: const Locale('en'), home: child),
);

/// Hosts the editor the way a page does: a Scaffold over the Store.
Future<void> _showEditor(
  WidgetTester tester,
  Store store, {
  Task? task,
  VoidCallback? onClose,
}) async {
  await tester.pumpWidget(
    _host(
      store,
      Scaffold(
        body: TaskDetailPanel(
          task: task ?? store.tasks.first,
          isSidebar: true,
          onClose: onClose,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _finish(WidgetTester tester, Store store) async {
  // Disposed here rather than in tearDown: the store's deadline timer is still
  // pending when the framework checks for leaks otherwise.
  await tester.pumpWidget(const SizedBox.shrink());
  store.dispose();
  await tester.pump();
}

TextEditingController _controller(WidgetTester tester, String key) =>
    tester.widget<TextField>(find.byKey(ValueKey(key))).controller!;

/// Mirrors the wide layout of the three pages, where one GlobalKey is reused
/// across tasks so the editor keeps its state and only [TaskEditDraft.load]
/// separates one task's draft from the next.
class _SessionPage extends StatefulWidget {
  const _SessionPage({required this.store});

  final Store store;

  @override
  State<_SessionPage> createState() => _SessionPageState();
}

class _SessionPageState extends State<_SessionPage> {
  final _detailKey = GlobalKey();

  late final TaskDetailSession _detail = TaskDetailSession(
    onChanged: () => setState(() {}),
  );

  @override
  Widget build(BuildContext context) {
    final task = _detail.taskIn(widget.store);
    return Scaffold(
      body: Column(
        children: [
          for (final candidate in widget.store.tasks)
            TextButton(
              key: ValueKey('open-${candidate.id}'),
              onPressed: () => _detail.open(context, candidate, isWide: true),
              child: Text('open ${candidate.id}'),
            ),
          Expanded(
            child: task == null
                ? const SizedBox.shrink()
                : TaskDetailPanel(
                  key: _detailKey,
                  task: task,
                  isSidebar: true,
                  onDirtyChanged: _detail.reportDraft,
                  onClose: _detail.handleClose,
                ),
          ),
        ],
      ),
    );
  }
}
