import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/import_preview/draft_preview.dart';
import 'package:matrixflow_native/ocr/ocr_runtime.dart';
import 'package:matrixflow_native/screenshot_import/screenshot_capture.dart';

import 'support/wp17_i3a_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late File first;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('wp17-i3a-test-');
    first = await File('${temp.path}/private-first.png').writeAsBytes(png());
  });
  tearDown(() async {
    await temp.delete(recursive: true);
  });
  Future<File> write(String name, List<int> bytes) =>
      File('${temp.path}/$name').writeAsBytes(bytes);
  Future<OcrImageResult> recognize(
    String path,
    OcrCancellationToken token,
  ) async => result(path, [line('Buy milk', 50, 140), line('Eggs', 80, 200)]);

  test(
    'capture retains selection order and per-image failures, without leaking paths',
    () async {
      final broken = await write('broken.png', [1, 2, 3]);
      final jpeg = await write('wrong.jpg', png());
      final missingModel = await write('missing-model.png', png());
      final seen = <String>[];
      final capture = ScreenshotCapture.withRecognizer(
        recognize: (path, token) async {
          seen.add(path);
          if (path == missingModel.path) {
            return result(
              path,
              [],
              error: 'cannot read dict: private/model/path',
            );
          }
          return recognize(path, token);
        },
      );
      final batch = (await capture.captureFiles([
        picked(first),
        picked(broken),
        picked(jpeg),
        picked(missingModel),
        picked(first),
      ])).batch!;
      expect(batch.images.map((image) => image.id), [
        'image-1',
        'image-2',
        'image-3',
        'image-4',
        'image-5',
      ]);
      expect(batch.images.map((image) => image.failed), [
        false,
        true,
        true,
        true,
        false,
      ]);
      expect(batch.images[2].error, contains('only PNG'));
      expect(batch.images[3].error, contains('model files are missing'));
      expect(batch.images[3].error, isNot(contains('private')));
      expect(seen, [first.path, missingModel.path, first.path]);
      expect(batch.activeTasks.map((task) => task.title), [
        'Buy milk',
        'Eggs',
        'Buy milk',
        'Eggs',
      ]);
      expect(batch.duplicates.single.imageIds, ['image-1', 'image-5']);
      expect(batch.duplicates.single.reason, 'identical-bytes');
      batch.boardId = 'board';
      batch.quadrant = 1;
      for (final task in batch.activeTasks) {
        task.confirmed = true;
      }
      expect(batch.canSubmit, isFalse);
      batch.duplicates.single.acknowledged = true;
      expect(batch.canSubmit, isTrue);
      expect(batch.snapshot().tasks, hasLength(4));
      expect(
        batch.snapshot().tasks.every((task) => task.dueText == null),
        isTrue,
      );
    },
  );

  test('similar text is a hint only even when PNG bytes differ', () async {
    final dark = await write('dark.png', png(rgba: bitmap(dark: true)));
    final capture = ScreenshotCapture.withRecognizer(recognize: recognize);
    final batch = (await capture.captureFiles([
      picked(first),
      picked(dark),
    ])).batch!;
    expect(batch.duplicates.single.reason, 'char-jaccard=1.000');
    expect(batch.activeTasks, hasLength(4));
    expect(batch.activeTasks.every((task) => !task.confirmed), isTrue);
    batch.images.last.skipped = true;
    expect(batch.activeTasks, hasLength(2));
  });

  test(
    'picker cancellation/errors, empty batches and missing paths stay explicit',
    () async {
      expect(
        (await ScreenshotCapture.withRecognizer(
          recognize: recognize,
          picker: () async => null,
        ).pickAndCapture()).cancelled,
        isTrue,
      );
      expect(
        (await ScreenshotCapture.withRecognizer(
          recognize: recognize,
          picker: () async => throw StateError('PRIVATE'),
        ).pickAndCapture()).error,
        'Screenshot file selection failed.',
      );
      final capture = ScreenshotCapture.withRecognizer(recognize: recognize);
      expect(
        (await capture.captureFiles([])).error,
        contains('No screenshots'),
      );
      final batch = (await capture.captureFiles([
        PlatformFile(name: 'no-path.png', size: 20),
      ])).batch!;
      expect(batch.images.single.error, contains('no readable file path'));
      expect(batch.activeTasks, isEmpty);
    },
  );

  test('more than ten files are rejected before any decode or OCR', () async {
    var calls = 0;
    final capture = ScreenshotCapture.withRecognizer(
      recognize: (path, token) async {
        calls++;
        return recognize(path, token);
      },
      decodeMarks: (_, __, ___) async {
        calls++;
        return [];
      },
    );
    final output = await capture.captureFiles(List.filled(11, picked(first)));
    expect(output.error, contains('at most 10'));
    expect(output.batch, isNull);
    expect(calls, 0);
  });

  test(
    'real file size, signature, dimensions, corrupt pixels and APNG are checked',
    () async {
      var calls = 0;
      final capture = ScreenshotCapture.withRecognizer(
        recognize: (path, token) async {
          calls++;
          return recognize(path, token);
        },
      );
      final big = await write('oversize.png', const []);
      final bigHandle = await big.open(mode: FileMode.write);
      await bigHandle.truncate(ScreenshotLimits.maxFileBytes + 1);
      await bigHandle.close();
      final cases = <File>[
        big,
        await write('empty.png', []),
        await write('fake.png', [255, 216, 255, 0]),
        await write('wide.png', png(width: 4097, headerOnly: true)),
        await write('tall.png', png(height: 8193, headerOnly: true)),
        await write(
          'pixels.png',
          png(width: 4000, height: 3200, headerOnly: true),
        ),
        await write('zero.png', png(width: 0, headerOnly: true)),
        await write('decode.png', png(headerOnly: true)),
      ];
      final base = png();
      final apng = Uint8List.fromList([
        ...base.sublist(0, 33),
        ...chunk('acTL', const [0, 0, 0, 100, 0, 0, 0, 0]),
        ...base.sublist(33),
      ]);
      cases.add(await write('animation.png', apng));
      final batch = (await capture.captureFiles(
        cases.map((file) => picked(file, declaredSize: 1)).toList(),
      )).batch!;
      expect(batch.images.every((image) => image.failed), isTrue);
      expect(batch.images.first.error, contains('16 MiB'));
      expect(batch.images[3].error, contains('dimensions'));
      expect(batch.images.last.error, contains('Animated PNG'));
      expect(calls, 0);
    },
  );

  test(
    '48 MiB batch budget stops reads/decodes, but later small images survive',
    () async {
      final large = await _sizedPng(
        '${temp.path}/large.png',
        ScreenshotLimits.maxFileBytes,
      );
      var decoded = 0;
      final capture = ScreenshotCapture.withRecognizer(
        recognize: (path, _) async => result(path, []),
        decodeMarks: (_, __, ___) async {
          decoded++;
          return [];
        },
      );
      final output = await capture.captureFiles([
        picked(large),
        picked(large),
        picked(first),
        picked(large),
        picked(first),
      ]);
      final batch = output.batch!;
      expect(batch.images.map((image) => image.failed), [
        false,
        false,
        false,
        true,
        false,
      ]);
      expect(batch.images[3].error, contains('48 MiB'));
      expect(decoded, 4);
    },
  );

  test(
    '24 Mi-pixel budget stops decode before allocation, including failed OCR',
    () async {
      final large = await write(
        'max-pixels.png',
        png(width: 4096, height: 3072, headerOnly: true),
      );
      var decoded = 0;
      final capture = ScreenshotCapture.withRecognizer(
        recognize: (path, _) async =>
            result(path, [], width: 4096, height: 3072, error: 'failure'),
        decodeMarks: (_, __, ___) async {
          decoded++;
          return [];
        },
      );
      final batch = (await capture.captureFiles(
        List.filled(3, picked(large)),
      )).batch!;
      expect(decoded, 2);
      expect(batch.images.last.error, contains('24 Mi-pixel'));
    },
  );

  test(
    'dimensions, malformed OCR and arbitrary exceptions are per-image failures',
    () async {
      var i = 0;
      final capture = ScreenshotCapture.withRecognizer(
        recognize: (path, _) async {
          i++;
          if (i == 1) return result(path, [], width: 401);
          if (i == 2) return result(path, [line('PRIVATE', double.nan, 140)]);
          if (i == 3) throw StateError('PRIVATE path/recognized-text');
          return recognize(path, OcrCancellationToken());
        },
      );
      final batch = (await capture.captureFiles(
        List.filled(4, picked(first)),
      )).batch!;
      expect(batch.images.map((image) => image.failed), [
        true,
        true,
        true,
        false,
      ]);
      expect(
        batch.images
            .take(3)
            .every((image) => !image.error!.contains('PRIVATE')),
        isTrue,
      );
    },
  );

  test(
    'dispose during picker or native await suppresses stale draft results',
    () async {
      final selection = Completer<List<PlatformFile>?>();
      final capture = ScreenshotCapture.withRecognizer(
        recognize: recognize,
        picker: () => selection.future,
      );
      final pending = capture.pickAndCapture();
      capture.dispose();
      selection.complete([picked(first)]);
      expect((await pending).cancelled, isTrue);
      final entered = Completer<void>();
      final raw = Completer<OcrImageResult>();
      final active = ScreenshotCapture.withRecognizer(
        recognize: (path, _) {
          entered.complete();
          return raw.future;
        },
      );
      final processing = active.captureFiles([picked(first)]);
      await entered.future;
      expect(
        (await active.captureFiles([picked(first)])).error,
        contains('already running'),
      );
      active.dispose();
      raw.complete(result(first.path, []));
      expect((await processing).batch, isNull);
    },
  );

  test(
    'external cancellation preserves one failed image for each selection',
    () async {
      final token = OcrCancellationToken()..cancel();
      var calls = 0;
      final capture = ScreenshotCapture.withRecognizer(
        recognize: (path, _) async {
          calls++;
          return result(path, []);
        },
      );
      final batch = (await capture.captureFiles(
        List.filled(3, picked(first)),
        cancellation: token,
      )).batch!;
      expect(batch.images, hasLength(3));
      expect(batch.images.every((image) => image.failed), isTrue);
      expect(calls, 0);
    },
  );

  test(
    'captures across separate instances share one bitmap/native queue',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      var calls = 0;
      Future<OcrImageResult> controlled(
        String path,
        OcrCancellationToken _,
      ) async {
        calls++;
        if (calls == 1) {
          entered.complete();
          await release.future;
        }
        return result(path, []);
      }

      final a = ScreenshotCapture.withRecognizer(recognize: controlled);
      final b = ScreenshotCapture.withRecognizer(recognize: controlled);
      final p1 = a.captureFiles([picked(first)]);
      await entered.future;
      final p2 = b.captureFiles([picked(first)]);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(calls, 1);
      b.dispose();
      release.complete();
      expect((await p1).batch, isNotNull);
      expect((await p2).cancelled, isTrue);
      expect(calls, 1);
    },
  );

  testWidgets(
    'missing models are displayed by existing preview and cannot submit',
    (tester) async {
      final capture = ScreenshotCapture(
        runtime: OcrRuntime(
          assetsRoot: '${temp.path}/missing-models',
          libraryPath: 'never-loaded',
        ),
      );
      final output = await tester.runAsync(
        () => capture.captureFiles([picked(first)]),
      );
      var submits = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DraftPreview(
              batch: output!.batch!,
              boards: const [ImportBoardChoice('board', 'Board')],
              onSubmit: (_) async {
                submits++;
              },
              onCancel: () {},
            ),
          ),
        ),
      );
      expect(
        find.textContaining('OCR model files are missing'),
        findsOneWidget,
      );
      expect(find.textContaining('not formally available'), findsOneWidget);
      expect(output.batch!.canSubmit, isFalse);
      expect(submits, 0);
    },
  );

  final raw =
      jsonDecode(
            File(
              'docs/evidence/wp17r2/results/win/raw/ncnn-cpu-t4/all.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  test(
    'a source changed during OCR fails instead of mixing text and gutter evidence',
    () async {
      final capture = ScreenshotCapture.withRecognizer(
        recognize: (path, _) async {
          await File(path).writeAsBytes([1, 2, 3]);
          return recognize(path, OcrCancellationToken());
        },
      );
      final batch = (await capture.captureFiles([picked(first)])).batch!;
      expect(batch.images.single.error, contains('changed during OCR'));
      expect(batch.activeTasks, isEmpty);
    },
  );

  test(
    'cancel during model preflight prevents both bitmap decode and OCR',
    () async {
      final entered = Completer<void>();
      final modelCheck = Completer<String?>();
      var calls = 0;
      final capture = ScreenshotCapture.withRecognizer(
        recognize: (path, _) async {
          calls++;
          return result(path, []);
        },
        modelAvailability: () {
          entered.complete();
          return modelCheck.future;
        },
        decodeMarks: (_, __, ___) async {
          calls++;
          return [];
        },
      );
      final pending = capture.captureFiles([picked(first)]);
      await entered.future;
      capture.cancel();
      modelCheck.complete(null);
      expect((await pending).cancelled, isTrue);
      expect(calls, 0);
    },
  );

  for (final source in raw['images'] as List) {
    final expected = source as Map<String, dynamic>;
    final name = (expected['path'] as String)
        .replaceAll('\\', '/')
        .split('/')
        .last;
    test(
      'injected R2 OCR + real PNG scan reproduces reference draft: $name',
      () async {
        final file = File('docs/evidence/wp17r2/samples/images/$name');
        final capture = ScreenshotCapture.withRecognizer(
          recognize: (path, _) async => OcrImageResult.fromJson(path, expected),
        );
        final batch = (await capture.captureFiles([picked(file)])).batch!;
        expect(batch.images.single.error, isNull);
        final reference =
            (jsonDecode(
                      File(
                        'docs/evidence/wp17r2/results/win/diffs/ncnn-cpu-t4/${name.replaceAll('.png', '')}.json',
                      ).readAsStringSync(),
                    )
                    as Map)['draft']
                as Map;
        final tasks = reference['tasks'] as List;
        expect(
          batch.activeTasks.map((task) => task.title),
          tasks.map((task) => task['title']),
        );
        expect(
          batch.activeTasks.map((task) => task.checked),
          tasks.map((task) => task['checked']),
        );
        expect(
          batch.activeTasks.map((task) => task.dueText),
          tasks.map((task) => task['due']),
        );
        expect(
          batch.activeTasks.map((task) => task.parentId),
          tasks.map(
            (task) =>
                task['parent'] == null ? null : 'image-1:${task['parent']}',
          ),
        );
        expect(
          batch.images.single.tasks
              .where((task) => task.excluded)
              .map((task) => task.title),
          (reference['dropped'] as List).map((row) => row['text']),
        );
        expect(batch.activeTasks.every((task) => !task.confirmed), isTrue);
      },
    );
  }
}

Future<File> _sizedPng(String path, int size) async {
  final base = png(headerOnly: true);
  final file = File(path);
  final handle = await file.open(mode: FileMode.write);
  try {
    await handle.writeFrom(base.sublist(0, base.length - 12));
    final header = ByteData(8)
      ..setUint32(0, size - base.length - 12)
      ..setUint32(4, 0x74455874);
    await handle.writeFrom(header.buffer.asUint8List());
    await handle.setPosition(size - 16);
    await handle.writeFrom(Uint8List(4));
    await handle.writeFrom(base.sublist(base.length - 12));
  } finally {
    await handle.close();
  }
  return file;
}
