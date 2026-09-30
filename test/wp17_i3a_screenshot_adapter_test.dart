import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/import_preview/draft_model.dart';
import 'package:matrixflow_native/screenshot_import/gutter_scan.dart';
import 'package:matrixflow_native/screenshot_import/screenshot_adapter.dart';

import 'support/wp17_i3a_fixtures.dart';

void main() {
  const adapter = ScreenshotDraftAdapter();
  test(
    'gutter scan uses pixels in light and dark themes, never OCR glyphs',
    () {
      for (final dark in [false, true]) {
        final marks = scanGutter(bitmap(dark: dark), 400, 400);
        expect(marks, hasLength(2));
        expect(marks.map((mark) => mark.checked), [false, true]);
        expect(marks.first.box, [12, 140, 17, 16]);
        final wire = adapter.adapt(
          id: 'a',
          marks: marks,
          result: result('PRIVATE.png', [
            line('√', 14, 140, width: 10),
            line('Buy milk', 50, 140),
            line('Eggs', 80, 200),
          ]),
        );
        final tasks = wire['tasks'] as List;
        expect(tasks.map((task) => task['title']), ['Buy milk', 'Eggs']);
        expect(tasks.map((task) => task['checked']), [false, true]);
        expect(tasks.first['line_indices'], [1]);
        expect(tasks.first['anchor_line'], 1);
        expect(tasks.last['level'], 1);
        expect(tasks.last['parent'], 0);
        expect(jsonEncode(wire), isNot(contains('PRIVATE')));
      }
    },
  );

  test(
    'sorts geometry and retains chrome, sections, meta, noise and raw date',
    () {
      final wire = adapter.adapt(
        id: 'a',
        marks: scanGutter(bitmap(), 400, 400),
        result: result('unused', [
          line('Eggs', 80, 200),
          line('Tomorrow 18:00?', 250, 142),
          line('Buy milk', 50, 140),
          line('Section', 15, 100),
          line('Count', 250, 280),
          line('9:41', 10, 10),
          line('\u200b \n', 10, 330),
        ]),
      );
      expect((wire['rows'] as List).map((row) => row['kind']), [
        'chrome',
        'section',
        'task',
        'task',
        'meta',
      ]);
      expect((wire['dropped'] as List).map((row) => row['text']), [
        '9:41',
        'Section',
        'Count',
      ]);
      expect(wire['noise_lines'], hasLength(1));
      final tasks = wire['tasks'] as List;
      expect(tasks.first['line_indices'], [2, 1]);
      expect(tasks.first['due'], 'Tomorrow 18:00?');
      expect(tasks.last['parent'], 2);
      final batch = DraftBatch.fromJson(wire);
      expect(
        batch.images.single.tasks.where((task) => task.excluded),
        hasLength(3),
      );
      expect(batch.activeTasks.first.dueText, 'Tomorrow 18:00?');
      expect(batch.activeTasks.last.parentId, 'a:2');
      expect(
        batch.activeTasks.every((task) => !task.confirmed && !task.keepDueText),
        isTrue,
      );
      expect(
        batch.activeTasks.first.reviewReasons,
        contains('date text needs review'),
      );
      expect(
        batch.activeTasks.every(
          (task) => task.reviewReasons.contains('indent/parent needs review'),
        ),
        isTrue,
      );
      expect(batch.canSubmit, isFalse);
    },
  );

  test('OCR check symbols without image-side marks stay excluded', () {
    final wire = adapter.adapt(
      id: 'a',
      marks: [],
      result: result('unused', [line('√ completed task', 15, 150)]),
    );
    final batch = DraftBatch.fromJson(wire);
    expect(batch.activeTasks, isEmpty);
    expect(batch.images.single.tasks.single.excluded, isTrue);
    expect(batch.images.single.tasks.single.checked, isFalse);
  });

  test(
    'ambiguous marks, orphan indent, split blocks and confidence need review',
    () {
      final wire = adapter.adapt(
        id: 'a',
        marks: const [
          GutterMark([40, 140, 17, 16], .5),
          GutterMark([70, 140, 17, 16], .8),
        ],
        result: result('unused', [
          line('one ', 90, 140, width: 20, score: .6),
          line('two ', 120, 140, width: 20),
          line('three', 160, 140, width: 20),
        ]),
      );
      final task = (wire['tasks'] as List).single;
      expect(task['parent'], isNull);
      expect(task['checked'], isFalse);
      final reasons = task['needs_confirmation'] as List;
      expect(reasons, contains('multiple gutter marks match this row'));
      expect(reasons, contains('indented task without a visible parent'));
      expect(
        reasons.any((reason) => (reason as String).contains('split/merge')),
        isTrue,
      );
      expect(reasons, contains('low OCR confidence; text needs review'));
    },
  );

  test(
    'missing title, glyph-only row and unmatched marks remain reviewable',
    () {
      final wire = adapter.adapt(
        id: 'a',
        marks: const [
          GutterMark([12, 140, 17, 16], .9),
          GutterMark([12, 200, 17, 16], .1),
          GutterMark([12, 300, 17, 16], .1),
        ],
        result: result('unused', [
          line('V', 14, 140, width: 10),
          line('date?', 260, 200),
        ]),
      );
      final tasks = wire['tasks'] as List;
      expect(
        tasks.first['needs_confirmation'],
        contains('only checkbox glyphs were recognized; title needs review'),
      );
      expect(tasks.last['title'], isEmpty);
      expect(
        tasks.last['needs_confirmation'],
        contains('task row has no left-aligned text'),
      );
      expect(wire['notes'], contains('1 gutter mark(s) matched no text row'));
      expect(DraftBatch.fromJson(wire).canSubmit, isFalse);
    },
  );

  test('invalid and excessive injected OCR cannot escape the adapter', () {
    for (final invalid in [
      line('invalid', -1, 140),
      line('invalid', double.nan, 140),
      line('invalid', 20, 140, score: double.infinity),
      line('invalid', 390, 140),
      line('x' * 8193, 20, 140),
    ]) {
      expect(
        () => adapter.adapt(
          id: 'a',
          marks: [],
          result: result('unused', [invalid]),
        ),
        throwsFormatException,
      );
    }
    expect(
      () => adapter.adapt(
        id: 'a',
        marks: [],
        result: result('unused', List.filled(2001, line('a', 20, 140))),
      ),
      throwsFormatException,
    );
    expect(
      () => adapter.adapt(
        id: 'a',
        marks: const [
          GutterMark([10, 140, 17, 16], 2),
        ],
        result: result('unused', []),
      ),
      throwsFormatException,
    );
  });

  test('resource bounded scanner rejects oversized or truncated bitmaps', () {
    expect(() => scanGutter(bitmap(), 4097, 400), throwsFormatException);
    expect(() => scanGutter(bitmap(), 400, 401), throwsFormatException);
  });
}
