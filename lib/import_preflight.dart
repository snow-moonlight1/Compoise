import 'dart:convert';
import 'dart:typed_data';

import 'data_migrations.dart';
import 'models.dart';
import 'recovery_text.dart';

class ImportPlan {
  final String mode;

  /// When set, a merge routes every imported task into this existing board.
  /// The choice is retained when the plan is recalculated at commit time.
  final String? targetBoardId;
  final List<Board> boards;
  final List<Task> tasks;
  final AppSettings? settings;
  final AIConfig? aiConfig;
  final bool hasCredential;

  /// Original payload the plan was inspected from, kept so a commit can
  /// re-derive the plan against the live library. A preview is a snapshot of
  /// an older state; replaying it blindly would drop commands accepted after
  /// the preview. Every nested map and list is copied and made unmodifiable,
  /// so later edits to the source cannot change what the user confirmed.
  final Map<String, dynamic>? payload;
  final int addedBoards;
  final int addedTasks;
  final int skipped;
  final int conflicts;
  final int repaired;
  final int removedBoards;
  final int removedTasks;
  final List<String> warnings;
  final int baseRevision;

  const ImportPlan({
    required this.mode,
    this.targetBoardId,
    required this.boards,
    required this.tasks,
    this.settings,
    this.aiConfig,
    this.hasCredential = false,
    this.payload,
    required this.addedBoards,
    required this.addedTasks,
    required this.skipped,
    required this.conflicts,
    required this.repaired,
    required this.removedBoards,
    required this.removedTasks,
    required this.warnings,
    required this.baseRevision,
  });
}

/// Why a backup was rejected, so the file flow can name the limit instead of
/// showing a generic parse error. `copy` picks the localized message.
class BackupRejectedException implements FormatException {
  const BackupRejectedException(
    this.copy,
    this.message, {
    this.source,
    this.offset = 0,
  });

  final String copy;

  @override
  final String message;
  @override
  final dynamic source;
  @override
  final int offset;

  @override
  String toString() => 'FormatException: $message';
}

class ImportPreflight {
  /// UTF-8 bytes of task text one backup file is guaranteed to carry. A single
  /// record may use the whole budget, which is why the file ceiling below is
  /// larger than this: `maxBytes` alone was rejected as a file ceiling by
  /// RF-R04, because the JSON around 4 MiB of notes is already over 4 MiB.
  static const maxBytes = 4 * 1024 * 1024;

  /// Ceiling for one backup file, i.e. the bounded read. Derived, not chosen:
  /// `maxBytes` of text + the structural bytes a library at the record caps
  /// costs on its own (measured in `test/review/rf04_size_measurement.dart`:
  /// 10000 tasks x 146 B + 50000 subtasks x 39 B + 500 boards x 34 B
  /// = 3.27 MiB) + the 751 B envelope an empty export already has, rounded up
  /// to 8 MiB, which leaves ~0.7 MiB for key escaping. Measured cost at this
  /// size is ~100 ms to encode and ~150 ms to decode.
  static const maxFileBytes = 8 * 1024 * 1024;

  /// A library whose text exceeds `maxBytes` still has to be recoverable, so
  /// export splits it into at most this many files of `maxFileBytes` each —
  /// together about 64 MiB, roughly ten times the largest library the record
  /// caps allow (measured 6.52 MiB). Beyond that the library is outside the
  /// supported contract and export says so instead of claiming a backup it
  /// cannot restore.
  static const maxParts = 8;

  static const maxBoards = 500;
  static const maxTasks = 10000;
  static const maxSubtasks = 50000;
  static const maxDepth = 12;

