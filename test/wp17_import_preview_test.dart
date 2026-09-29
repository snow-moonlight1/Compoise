import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/import_preview/draft_model.dart';
import 'package:matrixflow_native/import_preview/draft_preview.dart';

Map<String, dynamic> image(String id, {bool withDue = false}) => {
  'schema': 'wp17r2-draft/1',
  'id': id,
  'width': 1080,
  'height': 1403,
  'engine': 'ncnn-ppocrv5-mobile',
  'rows': [],
  'noise_lines': [],
  'notes': [],
  'tasks': [
    {
      'row': 3,
      'line_indices': [1],
      'anchor_line': 1,
      'title': 'Buy milk',
      'checked': false,
      'checkbox_box': [1, 2, 3, 4],
      'checkbox_fill': 0.1,
      'level': 0,
      'parent': null,
      'due': withDue ? 'today 18:00' : null,
      'needs_confirmation': [],
    },
    {
      'row': 4,
      'line_indices': [2],
      'anchor_line': 2,
      'title': 'Eggs',
      'checked': true,
      'checkbox_box': [1, 2, 3, 4],
      'checkbox_fill': 0.9,
      'level': 1,
      'parent': 3,
      'due': null,
      'needs_confirmation': ['indent uncertain'],
    },
  ],
  'dropped': [
    {'row': 2, 'kind': 'header', 'text': 'Groceries'},
  ],
};

DraftBatch batch() => DraftBatch.fromJson({
  'schema': 'wp17r2-draft/1',
  'images': [
    image('one', withDue: true),
    {'id': 'broken', 'error': 'OCR unavailable'},
    image('two'),
  ],
  'duplicates': [
    {
      'images': ['one', 'two'],
      'reason': 'identical-bytes',
      'hint_only': true,
    },
  ],
});

