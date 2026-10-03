import 'dart:math' as math;

import '../ocr/ocr_runtime.dart';
import 'gutter_scan.dart';

/// Pure wp17r2-draft/1 adapter; the returned wire objects are process memory.
/// Additional conservative reasons make every heuristic explicit in I2 review.
final class ScreenshotDraftAdapter {
  const ScreenshotDraftAdapter();

  Map<String, dynamic> adapt({
    required String id,
    required OcrImageResult result,
    required List<GutterMark> marks,
    String engine = 'ncnn-ppocrv5-mobile',
  }) {
    final w = result.width;
    final h = result.height;
    if (!result.succeeded ||
        w <= 0 ||
        h <= 0 ||
        w > 4096 ||
        h > 8192 ||
        w * h > 12 * 1024 * 1024 ||
        result.lines.length > 2000 ||
        marks.length > 2048) {
      throw const FormatException('invalid bounded OCR result');
    }
    var characters = 0;
    var blankOutside = 0;
    final kept = <int>[];
    final noise = <Map<String, dynamic>>[];
    for (final (i, line) in result.lines.indexed) {
      characters += line.text.length;
      if (characters > 128 * 1024 || line.text.length > 8192) {
        throw const FormatException('invalid OCR line or result too large');
      }
      if (!line.score.isFinite || line.score < 0 || line.score > 1) {
        throw const FormatException('invalid OCR line or result too large');
      }
      final usable = _usable(line.text);
      final boxOk = _validBox(line.box, w, h);
      if (usable.isEmpty) {
        // A blank recognizer box may sit outside a tiny image. That is an
        // empty result, not a task and not a reason to reject the picture.
        // Non-finite geometry is still corrupt.
        if (boxOk) {
          noise.add({'box': List<double>.of(line.box), 'score': line.score});
        } else if (_finiteQuad(line.box)) {
          blankOutside++;
        } else {
          throw const FormatException('invalid OCR line or result too large');
        }
      } else if (!boxOk) {
        throw const FormatException('invalid OCR line or result too large');
      } else {
        kept.add(i);
      }
    }
    for (final mark in marks) {
      if (!_validBox(mark.box, w, h) ||
          !mark.fill.isFinite ||
          mark.fill < 0 ||
          mark.fill > 1) {
        throw const FormatException('invalid gutter evidence');
      }
    }
    final lines = result.lines;
    kept.sort((a, b) {
      final order = _center(lines[a].box).compareTo(_center(lines[b].box));
      if (order != 0) return order;
      final horizontal = lines[a].box[0].compareTo(lines[b].box[0]);
      return horizontal != 0 ? horizontal : a.compareTo(b);
    });
    final groups = <_Row>[];
    for (final i in kept) {
      final box = lines[i].box;
      _Row? match;
      for (final row in groups) {
        final overlap =
            math.min(box[1] + box[3], row.bottom) - math.max(box[1], row.top);
        if (overlap > .5 * math.min(box[3], row.bottom - row.top)) {
          match = row;
          break;
        }
      }
      if (match == null) {
        groups.add(_Row([i], box[1], box[1] + box[3]));
      } else {
        match.indices.add(i);
        match.top = math.min(match.top, box[1]);
        match.bottom = math.max(match.bottom, box[1] + box[3]);
      }
    }
    groups.sort((a, b) => a.top.compareTo(b.top));
    final rows = <Map<String, dynamic>>[];
    final tasks = <Map<String, dynamic>>[];
    final dropped = <Map<String, dynamic>>[];
    final notes = <String>[];
    final used = <int>{};
    final sortedMarks = List<GutterMark>.of(marks)
      ..sort((a, b) => a.box[1].compareTo(b.box[1]));
    for (final (r, group) in groups.indexed) {
      final members = group.indices
        ..sort((a, b) {
          final x = lines[a].box[0].compareTo(lines[b].box[0]);
          return x != 0 ? x : a.compareTo(b);
        });
      final y =
          members.fold<double>(0, (v, i) => v + _center(lines[i].box)) /
          members.length;
      final candidates = <int>[
        for (var i = 0; i < sortedMarks.length; i++)
          if (!used.contains(i) &&
              _center(sortedMarks[i].box) >= group.top - 8 &&
              _center(sortedMarks[i].box) <= group.bottom + 8)
            i,
      ];
      final minX = members.map((i) => lines[i].box[0]).reduce(math.min);
      final legacy = <int>[
        for (final i in candidates)
          if (sortedMarks[i].sizedByWidthFraction) i,
      ];
      // Chrome and the historical width band stay on the old path. A rescued
      // square becomes a checkbox only when its shorter side matches the
      // line's character height and it sits at the start of that line.
      final rescued = y < .22 * w
          ? <int>[]
          : <int>[
              for (final i in candidates)
                if (!sortedMarks[i].sizedByWidthFraction &&
                    _rescuedMatches(sortedMarks[i], lines, members))
                  i,
            ];
      final chosen = legacy.isNotEmpty ? legacy : rescued;
      final markIndex = chosen.isEmpty ? null : chosen.first;
      final mark = markIndex == null ? null : sortedMarks[markIndex];
      final uncertain =
          mark == null &&
          y >= .22 * w &&
          minX <= .5 * w &&
          candidates.any(
            (i) =>
                !sortedMarks[i].sizedByWidthFraction &&
                _ambiguousRescue(sortedMarks[i], lines, members),
          );
      // A chrome row must not consume a mark needed by the next real row.
      if (markIndex != null && y >= .22 * w) used.add(markIndex);
      final kind = y < .22 * w
          ? 'chrome'
          : mark != null || uncertain
          ? 'task'
          : minX > .5 * w
          ? 'meta'
          : 'section';
      final text = members.map((i) => lines[i].text).join();
      rows.add({
        'index': r,
        'kind': kind,
        'line_indices': List<int>.of(members),
        'text': text,
        'y_center': (y * 100).round() / 100,
        'checkbox': mark == null
            ? null
            : {
                'box': List<double>.of(mark.box),
                'fill': mark.fill,
                'checked': mark.checked,
              },
      });
      if (kind != 'task') {
        dropped.add({'row': r, 'kind': kind, 'text': text});
        continue;
      }
      final textMembers = members
          .where((i) => !sortedMarks.any((cb) => _inside(lines[i].box, cb.box)))
          .toList();
      if (mark == null) {
        tasks.add(
          _uncertainTask(
            row: r,
            lines: lines,
            members: members,
            textMembers: textMembers,
            width: w,
          ),
        );
        continue;
      }
      final needs = <String>[
        'checkbox state needs review (gutter heuristic)',
        'indent/parent needs review',
      ];
      if (chosen.length > 1) {
        needs.add('multiple gutter marks match this row');
      }
      if (textMembers.isEmpty) {
        textMembers.addAll(members);
        needs.add('only checkbox glyphs were recognized; title needs review');
      }
      final titleMembers = textMembers
          .where((i) => lines[i].box[0] <= .5 * w)
          .toList();
      final due = textMembers
          .where((i) => lines[i].box[0] > .5 * w)
          .map((i) => lines[i].text)
          .join();
      if (titleMembers.isEmpty) needs.add('task row has no left-aligned text');
      if (textMembers.length > 2 || titleMembers.length > 1) {
        needs.add(
          'row contains ${textMembers.length} text blocks; split/merge needs review',
        );
      }
      if (textMembers.any((i) => lines[i].score < .8)) {
        needs.add('low OCR confidence; text needs review');
      }
      if (due.isNotEmpty) needs.add('date text needs review');
      final level = mark.box[0] < .07 * w ? 0 : 1;
      int? parent;
      if (level == 1) {
        for (final task in tasks.reversed) {
          if (task['level'] == 0) {
            parent = task['row'] as int;
            break;
          }
        }
        if (parent == null) needs.add('indented task without a visible parent');
      }
      int? anchor;
      for (final i in titleMembers) {
        if (anchor == null ||
            _usable(lines[i].text).length >
                _usable(lines[anchor].text).length) {
          anchor = i;
        }
      }
      tasks.add({
        'row': r,
        'line_indices': textMembers,
        'anchor_line': anchor,
        'title': titleMembers.map((i) => lines[i].text).join(),
        'checked': mark.checked,
        'checkbox_box': List<double>.of(mark.box),
        'checkbox_fill': mark.fill,
        'level': level,
        'parent': parent,
        'due': due.isEmpty ? null : due,
        'needs_confirmation': needs,
      });
    }
    final unusedStructural = [
      for (var i = 0; i < sortedMarks.length; i++)
        if (sortedMarks[i].sizedByWidthFraction && !used.contains(i)) i,
    ];
    if (unusedStructural.isNotEmpty) {
      notes.add(
        '${unusedStructural.length} gutter mark(s) matched no text row',
      );
    }
    if (noise.isNotEmpty) {
      notes.add('${noise.length} recognized block(s) had no usable text');
    }
    if (blankOutside > 0) {
      notes.add(
        '$blankOutside blank recognition box(es) were outside the image; no task was created',
      );
    }
    if (tasks.isEmpty) {
      notes.add('No task rows detected; review excluded candidates.');
    }
    return {
      'schema': 'wp17r2-draft/1',
      'id': id,
      'width': w,
      'height': h,
      'engine': engine,
      'rows': rows,
      'tasks': tasks,
      'dropped': dropped,
      'noise_lines': noise,
      'notes': notes,
    };
  }
}

