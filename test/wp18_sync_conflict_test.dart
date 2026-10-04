/// Catalogue and invariant suite for the WP18-R offline conflict prototype.
///
/// Every case is synthetic data in memory or in a temporary directory. No
/// device, no network, no real user library.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/experiments/wp18_sync/applier.dart';
import 'package:matrixflow_native/experiments/wp18_sync/demo_fixtures.dart';
import 'package:matrixflow_native/experiments/wp18_sync/plan.dart';
import 'package:matrixflow_native/experiments/wp18_sync/planner.dart';
import 'package:matrixflow_native/experiments/wp18_sync/snapshot.dart';

SyncPlan _build(
  SyncScenario scenario, {
  ResolutionPolicy policy = ResolutionPolicy.holdPending,
  PresenceModel? presence,
  Map<String, Override> overrides = const {},
  SafetyGuards guards = SafetyGuards.standard,
}) {
  final input = scenario.input();
  final pair = input.pair();
  return ConflictPlanner(
    base: input.baseSnapshot(),
    local: pair.$1,
    peer: pair.$2,
    presence: presence ?? input.presence,
    policy: policy,
    guards: guards,
    overrides: overrides,
  ).build();
}

SyncDecision? _decision(SyncPlan plan, String key) {
  for (final decision in plan.decisions) {
    if (decision.key == key) return decision;
  }
  return null;
}

void _expectStatus(
  SyncPlan plan,
  String key,
  DecisionStatus status,
  String reason,
) {
  final decision = _decision(plan, key);
  expect(decision, isNotNull, reason: '$key should appear in the plan');
  expect(
    decision!.status,
    status,
    reason: '$key status (reason ${decision.reason})',
  );
  expect(decision.reason, reason, reason: '$key reason');
}

void main() {
  final scenarios = wp18Scenarios();

  group('WP18-R conflict catalogue', () {
    for (final scenario in scenarios) {
      test(scenario.name, () {
        if (scenario.expectLoadError != null) {
          Object? caught;
          try {
            scenario.input().pair();
          } catch (error) {
            caught = error;
          }
          expect(caught, isA<SnapshotFormatException>());
          expect(
            (caught as SnapshotFormatException).errors.join('; '),
            contains(scenario.expectLoadError!),
          );
          return;
        }
        final plan = _build(scenario);
        for (final entry in scenario.expectAuto.entries) {
          _expectStatus(plan, entry.key, DecisionStatus.auto, entry.value);
        }
        for (final entry in scenario.expectPending.entries) {
          _expectStatus(plan, entry.key, DecisionStatus.pending, entry.value);
        }
        for (final entry in scenario.expectBlocked.entries) {
          _expectStatus(plan, entry.key, DecisionStatus.blocked, entry.value);
        }
        for (final warning in scenario.expectWarnings) {
          expect(
            plan.warnings.any((text) => text.contains(warning)),
            isTrue,
            reason: 'missing warning: $warning',
          );
        }
        final outcome = MergeApplier(plan).apply();
        expect(
          outcome.selfCheck,
          scenario.expectSelfCheck ?? isEmpty,
          reason: 'merged library must satisfy the backup contract',
        );
        expect(
          outcome.resurrected,
          isEmpty,
          reason: 'nothing may come back without an explicit choice',
        );
        expect(
          jsonDecode(jsonEncode(outcome.mergedV3)),
          isA<Map<String, dynamic>>(),
        );
      });
    }
  });

  group('WP18-R invariants across every scenario', () {
    test('the same three snapshots always produce the same plan', () {
      for (final scenario in scenarios) {
        if (scenario.expectLoadError != null) continue;
        final first = _build(scenario);
        final second = _build(scenario);
        expect(
          first.encodeJson(),
          second.encodeJson(),
          reason: '${scenario.name} is not deterministic',
        );
      }
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('a plan holds one decision per key', () {
      for (final scenario in scenarios) {
        if (scenario.expectLoadError != null) continue;
        final keys = _build(scenario).decisions
            .map((decision) => decision.key)
            .toSet();
        expect(
          keys.length,
          _build(scenario).decisions.length,
          reason: '${scenario.name} repeats a key',
        );
      }
    });

    test('an undecided record keeps its local content', () {
      for (final scenario in scenarios) {
        if (scenario.expectLoadError != null) continue;
        final plan = _build(scenario);
        final local = plan.left;
        final merged = MergeApplier(plan).apply().mergedSnapshot;
        for (final decision in plan.decisions) {
          if (decision.status == DecisionStatus.auto) continue;
          final before = local.records[decision.key];
          if (before == null) continue;
          final after = merged.records[decision.key];
          expect(
            after?.digest,
            before.digest,
            reason: '${scenario.name}: ${decision.key} was changed while '
                'the decision is ${decision.status.name}',
          );
        }
      }
    });

    test('nothing deleted on one side reappears on its own', () {
      for (final scenario in scenarios) {
        if (scenario.expectLoadError != null) continue;
        final plan = _build(scenario);
        final outcome = MergeApplier(plan).apply();
        for (final tombstone in plan.left.tombstones) {
          if (outcome.resurrected.any((d) => d.key == tombstone.key)) continue;
          expect(
            outcome.mergedSnapshot.records.containsKey(tombstone.key),
            isFalse,
            reason: '${scenario.name}: ${tombstone.key} came back without an '
                'explicit restore',
          );
        }
      }
    });

    test('every pending item tells the reviewer something', () {
      for (final scenario in scenarios) {
        if (scenario.expectLoadError != null) continue;
        for (final decision in _build(scenario).pending) {
          expect(
            decision.recommendation != null || decision.notes.isNotEmpty,
            isTrue,
            reason: '${scenario.name}: ${decision.key} has no guidance',
          );
          expect(
            decision.kind,
            isNot(ConflictKind.none),
            reason: '${scenario.name}: ${decision.key} is pending without a '
                'conflict kind',
          );
        }
      }
    });

    test('merging twice does not drift', () {
      for (final scenario in scenarios) {
        if (scenario.expectLoadError != null) continue;
        final plan = _build(scenario);
        final once = MergeApplier(plan).apply();
        final twice = MergeApplier(plan).apply();
        expect(
          once.mergedDigest,
          twice.mergedDigest,
          reason: '${scenario.name} is not idempotent',
        );
      }
    });

    test('a plain v3 export never produces an automatic deletion', () {
      for (final scenario in scenarios) {
        if (scenario.expectLoadError != null) continue;
        final input = scenario.input();
        if (input.presence != PresenceModel.presenceOnly) continue;
        final plan = _build(scenario, presence: PresenceModel.presenceOnly);
        for (final decision in plan.auto) {
          expect(
            decision.action == DecisionAction.delete,
            isFalse,
            reason: '${scenario.name}: ${decision.key} deleted from absence '
                'alone',
          );
        }
      }
    });
  });
}
