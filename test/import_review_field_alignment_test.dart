// Neumorphic: the labelled fields on the screenshot review page keep their
// value centered in the inset well instead of against its top edge.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:compoise/import_preview/draft_model.dart';
import 'package:compoise/import_preview/draft_preview.dart';
import 'package:compoise/models.dart';
import 'package:compoise/theme.dart';

import 'support/field_center_probe.dart';

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

    await tester.tap(find.byKey(const ValueKey('options-one:3')));
    await tester.pumpAndSettle();
    final fields = measureFields(tester);
    expect(fields.length, greaterThanOrEqualTo(4));
    expect(offCenterFields(tester), isEmpty);
  });
}
