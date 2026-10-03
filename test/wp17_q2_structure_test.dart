import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/import_preview/draft_model.dart';
import 'package:matrixflow_native/ocr/ocr_runtime.dart';
import 'package:matrixflow_native/screenshot_import/gutter_scan.dart';
import 'package:matrixflow_native/screenshot_import/screenshot_adapter.dart';
import 'package:matrixflow_native/screenshot_import/screenshot_capture.dart';

import 'support/wp17_i3a_fixtures.dart';

/// Q1 scene table. Checkbox geometry matches q1_quality.py: a 28px rectangle
/// whose inclusive extent is 29px, placed 62px left of the text.
const _scenes = [
  _Scene('small-light', 960, 1024, 18, 60, false, [
    _Task('整理项目 2026-10-03', false, 0),
    _Task('复查数字 0123456789', true, 1),
    _Task('提交报告 Q1', false, 0),
  ]),
  _Scene('large-dark', 960, 1280, 42, 110, true, [
    _Task('今晚整理资料', true, 0),
    _Task('明天 2026/10/04 09:30', false, 1),
    _Task('检查预算 128.50 元', false, 0),
  ]),
  _Scene('mixed-light', 1080, 1400, 32, 94, false, [
    _Task('Review 报告 レポート 2026-10-03', false, 0),
    _Task('確認 Task 12 完了', true, 1),
    _Task('会议 meeting 会議 09:30', false, 0),
  ]),
  _Scene('mixed-dark', 1080, 1400, 28, 94, true, [
    _Task('检查 API v5 2026/10/03', false, 0),
    _Task('Write tests 测试 42', true, 1),
    _Task('確認資料 report 100%', false, 0),
  ]),
  _Scene('dense-subtasks', 960, 1280, 24, 44, false, [
    _Task('发布前检查', false, 0),
    _Task('准备模型文件', true, 1),
    _Task('核对 SHA256 123456', false, 1),
    _Task('复查日期 2026-10-04', false, 1),
    _Task('提交变更', false, 0),
    _Task('运行单元测试', true, 1),
    _Task('Review code 12', false, 1),
    _Task('保存证据', false, 1),
    _Task('归档记录', true, 0),
  ]),
  _Scene('long-lines', 1600, 1100, 32, 130, false, [
    _Task(
      'Review the complete offline OCR report and check every task before saving',
      false,
      0,
    ),
    _Task(
      'Numbers 0123456789 dates 2026-10-03 and time 09:30 remain editable',
      true,
      0,
    ),
  ]),
  _Scene('tiny-dense', 960, 1024, 14, 40, true, [
    _Task('测试很小的文字 2026-10-03', false, 0),
    _Task('嵌套子任务 0123456789', true, 1),
    _Task('保存结果不自动写入日程', false, 0),
    _Task('English small text 42', false, 1),
  ]),
  _Scene('japanese', 1080, 1280, 36, 100, false, [
    _Task('会議の資料を確認する', false, 0),
    _Task('レポートを作成 2026/10/03', true, 1),
    _Task('買い物リスト 12345', false, 0),
  ]),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const adapter = ScreenshotDraftAdapter();

  test('legacy width-fraction marks keep their R2 geometry', () {
    final marks = scanGutter(bitmap(), 400, 400);
    expect(marks.map((mark) => mark.box), [
      [12.0, 140.0, 17.0, 16.0],
      [40.0, 200.0, 17.0, 16.0],
    ]);
    expect(marks.every((mark) => mark.sizedByWidthFraction), isTrue);
    expect(marks.map((mark) => mark.checked), [false, true]);
  });

  test(
    'Q1 scenes reproduce all 30 tasks, including the two wide long lines',
    () {
      expect(_scenes.fold<int>(0, (n, scene) => n + scene.tasks.length), 30);
      // The historical rule drops a 29px control on a 1600px image.
      expect(0.022 * 1600, greaterThan(29));
      final seen = <String>[];
      for (final scene in _scenes) {
        final drawn = _drawScene(scene);
        final marks = scanGutter(drawn.rgba, scene.width, scene.height);
        expect(marks, hasLength(scene.tasks.length), reason: scene.id);
        final rescued = scene.id == 'long-lines';
        expect(
          marks.every((mark) => mark.sizedByWidthFraction == !rescued),
          isTrue,
          reason: scene.id,
        );
        if (rescued) {
          expect(
            marks.every(
              (mark) =>
                  mark.box[2] < 0.022 * scene.width &&
                  mark.box[3] < 0.022 * scene.width,
            ),
            isTrue,
          );
        }
        final wire = adapter.adapt(
          id: scene.id,
          result: result(
            scene.id,
            drawn.lines,
            width: scene.width,
            height: scene.height,
          ),
          marks: marks,
        );
        final tasks = (wire['tasks'] as List).cast<Map<String, dynamic>>();
        expect(tasks, hasLength(scene.tasks.length), reason: scene.id);
        int? lastRoot;
        for (var i = 0; i < scene.tasks.length; i++) {
          final want = scene.tasks[i];
          final parent = want.level == 0 ? null : lastRoot;
          if (want.level == 0) lastRoot = i;
          expect(tasks[i]['title'], want.title, reason: scene.id);
          expect(tasks[i]['checked'], want.checked, reason: '${scene.id}#$i');
          expect(tasks[i]['level'], want.level, reason: '${scene.id}#$i');
          expect(tasks[i]['parent'], parent, reason: '${scene.id}#$i');
          expect(tasks[i]['due'], isNull, reason: scene.id);
          seen.add(want.title);
        }
        final batch = DraftBatch.fromJson(wire)
          ..boardId = 'board'
          ..quadrant = 1;
        expect(batch.activeTasks.every((task) => !task.confirmed), isTrue);
        expect(batch.canSubmit, isFalse, reason: scene.id);
      }
      expect(seen, hasLength(30));
    },
  );

  test('recorded long-line OCR boxes still become the two missed tasks', () {
    final rgba = _blank(1600, 1100, 248);
    _square(rgba, 1600, 50, 514, 29, 26);
    _square(rgba, 1600, 50, 644, 29, 26, filled: true);
    final marks = scanGutter(rgba, 1600, 1100);
    expect(marks, hasLength(2));
    expect(marks.every((mark) => !mark.sizedByWidthFraction), isTrue);
    final wire = adapter.adapt(
      id: 'long-lines',
      marks: marks,
      result: result(
        'long-lines',
        [
          OcrLine(
            text:
                'ReviewthecompleteofflineOCRreportandcheckeverytaskbeforesaving',
            box: [37.14, 503.8, 1150.73, 65.73],
            score: 0.953,
          ),
          OcrLine(
            text: 'Numbers0123456789dates2026-10-03andtime09:30remaineditable',
            box: [39.54, 634.54, 1097.58, 57.58],
            score: 0.9824,
          ),
        ],
        width: 1600,
        height: 1100,
      ),
    );
    final tasks = (wire['tasks'] as List).cast<Map<String, dynamic>>();
    expect(tasks.map((task) => task['checked']), [false, true]);
    expect(tasks.map((task) => task['level']), [0, 0]);
    expect(tasks.map((task) => task['parent']), [null, null]);
    expect(tasks.map((task) => task['due']), [null, null]);
    expect(tasks.map((task) => task['title']), [
      'ReviewthecompleteofflineOCRreportandcheckeverytaskbeforesaving',
      'Numbers0123456789dates2026-10-03andtime09:30remaineditable',
    ]);
  });

  test(
    'scaled, multiline, icon, date and body ink do not invent checkboxes',
    () {
      final scaled = _blank(1200, 800, 248);
      _square(scaled, 1200, 40, 300, 22, 26, filled: true);
      final scaledMarks = scanGutter(scaled, 1200, 800);
      expect(scaledMarks.single.sizedByWidthFraction, isFalse);
      final scaledWire = adapter.adapt(
        id: 'scaled',
        marks: scaledMarks,
        result: result(
          'scaled',
          [
            OcrLine(
              text: 'Scaled checkbox still follows the line height',
              box: [80, 292, 640, 40],
              score: 0.99,
            ),
          ],
          width: 1200,
          height: 800,
        ),
      );
      final scaledTask = (scaledWire['tasks'] as List).single;
      expect(scaledTask['checked'], isTrue);
      expect(scaledTask['level'], 0);

      final multi = _blank(1600, 700, 248);
      _square(multi, 1600, 50, 422, 29, 26);
      final multiMarks = scanGutter(multi, 1600, 700);
      final multiWire = adapter.adapt(
        id: 'multi',
        marks: multiMarks,
        result: result(
          'multi',
          [
            OcrLine(text: '第一行还没写完', box: [112, 420, 280, 28], score: 0.99),
            OcrLine(text: '第二行继续', box: [112, 430, 180, 28], score: 0.99),
          ],
          width: 1600,
          height: 700,
        ),
      );
      final multiTasks = multiWire['tasks'] as List;
      expect(multiTasks, hasLength(1));
      expect(multiTasks.single['title'], '第一行还没写完第二行继续');
      expect(multiTasks.single['checked'], isFalse);

      final noisy = _blank(1600, 800, 248);
      _square(noisy, 1600, 30, 400, 10, 26, filled: true);
      _bar(noisy, 1600, 40, 480, 90, 14, 26);
      for (var i = 0; i < 5; i++) {
        _square(noisy, 1600, 36 + i * 24, 560, 20, 26, filled: true);
      }
      final noisyMarks = scanGutter(noisy, 1600, 800);
      expect(noisyMarks, isEmpty);
      final noisyWire = adapter.adapt(
        id: 'noise',
        marks: noisyMarks,
        result: result(
          'noise',
          [
            OcrLine(text: '正文没有复选框', box: [80, 390, 240, 32], score: 0.99),
            OcrLine(text: '2026-10-03', box: [1100, 470, 160, 28], score: 0.99),
            OcrLine(text: '图标和笔画都不是任务', box: [80, 550, 280, 32], score: 0.99),
          ],
          width: 1600,
          height: 800,
        ),
      );
      expect(noisyWire['tasks'], isEmpty);
      expect((noisyWire['dropped'] as List).map((row) => row['kind']), [
        'section',
        'meta',
        'section',
      ]);

      final header = _blank(1080, 400, 248);
      _square(header, 1080, 54, 250, 18, 26, filled: true);
      final headerMarks = scanGutter(header, 1080, 400);
      final headerWire = adapter.adapt(
        id: 'header',
        marks: headerMarks,
        result: result(
          'header',
          [
            OcrLine(text: '今日', box: [40, 238, 78, 50], score: 0.99),
          ],
          width: 1080,
          height: 400,
        ),
      );
      expect(headerWire['tasks'], isEmpty);
      expect((headerWire['dropped'] as List).single['text'], '今日');
    },
  );

  test('a long line with a mismatched square stays an unconfirmed candidate', () {
    final rgba = _blank(1600, 700, 248);
    _square(rgba, 1600, 36, 420, 28, 26, filled: true);
    final wire = adapter.adapt(
      id: 'unsure',
      marks: scanGutter(rgba, 1600, 700),
      result: result(
        'unsure',
        [
          OcrLine(
            text:
                'This line is long enough to be a task but the square is too small for its text',
            box: [40, 400, 980, 80],
            score: 0.99,
          ),
        ],
        width: 1600,
        height: 700,
      ),
    );
    final task = (wire['tasks'] as List).single as Map<String, dynamic>;
    expect(task['checked'], isFalse);
    expect(task['checkbox_box'], isNull);
    expect(task['level'], 0);
    expect(task['parent'], isNull);
    expect(
      task['needs_confirmation'],
      contains(
        'task structure is uncertain; checkbox size does not match the text',
      ),
    );
    final batch = DraftBatch.fromJson(wire)
      ..boardId = 'board'
      ..quadrant = 1;
    expect(batch.activeTasks.single.confirmed, isFalse);
    expect(batch.canSubmit, isFalse);
  });

  test('blank out-of-range boxes produce no task and real text still fails', () {
    final blank = adapter.adapt(
      id: 'tiny',
      marks: const [],
      result: OcrImageResult(
        path: 'tiny.png',
        width: 8,
        height: 8,
        lines: const [
          OcrLine(text: '', box: [-0.25, -1.25, 10.5, 10.5], score: 0),
        ],
      ),
    );
    expect(blank['tasks'], isEmpty);
    expect(blank['noise_lines'], isEmpty);
    expect(
      blank['notes'],
      contains(
        '1 blank recognition box(es) were outside the image; no task was created',
      ),
    );
    final batch = DraftBatch.fromJson(blank);
    expect(batch.images.single.error, isNull);
    expect(batch.activeTasks, isEmpty);
    expect(batch.canSubmit, isFalse);

    expect(
      () => adapter.adapt(
        id: 'bad',
        marks: const [],
        result: OcrImageResult(
          path: 'bad.png',
          width: 8,
          height: 8,
          lines: const [
            OcrLine(text: '买菜', box: [-0.25, -1.25, 10.5, 10.5], score: 0.9),
          ],
        ),
      ),
      throwsFormatException,
    );
    expect(
      () => adapter.adapt(
        id: 'nan',
        marks: const [],
        result: OcrImageResult(
          path: 'nan.png',
          width: 8,
          height: 8,
          lines: [
            OcrLine(text: '', box: [double.nan, 0, 1, 1], score: 0),
          ],
        ),
      ),
      throwsFormatException,
    );
  });

  test(
    'capture keeps a blank tiny image and rejects non-empty overflow',
    () async {
      final temp = await Directory.systemTemp.createTemp('wp17-q2-');
      try {
        final file = File('${temp.path}/tiny.png');
        await file.writeAsBytes(
          png(width: 8, height: 8, rgba: _blank(8, 8, 255)),
        );
        final blank = ScreenshotCapture.withRecognizer(
          recognize: (path, _) async => OcrImageResult(
            path: path,
            width: 8,
            height: 8,
            lines: const [
              OcrLine(text: '', box: [-0.25, -1.25, 10.5, 10.5], score: 0),
            ],
          ),
        );
        final blankBatch = (await blank.captureFiles([picked(file)])).batch!;
        expect(blankBatch.images.single.error, isNull);
        expect(blankBatch.activeTasks, isEmpty);
        expect(
          blankBatch.images.single.notes.join('\n'),
          contains('outside the image'),
        );

        final rejected = ScreenshotCapture.withRecognizer(
          recognize: (path, _) async => OcrImageResult(
            path: path,
            width: 8,
            height: 8,
            lines: const [
              OcrLine(text: '买菜', box: [-0.25, -1.25, 10.5, 10.5], score: 0.9),
            ],
          ),
        );
        final rejectedBatch = (await rejected.captureFiles([
          picked(file),
        ])).batch!;
        expect(rejectedBatch.images.single.error, contains('Invalid PNG'));
        expect(rejectedBatch.activeTasks, isEmpty);
      } finally {
        await temp.delete(recursive: true);
      }
    },
  );

  test(
    'recorded Q1 fixtures reproduce 30 tasks when WP17_Q2_FIXTURES is set',
    () async {
      final root = Platform.environment['WP17_Q2_FIXTURES'];
      if (root == null || root.isEmpty) {
        markTestSkipped('set WP17_Q2_FIXTURES to the Q1 synthetic directory');
        return;
      }
      final labels =
          jsonDecode(await File('$root/labels.json').readAsString()) as Map;
      final raw =
          jsonDecode(await File('$root/native-raw.json').readAsString())
              as List;
      final byId = {
        for (final row in raw.cast<Map>()) row['id'] as String: row,
      };
      var matched = 0;
      for (final scene in (labels['cases'] as List).cast<Map>()) {
        final id = scene['id'] as String;
        final ocr = byId[id]!;
        final capture = ScreenshotCapture.withRecognizer(
          recognize: (path, _) async => OcrImageResult(
            path: path,
            width: ocr['width'] as int,
            height: ocr['height'] as int,
            lines: [
              for (final line in (ocr['lines'] as List).cast<Map>())
                OcrLine(
                  text: line['text'] as String,
                  box: (line['box'] as List)
                      .map((value) => (value as num).toDouble())
                      .toList(),
                  score: (line['score'] as num).toDouble(),
                ),
            ],
          ),
        );
        final batch = (await capture.captureFiles([
          picked(File('$root/$id.png')),
        ])).batch!;
        expect(batch.images.single.error, isNull, reason: id);
        final got = batch.activeTasks;
        final want = (scene['tasks'] as List).cast<Map>();
        final paired = _pairByQ1Distance(want, got);
        if (paired.any((task) => task == null) || got.length != want.length) {
          fail(
            '$id got ${got.length} ${got.map((task) => task.title).toList()} '
            'want ${want.length} ${want.map((task) => task['title']).toList()}',
          );
        }
        for (var i = 0; i < want.length; i++) {
          expect(paired[i]!.checked, want[i]['checked'], reason: '$id#$i');
          expect(paired[i]!.dueText, isNull, reason: id);
          expect(paired[i]!.confirmed, isFalse);
          final parent = want[i]['parent'];
          expect(
            paired[i]!.parentId,
            parent == null ? null : paired[parent as int]!.id,
            reason: '$id#$i',
          );
          matched++;
        }
      }
      expect(matched, 30);
    },
  );
}

