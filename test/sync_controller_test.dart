// When the app syncs: setup, edit debouncing, backoff, blocking problems,
// background handoff and disconnect. Timers are driven by hand.
import 'package:compoise/sync/sync_controller.dart';
import 'package:compoise/sync/sync_engine.dart';
import 'package:compoise/sync/sync_local.dart';
import 'package:compoise/sync/sync_provider.dart';
import 'package:compoise/sync/sync_remote.dart';
import 'package:compoise/sync/webdav_remote.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sync_controller_fakes.dart';
import 'sync_fakes.dart';

const absorb = Duration(seconds: 4);
const editSync = Duration(seconds: 20);
const startup = Duration(seconds: 3);
const periodic = Duration(minutes: 10);

const webdavConfig = SyncProviderConfig(
  kind: SyncProviderKind.webdav,
  deviceName: 'Laptop',
  webdav: WebDavSettings(url: 'https://dav.example.com/dav/', username: 'me'),
);

class Rig {
  Rig({MemorySyncRemote? remote, TestClock? clock})
    : remote = remote ?? MemorySyncRemote(),
      clock = clock ?? TestClock();

  final MemorySyncRemote remote;
  final TestClock clock;
  final host = SourceHost();
  final local = MemorySyncLocalStore();
  final keys = MemorySyncKeyStore();
  final secret = MemoryCredentials();
  final timers = ManualTimers();
  DateTime now = DateTime.utc(2025, 1, 1);
  final secretsSeen = <String>[];
  late SyncEngine engine;
  late SyncController controller;

  SyncController build() {
    engine = SyncEngine(
      host: host,
      localStore: local,
      keyStore: keys,
      deviceName: 'unnamed',
      platform: 'test',
      appVersion: '1.2.0',
      runner: inlineSyncRunner,
      nowMs: clock.call,
      inlineKdf: true,
    );
    controller = SyncController(
      engine: engine,
      source: host,
      localStore: local,
      secrets: SyncSecrets(vaultKey: MemoryCredentials(), provider: secret),
      remoteFactory: (config, value, _) {
        secretsSeen.add(value);
        return remote;
      },
      timer: timers.call,
      now: () => now,
    );
    return controller;
  }

  Future<SyncController> start() async {
    build();
    await controller.start();
    return controller;
  }

  /// A restart over the same files and secure storage.
  Future<SyncController> restart() async {
    controller.dispose();
    return start();
  }

  bool get uploaded => remote.log.any((line) => line.startsWith('write dev-'));
}