  static dynamic _freezeJson(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.unmodifiable({
        for (final entry in value.entries)
          entry.key as String: _freezeJson(entry.value),
      });
    }
    if (value is List) {
      return List<dynamic>.unmodifiable(value.map(_freezeJson));
    }
    return value;
  }

  static Map<String, dynamic> decode(Uint8List bytes) {
    if (bytes.length > maxFileBytes) {
      throw const BackupRejectedException(
        'importErrorTooLarge',
        'Backup exceeds the supported size limit',
      );
    }
    final source = utf8.decode(bytes).replaceFirst(RegExp(r'^\uFEFF'), '');
    var depth = 0;
    var quoted = false;
    var escaped = false;
    for (final unit in source.codeUnits) {
      if (quoted) {
        if (escaped) {
          escaped = false;
        } else if (unit == 92) {
          escaped = true;
        } else if (unit == 34) {
          quoted = false;
        }
      } else if (unit == 34) {
        quoted = true;
      } else if (unit == 123 || unit == 91) {
        if (++depth > maxDepth) {
          throw const BackupRejectedException(
            'importErrorTooDeep',
            'Backup nesting limit exceeded',
          );
        }
      } else if (unit == 125 || unit == 93) {
        depth--;
      }
    }
    final value = jsonDecode(source);
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invalid backup root');
    }
    return value;
  }

  static ImportPlan inspect(
    Map<String, dynamic> payload,
    String mode, {
    String? targetBoardId,
    required List<Board> currentBoards,
    required List<Task> currentTasks,
    required int revision,
  }) {
    if (mode != 'merge' && mode != 'overwrite') {
      throw const FormatException('Invalid import mode');
    }
    if (targetBoardId != null && mode != 'merge') {
      throw const FormatException('Target board requires merge mode');
    }
    if (targetBoardId != null &&
        !currentBoards.any((board) => board.id == targetBoardId)) {
      throw const FormatException('Import target board is missing');
    }
    void checkDepth(Object? value, int depth) {
      if (depth > maxDepth) {
        throw const BackupRejectedException(
          'importErrorTooDeep',
          'Backup nesting limit exceeded',
        );
      }
      if (value is Map) {
        for (final item in value.values) {
          checkDepth(item, depth + 1);
        }
      } else if (value is List) {
        for (final item in value) {
          checkDepth(item, depth + 1);
        }
      }
    }

    checkDepth(payload, 1);
    // Direct-map callers pass through the same structural and size gate. This
    // is the gate `buildBackupBundle` runs its own output through, so a backup
    // the app wrote can always be read back here.
    if (utf8.encode(jsonEncode(payload)).length > maxFileBytes) {
      throw const BackupRejectedException(
        'importErrorTooLarge',
        'Backup exceeds the supported size limit',
      );
    }
    if (payload['boards'] is! List || payload['tasks'] is! List) {
      throw const FormatException('Missing boards or tasks');
    }
    final boardsRaw = payload['boards'] as List;
    final tasksRaw = payload['tasks'] as List;
    // `recovery: true` is this app's own archive of a library past the count
    // caps. Only that marker may pass the count checks. A hand-built file
    // without it still stops at the caps.
    final recovery = payload['recovery'] == true;
    if (!recovery &&
        (boardsRaw.length > maxBoards || tasksRaw.length > maxTasks)) {
      throw const BackupRejectedException(
        'importErrorTooManyRecords',
        'Backup record limit exceeded',
      );
    }
    var children = 0;
    var repairs = 0;
    final warnings = <String>[];
    final cleanBoards = <Map<String, dynamic>>[];
    final cleanTasks = <Map<String, dynamic>>[];
    final boardIds = <String, String>{};
    final taskIds = <String, String>{};
    var skipped = 0;

    T parseRecord<T>(T Function() parse, String scope) {
      try {
        return parse();
      } catch (_) {
        throw CorruptDataPayloadException('Invalid $scope record');
      }
    }

    void validateTime(Map<String, dynamic> record, String field) {
      if (!record.containsKey(field) || record[field] == null) return;
      final value = record[field];
      if (value is! num || !value.isFinite || value.abs() > 8640000000000000) {
        throw const FormatException('Invalid backup timestamp');
      }
    }

    void unknown(
      Map<String, dynamic> record,
      Set<String> allowed,
      String scope,
    ) {
      final names = record.keys
          .where((key) => !allowed.contains(key))
          .map(
            (key) => RegExp(r'^[A-Za-z_][A-Za-z0-9_]{0,48}$').hasMatch(key)
                ? key
                : '[invalid name]',
          )
          .toList();
      if (names.isNotEmpty) warnings.add('$scope: ${names.join(', ')}');
    }

    unknown(payload, {
      'version',
      'timestamp',
      'boards',
      'tasks',
      'settings',
      'aiConfig',
      'recovery',
      'recoveryChunks',
    }, 'Backup');
    if (payload['settings'] is Map<String, dynamic>) {
      final rawSettings = payload['settings'] as Map<String, dynamic>;
      unknown(rawSettings, {
        'language',
        'theme',
        'themeColor',
        'defaultInputMode',
        'viewMode',
        'fontSize',
        'fontFamily',
        'autoGroupAI',
        'autoDecomposeAI',
        'autoCompleteParent',
        'suppressGroupPrompt',
        'suppressLongTermPrompt',
        'hideCompleted',
        'showCompletionRate',
        'reduceMotion',
        'urgencyThresholdDays',
        'closeToTray',
        'globalShortcut',
      }, 'Settings');
      final normalized = parseRecord(
        () => AppSettings.fromJson(rawSettings),
        'settings',
      ).toJson();
      for (final key in rawSettings.keys) {
        if (normalized.containsKey(key) &&
            rawSettings[key] != normalized[key]) {
          repairs++;
          warnings.add('Settings $key normalized');
        }
      }
    }
    if (payload['aiConfig'] is Map<String, dynamic>) {
      unknown(payload['aiConfig'] as Map<String, dynamic>, {
        'provider',
        'providerId',
        'protocol',
        'customBaseUrl',
        'customApiKey',
        'customModel',
        'enableThinking',
      }, 'AI configuration');
    }

    var boardIndex = 0;
    for (final raw in boardsRaw) {
      boardIndex++;
      if (raw is! Map<String, dynamic>) {
        throw const FormatException('Invalid board record');
      }
      validateTime(raw, 'createdAt');
      unknown(raw, {'id', 'name', 'createdAt'}, 'Board $boardIndex');
      final board = parseRecord(() => Board.fromJson(raw), 'board');
      final canonical = jsonEncode(board.toJson());
      final previous = boardIds[board.id];
      if (previous != null) {
        if (previous != canonical) {
          throw const FormatException('Conflicting board ID');
        }
        skipped++;
        continue;
      }
      boardIds[board.id] = canonical;
      cleanBoards.add(raw);
    }
    var taskIndex = 0;
    for (final raw in tasksRaw) {
      taskIndex++;
      if (raw is! Map<String, dynamic>) {
        throw const FormatException('Invalid task record');
      }
      for (final field in [
        'createdAt',
        'deadline',
        'plannedDate',
        'reminderAt',
        'completedAt',
      ]) {
        validateTime(raw, field);
      }
      unknown(raw, {
        'id',
        'boardId',
        'title',
        'quadrant',
        'isLongTerm',
        'completed',
        'createdAt',
        'deadline',
        'plannedDate',
        'subtasks',
        'reasoning',
        'urgencyMode',
        'notesMarkdown',
        'reminderAt',
        'reminderTimezone',
        'completedAt',
        'tags',
        'recoveryPending',
      }, 'Task $taskIndex');
      final childRaw = raw['subtasks'];
      if (childRaw != null && childRaw is! List) {
        throw const FormatException('Invalid subtasks');
      }
      final seenChildren = <String, String>{};
      final uniqueChildren = <Map<String, dynamic>>[];
      var childIndex = 0;
      for (final child in (childRaw as List?) ?? const []) {
        childIndex++;
        children++;
        if (!recovery && children > maxSubtasks) {
          throw const BackupRejectedException(
            'importErrorTooManyRecords',
            'Subtask limit exceeded',
          );
        }
        if (child is! Map<String, dynamic>) {
          throw const FormatException('Invalid subtask record');
        }
        for (final field in ['deadline', 'reminderAt', 'completedAt']) {
          validateTime(child, field);
        }
        unknown(child, {
          'id',
          'title',
          'completed',
          'deadline',
          'notesMarkdown',
          'reminderAt',
          'completedAt',
          'recoveryPending',
        }, 'Task $taskIndex / subtask $childIndex');
        final parsed = parseRecord(() => SubTask.fromJson(child), 'subtask');
        final canonical = jsonEncode(parsed.toJson());
        final previous = seenChildren[parsed.id];
        if (previous != null) {
          if (previous != canonical) {
            throw const FormatException('Conflicting subtask ID');
          }
          skipped++;
          continue;
        }
        seenChildren[parsed.id] = canonical;
        uniqueChildren.add(child);
      }
      final normalized = {...raw, 'subtasks': uniqueChildren};
      final task = parseRecord(() => Task.fromJson(normalized), 'task');
      final rawQuadrant = raw['quadrant'];
      final acceptedQuadrant = rawQuadrant is num
          ? rawQuadrant == task.quadrant
          : rawQuadrant is String &&
                RegExp('^[Qq]?${task.quadrant}\$').hasMatch(rawQuadrant.trim());
      if (!acceptedQuadrant) {
        repairs++;
        warnings.add('Task $taskIndex quadrant normalized');
      }
      final canonical = jsonEncode(task.toJson());
      final previous = taskIds[task.id];
      if (previous != null) {
        if (previous != canonical) {
          throw const FormatException('Conflicting task ID');
        }
        skipped++;
        continue;
      }
      taskIds[task.id] = canonical;
      cleanTasks.add(normalized);
    }
    final migration = DataMigrator.migratePayload({
      ...payload,
      'boards': cleanBoards,
      'tasks': cleanTasks,
    });
    warnings.addAll(migration.warnings);
    if (cleanBoards.isEmpty && cleanTasks.isEmpty) warnings.add('Empty backup');
    final existingBoards = {for (final board in currentBoards) board.id: board};
    final existingTasks = {for (final task in currentTasks) task.id: task};
    final resultBoards = mode == 'merge'
        ? List<Board>.from(currentBoards)
        : List<Board>.from(migration.boards);
    final resultTasks = mode == 'merge'
        ? List<Task>.from(currentTasks)
        : List<Task>.from(migration.tasks);
    var addedBoards = 0;
    var addedTasks = 0;
    var conflicts = 0;
    if (mode == 'merge') {
      if (targetBoardId == null) {
        for (final board in migration.boards) {
          final old = existingBoards[board.id];
          if (old == null) {
            resultBoards.add(board);
            addedBoards++;
          } else if (jsonEncode(old.toJson()) == jsonEncode(board.toJson())) {
            skipped++;
          } else {
            conflicts++;
          }
        }
      }
      final validIds = resultBoards.map((board) => board.id).toSet();
      final sourceIds = migration.boards.map((board) => board.id).toSet();
      for (final task in migration.tasks) {
        if (targetBoardId != null && !sourceIds.contains(task.boardId)) {
          skipped++;
          warnings.add('Orphan task skipped');
          continue;
        }
        final imported = targetBoardId == null
            ? task
            : Task.fromJson({...task.toJson(), 'boardId': targetBoardId});
        if (!validIds.contains(imported.boardId)) {
          skipped++;
          warnings.add('Orphan task skipped');
          continue;
        }
        final old = existingTasks[imported.id];
        if (old == null) {
          resultTasks.add(imported);
          addedTasks++;
        } else if (jsonEncode(old.toJson()) == jsonEncode(imported.toJson())) {
          skipped++;
        } else {
          conflicts++;
        }
      }
    } else {
      if (resultBoards.isEmpty) {
        resultBoards.add(
          Board(
            id: newId(),
            name: 'Board',
            createdAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );
        repairs++;
        warnings.add('Default board created');
      }
      final validIds = resultBoards.map((board) => board.id).toSet();
      for (final task in resultTasks) {
        if (task.boardId.isEmpty) {
          task.boardId = resultBoards.first.id;
          repairs++;
          warnings.add('Empty board reference repaired');
        } else if (!validIds.contains(task.boardId)) {
          throw const FormatException('Orphan task in overwrite backup');
        }
      }
      addedBoards = resultBoards.length;
      addedTasks = resultTasks.length;
    }
    // The caps define an ordinary backup. A merge that is legal by itself
    // would otherwise walk an already large library past the ceiling.
    // A recovery archive is the lossless way out for a library that is
    // already past those counts: each file is still bounded by bytes and
    // depth, and the marker is what allows the pieces to add up.
    var resultChildren = 0;
    for (final task in resultTasks) {
      resultChildren += task.subtasks.length;
    }
    if (!recovery &&
        (resultBoards.length > maxBoards ||
            resultTasks.length > maxTasks ||
            resultChildren > maxSubtasks)) {
      throw const BackupRejectedException(
        'importErrorTooManyRecords',
        'Import would exceed the supported library limits',
      );
    }
    final chunkRaw = payload['recoveryChunks'];
    if (chunkRaw != null) {
      if (!recovery || chunkRaw is! List) {
        throw const FormatException('Invalid recovery chunks');
      }
      _applyRecoveryChunks(resultTasks, chunkRaw, targetBoardId: targetBoardId);
    }
    return ImportPlan(
      mode: mode,
      targetBoardId: targetBoardId,
      boards: resultBoards,
      tasks: resultTasks,
      settings: mode == 'overwrite' ? migration.settings : null,
      aiConfig: mode == 'overwrite' ? migration.aiConfig : null,
      hasCredential:
          mode == 'overwrite' &&
          payload['aiConfig'] is Map<String, dynamic> &&
          (payload['aiConfig'] as Map<String, dynamic>).containsKey(
            'customApiKey',
          ),
      payload: _freezeJson(payload) as Map<String, dynamic>,
      addedBoards: addedBoards,
      addedTasks: addedTasks,
      skipped: skipped,
      conflicts: conflicts,
      repaired: repairs,
      removedBoards: mode == 'overwrite' ? currentBoards.length : 0,
      removedTasks: mode == 'overwrite' ? currentTasks.length : 0,
      warnings: warnings,
      baseRevision: revision,
    );
  }

  /// Applies recovery pieces onto tasks already in the result. The live library
  /// is not mutated. Every chunk is checked against a copy first; a mismatch
  /// throws before any of those copies replace [resultTasks].
  ///
  /// A chunk with `offset` continues one field: the bytes before `offset` must
  /// hash to `prefixSha256`, and `archiveId` must match a restore already in
  /// progress. When the assembled field reaches the declared length, its
  /// SHA-256 has to equal `archiveId` before the cursor is cleared. The same
  /// slice a second time is a skip. A chunk without `offset` is the earlier
  /// continuation shape: appending a text that is already the suffix would
  /// duplicate it, so that import is a skip.
  ///
  /// [targetBoardId] is the board the user selected for this merge. A chunk
  /// may continue only a task that already belongs to that board. It cannot
  /// find the same id on another board.
  static void _applyRecoveryChunks(
    List<Task> resultTasks,
    List<dynamic> chunks, {
    String? targetBoardId,
  }) {
    final parsed = [for (final raw in chunks) _RecoveryChunk.parse(raw)];
    final byId = {for (final task in resultTasks) task.id: task};
    final working = <String, Task>{};
    Task copyOf(String id) {
      final existing = working[id];
      if (existing != null) return existing;
      final current = byId[id];
      if (current == null) {
        throw const BackupRejectedException(
          'exportErrorIncomplete',
          'Recovery chunk does not belong to a task in this restore',
        );
      }
      final copy = Task.fromJson(current.toJson());
      working[id] = copy;
      return copy;
    }

    final groups = <String, List<_RecoveryChunk>>{};
    for (final chunk in parsed) {
      final task = copyOf(chunk.taskId);
      if (targetBoardId != null && task.boardId != targetBoardId) {
        throw const BackupRejectedException(
          'importErrorRecoveryBoard',
          'Recovery chunk is outside the selected board',
        );
      }
      if (chunk.subtaskId != null &&
          !task.subtasks.any((sub) => sub.id == chunk.subtaskId)) {
        throw const FormatException('Recovery chunk has no subtask');
      }
      final key =
          '${chunk.taskId}\u0000${chunk.subtaskId ?? ''}\u0000${chunk.field}';
      groups.putIfAbsent(key, () => []).add(chunk);
    }
    for (final group in groups.values) {
      group.sort((a, b) {
        final position = (a.offset ?? a.index).compareTo(b.offset ?? b.index);
        if (position != 0) return position;
        return a.index.compareTo(b.index);
      });
      final sample = group.first;
      final task = working[sample.taskId]!;
      var text = _readRecoveryField(task, sample.subtaskId, sample.field);
      var cursor = _readRecoveryCursor(task, sample.subtaskId, sample.field);
      for (final chunk in group) {
        final applied = _applyRecoveryChunk(text, cursor, chunk);
        text = applied.text;
        cursor = applied.cursor;
      }
      _writeRecoveryField(task, sample.subtaskId, sample.field, text);
      _writeRecoveryCursor(task, sample.subtaskId, sample.field, cursor);
    }
    for (final entry in working.entries) {
      final slot = resultTasks.indexWhere((task) => task.id == entry.key);
      resultTasks[slot] = entry.value;
    }
  }
}

