import 'dart:convert';

import 'import_preflight.dart';
import 'models.dart';
import 'recovery_text.dart';
import 'schedule_item.dart';

/// One file the user is asked to save. A library that fits a single file
/// produces one part with [index] and [total] both 1.
class BackupPart {
  const BackupPart({
    required this.index,
    required this.total,
    required this.json,
  });

  /// 1-based position in the restore order.
  final int index;
  final int total;
  final String json;

  int get bytes => utf8.encode(json).length;
}

/// Result of building the backup for a library. [single], [split] and
/// [recovery] are files a restore of this app accepts in order. Anything else
/// means no file was produced, so export does not claim a backup success.
///
/// [libraryTooLarge] means a part still cannot be imported. A library that
/// needs more than [ImportPreflight.maxParts] files is not this status: each
/// file stays inside the byte ceiling and the set is restored in order.
/// [incomplete] means a file would drop records or configuration on restore, so it is not a
/// complete backup.
enum BackupStatus {
  single,
  split,
  recovery,
  oversizedRecord,
  libraryTooLarge,
  incomplete,
}

class BackupBundle {
  const BackupBundle({required this.status, required this.parts});

  final BackupStatus status;

  /// Empty unless [recoverable].
  final List<BackupPart> parts;

  bool get recoverable =>
      status == BackupStatus.single ||
      status == BackupStatus.split ||
      status == BackupStatus.recovery;
}

/// Builds backup files from a document [Store.exportJson] already produced and
/// keeps the export/import contract symmetric: every returned file is checked
/// against the same [ImportPreflight] gates a restore runs, so a bundle reported
/// as recoverable can be restored into a fresh, empty library — every volume of
/// it, in order.
///
/// Checking one file at a time is not enough on its own. Ordinary files still
/// refuse a result library past the count caps, which is why two hand-made
/// volumes can each look legal and the second one still be refused. A library
/// this app already holds past those caps is exported as a recovery archive:
/// the same split, with `recovery: true` on every part, which is the only
/// marker the import gate lets add up past the caps. A part that would skip a
/// record is not a complete backup and is not returned.
///
/// A library whose single file passes every ordinary gate is exported
/// unchanged, byte for byte. A larger one is split along board boundaries so
/// every ordinary part carries its own dependencies; a single board too large for
/// one part is split further and each of those parts repeats that board's
/// record, which an import counts as an identical skip rather than a conflict.
/// Only the first part carries `settings` and `aiConfig`.
BackupBundle buildBackupBundle(String document) {
  try {
    return _buildBackupBundle(document);
  } on _OversizedRecord {
    return const BackupBundle(status: BackupStatus.oversizedRecord, parts: []);
  } catch (_) {
    // Export accepts a String, including damaged recovery copies. Parsing and
    // validation failures must not escape into the file-save flow.
    return const BackupBundle(status: BackupStatus.incomplete, parts: []);
  }
}

