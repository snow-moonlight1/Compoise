/// Conflict vocabulary for the WP18-R experiment.
///
/// A plan is the deliverable the user reviews: it names every divergent record,
/// says whether the engine could decide it alone, and records the evidence a
/// human needs in order to overrule the engine.
library;

import 'dart:convert';

import 'digest.dart';
import 'snapshot.dart';

enum DecisionAction { keep, add, update, delete, none }

enum DecisionStatus {
  /// The engine can apply this without asking.
  auto,

  /// Both sides changed something the engine cannot rank. Shown for review.
  pending,

  /// Applying this would produce a library the product rules reject, or would
  /// break a safety guard, so it is withheld until its blocker is decided.
  blocked,
}

enum ConflictKind {
  none,
  sameIdFork,
  deleteEdit,
  duplicateContent,
  concurrentCompletion,
  reparented,
  danglingReference,
  scheduleKindChanged,
  unknownField,
  presenceAmbiguity,
  civilDayFalseConflict,
  orderingDivergence,
  configDivergence,
  credentialBlocked,
  clockTie,
}

class FieldDiff {
  const FieldDiff({
    required this.field,
    this.base,
    this.left,
    this.right,
    this.sameCivilDay = false,
    this.merged,
    this.autoMergeable = false,
  });

  final String field;
  final Object? base;
  final Object? left;
  final Object? right;

  /// Set when the two instants are the same local civil day on their own zones.
  final bool sameCivilDay;
  final Object? merged;

  /// Only one side moved this field away from the baseline.
  final bool autoMergeable;

  bool get leftChanged => !_same(base, left);
  bool get rightChanged => !_same(base, right);

  Map<String, dynamic> toJson() => {
    'field': field,
    'base': base,
    'left': left,
    'right': right,
    if (sameCivilDay) 'sameCivilDay': true,
    if (merged != null) 'merged': merged,
    'autoMergeable': autoMergeable,
  };

  String describe() {
    final parts = [
      '$field: base=${_short(base)}',
      'local=${_short(left)}',
      'peer=${_short(right)}',
    ];
    if (sameCivilDay) parts.add('(same civil day)');
    if (merged != null) parts.add('=> ${_short(merged)}');
    return parts.join(' ');
  }

  static bool _same(Object? a, Object? b) => canonicalJson(a) == canonicalJson(b);
  static String _short(Object? value) {
    final text = value is String ? value : jsonEncode(canonicalJson(value));
    return text.length <= 48 ? text : '${text.substring(0, 45)}...';
  }
}

class SyncDecision {
  SyncDecision({
    required this.key,
    required this.kind,
    required this.action,
    required this.status,
    required this.reason,
    this.baseDigest,
    this.leftDigest,
    this.rightDigest,
    this.leftClock,
    this.rightClock,
    this.leftOrigin,
    this.rightOrigin,
    this.diffs = const [],
    this.fields,
    this.configSlot,
    this.localValue,
    this.peerValue,
    this.configValue,
    this.recommendation,
    this.blockedBy = const [],
    this.notes = const [],
  });

  final String key;

  /// Mutable: the policy, reference and override passes refine a decision that
  /// classification produced, and each refinement is kept in [history].
  ConflictKind kind;
  DecisionAction action;
  DecisionStatus status;

  /// Machine-readable code, so a test can assert the reason instead of prose.
  String reason;
  String? baseDigest;
  String? leftDigest;
  String? rightDigest;
  int? leftClock;
  int? rightClock;
  String? leftOrigin;
  String? rightOrigin;
  List<FieldDiff> diffs;

  /// Fields to write when the action is `add`/`update`. Null keeps the base.
  Map<String, dynamic>? fields;

  /// Only for the `config:` keys: the settings/AI blob each side holds, and the
  /// one the plan settled on. Config is never merged field by field.
  String? configSlot;
  Object? localValue;
  Object? peerValue;
  Object? configValue;

  /// What the engine would pick if a human confirmed nothing.
  String? recommendation;

  /// Keys this decision waits on.
  List<String> blockedBy;
  List<String> notes;

  /// Every pass that changed this decision, in order. A reviewer can see that
  /// "auto" is the result of classification plus a named policy, not a guess.
  final List<String> history = [];

  bool get isApplied => status == DecisionStatus.auto;
  bool get needsReview => status != DecisionStatus.auto;

  void record(String note) => history.add('${kind.name}/${status.name}: $note');

  Map<String, dynamic> toJson() => {
    'key': key,
    'kind': kind.name,
    'action': action.name,
    'status': status.name,
    'reason': reason,
    if (baseDigest != null) 'baseDigest': baseDigest,
    if (leftDigest != null) 'leftDigest': leftDigest,
    if (rightDigest != null) 'rightDigest': rightDigest,
    if (leftClock != null) 'leftClock': leftClock,
    if (rightClock != null) 'rightClock': rightClock,
    if (leftOrigin != null) 'leftOrigin': leftOrigin,
    if (rightOrigin != null) 'rightOrigin': rightOrigin,
    if (diffs.isNotEmpty) 'diffs': [for (final d in diffs) d.toJson()],
    if (fields != null) 'fields': fields,
    if (configSlot != null) 'configSlot': configSlot,
    if (configValue != null) 'configValue': configValue,
    if (recommendation != null) 'recommendation': recommendation,
    if (blockedBy.isNotEmpty) 'blockedBy': blockedBy,
    if (notes.isNotEmpty) 'notes': notes,
    if (history.isNotEmpty) 'history': history,
  };

