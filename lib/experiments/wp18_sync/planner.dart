/// Three-way conflict classification and resolution policies.
///
/// Classification is policy-free: it describes what the two devices did against
/// their common baseline. The policy pass then decides how much of that the
/// engine may apply without a human, and the reference pass withholds anything
/// that would leave a dangling board or task link. Splitting the passes is what
/// lets the simulator run the same library under different choices.
library;

import 'digest.dart';
import 'plan.dart';
import 'snapshot.dart';

/// What the engine may conclude from a record that is missing.
enum PresenceModel {
  /// Snapshots carry tombstones, so an absence is a stated deletion.
  tombstoneAware,

  /// A plain v3 backup: a missing record is only missing. Today's manual
  /// export cannot tell "the user deleted this" from "this peer never received
  /// it", so no deletion is ever inferred from it.
  presenceOnly,
}

enum ResolutionPolicy {
  /// Only single-sided changes and provably disjoint field merges are applied.
  holdPending,

  /// A reviewable conflict takes this device's version. A deletion still wins
  /// over an edit unless resurrection is explicitly allowed.
  preferLocal,

  /// A reviewable conflict takes the peer's version, same deletion guard.
  preferPeer,

  /// Merge field by field whenever no field was touched twice, and otherwise
  /// fall back to the local version.
  fieldwiseAuto,

  /// Nothing is applied without an override entry.
  manual,
}

class SafetyGuards {
  const SafetyGuards({
    this.allowResurrection = false,
    this.allowUnknownFields = false,
    this.requireReferenceIntegrity = true,
  });

  /// Writing back a record the user deleted. Off by default, and even when a
  /// policy turns it on the plan keeps an explicit resurrection entry.
  final bool allowResurrection;

  /// Carry fields the reader does not understand into the merged library.
  final bool allowUnknownFields;

  /// Never emit a record whose board or parent task is not in the result.
  final bool requireReferenceIntegrity;

  static const standard = SafetyGuards();
}

enum Override { takeLocal, takePeer, drop, restore, fieldwise }

class ConflictPlanner {
  ConflictPlanner({
    required this.base,
    required this.local,
    required this.peer,
    this.presence = PresenceModel.tombstoneAware,
    this.policy = ResolutionPolicy.holdPending,
    this.guards = SafetyGuards.standard,
    this.overrides = const {},
  });

  final SyncSnapshot base;
  final SyncSnapshot local;
  final SyncSnapshot peer;
  final PresenceModel presence;
  final ResolutionPolicy policy;
  final SafetyGuards guards;
  final Map<String, Override> overrides;

  final Map<String, SyncDecision> _decisions = <String, SyncDecision>{};
  List<String> _allKeys = const [];

  SyncPlan build() {
    _decisions.clear();
    _allKeys = <String>{
      ...base.records.keys,
      ...local.records.keys,
      ...peer.records.keys,
      for (final tombstone in local.tombstones) tombstone.key,
      for (final tombstone in peer.tombstones) tombstone.key,
    }.toList()..sort();
    for (final key in _allKeys) {
      _classify(key);
    }
    // Every pass that can create or re-shape a conflict runs before the policy
    // gets to choose, so a policy cannot miss a late-arriving item.
    _positionPass();
    _duplicatePass();
    _reparentPass();
    _configDecisions();
    for (final decision in _decisions.values.toList()) {
      _applyPolicy(decision);
    }
    if (guards.requireReferenceIntegrity) {
      _dependentsPass();
      _referencePass();
    }
    // Overrides are the human speaking last, after every automatic pass.
    _applyOverrides();
    final ordered = _decisions.values.toList()
      ..sort((a, b) {
        final byStatus = _rank(a).compareTo(_rank(b));
        return byStatus != 0 ? byStatus : a.key.compareTo(b.key);
      });
    return SyncPlan(
      base: base,
      left: local,
      right: peer,
      policy: policy.name,
      presenceModel: presence.name,
      decisions: ordered,
      warnings: _warnings(),
    );
  }

  int _rank(SyncDecision decision) => switch (decision.status) {
    DecisionStatus.pending => 0,
    DecisionStatus.blocked => 1,
    DecisionStatus.auto => 2,
  };

  List<String> _warnings() => [
    'Per-record clocks are per-device counters. Equal clocks do not mean '
        'equal time, and neither value is a global revision or a causal proof.',
    if (presence == PresenceModel.presenceOnly)
      'Presence-only input: absence is not deletion evidence, so a one-sided '
          'disappearance always stays pending.',
    for (final finding in base.referenceFindings) 'baseline: $finding',
    for (final finding in local.referenceFindings) 'local: $finding',
    for (final finding in peer.referenceFindings) 'peer: $finding',
    for (final name in <String>{
      ...local.unknownTopLevel,
      ...peer.unknownTopLevel,
    })
      'Unknown top-level field "$name" is not transported.',
  ];

  // ---------------------------------------------------------------- classify

