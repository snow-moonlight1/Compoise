/// Turns an approved plan into a library, without inventing a write path.
///
/// The merged result is delivered as files in a caller-chosen directory. This
/// package never touches SharedPreferences, the committed slots, or the Store,
/// so the product's byte, pixel, confirmation and commit gates stay untouched.
library;

import 'digest.dart';
import 'plan.dart';
import 'snapshot.dart';

class MergeOutcome {
  MergeOutcome({
    required this.plan,
    required this.mergedSnapshot,
    required this.applied,
    required this.carried,
    required this.resurrected,
    required this.selfCheck,
  });

  final SyncPlan plan;
  final SyncSnapshot mergedSnapshot;

  /// Decisions that actually changed library content.
  final List<SyncDecision> applied;

  /// Decisions left for a human; local content is untouched for these.
  final List<SyncDecision> carried;

  /// Deletions that were reopened, each one only after an explicit choice.
  final List<SyncDecision> resurrected;

  /// Problems found by re-reading the merged library with the same reader the
  /// snapshots used. Non-empty means the prototype produced something the
  /// product contract would refuse, so the run must not be called a success.
  final List<String> selfCheck;

  bool get isClean => selfCheck.isEmpty;
  bool get hasChanges => applied.isNotEmpty;

  Map<String, dynamic> get mergedV3 => mergedSnapshot.toV3Payload();
  Map<String, dynamic> get mergedEnvelope => mergedSnapshot.toEnvelope();
  String get mergedDigest => mergedSnapshot.libraryDigest;

  String describe() {
    final buffer = StringBuffer()
      ..writeln('WP18-R merge outcome')
      ..writeln(
        'applied ${applied.length}, carried ${carried.length}, '
            'resurrected ${resurrected.length}, '
            'records ${mergedSnapshot.records.length}',
      )
      ..writeln('merged library digest ${mergedSnapshot.libraryDigest}');
    if (selfCheck.isNotEmpty) {
      buffer.writeln('self-check failures:');
      for (final error in selfCheck) {
        buffer.writeln('  - $error');
      }
    }
    for (final decision in resurrected) {
      buffer.writeln('  resurrection: ${decision.key} (${decision.reason})');
    }
    for (final decision in carried) {
      buffer.writeln('  carried: ${decision.key} ${decision.reason}');
    }
    return buffer.toString();
  }
}

class MergeApplier {
  MergeApplier(this.plan);

  final SyncPlan plan;

  bool _changesContent(SyncDecision decision) {
    if (decision.configSlot != null) return decision.configValue != null;
    final current = plan.left.records[decision.key]?.fields;
    final next = decision.fields;
    if (next == null) return current != null;
    return canonicalJson(current) != canonicalJson(next);
  }

  /// A deletion conflict that ended up writing content back, whichever device
  /// held the deletion marker.
  bool _isResurrection(SyncDecision decision) =>
      plan.left.tombstoneFor(decision.key) != null ||
      decision.history.any((entry) => entry.contains('deleteEdit'));

  /// Starts from the local view and applies only what the plan settled. A
  /// pending or blocked item never alters the local record, so an undecided
  /// conflict cannot turn into a silent overwrite.
  MergeOutcome apply() {
    final records = <String, SyncRecord>{...plan.left.records};
    var tombstones = <Tombstone>[...plan.left.tombstones];
    final states = <String, RecordState>{...plan.left.recordStates};
    final applied = <SyncDecision>[];
    final carried = <SyncDecision>[];
    final resurrected = <SyncDecision>[];

    for (final decision in plan.decisions) {
      if (decision.status != DecisionStatus.auto) {
        if (decision.needsReview) carried.add(decision);
        continue;
      }
      switch (decision.action) {
        case DecisionAction.delete:
          final removed = records.remove(decision.key);
          if (removed != null) {
            states.remove(decision.key);
            tombstones = [
              ...tombstones.where((t) => t.key != decision.key),
              Tombstone(
                key: decision.key,
                deletedAtMs: plan.left.takenAtMs,
                clock: plan.left.clockFor(decision.key),
                originDeviceId: plan.left.device.deviceId,
                lastDigest: removed.digest,
              ),
            ];
          }
          applied.add(decision);
        case DecisionAction.add:
        case DecisionAction.update:
          if (decision.configSlot != null) {
            applied.add(decision);
            continue;
          }
          final fields = decision.fields;
          if (fields == null) continue;
          final previous =
              records[decision.key] ??
              SyncRecord(
                key: decision.key,
                fields: const {},
                unknownValues: const {},
                position: null,
              );
          records[decision.key] = previous.withFields(fields);
          states[decision.key] = RecordState(
            clock: _nextClock(decision.key),
            originDeviceId: _originOf(decision),
          );
          if (_isResurrection(decision)) {
            resurrected.add(decision);
          }
          applied.add(decision);
        case DecisionAction.keep:
        case DecisionAction.none:
          continue;
      }
    }

    // A config decision rewrites the config maps only, never a record.
    var settings = plan.left.settings;
    var aiConfig = plan.left.aiConfig;
    for (final decision in applied) {
      final slot = decision.configSlot;
      final value = decision.configValue;
      if (slot == null || value is! Map) continue;
      final map = Map<String, dynamic>.from(value);
      if (slot == 'settings') {
        settings = map;
      } else if (slot == 'aiConfig') {
        // The reader already dropped the credential; this keeps it dropped.
        map.remove('customApiKey');
        aiConfig = map;
      }
    }

    final merged = SyncSnapshot(
      device: plan.left.device,
      snapshotId: '${plan.left.snapshotId}+${plan.right.snapshotId}',
      sequence: _nextSequence(),
      takenAtMs: plan.left.takenAtMs,
      parentSnapshotId: plan.left.snapshotId,
      records: records,
      tombstones: tombstones,
      recordStates: states,
      settings: settings,
      aiConfig: aiConfig,
      unknownTopLevel: plan.left.unknownTopLevel,
    );
    return MergeOutcome(
      plan: plan,
      mergedSnapshot: merged,
      applied: [
        for (final decision in applied)
          if (_changesContent(decision)) decision,
      ],
      carried: carried,
      resurrected: resurrected,
      selfCheck: _selfCheck(merged),
    );
  }

  int _nextSequence() {
    var highest = plan.left.sequence;
    if (plan.right.sequence > highest) highest = plan.right.sequence;
    return highest + 1;
  }

  int _nextClock(String key) {
    final observed = [
      plan.left.clockFor(key),
      plan.right.clockFor(key),
    ]..sort();
    return observed.last + 1;
  }

  /// Where the winning content came from. A manual override can pick either
  /// side's body, so the fields are compared rather than trusting `reason`.
  String _originOf(SyncDecision decision) {
    final fields = decision.fields;
    final peerFields = plan.right.records[decision.key]?.fields;
    if (fields != null &&
        peerFields != null &&
        canonicalJson(peerFields) == canonicalJson(fields)) {
      return plan.right.device.deviceId;
    }
    return plan.left.device.deviceId;
  }

  List<String> _selfCheck(SyncSnapshot merged) {
    try {
      final reread = SyncSnapshot.fromV3(
        payload: merged.toV3Payload(),
        device: merged.device,
        snapshotId: merged.snapshotId,
        sequence: merged.sequence,
        takenAtMs: merged.takenAtMs,
      );
      return [
        for (final finding in reread.referenceFindings) 'reference: $finding',
      ];
    } on SnapshotFormatException catch (error) {
      return error.errors;
    }
  }
}
