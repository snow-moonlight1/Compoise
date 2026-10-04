/// Synthetic scenario catalogue for the WP18-R experiment.
///
/// Every case is synthetic library data in a temporary directory. Nothing here
/// reads a real user library, and the same catalogue drives both the CLI demo
/// and the tests, so a green suite and a printed plan describe the same thing.
library;

import 'package:matrixflow_native/experiments/wp18_sync/planner.dart';
import 'package:matrixflow_native/experiments/wp18_sync/snapshot.dart';

const int epoch = 1790000000000;
const int dayMs = 86400000;

/// Midnight of civil day [dayNumber] as seen at [zoneOffsetMinutes].
int civilMidnight(int dayNumber, int zoneOffsetMinutes) =>
    dayNumber * dayMs - zoneOffsetMinutes * 60000;

Map<String, dynamic> board(String id, String name, {int? createdAt}) => {
  'id': id,
  'name': name,
  'createdAt': createdAt ?? epoch,
};

Map<String, dynamic> task(
  String id,
  String boardId, {
  String title = 'Draft',
  int quadrant = 2,
  bool isLongTerm = false,
  bool completed = false,
  int? createdAt,
  int? deadline,
  int? plannedDate,
  String? reasoning,
  String? urgencyMode,
  String? notes,
  int? reminderAt,
  String? reminderTimezone,
  int? completedAt,
  List<String> tags = const [],
  List<Map<String, dynamic>> subtasks = const [],
  Map<String, dynamic>? extra,
}) => {
  'id': id,
  'boardId': boardId,
  'title': title,
  'quadrant': quadrant,
  'isLongTerm': isLongTerm,
  'completed': completed,
  'createdAt': createdAt ?? epoch,
  if (deadline != null) 'deadline': deadline,
  if (plannedDate != null) 'plannedDate': plannedDate,
  'subtasks': subtasks,
  if (reasoning != null) 'reasoning': reasoning,
  if (urgencyMode != null) 'urgencyMode': urgencyMode,
  if (notes != null) 'notesMarkdown': notes,
  if (reminderAt != null) 'reminderAt': reminderAt,
  if (reminderTimezone != null) 'reminderTimezone': reminderTimezone,
  if (completedAt != null) 'completedAt': completedAt,
  if (tags.isNotEmpty) 'tags': tags,
  ...?extra,
};

Map<String, dynamic> subtask(
  String id, {
  String title = 'Step',
  bool completed = false,
  int? deadline,
  String? notes,
  int? reminderAt,
  int? completedAt,
  Map<String, dynamic>? extra,
}) => {
  'id': id,
  'title': title,
  'completed': completed,
  if (deadline != null) 'deadline': deadline,
  if (notes != null) 'notesMarkdown': notes,
  if (reminderAt != null) 'reminderAt': reminderAt,
  if (completedAt != null) 'completedAt': completedAt,
  ...?extra,
};

Map<String, dynamic> timeBlock(
  String id,
  String taskId, {
  required int startAt,
  required int endAt,
  String timeZoneId = 'Asia/Shanghai',
}) => {
  'id': id,
  'kind': 'timeBlock',
  'taskId': taskId,
  'startAt': startAt,
  'endAt': endAt,
  'timeZoneId': timeZoneId,
};

Map<String, dynamic> event(
  String id, {
  String? title,
  String? taskId,
  String? boardId,
  required int startAt,
  required int endAt,
  String timeZoneId = 'Asia/Shanghai',
  Map<String, dynamic>? extra,
}) => {
  'id': id,
  'kind': 'event',
  if (title != null) 'title': title,
  if (taskId != null) 'taskId': taskId,
  if (boardId != null) 'boardId': boardId,
  'startAt': startAt,
  'endAt': endAt,
  'timeZoneId': timeZoneId,
  ...?extra,
};

Map<String, dynamic> library({
  List<Map<String, dynamic>> boards = const [],
  List<Map<String, dynamic>> tasks = const [],
  List<Map<String, dynamic>> schedule = const [],
  Map<String, dynamic>? settings,
  Map<String, dynamic>? aiConfig,
  int timestamp = epoch,
  Map<String, dynamic>? extra,
}) => {
  'version': 3,
  'timestamp': timestamp,
  'boards': boards,
  'tasks': tasks,
  'scheduleItems': schedule,
  if (settings != null) 'settings': settings,
  if (aiConfig != null) 'aiConfig': aiConfig,
  ...?extra,
};