BackupBundle _buildBackupBundle(String document) {
  final raw = jsonDecode(document.replaceFirst(RegExp(r'^\uFEFF'), ''));
  if (raw is! Map<String, dynamic>) {
    return const BackupBundle(status: BackupStatus.incomplete, parts: []);
  }
  final decoded = raw;
  final original = _sourceLibrary(decoded);
  final whole = _gateRejection(document);
  if (whole == null) {
    if (!_sameLibrary(original, _restoreInOrder([document]))) {
      return const BackupBundle(status: BackupStatus.incomplete, parts: []);
    }
    return BackupBundle(
      status: BackupStatus.single,
      parts: [BackupPart(index: 1, total: 1, json: document)],
    );
  }
  if (whole != 'importErrorTooLarge' && whole != 'importErrorTooManyRecords') {
    return const BackupBundle(status: BackupStatus.incomplete, parts: []);
  }
  final overCount = _libraryCounts(decoded).overSupportedCaps;
  if (overCount) {
    final flagged = jsonEncode({...decoded, 'recovery': true});
    if (utf8.encode(flagged).length <= ImportPreflight.maxFileBytes &&
        _gateRejection(flagged) == null &&
        _sameLibrary(original, _restoreInOrder([flagged]))) {
      return BackupBundle(
        status: BackupStatus.recovery,
        parts: [BackupPart(index: 1, total: 1, json: flagged)],
      );
    }
  }
  final noteChunks = <Map<String, dynamic>>[];
  final schedulesByTask = <String, List<Map<String, dynamic>>>{};
  final eventsByBoard = <String, List<Map<String, dynamic>>>{};
  for (final item in original.scheduleItems) {
    final owner = item.taskId ?? item.boardId!;
    final byOwner = item.taskId == null ? eventsByBoard : schedulesByTask;
    byOwner.putIfAbsent(owner, () => []).add(item.toJson());
  }
  final boardsById = <String, Map<String, dynamic>>{
    for (final board in decoded['boards'] as List<dynamic>)
      (board as Map<String, dynamic>)['id'] as String: board,
  };
  final strippedTasks = <Map<String, dynamic>>[];
  for (final raw in decoded['tasks'] as List<dynamic>) {
    final task = Map<String, dynamic>.from(raw as Map);
    // Linked records cannot move to a later volume. Reserve their bytes before
    // deciding how much task text must become a recovery continuation.
    _fitRecord(
      task,
      noteChunks,
      dependencyBytes:
          _encodedBytes(boardsById[task['boardId']]) +
          _recordBytes(schedulesByTask[task['id']] ?? const []),
    );
    strippedTasks.add(task);
  }
  final recovery =
      decoded['recovery'] == true || overCount || noteChunks.isNotEmpty;
  final groups = _groupByBoard(
    decoded['boards'] as List<dynamic>,
    strippedTasks,
    schedulesByTask,
    eventsByBoard,
  );
  final drafts = _pack(groups, decoded);
  if (drafts == null) {
    return const BackupBundle(status: BackupStatus.oversizedRecord, parts: []);
  }
  final boardOfTask = <String, String>{
    for (final task in strippedTasks)
      if (task['id'] is String && task['boardId'] is String)
        task['id'] as String: task['boardId'] as String,
  };
  for (final chunk in noteChunks) {
    _placeChunk(
      drafts,
      chunk,
      boardsById[boardOfTask[chunk['taskId']]],
      decoded,
    );
  }
  final bodies = <String>[];
  for (var index = 0; index < drafts.length; index++) {
    final json = jsonEncode(drafts[index].toJson(recovery: recovery));
    if (utf8.encode(json).length > ImportPreflight.maxFileBytes) {
      return const BackupBundle(
        status: BackupStatus.oversizedRecord,
        parts: [],
      );
    }
    bodies.add(json);
  }
  final restored = _restoreInOrder(bodies);
  if (!_sameLibrary(original, restored)) {
    return const BackupBundle(status: BackupStatus.incomplete, parts: []);
  }
  final parts = [
    for (var index = 0; index < bodies.length; index++)
      BackupPart(index: index + 1, total: bodies.length, json: bodies[index]),
  ];
  return BackupBundle(
    status: recovery
        ? BackupStatus.recovery
        : parts.length == 1
        ? BackupStatus.single
        : BackupStatus.split,
    parts: parts,
  );
}

class _Draft {
  _Draft(Map<String, dynamic> source, {required bool first})
    : envelope = {
        'version': source['version'] ?? ExportData.legacyVersion,
        if (source.containsKey('timestamp')) 'timestamp': source['timestamp'],
        if (first && source['settings'] != null) 'settings': source['settings'],
        if (first && source['aiConfig'] != null) 'aiConfig': source['aiConfig'],
      };

  final Map<String, dynamic> envelope;
  final List<Map<String, dynamic>> boards = [];
  final List<Map<String, dynamic>> tasks = [];
  final List<Map<String, dynamic>> scheduleItems = [];
  final List<Map<String, dynamic>> chunks = [];
  final Set<String> boardIds = {};
  int contentBytes = 0;