  void _classify(String key) {
    final b = base.records[key];
    final l = local.records[key];
    final r = peer.records[key];
    final lt = local.tombstoneFor(key);
    final rt = peer.tombstoneFor(key);

    if (l != null && r != null) {
      if (_hasUnknown(l) || _hasUnknown(r) || _hasUnknown(b)) {
        _unknownField(key, b, l, r);
        return;
      }
      if (l.digest == r.digest) {
        if (b == null) {
          _put(
            SyncDecision(
              key: key,
              kind: ConflictKind.none,
              action: DecisionAction.add,
              status: DecisionStatus.auto,
              reason: 'sameIdCreatedOnBothSidesWithSameContent',
              leftDigest: l.digest,
              rightDigest: r.digest,
              fields: l.fields,
            ),
          );
        } else if (b.digest != l.digest) {
          _singleSidedOrFork(key, b, l, r, bothEqual: true);
        }
        return;
      }
      if (b == null) {
        _fork(key, null, l, r, createdOnBothSides: true);
      } else {
        _singleSidedOrFork(key, b, l, r, bothEqual: false);
      }
      return;
    }

    // At most one side still holds the record.
    if (lt != null && rt != null) {
      _delete(key, b, reason: 'deletedOnBothSides');
      return;
    }
    if (lt != null && r != null) {
      if (b != null && b.digest == r.digest) {
        _delete(key, b, reason: 'localDeletedPeerUnchanged');
      } else {
        _put(
          _deleteEdit(
            key,
            base: b,
            survivor: r,
            deletedBy: 'local',
            tombstone: lt,
          ),
        );
      }
      return;
    }
    if (rt != null && l != null) {
      if (b != null && b.digest == l.digest) {
        _delete(key, b, reason: 'peerDeletedLocalUnchanged');
      } else {
        _put(
          _deleteEdit(
            key,
            base: b,
            survivor: l,
            deletedBy: 'peer',
            tombstone: rt,
          ),
        );
      }
      return;
    }
    if (lt != null && r == null) {
      // Nothing to apply now; the tombstone is what keeps the record from
      // coming back when another device still holds it.
      if (b != null) _delete(key, b, reason: 'localDeletedPeerNeverHadIt');
      return;
    }
    if (rt != null && l == null) {
      if (b != null) _delete(key, b, reason: 'peerDeletedLocalNeverHadIt');
      return;
    }
    if (l == null && r == null) {
      if (b == null) return;
      _put(
        SyncDecision(
          key: key,
          kind: ConflictKind.presenceAmbiguity,
          action: DecisionAction.none,
          status: DecisionStatus.pending,
          reason: 'goneOnBothSidesWithoutEvidence',
          baseDigest: b.digest,
          notes: [
            'Neither snapshot carries the record or a tombstone for it, so the '
                'merge cannot say who removed it.',
          ],
        ),
      );
      return;
    }
    final survivor = l ?? r;
    if (survivor == null) return;
    if (survivor.unknownFields.isNotEmpty) {
      _unknownField(key, b, l, r);
      return;
    }
    final fromLocal = l != null;
    if (b == null) {
      _put(
        SyncDecision(
          key: key,
          kind: ConflictKind.none,
          action: DecisionAction.add,
          status: DecisionStatus.auto,
          reason: fromLocal ? 'addedOnLocalOnly' : 'addedOnPeerOnly',
          leftDigest: l?.digest,
          rightDigest: r?.digest,
          fields: survivor.fields,
          leftClock: local.clockFor(key),
          rightClock: peer.clockFor(key),
          leftOrigin: local.originFor(key),
          rightOrigin: peer.originFor(key),
        ),
      );
      return;
    }
    if (survivor.digest == b.digest) {
      // One side dropped an unedited record with no deletion evidence.
      _put(_presenceAmbiguous(key, b, survivorOnLocal: fromLocal));
      return;
    }
    // The surviving record was edited; the other side simply lost it.
    _put(
      SyncDecision(
        key: key,
        kind: ConflictKind.presenceAmbiguity,
        action: DecisionAction.update,
        status: DecisionStatus.pending,
        reason: fromLocal
            ? 'onlyLocalEditedPeerLostIt'
            : 'onlyPeerEditedLocalLostIt',
        baseDigest: b.digest,
        leftDigest: l?.digest,
        rightDigest: r?.digest,
        fields: survivor.fields,
        recommendation:
            'keep the edited copy unless the loss is confirmed as a deletion',
      ),
    );
  }

  void _put(SyncDecision decision) => _decisions[decision.key] = decision;

  void _delete(String key, SyncRecord? b, {required String reason}) {
    _put(
      SyncDecision(
        key: key,
        kind: ConflictKind.none,
        action: DecisionAction.delete,
        status: DecisionStatus.auto,
        reason: reason,
        baseDigest: b?.digest,
      ),
    );
  }