/// A library plus the deletions and device counters a plain export cannot carry.
class ScenarioSnapshot {
  ScenarioSnapshot({
    required this.device,
    required this.snapshotId,
    required this.sequence,
    required this.takenAtMs,
    required this.library,
    this.deleted = const [],
    this.clocks = const {},
  });

  final DeviceIdentity device;
  final String snapshotId;
  final int sequence;
  final int takenAtMs;
  final Map<String, dynamic> library;

  /// Keys this device removed. `deletedFromLibrary` is true when the payload
  /// already omits them, which is the shape a backup file has.
  final List<String> deleted;
  final Map<String, int> clocks;

  SyncSnapshot materialize({Map<String, SyncRecord>? referenceState}) {
    final parsed = SyncSnapshot.fromV3(
      payload: library,
      device: device,
      snapshotId: snapshotId,
      sequence: sequence,
      takenAtMs: takenAtMs,
    );
    final records = <String, SyncRecord>{...parsed.records};
    final tombstones = <Tombstone>[];
    for (final key in deleted) {
      final previous = referenceState?[key] ?? records[key];
      records.remove(key);
      tombstones.add(
        Tombstone(
          key: key,
          deletedAtMs: takenAtMs,
          clock: clocks[key] ?? sequence,
          originDeviceId: device.deviceId,
          lastDigest: previous?.digest ?? 'unknown',
        ),
      );
    }
    final states = <String, RecordState>{
      for (final entry in parsed.recordStates.entries)
        if (records.containsKey(entry.key)) entry.key: entry.value,
    };
    for (final entry in clocks.entries) {
      states[entry.key] = RecordState(
        clock: entry.value,
        originDeviceId: device.deviceId,
      );
    }
    return SyncSnapshot(
      device: device,
      snapshotId: snapshotId,
      sequence: sequence,
      takenAtMs: takenAtMs,
      records: records,
      tombstones: tombstones,
      recordStates: states,
      settings: parsed.settings,
      aiConfig: parsed.aiConfig,
      carriesCredential: parsed.carriesCredential,
      unknownTopLevel: parsed.unknownTopLevel,
      referenceFindings: parsed.referenceFindings,
    );
  }
}

class ScenarioInput {
  ScenarioInput({
    required this.base,
    required this.local,
    required this.peer,
    this.presence = PresenceModel.tombstoneAware,
  });

  final ScenarioSnapshot base;
  final ScenarioSnapshot local;
  final ScenarioSnapshot peer;
  final PresenceModel presence;

  SyncSnapshot baseSnapshot() => base.materialize();

  /// Builds the local and peer views. A tombstone is only carried when the
  /// scenario says the snapshots are deletion-aware; a hand-made backup has
  /// deletions and no way to say so.
  (SyncSnapshot, SyncSnapshot) pair() {
    final reference = base.materialize().records;
    final l = _view(local, reference);
    final r = _view(peer, reference);
    return (l, r);
  }

  SyncSnapshot _view(ScenarioSnapshot spec, Map<String, SyncRecord> reference) {
    final snapshot = spec.materialize(referenceState: reference);
    if (presence == PresenceModel.tombstoneAware) return snapshot;
    // Same library content, deletion evidence removed.
    return SyncSnapshot(
      device: snapshot.device,
      snapshotId: snapshot.snapshotId,
      sequence: snapshot.sequence,
      takenAtMs: snapshot.takenAtMs,
      parentSnapshotId: snapshot.parentSnapshotId,
      records: snapshot.records,
      recordStates: snapshot.recordStates,
      settings: snapshot.settings,
      aiConfig: snapshot.aiConfig,
      carriesCredential: snapshot.carriesCredential,
      unknownTopLevel: snapshot.unknownTopLevel,
      referenceFindings: snapshot.referenceFindings,
    );
  }
}

class SyncScenario {
  SyncScenario({
    required this.name,
    required this.teaches,
    required this.input,
    this.expectPending = const {},
    this.expectAuto = const {},
    this.expectBlocked = const {},
    this.expectWarnings = const [],
    this.expectSelfCheck,
    this.expectLoadError,
    this.safetyNote,
  });

  final String name;
  final String teaches;
  final ScenarioInput Function() input;

  /// key -> reason the engine must reach. Tests assert these, so the printed
  /// demo and the suite cannot drift apart.
  final Map<String, String> expectPending;
  final Map<String, String> expectAuto;
  final Map<String, String> expectBlocked;
  final List<String> expectWarnings;