void main() {
  test(
    'R2 input maps parent rows, dropped candidates and date text safely',
    () {
      final value = batch();
      expect(value.images.map((item) => item.id), ['one', 'broken', 'two']);
      final one = value.images.first;
      expect(one.tasks.first.excluded, isTrue);
      expect(one.tasks[2].parentId, one.tasks[1].id);
      expect(one.tasks[1].reviewReasons, contains('date text needs review'));
      value.boardId = 'board';
      value.quadrant = 2;
      for (final task in value.activeTasks) {
        task.confirmed = true;
      }
      expect(
        value.canSubmit,
        isFalse,
      ); // duplicate needs explicit acknowledgement
      value.duplicates.first.acknowledged = true;
      expect(value.canSubmit, isTrue);
      final submission = value.snapshot();
      expect(submission.tasks.length, 4);
      expect(submission.tasks.first.dueText, isNull); // never infer a deadline
      one.tasks[1].keepDueText = true;
      expect(value.snapshot().tasks.first.dueText, 'today 18:00');
      expect(submission.tasks.first.dueText, isNull); // detached snapshot
    },
  );

  test(
    'invalid schema, duplicate IDs, malformed tasks and all skipped are gated',
    () {
      expect(
        () => DraftBatch.fromJson({'schema': 'other'}),
        throwsA(isA<DraftFormatException>()),
      );
      expect(
        () => DraftBatch.fromJson({
          'schema': 'wp17r2-draft/1',
          'images': [image('one'), image('one')],
        }),
        throwsA(isA<DraftFormatException>()),
      );
      final bad = image('bad');
      ((bad['tasks'] as List)[0] as Map<String, dynamic>)['checked'] = 'yes';
      expect(
        () => DraftBatch.fromJson(bad),
        throwsA(isA<DraftFormatException>()),
      );
      final value = batch();
      value.boardId = 'board';
      value.quadrant = 1;
      value.images[0].skipped = true;
      value.images[2].skipped = true;
      expect(value.canSubmit, isFalse);
      expect(() => value.snapshot(), throwsA(isA<DraftFormatException>()));
    },
  );

  test('split, merge, exclusion and invalid parent renew review', () {
    final value = DraftBatch.fromJson(image('one'));
    final tasks = value.images.first.tasks;
    final parent = tasks[1];
    final child = tasks[2];
    parent.confirmed = true;
    child.confirmed = true;
    parent.title = 'Milk\nBread';
    final split = value.splitAtNewline(parent)!;
    expect(split.title, 'Bread');
    expect(parent.confirmed, isFalse);
    expect(split.confirmed, isFalse);
    expect(
      () => value.setParent(parent, child.id),
      throwsA(isA<DraftFormatException>()),
    );
    value.setExcluded(parent, true);
    expect(child.parentId, isNull);
    expect(child.confirmed, isFalse);
    value.setExcluded(parent, false);
    expect(value.mergeWithPrevious(split), isTrue);
    expect(parent.title, 'Milk Bread');
  });

  testWidgets(
    'review is required; reorder, edit, skip failure, confirm and submit',
    (tester) async {
      tester.view.physicalSize = const Size(400, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final value = batch();
      ImportSubmission? submitted;
      var cancelled = false;
      Widget app() => MaterialApp(
        home: Scaffold(
          body: DraftPreview(
            batch: value,
            boards: const [ImportBoardChoice('board', 'My board')],
            onSubmit: (submission) async {
              submitted = submission;
            },
            onCancel: () {
              cancelled = true;
            },
          ),
        ),
      );
      await tester.pumpWidget(app());
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('import-submit')))
            .onPressed,
        isNull,
      );
      expect(find.text('OCR unavailable'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('image-down-one')));
      await tester.pumpWidget(app());
      expect(value.images.map((image) => image.id), ['broken', 'one', 'two']);
      value.boardId = 'board';
      value.quadrant = 1;
      for (final task in value.activeTasks) {
        task.confirmed = true;
      }
      await tester.pumpWidget(app());
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('import-submit')))
            .onPressed,
        isNull,
      );
      value.duplicates.first.acknowledged = true;
      await tester.pumpWidget(app());
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('import-submit')))
            .onPressed,
        isNotNull,
      );
      await tester.ensureVisible(find.byKey(const ValueKey('import-submit')));
      await tester.tap(find.byKey(const ValueKey('import-submit')));
      await tester.pump();
      expect(submitted, isNotNull);
      expect(submitted!.tasks.map((task) => task.imageId), [
        'one',
        'one',
        'two',
        'two',
      ]);
      expect(cancelled, isFalse);
    },
  );

  testWidgets('cancel never calls submit callback', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DraftPreview(
            batch: DraftBatch.fromJson(image('one')),
            boards: const [ImportBoardChoice('board', 'Board')],
            onSubmit: (_) async {
              calls++;
            },
            onCancel: () {},
          ),
        ),
      ),
    );
    await tester.ensureVisible(find.byKey(const ValueKey('import-cancel')));
    await tester.tap(find.byKey(const ValueKey('import-cancel')));
    await tester.pump();
    expect(calls, 0);
  });

  testWidgets('keyboard edit clears confirmation on a narrow screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final value = DraftBatch.fromJson(image('one'));
    value.boardId = 'board';
    value.quadrant = 1;
    for (final task in value.activeTasks) {
      task.confirmed = true;
    }
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DraftPreview(
            batch: value,
            boards: const [ImportBoardChoice('board', 'Board')],
            onSubmit: (_) async {},
            onCancel: () {},
          ),
        ),
      ),
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('import-submit')))
          .onPressed,
      isNotNull,
    );
    final title = find.byKey(const ValueKey('title-one:3'));
    await tester.ensureVisible(title);
    await tester.enterText(title, 'Buy oat milk');
    await tester.pump();
    expect(value.activeTasks.first.title, 'Buy oat milk');
    expect(value.activeTasks.first.confirmed, isFalse);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('import-submit')))
          .onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });
}
