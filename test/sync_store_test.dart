// The store side of sync: snapshot, the guarded commit, validation and
// rollback, and a store converging with another device through the engine.
import 'package:compoise/models.dart';
import 'package:compoise/storage.dart';
import 'package:compoise/sync/sync_engine.dart';
import 'package:compoise/sync/sync_library.dart';
import 'package:compoise/sync/sync_local.dart';
import 'package:compoise/sync/sync_remote.dart';
import 'package:compoise/sync/sync_store_host.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';
import 'sync_fakes.dart';

Board _board(String id, [String name = 'Board']) =>
    Board(id: id, name: name, createdAt: 1);

Task _task(String id, String title, {String boardId = 'b1'}) =>
    Task(id: id, boardId: boardId, title: title, quadrant: 1, createdAt: 10);

SyncLibrary _copy(
  SyncLibrary from, {
  List<Map<String, dynamic>>? boards,
  List<Map<String, dynamic>>? tasks,
  List<Map<String, dynamic>>? schedule,
  Map<String, Object?>? settings,
}) => SyncLibrary(
  boards: boards ?? from.boards,
  tasks: tasks ?? from.tasks,
  scheduleItems: schedule ?? from.scheduleItems,
  settings: {...from.settings, ...?settings},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the snapshot carries the live library and its revision', () async {
    final (store, _) = await makeStore(
      boards: [_board('b1')],
      tasks: [_task('t1', 'One')],
    );
    final snapshot = store.captureSyncSnapshot();
    expect(snapshot.revision, store.syncRevision);
    expect([for (final task in snapshot.library.tasks) task['id']], ['t1']);
    expect(snapshot.library.settings['comicOutline'], isFalse);
    store.addTasks([_task('t2', 'Two')]);
    expect(store.syncRevision, greaterThan(snapshot.revision));
    expect(store.syncLibraryDurable, isFalse);
    await store.flush(waitForReminders: false);
    expect(store.syncLibraryDurable, isTrue);
  });

  test('apply replaces the synced library in one durable commit', () async {
    final (store, _) = await makeStore(
      boards: [_board('b1')],
      tasks: [_task('t1', 'One'), _task('t2', 'Two')],
    );
    store.setFontSize(FontSizePref.large);
    await store.flush(waitForReminders: false);
    final snapshot = store.captureSyncSnapshot();
    final renamed = {...snapshot.library.tasks.first, 'title': 'One, renamed'};
    final library = _copy(
      snapshot.library,
      boards: [...snapshot.library.boards, _board('b2', 'Second').toJson()],
      tasks: [
        renamed,
        _task('t3', 'Three', boardId: 'b2').toJson(),
      ],
      schedule: [
        {
          'id': 's1',
          'kind': 'timeBlock',
          'taskId': 't3',
          'startAt': 1000,
          'endAt': 2000,
          'timeZoneId': 'UTC',
        },
      ],
      settings: {'theme': 'dark', 'urgencyThresholdDays': 99},
    );
    final t1Revision = store.taskSeq('t1');

    final outcome = await store.applySyncLibrary(snapshot.revision, library);

    expect(outcome, SyncApplyOutcome.applied);
    expect(
      [for (final task in store.tasks) task.title],
      ['One, renamed', 'Three'],
    );
    expect(store.boards.map((board) => board.id), ['b1', 'b2']);
    expect(store.scheduleItems.single.id, 's1');
    expect(store.settings.theme.name, 'dark');
    expect(store.settings.urgencyThresholdDays, 14);
    // Device-only preferences are not part of the synced settings.
    expect(store.settings.fontSize, FontSizePref.large);
    expect(store.taskSeq('t1'), greaterThan(t1Revision));
    expect(store.syncLibraryDurable, isTrue);
    expect(store.syncAppliedRevision, store.syncRevision);

    store.dispose();
    final restarted = await openStoreFromPrefs();
    expect([for (final task in restarted.tasks) task.id], ['t1', 't3']);
    expect(restarted.scheduleItems.single.taskId, 't3');
    expect(restarted.settings.fontSize, FontSizePref.large);
  });

  test('an edit accepted after the snapshot makes the apply stale', () async {
    final (store, _) = await makeStore(
      boards: [_board('b1')],
      tasks: [_task('t1', 'One')],
    );
    final snapshot = store.captureSyncSnapshot();
    store.addTasks([_task('t2', 'Typed meanwhile')]);
    final outcome = await store.applySyncLibrary(
      snapshot.revision,
      _copy(snapshot.library, tasks: const []),
    );
    expect(outcome, SyncApplyOutcome.stale);
    expect(store.tasks.map((task) => task.id).toSet(), {'t1', 't2'});
  });

  test('a library this build cannot accept fails untouched', () async {
    final (store, _) = await makeStore(
      boards: [_board('b1')],
      tasks: [_task('t1', 'One')],
    );
    final snapshot = store.captureSyncSnapshot();
    final broken = [
      _copy(snapshot.library, boards: const []),
      _copy(
        snapshot.library,
        tasks: [_task('t2', 'Lost', boardId: 'missing').toJson()],
      ),
      _copy(
        snapshot.library,
        tasks: [_task('t2', 'A').toJson(), _task('t2', 'B').toJson()],
      ),
      _copy(
        snapshot.library,
        schedule: [
          {
            'id': 's1',
            'kind': 'timeBlock',
            'taskId': 'nobody',
            'startAt': 1,
            'endAt': 2,
            'timeZoneId': 'UTC',
          },
        ],
      ),
      _copy(
        snapshot.library,
        tasks: [
          {..._task('t2', 'Bad').toJson(), 'title': 42},
        ],
      ),
    ];
    for (final library in broken) {
      expect(
        await store.applySyncLibrary(store.syncRevision, library),
        SyncApplyOutcome.failed,
      );
    }
    expect(store.tasks.single.id, 't1');
    expect(store.boards.single.id, 'b1');
    expect(store.syncLibraryDurable, isTrue);
  });

  test('a failed commit puts the library back', () async {
    var failing = false;
    final (store, _) = await makeStore(
      boards: [_board('b1')],
      tasks: [_task('t1', 'One')],
      saveWriter: (key, value) async {
        if (failing && key.startsWith('compoise-save-')) return false;
        return (await SharedPreferences.getInstance()).setString(key, value);
      },
    );
    final snapshot = store.captureSyncSnapshot();
    failing = true;
    final outcome = await store.applySyncLibrary(
      snapshot.revision,
      _copy(snapshot.library, tasks: [_task('t9', 'Never saved').toJson()]),
    );
    expect(outcome, SyncApplyOutcome.failed);
    expect(store.tasks.single.id, 't1');
    expect(store.syncLibraryDurable, isFalse);
    failing = false;
    expect((await store.retrySave(waitForReminders: false)).success, isTrue);
    expect(store.syncLibraryDurable, isTrue);
    expect(store.tasks.single.id, 't1');
  });

  test('the active board moves when sync removes it', () async {
    final (store, _) = await makeStore(
      boards: [_board('b1'), _board('b2')],
      tasks: [_task('t1', 'One', boardId: 'b2')],
    );
    store.setActiveBoard('b2');
    await store.flush(waitForReminders: false);
    final snapshot = store.captureSyncSnapshot();
    final outcome = await store.applySyncLibrary(
      snapshot.revision,
      _copy(snapshot.library, boards: [_board('b1').toJson()], tasks: const []),
    );
    expect(outcome, SyncApplyOutcome.applied);
    expect(store.activeBoardId, 'b1');
  });

  test('the host refuses to stamp a store that is not ready', () {
    final host = StoreSyncHost(Store());
    expect(host.capture, throwsStateError);
  });

  test('a store and another device converge through the engine', () async {
    final (store, _) = await makeStore(
      boards: [_board('b1', 'Home')],
      tasks: [_task('t1', 'From the store')],
    );
    final remote = MemorySyncRemote();
    final clock = TestClock();
    final engine = SyncEngine(
      host: StoreSyncHost(store),
      localStore: MemorySyncLocalStore(),
      keyStore: MemorySyncKeyStore(),
      deviceName: 'Store device',
      platform: 'test',
      appVersion: '1.2.0',
      runner: inlineSyncRunner,
      nowMs: clock.call,
      inlineKdf: true,
    );
    await engine.load();
    expect(await engine.createVault(remote, provider: 'memory'), isNotNull);

    final other = Device(remote, name: 'Other', clock: clock.call);
    await other.load();
    expect(await other.engine.joinVault(remote, provider: 'memory'), isNotNull);
    expect(other.host.task('t1').title, 'From the store');

    other.host.addTask('t2', 'From the other device');
    await other.engine.sync();
    expect(await engine.sync(), isNotNull);
    expect(store.tasks.map((task) => task.id).toSet(), {'t1', 't2'});

    final edited = Task.fromJson(
      store.tasks.firstWhere((task) => task.id == 't1').toJson(),
    )..title = 'Edited in the store';
    store.updateTask(edited);
    await store.flush(waitForReminders: false);
    await engine.absorbLocalEdits();
    await engine.sync();
    await other.engine.sync();
    expect(other.host.task('t1').title, 'Edited in the store');

    store.dispose();
    final restarted = await openStoreFromPrefs();
    expect(restarted.tasks.map((task) => task.id).toSet(), {'t1', 't2'});
  });
}

/// A second store over the same mock preferences, like a restart.
Future<Store> openStoreFromPrefs() async {
  final store = Store();
  registerTestStore(store);
  await store.init();
  await store.flush(waitForReminders: false);
  return store;
}