  String describe() {
    final head = [
      '[${status.name}] $key',
      '${kind.name} -> ${action.name} ($reason)',
    ];
    if (recommendation != null) head.add('suggested: $recommendation');
    if (blockedBy.isNotEmpty) head.add('blocked by ${blockedBy.join(', ')}');
    final lines = [head.join(' | ')];
    for (final diff in diffs) {
      lines.add('    ${diff.describe()}');
    }
    for (final note in notes) {
      lines.add('    note: $note');
    }
    return lines.join('\n');
  }
}

class SyncPlan {
  SyncPlan({
    required this.base,
    required this.left,
    required this.right,
    required this.policy,
    required this.presenceModel,
    required this.decisions,
    this.warnings = const [],
  });

  /// `left` is this device's snapshot and `right` is the peer's; the JSON keys
  /// name them `local` and `peer`. Neither is trusted as the later one.
  final SyncSnapshot base;
  final SyncSnapshot left;
  final SyncSnapshot right;
  final String policy;
  final String presenceModel;
  final List<SyncDecision> decisions;
  final List<String> warnings;

  List<SyncDecision> get auto => [
    for (final d in decisions)
      if (d.status == DecisionStatus.auto) d,
  ];

  List<SyncDecision> get pending => [
    for (final d in decisions)
      if (d.status == DecisionStatus.pending) d,
  ];

  List<SyncDecision> get blocked => [
    for (final d in decisions)
      if (d.status == DecisionStatus.blocked) d,
  ];

  List<SyncDecision> get conflicts => [
    for (final d in decisions)
      if (d.kind != ConflictKind.none) d,
  ];

  Map<String, int> get counts {
    final tally = <String, int>{};
    for (final decision in decisions) {
      final label = '${decision.kind.name}/${decision.status.name}';
      tally[label] = (tally[label] ?? 0) + 1;
    }
    return tally;
  }

  bool get hasReviewItems => pending.isNotEmpty || blocked.isNotEmpty;

  Map<String, dynamic> toJson() => {
    'tool': SyncSnapshot.envelopeTag,
    'policy': policy,
    'presenceModel': presenceModel,
    'identity': {
      'base': _identityOf(base),
      'local': _identityOf(left),
      'peer': _identityOf(right),
    },
    'clockCaveat':
        'Per-record clocks are per-device counters. They order events that '
        'share device history and are not a global revision, wall clock, or '
        'causality proof.',
    'counts': counts,
    'warnings': warnings,
    'decisions': [for (final d in decisions) d.toJson()],
  };

  static Map<String, dynamic> _identityOf(SyncSnapshot snapshot) => {
    'deviceId': snapshot.device.deviceId,
    'deviceLabel': snapshot.device.label,
    'snapshotId': snapshot.snapshotId,
    'sequence': snapshot.sequence,
    'takenAt': instantLabel(snapshot.takenAtMs),
    'zoneOffsetMinutes': snapshot.device.zoneOffsetMinutes,
    'libraryDigest': snapshot.libraryDigest,
    'tombstones': snapshot.tombstones.length,
  };

  String describe() {
    final buffer = StringBuffer()
      ..writeln('WP18-R offline conflict plan')
      ..writeln('policy: $policy   presence: $presenceModel')
      ..writeln(
        'base: ${base.device.deviceId}/${base.snapshotId}  '
        'local: ${left.device.deviceId}/${left.snapshotId}  '
        'peer: ${right.device.deviceId}/${right.snapshotId}',
      )
      ..writeln(
        'records ${left.records.length} -> decisions ${decisions.length}, '
        'auto ${auto.length}, pending ${pending.length}, '
        'blocked ${blocked.length}, conflicts ${conflicts.length}',
      );
    if (warnings.isNotEmpty) {
      buffer.writeln('warnings:');
      for (final warning in warnings) {
        buffer.writeln('  - $warning');
      }
    }
    for (final group in [
      ('needs review', pending),
      ('withheld', blocked),
      ('conflicts recorded as auto', [
        for (final d in auto)
          if (d.kind != ConflictKind.none) d,
      ]),
      ('auto decisions', [
        for (final d in auto)
          if (d.kind == ConflictKind.none) d,
      ]),
    ]) {
      if (group.$2.isEmpty) continue;
      buffer.writeln('');
      buffer.writeln('${group.$1} (${group.$2.length}):');
      for (final decision in group.$2) {
        buffer.writeln(decision.describe());
      }
    }
    return buffer.toString();
  }

  String encodeJson() =>
      const JsonEncoder.withIndent('  ').convert(toJson());
}