class _RecoveryCursor {
  const _RecoveryCursor(this.archiveId, this.length);

  final String archiveId;
  final int length;
}

class _AppliedChunk {
  const _AppliedChunk(this.text, this.cursor);

  final String text;
  final _RecoveryCursor? cursor;
}

class _RecoveryChunk {
  const _RecoveryChunk({
    required this.taskId,
    required this.subtaskId,
    required this.field,
    required this.index,
    required this.offset,
    required this.length,
    required this.archiveId,
    required this.prefixSha256,
    required this.text,
  });

  static const _taskFields = {'notesMarkdown', 'title', 'reasoning'};
  static const _subtaskFields = {'notesMarkdown', 'title'};

  final String taskId;
  final String? subtaskId;
  final String field;
  final int index;
  final int? offset;
  final int? length;
  final String? archiveId;
  final String? prefixSha256;
  final String text;

  static final _sha256Hex = RegExp(r'^[0-9a-f]{64}$');

  factory _RecoveryChunk.parse(dynamic raw) {
    if (raw is! Map) throw const FormatException('Invalid recovery chunk');
    final taskId = raw['taskId'];
    final text = raw['text'];
    final field = raw['field'];
    final index = raw['index'];
    final subtaskId = raw['subtaskId'];
    final offset = raw['offset'];
    final length = raw['length'];
    final archiveId = raw['archiveId'];
    final prefixSha256 = raw['prefixSha256'];
    final allowed = subtaskId == null ? _taskFields : _subtaskFields;
    if (taskId is! String ||
        taskId.isEmpty ||
        text is! String ||
        field is! String ||
        !allowed.contains(field) ||
        index is! int ||
        (subtaskId != null && (subtaskId is! String || subtaskId.isEmpty)) ||
        (offset != null && (offset is! int || offset < 0)) ||
        (length != null && (length is! int || length < 0)) ||
        (archiveId != null &&
            (archiveId is! String || !_sha256Hex.hasMatch(archiveId))) ||
        (prefixSha256 != null &&
            (prefixSha256 is! String || !_sha256Hex.hasMatch(prefixSha256)))) {
      throw const FormatException('Invalid recovery chunk');
    }
    final parsedOffset = offset as int?;
    final parsedLength = length as int?;
    if (parsedOffset != null &&
        parsedLength != null &&
        parsedOffset + text.length > parsedLength) {
      throw const FormatException('Invalid recovery chunk');
    }
    return _RecoveryChunk(
      taskId: taskId,
      subtaskId: subtaskId as String?,
      field: field,
      index: index,
      offset: parsedOffset,
      length: parsedLength,
      archiveId: archiveId as String?,
      prefixSha256: prefixSha256 as String?,
      text: text,
    );
  }
}