String _norm(String text) => text.replaceAll(RegExp(r'\s+'), '');

/// Q1 `score()` pairs each ground-truth title to an unused draft by
/// whitespace-stripped Levenshtein / reference length, accepting <= 0.35.
/// OCR on mixed-light joins a nearby glyph into "確認Task12完了"; exact equality
/// rejects that line even when checked and parent stay correct.
List<dynamic> _pairByQ1Distance(List<Map> want, List<dynamic> got) {
  final used = <int>{};
  final paired = <dynamic>[];
  for (final task in want) {
    final reference = _norm(task['title'] as String);
    var best = 2.0;
    var bestIndex = -1;
    for (var index = 0; index < got.length; index++) {
      if (used.contains(index)) continue;
      final distance =
          _levenshtein(reference, _norm(got[index].title as String)) /
          (reference.isEmpty ? 1 : reference.length);
      if (distance < best) {
        best = distance;
        bestIndex = index;
      }
    }
    if (bestIndex >= 0 && best <= 0.35) {
      used.add(bestIndex);
      paired.add(got[bestIndex]);
    } else {
      paired.add(null);
    }
  }
  return paired;
}

int _levenshtein(String a, String b) {
  final left = a.runes.toList();
  final right = b.runes.toList();
  if (a == b) return 0;
  if (left.isEmpty) return right.length;
  if (right.isEmpty) return left.length;
  var previous = List<int>.generate(right.length + 1, (index) => index);
  for (var i = 0; i < left.length; i++) {
    final current = <int>[i + 1];
    for (var j = 0; j < right.length; j++) {
      final substitute = left[i] == right[j] ? 0 : 1;
      current.add(
        [
          previous[j + 1] + 1,
          current[j] + 1,
          previous[j] + substitute,
        ].reduce((x, y) => x < y ? x : y),
      );
    }
    previous = current;
  }
  return previous.last;
}

