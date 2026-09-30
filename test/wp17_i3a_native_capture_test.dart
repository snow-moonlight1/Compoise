import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/ocr/ocr_runtime.dart';
import 'package:matrixflow_native/screenshot_import/screenshot_capture.dart';

import 'support/wp17_i3a_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final library = Platform.environment['WP17_OCR_TEST_LIBRARY'];
  final assets = Platform.environment['WP17_OCR_TEST_ASSETS'];
  final enabled = library != null && assets != null;
  final labels =
      jsonDecode(
            File('docs/evidence/wp17r2/samples/labels.json').readAsStringSync(),
          )
          as Map;

  test(
    'external native OCR -> PNG scan -> DraftBatch matches all 12 R2 reference drafts',
    () async {
      final capture = ScreenshotCapture(
        runtime: OcrRuntime(assetsRoot: assets!, libraryPath: library!),
      );
      var taskCount = 0;
      for (final sample in labels['cases'] as List) {
        final id = sample['id'] as String;
        final file = File('docs/evidence/wp17r2/samples/${sample['file']}');
        final batch = (await capture.captureFiles([picked(file)])).batch!;
        expect(batch.images.single.error, isNull, reason: id);
        final reference =
            (jsonDecode(
                      File(
                        'docs/evidence/wp17r2/results/win/diffs/ncnn-cpu-t4/$id.json',
                      ).readAsStringSync(),
                    )
                    as Map)['draft']
                as Map;
        final tasks = reference['tasks'] as List;
        expect(
          batch.activeTasks.map((task) => task.title),
          tasks.map((task) => task['title']),
          reason: id,
        );
        expect(
          batch.activeTasks.map((task) => task.checked),
          tasks.map((task) => task['checked']),
          reason: id,
        );
        expect(
          batch.activeTasks.map((task) => task.dueText),
          tasks.map((task) => task['due']),
          reason: id,
        );
        expect(
          batch.activeTasks.map((task) => task.parentId),
          tasks.map(
            (task) =>
                task['parent'] == null ? null : 'image-1:${task['parent']}',
          ),
          reason: id,
        );
        expect(batch.activeTasks.every((task) => !task.confirmed), isTrue);
        taskCount += batch.activeTasks.length;
      }
      expect(taskCount, 128);
    },
    skip: !enabled,
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'external native ten-image capture retains input order and requires review',
    () async {
      final capture = ScreenshotCapture(
        runtime: OcrRuntime(assetsRoot: assets!, libraryPath: library!),
      );
      final ids = (labels['batch_of_10'] as List).cast<String>();
      final files = [
        for (final id in ids)
          picked(File('docs/evidence/wp17r2/samples/images/$id.png')),
      ];
      final batch = (await capture.captureFiles(files)).batch!;
      expect(batch.images.map((image) => image.id), [
        for (var i = 1; i <= 10; i++) 'image-$i',
      ]);
      expect(batch.images.every((image) => !image.failed), isTrue);
      expect(batch.activeTasks.every((task) => !task.confirmed), isTrue);
      expect(batch.canSubmit, isFalse);
    },
    skip: !enabled,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
