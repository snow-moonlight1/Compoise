/// Editable, in-memory review state for the wp17r2-draft/1 adapter output.
///
/// Migration mapping: R2 images[].tasks[] become [DraftTask]s keyed by image
/// id and row. R2 `parent` (a row) becomes `parentId` within that image.
/// `due` stays unparsed text. `needs_confirmation` is retained as review
/// reasons. R2 `dropped` rows become excluded candidates that can be restored.
/// R2 `duplicates` become batch acknowledgements, never automatic deletion.
/// Editor-only fields (confirmed, excluded, destination, split/merge state)
/// are intentionally absent from the R2 wire format and never persisted here.
library;

import 'dart:convert';

class DraftFormatException implements Exception {
  final String message;
  const DraftFormatException(this.message);
  @override
  String toString() => 'DraftFormatException: $message';
}

Map<String, dynamic> _map(Object? value, String path) {
  if (value is! Map<String, dynamic>) {
    throw DraftFormatException('$path must be an object');
  }
  return value;
}

List<dynamic> _list(Object? value, String path) {
  if (value is! List) throw DraftFormatException('$path must be a list');
  return value;
}

String _string(Object? value, String path) {
  if (value is! String) throw DraftFormatException('$path must be a string');
  return value;
}

int _int(Object? value, String path) {
  if (value is! int) throw DraftFormatException('$path must be an integer');
  return value;
}

class DraftTask {
  final String id;
  final String imageId;
  final int? sourceRow;
  String title;
  bool checked;
  String? parentId;
  String? dueText;
  bool keepDueText;
  final List<String> reviewReasons;
  bool confirmed = false;
  bool excluded;

  DraftTask({
    required this.id,
    required this.imageId,
    required this.sourceRow,
    required this.title,
    required this.checked,
    this.parentId,
    this.dueText,
    this.keepDueText = false,
    List<String> reviewReasons = const [],
    this.excluded = false,
  }) : reviewReasons = List.of(reviewReasons);

  bool get hasValidTitle => title.trim().isNotEmpty;
}

class DraftImage {
  final String id;
  final int? width;
  final int? height;
  final String? engine;
  final String? error;
  bool skipped = false;
  final List<DraftTask> tasks;
  final List<String> notes;

  DraftImage({
    required this.id,
    this.width,
    this.height,
    this.engine,
    this.error,
    required this.tasks,
    this.notes = const [],
  });

  bool get failed => error != null;
}

class DuplicateHint {
  final List<String> imageIds;
  final String reason;
  bool acknowledged = false;
  DuplicateHint(this.imageIds, this.reason);
}

class ImportTask {
  final String id;
  final String imageId;
  final String title;
  final bool checked;
  final String? parentId;

  /// Unparsed OCR text. I3 may copy this as text; never infer a deadline here.
  final String? dueText;
  const ImportTask({
    required this.id,
    required this.imageId,
    required this.title,
    required this.checked,
    this.parentId,
    this.dueText,
  });
}

class ImportSubmission {
  final String boardId;
  final int quadrant;
  final List<ImportTask> tasks;
  final int skippedCount;
  const ImportSubmission({
    required this.boardId,
    required this.quadrant,
    required this.tasks,
    required this.skippedCount,
  });
}

class DraftBatch {
  final List<DraftImage> images;
  final List<DuplicateHint> duplicates;
  String? boardId;
  int? quadrant;
  int _nextId = 0;

  DraftBatch({required this.images, this.duplicates = const []});

  factory DraftBatch.fromJsonString(String input) {
    Object? decoded;
    try {
      decoded = jsonDecode(input);
    } on FormatException catch (e) {
      throw DraftFormatException('invalid JSON: ${e.message}');
    }
    return DraftBatch.fromJson(_map(decoded, 'root'));
  }