  SyncDecision _deleteEdit(
    String key, {
    required SyncRecord? base,
    required SyncRecord survivor,
    required String deletedBy,
    required Tombstone tombstone,
  }) => SyncDecision(
    key: key,
    kind: ConflictKind.deleteEdit,
    action: DecisionAction.none,
    status: DecisionStatus.pending,
    reason: deletedBy == 'local'
        ? 'localDeletedWhilePeerEdited'
        : 'peerDeletedWhileLocalEdited',
    baseDigest: base?.digest,
    leftDigest: deletedBy == 'local' ? tombstone.lastDigest : survivor.digest,
    rightDigest: deletedBy == 'local' ? survivor.digest : tombstone.lastDigest,
    fields: survivor.fields,
    recommendation: deletedBy == 'local'
        ? 'the local deletion stands unless the user restores by hand'
        : 'restoring the peer edit needs an explicit confirmation',
    notes: [
      '${deletedBy == "local" ? "Local" : "Peer"} deleted at '
          '${instantLabel(tombstone.deletedAtMs)} with digest '
          '${tombstone.lastDigest}.',
      'Resurrecting a user deletion is never automatic.',
    ],
  );

  SyncDecision _presenceAmbiguous(
    String key,
    SyncRecord b, {
    required bool survivorOnLocal,
  }) => SyncDecision(
    key: key,
    kind: ConflictKind.presenceAmbiguity,
    action: DecisionAction.none,
    status: DecisionStatus.pending,
    reason: presence == PresenceModel.tombstoneAware
        ? 'missingWithoutEvidence'
        : 'presenceOnlyCannotTellDeletion',
    baseDigest: b.digest,
    leftDigest: survivorOnLocal ? b.digest : null,
    rightDigest: survivorOnLocal ? null : b.digest,
    recommendation: survivorOnLocal
        ? 'local copy stays; the peer loss is not a proven deletion'
        : 'local stays empty; the peer copy is not a proven deletion either',
    notes: [
      'Absence without a tombstone is not a deletion statement.',
    ],
  );

  /// One record held by both devices. A device that still matches the baseline
  /// said nothing, so the other device's change is a single-sided update; a
  /// field the reader does not recognize blocks even that.
  void _singleSidedOrFork(
    String key,
    SyncRecord b,
    SyncRecord l,
    SyncRecord r, {
    required bool bothEqual,
  }) {
    if (bothEqual) {
      _put(
        SyncDecision(
          key: key,
          kind: ConflictKind.none,
          action: DecisionAction.update,
          status: DecisionStatus.auto,
          reason: 'bothSidesSameChange',
          baseDigest: b.digest,
          leftDigest: l.digest,
          rightDigest: r.digest,
          fields: l.fields,
          leftClock: local.clockFor(key),
          rightClock: peer.clockFor(key),
        ),
      );
      return;
    }
    final leftUnchanged = l.digest == b.digest;
    final rightUnchanged = r.digest == b.digest;
    if (leftUnchanged || rightUnchanged) {
      final mover = leftUnchanged ? r : l;
      if (mover.unknownFields.isNotEmpty ||
          (leftUnchanged && r.unknownFields.isNotEmpty)) {
        _unknownField(key, b, l, r);
        return;
      }
      _put(
        SyncDecision(
          key: key,
          kind: ConflictKind.none,
          action: DecisionAction.update,
          status: DecisionStatus.auto,
          reason: leftUnchanged ? 'onlyPeerChanged' : 'onlyLocalChanged',
          baseDigest: b.digest,
          leftDigest: l.digest,
          rightDigest: r.digest,
          fields: mover.fields,
          leftClock: local.clockFor(key),
          rightClock: peer.clockFor(key),
          leftOrigin: local.originFor(key),
          rightOrigin: peer.originFor(key),
        ),
      );
      return;
    }
    _fork(key, b, l, r, createdOnBothSides: false);
  }

  bool _hasUnknown(SyncRecord? record) =>
      record != null && record.unknownValues.isNotEmpty;

  void _unknownField(String key, SyncRecord? b, SyncRecord? l, SyncRecord? r) {
    final names = <String>{
      ...?b?.unknownFields,
      ...?l?.unknownFields,
      ...?r?.unknownFields,
    }.toList()
      ..sort();
    _put(
      SyncDecision(
        key: key,
        kind: ConflictKind.unknownField,
        action: DecisionAction.none,
        status: DecisionStatus.pending,
        reason: 'unrecognizedFieldsPresent',
        baseDigest: b?.digest,
        leftDigest: l?.digest,
        rightDigest: r?.digest,
        fields: (l ?? r)?.fields,
        recommendation:
            'say what ${names.join(', ')} means before merging this record',
        notes: ['Unrecognized fields: ${names.join(', ')}.'],
      ),
    );
  }

