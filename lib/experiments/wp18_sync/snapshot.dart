/// Snapshot and identity model for the WP18-R offline sync experiment.
///
/// Nothing here is a product contract. The `library` part of a snapshot is an
/// ordinary v3 backup payload (docs/BACKUP_FORMAT.md); the envelope around it
/// is an experiment-only sidecar that carries the two things a hand-made backup
/// cannot express: which device produced the snapshot, and which records were
/// deleted rather than merely absent. An envelope is never a valid import file
/// and this package does not hand one to the Store.
library;

import 'dart:convert';

import 'digest.dart';

/// The backup contract keeps ids unique per collection, so a schedule id is
/// allowed to equal a task id. Sync keys therefore carry a namespace.
enum SyncNamespace { board, task, subtask, schedule, config }

class SyncKey {
  const SyncKey(this.namespace, this.localId, {this.parentId});

  final SyncNamespace namespace;
  final String localId;

  /// Subtask ids are only unique inside their parent task, so the parent is
  /// part of the identity: moving a child is a delete plus an add.
  final String? parentId;

  String get text {
    if (namespace == SyncNamespace.subtask) {
      return 'subtask:$parentId/$localId';
    }
    return '${namespace.name}:$localId';
  }

  static String board(String id) => SyncKey(SyncNamespace.board, id).text;
  static String task(String id) => SyncKey(SyncNamespace.task, id).text;
  static String subtask(String taskId, String id) =>
      SyncKey(SyncNamespace.subtask, id, parentId: taskId).text;
  static String schedule(String id) => SyncKey(SyncNamespace.schedule, id).text;
  static String config(String slot) => SyncKey(SyncNamespace.config, slot).text;
}

/// Fields the current reader knows about. Mirrors the whitelists in
/// lib/import_preflight.dart; a field outside one of these sets is a
/// `unknownField` finding, never something the merger invents a meaning for.
const boardFields = {'id', 'name', 'createdAt'};
const taskFields = {
  'id',
  'boardId',
  'title',
  'quadrant',
  'isLongTerm',
  'completed',
  'createdAt',
  'deadline',
  'plannedDate',
  'reasoning',
  'urgencyMode',
  'notesMarkdown',
  'reminderAt',
  'reminderTimezone',
  'completedAt',
  'tags',
};
const subtaskFields = {
  'id',
  'title',
  'completed',
  'deadline',
  'notesMarkdown',
  'reminderAt',
  'completedAt',
};
const scheduleFields = {
  'id',
  'kind',
  'startAt',
  'endAt',
  'timeZoneId',
  'taskId',
  'boardId',
  'title',
};

/// Kept in the live library but not comparable across devices: a chunk cursor
/// and a subtask's place in its parent's list.
const deviceLocalTaskFields = {'recoveryPending'};
const deviceLocalSubtaskFields = {'recoveryPending'};

/// Fields whose meaning is a local civil day, not an absolute instant.
const civilDayTaskFields = {'deadline', 'plannedDate'};

const _maxTimestampMs = 8640000000000000;

class SyncRecord {
  SyncRecord({
    required this.key,
    required this.fields,
    required this.unknownValues,
    required this.position,
  });

  final String key;

  /// Own fields minus the id, so the same content under two ids stays
  /// comparable. Parent links that live in the key are excluded.
  final Map<String, dynamic> fields;

  /// Fields outside the known sets, kept verbatim so a reviewer can see what
  /// the engine refuses to interpret. They are part of [digest], because a
  /// record that only differs by an unknown field is still a difference.
  final Map<String, dynamic> unknownValues;

  /// Index inside the parent collection. Position is user-visible for subtasks.
  final int? position;

  List<String> get unknownFields => (unknownValues.keys.toList()..sort());

  String get digest => contentDigest({
    'fields': fields,
    'unknown': unknownValues,
  });

