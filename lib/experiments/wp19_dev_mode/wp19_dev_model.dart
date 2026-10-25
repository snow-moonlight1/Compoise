/// WP19-R experiment domain: a read-only "development lens" over the product's
/// [Board]/[Task] model, with fields that live only in this session.
///
/// Nothing here imports the Store, persistence, settings or reminder services,
/// and the loaded product tasks are never mutated: completion, phase, blockers
/// and acceptance notes are an overlay keyed by task id.
library;

import 'dart:convert';

import '../../models.dart';

/// Order the prototype assumes a development effort flows through.
enum DevPhase { design, build, verify, ship }

const List<DevPhase> devPhaseOrder = [
  DevPhase.design,
  DevPhase.build,
  DevPhase.verify,
  DevPhase.ship,
];

/// Every mutation the prototype can make, recorded as a reviewable intent
/// rather than an applied write.
enum DevIntentKind {
  complete,
  restore,
  batchComplete,
  phaseSet,
  blockerAdd,
  blockerRemove,
  acceptanceSet,
  fieldsReset,
  taskRemoved,
}

/// One recorded intent. [before] holds the exact field state of every view the
/// intent touched, so undo can put all of them back as one unit.
class DevIntent {
  final int seq;
  final DevIntentKind kind;
  final List<String> taskIds;
  final Map<String, Map<String, Object?>> before;
  final Map<String, Map<String, Object?>> after;
  final int atMs;

  const DevIntent({
    required this.seq,
    required this.kind,
    required this.taskIds,
    required this.before,
    required this.after,
    required this.atMs,
  });

  Map<String, Object?> toJson() => {
    'seq': seq,
    'kind': kind.name,
    'taskIds': taskIds,
    'atMs': atMs,
    'before': before,
    'after': after,
  };
}

/// A product task plus this session's experiment fields.
class DevTaskView {
  final Task source;
  final DevPhase? phase;
  final List<String> blockedBy;
  final String? acceptance;
  final bool done;

  const DevTaskView({
    required this.source,
    required this.phase,
    required this.blockedBy,
    required this.acceptance,
    required this.done,
  });

  String get id => source.id;

  DevTaskView copyWith({
    DevPhase? Function()? phase,
    List<String>? blockedBy,
    String? Function()? acceptance,
    bool? done,
  }) => DevTaskView(
    source: source,
    phase: phase != null ? phase() : this.phase,
    blockedBy: List.unmodifiable(blockedBy ?? this.blockedBy),
    acceptance: acceptance != null ? acceptance() : this.acceptance,
    done: done ?? this.done,
  );
}

/// Why a task can or cannot be started now.
enum DevBlockReason { ready, waitingOnBlockers, inCycle, done }

/// Result of asking "what may I work on right now?".
class DevReadiness {
  final DevBlockReason reason;

  /// Open blockers that resolve to a task in the same project.
  final List<String> waitingOn;

  /// Blocker ids that do not resolve to a task (a data defect, surfaced).
  final List<String> unresolved;

  /// Blocker chain that comes back to the task itself.
  final List<String> cycle;

  const DevReadiness({
    required this.reason,
    this.waitingOn = const [],
    this.unresolved = const [],
    this.cycle = const [],
  });
}

/// Experiment fields supplied when a session is seeded.
class DevFields {
  final DevPhase? phase;
  final List<String> blockedBy;
  final String? acceptance;

  const DevFields({this.phase, this.blockedBy = const [], this.acceptance});
}

class DevExperiment {
  static const String exportSchema = 'wp19r.dev-experiment/1';

  /// One minute per intent: the prototype's clock is synthetic so exports and
  /// tests stay reproducible.
  static const int _stepMs = 60 * 1000;

  final List<Board> boards;
  final Map<String, Task> _sources;
  final Map<String, DevTaskView> _views = {};
  final List<DevIntent> _journal = [];
  int _clockMs;

  DevExperiment({
    required this.boards,
    required List<Task> tasks,
    required Map<String, DevFields> fields,
    required int startClockMs,
  }) : _sources = {for (final task in tasks) task.id: task},
       _clockMs = startClockMs {
    for (final task in tasks) {
      final seeded = fields[task.id];
      _views[task.id] = DevTaskView(
        source: task,
        phase: seeded?.phase,
        blockedBy: seeded?.blockedBy ?? const [],
        acceptance: seeded?.acceptance,
        done: task.completed,
      );
    }
  }