  /// Problems the merged library is still expected to carry. A scenario whose
  /// result would be rejected by the product contract has to say so here, so
  /// the suite proves the engine notices instead of quietly writing it.
  final List<String>? expectSelfCheck;
  final String? expectLoadError;
  final String? safetyNote;
}

const _local = DeviceIdentity(
  deviceId: 'dev-laptop',
  label: 'Laptop',
  zoneOffsetMinutes: 480,
);
const _peer = DeviceIdentity(
  deviceId: 'dev-phone',
  label: 'Phone',
  zoneOffsetMinutes: -300,
);

/// Replaces same-id entries in place and appends the rest, so a scenario states
/// only what one device changed.
List<Map<String, dynamic>> _overlay(
  List<Map<String, dynamic>> base,
  List<Map<String, dynamic>> changes,
) {
  final out = [for (final item in base) Map<String, dynamic>.from(item)];
  for (final change in changes) {
    final index = out.indexWhere((item) => item['id'] == change['id']);
    if (index < 0) {
      out.add(Map<String, dynamic>.from(change));
    } else {
      out[index] = Map<String, dynamic>.from(change);
    }
  }
  return out;
}

ScenarioInput _threeWay({
  required List<Map<String, dynamic>> baseBoards,
  required List<Map<String, dynamic>> baseTasks,
  List<Map<String, dynamic>> baseSchedule = const [],
  List<Map<String, dynamic>> localBoards = const [],
  List<Map<String, dynamic>> localTasks = const [],
  List<Map<String, dynamic>> localSchedule = const [],
  List<Map<String, dynamic>> peerBoards = const [],
  List<Map<String, dynamic>> peerTasks = const [],
  List<Map<String, dynamic>> peerSchedule = const [],
  List<String> localDeleted = const [],
  List<String> peerDeleted = const [],
  Map<String, int> localClocks = const {},
  Map<String, int> peerClocks = const {},
  Map<String, dynamic>? baseSettings,
  Map<String, dynamic>? localSettings,
  Map<String, dynamic>? peerSettings,
  Map<String, dynamic>? baseAi,
  Map<String, dynamic>? localAi,
  Map<String, dynamic>? peerAi,
  PresenceModel presence = PresenceModel.tombstoneAware,
}) {
  final baseLib = library(
    boards: baseBoards,
    tasks: baseTasks,
    schedule: baseSchedule,
    settings: baseSettings,
    aiConfig: baseAi,
  );
  return ScenarioInput(
    presence: presence,
    base: ScenarioSnapshot(
      device: _local,
      snapshotId: 'snap-base',
      sequence: 1,
      takenAtMs: epoch,
      library: baseLib,
    ),
    local: ScenarioSnapshot(
      device: _local,
      snapshotId: 'snap-local',
      sequence: 2,
      takenAtMs: epoch + dayMs,
      library: library(
        boards: _overlay(baseBoards, localBoards),
        tasks: _overlay(baseTasks, localTasks),
        schedule: _overlay(baseSchedule, localSchedule),
        settings: localSettings ?? baseSettings,
        aiConfig: localAi ?? baseAi,
      ),
      deleted: localDeleted,
      clocks: localClocks,
    ),
    peer: ScenarioSnapshot(
      device: _peer,
      snapshotId: 'snap-peer',
      sequence: 2,
      takenAtMs: epoch + dayMs,
      library: library(
        boards: _overlay(baseBoards, peerBoards),
        tasks: _overlay(baseTasks, peerTasks),
        schedule: _overlay(baseSchedule, peerSchedule),
        settings: peerSettings ?? baseSettings,
        aiConfig: peerAi ?? baseAi,
      ),
      deleted: peerDeleted,
      clocks: peerClocks,
    ),
  );
}

/// The shared parent task body with one field changed, so each scenario states
/// only the difference it teaches.
Map<String, dynamic> t1({
  String? title,
  String? notes,
  int? plannedDate,
  int? deadline,
  int? reminderAt,
  String? reminderTimezone,
  bool completed = false,
  int? completedAt,
  List<Map<String, dynamic>>? subtasks,
  Map<String, dynamic>? extra,
}) => task(
  't-1',
  'b-1',
  title: title ?? 'Write release notes',
  notes: notes ?? 'cover the save protocol',
  plannedDate: plannedDate ?? civilMidnight(20600, 480),
  deadline: deadline,
  reminderAt: reminderAt,
  reminderTimezone: reminderTimezone,
  completed: completed,
  completedAt: completedAt,
  subtasks: subtasks ?? [subtask('s-1', title: 'list gates')],
  extra: extra,
);