_AppliedChunk _applyRecoveryChunk(
  String text,
  _RecoveryCursor? cursor,
  _RecoveryChunk chunk,
) {
  if (chunk.offset == null) {
    if (chunk.text.isEmpty || text.endsWith(chunk.text)) {
      return _AppliedChunk(text, cursor);
    }
    return _AppliedChunk(text + chunk.text, cursor);
  }
  if (chunk.archiveId == null || chunk.length == null) {
    throw const BackupRejectedException(
      'importErrorRecoveryChunk',
      'Recovery chunk is missing its content check',
    );
  }
  final offset = chunk.offset!;
  if (text.length < offset) {
    throw const BackupRejectedException(
      'importErrorRecoveryChunk',
      'Recovery chunk is missing an earlier volume',
    );
  }
  if (chunk.archiveId != null &&
      cursor != null &&
      (cursor.archiveId != chunk.archiveId ||
          (chunk.length != null && cursor.length != chunk.length))) {
    throw const BackupRejectedException(
      'importErrorRecoveryChunk',
      'Recovery chunk belongs to a different archive',
    );
  }
  if (chunk.prefixSha256 != null) {
    final actual = recoverySha256Hex(utf8.encode(text.substring(0, offset)));
    if (actual != chunk.prefixSha256) {
      throw const BackupRejectedException(
        'importErrorRecoveryChunk',
        'Recovery chunk does not match the note being restored',
      );
    }
  }
  final end = offset + chunk.text.length;
  if (text.length >= end) {
    if (text.substring(offset, end) != chunk.text) {
      throw const BackupRejectedException(
        'importErrorRecoveryChunk',
        'Recovery chunk conflicts with the current note',
      );
    }
    return _AppliedChunk(text, _cursorAfter(text, cursor, chunk));
  }
  if (text.length != offset) {
    throw const BackupRejectedException(
      'importErrorRecoveryChunk',
      'Recovery chunk conflicts with the current note',
    );
  }
  final appended = text + chunk.text;
  return _AppliedChunk(appended, _cursorAfter(appended, cursor, chunk));
}