Uint8List _blank(int width, int height, int rgb) {
  final bytes = Uint8List(width * height * 4);
  for (var i = 0; i < bytes.length; i += 4) {
    bytes[i] = bytes[i + 1] = bytes[i + 2] = rgb;
    bytes[i + 3] = 255;
  }
  return bytes;
}

void _square(
  Uint8List rgba,
  int width,
  int left,
  int top,
  int span,
  int rgb, {
  bool filled = false,
  int stroke = 2,
}) {
  for (var y = top; y < top + span; y++) {
    for (var x = left; x < left + span; x++) {
      final border =
          x < left + stroke ||
          y < top + stroke ||
          x >= left + span - stroke ||
          y >= top + span - stroke;
      if (!filled && !border) continue;
      final pixel = (y * width + x) * 4;
      rgba[pixel] = rgba[pixel + 1] = rgba[pixel + 2] = rgb;
    }
  }
}

void _bar(
  Uint8List rgba,
  int width,
  int left,
  int top,
  int barWidth,
  int barHeight,
  int rgb,
) {
  for (var y = top; y < top + barHeight; y++) {
    for (var x = left; x < left + barWidth; x++) {
      final pixel = (y * width + x) * 4;
      rgba[pixel] = rgba[pixel + 1] = rgba[pixel + 2] = rgb;
    }
  }
}

