import 'dart:convert';

import 'import_preflight.dart';

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

/// Result of building the backup for a library. Anything other than [single]
/// and [split] means the app could not produce files it would also accept on
/// the import side, so export reports that instead of claiming a backup success
/// the user cannot rely on.
///
/// [libraryTooLarge] is the record-count answer: the library holds more boards,
/// tasks or subtasks than a restore may end up with, or it needs more volumes
/// than [ImportPreflight.maxParts] allows. Both mean the same thing to the
/// user — this library cannot be backed up on these limits.
enum BackupStatus { single, split, oversizedRecord, libraryTooLarge }

class BackupBundle {
  const BackupBundle({required this.status, required this.parts});

  final BackupStatus status;

  /// Empty unless [recoverable].
  final List<BackupPart> parts;

  bool get recoverable =>
      status == BackupStatus.single || status == BackupStatus.split;
}

/// Builds backup files from a document [Store.exportJson] already produced and
/// keeps the export/import contract symmetric: every returned file is checked
/// against the same [ImportPreflight] gates a restore runs, so a bundle reported
/// as recoverable can be restored into a fresh, empty library — every volume of
/// it, in order.
///
/// Checking one file at a time is not enough on its own. The result library a
/// restore ends up with is the sum of all the volumes, and the count caps
/// apply to that sum, so a library that is over the caps can produce volumes
/// that each pass on their own. A 10,599-task library did exactly that: two
/// volumes, both legal alone, the second refused after the first had already
/// restored 7,066 tasks. Counting the whole document up front closes that, so
/// the guarantee is stated for the whole file set rather than per file.
///
/// A library whose single file is within the ceiling is exported unchanged, byte
/// for byte. A larger one is split along board boundaries so every part is a
/// complete backup on its own; a single board too large for one part is split
/// further and each of those parts repeats that board's record, which an import
/// counts as an identical skip rather than a conflict. Only the first part
/// carries `settings` and `aiConfig`: a merge import ignores them, and a
/// credential the user chose to include is then written exactly once.
BackupBundle buildBackupBundle(String document) {
  if (_gateRejection(document) == null) {
    return BackupBundle(
      status: BackupStatus.single,
      parts: [BackupPart(index: 1, total: 1, json: document)],
    );
  }
  final decoded = jsonDecode(document) as Map<String, dynamic>;
  // Refuse an over-count library here, before the expensive split and before a
  // single file is written: no truncation, no dropped record, no raised cap,
  // and the file flow shows the existing record-count advice.
  if (_libraryCounts(decoded).overSupportedCaps) {
    return const BackupBundle(status: BackupStatus.libraryTooLarge, parts: []);
  }
  final groups = _groupByBoard(
    decoded['boards'] as List<dynamic>,
    decoded['tasks'] as List<dynamic>,
  );
  final chunks = _pack(groups);
  if (chunks.length > ImportPreflight.maxParts) {
    return const BackupBundle(status: BackupStatus.libraryTooLarge, parts: []);
  }
  final settings = decoded['settings'];
  final aiConfig = decoded['aiConfig'];
  final parts = <BackupPart>[];
  for (var index = 0; index < chunks.length; index++) {
    final json = jsonEncode({
      'version': decoded['version'],
      'timestamp': decoded['timestamp'],
      'boards': chunks[index].boards,
      'tasks': chunks[index].tasks,
      if (index == 0 && settings != null) 'settings': settings,
      if (index == 0 && aiConfig != null) 'aiConfig': aiConfig,
    });
    final rejection = _gateRejection(json);
    if (rejection != null) {
      // A part this app would itself refuse: too many records means the
      // library is over the supported counts, anything else is a single record
      // bigger than a whole file, which no split can carry. Say so instead of
      // writing a file the import gate would later refuse.
      return BackupBundle(
        status: rejection == 'importErrorTooManyRecords'
            ? BackupStatus.libraryTooLarge
            : BackupStatus.oversizedRecord,
        parts: const [],
      );
    }
    parts.add(BackupPart(index: index + 1, total: chunks.length, json: json));
  }
  return BackupBundle(status: BackupStatus.split, parts: parts);
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
        if (owned.isNotEmpty &&
            piece + taskBytes > ImportPreflight.maxBytes) {
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
/// Merge mode is used because it still rejects every size, record and structure
/// violation a file can carry, while a task whose board is missing is reported
/// as skipped instead of blocking a backup.
String? _gateRejection(String document) {
  try {
    ImportPreflight.inspect(
      ImportPreflight.decode(utf8.encode(document)),
      'merge',
      currentBoards: const [],
      currentTasks: const [],
      revision: 0,
    );
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