void main() {
  test('connect creates a vault and saves the connection', () async {
    final rig = Rig();
    final controller = await rig.start();
    expect(controller.joined, isFalse);
    expect(rig.timers.active, [periodic]);

    rig.host.addTask('t1', 'Before sync');
    final report = await controller.connect(webdavConfig, 'pw');
    expect(report, isNotNull);
    expect(controller.connected, isTrue);
    expect(rig.secret.value, 'pw');
    expect(
      SyncProviderConfig.decode(rig.local.provider)?.webdav?.username,
      'me',
    );
    expect(rig.engine.deviceName, 'Laptop');
    expect(rig.remote.files.keys, contains('vault.json'));
    expect(rig.uploaded, isTrue);

    final restarted = await rig.restart();
    expect(restarted.connected, isTrue);
    expect(restarted.config?.deviceName, 'Laptop');
    expect(rig.secretsSeen.last, 'pw');
    expect(rig.timers.active, containsAll([startup, periodic]));
    rig.remote.log.clear();
    await rig.timers.fire(startup);
    expect(rig.remote.log, contains('list'));
  });

  test('edits are stamped soon and uploaded a little later', () async {
    final rig = Rig();
    final controller = await rig.start();
    await controller.connect(webdavConfig, 'pw');
    rig.remote.log.clear();

    rig.host.userEdit('t1', 'One');
    expect(rig.timers.active, containsAll([absorb, editSync]));
    final stateBefore = rig.local.state;
    await rig.timers.fire(absorb);
    expect(rig.local.state, isNot(stateBefore), reason: 'edit stamped');
    expect(rig.remote.log, isEmpty, reason: 'still offline');

    rig.host.userEdit('t2', 'Two');
    expect(rig.timers.active.where((delay) => delay == editSync), hasLength(1));
    await rig.timers.fire(editSync);
    expect(rig.uploaded, isTrue);
  });

  test('a downloaded change schedules nothing more', () async {
    final rig = Rig();
    final controller = await rig.start();
    await controller.connect(webdavConfig, 'pw');
    final other = Device(rig.remote, name: 'Other', clock: rig.clock.call);
    await other.load();
    await other.engine.joinVault(rig.remote, provider: 'webdav');
    other.host.addTask('t9', 'From the other device');
    await other.engine.sync();

    await controller.syncNow();
    expect(rig.host.hasTask('t9'), isTrue);
    expect(rig.timers.active, [periodic]);
  });

  test('failures back off and a success resets the delay', () async {
    final rig = Rig();
    final controller = await rig.start();
    await controller.connect(webdavConfig, 'pw');
    rig.remote.failNext(
      'list',
      const SyncRemoteException(SyncRemoteFailure.network),
      times: 3,
    );
    await controller.syncNow();
    expect(controller.status.phase, SyncPhase.error);
    expect(controller.nextRetryAt, rig.now.add(const Duration(seconds: 30)));
    await rig.timers.fire(const Duration(seconds: 30));
    await rig.timers.fire(const Duration(minutes: 1));
    expect(rig.timers.active, contains(const Duration(minutes: 2)));
    await rig.timers.fire(const Duration(minutes: 2));
    expect(controller.status.phase, SyncPhase.idle);
    expect(controller.nextRetryAt, isNull);
    expect(rig.timers.active, [periodic]);
  });

  test('a longer Retry-After wins over the backoff', () async {
    final rig = Rig();
    final controller = await rig.start();
    await controller.connect(webdavConfig, 'pw');
    rig.remote.failNext(
      'list',
      const SyncRemoteException(
        SyncRemoteFailure.rateLimited,
        '',
        Duration(minutes: 5),
      ),
    );
    await controller.syncNow();
    expect(rig.timers.active, contains(const Duration(minutes: 5)));
  });

  test('sign-in problems stop automatic rounds until the user acts', () async {
    final rig = Rig();
    final controller = await rig.start();
    await controller.connect(webdavConfig, 'pw');
    rig.remote.failNext(
      'list',
      const SyncRemoteException(SyncRemoteFailure.auth),
    );
    await controller.syncNow();
    expect(controller.status.phase, SyncPhase.needsAttention);
    expect(controller.nextRetryAt, isNull);

    rig.remote.log.clear();
    rig.host.userEdit('t1', 'Typed while signed out');
    await rig.timers.fire(editSync);
    await rig.timers.fire(periodic);
    expect(rig.remote.log, isEmpty);

    expect(await controller.updateSecret('new password'), isNotNull);
    expect(rig.secret.value, 'new password');
    expect(controller.status.phase, SyncPhase.idle);
    expect(rig.uploaded, isTrue);
  });

  test('a missing secret asks to sign in again', () async {
    final rig = Rig();
    final controller = await rig.start();
    await controller.connect(webdavConfig, 'pw');
    rig.secret.value = null;
    final restarted = await rig.restart();
    expect(restarted.problem, SyncConnectionProblem.missingSecret);
    expect(await restarted.syncNow(), isNull);

    rig.secret.failRead = true;
    final locked = await rig.restart();
    expect(locked.problem, SyncConnectionProblem.secureStorage);
    rig.secret.failRead = false;

    expect(await locked.updateSecret('pw'), isNotNull);
    expect(locked.problem, isNull);
  });

  test('going to the background uploads pending edits at once', () async {
    final rig = Rig();
    final controller = await rig.start();
    await controller.connect(webdavConfig, 'pw');
    rig.remote.log.clear();
    rig.host.userEdit('t1', 'Typed just before leaving');
    controller.setForeground(false);
    expect(rig.timers.active, contains(Duration.zero));
    expect(rig.timers.active, isNot(contains(periodic)));
    await rig.timers.fire(Duration.zero);
    expect(rig.uploaded, isTrue);

    rig.remote.log.clear();
    rig.now = rig.now.add(const Duration(minutes: 5));
    controller.setForeground(true);
    expect(rig.timers.active, containsAll([Duration.zero, periodic]));
    await rig.timers.fire(Duration.zero);
    expect(rig.remote.log, contains('list'));
  });

  test('a library that is not saved yet is not synced', () async {
    final rig = Rig();
    final controller = await rig.start();
    await controller.connect(webdavConfig, 'pw');
    rig.host.durable = false;
    rig.remote.log.clear();
    expect(await controller.syncNow(), isNull);
    expect(rig.remote.log, isEmpty);
    expect(controller.nextRetryAt, isNotNull);
  });

  test('a failed connect saves nothing', () async {
    final rig = Rig();
    final owner = Device(rig.remote, name: 'Owner', clock: rig.clock.call);
    await owner.load();
    await owner.engine.createVault(
      rig.remote,
      provider: 'webdav',
      password: 'vault password',
    );
    final controller = await rig.start();
    await expectLater(
      controller.connect(webdavConfig, 'pw'),
      throwsA(
        isA<SyncSetupException>().having(
          (error) => error.kind,
          'kind',
          SyncSetupError.passwordRequired,
        ),
      ),
    );
    expect(controller.joined, isFalse);
    expect(rig.local.provider, isNull);
    expect(rig.secret.value, isNull);

    expect(
      await controller.connect(webdavConfig, 'pw', password: 'vault password'),
      isNotNull,
    );
    expect(controller.connected, isTrue);
  });

  test('disconnect forgets the connection and keeps the library', () async {
    final rig = Rig();
    final controller = await rig.start();
    rig.host.addTask('t1', 'Stays');
    await controller.connect(webdavConfig, 'pw');
    await controller.disconnect(deleteOwnFile: true);
    expect(controller.joined, isFalse);
    expect(controller.config, isNull);
    expect(rig.local.provider, isNull);
    expect(rig.secret.value, isNull);
    expect(rig.host.hasTask('t1'), isTrue);
    expect(rig.remote.files.keys, ['vault.json']);
    rig.host.userEdit('t2', 'After leaving');
    expect(rig.timers.active, [periodic]);
  });
}