  bool get isEmpty => boards.isEmpty && tasks.isEmpty && chunks.isEmpty;

  // Summed record sizes include one comma per record, a conservative bound.
  // Keeping the envelope exact avoids re-encoding a growing 4 MiB draft for
  // every one of 10,000 small records.
  late final int envelopeBytes = _encodedBytes({
    ...envelope,
    'boards': const [],
    'tasks': const [],
    if (envelope['version'] == 3) 'scheduleItems': const [],
    'recovery': true,
  });

  int get bytes =>
      envelopeBytes +
      contentBytes +
      (chunks.isEmpty ? 0 : ',"recoveryChunks":[]'.length);

  void addBoard(Map<String, dynamic> board) {
    if (!boardIds.add(board['id'] as String)) return;
    boards.add(board);
    contentBytes += _encodedBytes(board) + 1;
  }

  void addTask(_TaskRecord task) {
    tasks.add(task.json);
    scheduleItems.addAll(task.scheduleItems);
    contentBytes += task.bytes;
  }

  void addEvents(List<Map<String, dynamic>> events) {
    scheduleItems.addAll(events);
    contentBytes += _recordBytes(events);
  }

  void addChunk(Map<String, dynamic> chunk) {
    chunks.add(chunk);
    contentBytes += _encodedBytes(chunk) + 1;
  }

  void removeChunk() {
    contentBytes -= _encodedBytes(chunks.removeLast()) + 1;
  }

  Map<String, dynamic> toJson({required bool recovery}) => {
    ...envelope,
    'boards': boards,
    'tasks': tasks,
    if (envelope['version'] == 3) 'scheduleItems': scheduleItems,
    if (recovery) 'recovery': true,
    if (chunks.isNotEmpty) 'recoveryChunks': chunks,
  };
}

/// Room left in a file for the envelope, settings and AI configuration around
/// one task record. The decision uses the encoded record, not a single field's
/// raw UTF-8 length.
const _recordSlack = 65536;

/// Fields smaller than this are structure, not a splittable value. Peeling
/// them would not bring an oversized record under the file ceiling.
const _minSplitBytes = 1024;

/// Pulls writable strings out of [task] until the encoded record fits in one
/// file, or until no large string remains. Parent and child text are measured
/// together, and the measure is the JSON-escaped size.
void _fitRecord(
  Map<String, dynamic> task,
  List<Map<String, dynamic>> chunks, {
  required int dependencyBytes,
}) {
  final id = task['id'];
  if (id is! String) return;
  final subs = task['subtasks'];
  if (subs is List) {
    task['subtasks'] = [
      for (final raw in subs)
        if (raw is Map) Map<String, dynamic>.from(raw) else raw,
    ];
  }
  while (_encodedBytes(task) + dependencyBytes + _recordSlack >
      ImportPreflight.maxFileBytes) {
    final before = _encodedBytes(task);
    if (!_peelLargest(task, id, chunks)) return;
    if (_encodedBytes(task) >= before) return;
  }
}

class _SplitTarget {
  const _SplitTarget(this.holder, this.field, this.subtaskId, this.text);

  final Map<String, dynamic> holder;
  final String field;
  final String? subtaskId;
  final String text;
}