  void _fork(
    String key,
    SyncRecord? b,
    SyncRecord l,
    SyncRecord r, {
    required bool createdOnBothSides,
  }) {
    if (l.unknownFields.isNotEmpty ||
        r.unknownFields.isNotEmpty ||
        (b?.unknownFields.isNotEmpty ?? false)) {
      _unknownField(key, b, l, r);
      return;
    }
    final diffs = _fieldDiffs(b, l, r);
    final completion = _bothCompleted(b, l, r);
    final singleSided = diffs.isNotEmpty &&
        diffs.every((d) => d.autoMergeable) &&
        completion == null;
    final kindChanged = _kindChanged(b, l, r);
    if (diffs.isNotEmpty && diffs.every((d) => d.sameCivilDay)) {
      // Every difference is the same local civil day seen from two zones, so
      // there is no user decision to make. Keep the local representation.
      _put(
        SyncDecision(
          key: key,
          kind: ConflictKind.civilDayFalseConflict,
          action: DecisionAction.update,
          status: DecisionStatus.auto,
          reason: 'sameCivilDayDifferentZone',
          baseDigest: b?.digest,
          leftDigest: l.digest,
          rightDigest: r.digest,
          diffs: diffs,
          fields: l.fields,
          notes: [
            'planned day and deadline are local civil midnights '
                '(BACKUP_FORMAT.md): ${local.device.label} at '
                '${local.device.zoneOffsetMinutes >= 0 ? "+" : ""}'
                '${local.device.zoneOffsetMinutes}min and ${peer.device.label} '
                'at '
                '${peer.device.zoneOffsetMinutes >= 0 ? "+" : ""}'
                '${peer.device.zoneOffsetMinutes}min can write different epoch '
                'values for the same day.',
          ],
        ),
      );
      return;
    }
    _put(
      SyncDecision(
        key: key,
        kind: kindChanged
            ? ConflictKind.scheduleKindChanged
            : completion != null
            ? ConflictKind.concurrentCompletion
            : ConflictKind.sameIdFork,
        action: DecisionAction.none,
        status: DecisionStatus.pending,
        reason: createdOnBothSides
            ? 'sameIdCreatedDifferentlyOnBothSides'
            : 'editedOnBothSides',
        baseDigest: b?.digest,
        leftDigest: l.digest,
        rightDigest: r.digest,
        leftClock: local.clockFor(key),
        rightClock: peer.clockFor(key),
        leftOrigin: local.originFor(key),
        rightOrigin: peer.originFor(key),
        diffs: diffs,
        fields: _mergedBody(l, r, diffs),
        recommendation: singleSided
            ? 'fieldwise merge available: no field was touched twice'
            : (completion ??
                  'at least one field was edited on both sides: pick a version'),
        notes: [
          if (completion != null) completion,
          if (local.clockFor(key) == peer.clockFor(key))
            'Equal device counters: any ordering in this plan is by device id, '
                'which is deterministic but not a claim about time.',
          'leftClock=${local.clockFor(key)} peerClock=${peer.clockFor(key)}',
        ],
      ),
    );
  }

  /// True when the two sides disagree about what the record is.
  bool _kindChanged(SyncRecord? b, SyncRecord l, SyncRecord r) =>
      l.key.startsWith('schedule:') && l.fields['kind'] != r.fields['kind'];

  /// The local body with every single-sided change applied. Fields both sides
  /// moved stay at the local value and are marked by [FieldDiff.autoMergeable],
  /// so a merged record is always a complete record, never a field fragment.
  Map<String, dynamic> _mergedBody(
    SyncRecord l,
    SyncRecord r,
    List<FieldDiff> diffs,
  ) {
    final body = <String, dynamic>{...l.fields};
    for (final diff in diffs) {
      if (!diff.autoMergeable) continue;
      if (diff.sameCivilDay) continue;
      if (canonicalJson(body[diff.field]) == canonicalJson(diff.merged)) {
        continue;
      }
      // Only take the peer value when the local side left that field alone.
      if (canonicalJson(diff.left) == canonicalJson(diff.base)) {
        body[diff.field] = diff.merged;
      } else if (diff.merged != null) {
        body[diff.field] = diff.merged;
      }
    }
    return body;
  }

  String? _bothCompleted(SyncRecord? b, SyncRecord l, SyncRecord r) {
    bool done(SyncRecord? record) => record?.fields['completed'] == true;
    if (b == null || done(b) || !done(l) || !done(r)) return null;
    return 'Both sides completed this task: local at '
        '${_stamp(l.fields['completedAt'])}, peer at '
        '${_stamp(r.fields['completedAt'])}. Neither is provably first.';
  }

  static String _stamp(Object? value) =>
      value is int ? instantLabel(value) : 'unrecorded';

  List<FieldDiff> _fieldDiffs(SyncRecord? b, SyncRecord l, SyncRecord r) {
    final names = <String>{
      ...?b?.fields.keys,
      ...l.fields.keys,
      ...r.fields.keys,
    }.toList()
      ..sort();
    final out = <FieldDiff>[];
    for (final field in names) {
      final baseValue = b?.fields[field];
      final leftValue = l.fields[field];
      final rightValue = r.fields[field];
      final leftChanged = !_equal(baseValue, leftValue);
      final rightChanged = !_equal(baseValue, rightValue);
      if (!leftChanged && !rightChanged) continue;
      if (!_equal(leftValue, rightValue) &&
          leftChanged &&
          rightChanged &&
          _isCivilDay(field, b, l, r) &&
          baseValue is int &&
          leftValue is int &&
          rightValue is int &&
          isSameCivilDay(
            leftMs: leftValue,
            rightMs: rightValue,
            leftZoneOffsetMinutes: local.device.zoneOffsetMinutes,
            rightZoneOffsetMinutes: peer.device.zoneOffsetMinutes,
          )) {
        out.add(
          FieldDiff(
            field: field,
            base: baseValue,
            left: leftValue,
            right: rightValue,
            sameCivilDay: true,
            merged: leftValue,
            autoMergeable: true,
          ),
        );
        continue;
      }
      out.add(
        FieldDiff(
          field: field,
          base: baseValue,
          left: leftValue,
          right: rightValue,
          merged: leftChanged && !_equal(rightValue, baseValue)
              ? null
              : (leftChanged ? leftValue : rightValue),
          autoMergeable: _equal(rightValue, baseValue) ||
              _equal(leftValue, baseValue) ||
              _equal(leftValue, rightValue),
        ),
      );
    }
    return out;
  }