  String get signature {
    final comparable = Map<String, dynamic>.from(fields);
    for (final field in deviceLocalTaskFields) {
      comparable.remove(field);
    }
    return contentDigest(comparable);
  }

  SyncRecord withFields(Map<String, dynamic> next) => SyncRecord(
    key: key,
    fields: next,
    unknownValues: unknownValues,
    position: position,
  );
}

class DeviceIdentity {
  const DeviceIdentity({
    required this.deviceId,
    required this.label,
    required this.zoneOffsetMinutes,
  });

  final String deviceId;
  final String label;

  /// Prototype stand-in for the device zone. Resolving real IANA rules, DST and
  /// the reminder pipeline belongs to the next package.
  final int zoneOffsetMinutes;

  static const local = DeviceIdentity(
    deviceId: 'dev-local',
    label: 'Local device',
    zoneOffsetMinutes: 480,
  );
  static const remote = DeviceIdentity(
    deviceId: 'dev-remote',
    label: 'Second device',
    zoneOffsetMinutes: -300,
  );

  Map<String, dynamic> toJson() => {
    'deviceId': deviceId,
    'label': label,
    'zoneOffsetMinutes': zoneOffsetMinutes,
  };

  static DeviceIdentity fromJson(Map<String, dynamic> json) => DeviceIdentity(
    deviceId: json['deviceId'] as String,
    label: (json['label'] as String?) ?? json['deviceId'] as String,
    zoneOffsetMinutes: (json['zoneOffsetMinutes'] as num?)?.toInt() ?? 0,
  );
}

class Tombstone {
  const Tombstone({
    required this.key,
    required this.deletedAtMs,
    required this.clock,
    required this.originDeviceId,
    required this.lastDigest,
  });

  final String key;
  final int deletedAtMs;
  final int clock;
  final String originDeviceId;

  /// The digest the record had at deletion. A newer digest on the peer means
  /// the peer edited something the deletion does not know about.
  final String lastDigest;

  Map<String, dynamic> toJson() => {
    'key': key,
    'deletedAtMs': deletedAtMs,
    'clock': clock,
    'originDeviceId': originDeviceId,
    'lastDigest': lastDigest,
  };

  static Tombstone fromJson(Map<String, dynamic> json) {
    final key = json['key'];
    if (key is! String || key.isEmpty) {
      throw const SnapshotFormatException(['Tombstone without a key']);
    }
    return Tombstone(
      key: key,
      deletedAtMs: _requiredInt(json['deletedAtMs'], 'tombstone deletedAtMs'),
      clock: _requiredInt(json['clock'], 'tombstone clock'),
      originDeviceId: (json['originDeviceId'] as String?) ?? '',
      lastDigest: (json['lastDigest'] as String?) ?? '',
    );
  }
}

class RecordState {
  const RecordState({required this.clock, required this.originDeviceId});

  final int clock;
  final String originDeviceId;

  Map<String, dynamic> toJson() => {
    'clock': clock,
    'originDeviceId': originDeviceId,
  };
}

class SnapshotFormatException implements Exception {
  const SnapshotFormatException(this.errors);

  final List<String> errors;

  @override
  String toString() => 'Invalid snapshot: ${errors.join('; ')}';
}

/// One device's view of the library at one instant.
class SyncSnapshot {
  SyncSnapshot({
    required this.device,
    required this.snapshotId,
    required this.sequence,
    required this.takenAtMs,
    this.parentSnapshotId,
    this.records = const {},
    this.tombstones = const [],
    this.recordStates = const {},
    this.settings,
    this.aiConfig,
    this.carriesCredential = false,
    this.unknownTopLevel = const [],
    this.referenceFindings = const [],
  });