bool _peelLargest(
  Map<String, dynamic> task,
  String taskId,
  List<Map<String, dynamic>> chunks,
) {
  _SplitTarget? best;
  var bestSize = 0;
  void consider(Map<String, dynamic> owner, String field, String? childId) {
    final value = owner[field];
    if (value is! String || value.isEmpty) return;
    final size = jsonStringUtf8Length(value);
    if (size < _minSplitBytes || size <= bestSize) return;
    best = _SplitTarget(owner, field, childId, value);
    bestSize = size;
  }

  consider(task, 'notesMarkdown', null);
  consider(task, 'title', null);
  consider(task, 'reasoning', null);
  final subs = task['subtasks'];
  if (subs is List) {
    for (final raw in subs) {
      if (raw is! Map<String, dynamic>) continue;
      final childId = raw['id'];
      if (childId is! String) continue;
      consider(raw, 'notesMarkdown', childId);
      consider(raw, 'title', childId);
    }
  }
  final chosen = best;
  if (chosen == null) return false;
  chosen.holder.remove(chosen.field);
  _appendFieldChunks(
    chunks: chunks,
    taskId: taskId,
    subtaskId: chosen.subtaskId,
    field: chosen.field,
    text: chosen.text,
  );
  return true;
}

void _appendFieldChunks({
  required List<Map<String, dynamic>> chunks,
  required String taskId,
  required String? subtaskId,
  required String field,
  required String text,
}) {
  final archiveId = recoverySha256Hex(utf8.encode(text));
  final parts = sliceJsonText(text, ImportPreflight.maxBytes);
  var offset = 0;
  for (var index = 0; index < parts.length; index++) {
    final part = parts[index];
    chunks.add({
      'taskId': taskId,
      if (subtaskId != null) 'subtaskId': subtaskId,
      'field': field,
      'index': index,
      'offset': offset,
      'length': text.length,
      'archiveId': archiveId,
      'prefixSha256': recoverySha256Hex(utf8.encode(text.substring(0, offset))),
      'text': part,
    });
    offset += part.length;
  }
}

void _placeChunk(
  List<_Draft> drafts,
  Map<String, dynamic> chunk,
  Map<String, dynamic>? board,
  Map<String, dynamic> source,
) {
  for (final draft in drafts.reversed) {
    final carriesTask = draft.tasks.any(
      (task) => task['id'] == chunk['taskId'],
    );
    final carriesChunk = draft.chunks.any(
      (piece) => piece['taskId'] == chunk['taskId'],
    );
    if (!carriesTask && !carriesChunk) continue;
    draft.addChunk(chunk);
    if (draft.bytes <= ImportPreflight.maxFileBytes) return;
    draft.removeChunk();
    // A later piece must not fall back into an earlier volume. Import applies
    // files in order and rejects an offset that arrives before its prefix.
    break;
  }
  final extra = _Draft(source, first: false);
  if (board != null) extra.addBoard(board);
  extra.addChunk(chunk);
  drafts.add(extra);
}

class _Library {
  const _Library({
    required this.boards,
    required this.tasks,
    required this.scheduleItems,
    this.settings,
    this.aiConfig,
  });

  final List<Board> boards;
  final List<Task> tasks;
  final List<ScheduleItem> scheduleItems;
  final AppSettings? settings;
  final AIConfig? aiConfig;
}

class _OversizedRecord implements Exception {}