_RecoveryCursor? _cursorAfter(
  String text,
  _RecoveryCursor? cursor,
  _RecoveryChunk chunk,
) {
  final archiveId = chunk.archiveId;
  final length = chunk.length;
  if (archiveId == null || length == null) return cursor;
  if (text.length < length) return _RecoveryCursor(archiveId, length);
  if (recoverySha256Hex(utf8.encode(text)) != archiveId) {
    throw const BackupRejectedException(
      'importErrorRecoveryChunk',
      'Recovery chunk does not match the declared note',
    );
  }
  return null;
}

String _readRecoveryField(Task task, String? subtaskId, String field) {
  if (subtaskId == null) {
    switch (field) {
      case 'notesMarkdown':
        return task.notesMarkdown ?? '';
      case 'title':
        return task.title;
      case 'reasoning':
        return task.reasoning ?? '';
    }
  } else {
    final sub = task.subtasks.firstWhere((item) => item.id == subtaskId);
    switch (field) {
      case 'notesMarkdown':
        return sub.notesMarkdown ?? '';
      case 'title':
        return sub.title;
    }
  }
  throw const FormatException('Invalid recovery chunk');
}

void _writeRecoveryField(
  Task task,
  String? subtaskId,
  String field,
  String value,
) {
  if (subtaskId == null) {
    switch (field) {
      case 'notesMarkdown':
        task.notesMarkdown = value.isEmpty ? null : value;
        return;
      case 'title':
        task.title = value;
        return;
      case 'reasoning':
        task.reasoning = value.isEmpty ? null : value;
        return;
    }
  } else {
    final sub = task.subtasks.firstWhere((item) => item.id == subtaskId);
    switch (field) {
      case 'notesMarkdown':
        sub.notesMarkdown = value.isEmpty ? null : value;
        return;
      case 'title':
        sub.title = value;
        return;
    }
  }
  throw const FormatException('Invalid recovery chunk');
}

