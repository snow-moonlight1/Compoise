/// Maps the task library to sync records and back.
///
/// The library side uses the backup JSON shapes (docs/backup-format.md):
/// boards, parent tasks with nested subtasks, schedule items, and the subset of
/// settings that is meant to follow the user across devices. Every record
/// becomes one key with a fixed set of fields; fields a record does not carry
/// are compared as `null`, so clearing a value is an edit like any other.
library;

import '../models.dart';
import '../schedule_item.dart';
import 'sync_json.dart';
import 'sync_state.dart';

const String boardPrefix = 'b:';
const String taskPrefix = 't:';
const String subtaskPrefix = 's:';
const String schedulePrefix = 'e:';
const String settingsKey = 'cfg:settings';

/// Position inside the parent collection. Not part of the backup shape.
const String orderField = '_o';

const List<String> syncedBoardFields = ['name', 'createdAt', orderField];

const List<String> syncedTaskFields = [
  'boardId',
  'title',
  'quadrant',
  'isLongTerm',
  'completed',
  'createdAt',
  'countProgress',
  'deadline',
  'plannedDate',
  'reasoning',
  'urgencyMode',
  'notesMarkdown',
  'reminderAt',
  'reminderTimezone',
  'completedAt',
  'tags',
  orderField,
];

const List<String> syncedSubtaskFields = [
  'title',
  'completed',
  'deadline',
  'notesMarkdown',
  'reminderAt',
  'completedAt',
  orderField,
];

/// Schedule items are replaced as a whole: their kind decides which
/// association fields are legal, so merging them field by field could produce
/// an item that no device ever wrote.
const String scheduleValueField = 'v';

/// Settings that describe how the user works, not how this device looks.
/// Font size, view mode, motion, tray and shortcut stay per device.
const List<String> syncedSettingFields = [
  'language',
  'theme',
  'themeColor',
  'defaultInputMode',
  'autoGroupAI',
  'autoDecomposeAI',
  'autoCompleteParent',
  'suppressGroupPrompt',
  'suppressLongTermPrompt',
  'hideCompleted',
  'showCompletionRate',
  'comicOutline',
  'neumorphic',
  'urgencyThresholdDays',
];

/// A record without its required field was brought back by an edit made
/// after its other fields were pruned (see [SyncState.prune]). It cannot be
/// rebuilt faithfully, so [deriveLibrary] leaves it out.
const String _boardRequired = 'createdAt';
const String _taskRequired = 'createdAt';
const String _subtaskRequired = 'title';

String subtaskKey(String taskId, String subtaskId) =>
    '$subtaskPrefix${taskId.length}:$taskId:$subtaskId';

/// Returns `(taskId, subtaskId)` for a subtask key, or null when malformed.
(String, String)? parseSubtaskKey(String key) {
  if (!key.startsWith(subtaskPrefix)) return null;
  final rest = key.substring(subtaskPrefix.length);
  final colon = rest.indexOf(':');
  if (colon <= 0) return null;
  final length = int.tryParse(rest.substring(0, colon));
  if (length == null || length <= 0) return null;
  final start = colon + 1;
  if (rest.length < start + length + 2) return null;
  if (rest[start + length] != ':') return null;
  final taskId = rest.substring(start, start + length);
  final subtaskId = rest.substring(start + length + 1);
  if (subtaskId.isEmpty) return null;
  return (taskId, subtaskId);
}

/// One device's library in backup JSON shapes.
class SyncLibrary {
  SyncLibrary({
    required this.boards,
    required this.tasks,
    required this.scheduleItems,
    Map<String, Object?>? settings,
  }) : settings = settings ?? <String, Object?>{};

  final List<Map<String, dynamic>> boards;
  final List<Map<String, dynamic>> tasks;
  final List<Map<String, dynamic>> scheduleItems;

  /// Only [syncedSettingFields]; other keys are ignored.
  final Map<String, Object?> settings;

  factory SyncLibrary.fromModels({
    required List<Board> boards,
    required List<Task> tasks,
    required List<ScheduleItem> scheduleItems,
    required AppSettings settings,
  }) {
    final allSettings = settings.toJson();
    return SyncLibrary(
      boards: [for (final board in boards) board.toJson()],
      tasks: [for (final task in tasks) task.toJson()],
      scheduleItems: [for (final item in scheduleItems) item.toJson()],
      settings: {
        for (final field in syncedSettingFields)
          if (allSettings.containsKey(field)) field: allSettings[field],
        // toJson leaves these out while they are off; off is a value too.
        'comicOutline': settings.comicOutline,
        'neumorphic': settings.neumorphic,
      },
    );
  }

  /// True when any record carries restore state that only this device can
  /// finish. Syncing such a library would spread partially restored text.
  bool get hasPendingRestore => tasks.any(
    (task) =>
        task['recoveryPending'] != null ||
        ((task['subtasks'] as List?) ?? const []).any(
          (sub) => sub is Map && sub['recoveryPending'] != null,
        ),
  );

