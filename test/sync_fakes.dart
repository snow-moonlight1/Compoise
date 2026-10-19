// Shared fakes for the sync tests: a library host that behaves like the
// store's sync commit (stale check, model validation) without Flutter UI.
import 'package:compoise/models.dart';
import 'package:compoise/schedule_item.dart';
import 'package:compoise/sync/sync_engine.dart';
import 'package:compoise/sync/sync_library.dart';
import 'package:compoise/sync/sync_local.dart';
import 'package:compoise/sync/sync_remote.dart';

class FakeHost implements SyncHost {
  FakeHost({String boardId = 'inbox', String boardName = 'Inbox'})
    : boards = [Board(id: boardId, name: boardName, createdAt: 1)];

  List<Board> boards;
  List<Task> tasks = [];
  List<ScheduleItem> schedule = [];
  AppSettings settings = AppSettings();
  int revision = 0;
  int applies = 0;

  /// Runs once inside the next [apply], before the stale check, like a user
  /// edit that lands while the sync commit is queued.
  void Function()? duringApply;
  bool failApply = false;

  @override
  SyncSnapshot capture() => SyncSnapshot(
    revision: revision,
    library: SyncLibrary.fromModels(
      boards: boards,
      tasks: tasks,
      scheduleItems: schedule,
      settings: settings,
    ),
  );

  @override
  Future<SyncApplyOutcome> apply(int baseRevision, SyncLibrary library) async {
    final hook = duringApply;
    duringApply = null;
    hook?.call();
    if (baseRevision != revision) return SyncApplyOutcome.stale;
    if (failApply) return SyncApplyOutcome.failed;
    boards = [for (final json in library.boards) Board.fromJson(json)];
    tasks = [for (final json in library.tasks) Task.fromJson(json)];
    schedule = [
      for (final json in library.scheduleItems) ScheduleItem.fromJson(json),
    ];
    settings = AppSettings.fromJson(
      overlaySettings(settings.toJson(), library.settings),
    );
    revision++;
    applies++;
    return SyncApplyOutcome.applied;
  }

  // --- edits, each bumping the revision like a store command ---

  Task addTask(String id, String title, {String? boardId, int quadrant = 1}) {
    final task = Task(
      id: id,
      boardId: boardId ?? boards.first.id,
      title: title,
      quadrant: quadrant,
      createdAt: 1000 + tasks.length,
    );
    tasks.add(task);
    revision++;
    return task;
  }

  Task task(String id) => tasks.firstWhere((task) => task.id == id);

  bool hasTask(String id) => tasks.any((task) => task.id == id);

  void edit(String id, void Function(Task task) change) {
    change(task(id));
    revision++;
  }

  void removeTask(String id) {
    tasks.removeWhere((task) => task.id == id);
    schedule.removeWhere((item) => item.taskId == id);
    revision++;
  }

  void addBoard(String id, String name) {
    boards.add(Board(id: id, name: name, createdAt: 2 + boards.length));
    revision++;
  }

  void removeBoard(String id) {
    boards.removeWhere((board) => board.id == id);
    tasks.removeWhere((task) => task.boardId == id);
    revision++;
  }

  /// Comparable view of the synced library.
  Map<String, Object?> view() {
    final library = capture().library;
    return {
      'boards': library.boards,
      'tasks': library.tasks,
      'schedule': [...library.scheduleItems]
        ..sort((a, b) => '${a['id']}'.compareTo('${b['id']}')),
      'settings': library.settings,
    };
  }
}

class Device {
  Device(
    this.remote, {
    required this.name,
    int Function()? clock,
    FakeHost? host,
  }) : host = host ?? FakeHost(),
       local = MemorySyncLocalStore(),
       keys = MemorySyncKeyStore() {
    engine = SyncEngine(
      host: this.host,
      localStore: local,
      keyStore: keys,
      deviceName: name,
      platform: 'test',
      appVersion: '1.2.0',
      runner: inlineSyncRunner,
      nowMs: clock,
      inlineKdf: true,
    );
  }

  final SyncRemote remote;
  final String name;
  final FakeHost host;
  final MemorySyncLocalStore local;
  final MemorySyncKeyStore keys;
  late final SyncEngine engine;

  Future<void> load() => engine.load();
}

/// Wall clock for tests: starts at 2025-01-01 and advances 1 s per call.
class TestClock {
  TestClock([this.ms = 1735689600000]);

  int ms;

  int call() => ms += 1000;
}