_RecoveryCursor? _readRecoveryCursor(
  Task task,
  String? subtaskId,
  String field,
) {
  final raw = subtaskId == null
      ? task.recoveryPending
      : task.subtasks
            .firstWhere((item) => item.id == subtaskId)
            .recoveryPending;
  final entry = raw?[field];
  if (entry == null) return null;
  if (entry is! Map) throw const FormatException('Invalid recovery cursor');
  final archiveId = entry['archiveId'];
  final length = entry['length'];
  if (archiveId is! String || length is! int) {
    throw const FormatException('Invalid recovery cursor');
  }
  return _RecoveryCursor(archiveId, length);
}

void _writeRecoveryCursor(
  Task task,
  String? subtaskId,
  String field,
  _RecoveryCursor? cursor,
) {
  Map<String, dynamic>? next(Map<String, dynamic>? current) {
    final copy = <String, dynamic>{...?current};
    if (cursor == null) {
      copy.remove(field);
    } else {
      copy[field] = {'archiveId': cursor.archiveId, 'length': cursor.length};
    }
    return copy.isEmpty ? null : copy;
  }

  if (subtaskId == null) {
    task.recoveryPending = next(task.recoveryPending);
    return;
  }
  final sub = task.subtasks.firstWhere((item) => item.id == subtaskId);
  sub.recoveryPending = next(sub.recoveryPending);
}