  /// Accepts a single R2 image or a batch envelope with `images`/`duplicates`.
  /// A failed image is an I3 extension: `{id, error}` in `images`.
  factory DraftBatch.fromJson(Map<String, dynamic> json) {
    if (json['schema'] != 'wp17r2-draft/1') {
      throw const DraftFormatException('unsupported draft schema');
    }
    final imageMaps = json.containsKey('images')
        ? _list(json['images'], 'images')
        : <dynamic>[json];
    if (imageMaps.isEmpty) throw const DraftFormatException('images is empty');
    final images = <DraftImage>[];
    final seenIds = <String>{};
    for (var i = 0; i < imageMaps.length; i++) {
      final source = _map(imageMaps[i], 'images[$i]');
      final id = _string(source['id'], 'images[$i].id');
      if (id.trim().isEmpty || !seenIds.add(id)) {
        throw DraftFormatException('duplicate or empty image id: $id');
      }
      final error = source['error'];
      if (error != null) {
        images.add(
          DraftImage(id: id, error: _string(error, 'error'), tasks: []),
        );
        continue;
      }
      if (source['schema'] != null && source['schema'] != 'wp17r2-draft/1') {
        throw DraftFormatException('unsupported image schema: $id');
      }
      final width = _int(source['width'], '$id.width');
      final height = _int(source['height'], '$id.height');
      if (width <= 0 || height <= 0) {
        throw DraftFormatException('$id has invalid dimensions');
      }
      final rows = <int, DraftTask>{};
      final tasks = <DraftTask>[];
      for (final (index, raw) in _list(source['tasks'], '$id.tasks').indexed) {
        final item = _map(raw, '$id.tasks[$index]');
        final row = _int(item['row'], '$id.tasks[$index].row');
        if (row < 0 || rows.containsKey(row)) {
          throw DraftFormatException('$id has duplicate/invalid task row $row');
        }
        final checked = item['checked'];
        if (checked is! bool) {
          throw DraftFormatException('$id task $row checked must be boolean');
        }
        final level = _int(item['level'], '$id task $row level');
        if (level < 0 || level > 1) {
          throw DraftFormatException('$id task $row level is invalid');
        }
        final due = item['due'];
        final reasons = _list(
          item['needs_confirmation'],
          '$id task $row needs_confirmation',
        ).map((value) => _string(value, 'confirmation reason')).toList();
        if (due != null &&
            _string(due, '$id task $row due').trim().isNotEmpty) {
          reasons.add('date text needs review');
        }
        if (level == 1 || item['parent'] != null) {
          reasons.add('indent/parent needs review');
        }
        final task = DraftTask(
          id: '$id:$row',
          imageId: id,
          sourceRow: row,
          title: _string(item['title'], '$id task $row title'),
          checked: checked,
          dueText: due == null ? null : due as String,
          reviewReasons: reasons,
        );
        rows[row] = task;
        tasks.add(task);
      }
      for (final (index, raw) in _list(source['tasks'], '$id.tasks').indexed) {
        final item = _map(raw, '$id.tasks[$index]');
        final parent = item['parent'];
        if (parent == null) continue;
        final row = _int(parent, '$id parent');
        final candidate = rows[row];
        final task = tasks[index];
        if (candidate == null ||
            candidate == task ||
            tasks.indexOf(candidate) >= index) {
          task.reviewReasons.add('parent row is missing or out of order');
        } else {
          task.parentId = candidate.id;
        }
      }
      final dropped = _list(source['dropped'], '$id.dropped');
      for (final (index, raw) in dropped.indexed) {
        final item = _map(raw, '$id.dropped[$index]');
        final row = _int(item['row'], '$id dropped row');
        final text = _string(item['text'], '$id dropped text');
        tasks.add(
          DraftTask(
            id: '$id:dropped:$row:$index',
            imageId: id,
            sourceRow: row,
            title: text,
            checked: false,
            excluded: true,
            reviewReasons: [
              'dropped ${_string(item['kind'], '$id dropped kind')}',
            ],
          ),
        );
      }
      tasks.sort((a, b) => (a.sourceRow ?? 0).compareTo(b.sourceRow ?? 0));
      images.add(
        DraftImage(
          id: id,
          width: width,
          height: height,
          engine: _string(source['engine'], '$id.engine'),
          tasks: tasks,
          notes: source['notes'] == null
              ? []
              : _list(
                  source['notes'],
                  '$id.notes',
                ).map((value) => _string(value, '$id note')).toList(),
        ),
      );
    }
    final duplicates = <DuplicateHint>[];
    for (final raw
        in json['duplicates'] == null
            ? <dynamic>[]
            : _list(json['duplicates'], 'duplicates')) {
      final item = _map(raw, 'duplicate');
      final ids = _list(
        item['images'],
        'duplicate.images',
      ).map((value) => _string(value, 'duplicate image id')).toList();
      if (ids.length != 2 ||
          ids[0] == ids[1] ||
          ids.any((id) => !seenIds.contains(id)) ||
          item['hint_only'] != true) {
        throw const DraftFormatException('invalid duplicate hint');
      }
      duplicates.add(
        DuplicateHint(ids, _string(item['reason'], 'duplicate.reason')),
      );
    }
    return DraftBatch(images: images, duplicates: duplicates);
  }