List<Map<String, dynamic>> get _baseTasks => [t1()];

List<SyncScenario> wp18Scenarios() => [
  SyncScenario(
    name: 'add-on-local-only',
    teaches: 'One device adds a task; the other is silent.',
    input: () => _threeWay(
      baseBoards: [board('b-1', 'Release')],
      baseTasks: _baseTasks,
      localTasks: [task('t-2', 'b-1', title: 'Call the vendor')],
    ),
    expectAuto: {'task:t-2': 'addedOnLocalOnly'},
  ),
  SyncScenario(
    name: 'add-on-peer-only',
    teaches: 'The peer adds a task the local device has never seen.',
    input: () => _threeWay(
      baseBoards: [board('b-1', 'Release')],
      baseTasks: _baseTasks,
      peerTasks: [task('t-3', 'b-1', title: 'Rotate the signing key')],
    ),
    expectAuto: {'task:t-3': 'addedOnPeerOnly'},
  ),
  SyncScenario(
    name: 'same-id-same-content',
    teaches:
        'Two devices create the same id with identical content: one copy, no '
        'conflict.',
    input: () => _threeWay(
      baseBoards: [board('b-1', 'Release')],
      baseTasks: _baseTasks,
      localTasks: [task('t-9', 'b-1', title: 'Shared id guess')],
      peerTasks: [task('t-9', 'b-1', title: 'Shared id guess')],
    ),
    expectAuto: {'task:t-9': 'sameIdCreatedOnBothSidesWithSameContent'},
  ),
  SyncScenario(
    name: 'edit-fork-same-field',
    teaches: 'Same id, both sides renamed the task differently.',
    input: () => _threeWay(
      baseBoards: [board('b-1', 'Release')],
      baseTasks: _baseTasks,
      localTasks: [t1(title: 'Ship notes v2')],
      peerTasks: [t1(title: 'Ship notes v3')],
    ),
    expectPending: {'task:t-1': 'editedOnBothSides'},
    safetyNote: 'No policy may pick a title without a user decision.',
  ),
  SyncScenario(
    name: 'fieldwise-disjoint',
    teaches:
        'Each side touched a different field: the engine can merge without '
        'overwriting anybody.',
    input: () => _threeWay(
      baseBoards: [board('b-1', 'Release')],
      baseTasks: _baseTasks,
      localTasks: [t1(notes: 'add the gate table')],
      peerTasks: [t1(deadline: civilMidnight(20605, 480))],
    ),
    expectAuto: {'task:t-1': 'fieldwiseMergedNoFieldTouchedTwice'},
  ),
  SyncScenario(
    name: 'delete-edit-peer-deleted',
    teaches: 'The peer deleted a task the local device edited.',
    input: () => _threeWay(
      baseBoards: [board('b-1', 'Release')],
      baseTasks: _baseTasks,
      localTasks: [t1(title: 'Write release notes (edited)')],
      peerDeleted: ['task:t-1', 'subtask:t-1/s-1', 'schedule:k-1'],
    ),
    expectPending: {'task:t-1': 'peerDeletedWhileLocalEdited'},
    safetyNote:
        'A deletion is a user decision. preferPeer may not resurrect it, and '
        'the merged library keeps the local edit untouched.',
  ),
  SyncScenario(
    name: 'delete-unchanged',
    teaches: 'One side deleted an untouched task: the deletion is decided.',
    input: () => _threeWay(
      baseBoards: [board('b-1', 'Release')],
      baseTasks: _baseTasks,
      peerDeleted: ['task:t-1', 'subtask:t-1/s-1', 'schedule:k-1'],
    ),
    expectAuto: {'task:t-1': 'peerDeletedLocalUnchanged'},
  ),
  SyncScenario(
    name: 'presence-only-missing',
    teaches:
        'A hand-made backup omits a task but cannot say why, so absence is not '
        'a deletion.',
    input: () => _threeWay(
      presence: PresenceModel.presenceOnly,
      baseBoards: [board('b-1', 'Release')],
      baseTasks: _baseTasks,
      peerDeleted: ['task:t-1', 'subtask:t-1/s-1', 'schedule:k-1'],
    ),
    expectPending: {'task:t-1': 'presenceOnlyCannotTellDeletion'},
    safetyNote: 'Manual export is not a sync feed.',
  ),
  SyncScenario(
    name: 'add-add-duplicate-different-ids',
    teaches:
        'Both devices typed the same task and got two ids: deduping is a product '
        'decision, so it waits.',
    input: () => _threeWay(
      baseBoards: [board('b-1', 'Release')],
      baseTasks: _baseTasks,
      localTasks: [task('t-l1', 'b-1', title: 'Book the room')],
      peerTasks: [task('t-p1', 'b-1', title: 'Book the room')],
    ),
    expectPending: {'task:t-p1': 'sameContentUnderDifferentId'},
    expectAuto: {'task:t-l1': 'addedOnLocalOnly'},
  ),
  SyncScenario(
    name: 'concurrent-completion',
    teaches: 'Both devices completed the same task at different instants.',
    input: () => _threeWay(
      baseBoards: [board('b-1', 'Release')],
      baseTasks: _baseTasks,
      localTasks: [t1(completed: true, completedAt: epoch + dayMs)],
      peerTasks: [
        t1(completed: true, completedAt: epoch + 2 * dayMs),
      ],
    ),
    expectPending: {'task:t-1': 'editedOnBothSides'},
    safetyNote: 'Which completion wins is a product rule, not a digest guess.',
  ),
  SyncScenario(
    name: 'subtask-reparented',
    teaches:
        'A child moved between tasks; read literally that is a delete plus a '
        'duplicate.',
    input: () => _threeWay(
      baseBoards: [board('b-1', 'Release')],
      baseTasks: [
        ..._baseTasks,
        task('t-2', 'b-1', title: 'Ops'),
      ],
      localDeleted: ['subtask:t-1/s-1'],
      peerTasks: [
        t1(subtasks: const []),
        task('t-2', 'b-1', title: 'Ops', subtasks: [subtask('s-1', title: 'list gates')]),
      ],
    ),
    expectPending: {
      'subtask:t-1/s-1': 'subtaskMayHaveMovedParent',
      'subtask:t-2/s-1': 'subtaskMayHaveMovedParent',
    },
    safetyNote: 'A move must never leave two copies of the same child.',
  ),
  SyncScenario(
    name: 'board-rename-with-new-task',
    teaches: 'The peer renamed a board while the local device added a task.',
    input: () => _threeWay(
      baseBoards: [board('b-1', 'Release')],
      baseTasks: _baseTasks,
      localTasks: [task('t-2', 'b-1', title: 'Draft changelog')],
      peerBoards: [board('b-1', 'Release 26.10', createdAt: epoch)],
    ),
    expectAuto: {
      'task:t-2': 'addedOnLocalOnly',
      'board:b-1': 'onlyPeerChanged',
    },
  ),
  SyncScenario(
    name: 'schedule-parent-deleted',
    teaches:
        'A new block points at a task the other device deleted: the referrer is '
        'withheld instead of dangling.',
    input: () => _threeWay(
      baseBoards: [board('b-1', 'Release')],
      baseTasks: [
        ..._baseTasks,
        task('t-8', 'b-1', title: 'Plan review'),
      ],
      localSchedule: [
        timeBlock(
          'k-8',
          't-8',
          startAt: epoch + 4 * dayMs,
          endAt: epoch + 5 * dayMs,
        ),
      ],
      peerDeleted: ['task:t-8'],
    ),
    expectAuto: {'schedule:k-8': 'addedOnLocalOnly'},
    expectBlocked: {'task:t-8': 'deletionWouldOrphanDependents'},
    safetyNote:
        'The task and its block commit as one batch, so a deletion that would '
        'orphan the block is withheld instead of half-applied.',
  ),
  SyncScenario(
    name: 'peer-added-block-for-deleted-task',
    teaches:
        'The peer adds a block whose task the local device deleted: the new '
        'record is withheld, so nothing is added by mistake.',
    input: () => _threeWay(
      baseBoards: [board('b-1', 'Release')],
      baseTasks: _baseTasks,
      peerSchedule: [
        timeBlock(
          'k-2',
          't-1',
          startAt: epoch + 6 * dayMs,
          endAt: epoch + 7 * dayMs,
        ),
      ],
      localDeleted: ['task:t-1', 'subtask:t-1/s-1', 'schedule:k-1'],
    ),
    expectBlocked: {'schedule:k-2': 'referencedRecordNotSettled'},
    safetyNote: 'An orphan is never converted into a standalone event.',
  ),
  SyncScenario(
    name: 'both-deleted-without-evidence',
    teaches:
        'A record gone from both hand-made backups, with no tombstone anywhere: '
        'the engine will not call that a deletion.',
    input: () => _threeWay(
      presence: PresenceModel.presenceOnly,
      baseBoards: [board('b-1', 'Release')],
      baseTasks: _baseTasks,
      localDeleted: ['task:t-1', 'subtask:t-1/s-1', 'schedule:k-1'],
      peerDeleted: ['task:t-1', 'subtask:t-1/s-1', 'schedule:k-1'],
    ),
    expectPending: {'task:t-1': 'goneOnBothSidesWithoutEvidence'},
  ),
  SyncScenario(
    name: 'unknown-field-only-change',
    teaches:
        'A peer that only adds an unrecognized field still has to be read '
        'before anything moves.',
    input: () => _threeWay(
      baseBoards: [board('b-1', 'Release')],
      baseTasks: _baseTasks,
      peerTasks: [t1(extra: {'syncPinned': true})],
    ),
    expectPending: {'task:t-1': 'unrecognizedFieldsPresent'},
  ),
  SyncScenario(
    name: 'board-deleted-with-tasks-on-it',
    teaches: 'A board deletion cannot leave its tasks stranded.',
    input: () => _threeWay(
      baseBoards: [board('b-1', 'Release')],
      baseTasks: _baseTasks,
      peerDeleted: ['board:b-1'],
    ),
    expectBlocked: {'board:b-1': 'deletionWouldOrphanDependents'},
  ),
  SyncScenario(
    name: 'delete-board-and-its-tasks-together',
    teaches:
        'When the whole batch is deleted together, the deletion is decided and '
        'nothing is left dangling.',
    input: () => _threeWay(
      baseBoards: [board('b-1', 'Release')],
      baseTasks: _baseTasks,
      peerDeleted: ['board:b-1', 'task:t-1', 'subtask:t-1/s-1', 'schedule:k-1'],
    ),
    expectAuto: {'board:b-1': 'peerDeletedLocalUnchanged'},
  ),
  SyncScenario(
    name: 'schedule-kind-changed',
    teaches:
        'The same id turning from a block into an event is a shape change, not '
        'an edit.',
    input: () => _threeWay(
      baseBoards: [board('b-1', 'Release')],
      baseTasks: _baseTasks,
      baseSchedule: [
        timeBlock('k-1', 't-1', startAt: epoch, endAt: epoch + dayMs),
      ],
      localSchedule: [
        timeBlock(
          'k-1',
          't-1',
          startAt: epoch + dayMs,
          endAt: epoch + 2 * dayMs,
        ),
      ],
      peerSchedule: [
        event(
          'k-1',
          title: 'Review',
          taskId: 't-1',
          startAt: epoch,
          endAt: epoch + dayMs,
        ),
      ],
    ),
    expectPending: {'schedule:k-1': 'editedOnBothSides'},
  ),
  SyncScenario(
    name: 'board-rename-fork',
    teaches: 'Both sides renamed the same board differently.',
    input: () => _threeWay(
      baseBoards: [board('b-1', 'Release')],
      baseTasks: _baseTasks,
      localBoards: [board('b-1', 'Release notes')],
      peerBoards: [board('b-1', 'Ship list')],
    ),
    expectPending: {'board:b-1': 'editedOnBothSides'},
  ),
  SyncScenario(
    name: 'id-namespace-collision',
    teaches: 'A task id and a schedule id may be equal; that is not a conflict.',
    input: () => _threeWay(
      baseBoards: [board('b-1', 'Release')],
      baseTasks: [task('shared-1', 'b-1', title: 'Shared name')],
      baseSchedule: [
        timeBlock(
          'shared-1',
          'shared-1',
          startAt: epoch,
          endAt: epoch + dayMs,
        ),
      ],
      localTasks: [task('shared-1', 'b-1', title: 'Shared name edited')],
    ),
    expectAuto: {'task:shared-1': 'onlyLocalChanged'},
  ),
  SyncScenario(
    name: 'planned-date-same-civil-day',
    teaches:
        'Two zones wrote different epoch values for the same planned day: a '
        'false conflict the engine can dismiss.',
    input: () => _threeWay(
      baseBoards: [board('b-1', 'Release')],
      baseTasks: [
        task(
          't-1',
          'b-1',
          plannedDate: civilMidnight(20600, 0),
          subtasks: [subtask('s-1', title: 'list gates')],
        ),
      ],
      localTasks: [
        task(
          't-1',
          'b-1',
          plannedDate: civilMidnight(20600, 480),
          subtasks: [subtask('s-1', title: 'list gates')],
        ),
      ],
      peerTasks: [
        task(
          't-1',
          'b-1',
          plannedDate: civilMidnight(20600, -300),
          subtasks: [subtask('s-1', title: 'list gates')],
        ),
      ],
    ),
    expectAuto: {'task:t-1': 'sameCivilDayDifferentZone'},
  ),
  SyncScenario(
    name: 'planned-date-different-day',
    teaches: 'A real difference in the planned day stays a conflict.',
    input: () => _threeWay(
      baseBoards: [board('b-1', 'Release')],
      baseTasks: [
        task(
          't-1',
          'b-1',
          plannedDate: civilMidnight(20600, 480),
          subtasks: [subtask('s-1', title: 'list gates')],
        ),
      ],
      localTasks: [
        task(
          't-1',
          'b-1',
          plannedDate: civilMidnight(20601, 480),
          subtasks: [subtask('s-1', title: 'list gates')],
        ),
      ],
      peerTasks: [
        task(
          't-1',
          'b-1',
          plannedDate: civilMidnight(20603, -300),
          subtasks: [subtask('s-1', title: 'list gates')],
        ),
      ],
    ),
    expectPending: {'task:t-1': 'editedOnBothSides'},
  ),
  SyncScenario(
    name: 'reminder-timezone-divergence',
    teaches: 'A reminder zone change is a real change, not a formatting note.',
    input: () => _threeWay(
      baseBoards: [board('b-1', 'Release')],
      baseTasks: [
        task(
          't-1',
          'b-1',
          reminderAt: epoch + dayMs,
          reminderTimezone: 'Asia/Shanghai',
          subtasks: [subtask('s-1', title: 'list gates')],
        ),
      ],
      peerTasks: [
        task(
          't-1',
          'b-1',
          reminderAt: epoch + dayMs,
          reminderTimezone: 'America/New_York',
          subtasks: [subtask('s-1', title: 'list gates')],
        ),
      ],
    ),
    expectAuto: {'task:t-1': 'onlyPeerChanged'},
  ),
  SyncScenario(
    name: 'unknown-field-on-peer',
    teaches: 'A field the reader does not know stops the merge for that record.',
    input: () => _threeWay(
      baseBoards: [board('b-1', 'Release')],
      baseTasks: _baseTasks,
      peerTasks: [
        task(
          't-1',
          'b-1',
          title: 'Write release notes',
          notes: 'cover the save protocol',
          plannedDate: civilMidnight(20600, 480),
          subtasks: [subtask('s-1', title: 'list gates')],
          extra: {'syncPinned': true},
        ),
      ],
    ),
    expectPending: {'task:t-1': 'unrecognizedFieldsPresent'},
    safetyNote: 'Unknown fields never ride along silently.',
  ),
  SyncScenario(
    name: 'settings-divergence',
    teaches: 'Settings are a whole-blob decision, never a field merge.',
    input: () => _threeWay(
      baseBoards: [board('b-1', 'Release')],
      baseTasks: _baseTasks,
      baseSettings: {'language': 'zh', 'theme': 'system'},
      localSettings: {'language': 'en', 'theme': 'system'},
      peerSettings: {'language': 'ja', 'theme': 'dark'},
    ),
    expectPending: {'config:settings': 'settingsDiffer'},
  ),
  SyncScenario(
    name: 'credential-never-transported',
    teaches: 'An API key in a payload is dropped by the reader and blocked.',
    input: () => _threeWay(
      baseBoards: [board('b-1', 'Release')],
      baseTasks: _baseTasks,
      baseAi: {
        'providerId': 'deepseek',
        'customBaseUrl': 'https://api.deepseek.com',
        'customModel': 'chat',
      },
      localAi: {
        'providerId': 'deepseek',
        'customBaseUrl': 'https://api.deepseek.com',
        'customModel': 'chat',
        'customApiKey': 'SECRET-LOCAL-DO-NOT-SHARE',
      },
      peerAi: {
        'providerId': 'custom',
        'customBaseUrl': 'https://example.invalid/v1',
        'customModel': 'other',
        'customApiKey': 'SECRET-PEER-DO-NOT-SHARE',
      },
    ),
    expectBlocked: {'config:credential': 'credentialNeverTransported'},
    safetyNote:
        'No plan text, merged file, or transport copy may contain the key '
        'value.',
  ),
  SyncScenario(
    name: 'subtask-both-edited',
    teaches: 'A child edited on both sides is a fork like any other record.',
    input: () => _threeWay(
      baseBoards: [board('b-1', 'Release')],
      baseTasks: _baseTasks,
      localTasks: [t1(subtasks: [subtask('s-1', title: 'list gates locally')])],
      peerTasks: [
        t1(subtasks: [subtask('s-1', title: 'list gates and dates')]),
      ],
    ),
    expectPending: {'subtask:t-1/s-1': 'editedOnBothSides'},
  ),
  SyncScenario(
    name: 'subtask-reordered-both',
    teaches: 'Identical children in a different order: content matches, order '
        'does not.',
    input: () {
      List<Map<String, dynamic>> order(List<String> ids) => [
        for (final id in ids) subtask(id, title: 'step $id'),
      ];

      return _threeWay(
        baseBoards: [board('b-1', 'Release')],
        baseTasks: [t1(subtasks: order(['s-1', 's-2', 's-3']))],
        localTasks: [t1(subtasks: order(['s-2', 's-1', 's-3']))],
        peerTasks: [t1(subtasks: order(['s-1', 's-3', 's-2']))],
      );
    },
    expectPending: {'subtask:t-1/s-2': 'reorderedOnBothSides'},
    expectAuto: {'subtask:t-1/s-1': 'onlyLocalReordered'},
  ),
  SyncScenario(
    name: 'clock-tie-same-counter',
    teaches:
        'Equal device counters give no ordering. The plan still stays stable '
        'and says so.',
    input: () => _threeWay(
      baseBoards: [board('b-1', 'Release')],
      baseTasks: _baseTasks,
      localTasks: [t1(title: 'Local wording')],
      peerTasks: [t1(title: 'Peer wording')],
      localClocks: {'task:t-1': 7},
      peerClocks: {'task:t-1': 7},
    ),
    expectPending: {'task:t-1': 'editedOnBothSides'},
    safetyNote:
        'The plan records the tie: ordering by device id is deterministic, not '
        'causal.',
  ),
  SyncScenario(
    name: 'corrupt-duplicate-schedule-id',
    teaches: 'A repeated schedule id is refused before any planning happens.',
    input: () {
      final clean = library(
        boards: [board('b-1', 'Release')],
        tasks: _baseTasks,
      );
      return ScenarioInput(
        base: ScenarioSnapshot(
          device: _local,
          snapshotId: 'snap-base',
          sequence: 1,
          takenAtMs: epoch,
          library: clean,
        ),
        local: ScenarioSnapshot(
          device: _local,
          snapshotId: 'snap-local',
          sequence: 2,
          takenAtMs: epoch + dayMs,
          library: clean,
        ),
        peer: ScenarioSnapshot(
          device: _peer,
          snapshotId: 'snap-peer',
          sequence: 2,
          takenAtMs: epoch + dayMs,
          library: library(
            boards: [board('b-1', 'Release')],
            tasks: _baseTasks,
            schedule: [
              timeBlock(
                'k-1',
                't-1',
                startAt: epoch,
                endAt: epoch + dayMs,
              ),
              timeBlock(
                'k-1',
                't-1',
                startAt: epoch + dayMs,
                endAt: epoch + 2 * dayMs,
              ),
            ],
          ),
        ),
      );
    },
    expectLoadError: 'Duplicate schedule id k-1',
  ),
  SyncScenario(
    name: 'corrupt-inverted-interval',
    teaches: 'startAt must be before endAt.',
    input: () => _threeWay(
      baseBoards: [board('b-1', 'Release')],
      baseTasks: _baseTasks,
      baseSchedule: [
        timeBlock('k-1', 't-1', startAt: epoch + dayMs, endAt: epoch),
      ],
    ),
    expectLoadError: 'Schedule k-1 has an invalid interval',
  ),
  SyncScenario(
    name: 'corrupt-orphan-schedule',
    teaches: 'A block whose task does not exist is reported, not repaired.',
    input: () => _threeWay(
      baseBoards: [board('b-1', 'Release')],
      baseTasks: _baseTasks,
      peerSchedule: [
        timeBlock(
          'k-7',
          't-missing',
          startAt: epoch,
          endAt: epoch + dayMs,
        ),
      ],
    ),
    expectWarnings: ['peer: Schedule k-7 points at missing task t-missing'],
  ),
];