  static bool _equal(Object? a, Object? b) =>
      canonicalJson(a) == canonicalJson(b);

  bool _isCivilDay(String field, SyncRecord? b, SyncRecord l, SyncRecord r) =>
      civilDayTaskFields.contains(field) && l.key.startsWith('task:');

  // -------------------------------------------------------------- other passes

  /// Positions are not in the compared content, so an order-only change needs
  /// its own look. Subtask order is user-visible in v3.
  void _positionPass() {
    for (final key in _allKeys) {
      if (!key.startsWith('subtask:')) continue;
      final b = base.records[key];
      final l = local.records[key];
      final r = peer.records[key];
      if (b == null || l == null || r == null) continue;
      if (!_equal(l.digest, r.digest)) continue;
      final existing = _decisions[key];
      if (existing != null && existing.action != DecisionAction.update) continue;
      final leftMoved = l.position != b.position;
      final rightMoved = r.position != b.position;
      if (!leftMoved && !rightMoved) continue;
      if (leftMoved && rightMoved && l.position != r.position) {
        _put(
          SyncDecision(
            key: key,
            kind: ConflictKind.orderingDivergence,
            action: DecisionAction.none,
            status: DecisionStatus.pending,
            reason: 'reorderedOnBothSides',
            baseDigest: b.digest,
            leftDigest: l.digest,
            rightDigest: r.digest,
            fields: l.fields,
            recommendation: 'content matches, only the order differs: pick one',
            notes: [
              'local position ${l.position}, peer position ${r.position}',
            ],
          ),
        );
      } else {
        _put(
          SyncDecision(
            key: key,
            kind: ConflictKind.orderingDivergence,
            action: DecisionAction.update,
            status: DecisionStatus.auto,
            reason: leftMoved ? 'onlyLocalReordered' : 'onlyPeerReordered',
            baseDigest: b.digest,
            leftDigest: l.digest,
            rightDigest: r.digest,
            fields: l.fields,
            notes: ['order taken from ${leftMoved ? "local" : "peer"}'],
          ),
        );
      }
    }
  }

  /// Equivalent content created under different ids on the two devices.
  void _duplicatePass() {
    final bySignature = <String, List<SyncDecision>>{};
    for (final decision in _decisions.values) {
      if (decision.reason != 'addedOnLocalOnly' &&
          decision.reason != 'addedOnPeerOnly') {
        continue;
      }
      final record = local.records[decision.key] ?? peer.records[decision.key];
      final signature = record == null
          ? null
          : _dedupeSignature(decision.key, record);
      if (signature == null) continue;
      (bySignature[signature] ??= []).add(decision);
    }
    for (final group in bySignature.values) {
      final localAdds = [
        for (final d in group)
          if (d.reason == 'addedOnLocalOnly') d,
      ];
      final peerAdds = [
        for (final d in group)
          if (d.reason == 'addedOnPeerOnly') d,
      ];
      if (localAdds.isEmpty || peerAdds.isEmpty) continue;
      final kept = (localAdds.first);
      for (final duplicate in peerAdds) {
        duplicate.kind = ConflictKind.duplicateContent;
        duplicate.status = DecisionStatus.pending;
        duplicate.action = DecisionAction.none;
        duplicate.reason = 'sameContentUnderDifferentId';
        duplicate.recommendation =
            'keep ${kept.key} and drop ${duplicate.key}, or keep both';
        duplicate.notes = [
          ...duplicate.notes,
          'Deduping is a product decision: a schedule on either device may '
              'already point at one of the two ids.',
        ];
      }
    }
  }

  String? _dedupeSignature(String key, SyncRecord record) {
    final fields = record.fields;
    if (key.startsWith('task:')) {
      return contentDigest({
        'title': fields['title'],
        'boardId': fields['boardId'],
        'quadrant': fields['quadrant'],
        'deadline': fields['deadline'],
        'isLongTerm': fields['isLongTerm'],
      });
    }
    if (key.startsWith('board:')) {
      return contentDigest({'name': fields['name']});
    }
    if (key.startsWith('schedule:')) {
      return contentDigest({
        'kind': fields['kind'],
        'taskId': fields['taskId'],
        'boardId': fields['boardId'],
        'title': fields['title'],
        'startAt': fields['startAt'],
        'endAt': fields['endAt'],
      });
    }
    return null;
  }