  /// Reads a plain v3 payload into the presence-only shape.
  ///
  /// This is what a manual backup can give today: no device, no deletion
  /// evidence, and one shared clock for every record in the file.
  factory SyncSnapshot.fromV3({
    required Map<String, dynamic> payload,
    DeviceIdentity device = DeviceIdentity.local,
    required String snapshotId,
    int sequence = 1,
    int? takenAtMs,
    String? parentSnapshotId,
  }) {
    final parsed = _ParsedLibrary.parse(payload);
    parsed.reject();
    final stamp = takenAtMs ?? _requiredInt(payload['timestamp'], 'timestamp');
    return SyncSnapshot(
      device: device,
      snapshotId: snapshotId,
      sequence: sequence,
      takenAtMs: stamp,
      parentSnapshotId: parentSnapshotId,
      records: parsed.records,
      settings: parsed.settings,
      aiConfig: parsed.aiConfig,
      carriesCredential: parsed.carriesCredential,
      unknownTopLevel: parsed.unknownTopLevel,
      referenceFindings: parsed.referenceFindings,
      recordStates: {
        for (final key in parsed.records.keys)
          key: RecordState(clock: sequence, originDeviceId: device.deviceId),
      },
    );
  }

  factory SyncSnapshot.fromEnvelope(Map<String, dynamic> envelope) {
    final shape = (envelope['envelope'] as String?) ?? '';
    if (shape != envelopeTag) {
      throw SnapshotFormatException(['Unknown envelope "$shape"']);
    }
    final deviceRaw = envelope['device'];
    final snapshotRaw = envelope['snapshot'];
    final libraryRaw = envelope['library'];
    if (deviceRaw is! Map || snapshotRaw is! Map || libraryRaw is! Map) {
      throw const SnapshotFormatException(['Incomplete envelope']);
    }
    final parsed = _ParsedLibrary.parse(
      Map<String, dynamic>.from(libraryRaw),
    );
    parsed.reject();
    final device = DeviceIdentity.fromJson(
      Map<String, dynamic>.from(deviceRaw),
    );
    final tombstones = <Tombstone>[
      for (final raw in (envelope['tombstones'] as List? ?? const []))
        if (raw is Map) Tombstone.fromJson(Map<String, dynamic>.from(raw)),
    ];
    final states = <String, RecordState>{};
    final stateRaw = envelope['recordState'];
    if (stateRaw is Map) {
      for (final entry in stateRaw.entries) {
        if (entry.value is! Map) continue;
        final value = Map<String, dynamic>.from(entry.value as Map);
        states['${entry.key}'] = RecordState(
          clock: _requiredInt(value['clock'], 'record clock'),
          originDeviceId: (value['originDeviceId'] as String?) ?? '',
        );
      }
    }
    final snapshotId = snapshotRaw['snapshotId'];
    if (snapshotId is! String || snapshotId.isEmpty) {
      throw const SnapshotFormatException(['Envelope without a snapshot id']);
    }
    for (final tombstone in tombstones) {
      if (parsed.records.containsKey(tombstone.key)) {
        throw SnapshotFormatException([
          'Tombstone and live record for ${tombstone.key}',
        ]);
      }
    }
    return SyncSnapshot(
      device: device,
      snapshotId: snapshotId,
      sequence: _requiredInt(snapshotRaw['sequence'], 'snapshot sequence'),
      takenAtMs: _requiredInt(snapshotRaw['takenAtMs'], 'snapshot takenAtMs'),
      parentSnapshotId: snapshotRaw['parentSnapshotId'] as String?,
      records: parsed.records,
      tombstones: tombstones,
      recordStates: states,
      settings: parsed.settings,
      aiConfig: parsed.aiConfig,
      carriesCredential: parsed.carriesCredential,
      unknownTopLevel: parsed.unknownTopLevel,
      referenceFindings: parsed.referenceFindings,
    );
  }

  static const envelopeTag = 'wp18-sync/0';