/// Parse the source even when the bounded-read gate cannot inspect it. This
/// prevents a duplicate or damaged record being hidden by packing/deduplication.
_Library _sourceLibrary(Map<String, dynamic> decoded) {
  final version = decoded['version'] ?? ExportData.legacyVersion;
  if (version is! num ||
      !version.isFinite ||
      version.toInt() != version ||
      !ExportData.supportedVersions.contains(version.toInt()) ||
      decoded['boards'] is! List ||
      decoded['tasks'] is! List ||
      (version != 3 && decoded.containsKey('scheduleItems')) ||
      (version == 3 && decoded['scheduleItems'] is! List)) {
    throw const FormatException('Invalid backup envelope');
  }
  final boards = [
    for (final raw in decoded['boards'] as List)
      Board.fromJson(Map<String, dynamic>.from(raw as Map)),
  ];
  final tasks = [
    for (final raw in decoded['tasks'] as List)
      Task.fromJson(Map<String, dynamic>.from(raw as Map)),
  ];
  final schedules = <ScheduleItem>[
    if (version == 3)
      for (final raw in decoded['scheduleItems'] as List)
        ScheduleItem.fromJson(Map<String, dynamic>.from(raw as Map)),
  ];
  void unique(Iterable<String> ids) {
    final seen = <String>{};
    for (final id in ids) {
      if (!seen.add(id)) throw const FormatException('Duplicate backup id');
    }
  }

  unique(boards.map((board) => board.id));
  unique(tasks.map((task) => task.id));
  final boardIds = boards.map((board) => board.id).toSet();
  for (final task in tasks) {
    if (!boardIds.contains(task.boardId)) {
      throw const FormatException('Orphan backup task');
    }
    unique(task.subtasks.map((child) => child.id));
  }
  validateScheduleCollection(
    schedules,
    parentTaskIds: tasks.map((task) => task.id).toSet(),
    boardIds: boardIds,
  );
  for (final schedule in schedules) {
    if (schedule.title != null &&
        jsonStringUtf8Length(schedule.title!) >
            ImportPreflight.maxScheduleTitleBytes) {
      throw _OversizedRecord();
    }
  }
  return _Library(
    boards: boards,
    tasks: tasks,
    scheduleItems: schedules,
    settings: decoded['settings'] == null
        ? null
        : AppSettings.fromJson(decoded['settings'] as Map<String, dynamic>),
    aiConfig: decoded['aiConfig'] == null
        ? null
        : AIConfig.fromJson(decoded['aiConfig'] as Map<String, dynamic>),
  );
}

/// Imports every volume, carrying all collections and first-volume settings.
/// A chunk continuation is validated against the preceding restored library.
_Library? _restoreInOrder(List<String> bodies) {
  var boards = <Board>[];
  var tasks = <Task>[];
  var scheduleItems = <ScheduleItem>[];
  AppSettings? settings;
  AIConfig? aiConfig;
  for (var index = 0; index < bodies.length; index++) {
    try {
      final plan = ImportPreflight.inspect(
        ImportPreflight.decode(utf8.encode(bodies[index])),
        index == 0 ? 'overwrite' : 'merge',
        currentBoards: boards,
        currentTasks: tasks,
        currentScheduleItems: scheduleItems,
        revision: 0,
      );
      if (plan.conflicts != 0 ||
          plan.warnings.any((warning) => warning.contains('Orphan'))) {
        return null;
      }
      boards = plan.boards;
      tasks = plan.tasks;
      scheduleItems = plan.scheduleItems;
      if (index == 0) {
        settings = plan.settings;
        aiConfig = plan.aiConfig;
      }
    } on BackupRejectedException {
      return null;
    } catch (_) {
      return null;
    }
  }
  return _Library(
    boards: boards,
    tasks: tasks,
    scheduleItems: scheduleItems,
    settings: settings,
    aiConfig: aiConfig,
  );
}

bool _sameRecords(
  List<Map<String, dynamic>> original,
  List<Map<String, dynamic>> actual,
) {
  final byId = {for (final record in actual) record['id']: jsonEncode(record)};
  return original.length == actual.length &&
      byId.length == actual.length &&
      original.every((record) => byId[record['id']] == jsonEncode(record));
}

bool _sameLibrary(_Library original, _Library? actual) =>
    actual != null &&
    (_sameRecords(
          original.boards.map((board) => board.toJson()).toList(),
          actual.boards.map((board) => board.toJson()).toList(),
        ) ||
        // Overwrite of an empty library creates the ordinary default board.
        // Its generated id/time do not represent dropped source content.
        (original.boards.isEmpty &&
            original.tasks.isEmpty &&
            original.scheduleItems.isEmpty &&
            actual.boards.length == 1)) &&
    _sameRecords(
      original.tasks.map((task) => task.toJson()).toList(),
      actual.tasks.map((task) => task.toJson()).toList(),
    ) &&
    _sameRecords(
      original.scheduleItems.map((item) => item.toJson()).toList(),
      actual.scheduleItems.map((item) => item.toJson()).toList(),
    ) &&
    jsonEncode(original.settings?.toJson()) ==
        jsonEncode(actual.settings?.toJson()) &&
    jsonEncode(original.aiConfig?.toJson(includeCredential: true)) ==
        jsonEncode(actual.aiConfig?.toJson(includeCredential: true));