  int get subtaskCount => tasks.fold(
    0,
    (sum, task) => sum + ((task['subtasks'] as List?)?.length ?? 0),
  );

  /// Backup v4 payload for import preflight. Settings are left out; the host
  /// applies [settings] on top of its own.
  Map<String, dynamic> toBackupPayload({required int timestamp}) => {
    'version': 4,
    'timestamp': timestamp,
    'boards': boards,
    'tasks': tasks,
    'scheduleItems': scheduleItems,
  };

  /// Record key to the full field map of that record.
  Map<String, Map<String, Object?>> flatten() {
    final out = <String, Map<String, Object?>>{};
    for (var i = 0; i < boards.length; i++) {
      final board = boards[i];
      out['$boardPrefix${board['id']}'] = {
        for (final field in syncedBoardFields)
          field: field == orderField ? i : jsonCopy(board[field]),
      };
    }
    for (var i = 0; i < tasks.length; i++) {
      final task = tasks[i];
      final id = '${task['id']}';
      out['$taskPrefix$id'] = {
        for (final field in syncedTaskFields)
          field: field == orderField ? i : jsonCopy(task[field]),
      };
      final subtasks = (task['subtasks'] as List?) ?? const [];
      for (var j = 0; j < subtasks.length; j++) {
        final sub = subtasks[j] as Map;
        out[subtaskKey(id, '${sub['id']}')] = {
          for (final field in syncedSubtaskFields)
            field: field == orderField ? j : jsonCopy(sub[field]),
        };
      }
    }
    for (final item in scheduleItems) {
      final value = Map<String, dynamic>.from(item)..remove('id');
      out['$schedulePrefix${item['id']}'] = {scheduleValueField: value};
    }
    if (settings.isNotEmpty) {
      out[settingsKey] = {
        for (final field in syncedSettingFields)
          if (settings.containsKey(field)) field: jsonCopy(settings[field]),
      };
    }
    return out;
  }

  /// Compares two libraries by content, ignoring schedule order.
  bool sameContentAs(SyncLibrary other) {
    final a = flatten();
    final b = other.flatten();
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      final theirs = b[entry.key];
      if (theirs == null || !sameJson(entry.value, theirs)) return false;
    }
    return true;
  }
}

/// Records the difference between [live] and what [state] currently derives
/// to, stamping every changed field with [clock].
///
/// Records [derive] leaves out (for example because a newer app version wrote
/// a value this build cannot read) are not touched, so they cannot be deleted
/// by accident. Pass [includeSettings] false to let existing remote settings
/// win when a device first joins.
///
/// Returns true when anything was recorded.
bool absorbLibrary(
  SyncState state,
  SyncLibrary live,
  int clock, {
  bool includeSettings = true,
}) {
  var changed = false;
  final before = deriveLibrary(state).flatten();
  final after = live.flatten();
  if (!includeSettings) {
    after.remove(settingsKey);
    before.remove(settingsKey);
  }
  for (final entry in after.entries) {
    final previous = before[entry.key];
    for (final field in entry.value.entries) {
      if (previous == null || !sameJson(field.value, previous[field.key])) {
        state.setField(entry.key, field.key, field.value, clock);
        changed = true;
      }
    }
  }
  for (final key in before.keys) {
    if (!after.containsKey(key)) {
      state.tombstone(key, clock);
      changed = true;
    }
  }
  return changed;
}

int _orderOf(Map<String, Object?> fields) {
  final value = fields[orderField];
  return value is int ? value : 1 << 52;
}

int _compareOrdered(
  MapEntry<String, SyncRecord> a,
  MapEntry<String, SyncRecord> b,
) {
  final byOrder = _orderOf(a.value.fields).compareTo(_orderOf(b.value.fields));
  return byOrder != 0 ? byOrder : a.key.compareTo(b.key);
}

Map<String, dynamic> _withoutNulls(String id, Map<String, Object?> fields) => {
  'id': id,
  for (final entry in fields.entries)
    if (entry.key != orderField && entry.value != null)
      entry.key: jsonCopy(entry.value),
};

