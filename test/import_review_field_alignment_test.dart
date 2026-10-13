// Neumorphic: the labelled fields on the screenshot review page keep their
// value centered in the inset well instead of against its top edge.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:compoise/import_preview/draft_model.dart';
import 'package:compoise/import_preview/draft_preview.dart';
import 'package:compoise/models.dart';
import 'package:compoise/theme.dart';

void main() {
  testWidgets('neumorphic: review page values sit in the middle of the well', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(600, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final batch = DraftBatch.fromJson({
      'schema': 'wp17r2-draft/1',
      'images': [
        {
          'schema': 'wp17r2-draft/1',
          'id': 'one',
          'width': 1080,
          'height': 1403,
          'engine': 'ncnn-ppocrv5-mobile',
          'rows': [],
          'noise_lines': [],
          'notes': [],
          'tasks': [
            {
              'row': 3,
              'title': '周五前提交季度报告',
              'checked': false,
              'level': 0,
              'parent': null,
              'due': '周五',
              'needs_confirmation': [],
            },
          ],
          'dropped': [],
        },
      ],
    });
    batch.boardId = 'board';
    batch.quadrant = 1;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(
          Brightness.light,
          ThemeColor.purple,
          neumorphic: true,
        ),
        home: Scaffold(
          body: DraftPreview(
            batch: batch,
            language: Language.en,
            boards: const [ImportBoardChoice('board', 'My Tasks')],
            thumbnails: const {},
            onSubmit: (_) async {},
            onCancel: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    void centered(Finder field, Finder value) {
      final box = tester.getRect(field);
      final text = tester.getRect(value.first);
      // NeuInputBorder leaves a 16px band above the well for the label.
      final wellTop = box.top + 16;
      final above = text.top - wellTop;
      final below = wellTop + 48 - text.bottom;
      expect(above, greaterThanOrEqualTo(10), reason: '$value');
      expect((above - below).abs(), lessThanOrEqualTo(1), reason: '$value');
    }


    centered(find.byKey(const ValueKey('import-board')), find.text('My Tasks'));
    final task = batch.images.single.tasks.single;
    final title = find.byKey(ValueKey('title-${task.id}'));
    centered(
      title,
      find.descendant(of: title, matching: find.byType(EditableText)),
    );
    final parent = find.byKey(ValueKey('parent-${task.id}'));
    centered(
      parent,
      find.descendant(of: parent, matching: find.text('No parent')),
    );
  });
}