  /// A child that left one parent and arrived under another shows up as a
  /// delete plus an add. Read literally that duplicates the child.
  void _reparentPass() {
    final deletes = [
      for (final d in _decisions.values)
        if (d.action == DecisionAction.delete && d.key.startsWith('subtask:')) d,
    ];
    final adds = [
      for (final d in _decisions.values)
        if (d.reason == 'addedOnPeerOnly' && d.key.startsWith('subtask:')) d,
    ];
    for (final deletion in deletes) {
      final moved = _matchBySignature(deletion.key, adds);
      if (moved == null) continue;
      deletion.kind = ConflictKind.reparented;
      deletion.status = DecisionStatus.pending;
      deletion.reason = 'subtaskMayHaveMovedParent';
      deletion.blockedBy = [moved.key];
      deletion.recommendation =
          'treat as one move ${deletion.key} -> ${moved.key}';
      moved.kind = ConflictKind.reparented;
      moved.status = DecisionStatus.pending;
      moved.reason = 'subtaskMayHaveMovedParent';
      moved.blockedBy = [deletion.key];
      moved.recommendation =
          'treat as one move ${deletion.key} -> ${moved.key}';
    }
  }

  SyncDecision? _matchBySignature(String key, List<SyncDecision> candidates) {
    final record = base.records[key] ?? local.records[key];
    if (record == null) return null;
    final signature = contentDigest({
      for (final entry in record.fields.entries)
        if (entry.key != 'position') entry.key: entry.value,
    });
    for (final candidate in candidates) {
      final other = peer.records[candidate.key];
      if (other == null) continue;
      final otherSignature = contentDigest({
        for (final entry in other.fields.entries)
          if (entry.key != 'position') entry.key: entry.value,
      });
      if (otherSignature == signature) return candidate;
    }
    return null;
  }

  void _configDecisions() {
    final settingsL = local.settings;
    final settingsR = peer.settings;
    if (settingsL != null &&
        settingsR != null &&
        !_equal(settingsL, settingsR)) {
      _put(
        SyncDecision(
          key: SyncKey.config('settings'),
          kind: ConflictKind.configDivergence,
          action: DecisionAction.none,
          status: DecisionStatus.pending,
          reason: 'settingsDiffer',
          leftDigest: contentDigest(settingsL),
          rightDigest: contentDigest(settingsR),
          configSlot: 'settings',
          localValue: settingsL,
          peerValue: settingsR,
          configValue: settingsL,
          recommendation: 'settings are not merged field by field: pick one',
        ),
      );
    }
    final aiL = local.aiConfig;
    final aiR = peer.aiConfig;
    if (aiL != null && aiR != null && !_equal(aiL, aiR)) {
      _put(
        SyncDecision(
          key: SyncKey.config('ai'),
          kind: ConflictKind.configDivergence,
          action: DecisionAction.none,
          status: DecisionStatus.pending,
          reason: 'aiConfigDiffer',
          leftDigest: contentDigest(aiL),
          rightDigest: contentDigest(aiR),
          recommendation: 'review endpoints before transporting any config',
        ),
      );
    }
    if (local.carriesCredential || peer.carriesCredential) {
      _put(
        SyncDecision(
          key: SyncKey.config('credential'),
          kind: ConflictKind.credentialBlocked,
          action: DecisionAction.none,
          status: DecisionStatus.blocked,
          reason: 'credentialNeverTransported',
          recommendation: 're-enter the key on the target device',
          notes: [
            'The reader dropped aiConfig.customApiKey, and a default backup '
                'never writes it. No policy in this package moves a credential.',
          ],
        ),
      );
    }
  }

  // ------------------------------------------------------------- policy pass

  void _applyPolicy(SyncDecision decision) {
    if (decision.status != DecisionStatus.pending) return;
    switch (policy) {
      case ResolutionPolicy.manual:
        return;
      case ResolutionPolicy.holdPending:
        if (decision.kind == ConflictKind.sameIdFork &&
            decision.fields != null &&
            decision.diffs.isNotEmpty &&
            decision.diffs.every((d) => d.autoMergeable)) {
          _acceptFieldwise(decision);
        }
      case ResolutionPolicy.fieldwiseAuto:
        if (decision.kind == ConflictKind.sameIdFork &&
            decision.fields != null &&
            decision.diffs.isNotEmpty &&
            decision.diffs.every((d) => d.autoMergeable)) {
          _acceptFieldwise(decision);
        } else {
          _prefer(decision, localSide: true);
        }
      case ResolutionPolicy.preferLocal:
        _prefer(decision, localSide: true);
      case ResolutionPolicy.preferPeer:
        _prefer(decision, localSide: false);
    }
  }

  void _acceptFieldwise(SyncDecision decision) {
    decision.record('policy ${policy.name} merged disjoint fields');
    decision.kind = ConflictKind.none;
    decision.status = DecisionStatus.auto;
    decision.action = DecisionAction.update;
    decision.reason = 'fieldwiseMergedNoFieldTouchedTwice';
    decision.recommendation = null;
  }