  int get intentCount => _journal.length;

  List<DevIntent> get journal => List.unmodifiable(_journal);

  List<DevTaskView> get tasks => List.unmodifiable(_orderedViews);

  Iterable<DevTaskView> get openTasks => _orderedViews.where((v) => !v.done);

  DevTaskView? view(String id) => _views[id];

  /// Tasks whose session state differs from what was loaded.
  int get touchedTaskCount => _views.values
      .where(
        (view) =>
            view.done != view.source.completed ||
            view.phase != null ||
            view.blockedBy.isNotEmpty ||
            view.acceptance != null,
      )
      .length;

  // ---------------------------------------------------------------- derived

  /// Blocking is only meaningful inside one project: a blocker from another
  /// board is reported as unresolved instead of silently linking projects.
  DevReadiness readiness(DevTaskView view) {
    if (view.done) return const DevReadiness(reason: DevBlockReason.done);
    final waitingOn = <String>[];
    final unresolved = <String>[];
    for (final blockerId in view.blockedBy) {
      final blocker = _views[blockerId];
      if (blocker == null || blocker.source.boardId != view.source.boardId) {
        unresolved.add(blockerId);
        continue;
      }
      if (!blocker.done) waitingOn.add(blockerId);
    }
    if (waitingOn.isEmpty) {
      return DevReadiness(
        reason: DevBlockReason.ready,
        unresolved: List.unmodifiable(unresolved),
      );
    }
    final cycle = _cycleThrough(view.id);
    return DevReadiness(
      reason: cycle == null
          ? DevBlockReason.waitingOnBlockers
          : DevBlockReason.inCycle,
      waitingOn: List.unmodifiable(waitingOn),
      unresolved: List.unmodifiable(unresolved),
      cycle: List.unmodifiable(cycle ?? const []),
    );
  }

  /// Ids of the blocker chain that leads back to [taskId], or null if acyclic.
  List<String>? _cycleThrough(String taskId) {
    final stack = <String>[];
    final deadEnds = <String>{};

    List<String>? walk(String id) {
      if (deadEnds.contains(id)) return null;
      stack.add(id);
      final view = _views[id];
      if (view != null) {
        for (final next in finalBlockerIds(view)) {
          // A finished blocker cannot hold anyone, so a chain that loops
          // through completed work is a wait, not a deadlock.
          if (_views[next]!.done) continue;
          if (next == taskId && stack.length > 1) {
            return List.unmodifiable(stack);
          }
          final found = walk(next);
          if (found != null) return found;
        }
      }
      stack.removeLast();
      deadEnds.add(id);
      return null;
    }

    final found = walk(taskId);
    return found;
  }

  /// Blockers that resolve to a task in the same project.
  List<String> finalBlockerIds(DevTaskView view) => [
    for (final blockerId in view.blockedBy)
      if (_views[blockerId] != null &&
          _views[blockerId]!.source.boardId == view.source.boardId)
        blockerId,
  ];

  /// Open tasks that would become startable if [taskIds] were completed.
  List<String> unlockedBy(List<String> taskIds) {
    final completing = taskIds.toSet();
    final result = <String>[];
    for (final view in openTasks) {
      if (completing.contains(view.id)) continue;
      if (readiness(view).reason != DevBlockReason.waitingOnBlockers) continue;
      final stillOpen = [
        for (final blockerId in finalBlockerIds(view))
          if (!completing.contains(blockerId) && !_views[blockerId]!.done)
            blockerId,
      ];
      if (stillOpen.isEmpty) result.add(view.id);
    }
    return result;
  }

  List<DevTaskView> inPhase(DevPhase? phase, {String? boardId}) => [
    for (final view in _orderedViews)
      if (view.phase == phase &&
          (boardId == null || view.source.boardId == boardId))
        view,
  ];

  /// Phases with at least one task, in flow order; null group last.
  List<DevPhase?> phasesPresent({String? boardId}) {
    final present = <DevPhase?>{};
    for (final view in _orderedViews) {
      if (boardId != null && view.source.boardId != boardId) continue;
      present.add(view.phase);
    }
    return [
      for (final phase in devPhaseOrder)
        if (present.contains(phase)) phase,
      if (present.contains(null)) null,
    ];
  }

  /// Stable order: flow position, then project, then ready/blocked/done, then id.
  List<DevTaskView> get _orderedViews {
    final views = _views.values.toList()..sort(_compare);
    return views;
  }