  List<DraftTask> get activeTasks => [
    for (final image in images)
      if (!image.skipped && !image.failed)
        for (final task in image.tasks)
          if (!task.excluded) task,
  ];

  bool get canSubmit =>
      boardId != null &&
      boardId!.isNotEmpty &&
      quadrant != null &&
      quadrant! >= 1 &&
      quadrant! <= 4 &&
      activeTasks.isNotEmpty &&
      activeTasks.every(
        (task) =>
            task.confirmed &&
            task.hasValidTitle &&
            (task.parentId == null ||
                activeTasks.any(
                  (parent) =>
                      parent.id == task.parentId &&
                      parent.imageId == task.imageId,
                )),
      ) &&
      duplicates.every(
        (hint) =>
            hint.acknowledged ||
            hint.imageIds.any(
              (id) => images.firstWhere((image) => image.id == id).skipped,
            ),
      );

  void moveImage(int oldIndex, int newIndex) {
    if (oldIndex < 0 ||
        oldIndex >= images.length ||
        newIndex < 0 ||
        newIndex >= images.length) {
      return;
    }
    images.insert(newIndex, images.removeAt(oldIndex));
  }

  void setParent(DraftTask task, String? parentId) {
    if (parentId != null) {
      final image = images.firstWhere((image) => image.id == task.imageId);
      final index = image.tasks.indexOf(task);
      if (index < 0 ||
          !image.tasks
              .take(index)
              .any(
                (candidate) => candidate.id == parentId && !candidate.excluded,
              )) {
        throw const DraftFormatException(
          'parent must be an earlier active task in the same image',
        );
      }
    }
    task.parentId = parentId;
    task.confirmed = false;
  }

  void setExcluded(DraftTask task, bool excluded) {
    task.excluded = excluded;
    task.confirmed = false;
    if (excluded) {
      for (final image in images) {
        for (final child in image.tasks.where(
          (item) => item.parentId == task.id,
        )) {
          child.parentId = null;
          child.confirmed = false;
          child.reviewReasons.add('parent was excluded');
        }
      }
    }
  }

  /// Splits on the first nonempty newline; both pieces require renewed review.
  DraftTask? splitAtNewline(DraftTask task) {
    final parts = task.title.split('\n');
    if (parts.length < 2 ||
        parts.first.trim().isEmpty ||
        parts.skip(1).join(' ').trim().isEmpty) {
      return null;
    }
    final image = images.firstWhere((image) => image.id == task.imageId);
    task.title = parts.first.trim();
    task.confirmed = false;
    final child = DraftTask(
      id: '${task.imageId}:edit:${_nextId++}',
      imageId: task.imageId,
      sourceRow: task.sourceRow,
      title: parts.skip(1).join(' ').trim(),
      checked: task.checked,
      parentId: task.parentId,
      reviewReasons: ['split task needs review'],
    );
    image.tasks.insert(image.tasks.indexOf(task) + 1, child);
    return child;
  }

  /// Merges into the immediately preceding active task of the same image.
  bool mergeWithPrevious(DraftTask task) {
    final image = images.firstWhere((image) => image.id == task.imageId);
    final index = image.tasks.indexOf(task);
    if (index <= 0) return false;
    final previous = image.tasks
        .take(index)
        .toList()
        .reversed
        .where((item) => !item.excluded)
        .firstOrNull;
    if (previous == null) return false;
    previous.title = '${previous.title.trim()} ${task.title.trim()}'.trim();
    previous.confirmed = false;
    previous.reviewReasons.add('merged task needs review');
    for (final child in image.tasks.where((item) => item.parentId == task.id)) {
      child.parentId = previous.id;
      child.confirmed = false;
    }
    image.tasks.remove(task);
    return true;
  }

  ImportSubmission snapshot() {
    if (!canSubmit) {
      throw const DraftFormatException('batch is not ready to submit');
    }
    return ImportSubmission(
      boardId: boardId!,
      quadrant: quadrant!,
      tasks: [
        for (final task in activeTasks)
          ImportTask(
            id: task.id,
            imageId: task.imageId,
            title: task.title.trim(),
            checked: task.checked,
            parentId: task.parentId,
            dueText: task.keepDueText ? task.dueText?.trim() : null,
          ),
      ],
      skippedCount: images.fold(
        0,
        (count, image) =>
            count +
            (image.skipped
                ? image.tasks.length
                : image.tasks.where((task) => task.excluded).length),
      ),
    );
  }
}
