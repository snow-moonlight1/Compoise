import 'dart:convert';
import 'dart:io' as io;
import 'dart:math';
import 'dart:typed_data';

import 'package:compoise/models.dart';
import 'package:compoise/sync/sync_engine.dart';
import 'package:compoise/sync/sync_files.dart';
import 'package:compoise/sync/sync_remote.dart';
import 'package:compoise/sync/sync_state.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sync_fakes.dart';

Future<Device> _device(
  MemorySyncRemote remote,
  String name, {
  TestClock? clock,
  FakeHost? host,
}) async {
  final device = Device(remote, name: name, clock: clock?.call, host: host);
  await device.load();
  return device;
}

Matcher _setup(SyncSetupError kind) =>
    throwsA(isA<SyncSetupException>().having((e) => e.kind, 'kind', kind));

void main() {
  late MemorySyncRemote remote;
  late TestClock clock;

  setUp(() {
    remote = MemorySyncRemote();
    clock = TestClock();
  });

  test('a second device joins and receives the library', () async {
    final a = await _device(remote, 'A', clock: clock);
    a.host.addTask('t1', 'Buy milk');
    a.host.addBoard('work', 'Work');
    a.host.settings.language = Language.ja;
    final report = await a.engine.createVault(remote, provider: 'memory');
    expect(report!.uploaded, isTrue);
    expect(
      remote.files.keys,
      containsAll([vaultFileName, deviceFileName(a.engine.deviceId)]),
    );

    final b = await _device(remote, 'B', clock: clock);
    b.host.settings.closeToTray = true;
    await b.engine.joinVault(remote, provider: 'memory');
    expect(b.host.view()['tasks'], a.host.view()['tasks']);
    expect(b.host.boards.map((x) => x.id), ['inbox', 'work']);
    expect(b.host.settings.language, Language.ja);
    expect(b.host.settings.closeToTray, isTrue, reason: 'device-only');
    expect(b.engine.status.phase, SyncPhase.idle);

    // Both converge and a quiet round changes nothing.
    await a.engine.sync();
    final writes = remote.log.where((op) => op.startsWith('write')).length;
    final applies = a.host.applies;
    final quiet = await a.engine.sync();
    expect(quiet!.uploaded, isFalse);
    expect(quiet.applied, isFalse);
    expect(remote.log.where((op) => op.startsWith('write')).length, writes);
    expect(a.host.applies, applies);
    expect(a.engine.devices.map((d) => d.info?.name), ['A', 'B']);
  });

  test('offline edits on two devices merge field by field', () async {
    final a = await _device(remote, 'A', clock: clock);
    a.host.addTask('t1', 'Report');
    await a.engine.createVault(remote, provider: 'memory');
    final b = await _device(remote, 'B', clock: clock);
    await b.engine.joinVault(remote, provider: 'memory');

    a.host.edit('t1', (t) => t.title = 'Quarterly report');
    b.host.edit('t1', (t) => t.notesMarkdown = 'Ask finance');
    b.host.addTask('t2', 'From B');
    a.host.removeTask('t1');
    a.host.addTask('t1b', 'only on A');
    await a.engine.sync();
    await b.engine.sync();
    await a.engine.sync();
    expect(a.host.view(), b.host.view());
    // t1 was deleted on A while B edited it: the concurrent edit keeps it.
    expect(a.host.hasTask('t1'), isTrue);
    expect(a.host.task('t1').notesMarkdown, 'Ask finance');
    expect(a.host.hasTask('t2'), isTrue);
    expect(a.host.hasTask('t1b'), isTrue);
  });

  test('offline edits keep the time they were made', () async {
    final a = await _device(remote, 'A', clock: clock);
    a.host.addTask('t1', 'Draft');
    await a.engine.createVault(remote, provider: 'memory');
    final b = await _device(remote, 'B', clock: clock);
    await b.engine.joinVault(remote, provider: 'memory');
    // B edits while offline; the app absorbs the edit right after it.
    b.host.edit('t1', (t) => t.title = 'Morning on B');
    await b.engine.absorbLocalEdits();
    // Later, A edits the same field and syncs first.
    a.host.edit('t1', (t) => t.title = 'Afternoon on A');
    await a.engine.sync();
    // B comes back online in the evening.
    await b.engine.sync();
    await a.engine.sync();
    expect(b.host.task('t1').title, 'Afternoon on A');
    expect(a.host.task('t1').title, 'Afternoon on A');
  });

  test('the same field edited on both sides converges on one value', () async {
    final a = await _device(remote, 'A', clock: clock);
    a.host.addTask('t1', 'Draft');
    await a.engine.createVault(remote, provider: 'memory');
    final b = await _device(remote, 'B', clock: clock);
    await b.engine.joinVault(remote, provider: 'memory');
    a.host.edit('t1', (t) => t.title = 'From A');
    b.host.edit('t1', (t) => t.title = 'From B');
    await a.engine.sync(); // A's clock is earlier
    await b.engine.sync();
    await a.engine.sync();
    expect(a.host.task('t1').title, 'From B');
    expect(b.host.task('t1').title, 'From B');
  });

  test(
    'deletions do not come back, also for a device that joins later',
    () async {
      final a = await _device(remote, 'A', clock: clock);
      a.host.addTask('t1', 'Keep');
      a.host.addTask('t2', 'Delete me');
      await a.engine.createVault(remote, provider: 'memory');
      final b = await _device(remote, 'B', clock: clock);
      await b.engine.joinVault(remote, provider: 'memory');
      b.host.removeTask('t2');
      await b.engine.sync();
      await a.engine.sync();
      expect(a.host.hasTask('t2'), isFalse);

      // C has an old copy of t2 from a backup and merges it in.
      final c = await _device(remote, 'C', clock: clock);
      c.host.addTask('t2', 'Delete me');
      c.host.addTask('t3', 'Only on C');
      await c.engine.joinVault(
        remote,
        provider: 'memory',
        mode: SyncJoinMode.merge,
      );
      expect(c.host.hasTask('t2'), isFalse);
      expect(c.host.hasTask('t3'), isTrue);
      await a.engine.sync();
      expect(a.host.hasTask('t2'), isFalse);
      expect(a.host.hasTask('t3'), isTrue);
    },
  );

  test('merge join: the vault wins where it already knows a record', () async {
    final a = await _device(remote, 'A', clock: clock);
    a.host.addTask('shared', 'Vault title');
    a.host.settings.themeColor = ThemeColor.values.last;
    await a.engine.createVault(remote, provider: 'memory');
    final b = await _device(remote, 'B', clock: clock);
    b.host.addTask('shared', 'Stale local title');
    b.host.addTask('mine', 'Local only');
    await b.engine.joinVault(remote, provider: 'memory');
    expect(b.host.task('shared').title, 'Vault title');
    expect(b.host.hasTask('mine'), isTrue);
    expect(b.host.settings.themeColor, ThemeColor.values.last);
    expect(b.host.boards, hasLength(1), reason: 'same starter board id');
  });

  test('replace join: the library becomes the vault copy', () async {
    final a = await _device(remote, 'A', clock: clock);
    a.host.addTask('t1', 'Vault');
    await a.engine.createVault(remote, provider: 'memory');
    final b = await _device(
      remote,
      'B',
      clock: clock,
      host: FakeHost(boardId: 'other'),
    );
    b.host.addTask('local', 'Will go');
    await b.engine.joinVault(
      remote,
      provider: 'memory',
      mode: SyncJoinMode.replaceLocal,
    );
    expect(b.host.hasTask('local'), isFalse);
    expect(b.host.boards.map((x) => x.id), ['inbox']);
    await a.engine.sync();
    expect(a.host.hasTask('local'), isFalse);
  });

  test('rejoining after the library was lost restores it from this device\'s '
      'own file', () async {
    final a = await _device(remote, 'A', clock: clock);
    a.host.addTask('t1', 'Only copy');
    a.host.addTask('t2', 'Deleted while joined');
    await a.engine.createVault(remote, provider: 'memory');
    a.host.removeTask('t2');
    await a.engine.sync();
    final own = deviceFileName(a.engine.deviceId);
    await a.engine.disconnect();

    // For example an old backup restored while sync was off: the device id
    // stays, the library is back to the empty starter board.
    a.host.removeTask('t1');
    await a.engine.joinVault(remote, provider: 'memory');
    expect(a.engine.status.phase, SyncPhase.idle);
    expect(a.host.hasTask('t1'), isTrue);
    expect(a.host.hasTask('t2'), isFalse, reason: 'tombstone kept');
    expect(a.engine.devices.map((d) => d.isThisDevice), [true]);
    expect(a.engine.status.unreadablePeers, 0);

    // The uploaded file still holds everything, for any device.
    expect(remote.files.keys, contains(own));
    final b = await _device(remote, 'B', clock: clock);
    await b.engine.joinVault(remote, provider: 'memory');
    expect(b.host.hasTask('t1'), isTrue);
    expect(b.host.hasTask('t2'), isFalse);

    // Later rounds treat the file as this device's own again.
    final reads = remote.log.where((op) => op == 'read $own').length;
    a.host.addTask('t3', 'After rejoining');
    await a.engine.sync();
    expect(remote.log.where((op) => op == 'read $own').length, reads);
  });

  test(
    'a merge rejoin keeps local additions and the earlier own file',
    () async {
      final a = await _device(remote, 'A', clock: clock);
      a.host.addTask('t1', 'From before');
      await a.engine.createVault(remote, provider: 'memory');
      await a.engine.disconnect();
      a.host.removeTask('t1');
      a.host.addTask('t2', 'Added while off');
      await a.engine.joinVault(remote, provider: 'memory');
      expect(a.host.hasTask('t1'), isTrue);
      expect(a.host.hasTask('t2'), isTrue);
    },
  );

  test(
    'a pristine device replaces automatically; an empty vault never wipes',
    () async {
      final a = await _device(
        remote,
        'A',
        clock: clock,
        host: FakeHost(boardId: 'a-inbox'),
      );
      a.host.addTask('t1', 'A');
      await a.engine.createVault(remote, provider: 'memory');
      final b = await _device(
        remote,
        'B',
        clock: clock,
        host: FakeHost(boardId: 'b-inbox'),
      );
      await b.engine.joinVault(remote, provider: 'memory');
      expect(b.host.boards.map((x) => x.id), [
        'a-inbox',
      ], reason: 'no stray empty board');

      // A vault with no device file yet: replacing would leave nothing.
      final empty = MemorySyncRemote();
      final c = await _device(empty, 'C', clock: clock);
      final vault = SyncVault(vaultId: 'emptyvault1', createdAt: 1);
      await empty.write(vaultFileName, vault.encode());
      final d = await _device(empty, 'D', clock: clock);
      d.host.addTask('keep', 'Keep me');
      await d.engine.joinVault(
        empty,
        provider: 'memory',
        mode: SyncJoinMode.replaceLocal,
      );
      expect(d.host.hasTask('keep'), isTrue);
      expect(c.engine.joined, isFalse);
    },
  );

  test('an encrypted vault needs the password and leaks no text', () async {
    final a = await _device(remote, 'A', clock: clock);
    a.host.addTask('t1', 'Secret plan');
    await a.engine.createVault(remote, provider: 'memory', password: 'hunter2');
    for (final entry in remote.files.entries) {
      if (entry.key == vaultFileName) continue;
      expect(latin1.decode(entry.value), isNot(contains('Secret')));
      expect(
        utf8.decode(entry.value, allowMalformed: true),
        isNot(contains('Secret')),
      );
    }
    final vaultText = utf8.decode(remote.files[vaultFileName]!);
    expect(vaultText, isNot(contains('hunter2')));

    final b = await _device(remote, 'B', clock: clock);
    await expectLater(
      b.engine.joinVault(remote, provider: 'memory'),
      _setup(SyncSetupError.passwordRequired),
    );
    await expectLater(
      b.engine.joinVault(remote, provider: 'memory', password: 'wrong'),
      _setup(SyncSetupError.wrongPassword),
    );
    expect(b.engine.joined, isFalse);
    await b.engine.joinVault(remote, provider: 'memory', password: 'hunter2');
    expect(b.host.task('t1').title, 'Secret plan');
    expect(b.keys.key, isNotNull, reason: 'derived key kept in secure storage');
  });

  test('a plain file slipped into an encrypted vault is ignored', () async {
    final a = await _device(remote, 'A', clock: clock);
    a.host.addTask('t1', 'Real');
    await a.engine.createVault(remote, provider: 'memory', password: 'pw');
    final intruder = await _device(MemorySyncRemote(), 'X', clock: clock);
    intruder.host.addTask('evil', 'Injected');
    // Forge a plain device file with the vault's id.
    final state = SyncState()..setField('t:evil', 'title', 'Injected', 1);
    final vaultId = SyncVault.decode(remote.files[vaultFileName]!).vaultId;
    final payload = DevicePayload(
      vaultId: vaultId,
      device: const SyncDeviceInfo(
        id: 'intruder01',
        name: 'X',
        platform: '',
        appVersion: '',
      ),
      writtenAt: 1,
      state: state,
    );
    final bytes = Uint8List.fromList([
      0x43,
      0x50,
      0x53,
      0x31,
      1,
      0,
      ...io.gzip.encode(payload.encodeJson()),
    ]);
    await remote.write(deviceFileName('intruder01'), bytes);
    final report = await a.engine.sync();
    expect(report!.unreadablePeers, 1);
    expect(a.host.hasTask('evil'), isFalse);
    expect(a.engine.devices.where((d) => d.unreadable), hasLength(1));
  });

  test(
    'changing the password: others unlock and keep their offline edits',
    () async {
      final a = await _device(remote, 'A', clock: clock);
      a.host.addTask('t1', 'Shared');
      await a.engine.createVault(remote, provider: 'memory', password: 'old');
      final b = await _device(remote, 'B', clock: clock);
      await b.engine.joinVault(remote, provider: 'memory', password: 'old');
      b.host.addTask('offline', 'Made while A changed the password');
      b.host.removeTask('t1');

      await a.engine.changePassword('new');
      expect(
        remote.files.keys.where((n) => deviceIdOfFile(n) != null),
        hasLength(1),
      );

      expect(await b.engine.sync(), isNull);
      expect(b.engine.status.phase, SyncPhase.needsPassword);
      expect(b.engine.status.issue, SyncIssue.passwordChanged);
      await expectLater(
        b.engine.unlock('old'),
        _setup(SyncSetupError.wrongPassword),
      );
      await b.engine.unlock('new');
      await a.engine.sync();
      expect(a.host.hasTask('offline'), isTrue);
      expect(
        a.host.hasTask('t1'),
        isFalse,
        reason: 'the deletion survives too',
      );

      // Removing the password asks before uploading plain files.
      await a.engine.changePassword(null);
      await b.engine.sync();
      expect(b.engine.status.issue, SyncIssue.encryptionRemoved);
      await b.engine.acceptPlainVault();
      expect(b.engine.encrypted, isFalse);
      expect(b.engine.status.phase, SyncPhase.idle);
    },
  );

  test(
    'a replaced or missing vault stops sync without touching the library',
    () async {
      final a = await _device(remote, 'A', clock: clock);
      a.host.addTask('t1', 'Mine');
      await a.engine.createVault(remote, provider: 'memory');
      remote.files.clear();
      await a.engine.sync();
      expect(a.engine.status.issue, SyncIssue.vaultMissing);
      expect(a.host.hasTask('t1'), isTrue);

      final other = SyncVault(vaultId: 'someoneelse', createdAt: 1);
      await remote.write(vaultFileName, other.encode());
      await a.engine.sync();
      expect(a.engine.status.phase, SyncPhase.needsAttention);
      expect(a.engine.status.issue, SyncIssue.vaultReplaced);
      expect(a.host.hasTask('t1'), isTrue);

      await a.engine.disconnect();
      expect(a.engine.joined, isFalse);
      expect(a.engine.status.phase, SyncPhase.off);
      expect(a.host.hasTask('t1'), isTrue);
    },
  );

  test(
    'network failures leave everything as it was and retry cleanly',
    () async {
      final a = await _device(remote, 'A', clock: clock);
      a.host.addTask('t1', 'One');
      await a.engine.createVault(remote, provider: 'memory');
      final b = await _device(remote, 'B', clock: clock);
      await b.engine.joinVault(remote, provider: 'memory');

      a.host.addTask('t2', 'Two');
      remote.failNext(
        'write',
        const SyncRemoteException(
          SyncRemoteFailure.rateLimited,
          '',
          Duration(minutes: 5),
        ),
      );
      expect(await a.engine.sync(), isNull);
      expect(a.engine.status.phase, SyncPhase.error);
      expect(a.engine.status.issue, SyncIssue.rateLimited);
      expect(a.engine.status.retryAfter, const Duration(minutes: 5));
      expect(a.host.hasTask('t2'), isTrue);

      remote.failNext(
        'list',
        const SyncRemoteException(SyncRemoteFailure.network),
      );
      expect(await b.engine.sync(), isNull);
      expect(b.engine.status.issue, SyncIssue.network);

      await a.engine.sync(); // retried upload
      await b.engine.sync();
      expect(b.host.hasTask('t2'), isTrue);

      a.host.addTask('t3', 'Three');
      await a.engine.sync();
      remote.failNext(
        'read',
        const SyncRemoteException(SyncRemoteFailure.auth),
      );
      await b.engine.sync();
      expect(b.engine.status.phase, SyncPhase.needsAttention);
      expect(b.engine.status.issue, SyncIssue.auth);
      await b.engine.sync();
      expect(b.host.hasTask('t3'), isTrue);
    },
  );

  test('a half-written download is skipped and read again next time', () async {
    final a = await _device(remote, 'A', clock: clock);
    await a.engine.createVault(remote, provider: 'memory', password: 'pw');
    final b = await _device(remote, 'B', clock: clock);
    await b.engine.joinVault(remote, provider: 'memory', password: 'pw');
    a.host.addTask('t1', 'Arrives late');
    await a.engine.sync();
    remote.truncateNextRead = 30;
    final report = await b.engine.sync();
    expect(report!.unreadablePeers, 1);
    expect(b.host.hasTask('t1'), isFalse);
    final retry = await b.engine.sync();
    expect(retry!.unreadablePeers, 0);
    expect(b.host.hasTask('t1'), isTrue);
  });

  test('duplicate delivery and replayed old files change nothing', () async {
    final a = await _device(remote, 'A', clock: clock);
    a.host.addTask('t1', 'v1');
    await a.engine.createVault(remote, provider: 'memory');
    final b = await _device(remote, 'B', clock: clock);
    await b.engine.joinVault(remote, provider: 'memory');
    final aFile = deviceFileName(a.engine.deviceId);
    final old = remote.files[aFile]!;
    a.host.edit('t1', (t) => t.title = 'v2');
    await a.engine.sync();
    await b.engine.sync();
    expect(b.host.task('t1').title, 'v2');
    await remote.write(aFile, old); // an old copy reappears
    await b.engine.sync();
    await b.engine.sync();
    expect(b.host.task('t1').title, 'v2');
  });

  test('edits during the commit are never overwritten', () async {
    final a = await _device(remote, 'A', clock: clock);
    a.host.addTask('t1', 'From A');
    await a.engine.createVault(remote, provider: 'memory');
    final b = await _device(remote, 'B', clock: clock);
    await b.engine.joinVault(remote, provider: 'memory');
    a.host.addTask('t2', 'Second from A');
    await a.engine.sync();

    var typed = 0;
    void type() {
      typed++;
      b.host.edit('t1', (t) => t.title = 'typing $typed');
      if (typed < 2) b.host.duringApply = type;
    }

    b.host.duringApply = type;
    final report = await b.engine.sync();
    expect(report, isNotNull);
    expect(b.host.task('t1').title, 'typing 2');
    expect(b.host.hasTask('t2'), isTrue);
    await a.engine.sync();
    expect(a.host.task('t1').title, 'typing 2');

    // A user who never stops typing: the round gives up and says so.
    a.host.addTask('t3', 'Third');
    await a.engine.sync();
    void forever() {
      b.host.edit('t1', (t) => t.title = 'again');
      b.host.duringApply = forever;
    }

    b.host.duringApply = forever;
    expect(await b.engine.sync(), isNull);
    expect(b.engine.status.issue, SyncIssue.busy);
    b.host.duringApply = null;
    await b.engine.sync();
    expect(b.host.hasTask('t3'), isTrue);
    expect(b.host.task('t1').title, 'again');
  });

  test('a failed library commit keeps the old sync state', () async {
    final a = await _device(remote, 'A', clock: clock);
    await a.engine.createVault(remote, provider: 'memory');
    final b = await _device(remote, 'B', clock: clock);
    await b.engine.joinVault(remote, provider: 'memory');
    a.host.addTask('t1', 'New');
    await a.engine.sync();
    final stateBefore = b.local.state;
    b.host.failApply = true;
    expect(await b.engine.sync(), isNull);
    expect(b.engine.status.issue, SyncIssue.localWrite);
    expect(b.local.state, stateBefore);
    b.host.failApply = false;
    await b.engine.sync();
    expect(b.host.hasTask('t1'), isTrue);
    // B's next upload must not claim t1 as its own new edit.
    final record = SyncState.fromJson(
      jsonDecode(b.local.state!),
    ).records['t:t1']!;
    final aState = SyncState.fromJson(
      jsonDecode(a.local.state!),
    ).records['t:t1']!;
    expect(record.clocks, aState.clocks);
  });

  test('a crash after the commit adopts the pending state', () async {
    final a = await _device(remote, 'A', clock: clock);
    await a.engine.createVault(remote, provider: 'memory');
    final b = await _device(remote, 'B', clock: clock);
    await b.engine.joinVault(remote, provider: 'memory');
    a.host.addTask('t1', 'New');
    await a.engine.sync();
    b.local.failNextStateWrite = true;
    expect(await b.engine.sync(), isNull);
    expect(b.host.hasTask('t1'), isTrue, reason: 'library committed');
    expect(b.local.pending, isNotNull);
    await b.engine.sync();
    expect(b.local.pending, isNull);
    final record = SyncState.fromJson(
      jsonDecode(b.local.state!),
    ).records['t:t1']!;
    final aState = SyncState.fromJson(
      jsonDecode(a.local.state!),
    ).records['t:t1']!;
    expect(
      record.clocks,
      aState.clocks,
      reason: 'not re-stamped as local edits',
    );
  });

  test('a damaged local state file is rebuilt without resurrecting', () async {
    final a = await _device(remote, 'A', clock: clock);
    a.host.addTask('t1', 'Keep');
    a.host.addTask('t2', 'Deleted elsewhere');
    await a.engine.createVault(remote, provider: 'memory');
    final b = await _device(remote, 'B', clock: clock);
    await b.engine.joinVault(remote, provider: 'memory');
    a.host.removeTask('t2');
    await a.engine.sync();
    b.local.state = '{"clock": "broken"}';
    await b.engine.sync();
    expect(b.engine.status.phase, SyncPhase.idle);
    expect(b.host.hasTask('t2'), isFalse);
    await a.engine.sync();
    expect(a.host.hasTask('t2'), isFalse);
  });

  test('startup recovery in progress pauses sync', () async {
    final a = await _device(remote, 'A', clock: clock);
    a.host.addTask('t1', 'x');
    await a.engine.createVault(remote, provider: 'memory');
    a.host.edit('t1', (t) => t.recoveryPending = {'title': 'x'});
    final writes = remote.log.length;
    expect(await a.engine.sync(), isNull);
    expect(a.engine.status.issue, SyncIssue.pendingRestore);
    expect(remote.log.length, writes);
  });

  test('removing a device deletes only its file', () async {
    final a = await _device(remote, 'A', clock: clock);
    a.host.addTask('t1', 'x');
    await a.engine.createVault(remote, provider: 'memory');
    final b = await _device(remote, 'B', clock: clock);
    await b.engine.joinVault(remote, provider: 'memory');
    await a.engine.sync();
    expect(a.engine.devices, hasLength(2));
    await a.engine.removeDevice(b.engine.deviceId);
    expect(
      remote.files.containsKey(deviceFileName(b.engine.deviceId)),
      isFalse,
    );
    expect(a.engine.devices, hasLength(1));
    expect(a.host.hasTask('t1'), isTrue);
  });

  test('setup errors', () async {
    final a = await _device(remote, 'A', clock: clock);
    await expectLater(
      a.engine.joinVault(remote, provider: 'memory'),
      _setup(SyncSetupError.vaultMissing),
    );
    await a.engine.createVault(remote, provider: 'memory');
    await expectLater(
      a.engine.createVault(remote, provider: 'memory'),
      _setup(SyncSetupError.alreadyJoined),
    );
    final b = await _device(remote, 'B', clock: clock);
    await expectLater(
      b.engine.createVault(remote, provider: 'memory'),
      _setup(SyncSetupError.vaultExists),
    );
    final newer = MemorySyncRemote();
    await newer.write(
      vaultFileName,
      Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'app': 'compoise',
            'kind': 'vault',
            'format': 2,
            'vaultId': 'futurevault',
            'createdAt': 1,
          }),
        ),
      ),
    );
    await expectLater(
      b.engine.joinVault(newer, provider: 'memory'),
      _setup(SyncSetupError.newerFormat),
    );
  });

  test('three devices editing offline converge (randomized)', () async {
    for (var seed = 0; seed < 12; seed++) {
      final random = Random(seed);
      final remote = MemorySyncRemote();
      final clock = TestClock();
      final devices = [
        for (final name in ['A', 'B', 'C'])
          await _device(remote, name, clock: clock),
      ];
      devices[0].host.addTask('seed', 'Seed');
      await devices[0].engine.createVault(remote, provider: 'memory');
      await devices[1].engine.joinVault(remote, provider: 'memory');
      await devices[2].engine.joinVault(remote, provider: 'memory');
      var nextId = 0;
      for (var step = 0; step < 40; step++) {
        final device = devices[random.nextInt(3)];
        final host = device.host;
        switch (random.nextInt(6)) {
          case 0:
            host.addTask(
              'n${nextId++}',
              'Task $step',
              quadrant: 1 + random.nextInt(4),
            );
          case 1 when host.tasks.isNotEmpty:
            final task = host.tasks[random.nextInt(host.tasks.length)];
            host.edit(task.id, (t) => t.title = 'Edited $step');
          case 2 when host.tasks.isNotEmpty:
            final task = host.tasks[random.nextInt(host.tasks.length)];
            host.edit(task.id, (t) => t.completed = !t.completed);
          case 3 when host.tasks.isNotEmpty:
            host.removeTask(host.tasks[random.nextInt(host.tasks.length)].id);
          case 4 when host.tasks.isNotEmpty:
            final task = host.tasks[random.nextInt(host.tasks.length)];
            host.edit(
              task.id,
              (t) =>
                  t.subtasks.add(SubTask(id: 'sub$step', title: 'Sub $step')),
            );
          default:
            await device.engine.sync();
        }
      }
      for (var pass = 0; pass < 2; pass++) {
        for (final device in devices) {
          await device.engine.sync();
        }
      }
      expect(
        devices[1].host.view(),
        devices[0].host.view(),
        reason: 'seed $seed',
      );
      expect(
        devices[2].host.view(),
        devices[0].host.view(),
        reason: 'seed $seed',
      );
    }
  });
}