({Uint8List rgba, List<OcrLine> lines}) _drawScene(_Scene scene) {
  final rgba = _blank(scene.width, scene.height, scene.dark ? 24 : 248);
  final ink = scene.dark ? 234 : 26;
  final lines = <OcrLine>[];
  final origin = (0.32 * scene.width).floor();
  for (var i = 0; i < scene.tasks.length; i++) {
    final task = scene.tasks[i];
    final textX = 112 + task.level * 52;
    final textY = origin + i * scene.spacing;
    final boxX = textX - 62;
    final boxY = textY + (scene.font - 28 > 0 ? (scene.font - 28) ~/ 2 : 0);
    _square(rgba, scene.width, boxX, boxY, 29, ink, filled: task.checked);
    lines.add(
      OcrLine(
        text: task.title,
        box: [textX.toDouble(), textY.toDouble(), 240, scene.font.toDouble()],
        score: 0.99,
      ),
    );
  }
  return (rgba: rgba, lines: lines);
}

final class _Scene {
  const _Scene(
    this.id,
    this.width,
    this.height,
    this.font,
    this.spacing,
    this.dark,
    this.tasks,
  );
  final String id;
  final int width;
  final int height;
  final int font;
  final int spacing;
  final bool dark;
  final List<_Task> tasks;
}

final class _Task {
  const _Task(this.title, this.checked, this.level);
  final String title;
  final bool checked;
  final int level;
}