  void _prefer(SyncDecision decision, {required bool localSide}) {
    if (_neverAuto.contains(decision.kind)) return;
    if (decision.kind == ConflictKind.deleteEdit) {
      if (!guards.allowResurrection) {
        decision.notes = [
          ...decision.notes,
          'Withheld under ${policy.name}: applying it would write back a '
              'record the other device deleted. Set allowResurrection or '
              'confirm the restore by hand.',
        ];
        return;
      }
      decision.record('explicit resurrection allowed by guard');
      decision.status = DecisionStatus.auto;
      decision.action = localSide
          ? DecisionAction.update
          : DecisionAction.delete;
      decision.reason = localSide
          ? 'resurrectionConfirmedByPolicy'
          : 'deletionWinsByPolicy';
      decision.notes = [
        ...decision.notes,
        'Explicit ${localSide ? "restore" : "deletion"} under ${policy.name}.',
      ];
      return;
    }
    if (decision.kind == ConflictKind.unknownField) {
      if (guards.allowUnknownFields) {
        decision.record('unknown fields passed through by guard');
        decision.status = DecisionStatus.auto;
        decision.action = DecisionAction.update;
        decision.reason = 'unknownFieldsPassedThrough';
      }
      return;
    }
    if (decision.kind == ConflictKind.configDivergence) {
      decision.record('policy picked one settings version');
      decision.status = DecisionStatus.auto;
      decision.action = DecisionAction.update;
      decision.configValue = localSide ? decision.localValue : decision.peerValue;
      decision.reason = localSide ? 'localWinsByPolicy' : 'peerWinsByPolicy';
      return;
    }
    final chosen = (localSide ? local : peer).records[decision.key];
    if (chosen == null) return;
    decision.record('policy chose the ${localSide ? "local" : "peer"} version');
    decision.fields = chosen.fields;
    decision.status = DecisionStatus.auto;
    decision.action = DecisionAction.update;
    decision.reason = localSide ? 'localWinsByPolicy' : 'peerWinsByPolicy';
  }

  /// Conflicts a version-picking policy must never resolve on its own.
  static const _neverAuto = {
    ConflictKind.presenceAmbiguity,
    ConflictKind.credentialBlocked,
    ConflictKind.danglingReference,
    ConflictKind.duplicateContent,
    ConflictKind.reparented,
    ConflictKind.scheduleKindChanged,
    ConflictKind.civilDayFalseConflict,
  };

  /// A deletion that would leave a surviving task, subtask or schedule behind is
  /// withheld. The backup contract commits a task together with its records
  /// (docs/DATA_COMPATIBILITY.md), so half of that batch must not be applied.
  void _dependentsPass() {
    final survivors = <String>{...local.records.keys};
    for (final entry in _decisions.entries) {
      final decision = entry.value;
      if (decision.status != DecisionStatus.auto) continue;
      if (decision.action == DecisionAction.delete) {
        survivors.remove(entry.key);
      } else if (decision.action == DecisionAction.add ||
          decision.action == DecisionAction.update) {
        survivors.add(entry.key);
      }
    }
    for (final entry in _decisions.entries.toList()) {
      final decision = entry.value;
      if (decision.status != DecisionStatus.auto) continue;
      if (decision.action != DecisionAction.delete) continue;
      final target = entry.key;
      if (!target.startsWith('board:') && !target.startsWith('task:')) continue;
      final dependents = _survivingDependents(target, survivors);
      if (dependents.isEmpty) continue;
      decision.record('deletion withheld: survivors still reference it');
      decision.status = DecisionStatus.blocked;
      decision.action = DecisionAction.none;
      decision.kind = ConflictKind.danglingReference;
      decision.reason = 'deletionWouldOrphanDependents';
      decision.blockedBy = dependents;
      decision.notes = [
        ...decision.notes,
        'Deleting $target would leave ${dependents.join(', ')} pointing at '
            'nothing. Resolve those records first.',
      ];
      survivors.remove(target);
    }
  }

  List<String> _survivingDependents(String target, Set<String> survivors) {
    final out = <String>[];
    for (final key in survivors) {
      if (key == target) continue;
      final fields = _fieldsOf(key);
      if (fields == null) continue;
      if (target.startsWith('task:')) {
        final taskId = target.substring('task:'.length);
        if (key.startsWith('subtask:') &&
            key.substring('subtask:'.length).split('/').first == taskId) {
          out.add(key);
          continue;
        }
        if (key.startsWith('schedule:') && fields['taskId'] == taskId) {
          out.add(key);
        }
      } else if (target.startsWith('board:')) {
        final boardId = target.substring('board:'.length);
        if ((key.startsWith('task:') || key.startsWith('schedule:')) &&
            fields['boardId'] == boardId) {
          out.add(key);
        }
      }
    }
    return out..sort();
  }

  Map<String, dynamic>? _fieldsOf(String key) =>
      _decisions[key]?.fields ??
      local.records[key]?.fields ??
      peer.records[key]?.fields ??
      base.records[key]?.fields;