/// A task and its linked schedules must first appear together in one volume.
class _TaskRecord {
  _TaskRecord(this.json, this.scheduleItems)
    : bytes = _encodedBytes(json) + 1 + _recordBytes(scheduleItems);

  final Map<String, dynamic> json;
  final List<Map<String, dynamic>> scheduleItems;
  final int bytes;
}

/// A board's first appearance owns all of its independent events. Later
/// appearances repeat only the board, alongside more tasks or recovery chunks.
class _Group {
  _Group(this.board, this.tasks, this.events)
    : boardBytes = _encodedBytes(board) + 1,
      eventBytes = _recordBytes(events);

  final Map<String, dynamic> board;
  final List<_TaskRecord> tasks;
  final List<Map<String, dynamic>> events;
  final int boardBytes;
  final int eventBytes;

  int get bytes =>
      boardBytes + eventBytes + tasks.fold(0, (sum, task) => sum + task.bytes);
}

List<_Group> _groupByBoard(
  List<dynamic> boards,
  List<dynamic> tasks,
  Map<String, List<Map<String, dynamic>>> schedulesByTask,
  Map<String, List<Map<String, dynamic>>> eventsByBoard,
) {
  final byId = <String, List<_TaskRecord>>{};
  for (final task in tasks) {
    final record = task as Map<String, dynamic>;
    byId
        .putIfAbsent(record['boardId'] as String, () => [])
        .add(_TaskRecord(record, schedulesByTask[record['id']] ?? const []));
  }
  final groups = <_Group>[];
  for (final board in boards) {
    final record = board as Map<String, dynamic>;
    final id = record['id'];
    groups.add(
      _Group(record, byId[id] ?? const [], eventsByBoard[id] ?? const []),
    );
  }
  return groups;
}

/// Greedy packing includes every dependency's escaped JSON bytes. Finish a
/// pending task/event group before splitting a large board. Empty boards can
/// join its first volume without moving a repeated board ahead of its events.
List<_Draft>? _pack(List<_Group> groups, Map<String, dynamic> source) {
  final drafts = <_Draft>[];
  var draft = _Draft(source, first: true);
  void flush() {
    if (draft.isEmpty) return;
    drafts.add(draft);
    draft = _Draft(source, first: false);
  }

  for (final group in groups) {
    final cost = group.bytes;
    if (cost <= ImportPreflight.maxBytes) {
      if (draft.contentBytes + cost > ImportPreflight.maxBytes ||
          draft.bytes + cost > ImportPreflight.maxFileBytes) {
        flush();
      }
      if (draft.bytes + cost <= ImportPreflight.maxFileBytes) {
        draft.addBoard(group.board);
        draft.addEvents(group.events);
        for (final task in group.tasks) {
          draft.addTask(task);
        }
        continue;
      }
    }
    if (draft.tasks.isNotEmpty ||
        draft.scheduleItems.isNotEmpty ||
        draft.contentBytes + group.boardBytes + group.eventBytes >
            ImportPreflight.maxBytes ||
        draft.bytes + group.boardBytes + group.eventBytes >
            ImportPreflight.maxFileBytes) {
      flush();
    }
    // A board with too many independent events cannot be introduced in pieces.
    if (draft.bytes + group.boardBytes + group.eventBytes >
        ImportPreflight.maxFileBytes) {
      return null;
    }
    draft.addBoard(group.board);
    draft.addEvents(group.events);
    for (final task in group.tasks) {
      if (draft.contentBytes + task.bytes > ImportPreflight.maxBytes ||
          draft.bytes + task.bytes > ImportPreflight.maxFileBytes) {
        // A board without events can stay beside its first indivisible task,
        // even if that task exceeds the 4 MiB target budget.
        if (draft.tasks.isNotEmpty ||
            draft.scheduleItems.isNotEmpty ||
            draft.bytes + task.bytes > ImportPreflight.maxFileBytes) {
          flush();
          draft.addBoard(group.board);
        }
      }
      if (draft.bytes + task.bytes > ImportPreflight.maxFileBytes) return null;
      draft.addTask(task);
    }
    flush();
  }
  flush();
  if (drafts.isEmpty) drafts.add(draft);
  return drafts;
}

