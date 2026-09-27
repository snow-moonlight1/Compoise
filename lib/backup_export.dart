import 'dart:convert';

import 'import_preflight.dart';
import 'models.dart';
import 'recovery_text.dart';

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
/// [incomplete] means a file would drop tasks on restore, so it is not a
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
/// task is not a complete backup and is not returned.
///
/// A library whose single file passes every ordinary gate is exported
/// unchanged, byte for byte. A larger one is split along board boundaries so
/// every part is a complete backup on its own; a single board too large for
/// one part is split further and each of those parts repeats that board's
/// record, which an import counts as an identical skip rather than a conflict.
/// Only the first part carries `settings` and `aiConfig`.
BackupBundle buildBackupBundle(String document) {
  final whole = _gateRejection(document);
  if (whole == null) {
    return BackupBundle(
      status: BackupStatus.single,
      parts: [BackupPart(index: 1, total: 1, json: document)],
    );
  }
  if (whole == 'exportErrorIncomplete') {
    return const BackupBundle(status: BackupStatus.incomplete, parts: []);
  }
  final decoded = jsonDecode(document) as Map<String, dynamic>;
  final overCount = _libraryCounts(decoded).overSupportedCaps;
  if (overCount) {
    final flagged = jsonEncode({...decoded, 'recovery': true});
    if (utf8.encode(flagged).length <= ImportPreflight.maxFileBytes &&
        _gateRejection(flagged) == null) {
      return BackupBundle(
        status: BackupStatus.recovery,
        parts: [BackupPart(index: 1, total: 1, json: flagged)],
      );
    }
  }
  final noteChunks = <Map<String, dynamic>>[];
  final strippedTasks = <Map<String, dynamic>>[];
  for (final raw in decoded['tasks'] as List<dynamic>) {
    final task = Map<String, dynamic>.from(raw as Map);
    _fitRecord(task, noteChunks);
    strippedTasks.add(task);
  }
  final recovery = overCount || noteChunks.isNotEmpty;
  final groups = _groupByBoard(
    decoded['boards'] as List<dynamic>,
    strippedTasks,
  );
  final packed = _pack(groups);
  final drafts = [
    for (final chunk in packed)
      _Draft(boards: chunk.boards, tasks: chunk.tasks),
  ];
  if (drafts.isEmpty) {
    drafts.add(_Draft(boards: const [], tasks: const []));
  }
  final boardsById = <String, Map<String, dynamic>>{
    for (final board in decoded['boards'] as List<dynamic>)
      if (board is Map && board['id'] is String)
        board['id'] as String: Map<String, dynamic>.from(board),
  };
  final boardOfTask = <String, String>{
    for (final task in strippedTasks)
      if (task['id'] is String && task['boardId'] is String)
        task['id'] as String: task['boardId'] as String,
  };
  for (final chunk in noteChunks) {
    _placeChunk(drafts, chunk, boardsById[boardOfTask[chunk['taskId']]]);
  }
  final settings = decoded['settings'];
  final aiConfig = decoded['aiConfig'];
  final bodies = <String>[];
  for (var index = 0; index < drafts.length; index++) {
    final json = jsonEncode({
      'version': decoded['version'],
      'timestamp': decoded['timestamp'],
      'boards': drafts[index].boards,
      'tasks': drafts[index].tasks,
      if (recovery) 'recovery': true,
      if (drafts[index].chunks.isNotEmpty)
        'recoveryChunks': drafts[index].chunks,
      if (index == 0 && settings != null) 'settings': settings,
      if (index == 0 && aiConfig != null) 'aiConfig': aiConfig,
    });
    if (utf8.encode(json).length > ImportPreflight.maxFileBytes) {
      return const BackupBundle(
        status: BackupStatus.oversizedRecord,
        parts: [],
      );
    }
    bodies.add(json);
  }
  final restored = _restoreInOrder(bodies);
  if (restored == null) {
    return const BackupBundle(status: BackupStatus.incomplete, parts: []);
  }
  if (!_sameTasks(decoded, restored)) {
    return const BackupBundle(status: BackupStatus.incomplete, parts: []);
  }
  final parts = [
    for (var index = 0; index < bodies.length; index++)
      BackupPart(index: index + 1, total: bodies.length, json: bodies[index]),
  ];
  if (parts.length == 1 && !recovery) {
    return BackupBundle(
      status: BackupStatus.single,
      parts: [BackupPart(index: 1, total: 1, json: document)],
    );
  }
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
  _Draft({required this.boards, required this.tasks});

  final List<Map<String, dynamic>> boards;
  final List<Map<String, dynamic>> tasks;
  final List<Map<String, dynamic>> chunks = [];
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
void _fitRecord(Map<String, dynamic> task, List<Map<String, dynamic>> chunks) {
  final id = task['id'];
  if (id is! String) return;
  final subs = task['subtasks'];
  if (subs is List) {
    task['subtasks'] = [
      for (final raw in subs)
        if (raw is Map) Map<String, dynamic>.from(raw) else raw,
    ];
  }
  while (_encodedBytes(task) + _recordSlack > ImportPreflight.maxFileBytes) {
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
) {
  for (final draft in drafts.reversed) {
    final carriesTask = draft.tasks.any(
      (task) => task['id'] == chunk['taskId'],
    );
    final carriesChunk = draft.chunks.any(
      (piece) => piece['taskId'] == chunk['taskId'],
    );
    if (!carriesTask && !carriesChunk) continue;
    draft.chunks.add(chunk);
    if (_draftBytes(draft) <= ImportPreflight.maxFileBytes) return;
    draft.chunks.removeLast();
    // A later piece must not fall back into an earlier volume. Import applies
    // files in order and rejects an offset that arrives before its prefix.
    break;
  }
  final extra = _Draft(
    boards: [if (board != null) Map<String, dynamic>.from(board)],
    tasks: const [],
  );
  extra.chunks.add(chunk);
  drafts.add(extra);
}

int _draftBytes(_Draft draft) => utf8
    .encode(
      jsonEncode({
        'version': 2,
        'boards': draft.boards,
        'tasks': draft.tasks,
        'recovery': true,
        if (draft.chunks.isNotEmpty) 'recoveryChunks': draft.chunks,
      }),
    )
    .length;

/// Imports [bodies] in order against an empty library. Returns the tasks that
/// landed, or null when a part would be refused or would drop a task.
List<Task>? _restoreInOrder(List<String> bodies) {
  var boards = <Board>[];
  var tasks = <Task>[];
  for (var index = 0; index < bodies.length; index++) {
    try {
      final plan = ImportPreflight.inspect(
        ImportPreflight.decode(utf8.encode(bodies[index])),
        index == 0 ? 'overwrite' : 'merge',
        currentBoards: boards,
        currentTasks: tasks,
        revision: 0,
      );
      if (plan.conflicts != 0 ||
          plan.warnings.any((warning) => warning.contains('Orphan'))) {
        return null;
      }
      boards = plan.boards;
      tasks = plan.tasks;
    } on BackupRejectedException {
      return null;
    } catch (_) {
      return null;
    }
  }
  return tasks;
}

bool _sameTasks(Map<String, dynamic> decoded, List<Task> restored) {
  final original = <String, String>{};
  for (final raw in decoded['tasks'] as List<dynamic>) {
    if (raw is! Map) return false;
    final task = Task.fromJson(Map<String, dynamic>.from(raw));
    original[task.id] = jsonEncode(task.toJson());
  }
  final actual = {
    for (final task in restored) task.id: jsonEncode(task.toJson()),
  };
  if (original.length != actual.length) return false;
  for (final entry in original.entries) {
    if (actual[entry.key] != entry.value) return false;
  }
  return true;
}

/// A board and the tasks that live on it are the unit that stays together: a
/// part that carried a task without its board would lose that task on merge.
class _Group {
  _Group(this.board, this.tasks);

  final Map<String, dynamic>? board;
  final List<Map<String, dynamic>> tasks;

  int get bytes =>
      (board == null ? 0 : _encodedBytes(board)) +
      tasks.fold(0, (sum, task) => sum + _encodedBytes(task));
}

/// One part's content before it is encoded.
class _Chunk {
  _Chunk({required this.boards, required this.tasks});

  final List<Map<String, dynamic>> boards;
  final List<Map<String, dynamic>> tasks;
}

List<_Group> _groupByBoard(List<dynamic> boards, List<dynamic> tasks) {
  final byId = <String, List<Map<String, dynamic>>>{};
  final unhosted = <Map<String, dynamic>>[];
  for (final task in tasks) {
    final record = task as Map<String, dynamic>;
    final owner = record['boardId'];
    if (owner is String && owner.isNotEmpty) {
      byId.putIfAbsent(owner, () => []).add(record);
    } else {
      unhosted.add(record);
    }
  }
  final groups = <_Group>[];
  for (final board in boards) {
    final record = board as Map<String, dynamic>;
    final id = record['id'];
    groups.add(
      _Group(record, id is String ? byId.remove(id) ?? const [] : const []),
    );
  }
  byId.forEach((_, owned) => groups.add(_Group(null, owned)));
  if (unhosted.isNotEmpty) groups.add(_Group(null, unhosted));
  return groups;
}

/// Greedy packing to the content budget, so a part's own JSON always stays
/// under the file ceiling: the budget leaves room for the envelope and for the
/// structure the record caps allow on top of the text they carry.
List<_Chunk> _pack(List<_Group> groups) {
  final chunks = <_Chunk>[];
  var boards = <Map<String, dynamic>>[];
  var tasks = <Map<String, dynamic>>[];
  var bytes = 0;
  void flush() {
    if (boards.isEmpty && tasks.isEmpty) return;
    chunks.add(_Chunk(boards: boards, tasks: tasks));
    boards = <Map<String, dynamic>>[];
    tasks = <Map<String, dynamic>>[];
    bytes = 0;
  }

  for (final group in groups) {
    final cost = group.bytes;
    if (cost > ImportPreflight.maxBytes) {
      // This group needs parts of its own. A board too large for one part has
      // its tasks spread over several and each of those parts repeats the board
      // record; the part that is still collecting small boards is untouched.
      if (group.board == null) {
        chunks.add(_Chunk(boards: const [], tasks: group.tasks));
        continue;
      }
      var owned = <Map<String, dynamic>>[];
      var piece = _encodedBytes(group.board);
      for (final task in group.tasks) {
        final taskBytes = _encodedBytes(task);
        if (owned.isNotEmpty && piece + taskBytes > ImportPreflight.maxBytes) {
          chunks.add(_Chunk(boards: [group.board!], tasks: owned));
          owned = <Map<String, dynamic>>[];
          piece = _encodedBytes(group.board);
        }
        owned.add(task);
        piece += taskBytes;
        if (piece > ImportPreflight.maxBytes) {
          chunks.add(_Chunk(boards: [group.board!], tasks: owned));
          owned = <Map<String, dynamic>>[];
          piece = _encodedBytes(group.board);
        }
      }
      if (owned.isNotEmpty) {
        chunks.add(_Chunk(boards: [group.board!], tasks: owned));
      }
      continue;
    }
    if (bytes + cost > ImportPreflight.maxBytes) flush();
    if (group.board != null) boards.add(group.board!);
    tasks.addAll(group.tasks);
    bytes += cost;
  }
  flush();
  return chunks;
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
  const _LibraryCounts(this.boards, this.tasks, this.subtasks);

  final int boards;
  final int tasks;
  final int subtasks;

  bool get overSupportedCaps =>
      boards > ImportPreflight.maxBoards ||
      tasks > ImportPreflight.maxTasks ||
      subtasks > ImportPreflight.maxSubtasks;
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

/// File name for one part. A single-file backup keeps the plain name, so an
/// older build reads it exactly as before.
String backupFileName(String date, BackupPart part) => part.total == 1
    ? 'matrixflow_backup_$date.json'
    : 'matrixflow_backup_${date}_part${part.index}of${part.total}.json';
