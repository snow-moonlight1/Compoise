import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/import_preview/draft_model.dart';
import 'package:matrixflow_native/import_preview/draft_preview.dart';
import 'package:matrixflow_native/l10n.dart';
import 'package:matrixflow_native/models.dart';

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

Map<String, dynamic> taskJson({
  required int row,
  required String title,
  int level = 0,
  Object? parent,
  Object? due,
  Object? checked = false,
  Object? needs = const <String>[],
}) => {
  'row': row,
  'title': title,
  'checked': checked,
  'level': level,
  'parent': parent,
  'due': due,
  'needs_confirmation': needs,
};

Map<String, dynamic> imageJson(
  String id,
  List<Map<String, dynamic>> tasks, {
  List<Map<String, dynamic>> dropped = const [],
}) => {
  'schema': 'wp17r2-draft/1',
  'id': id,
  'width': 1080,
  'height': 1403,
  'engine': 'ncnn-ppocrv5-mobile',
  'tasks': tasks,
  'dropped': dropped,
  'notes': <String>['note for $id'],
};

void ready(DraftBatch value) {
  value.boardId = 'board';
  value.quadrant = 1;
  for (final task in value.activeTasks) {
    task.confirmed = true;
  }
  for (final hint in value.duplicates) {
    hint.acknowledged = true;
  }
}

final Uint8List _png = Uint8List.fromList(const [
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0A,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
]);