/// Builds the library a state describes. Deterministic: every device that
/// holds the same state derives the same library.
SyncLibrary deriveLibrary(SyncState state) {
  final boardEntries = <MapEntry<String, SyncRecord>>[];
  final taskEntries = <MapEntry<String, SyncRecord>>[];
  final subtaskEntries = <String, List<MapEntry<String, SyncRecord>>>{};
  final subtaskIds = <String, String>{};
  final scheduleEntries = <MapEntry<String, SyncRecord>>[];
  final deadBoards = <MapEntry<String, SyncRecord>>[];
  for (final entry in state.records.entries) {
    final key = entry.key;
    final alive = state.isAlive(key);
    if (key.startsWith(boardPrefix)) {
      if (!entry.value.clocks.containsKey(_boardRequired)) continue;
      (alive ? boardEntries : deadBoards).add(entry);
    } else if (key.startsWith(subtaskPrefix)) {
      final parsed = parseSubtaskKey(key);
      if (parsed == null) continue;
      if (!entry.value.clocks.containsKey(_subtaskRequired)) continue;
      if (!alive && !_revivedWithParent(state, key, parsed.$1)) continue;
      (subtaskEntries[parsed.$1] ??= []).add(entry);
      subtaskIds[key] = parsed.$2;
    } else if (!alive) {
      continue;
    } else if (key.startsWith(taskPrefix)) {
      if (!entry.value.clocks.containsKey(_taskRequired)) continue;
      taskEntries.add(entry);
    } else if (key.startsWith(schedulePrefix)) {
      scheduleEntries.add(entry);
    }
  }

  final boards = <Map<String, dynamic>>[];
  void addBoards(Iterable<MapEntry<String, SyncRecord>> entries) {
    for (final entry in entries) {
      final id = entry.key.substring(boardPrefix.length);
      try {
        boards.add(
          Board.fromJson(_withoutNulls(id, entry.value.fields)).toJson(),
        );
      } catch (_) {
        // A value this build cannot read stays in the state untouched.
      }
    }
  }

  addBoards(boardEntries.toList()..sort(_compareOrdered));
  if (boards.isEmpty && deadBoards.isNotEmpty) {
    // Two devices deleted each other's last remaining board. Bring back the
    // most recently edited one so the tasks still have somewhere to live.
    deadBoards.sort((a, b) {
      final byClock = b.value.maxClock.compareTo(a.value.maxClock);
      return byClock != 0 ? byClock : a.key.compareTo(b.key);
    });
    addBoards([deadBoards.first]);
  }
  final boardIds = {for (final board in boards) board['id'] as String};
  final fallbackBoard = boards.isEmpty ? null : boards.first['id'] as String;

  final tasks = <Map<String, dynamic>>[];
  taskEntries.sort(_compareOrdered);
  for (final entry in taskEntries) {
    final id = entry.key.substring(taskPrefix.length);
    final raw = _withoutNulls(id, entry.value.fields);
    if (!boardIds.contains(raw['boardId'])) {
      if (fallbackBoard == null) continue;
      raw['boardId'] = fallbackBoard;
    }
    final subs = (subtaskEntries[id] ?? [])..sort(_compareOrdered);
    raw['subtasks'] = <Map<String, dynamic>>[
      for (final sub in subs)
        _withoutNulls(subtaskIds[sub.key]!, sub.value.fields),
    ];
    try {
      tasks.add(Task.fromJson(raw).toJson());
    } catch (_) {
      try {
        // Keep the task when only a subtask is unreadable.
        raw['subtasks'] = [
          for (final sub in raw['subtasks'] as List)
            if (_readableSubtask(sub as Map<String, dynamic>)) sub,
        ];
        tasks.add(Task.fromJson(raw).toJson());
      } catch (_) {}
    }
  }
  final taskIds = {for (final task in tasks) task['id'] as String};

  final scheduleItems = <Map<String, dynamic>>[];
  scheduleEntries.sort((a, b) => a.key.compareTo(b.key));
  for (final entry in scheduleEntries) {
    final value = entry.value.fields[scheduleValueField];
    if (value is! Map) continue;
    final raw = Map<String, dynamic>.from(value)
      ..['id'] = entry.key.substring(schedulePrefix.length);
    final taskId = raw['taskId'];
    final boardId = raw['boardId'];
    if (taskId != null && !taskIds.contains(taskId)) continue;
    if (boardId != null && !boardIds.contains(boardId)) {
      if (fallbackBoard == null) continue;
      raw['boardId'] = fallbackBoard;
    }
    try {
      scheduleItems.add(ScheduleItem.fromJson(raw).toJson());
    } catch (_) {}
  }

  final settings = <String, Object?>{};
  if (state.isAlive(settingsKey)) {
    final fields = state.records[settingsKey]!.fields;
    for (final field in syncedSettingFields) {
      if (fields[field] != null) settings[field] = jsonCopy(fields[field]);
    }
  }
  return SyncLibrary(
    boards: boards,
    tasks: tasks,
    scheduleItems: scheduleItems,
    settings: settings,
  );
}

/// Deleting a task deletes its subtasks in the same edit, so they share the
/// task's tombstone clock. When a concurrent edit brings the task back, those
/// subtasks come back with it; one deleted on its own earlier stays deleted.
bool _revivedWithParent(SyncState state, String key, String taskId) {
  final parentKey = '$taskPrefix$taskId';
  final parentDeletedAt = state.tombstones[parentKey];
  return parentDeletedAt != null &&
      state.tombstones[key] == parentDeletedAt &&
      state.isAlive(parentKey);
}

bool _readableSubtask(Map<String, dynamic> raw) {
  try {
    SubTask.fromJson(raw);
    return true;
  } catch (_) {
    return false;
  }
}

/// Applies the synced subset of [synced] to the device's own settings JSON.
Map<String, dynamic> overlaySettings(
  Map<String, dynamic> local,
  Map<String, Object?> synced,
) => {
  ...local,
  for (final field in syncedSettingFields)
    if (synced.containsKey(field)) field: jsonCopy(synced[field]),
};
