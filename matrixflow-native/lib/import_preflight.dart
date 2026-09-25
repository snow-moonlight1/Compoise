import 'dart:convert';
import 'dart:typed_data';

import 'data_migrations.dart';
import 'models.dart';

class ImportPlan {
  final String mode;
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
    required List<Board> currentBoards,
    required List<Task> currentTasks,
    required int revision,
  }) {
    if (mode != 'merge' && mode != 'overwrite') {
      throw const FormatException('Invalid import mode');
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
    if (boardsRaw.length > maxBoards || tasksRaw.length > maxTasks) {
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
      final names =
          record.keys
              .where((key) => !allowed.contains(key))
              .map(
                (key) =>
                    RegExp(r'^[A-Za-z_][A-Za-z0-9_]{0,48}$').hasMatch(key)
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
      final normalized =
          parseRecord(
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
        'subtasks',
        'reasoning',
        'urgencyMode',
        'notesMarkdown',
        'reminderAt',
        'reminderTimezone',
        'completedAt',
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
        if (++children > maxSubtasks) {
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
      final acceptedQuadrant =
          rawQuadrant is num
              ? rawQuadrant == task.quadrant
              : rawQuadrant is String &&
                  RegExp(
                    '^[Qq]?${task.quadrant}\$',
                  ).hasMatch(rawQuadrant.trim());
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
    final resultBoards =
        mode == 'merge'
            ? List<Board>.from(currentBoards)
            : List<Board>.from(migration.boards);
    final resultTasks =
        mode == 'merge'
            ? List<Task>.from(currentTasks)
            : List<Task>.from(migration.tasks);
    var addedBoards = 0;
    var addedTasks = 0;
    var conflicts = 0;
    if (mode == 'merge') {
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
      final validIds = resultBoards.map((board) => board.id).toSet();
      for (final task in migration.tasks) {
        if (!validIds.contains(task.boardId)) {
          skipped++;
          warnings.add('Orphan task skipped');
          continue;
        }
        final old = existingTasks[task.id];
        if (old == null) {
          resultTasks.add(task);
          addedTasks++;
        } else if (jsonEncode(old.toJson()) == jsonEncode(task.toJson())) {
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
    // The caps define the library this app supports, not just one file. A
    // merge that is legal by itself would otherwise walk an already large
    // library past the ceiling, leaving a library no backup can carry.
    var resultChildren = 0;
    for (final task in resultTasks) {
      resultChildren += task.subtasks.length;
    }
    if (resultBoards.length > maxBoards ||
        resultTasks.length > maxTasks ||
        resultChildren > maxSubtasks) {
      throw const BackupRejectedException(
        'importErrorTooManyRecords',
        'Import would exceed the supported library limits',
      );
    }
    return ImportPlan(
      mode: mode,
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
}