Future<void> pumpPreview(
  WidgetTester tester, {
  required DraftBatch value,
  required Future<void> Function(ImportSubmission submission) onSubmit,
  Language language = Language.zh,
  Size size = const Size(390, 844),
  double textScale = 1,
  double keyboardInset = 0,
  Map<String, ImageProvider> thumbnails = const {},
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.viewInsets = FakeViewPadding(bottom: keyboardInset);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: DraftPreview(
          batch: value,
          language: language,
          boards: const [ImportBoardChoice('board', 'My board')],
          thumbnails: thumbnails,
          onSubmit: onSubmit,
          onCancel: () {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder get reviewScrollable => find.descendant(
  of: find.byKey(const ValueKey('import-review-scroll')),
  matching: find.byWidgetPredicate(
    (widget) => widget is Scrollable && widget.restorationId == null,
  ),
);

Future<void> tapSubmit(WidgetTester tester) async {
  final submit = find.byKey(const ValueKey('import-submit'));
  await tester.ensureVisible(submit);
  expect(
    tester.widget<FilledButton>(submit).onPressed,
    isNull,
    reason: 'submit stays disabled until the batch is ready',
  );
  await tester.tap(submit);
  await tester.pump();
}

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

  test(
    'schema checks parent order, missing parents, duplicates and raw dates',
    () {
      final reversed = DraftBatch.fromJson(
        imageJson('shot', [
          taskJson(row: 4, title: 'Child', level: 1, parent: 3),
          taskJson(row: 3, title: 'Parent'),
        ]),
      );
      final tasks = reversed.images.single.tasks;
      expect(tasks.map((task) => task.title), ['Parent', 'Child']);
      expect(tasks[1].parentId, tasks[0].id);

      final missing = DraftBatch.fromJson(
        imageJson('shot', [
          taskJson(row: 3, title: 'Orphan', level: 1, parent: 99),
        ]),
      );
      final orphan = missing.images.single.tasks.single;
      expect(orphan.parentId, isNull);
      expect(
        orphan.reviewReasons,
        containsAll([
          'indent/parent needs review',
          'parent row is missing or out of order',
        ]),
      );

      final laterParent = DraftBatch.fromJson(
        imageJson('shot', [
          taskJson(row: 3, title: 'Child', level: 1, parent: 4),
          taskJson(row: 4, title: 'Later'),
        ]),
      );
      expect(laterParent.images.single.tasks.first.parentId, isNull);
      expect(
        laterParent.images.single.tasks.first.reviewReasons,
        contains('parent row is missing or out of order'),
      );

      final raw = '周五 18:00（备注）';
      final dated = DraftBatch.fromJson(
        imageJson('shot', [taskJson(row: 1, title: 'Call', due: raw)]),
      );
      final datedTask = dated.images.single.tasks.single;
      expect(datedTask.dueText, raw);
      expect(datedTask.reviewReasons, contains('date text needs review'));
      ready(dated);
      datedTask.keepDueText = true;
      expect(dated.snapshot().tasks.single.dueText, raw);
      datedTask.dueText = '   ';
      datedTask.confirmed = true;
      expect(dated.snapshot().tasks.single.dueText, isNull);

      expect(
        () => DraftBatch.fromJsonString('{'),
        throwsA(isA<DraftFormatException>()),
      );
      expect(
        () => DraftBatch.fromJson({'schema': 'wp17r2-draft/1', 'images': []}),
        throwsA(isA<DraftFormatException>()),
      );
      expect(
        () =>
            DraftBatch.fromJson(imageJson(' ', [taskJson(row: 1, title: 'A')])),
        throwsA(isA<DraftFormatException>()),
      );
      final broken = imageJson('shot', [taskJson(row: 1, title: 'A')]);
      broken.remove('tasks');
      expect(
        () => DraftBatch.fromJson(broken),
        throwsA(isA<DraftFormatException>()),
      );
      expect(
        () => DraftBatch.fromJson(
          imageJson('shot', [taskJson(row: 1, title: 'A', level: 2)]),
        ),
        throwsA(isA<DraftFormatException>()),
      );
      expect(
        () => DraftBatch.fromJson(
          imageJson('shot', [
            taskJson(row: 1, title: 'A'),
            taskJson(row: 1, title: 'B'),
          ]),
        ),
        throwsA(isA<DraftFormatException>()),
      );
      expect(
        () => DraftBatch.fromJson(
          imageJson('shot', [taskJson(row: 1, title: 'A', due: 20260929)]),
        ),
        throwsA(isA<DraftFormatException>()),
      );
      expect(
        () => DraftBatch.fromJson(
          imageJson('shot', [taskJson(row: 1, title: 'A', parent: '3')]),
        ),
        throwsA(isA<DraftFormatException>()),
      );
      expect(
        () => DraftBatch.fromJson(
          imageJson('shot', [taskJson(row: 1, title: 'A', needs: 'review')]),
        ),
        throwsA(isA<DraftFormatException>()),
      );
      expect(
        () => DraftBatch.fromJson({
          'schema': 'wp17r2-draft/1',
          'images': [
            imageJson('a', [taskJson(row: 1, title: 'A')]),
            imageJson('b', [taskJson(row: 1, title: 'B')]),
          ],
          'duplicates': [
            {
              'images': ['a', 'b'],
              'reason': 'identical-bytes',
              'hint_only': false,
            },
          ],
        }),
        throwsA(isA<DraftFormatException>()),
      );
      expect(
        () => DraftBatch.fromJson({
          'schema': 'wp17r2-draft/1',
          'images': [
            imageJson('a', [taskJson(row: 1, title: 'A')]),
          ],
          'duplicates': [
            {
              'images': ['a', 'missing'],
              'reason': 'identical-bytes',
              'hint_only': true,
            },
          ],
        }),
        throwsA(isA<DraftFormatException>()),
      );

      final hinted = batch();
      ready(hinted);
      hinted.duplicates.first.acknowledged = false;
      hinted.images[2].skipped = true;
      expect(hinted.canSubmit, isTrue);
      hinted.images[2].skipped = false;
      for (final task in hinted.activeTasks) {
        task.confirmed = true;
      }
      expect(hinted.canSubmit, isFalse);
    },
  );

  test('snapshot copies review results and drops live lists and image data', () {
    final value = batch();
    ready(value);
    value.images.first.tasks[1].keepDueText = true;
    value.images.first.tasks[1].dueText = '  2026-09-29 18:00  ';
    final submission = value.snapshot();
    expect(submission.tasks, isA<List<ImportTask>>());
    expect(
      () => submission.tasks.add(submission.tasks.first),
      throwsUnsupportedError,
    );
    expect(submission.tasks, isNot(same(value.images.first.tasks)));
    expect(submission.tasks.first.dueText, '2026-09-29 18:00');
    expect(submission.tasks.first.checked, isFalse);
    expect(
      submission.tasks.map((task) => task.imageId),
      isNot(contains('broken')),
    );
    expect(
      submission.tasks.map((task) => task.title),
      isNot(contains('Groceries')),
    );

    value.images.first.tasks[1].title = 'changed after snapshot';
    value.images.first.tasks[1].dueText = 'changed date';
    value.images.first.tasks[1].checked = true;
    value.boardId = 'other-board';
    value.quadrant = 4;
    value.images.first.tasks.add(
      DraftTask(
        id: 'extra',
        imageId: 'one',
        sourceRow: 9,
        title: 'extra',
        checked: false,
      ),
    );
    expect(submission.boardId, 'board');
    expect(submission.quadrant, 1);
    expect(submission.tasks.first.title, 'Buy milk');
    expect(submission.tasks.first.dueText, '2026-09-29 18:00');
    expect(submission.tasks.first.checked, isFalse);
    expect(submission.tasks, hasLength(4));
    final flat = submission.tasks
        .map(
          (task) =>
              '${task.id}|${task.imageId}|${task.title}|${task.dueText}|${task.parentId}',
        )
        .join('\n');
    expect(flat, isNot(contains('ncnn')));
    expect(flat, isNot(contains('OCR unavailable')));
    expect(flat, isNot(contains('identical-bytes')));
    expect(flat, isNot(contains('note for')));
    expect(flat, isNot(contains(_png.join(','))));

    value.images.first.tasks[1].parentId = value.images.first.tasks[2].id;
    expect(value.canSubmit, isFalse);
    expect(() => value.snapshot(), throwsA(isA<DraftFormatException>()));
  });

  test(
    'split, merge, exclude and restore clear confirmation of affected tasks',
    () {
      final value = DraftBatch.fromJson(image('one'));
      final tasks = value.images.single.tasks;
      final dropped = tasks[0];
      final parent = tasks[1];
      final child = tasks[2];
      dropped.confirmed = true;
      parent.confirmed = true;
      child.confirmed = true;
      parent.title = 'Milk\nBread';

      final split = value.splitAtNewline(parent)!;
      expect(parent.confirmed, isFalse);
      expect(split.confirmed, isFalse);
      expect(child.confirmed, isTrue);

      parent.confirmed = true;
      split.confirmed = true;
      expect(value.mergeWithPrevious(split), isTrue);
      expect(parent.confirmed, isFalse);
      expect(parent.title, 'Milk Bread');
      expect(child.confirmed, isTrue);

      parent.confirmed = true;
      value.setExcluded(parent, true);
      expect(parent.confirmed, isFalse);
      expect(parent.excluded, isTrue);
      expect(child.parentId, isNull);
      expect(child.confirmed, isFalse);
      expect(child.reviewReasons, contains('parent was excluded'));

      value.setExcluded(parent, false);
      expect(parent.excluded, isFalse);
      expect(parent.confirmed, isFalse);
      expect(child.confirmed, isFalse);

      value.setExcluded(dropped, false);
      expect(dropped.excluded, isFalse);
      expect(dropped.confirmed, isFalse);

      ready(value);
      parent.confirmed = false;
      expect(value.canSubmit, isFalse);
      expect(() => value.snapshot(), throwsA(isA<DraftFormatException>()));
    },
  );

  test('preview package does not touch files, OCR, store, or navigation', () {
    for (final path in [
      'lib/import_preview/draft_model.dart',
      'lib/import_preview/draft_preview.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source, isNot(contains('dart:io')));
      expect(source, isNot(contains('file_picker')));
      expect(source, isNot(contains('shared_preferences')));
      expect(source, isNot(contains('storage.dart')));
      expect(source, isNot(contains('package:matrixflow_native/ocr')));
      expect(source, isNot(contains('File(')));
      expect(source, isNot(contains('writeAsString')));
      expect(source, isNot(contains('Navigator.')));
      expect(source, isNot(contains('GoRouter')));
      expect(source, isNot(contains('DateTime')));
    }
  });

  testWidgets('incomplete review never calls onSubmit', (tester) async {
    addTearDown(tester.view.reset);
    var calls = 0;
    Future<void> submit(ImportSubmission _) async => calls++;

    final failed = DraftBatch.fromJson({
      'schema': 'wp17r2-draft/1',
      'images': [
        {'id': 'broken', 'error': 'OCR unavailable'},
      ],
    });
    failed.boardId = 'board';
    failed.quadrant = 2;
    await pumpPreview(tester, value: failed, onSubmit: submit);
    await tapSubmit(tester);

    final skipped = batch();
    ready(skipped);
    skipped.images[0].skipped = true;
    skipped.images[2].skipped = true;
    await pumpPreview(tester, value: skipped, onSubmit: submit);
    await tapSubmit(tester);

    final empty = DraftBatch.fromJson(image('one'));
    ready(empty);
    empty.activeTasks.first.title = '   ';
    await pumpPreview(tester, value: empty, onSubmit: submit);
    expect(find.text('请输入任务文字'), findsOneWidget);
    await tapSubmit(tester);

    final unconfirmed = batch();
    unconfirmed.boardId = 'board';
    unconfirmed.quadrant = 3;
    unconfirmed.duplicates.first.acknowledged = true;
    await pumpPreview(tester, value: unconfirmed, onSubmit: submit);
    await tapSubmit(tester);

    final duplicate = batch();
    ready(duplicate);
    duplicate.duplicates.first.acknowledged = false;
    await pumpPreview(tester, value: duplicate, onSubmit: submit);
    await tapSubmit(tester);

    expect(calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('clearing a title in the field blocks submit', (tester) async {
    addTearDown(tester.view.reset);
    var calls = 0;
    final value = DraftBatch.fromJson(image('one'));
    ready(value);
    await pumpPreview(
      tester,
      value: value,
      onSubmit: (_) async => calls++,
      size: const Size(390, 844),
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('import-submit')))
          .onPressed,
      isNotNull,
    );
    final title = find.byKey(const ValueKey('title-one:3'));
    await tester.ensureVisible(title);
    await tester.enterText(title, '');
    await tester.pump();
    expect(value.activeTasks.first.title, isEmpty);
    expect(value.activeTasks.first.confirmed, isFalse);
    await tapSubmit(tester);
    expect(calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'split, merge, exclude and restore disable submit until reconfirmed',
    (tester) async {
      addTearDown(tester.view.reset);
      var calls = 0;
      final value = DraftBatch.fromJson(
        imageJson('one', [
          taskJson(row: 1, title: 'Milk\nBread'),
          taskJson(row: 2, title: 'Eggs', level: 1, parent: 1),
        ]),
      );
      ready(value);
      await pumpPreview(
        tester,
        value: value,
        onSubmit: (_) async => calls++,
        size: const Size(390, 844),
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('import-submit')))
            .onPressed,
        isNotNull,
      );

      await tester.ensureVisible(find.byKey(const ValueKey('split-one:1')));
      await tester.tap(find.byKey(const ValueKey('split-one:1')));
      await tester.pumpAndSettle();
      expect(value.images.single.tasks[0].confirmed, isFalse);
      expect(value.images.single.tasks[1].confirmed, isFalse);
      await tapSubmit(tester);

      for (final key in const ['confirm-one:1', 'confirm-one:edit:0']) {
        final box = find.byKey(ValueKey(key));
        await tester.ensureVisible(box);
        await tester.tap(box);
        await tester.pump();
      }
      await tester.ensureVisible(
        find.byKey(const ValueKey('merge-one:edit:0')),
      );
      await tester.tap(find.byKey(const ValueKey('merge-one:edit:0')));
      await tester.pumpAndSettle();
      expect(value.images.single.tasks.first.confirmed, isFalse);
      expect(value.images.single.tasks.first.title, 'Milk Bread');
      await tapSubmit(tester);

      final parentConfirm = find.byKey(const ValueKey('confirm-one:1'));
      await tester.ensureVisible(parentConfirm);
      await tester.tap(parentConfirm);
      await tester.pump();
      await tester.ensureVisible(find.byKey(const ValueKey('exclude-one:1')));
      await tester.tap(find.byKey(const ValueKey('exclude-one:1')));
      await tester.pumpAndSettle();
      final tasks = value.images.single.tasks;
      expect(tasks.first.excluded, isTrue);
      expect(tasks.first.confirmed, isFalse);
      expect(tasks[1].parentId, isNull);
      expect(tasks[1].confirmed, isFalse);
      await tapSubmit(tester);

      final restore = find.byKey(const ValueKey('exclude-one:1'));
      await tester.ensureVisible(restore);
      await tester.tap(restore);
      await tester.pumpAndSettle();
      expect(tasks.first.excluded, isFalse);
      expect(tasks.first.confirmed, isFalse);
      await tapSubmit(tester);
      expect(calls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('narrow, phone, large text, keyboard and scroll stay usable', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    addTearDown(tester.view.reset);
    final thumbnails = {'one': MemoryImage(_png), 'two': MemoryImage(_png)};
    for (final size in const [Size(320, 720), Size(390, 844)]) {
      for (final scale in const [1.0, 2.0]) {
        await pumpPreview(
          tester,
          value: batch(),
          onSubmit: (_) async {},
          size: size,
          textScale: scale,
          thumbnails: thumbnails,
        );
        expect(tester.takeException(), isNull, reason: '$size scale $scale');
        final submit = find.byKey(const ValueKey('import-submit'));
        await tester.ensureVisible(submit);
        expect(
          tester.getRect(submit).bottom,
          lessThanOrEqualTo(tester.getRect(reviewScrollable).bottom + 1),
        );
        expect(
          tester.takeException(),
          isNull,
          reason: 'scroll $size scale $scale',
        );
      }
    }

    final keyboardBatch = batch();
    await pumpPreview(
      tester,
      value: keyboardBatch,
      onSubmit: (_) async {},
      size: const Size(320, 720),
      textScale: 2,
      keyboardInset: 320,
      thumbnails: thumbnails,
    );
    final scrollState = tester.state<ScrollableState>(reviewScrollable);
    expect(scrollState.position.viewportDimension, lessThan(420));
    expect(scrollState.position.maxScrollExtent, greaterThan(0));
    final title = find.byKey(const ValueKey('title-two:3'));
    await tester.ensureVisible(title);
    await tester.enterText(title, '键盘输入');
    await tester.pump();
    expect(
      keyboardBatch.images.last.tasks
          .firstWhere((task) => task.id == 'two:3')
          .title,
      '键盘输入',
    );
    final submit = find.byKey(const ValueKey('import-submit'));
    await tester.ensureVisible(submit);
    final viewport = tester.getRect(reviewScrollable);
    expect(
      tester.getRect(submit).bottom,
      lessThanOrEqualTo(viewport.bottom + 1),
    );
    var implicit = false;
    void visit(SemanticsNode node) {
      if (node.hasFlag(SemanticsFlag.hasImplicitScrolling)) implicit = true;
      node.visitChildren((child) {
        visit(child);
        return true;
      });
    }

    for (final view in tester.binding.renderViews) {
      final root = view.owner?.semanticsOwner?.rootSemanticsNode;
      if (root != null) visit(root);
    }
    expect(implicit, isTrue);
    semantics.dispose();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Chinese, English and Japanese copy expose semantic labels', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    addTearDown(tester.view.reset);
    const foreign = {
      Language.en: '校对截图任务',
      Language.zh: 'Review screenshot tasks',
      Language.ja: 'Review screenshot tasks',
    };
    for (final language in const [Language.zh, Language.en, Language.ja]) {
      final dict = dictOf(language);
      await pumpPreview(
        tester,
        value: batch(),
        onSubmit: (_) async {},
        language: language,
        size: const Size(390, 844),
        thumbnails: {'one': MemoryImage(_png)},
      );
      expect(find.text(dict['importReviewTitle']!), findsOneWidget);
      expect(find.text(foreign[language]!), findsNothing);
      expect(find.text(dict['importReviewHint']!), findsOneWidget);
      expect(find.text(dict['importImageFailed']!), findsOneWidget);
      expect(find.text(dict['importDateHint']!), findsWidgets);
      expect(find.text(dict['importDuplicateHint']!), findsOneWidget);
      expect(find.text(dict['cancel']!), findsOneWidget);
      expect(find.text(dict['importSubmit']!), findsOneWidget);
      expect(
        find.text('${dict['importNeedsReview']}: ${dict['importReasonDate']}'),
        findsWidgets,
      );
      expect(
        find.text(
          '${dict['importNeedsReview']}: ${dict['importReasonParent']}',
        ),
        findsWidgets,
      );
      expect(
        find.text(
          '${dict['importNeedsReview']}: ${dict['importReasonDropped']}: header',
        ),
        findsWidgets,
      );
      expect(
        find.text('${dict['importNeedsReview']}: indent uncertain'),
        findsWidgets,
      );

      expect(
        tester
            .getSemantics(find.text(dict['importReviewTitle']!))
            .hasFlag(SemanticsFlag.isHeader),
        isTrue,
      );
      expect(
        tester.getSemantics(find.byType(Image)).label,
        '${dict['importImage']!} 1',
      );
      expect(
        tester
            .getSemantics(find.byTooltip(dict['importMoveLater']!).first)
            .tooltip,
        dict['importMoveLater'],
      );
      expect(
        tester
            .getSemantics(find.byKey(const ValueKey('import-submit')))
            .hasFlag(SemanticsFlag.isButton),
        isTrue,
      );
      expect(
        tester.getSemantics(find.byKey(const ValueKey('import-submit'))).label,
        contains(dict['importSubmit']!),
      );
      expect(
        tester.getSemantics(find.byKey(const ValueKey('duplicate-0'))).label,
        contains(dict['importDuplicate']!),
      );
      expect(tester.takeException(), isNull, reason: language.name);
    }
    semantics.dispose();
  });

  testWidgets('keyboard activates only a ready submit button', (tester) async {
    final semantics = tester.ensureSemantics();
    addTearDown(tester.view.reset);
    var calls = 0;
    final blocked = DraftBatch.fromJson(image('one'));
    blocked.boardId = 'board';
    blocked.quadrant = 1;
    await pumpPreview(
      tester,
      value: blocked,
      onSubmit: (_) async => calls++,
      size: const Size(390, 844),
    );
    final blockedButton = find.byKey(const ValueKey('import-submit'));
    await tester.ensureVisible(blockedButton);
    final blockedSemantics = tester.getSemantics(blockedButton);
    expect(blockedSemantics.hasFlag(SemanticsFlag.isButton), isTrue);
    expect(blockedSemantics.hasFlag(SemanticsFlag.isEnabled), isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(calls, 0);

    final value = DraftBatch.fromJson(image('one'));
    ready(value);
    await pumpPreview(
      tester,
      value: value,
      onSubmit: (_) async => calls++,
      size: const Size(390, 844),
    );
    final title = find.byKey(const ValueKey('title-one:3'));
    await tester.ensureVisible(title);
    await tester.tap(title);
    await tester.pump();
    await tester.enterText(title, 'Buy oat milk');
    await tester.pump();
    expect(value.activeTasks.first.confirmed, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(calls, 0);

    final confirm = find.byKey(const ValueKey('confirm-one:3'));
    await tester.ensureVisible(confirm);
    await tester.tap(confirm);
    await tester.pump();
    final submit = find.byKey(const ValueKey('import-submit'));
    await tester.ensureVisible(submit);
    expect(
      tester.getSemantics(submit).hasFlag(SemanticsFlag.isEnabled),
      isTrue,
    );
    final root = tester.element(submit);
    var reached = false;
    for (var i = 0; i < 60 && !reached; i++) {
      final context = tester.binding.focusManager.primaryFocus?.context;
      if (context is Element) {
        var found = context == root;
        void visit(Element element) {
          if (found) return;
          if (element == context) {
            found = true;
            return;
          }
          element.visitChildren(visit);
        }

        if (!found) visit(root);
        reached = found;
      }
      if (!reached) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
    }
    expect(reached, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(calls, 1);
    semantics.dispose();
    expect(tester.takeException(), isNull);
  });
}