final class _Row {
  _Row(this.indices, this.top, this.bottom);
  final List<int> indices;
  double top;
  double bottom;
}

double _center(List<double> b) => b[1] + b[3] / 2;
String _usable(String text) => text.replaceAll(
  RegExp(
    r'[\s\x00-\x1f\x7f-\x9f\u200b-\u200f\u202a-\u202e\u2060-\u206f\ufeff]',
  ),
  '',
);
bool _validBox(List<double> b, int w, int h) =>
    _finiteQuad(b) &&
    b[0] >= 0 &&
    b[1] >= 0 &&
    b[2] > 0 &&
    b[3] > 0 &&
    b[0] + b[2] <= w &&
    b[1] + b[3] <= h;

bool _finiteQuad(List<double> box) =>
    box.length == 4 && box.every((value) => value.isFinite);

/// Widest text block in the row. Its height is the character-height evidence
/// and its horizontal span shows whether a square is a leading control.
List<double>? _titleBox(List<OcrLine> lines, List<int> members) {
  List<double>? box;
  var width = -1.0;
  for (final i in members) {
    final candidate = lines[i].box;
    if (candidate.length == 4 && candidate[2] > width) {
      width = candidate[2];
      box = candidate;
    }
  }
  return box;
}

bool _leadingControl(GutterMark mark, List<double> line) {
  final side = math.max(mark.box[2], mark.box[3]);
  if (side <= 0 || line[3] <= 0) return false;
  final markRight = mark.box[0] + mark.box[2];
  // A glyph in the middle of a header is not a leading checkbox.
  if (mark.box[0] > line[0] + side) return false;
  return line[0] + line[2] >= markRight + side;
}