/// The exact check a restore runs: bounded read, then preflight against an empty
/// library, returning the rejection's copy key or null when the file passes.
///
/// Merge mode still rejects size, structure and ordinary count violations. A
/// task whose board is missing is a skip, and a skip is not a complete backup:
/// the caller must not report success for a file that would drop that task.
String? _gateRejection(String document) {
  try {
    final plan = ImportPreflight.inspect(
      ImportPreflight.decode(utf8.encode(document)),
      'merge',
      currentBoards: const [],
      currentTasks: const [],
      revision: 0,
    );
    if (plan.skipped > 0) return 'exportErrorIncomplete';
    return null;
  } on BackupRejectedException catch (error) {
    return error.copy;
  } catch (_) {
    return 'importError';
  }
}

/// What a library holds, counted the way a restore that imports every volume in
/// order ends up counting it.
class _LibraryCounts {
  const _LibraryCounts(
    this.boards,
    this.tasks,
    this.subtasks,
    this.scheduleItems,
  );

  final int boards;
  final int tasks;
  final int subtasks;
  final int scheduleItems;

  bool get overSupportedCaps =>
      boards > ImportPreflight.maxBoards ||
      tasks > ImportPreflight.maxTasks ||
      subtasks > ImportPreflight.maxSubtasks ||
      scheduleItems > ImportPreflight.maxScheduleItems;
}

/// Counts the records a full restore of [decoded] would leave in the library.
///
/// Distinct ids, because that is what the import gate counts too: a board
/// repeated by every volume its tasks span is one board, and an identical
/// repeat is skipped rather than added. A record without a usable id is counted
/// on its own — the gate refuses such a record anyway, and counting it can only
/// make an export refusal come earlier, never later.
_LibraryCounts _libraryCounts(Map<String, dynamic> decoded) {
  final tasks = <Map<dynamic, dynamic>>[];
  final seenTasks = <String>{};
  for (final record in (decoded['tasks'] as List?) ?? const <dynamic>[]) {
    if (record is! Map) continue;
    final id = record['id'];
    if (id is String && !seenTasks.add(id)) continue;
    tasks.add(record);
  }
  var subtasks = 0;
  for (final task in tasks) {
    final children = task['subtasks'];
    if (children is List) subtasks += _distinctIdCount(children);
  }
  return _LibraryCounts(
    _distinctIdCount((decoded['boards'] as List?) ?? const <dynamic>[]),
    tasks.length,
    subtasks,
    decoded['version'] == 3
        ? _distinctIdCount(decoded['scheduleItems'] as List<dynamic>)
        : 0,
  );
}

int _distinctIdCount(List<dynamic> records) {
  final seen = <String>{};
  var count = 0;
  for (final record in records) {
    final id = record is Map ? record['id'] : null;
    if (id is String) {
      if (seen.add(id)) count++;
    } else {
      count++;
    }
  }
  return count;
}

int _encodedBytes(Object? value) => utf8.encode(jsonEncode(value)).length;

int _recordBytes(List<Map<String, dynamic>> records) =>
    records.fold(0, (sum, record) => sum + _encodedBytes(record) + 1);

/// File name for one part. A single-file backup keeps the plain name, so an
/// older build reads it exactly as before.
String backupFileName(String date, BackupPart part) => part.total == 1
    ? 'matrixflow_backup_$date.json'
    : 'matrixflow_backup_${date}_part${part.index}of${part.total}.json';
