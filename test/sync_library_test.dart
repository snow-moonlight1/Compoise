import 'package:compoise/models.dart';
import 'package:compoise/schedule_item.dart';
import 'package:compoise/sync/sync_library.dart';
import 'package:compoise/sync/sync_state.dart';
import 'package:flutter_test/flutter_test.dart';

SyncLibrary _library({
  List<Board>? boards,
  List<Task>? tasks,
  List<ScheduleItem>? schedule,
  AppSettings? settings,
}) => SyncLibrary.fromModels(
  boards: boards ?? [Board(id: 'b1', name: 'Inbox', createdAt: 1)],
  tasks: tasks ?? const [],
  scheduleItems: schedule ?? const [],
  settings: settings ?? AppSettings(),
);

Task _task(String id, {String board = 'b1', List<SubTask>? subtasks}) => Task(
  id: id,
  boardId: board,
  title: 'Task $id',
  quadrant: 2,
  createdAt: 100,
  subtasks: subtasks,
  tags: const ['work'],
  deadline: 5000,
  notesMarkdown: '**n**',
);

void main() {
  test('subtask keys survive ids that contain colons', () {
    final key = subtaskKey('a:b', 'c:d');
    expect(parseSubtaskKey(key), ('a:b', 'c:d'));
    expect(parseSubtaskKey('s:x'), isNull);
    expect(parseSubtaskKey('s:3:ab:c'), isNull);
    expect(parseSubtaskKey('t:1'), isNull);
  });

  test('absorb then derive reproduces the library', () {
    final live = _library(
      boards: [
        Board(id: 'b1', name: 'Inbox', createdAt: 1),
        Board(id: 'b2', name: 'Work', createdAt: 2),
      ],
      tasks: [
        _task(
          't1',
          subtasks: [
            SubTask(id: 's1', title: 'first', deadline: 10),
            SubTask(id: 's2', title: 'second', completed: true, completedAt: 9),
          ],
        ),
        _task('t2', board: 'b2'),
      ],
      schedule: [
        ScheduleItem.timeBlock(
          id: 'e1',
          taskId: 't1',
          startAt: 1000,
          endAt: 2000,
          timeZoneId: 'Asia/Shanghai',
        ),
        ScheduleItem.event(
          id: 'e0',
          title: 'Standup',
          boardId: 'b2',
          startAt: 3000,
          endAt: 4000,
          timeZoneId: 'UTC',
        ),
      ],
      settings: AppSettings(language: Language.zh, neumorphic: true),
    );
    final state = SyncState();
    absorbLibrary(state, live, 10);
    final derived = deriveLibrary(state);
    expect(derived.sameContentAs(live), isTrue);
    expect(derived.boards.map((b) => b['id']), ['b1', 'b2']);
    expect(derived.tasks.first['subtasks'], live.tasks.first['subtasks']);
    expect(derived.settings['language'], 'zh');
    expect(derived.settings['neumorphic'], true);

    // Absorbing the same library again records nothing.
    final before = state.digest();
    absorbLibrary(state, live, 11);
    expect(state.digest(), before);
  });

  test('absorb stamps only the fields that changed, and deletions', () {
    final state = SyncState();
    final t1 = _task(
      't1',
      subtasks: [SubTask(id: 's1', title: 'a')],
    );
    absorbLibrary(state, _library(tasks: [t1, _task('t2')]), 10);
    final edited = _task('t1', subtasks: const [])..title = 'renamed';
    absorbLibrary(state, _library(tasks: [edited]), 20);
    final record = state.records['t:t1']!;
    expect(record.clocks['title'], 20);
    expect(record.clocks['notesMarkdown'], 10);
    expect(state.tombstones['t:t2'], 20);
    expect(state.tombstones[subtaskKey('t1', 's1')], 20);
    expect(deriveLibrary(state).tasks.single['title'], 'renamed');
  });

  test('turning an appearance switch off is recorded', () {
    final state = SyncState();
    absorbLibrary(
      state,
      _library(settings: AppSettings(comicOutline: true)),
      1,
    );
    absorbLibrary(state, _library(settings: AppSettings()), 2);
    expect(deriveLibrary(state).settings['comicOutline'], false);
  });

  test('device-only settings never enter the state', () {
    final state = SyncState();
    absorbLibrary(
      state,
      _library(
        settings: AppSettings(
          fontSize: FontSizePref.values.last,
          closeToTray: true,
          globalShortcut: 'Ctrl+Q',
        ),
      ),
      1,
    );
    final fields = state.records[settingsKey]!.fields.keys;
    expect(fields, isNot(contains('fontSize')));
    expect(fields, isNot(contains('closeToTray')));
    expect(fields, isNot(contains('globalShortcut')));
    expect(fields, isNot(contains('viewMode')));
    final local = AppSettings(closeToTray: true).toJson();
    final merged = overlaySettings(local, {'language': 'ja'});
    expect(merged['closeToTray'], true);
    expect(merged['language'], 'ja');
  });

  test('records this build cannot read are kept, not deleted', () {
    final state = SyncState();
    absorbLibrary(state, _library(tasks: [_task('t1')]), 1);
    // A newer version wrote a schedule kind this build does not know.
    state.setField('e:future', 'v', {'kind': 'hologram', 'startAt': 1}, 2);
    final derived = deriveLibrary(state);
    expect(derived.scheduleItems, isEmpty);
    absorbLibrary(state, derived, 3);
    expect(state.isAlive('e:future'), isTrue);
  });

  test('derive repairs what concurrent edits can produce', () {
    final state = SyncState();
    absorbLibrary(
      state,
      _library(
        boards: [
          Board(id: 'b1', name: 'Inbox', createdAt: 1),
          Board(id: 'b2', name: 'Work', createdAt: 2),
        ],
        tasks: [_task('t1', board: 'b2')],
        schedule: [
          ScheduleItem.timeBlock(
            id: 'e1',
            taskId: 't1',
            startAt: 1,
            endAt: 2,
            timeZoneId: 'UTC',
          ),
        ],
      ),
      1,
    );
    // Device A deletes board b2; device B moved... nothing: t1 is still on b2.
    state.tombstone('b:b2', 5);
    state.setField('t:t1', 'title', 'edited on B', 6);
    var derived = deriveLibrary(state);
    expect(derived.tasks.single['boardId'], 'b1', reason: 'orphan moves');
    expect(derived.scheduleItems, hasLength(1));

    // Both remaining boards deleted on different devices: the newest returns.
    state.tombstone('b:b1', 7);
    derived = deriveLibrary(state);
    expect(derived.boards, hasLength(1));
    expect(derived.tasks, hasLength(1));

    // A time block whose task is gone is dropped.
    state.tombstone('t:t1', 9);
    derived = deriveLibrary(state);
    expect(derived.tasks, isEmpty);
    expect(derived.scheduleItems, isEmpty);
  });

  test('subtasks deleted with their task come back with it', () {
    final state = SyncState();
    final task = _task(
      't1',
      subtasks: [
        SubTask(id: 'gone', title: 'deleted first'),
        SubTask(id: 'kept', title: 'with parent'),
      ],
    );
    absorbLibrary(state, _library(tasks: [task]), 1);
    absorbLibrary(
      state,
      _library(
        tasks: [
          _task(
            't1',
            subtasks: [SubTask(id: 'kept', title: 'with parent')],
          ),
        ],
      ),
      2,
    );
    absorbLibrary(state, _library(), 3); // task deleted
    expect(deriveLibrary(state).tasks, isEmpty);
    // Another device edited the task concurrently.
    state.setField('t:t1', 'title', 'still needed', 4);
    final subs = deriveLibrary(state).tasks.single['subtasks'] as List;
    expect(subs.map((s) => s['id']), ['kept']);
  });

  test('derive is deterministic regardless of record order', () {
    final a = SyncState();
    absorbLibrary(a, _library(tasks: [_task('t2'), _task('t1')]), 1);
    final b = SyncState();
    for (final key in a.records.keys.toList().reversed) {
      final record = a.records[key]!;
      for (final field in record.clocks.keys) {
        b.setField(key, field, record.fields[field], record.clocks[field]!);
      }
    }
    expect(
      deriveLibrary(b).tasks.map((t) => t['id']),
      deriveLibrary(a).tasks.map((t) => t['id']),
    );
    expect(deriveLibrary(a).tasks.map((t) => t['id']), ['t2', 't1']);
  });

  test('pending restore blocks sync', () {
    final task = _task('t1')..recoveryPending = {'title': 'x'};
    expect(_library(tasks: [task]).hasPendingRestore, isTrue);
    expect(_library(tasks: [_task('t1')]).hasPendingRestore, isFalse);
  });

  test('a record revived without its content is left out', () {
    final state = SyncState()..setField('t:ghost', 'title', 'only a title', 5);
    absorbLibrary(state, _library(), 1);
    expect(deriveLibrary(state).tasks, isEmpty);
  });
}