  final DeviceIdentity device;
  final String snapshotId;
  final int sequence;
  final String? parentSnapshotId;
  final int takenAtMs;
  final Map<String, SyncRecord> records;
  final List<Tombstone> tombstones;
  final Map<String, RecordState> recordStates;
  final Map<String, dynamic>? settings;
  final Map<String, dynamic>? aiConfig;

  /// True when the payload held `aiConfig.customApiKey`. The value itself is
  /// dropped on read: an experiment plan must never carry a secret.
  final bool carriesCredential;

  final List<String> unknownTopLevel;
  final List<String> referenceFindings;

  Tombstone? tombstoneFor(String key) {
    for (final tombstone in tombstones) {
      if (tombstone.key == key) return tombstone;
    }
    return null;
  }

  RecordState? stateFor(String key) => recordStates[key];

  /// The record's own clock when the envelope has one. A plain v3 snapshot
  /// leaves every record at the snapshot clock, which is exactly why its
  /// ordering information cannot be trusted as a sync clock.
  int clockFor(String key) => recordStates[key]?.clock ?? sequence;

  String originFor(String key) =>
      recordStates[key]?.originDeviceId ?? device.deviceId;

  /// Content tag for the whole snapshot. The reader in
  /// `LocalDirectoryTransport.pull` recomputes it from the file it read, so a
  /// torn or edited copy is caught before it can be merged.
  static String digestOf({
    required Object? library,
    required Object? tombstones,
  }) => contentDigest({
    'library': library,
    'tombstones': tombstones,
  });

  String get libraryDigest =>
      digestOf(library: toV3Payload(), tombstones: tombstonePayload());

  /// Tombstone bodies in a stable order.
  List<Map<String, dynamic>> tombstonePayload() => [
    for (final tombstone in [...tombstones]..sort((a, b) => a.key.compareTo(b.key)))
      tombstone.toJson(),
  ];

  /// Writes the presence half of the snapshot back as a v3 payload.
  Map<String, dynamic> toV3Payload() {
    final boards = <Map<String, dynamic>>[];
    final tasks = <Map<String, dynamic>>[];
    final schedule = <Map<String, dynamic>>[];
    final children = <String, List<SyncRecord>>{};
    for (final entry in records.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key))) {
      final key = entry.key;
      final fields = Map<String, dynamic>.from(entry.value.fields);
      if (key.startsWith('board:')) {
        boards.add({'id': key.substring('board:'.length), ...fields});
      } else if (key.startsWith('task:')) {
        tasks.add({'id': key.substring('task:'.length), ...fields});
      } else if (key.startsWith('schedule:')) {
        schedule.add({'id': key.substring('schedule:'.length), ...fields});
      } else if (key.startsWith('subtask:')) {
        final taskId = key.substring('subtask:'.length).split('/').first;
        (children[taskId] ??= []).add(entry.value);
      }
    }
    for (final task in tasks) {
      final kids = children['${task['id']}'] ?? const <SyncRecord>[];
      final ordered = kids.toList()
        ..sort((a, b) {
          final byPosition = (a.position ?? 0).compareTo(b.position ?? 0);
          return byPosition != 0 ? byPosition : a.key.compareTo(b.key);
        });
      task['subtasks'] = [
        for (final kid in ordered) {'id': kid.key.split('/').last, ...kid.fields},
      ];
    }
    // A task's children are part of the task record on disk, so a task with no
    // surviving children still needs the (empty) list to stay importable.
    for (final task in tasks) {
      task['subtasks'] ??= <Map<String, dynamic>>[];
    }
    return {
      'version': 3,
      'timestamp': takenAtMs,
      'boards': boards,
      'tasks': tasks,
      'scheduleItems': schedule,
      if (settings != null) 'settings': settings,
      if (aiConfig != null) 'aiConfig': aiConfig,
    };
  }

  /// Writes the experiment envelope: the v3 payload plus the sidecar a manual
  /// backup cannot carry.
  Map<String, dynamic> toEnvelope() => {
    'envelope': envelopeTag,
    'device': device.toJson(),
    'snapshot': {
      'snapshotId': snapshotId,
      'sequence': sequence,
      'parentSnapshotId': parentSnapshotId,
      'takenAtMs': takenAtMs,
      'libraryDigest': libraryDigest,
    },
    'library': toV3Payload(),
    'tombstones': tombstonePayload(),
    'recordState': {
      for (final entry in recordStates.entries) entry.key: entry.value.toJson(),
    },
  };

  String encodeEnvelope() => jsonEncode(toEnvelope());

  static SyncSnapshot decodeEnvelopeText(String text) =>
      SyncSnapshot.fromEnvelope(
        Map<String, dynamic>.from(jsonDecode(text) as Map),
      );

  /// Adds a deletion marker so an absence stops being ambiguous.
  SyncSnapshot withTombstone(Tombstone tombstone) => SyncSnapshot(
    device: device,
    snapshotId: snapshotId,
    sequence: sequence,
    takenAtMs: takenAtMs,
    parentSnapshotId: parentSnapshotId,
    records: {
      for (final entry in records.entries)
        if (entry.key != tombstone.key) entry.key: entry.value,
    },
    tombstones: [
      for (final existing in tombstones)
        if (existing.key != tombstone.key) existing,
      tombstone,
    ],
    recordStates: recordStates,
    settings: settings,
    aiConfig: aiConfig,
    carriesCredential: carriesCredential,
    unknownTopLevel: unknownTopLevel,
    referenceFindings: referenceFindings,
  );

  SyncSnapshot withRecords(Map<String, SyncRecord> nextRecords) => SyncSnapshot(
    device: device,
    snapshotId: snapshotId,
    sequence: sequence,
    takenAtMs: takenAtMs,
    parentSnapshotId: parentSnapshotId,
    records: nextRecords,
    tombstones: tombstones,
    recordStates: recordStates,
    settings: settings,
    aiConfig: aiConfig,
    carriesCredential: carriesCredential,
    unknownTopLevel: unknownTopLevel,
    referenceFindings: referenceFindings,
  );
}

