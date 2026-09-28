import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/widgets/task_tags_editor.dart';

/// WP12 tags, component half: what [TaskTagsEditor] owes the draft that owns it.
/// There is no Store behind these trees — the editor must work on plain lists.
const _en = {
  'tagPlaceholder': 'Tag name',
  'addTag': 'Add tag',
  'tagRemove': 'Remove {tag}',
};

void main() {
  late List<List<String>> changes;

  setUp(() => changes = []);

  Future<void> pump(
    WidgetTester tester,
    List<String> value, {
    Map<String, String> t = _en,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TaskTagsEditor(value: value, onChanged: changes.add, t: t),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(
      find.byKey(const ValueKey('task-tag-input')),
      text,
    );
    await tester.pump();
  }

  Future<void> submit(WidgetTester tester) async {
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
  }

  Finder chip(String tag) => find.byKey(ValueKey('task-tag-$tag'));

  Future<void> delete(WidgetTester tester, String tag) async {
    await tester.tap(
      find.descendant(of: chip(tag), matching: find.byIcon(Icons.close)),
    );
    await tester.pumpAndSettle();
  }

  group('TaskTagsEditor', () {
    testWidgets('shows the draft tags and nothing else', (tester) async {
      await pump(tester, ['Work', '家庭']);
      expect(find.byKey(const ValueKey('task-tags-list')), findsOneWidget);
      expect(chip('Work'), findsOneWidget);
      expect(chip('家庭'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('task-tag-input')),
        findsOneWidget,
      );
    });

    testWidgets('an empty draft is just the input', (tester) async {
      await pump(tester, const []);
      expect(find.byKey(const ValueKey('task-tags-list')), findsNothing);
      expect(find.byType(Chip), findsNothing);
    });

    testWidgets('entering a tag reports it and clears the field', (
      tester,
    ) async {
      await pump(tester, ['Work']);
      await type(tester, 'Home');
      await submit(tester);

      expect(changes, [
        ['Work', 'Home'],
      ]);
      final field = tester.widget<TextField>(
        find.byKey(const ValueKey('task-tag-input')),
      );
      expect(field.controller!.text, isEmpty);
      expect(
        field.focusNode!.hasFocus,
        isTrue,
        reason: 'the next tag should not need another tap',
      );
    });

    testWidgets('the add button does the same as the done action', (
      tester,
    ) async {
      await pump(tester, const []);
      await type(tester, 'Urgent');
      await tester.tap(find.byKey(const ValueKey('task-tag-add')));
      await tester.pumpAndSettle();
      expect(changes.single, ['Urgent']);
    });

    testWidgets('a tag the draft already has is not a change', (tester) async {
      await pump(tester, ['Work']);
      await type(tester, ' work ');
      await submit(tester);
      expect(changes, isEmpty, reason: 'a duplicate must not dirty the draft');

      await type(tester, 'WORK');
      await tester.tap(find.byKey(const ValueKey('task-tag-add')));
      await tester.pumpAndSettle();
      expect(changes, isEmpty);
    });

    testWidgets('blank input is ignored', (tester) async {
      await pump(tester, ['Work']);
      await type(tester, '   ');
      await submit(tester);
      expect(changes, isEmpty);

      await type(tester, '');
      await submit(tester);
      expect(changes, isEmpty);
    });

    testWidgets('deleting a chip reports what is left', (tester) async {
      await pump(tester, ['Work', 'Home', 'Urgent']);
      await delete(tester, 'Home');
      expect(changes.single, ['Work', 'Urgent']);
    });

    testWidgets('a messy draft is reported clean', (tester) async {
      await pump(tester, [' Work ', 'work', '', 'Home']);
      expect(find.byType(Chip), findsNWidgets(2));
      await type(tester, ' urgent ');
      await submit(tester);
      expect(changes.single, ['Work', 'Home', 'urgent']);
    });

    testWidgets('the list it is given is never edited', (tester) async {
      final draft = ['Work', 'Home'];
      await pump(tester, draft);

      await type(tester, 'Urgent');
      await submit(tester);
      await delete(tester, 'Work');

      expect(changes, hasLength(2));
      expect(draft, ['Work', 'Home']);
      expect(changes.first, ['Work', 'Home', 'Urgent']);
      expect(changes.last, ['Home']);
      expect(identical(changes.first, draft), isFalse);
      expect(identical(changes.last, draft), isFalse);
    });

    testWidgets('it reports a change and waits for the caller to redraw', (
      tester,
    ) async {
      await pump(tester, ['Work']);
      await delete(tester, 'Work');
      expect(changes.single, isEmpty);
      expect(
        find.byType(Chip),
        findsOneWidget,
        reason: 'the draft belongs to the caller, not this widget',
      );
    });

    testWidgets('labels come from the dictionary the caller passes', (
      tester,
    ) async {
      await pump(
        tester,
        ['Work'],
        t: const {
          'tagPlaceholder': 'タグ名',
          'addTag': 'タグを追加',
          'tagRemove': '{tag} を削除',
        },
      );
      expect(find.text('タグ名'), findsOneWidget);
      expect(find.byTooltip('タグを追加'), findsOneWidget);
      expect(find.byTooltip('Work を削除'), findsOneWidget);
    });
  });

  group('draft round trip', () {
    testWidgets('a caller that owns the draft sees its own list back', (
      tester,
    ) async {
      var draft = <String>['Work'];
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) => Scaffold(
              body: TaskTagsEditor(
                value: draft,
                onChanged: (next) => setState(() => draft = next),
                t: _en,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await type(tester, ' Home ');
      await submit(tester);
      expect(draft, ['Work', 'Home']);
      expect(chip('Home'), findsOneWidget);

      await delete(tester, 'Work');
      expect(draft, ['Home']);
      expect(chip('Work'), findsNothing);
      expect(chip('Home'), findsOneWidget);
    });
  });
}