  int _compare(DevTaskView a, DevTaskView b) {
    final byPhase = _phaseRank(a).compareTo(_phaseRank(b));
    if (byPhase != 0) return byPhase;
    final byBoard = a.source.boardId.compareTo(b.source.boardId);
    if (byBoard != 0) return byBoard;
    final byState = _stateRank(a).compareTo(_stateRank(b));
    if (byState != 0) return byState;
    return a.id.compareTo(b.id);
  }

  int _phaseRank(DevTaskView view) => view.phase == null
      ? devPhaseOrder.length
      : devPhaseOrder.indexOf(view.phase!);

  int _stateRank(DevTaskView view) => switch (readiness(view).reason) {
    DevBlockReason.ready => 0,
    DevBlockReason.inCycle => 1,
    DevBlockReason.waitingOnBlockers => 2,
    DevBlockReason.done => 3,
  };

  // ---------------------------------------------------------------- actions

  bool toggleComplete(String id) {
    final view = _views[id];
    if (view == null) return false;
    final nextState = !view.done;
    _apply(
      kind: nextState ? DevIntentKind.complete : DevIntentKind.restore,
      taskIds: [id],
      mutate: (target) => target.copyWith(done: nextState),
    );
    return true;
  }

  /// Completing several tasks records exactly one intent, so undo reverses the
  /// whole batch instead of leaving a half-applied selection.
  bool completeBatch(Iterable<String> ids) {
    final targets = [
      for (final id in ids)
        if (_views[id] != null && !_views[id]!.done) id,
    ];
    if (targets.isEmpty) return false;
    _apply(
      kind: DevIntentKind.batchComplete,
      taskIds: targets,
      mutate: (target) => target.copyWith(done: true),
    );
    return true;
  }

  bool setPhase(String id, DevPhase? phase) {
    final view = _views[id];
    if (view == null || view.phase == phase) return false;
    _apply(
      kind: DevIntentKind.phaseSet,
      taskIds: [id],
      mutate: (target) => target.copyWith(phase: () => phase),
    );
    return true;
  }

  bool addBlocker(String id, String blockerId) {
    final view = _views[id];
    if (view == null ||
        id == blockerId ||
        _views[blockerId] == null ||
        view.blockedBy.contains(blockerId)) {
      return false;
    }
    _apply(
      kind: DevIntentKind.blockerAdd,
      taskIds: [id],
      mutate: (target) => target.copyWith(
        blockedBy: ([...target.blockedBy, blockerId]..sort()),
      ),
    );
    return true;
  }

  bool removeBlocker(String id, String blockerId) {
    final view = _views[id];
    if (view == null || !view.blockedBy.contains(blockerId)) return false;
    _apply(
      kind: DevIntentKind.blockerRemove,
      taskIds: [id],
      mutate: (target) => target.copyWith(
        blockedBy: target.blockedBy
            .where((existing) => existing != blockerId)
            .toList(),
      ),
    );
    return true;
  }

  bool setAcceptance(String id, String? acceptance) {
    final view = _views[id];
    if (view == null || view.acceptance == acceptance) return false;
    _apply(
      kind: DevIntentKind.acceptanceSet,
      taskIds: [id],
      mutate: (target) => target.copyWith(acceptance: () => acceptance),
    );
    return true;
  }

  /// Drops this session's fields for one task; the product task stays put.
  bool resetFields(String id) {
    final view = _views[id];
    if (view == null) return false;
    if (view.phase == null &&
        view.blockedBy.isEmpty &&
        view.acceptance == null &&
        view.done == view.source.completed) {
      return false;
    }
    _apply(
      kind: DevIntentKind.fieldsReset,
      taskIds: [id],
      mutate: (target) => target.copyWith(
        phase: () => null,
        blockedBy: const [],
        acceptance: () => null,
        done: target.source.completed,
      ),
    );
    return true;
  }