int _requiredInt(Object? value, String field) {
  if (value is! int) {
    throw SnapshotFormatException(['$field must be an integer']);
  }
  return value;
}

class _ParsedLibrary {
  _ParsedLibrary();

  final records = <String, SyncRecord>{};
  final errors = <String>[];
  final referenceFindings = <String>[];
  final unknownTopLevel = <String>[];
  Map<String, dynamic>? settings;
  Map<String, dynamic>? aiConfig;
  bool carriesCredential = false;

  void reject() {
    if (errors.isNotEmpty) throw SnapshotFormatException(errors);
  }

  static _ParsedLibrary parse(Map<String, dynamic> payload) {
    final out = _ParsedLibrary();
    final rawVersion = payload['version'];
    final version = rawVersion == null ? 1 : _requiredInt(rawVersion, 'version');
    if (version < 1 || version > 3) {
      out.errors.add('Unsupported export version $version');
      return out;
    }
    final knownTop = {
      'version',
      'timestamp',
      'boards',
      'tasks',
      'settings',
      'aiConfig',
      'recovery',
      'recoveryChunks',
      if (version == 3) 'scheduleItems',
    };
    for (final key in payload.keys) {
      if (!knownTop.contains(key)) out.unknownTopLevel.add(key);
    }
    if (version == 3 && payload['scheduleItems'] is! List) {
      out.errors.add('v3 requires a scheduleItems array');
    }
    final boards = payload['boards'];
    final tasks = payload['tasks'];
    if (boards is! List || tasks is! List) {
      out.errors.add('boards and tasks must be arrays');
      return out;
    }
    final schedule = version == 3
        ? (payload['scheduleItems'] as List)
        : const <dynamic>[];
    if (version != 3 && payload.containsKey('scheduleItems')) {
      out.unknownTopLevel.add('scheduleItems(v$version ignored)');
    }

    final boardIds = <String>{};
    for (var index = 0; index < boards.length; index++) {
      final raw = _asMap(boards[index], 'Board ${index + 1}', out);
      if (raw == null) continue;
      final id = _idOf(raw, 'Board ${index + 1}', out);
      if (id == null) continue;
      if (!boardIds.add(id)) {
        out.errors.add('Duplicate board id $id');
        continue;
      }
      out.records[SyncKey.board(id)] = _record(
        SyncKey.board(id),
        raw,
        boardFields,
        {'id'},
        position: index,
      );
    }

    final taskIds = <String>{};
    for (var index = 0; index < tasks.length; index++) {
      final raw = _asMap(tasks[index], 'Task ${index + 1}', out);
      if (raw == null) continue;
      final id = _idOf(raw, 'Task ${index + 1}', out);
      if (id == null) continue;
      if (!taskIds.add(id)) {
        out.errors.add('Duplicate task id $id');
        continue;
      }
      _checkTimes(raw, [
        'createdAt',
        'deadline',
        'plannedDate',
        'reminderAt',
        'completedAt',
      ], 'Task $id', out);
      out.records[SyncKey.task(id)] = _record(
        SyncKey.task(id),
        raw,
        taskFields,
        {'id', 'subtasks'},
        position: index,
      );
      final children = raw['subtasks'];
      if (children is! List) {
        out.errors.add('Task $id has no subtasks array');
        continue;
      }
      final childIds = <String>{};
      for (var child = 0; child < children.length; child++) {
        final childRaw = _asMap(children[child], 'Subtask $id/$child', out);
        if (childRaw == null) continue;
        final childId = _idOf(childRaw, 'Subtask of $id', out);
        if (childId == null) continue;
        if (!childIds.add(childId)) {
          out.errors.add('Duplicate subtask id $childId in task $id');
          continue;
        }
        _checkTimes(childRaw, [
          'deadline',
          'reminderAt',
          'completedAt',
        ], 'Subtask $id/$childId', out);
        out.records[SyncKey.subtask(id, childId)] = _record(
          SyncKey.subtask(id, childId),
          childRaw,
          subtaskFields,
          {'id'},
          position: child,
        );
      }
    }

    final seenScheduleIds = <String>{};
    for (var index = 0; index < schedule.length; index++) {
      final raw = _asMap(schedule[index], 'Schedule ${index + 1}', out);
      if (raw == null) continue;
      final id = _idOf(raw, 'Schedule ${index + 1}', out);
      if (id == null) continue;
      // The contract rejects a repeated schedule id even when the body matches.
      if (!seenScheduleIds.add(id)) {
        out.errors.add('Duplicate schedule id $id');
        continue;
      }
      final kind = raw['kind'];
      final start = raw['startAt'];
      final end = raw['endAt'];
      if (start is! int || end is! int) {
        out.errors.add('Schedule $id needs integer startAt/endAt');
        continue;
      }
      if (start.abs() > _maxTimestampMs ||
          end.abs() > _maxTimestampMs ||
          start >= end) {
        out.errors.add('Schedule $id has an invalid interval');
        continue;
      }
      final zone = raw['timeZoneId'];
      if (zone is! String || !_zoneShapeOk(zone)) {
        out.errors.add('Schedule $id has an unparseable timeZoneId');
        continue;
      }
      final taskId = raw['taskId'];
      final boardId = raw['boardId'];
      final title = raw['title'];
      if (kind == 'timeBlock') {
        if (raw.containsKey('boardId') || raw.containsKey('title')) {
          out.errors.add('Time block $id carries event fields');
          continue;
        }
        if (taskId is! String || taskId.trim().isEmpty) {
          out.errors.add('Time block $id has no taskId');
          continue;
        }
      } else if (kind == 'event') {
        if (title is! String || title.trim().isEmpty) {
          out.errors.add('Event $id has no title');
          continue;
        }
        if ((taskId == null) == (boardId == null)) {
          out.errors.add('Event $id needs exactly one of taskId/boardId');
          continue;
        }
      } else {
        out.errors.add('Schedule $id has unknown kind $kind');
        continue;
      }
      out.records[SyncKey.schedule(id)] = _record(
        SyncKey.schedule(id),
        raw,
        scheduleFields,
        {'id'},
        position: index,
      );
    }

    final rawSettings = payload['settings'];
    if (rawSettings is Map) {
      out.settings = Map<String, dynamic>.from(rawSettings);
    }
    final rawAi = payload['aiConfig'];
    if (rawAi is Map) {
      final copy = Map<String, dynamic>.from(rawAi);
      final credential = copy['customApiKey'];
      out.carriesCredential = credential is String && credential.isNotEmpty;
      copy.remove('customApiKey');
      out.aiConfig = copy;
    }

    // Referential integrity is reported, not silently repaired: the merger has
    // to show the user a dangling reference instead of inventing a record.
    for (final entry in out.records.entries.toList()) {
      final key = entry.key;
      final fields = entry.value.fields;
      if (key.startsWith('task:')) {
        final boardId = fields['boardId'];
        if (boardId is String && boardId.isNotEmpty) {
          if (!boardIds.contains(boardId)) {
            out.referenceFindings.add(
              'Task ${key.substring(5)} points at missing board $boardId',
            );
          }
        }
      }
      if (key.startsWith('schedule:')) {
        final taskId = fields['taskId'];
        if (taskId is String &&
            taskId.isNotEmpty &&
            !taskIds.contains(taskId)) {
          out.referenceFindings.add(
            'Schedule ${key.substring(9)} points at missing task $taskId',
          );
        }
        final boardId = fields['boardId'];
        if (boardId is String &&
            boardId.isNotEmpty &&
            !boardIds.contains(boardId)) {
          out.referenceFindings.add(
            'Schedule ${key.substring(9)} points at missing board $boardId',
          );
        }
      }
    }
    return out;
  }
}

