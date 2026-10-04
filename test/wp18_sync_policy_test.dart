/// Same library, different choices: the policy, guard and override suite.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/experiments/wp18_sync/applier.dart';
import 'package:matrixflow_native/experiments/wp18_sync/demo_fixtures.dart';
import 'package:matrixflow_native/experiments/wp18_sync/plan.dart';
import 'package:matrixflow_native/experiments/wp18_sync/planner.dart';
import 'package:matrixflow_native/experiments/wp18_sync/snapshot.dart';

void main() {
  SyncScenario named(String name) {
    for (final scenario in wp18Scenarios()) {
      if (scenario.name == name) return scenario;
    }
    throw StateError('missing scenario $name');
  }

  (SyncPlan, MergeOutcome) run(
    String scenarioName, {
    ResolutionPolicy policy = ResolutionPolicy.holdPending,
    SafetyGuards guards = SafetyGuards.standard,
    Map<String, Override> overrides = const {},
  }) {
    final input = named(scenarioName).input();
    final pair = input.pair();
    final plan = ConflictPlanner(
      base: input.baseSnapshot(),
      local: pair.$1,
      peer: pair.$2,
      presence: input.presence,
      policy: policy,
      guards: guards,
      overrides: overrides,
    ).build();
    return (plan, MergeApplier(plan).apply());
  }

  Map<String, dynamic>? body(MergeOutcome outcome, String key) =>
      outcome.mergedSnapshot.records[key]?.fields;

  group('WP18-R resolution policies', () {
    test('holdPending leaves a two-sided title edit for review', () {
      final (plan, outcome) = run('edit-fork-same-field');
      expect(plan.pending.single.key, 'task:t-1');
      expect(body(outcome, 'task:t-1')?['title'], 'Ship notes v2');
      expect(outcome.applied, isEmpty);
    });

    test('preferLocal takes this device and says so in the history', () {
      final (plan, outcome) = run(
        'edit-fork-same-field',
        policy: ResolutionPolicy.preferLocal,
      );
      expect(plan.pending, isEmpty);
      expect(body(outcome, 'task:t-1')?['title'], 'Ship notes v2');
      expect(
        plan.decisions.single.history.any(
          (entry) => entry.contains('policy chose the local version'),
        ),
        isTrue,
      );
      expect(plan.decisions.single.reason, 'localWinsByPolicy');
    });

    test('preferPeer takes the other device', () {
      final (plan, outcome) = run(
        'edit-fork-same-field',
        policy: ResolutionPolicy.preferPeer,
      );
      expect(body(outcome, 'task:t-1')?['title'], 'Ship notes v3');
      expect(plan.decisions.single.reason, 'peerWinsByPolicy');
    });

    test('a fieldwise merge keeps both single-sided edits', () {
      final (plan, outcome) = run('fieldwise-disjoint');
      final merged = body(outcome, 'task:t-1');
      expect(merged?['notesMarkdown'], 'add the gate table');
      expect(merged?['deadline'], isNotNull);
      expect(outcome.selfCheck, isEmpty);
      expect(
        plan.decisions.single.reason,
        'fieldwiseMergedNoFieldTouchedTwice',
      );
      expect(plan.decisions.single.fields?.keys, contains('deadline'));
      expect(plan.decisions.single.fields?.keys, contains('notesMarkdown'));
    });

    test('fieldwiseAuto still stops where a field was touched twice', () {
      final (plan, _) = run(
        'edit-fork-same-field',
        policy: ResolutionPolicy.fieldwiseAuto,
      );
      // Both sides renamed the same field, so the fallback picks one and says
      // which, instead of inventing a third title.
      expect(plan.decisions.single.reason, 'localWinsByPolicy');
      expect(plan.pending, isEmpty);
    });

    test('manual applies nothing without an explicit decision', () {
      final (plan, outcome) = run('edit-fork-same-field', policy: ResolutionPolicy.manual);
      expect(plan.pending.length, 1);
      expect(outcome.applied, isEmpty);
    });

    test('an override is the human speaking last', () {
      final (plan, outcome) = run(
        'edit-fork-same-field',
        policy: ResolutionPolicy.manual,
        overrides: const {'task:t-1': Override.takePeer},
      );
      expect(body(outcome, 'task:t-1')?['title'], 'Ship notes v3');
      expect(plan.decisions.single.reason, 'overriddenTakePeer');
      expect(plan.decisions.single.status, DecisionStatus.auto);
    });

    test('an override may drop the peer copy of a duplicate', () {
      final (plan, outcome) = run(
        'add-add-duplicate-different-ids',
        overrides: const {'task:t-p1': Override.drop},
      );
      expect(outcome.mergedSnapshot.records.containsKey('task:t-p1'), isFalse);
      expect(outcome.mergedSnapshot.records.containsKey('task:t-l1'), isTrue);
      expect(plan.pending.where((d) => d.key == 'task:t-p1'), isEmpty);
    });

    test('settings are picked whole, never merged field by field', () {
      final (_, hold) = run('settings-divergence');
      expect(hold.mergedSnapshot.settings?['language'], 'en');
      final (plan, peerWin) = run(
        'settings-divergence',
        policy: ResolutionPolicy.preferPeer,
      );
      expect(peerWin.mergedSnapshot.settings?['language'], 'ja');
      expect(plan.decisions.any((d) => d.reason == 'peerWinsByPolicy'), isTrue);
      // Neither outcome mixes the two files.
      expect(peerWin.mergedSnapshot.settings?['theme'], 'dark');
      expect(hold.mergedSnapshot.settings?['theme'], 'system');
    });
  });

  group('WP18-R deletion safety', () {
    test('preferPeer does not resurrect a locally edited deletion', () {
      final (plan, outcome) = run(
        'delete-edit-peer-deleted',
        policy: ResolutionPolicy.preferPeer,
      );
      expect(plan.pending.single.kind, ConflictKind.deleteEdit);
      expect(
        plan.pending.single.notes.any(
          (note) => note.contains('Withheld under preferPeer'),
        ),
        isTrue,
      );
      expect(outcome.resurrected, isEmpty);
      expect(outcome.mergedSnapshot.records.containsKey('task:t-1'), isTrue);
    });

    test('allowResurrection still records the choice it was given', () {
      final (plan, outcome) = run(
        'delete-edit-peer-deleted',
        policy: ResolutionPolicy.preferPeer,
        guards: const SafetyGuards(allowResurrection: true),
      );
      expect(
        plan.decisions.any(
          (d) => d.key == 'task:t-1' && d.reason == 'deletionWinsByPolicy',
        ),
        isTrue,
      );
      // The peer's deletion wins: the edited local copy goes away.
      expect(outcome.mergedSnapshot.records.containsKey('task:t-1'), isFalse);
      expect(outcome.selfCheck, isEmpty);
      expect(outcome.mergedSnapshot.tombstones, isNotEmpty);
    });

    test('preferLocal keeps the deletion of an untouched record', () {
      final (_, outcome) = run(
        'delete-unchanged',
        policy: ResolutionPolicy.preferLocal,
      );
      expect(outcome.mergedSnapshot.records.containsKey('task:t-1'), isFalse);
    });

    test('allowResurrection with preferLocal writes the record back and says so', () {
      final (plan, outcome) = run(
        'delete-edit-peer-deleted',
        policy: ResolutionPolicy.preferLocal,
        guards: const SafetyGuards(allowResurrection: true),
      );
      expect(
        plan.decisions.any(
          (d) => d.key == 'task:t-1' && d.reason == 'resurrectionConfirmedByPolicy',
        ),
        isTrue,
      );
      expect(outcome.resurrected.single.key, 'task:t-1');
      expect(outcome.mergedSnapshot.records.containsKey('task:t-1'), isTrue);
      expect(
        outcome.describe().contains('resurrection: task:t-1'),
        isTrue,
        reason: 'the written report must name the restore',
      );
    });

    test('restoring by hand marks the outcome as a resurrection', () {
      final (_, outcome) = run(
        'delete-edit-peer-deleted',
        policy: ResolutionPolicy.manual,
        overrides: const {'task:t-1': Override.restore},
      );
      expect(outcome.mergedSnapshot.records.containsKey('task:t-1'), isTrue);
      expect(outcome.resurrected.single.key, 'task:t-1');
      expect(outcome.resurrected.single.reason, 'overriddenRestore');
    });

    test('a blocked deletion cannot orphan its dependents by accident', () {
      final (plan, outcome) = run('schedule-parent-deleted');
      final blocked = plan.blocked.single;
      expect(blocked.key, 'task:t-8');
      expect(blocked.reason, 'deletionWouldOrphanDependents');
      expect(blocked.blockedBy, contains('schedule:k-8'));
      expect(outcome.selfCheck, isEmpty);
    });

    test('forcing an orphaning deletion is caught by the self-check', () {
      final (_, outcome) = run(
        'schedule-parent-deleted',
        overrides: const {'task:t-8': Override.drop},
      );
      expect(outcome.isClean, isFalse);
      expect(
        outcome.selfCheck.any((error) => error.contains('k-8')),
        isTrue,
      );
    });
  });

  group('WP18-R credential boundary', () {
    test('a key value never reaches the plan, the merge, or a stored copy', () {
      final (plan, outcome) = run(
        'credential-never-transported',
        policy: ResolutionPolicy.preferPeer,
      );
      for (final text in [
        plan.encodeJson(),
        jsonEncode(outcome.mergedV3),
        jsonEncode(outcome.mergedEnvelope),
        plan.describe(),
        outcome.describe(),
      ]) {
        expect(text, isNot(contains('SECRET-LOCAL-DO-NOT-SHARE')));
        expect(text, isNot(contains('SECRET-PEER-DO-NOT-SHARE')));
      }
      // The reader drops the field, so no output can even name it.
      for (final text in [
        jsonEncode(outcome.mergedV3),
        jsonEncode(outcome.mergedEnvelope),
      ]) {
        expect(text, isNot(contains('customApiKey')));
      }
      expect(
        plan.decisions.any(
          (d) =>
              d.key == 'config:credential' &&
              d.status == DecisionStatus.blocked,
        ),
        isTrue,
      );
    });

    test('no policy and no override puts a body behind the credential item', () {
      for (final policy in ResolutionPolicy.values) {
        final (plan, outcome) = run(
          'credential-never-transported',
          policy: policy,
          guards: const SafetyGuards(allowResurrection: true),
          overrides: const {'config:credential': Override.takePeer},
        );
        final credential = plan.decisions
            .where((d) => d.key == 'config:credential')
            .single;
        expect(
          credential.fields,
          isNull,
          reason: 'policy ${policy.name} must have nothing to write',
        );
        expect(
          jsonEncode(outcome.mergedV3),
          isNot(contains('customApiKey')),
          reason: 'policy ${policy.name}',
        );
        expect(
          jsonEncode(outcome.mergedV3),
          isNot(contains('SECRET-')),
          reason: 'policy ${policy.name}',
        );
      }
    });
  });

  group('WP18-R clock honesty', () {
    test('equal device counters are labelled as a tie, not as time', () {
      final (plan, _) = run('clock-tie-same-counter');
      final decision = plan.pending.single;
      expect(decision.leftClock, decision.rightClock);
      expect(
        decision.notes.any((note) => note.contains('device counters')),
        isTrue,
      );
      expect(
        plan.warnings.any((warning) => warning.contains('is a global revision')),
        isTrue,
      );
    });

    test('a plain v3 snapshot puts every record at one clock', () {
      final snapshot = SyncSnapshot.fromV3(
        payload: named('delete-unchanged').input().baseSnapshot().toV3Payload(),
        device: DeviceIdentity.local,
        snapshotId: 'plain',
        sequence: 4,
        takenAtMs: 1790000000000,
      );
      expect(snapshot.records, isNotEmpty);
      for (final key in snapshot.records.keys) {
        expect(
          snapshot.clockFor(key),
          4,
          reason: '$key should share the snapshot clock',
        );
      }
    });

    test('the engine is not run with an unapproved global-revision claim', () {
      // A regression guard for the design note: nothing in a plan may assert
      // that a device counter orders events across devices.
      for (final scenario in wp18Scenarios()) {
        if (scenario.expectLoadError != null) continue;
        final input = scenario.input();
        final pair = input.pair();
        final plan = ConflictPlanner(
          base: input.baseSnapshot(),
          local: pair.$1,
          peer: pair.$2,
          presence: input.presence,
        ).build();
        expect(
          plan.toJson()['clockCaveat'],
          contains('not a global revision'),
          reason: scenario.name,
        );
      }
    });
  });
}