  /// A referrer whose target did not survive the merge is withheld rather than
  /// emitted as a dangling reference. Applied decisions are re-checked until
  /// stable, because withholding a task also invalidates its blocks.
  void _referencePass() {
    final boards = <String>{};
    final tasks = <String>{};
    for (final entry in local.records.entries) {
      final key = entry.key;
      final decision = _decisions[key];
      if (decision != null &&
          decision.status == DecisionStatus.auto &&
          decision.action == DecisionAction.delete) {
        continue;
      }
      if (key.startsWith('board:')) {
        boards.add(key.substring('board:'.length));
      } else if (key.startsWith('task:')) {
        tasks.add(key.substring('task:'.length));
      }
    }
    for (final entry in _decisions.entries) {
      if (entry.value.status != DecisionStatus.auto) continue;
      if (entry.value.action == DecisionAction.add) {
        if (entry.key.startsWith('board:')) {
          boards.add(entry.key.substring('board:'.length));
        } else if (entry.key.startsWith('task:')) {
          tasks.add(entry.key.substring('task:'.length));
        }
      }
    }
    var settled = false;
    var round = 0;
    while (!settled && round < 8) {
      round++;
      settled = true;
      for (final entry in _decisions.entries) {
        final key = entry.key;
        final decision = entry.value;
        if (decision.status != DecisionStatus.auto) continue;
        if (decision.action != DecisionAction.add &&
            decision.action != DecisionAction.update) {
          continue;
        }
        final fields = decision.fields;
        if (fields == null) continue;
        if (key.startsWith('task:')) {
          final boardId = fields['boardId'];
          if (boardId is String &&
              boardId.isNotEmpty &&
              !boards.contains(boardId)) {
            _withhold(decision, SyncKey.board(boardId));
            settled = false;
          }
        } else if (key.startsWith('schedule:')) {
          final taskId = fields['taskId'];
          if (taskId is String &&
              taskId.isNotEmpty &&
              !tasks.contains(taskId)) {
            _withhold(decision, SyncKey.task(taskId));
            settled = false;
          }
          final boardId = fields['boardId'];
          if (boardId is String &&
              boardId.isNotEmpty &&
              !boards.contains(boardId)) {
            _withhold(decision, SyncKey.board(boardId));
            settled = false;
          }
        } else if (key.startsWith('subtask:')) {
          final parent = key.substring('subtask:'.length).split('/').first;
          if (!tasks.contains(parent)) {
            _withhold(decision, SyncKey.task(parent));
            settled = false;
          }
        }
      }
      if (!settled) {
        // Drop the targets that were just withheld from the surviving sets.
        for (final entry in _decisions.entries) {
          final decision = entry.value;
          if (decision.status != DecisionStatus.blocked) continue;
          if (entry.key.startsWith('board:')) {
            boards.remove(entry.key.substring('board:'.length));
          } else if (entry.key.startsWith('task:')) {
            tasks.remove(entry.key.substring('task:'.length));
          }
        }
      }
    }
  }

  void _withhold(SyncDecision decision, String target) {
    decision.record('withheld to keep references closed');
    decision.status = DecisionStatus.blocked;
    decision.action = DecisionAction.none;
    decision.kind = ConflictKind.danglingReference;
    decision.reason = 'referencedRecordNotSettled';
    decision.blockedBy = [...decision.blockedBy, target];
    decision.notes = [
      ...decision.notes,
      'Withheld so the merged library has no dangling reference. The backup '
          'contract refuses to turn an orphan into a standalone event.',
    ];
  }

  void _applyOverrides() {
    for (final entry in overrides.entries) {
      final decision = _decisions[entry.key];
      if (decision == null) continue;
      decision.record('user override ${entry.value.name}');
      switch (entry.value) {
        case Override.takeLocal:
          decision.fields ??= local.records[decision.key]?.fields;
          decision.kind = ConflictKind.none;
          decision.status = DecisionStatus.auto;
          decision.action = DecisionAction.update;
          decision.reason = 'overriddenTakeLocal';
        case Override.takePeer:
          decision.fields = peer.records[decision.key]?.fields ??
              decision.fields;
          decision.kind = ConflictKind.none;
          decision.status = DecisionStatus.auto;
          decision.action = DecisionAction.update;
          decision.reason = 'overriddenTakePeer';
        case Override.drop:
          decision.kind = ConflictKind.none;
          decision.status = DecisionStatus.auto;
          decision.action = DecisionAction.delete;
          decision.fields = null;
          decision.reason = 'overriddenDrop';
        case Override.restore:
          decision.kind = ConflictKind.none;
          decision.status = DecisionStatus.auto;
          decision.action = DecisionAction.update;
          decision.reason = 'overriddenRestore';
          decision.notes = [
            ...decision.notes,
            'User confirmed writing this record back after a deletion.',
          ];
        case Override.fieldwise:
          decision.kind = ConflictKind.none;
          decision.status = DecisionStatus.auto;
          decision.action = DecisionAction.update;
          decision.reason = 'overriddenFieldwise';
      }
    }
  }
}
