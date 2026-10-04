/// The transport boundary and its failure modes, over a temporary directory.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/experiments/wp18_sync/applier.dart';
import 'package:matrixflow_native/experiments/wp18_sync/demo_fixtures.dart';
import 'package:matrixflow_native/experiments/wp18_sync/planner.dart';
import 'package:matrixflow_native/experiments/wp18_sync/snapshot.dart';
import 'package:matrixflow_native/experiments/wp18_sync/transport.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('wp18-r-transport-');
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  ScenarioInput scenario(String name) {
    for (final entry in wp18Scenarios()) {
      if (entry.name == name) return entry.input();
    }
    throw StateError('missing scenario $name');
  }

  (SyncSnapshot, SyncSnapshot) pair(String name) => scenario(name).pair();

  List<int> readStored(Directory dir, String deviceId, String snapshotId) {
    final file = File('${dir.path}/remote/$deviceId/$snapshotId.wp18');
    expect(file.existsSync(), isTrue, reason: '${file.path} is missing');
    return file.readAsBytesSync();
  }

  Directory remoteDir(Directory base) => Directory('${base.path}/remote');

  group('WP18-R transport round trip', () {
    test('an envelope survives storage and replans identically', () async {
      final (local, peer) = pair('delete-edit-peer-deleted');
      final transport = LocalDirectoryTransport(root);
      final put = await transport.put(peer, operationId: 'op-1');
      expect(put.stored, isTrue);
      expect(put.reason, 'stored');
      final pulled = await transport.pull();
      expect(pulled.entries, hasLength(1));
      final restored = SyncSnapshot.decodeEnvelopeText(
        utf8.decode(pulled.entries.single.bytes),
      );
      expect(restored.device.deviceId, peer.device.deviceId);
      expect(restored.snapshotId, peer.snapshotId);
      expect(
        restored.tombstones.map((t) => t.key).toList()..sort(),
        peer.tombstones.map((t) => t.key).toList()..sort(),
      );
      expect(restored.libraryDigest, peer.libraryDigest);

      final viaMemory = ConflictPlanner(
        base: scenario('delete-edit-peer-deleted').baseSnapshot(),
        local: local,
        peer: peer,
      ).build();
      final viaStorage = ConflictPlanner(
        base: scenario('delete-edit-peer-deleted').baseSnapshot(),
        local: local,
        peer: restored,
      ).build();
      expect(
        viaStorage.pending.map((d) => '${d.key}/${d.reason}').toList()..sort(),
        viaMemory.pending.map((d) => '${d.key}/${d.reason}').toList()..sort(),
      );
    });

    test('capabilities name the provider gaps a design must cover', () async {
      final transport = LocalDirectoryTransport(root);
      final caps = await transport.capabilities();
      expect(caps.supportsConditionalPut, isTrue);
      expect(caps.shortfalls(), isEmpty);
      const weak = TransportCapabilities(
        supportsConditionalPut: false,
        serverKeepsTombstones: false,
        supportsChangeFeed: false,
        maxItemBytes: 1024,
        requiresAccount: true,
        onlineOnly: true,
      );
      expect(weak.shortfalls(), hasLength(5));
      expect(weak.maxItemBytes, 1024);
    });

    test('oversized payloads are refused by the declared limit', () async {
      final (local, _) = pair('add-on-local-only');
      final transport = LocalDirectoryTransport(
        root,
        caps: const TransportCapabilities(
          supportsConditionalPut: true,
          serverKeepsTombstones: true,
          supportsChangeFeed: true,
          maxItemBytes: 8,
          requiresAccount: false,
          onlineOnly: false,
        ),
      );
      final result = await transport.put(local);
      expect(result.stored, isFalse);
      expect(result.reason, 'oversized');
      expect(remoteDir(root).listSync(), isEmpty);
    });
  });

  group('WP18-R transport failures', () {
    test('offline changes nothing on either side', () async {
      final (local, peer) = pair('add-on-peer-only');
      final faults = TransportFault(offline: true);
      final transport = LocalDirectoryTransport(root, faults: faults);
      final result = await pushWithRetry(transport, local, maxAttempts: 2);
      expect(result.delivered, isFalse);
      expect(result.result?.reason, 'offline');
      expect(result.attempts, 2);
      expect(remoteDir(root).listSync(), isEmpty);
      expect(
        MergeApplier(
          ConflictPlanner(base: local, local: local, peer: peer).build(),
        ).apply().mergedSnapshot.records.containsKey('task:t-3'),
        isTrue,
        reason: 'the local library must be unchanged by a failed push',
      );
    });

    test('a write that throws is retried and lands once', () async {
      final (local, _) = pair('add-on-local-only');
      final faults = TransportFault(failNextWrites: 1);
      final transport = LocalDirectoryTransport(root, faults: faults);
      final result = await pushWithRetry(
        transport,
        local,
        maxAttempts: 3,
        operationId: 'op-retry',
      );
      expect(result.delivered, isTrue);
      expect(result.attempts, 2);
      final journal = File('${root.path}/journal.jsonl').readAsLinesSync();
      expect(
        journal.any((line) => line.contains('"result":"write-failed"')),
        isTrue,
        reason: 'the failed first attempt must be visible in the journal',
      );
      expect(
        journal.any(
          (line) =>
              line.contains('"result":"stored"') &&
              line.contains('"operationId":"op-retry"'),
        ),
        isTrue,
      );
      final again = await transport.put(local, operationId: 'op-retry');
      expect(again.reason, 'duplicate');
      expect(again.stored, isFalse);
      expect(
        Directory('${root.path}/remote/${local.device.deviceId}')
            .listSync()
            .where((e) => e.path.endsWith('.wp18')),
        hasLength(1),
      );
    });

    test('a replay after cancellation is a no-op, not a second copy', () async {
      final (local, _) = pair('add-on-local-only');
      final faults = TransportFault(cancelAfterWrite: true);
      final transport = LocalDirectoryTransport(root, faults: faults);
      Object? thrown;
      try {
        await transport.put(local, operationId: 'op-cancel');
      } catch (error) {
        thrown = error;
      }
      expect(thrown, isA<TransportCancelled>());
      // The copy is on the remote even though the call reported a cancellation.
      expect(
        readStored(root, local.device.deviceId, local.snapshotId),
        isNotEmpty,
      );
      final replay = await transport.put(local, operationId: 'op-cancel');
      expect(replay.reason, 'duplicate');
      final head = File(
        '${root.path}/remote/${local.device.deviceId}.HEAD',
      );
      final stored = jsonDecode(head.readAsStringSync()) as Map;
      expect(stored['digest'], local.libraryDigest);
    });

    test('a stale write is refused when the remote moved on', () async {
      final (local, _) = pair('add-on-local-only');
      final transport = LocalDirectoryTransport(root);
      await transport.put(local, operationId: 'op-first');
      final diverged = await transport.put(
        local,
        expectedDigest: 'stale-digest',
        operationId: 'op-second',
      );
      expect(diverged.stored, isFalse);
      expect(diverged.reason, 'remote-diverged');
      expect(diverged.remoteDigest, local.libraryDigest);
    });

    test('a corrupted copy is detected and excluded from planning', () async {
      final (local, _) = pair('add-on-local-only');
      final transport = LocalDirectoryTransport(root);
      await transport.put(local, operationId: 'op-clean');
      final path = '${root.path}/remote/${local.device.deviceId}/'
          '${local.snapshotId}.wp18';
      final file = File(path);
      final text = file.readAsStringSync();
      file.writeAsStringSync('$text{"tampered":true}', flush: true);
      final pulled = await transport.pull();
      expect(pulled.entries, isEmpty);
      expect(pulled.reason, contains('not valid JSON'));
      // Repair: writing the same snapshot again restores a readable copy.
      final repair = await transport.put(local, operationId: 'op-repair');
      expect(repair.reason, 'stored');
      expect((await transport.pull()).entries, hasLength(1));
    });

    test('a library edited inside the file fails its content tag', () async {
      final (local, _) = pair('add-on-local-only');
      final transport = LocalDirectoryTransport(root);
      await transport.put(local, operationId: 'op-tag');
      final file = File(
        '${root.path}/remote/${local.device.deviceId}/'
        '${local.snapshotId}.wp18',
      );
      final decoded = Map<String, dynamic>.from(
        jsonDecode(file.readAsStringSync()) as Map,
      );
      ((decoded['library'] as Map)['tasks'] as List).first['title'] = 'tampered';
      file.writeAsStringSync(jsonEncode(decoded), flush: true);
      final pulled = await transport.pull();
      expect(pulled.entries, isEmpty);
      expect(pulled.reason, contains('digest mismatch'));
    });
  });

  group('WP18-R two devices over one provider', () {
    test('both sides converge and the merge is importable', () async {
      final (local, peer) = pair('board-rename-with-new-task');
      final transport = LocalDirectoryTransport(root);
      await transport.put(local, operationId: 'op-a');
      await transport.put(peer, operationId: 'op-b');
      final pulled = await transport.pull();
      expect(pulled.entries, hasLength(2));

      final base = pair('board-rename-with-new-task').$1;
      final plan = ConflictPlanner(
        base: base,
        local: local,
        peer: SyncSnapshot.decodeEnvelopeText(
          utf8.decode(
            pulled.entries
                .firstWhere((e) => e.deviceId == peer.device.deviceId)
                .bytes,
          ),
        ),
      ).build();
      final outcome = MergeApplier(plan).apply();
      expect(outcome.isClean, isTrue);
      expect(
        outcome.mergedSnapshot.records['board:b-1']?.fields['name'],
        'Release 26.10',
      );
      expect(
        outcome.mergedSnapshot.records.containsKey('task:t-2'),
        isTrue,
      );
      expect(
        SyncSnapshot.fromV3(
          payload: outcome.mergedV3,
          device: local.device,
          snapshotId: 'merged-check',
          sequence: 9,
        ).records.length,
        outcome.mergedSnapshot.records.length,
      );
    });

    test('storage keeps forward slashes usable and names unique', () async {
      final (local, _) = pair('add-on-local-only');
      final transport = LocalDirectoryTransport(root);
      await transport.put(local, operationId: 'op-x');
      final files = remoteDir(root)
          .listSync(recursive: true)
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .toList();
      expect(files.toSet().length, files.length);
      expect(files.any((name) => name.endsWith('.wp18')), isTrue);
      expect(files, contains('${local.device.deviceId}.HEAD'));
    });
  });
}