SyncRecord _record(
  String key,
  Map<String, dynamic> raw,
  Set<String> allowed,
  Set<String> dropped, {
  required int? position,
}) {
  final fields = <String, dynamic>{};
  final unknown = <String, dynamic>{};
  for (final entry in raw.entries) {
    if (dropped.contains(entry.key)) continue;
    if (!allowed.contains(entry.key)) {
      unknown[entry.key] = entry.value;
      continue;
    }
    fields[entry.key] = entry.value;
  }
  return SyncRecord(
    key: key,
    fields: fields,
    unknownValues: unknown,
    position: position,
  );
}

Map<String, dynamic>? _asMap(
  Object? raw,
  String scope,
  _ParsedLibrary out,
) {
  if (raw is Map) return Map<String, dynamic>.from(raw);
  out.errors.add('$scope is not an object');
  return null;
}

String? _idOf(Map<String, dynamic> raw, String scope, _ParsedLibrary out) {
  final id = raw['id'];
  if (id is! String || id.trim().isEmpty) {
    out.errors.add('$scope has a missing or blank id');
    return null;
  }
  return id;
}

void _checkTimes(
  Map<String, dynamic> raw,
  List<String> fields,
  String scope,
  _ParsedLibrary out,
) {
  for (final field in fields) {
    final value = raw[field];
    if (value == null) continue;
    if (value is! num || !value.isFinite || value.abs() > _maxTimestampMs) {
      out.errors.add('$scope has an invalid $field');
    }
  }
}

bool _zoneShapeOk(String zone) =>
    RegExp(r'^[A-Za-z]{1,32}([/_+-][A-Za-z0-9]{1,32})*$').hasMatch(zone) ||
    RegExp(r'^[+-]\d{2}:\d{2}$').hasMatch(zone);