double _minSideRatio(GutterMark mark, List<double> line) {
  if (line[3] <= 0) return 0;
  return math.min(mark.box[2], mark.box[3]) / line[3];
}

bool _rescuedMatches(GutterMark mark, List<OcrLine> lines, List<int> members) {
  final line = _titleBox(lines, members);
  if (line == null || !_leadingControl(mark, line)) return false;
  final ratio = _minSideRatio(mark, line);
  // 29px on the recorded 57–66px long-line boxes is about 0.44–0.50.
  // Shorter header fragments such as a 15px stroke on a 50px title stay below.
  return ratio >= .38 && ratio <= 2;
}

bool _ambiguousRescue(GutterMark mark, List<OcrLine> lines, List<int> members) {
  final line = _titleBox(lines, members);
  if (line == null || !_leadingControl(mark, line)) return false;
  final side = math.max(mark.box[2], mark.box[3]);
  // Short headers stay sections. A long line is task-like text.
  if (line[2] < side * 8) return false;
  final ratio = _minSideRatio(mark, line);
  return ratio >= .25 && ratio < .38;
}

Map<String, dynamic> _uncertainTask({
  required int row,
  required List<OcrLine> lines,
  required List<int> members,
  required List<int> textMembers,
  required int width,
}) {
  final usableMembers = textMembers.isEmpty
      ? List<int>.of(members)
      : textMembers;
  final titleMembers = usableMembers
      .where((i) => lines[i].box[0] <= .5 * width)
      .toList();
  final due = usableMembers
      .where((i) => lines[i].box[0] > .5 * width)
      .map((i) => lines[i].text)
      .join();
  final needs = <String>[
    'task structure is uncertain; checkbox size does not match the text',
  ];
  if (textMembers.isEmpty) {
    needs.add('only checkbox glyphs were recognized; title needs review');
  }
  if (titleMembers.isEmpty) needs.add('task row has no left-aligned text');
  if (usableMembers.length > 2 || titleMembers.length > 1) {
    needs.add(
      'row contains ${usableMembers.length} text blocks; split/merge needs review',
    );
  }
  if (usableMembers.any((i) => lines[i].score < .8)) {
    needs.add('low OCR confidence; text needs review');
  }
  if (due.isNotEmpty) needs.add('date text needs review');
  int? anchor;
  for (final i in titleMembers) {
    if (anchor == null ||
        _usable(lines[i].text).length > _usable(lines[anchor].text).length) {
      anchor = i;
    }
  }
  return {
    'row': row,
    'line_indices': usableMembers,
    'anchor_line': anchor,
    'title': titleMembers.map((i) => lines[i].text).join(),
    'checked': false,
    'checkbox_box': null,
    'checkbox_fill': null,
    'level': 0,
    'parent': null,
    'due': due.isEmpty ? null : due,
    'needs_confirmation': needs,
  };
}

bool _inside(List<double> a, List<double> b) {
  final cx = a[0] + a[2] / 2;
  final cy = a[1] + a[3] / 2;
  if (cx >= b[0] && cx <= b[0] + b[2] && cy >= b[1] && cy <= b[1] + b[3]) {
    return true;
  }
  final intersection =
      math.max(0.0, math.min(a[0] + a[2], b[0] + b[2]) - math.max(a[0], b[0])) *
      math.max(0.0, math.min(a[1] + a[3], b[1] + b[3]) - math.max(a[1], b[1]));
  return intersection / (a[2] * a[3] + b[2] * b[3] - intersection) > .5;
}