  /// Removes a task from the prototype session only, and with it every pointer
  /// that named it, so no task keeps waiting on something that is gone.
  /// One intent covers all of it; undo restores the whole set.
  bool removeTask(String id) {
    final view = _views[id];
    if (view == null) return false;
    _clockMs += _stepMs;
    final before = <String, Map<String, Object?>>{
      for (final affected in _views.values)
        if (affected.id == id || affected.blockedBy.contains(id))
          affected.id: _snapshot(affected),
    };
    final after = <String, Map<String, Object?>>{
      for (final affectedId in before.keys)
        if (affectedId != id)
          affectedId: _snapshot(
            _views[affectedId]!.copyWith(
              blockedBy: _views[affectedId]!.blockedBy
                  .where((existing) => existing != id)
                  .toList(),
            ),
          ),
    };
    _views.remove(id);
    for (final entry in after.entries) {
      _views[entry.key] = _restore(_sources[entry.key]!, entry.value);
    }
    _journal.add(
      DevIntent(
        seq: _journal.length + 1,
        kind: DevIntentKind.taskRemoved,
        taskIds: [id],
        before: before,
        after: after,
        atMs: _clockMs,
      ),
    );
    return true;
  }

  bool undoLast() {
    if (_journal.isEmpty) return false;
    final intent = _journal.removeLast();
    _clockMs += _stepMs;
    for (final entry in intent.before.entries) {
      final source = _sources[entry.key];
      if (source == null) continue;
      _views[entry.key] = _restore(source, entry.value);
    }
    return true;
  }

  // ----------------------------------------------------------------- export

  /// Advances the synthetic clock once and records what changed, so [undoLast]
  /// can restore every touched view as a single unit.
  void _apply({
    required DevIntentKind kind,
    required List<String> taskIds,
    required DevTaskView Function(DevTaskView) mutate,
  }) {
    _clockMs += _stepMs;
    final before = <String, Map<String, Object?>>{};
    final after = <String, Map<String, Object?>>{};
    for (final id in taskIds) {
      final current = _views[id];
      if (current == null) continue;
      before[id] = _snapshot(current);
      final next = mutate(current);
      _views[id] = next;
      after[id] = _snapshot(next);
    }
    _journal.add(
      DevIntent(
        seq: _journal.length + 1,
        kind: kind,
        taskIds: taskIds,
        before: before,
        after: after,
        atMs: _clockMs,
      ),
    );
  }

  Map<String, Object?> exportState({String? boardId}) {
    final views = [
      for (final view in _orderedViews)
        if (boardId == null || view.source.boardId == boardId) view,
    ];
    final seenBoardIds = {for (final view in views) view.source.boardId};
    return {
      'schema': exportSchema,
      'storage': 'memory-only',
      'clockMs': _clockMs,
      'projects': [
        for (final board in boards)
          if (seenBoardIds.contains(board.id))
            {
              'id': board.id,
              'name': board.name,
              'openTasks': views
                  .where((view) =>
                      view.source.boardId == board.id && !view.done)
                  .length,
            },
      ],
      'tasks': [for (final view in views) _exportTask(view)],
      'intents': [for (final intent in _journal) intent.toJson()],
    };
  }

  String exportJson({String? boardId, bool indent = true}) {
    final encoder = indent
        ? const JsonEncoder.withIndent('  ')
        : const JsonEncoder();
    return encoder.convert(exportState(boardId: boardId));
  }

  Map<String, Object?> _snapshot(DevTaskView view) => {
    'phase': view.phase?.name,
    'blockedBy': view.blockedBy,
    'acceptance': view.acceptance,
    'done': view.done,
  };

  DevTaskView _restore(Task source, Map<String, Object?> data) {
    final phaseName = data['phase'] as String?;
    return DevTaskView(
      source: source,
      phase: phaseName == null
          ? null
          : devPhaseOrder.firstWhere(
              (candidate) => candidate.name == phaseName,
            ),
      blockedBy: (data['blockedBy'] as List?)?.cast<String>() ?? const [],
      acceptance: data['acceptance'] as String?,
      done: (data['done'] as bool?) ?? false,
    );
  }

  Map<String, Object?> _exportTask(DevTaskView view) {
    final readiness = this.readiness(view);
    final source = view.source;
    return {
      'id': view.id,
      'project': source.boardId,
      'title': source.title,
      'quadrant': source.quadrant,
      'tags': source.tags,
      'sourceCompleted': source.completed,
      'phase': view.phase?.name,
      'done': view.done,
      'acceptance': view.acceptance,
      'blockedBy': view.blockedBy,
      'ready': readiness.reason == DevBlockReason.ready,
      'reason': readiness.reason.name,
      'waitingOn': readiness.waitingOn,
      'unresolvedBlockers': readiness.unresolved,
      'cycle': readiness.cycle,
      'hasSubtasks': source.hasSubtasks,
      'deadline': source.deadline,
      'plannedDate': source.plannedDate,
    };
  }
}
