/// Agreement between the experiment's reader and the product's own backup
/// rules. The experiment never imports Store or SaveProtocol; it only reads
/// v3 payloads through the product model to prove the two agree.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/experiments/wp18_sync/applier.dart';
import 'package:matrixflow_native/experiments/wp18_sync/demo_fixtures.dart';
import 'package:matrixflow_native/experiments/wp18_sync/digest.dart';
import 'package:matrixflow_native/experiments/wp18_sync/planner.dart';
import 'package:matrixflow_native/experiments/wp18_sync/snapshot.dart';
import 'package:matrixflow_native/import_preflight.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/recovery_text.dart' show recoverySha256Hex;
import 'package:matrixflow_native/schedule_item.dart';

Map<String, dynamic> _decode(Map<String, dynamic> payload) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(payload)) as Map);

Set<String> _productIds(ExportData data) => {
  for (final board in data.boards) 'board:${board.id}',
  for (final task in data.tasks) 'task:${task.id}',
  for (final task in data.tasks)
    for (final child in task.subtasks) 'subtask:${task.id}/${child.id}',
  for (final item in data.scheduleItems) 'schedule:${item.id}',
};

void main() {
  SyncScenario named(String name) {
    for (final scenario in wp18Scenarios()) {
      if (scenario.name == name) return scenario;
    }
    throw StateError('missing scenario $name');
  }

  group('WP18-R agrees with the product backup contract', () {
    test('every acceptable merge re-reads through ExportData', () {
      var checked = 0;
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
        final outcome = MergeApplier(plan).apply();
        if (outcome.selfCheck.isNotEmpty) continue;
        final data = ExportData.fromJson(_decode(outcome.mergedV3));
        expect(
          _productIds(data).length,
          outcome.mergedSnapshot.records.length,
          reason: '${scenario.name}: the product sees a different record set',
        );
        checked++;
      }
      expect(checked, greaterThan(20));
    });

    test('a merge the experiment flags is refused by the product too', () {
      final scenario = named('schedule-parent-deleted');
      final input = scenario.input();
      final pair = input.pair();
      final plan = ConflictPlanner(
        base: input.baseSnapshot(),
        local: pair.$1,
        peer: pair.$2,
        presence: input.presence,
        // The human forces the orphaning deletion the engine withheld.
        overrides: const {'task:t-8': Override.drop},
      ).build();
      final outcome = MergeApplier(plan).apply();
      expect(outcome.selfCheck, isNotEmpty);
      expect(
        () => ExportData.fromJson(_decode(outcome.mergedV3)),
        throwsA(isA<FormatException>()),
        reason: 'the product must reject what the self-check rejected',
      );
    });

    test('baseline payloads carry the same ids in both readers', () {
      for (final scenario in wp18Scenarios()) {
        if (scenario.expectLoadError != null) continue;
        final base = scenario.input().baseSnapshot();
        final payload = base.toV3Payload();
        final data = ExportData.fromJson(_decode(payload));
        expect(
          _productIds(data),
          base.records.keys.toSet(),
          reason: scenario.name,
        );
      }
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('the preflight names the same unknown field the engine refuses', () {
      final input = named('unknown-field-on-peer').input();
      // The raw fixture payload, not the engine's own writer: the experiment
      // refuses to transport a field it does not understand, so a round trip
      // through it would drop the very thing being compared.
      final payload = _decode(input.peer.library);
      final plan = ImportPreflight.inspect(
        payload,
        'merge',
        currentBoards: const [],
        currentTasks: const [],
        revision: 0,
      );
      expect(
        plan.warnings.any((warning) => warning.contains('syncPinned')),
        isTrue,
        reason: 'the product preflight should flag the field too',
      );
      final conflict = ConflictPlanner(
        base: input.baseSnapshot(),
        local: input.pair().$1,
        peer: input.pair().$2,
      ).build();
      expect(conflict.pending.single.reason, 'unrecognizedFieldsPresent');
    });

    test('both readers reject a timestamp outside the allowed range', () {
      final payload = library(
        boards: [board('b-1', 'Release')],
        tasks: [
          task('t-1', 'b-1', deadline: 8640000000000001),
        ],
      );
      expect(
        () => ExportData.fromJson(_decode(payload)),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => SyncSnapshot.fromV3(
          payload: _decode(payload),
          snapshotId: 'x',
          takenAtMs: 1,
        ),
        throwsA(isA<SnapshotFormatException>()),
      );
    });

    test('both readers reject an inverted schedule interval', () {
      final payload = library(
        boards: [board('b-1', 'Release')],
        tasks: [task('t-1', 'b-1')],
        schedule: [
          timeBlock('k-1', 't-1', startAt: 2000, endAt: 1000),
        ],
      );
      expect(
        () => ExportData.fromJson(_decode(payload)),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => SyncSnapshot.fromV3(
          payload: _decode(payload),
          snapshotId: 'x',
          takenAtMs: 1,
        ),
        throwsA(
          isA<SnapshotFormatException>().having(
            (e) => e.errors.join(' '),
            'errors',
            contains('invalid interval'),
          ),
        ),
      );
    });

    test('both readers reject a repeated schedule id', () {
      final payload = library(
        boards: [board('b-1', 'Release')],
        tasks: [task('t-1', 'b-1')],
        schedule: [
          timeBlock('k-1', 't-1', startAt: 1000, endAt: 2000),
          timeBlock('k-2', 't-1', startAt: 1000, endAt: 2000),
        ],
      );
      final duplicated = Map<String, dynamic>.from(payload);
      duplicated['scheduleItems'] = [
        ...(payload['scheduleItems'] as List),
        {
          'id': 'k-1',
          'kind': 'timeBlock',
          'taskId': 't-1',
          'startAt': 3000,
          'endAt': 4000,
          'timeZoneId': 'Asia/Shanghai',
        },
      ];
      expect(
        () => ExportData.fromJson(_decode(duplicated)),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => SyncSnapshot.fromV3(
          payload: _decode(duplicated),
          snapshotId: 'x',
          takenAtMs: 1,
        ),
        throwsA(isA<SnapshotFormatException>()),
      );
    });

    test('both readers keep task and schedule id namespaces apart', () {
      final payload = library(
        boards: [board('b-1', 'Release')],
        tasks: [task('shared-1', 'b-1')],
        schedule: [
          timeBlock('shared-1', 'shared-1', startAt: 1000, endAt: 2000),
        ],
      );
      final data = ExportData.fromJson(_decode(payload));
      expect(data.tasks.single.id, 'shared-1');
      expect(data.scheduleItems.single.id, 'shared-1');
      final snapshot = SyncSnapshot.fromV3(
        payload: _decode(payload),
        snapshotId: 'x',
        takenAtMs: 1,
      );
      expect(
        snapshot.records.keys.toSet(),
        {'board:b-1', 'task:shared-1', 'schedule:shared-1'},
      );
    });

    test('the size and depth gates the package must not weaken still hold', () {
      expect(ImportPreflight.maxFileBytes, 8 * 1024 * 1024);
      expect(ImportPreflight.maxDepth, 12);
      expect(ImportPreflight.maxBoards, 500);
      expect(ImportPreflight.maxTasks, 10000);
      expect(ImportPreflight.maxScheduleItems, 10000);
      final bytes = Uint8List.fromList(
        utf8.encode(jsonEncode(library(boards: [board('b-1', 'Release')]))),
      );
      expect(ImportPreflight.decode(bytes), isA<Map<String, dynamic>>());
    });

    test('v1 and v2 payloads still read, with no schedule invented', () {
      final v2 = {
        'version': 2,
        'timestamp': epoch,
        'boards': [board('b-1', 'Release')],
        'tasks': [task('t-1', 'b-1')],
        'scheduleItems': [
          timeBlock('k-1', 't-1', startAt: 1000, endAt: 2000),
        ],
      };
      final data = ExportData.fromJson(_decode(v2));
      expect(data.scheduleItems, isEmpty);
      final snapshot = SyncSnapshot.fromV3(
        payload: _decode(v2),
        snapshotId: 'x',
        takenAtMs: 1,
      );
      expect(
        snapshot.records.keys,
        isNot(contains('schedule:k-1')),
        reason: 'a v2 file cannot carry schedules',
      );
      expect(
        snapshot.unknownTopLevel,
        contains('scheduleItems(v2 ignored)'),
      );
    });

    test('a future version is refused by both readers', () {
      final payload = {
        'version': 4,
        'timestamp': epoch,
        'boards': <Map<String, dynamic>>[],
        'tasks': <Map<String, dynamic>>[],
        'scheduleItems': <Map<String, dynamic>>[],
      };
      expect(
        () => ExportData.fromJson(_decode(payload)),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => SyncSnapshot.fromV3(
          payload: _decode(payload),
          snapshotId: 'x',
          takenAtMs: 1,
        ),
        throwsA(isA<SnapshotFormatException>()),
      );
    });

    test('subtask order is preserved into a v3 task list', () {
      final input = named('subtask-reordered-both').input();
      final pair = input.pair();
      final outcome = MergeApplier(
        ConflictPlanner(
          base: input.baseSnapshot(),
          local: pair.$1,
          peer: pair.$2,
        ).build(),
      ).apply();
      final task = (outcome.mergedV3['tasks'] as List).single
          as Map<String, dynamic>;
      final ids = [
        for (final child in task['subtasks'] as List)
          (child as Map)['id'] as String,
      ];
      expect(ids.first, 's-2');
      expect(ExportData.fromJson(_decode(outcome.mergedV3)).tasks.single.id, 't-1');
    });

    test('canonical encoding is order independent', () {
      final left = canonicalJson({'a': 1, 'b': [1, 2]});
      final right = canonicalJson({'b': [1, 2], 'a': 1});
      expect(left, right);
      expect(contentDigest({'x': 1}), contentDigest({'x': 1}));
      expect(contentDigest({'x': 1}), isNot(contentDigest({'x': 2})));
      expect(contentDigest(null).length, 64);
      // Same function the recovery archive uses for archiveId, so an envelope
      // tag and a recovery tag are comparable.
      expect(contentDigest('abc'), recoverySha256Hex(utf8.encode('"abc"')));
    });

    test('a civil day agrees across zones only when it should', () {
      expect(
        isSameCivilDay(
          leftMs: civilMidnight(20600, 480),
          rightMs: civilMidnight(20600, -300),
          leftZoneOffsetMinutes: 480,
          rightZoneOffsetMinutes: -300,
        ),
        isTrue,
      );
      expect(
        isSameCivilDay(
          leftMs: civilMidnight(20600, 480),
          rightMs: civilMidnight(20601, -300),
          leftZoneOffsetMinutes: 480,
          rightZoneOffsetMinutes: -300,
        ),
        isFalse,
      );
      expect(
        civilDayLabel(civilMidnight(0, 0), 0),
        '1970-01-01',
      );
    });

    test('the product model round-trips a plan body the engine merged', () {
      final input = named('fieldwise-disjoint').input();
      final pair = input.pair();
      final plan = ConflictPlanner(
        base: input.baseSnapshot(),
        local: pair.$1,
        peer: pair.$2,
      ).build();
      final decision = plan.decisions.single;
      final merged = decision.fields ?? const <String, dynamic>{};
      final task = Task.fromJson({
        'id': 't-1',
        'boardId': 'b-1',
        'createdAt': epoch,
        'quadrant': 2,
        ...merged,
        'subtasks': const <Map<String, dynamic>>[],
      });
      expect(task.notesMarkdown, 'add the gate table');
      expect(task.deadline, isNotNull);
      expect(task.plannedDate, civilMidnight(20600, 480));
      // A schedule the engine carried through unchanged still reads as a
      // product ScheduleItem.
      final peerSchedule = named('peer-added-block-for-deleted-task')
          .input()
          .pair()
          .$2
          .records['schedule:k-2']!;
      expect(
        ScheduleItem.fromJson({
          'id': 'k-2',
          ...peerSchedule.fields,
        }).taskId,
        't-1',
      );
    });
  });
}
