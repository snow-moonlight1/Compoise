import 'dart:convert';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/schedule_item.dart';
import 'package:matrixflow_native/storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'rf02_import_commit_race_test.dart' as race;

const _start = 1790701200000;

Board _board(String id) => Board(id: id, name: id, createdAt: 1);
Task _task(String id, {String boardId = 'b'}) => Task(
  id: id,
  boardId: boardId,
  title: id,
  quadrant: 2,
  createdAt: 1,
  plannedDate: 1790697600000,
  deadline: 1900000000000,
  reminderAt: 1899990000000,
  notesMarkdown: 'notes',
  tags: ['tag'],
);
ScheduleItem _block(String id, {String taskId = 't', int delta = 0}) =>
    ScheduleItem.timeBlock(
      id: id,
      taskId: taskId,
      startAt: _start + delta,
      endAt: _start + delta + 3600000,
      timeZoneId: 'Asia/Shanghai',
    );
ScheduleItem _event(String id, {String boardId = 'b', String title = '会议'}) =>
    ScheduleItem.event(
      id: id,
      boardId: boardId,
      title: title,
      startAt: _start,
      endAt: _start + 7200000,
      timeZoneId: 'UTC',
    );
Map<String, dynamic> _payload({List<ScheduleItem>? items}) => {
  'version': 3,
  'boards': [_board('b').toJson()],
  'tasks': [_task('t').toJson()],
  'scheduleItems': (items ?? [_block('block'), _event('event')])
      .map((item) => item.toJson())
      .toList(),
  'settings': AppSettings(language: Language.ja).toJson(),
  'aiConfig': AIConfig().toJson(),
};
ImportPlan _inspect(
  Map<String, dynamic> payload, {
  String mode = 'overwrite',
  List<Board> boards = const [],
  List<Task> tasks = const [],
  List<ScheduleItem> items = const [],
  String? target,
}) => ImportPreflight.inspect(
  payload,
  mode,
  currentBoards: boards,
  currentTasks: tasks,
  currentScheduleItems: items,
  targetBoardId: target,
  revision: 0,
);

Future<Store> _open({SaveWrite? writer, CredentialStore? credentials}) async {
  final store = Store(saveWriter: writer, credentialStore: credentials);
  await store.init();
  await store.flush();
  return store;
}

Future<Store> _seed({SaveWrite? writer, CredentialStore? credentials}) async {
  SharedPreferences.setMockInitialValues({
    'matrixflow-boards': jsonEncode([_board('b').toJson()]),
    'matrixflow-tasks': jsonEncode([_task('t').toJson()]),
    SaveProtocol.scheduleKey: jsonEncode([_block('old').toJson()]),
  });
  return _open(writer: writer, credentials: credentials);
}

String _canonical(Store store) => jsonEncode({
  'boards': store.boards.map((b) => b.toJson()).toList(),
  'tasks': store.tasks.map((t) => t.toJson()).toList(),
  'scheduleItems': store.scheduleItems.map((s) => s.toJson()).toList(),
  'settings': store.settings.toJson(),
  'aiConfig': store.aiConfig.toJson(),
  'activeBoardId': store.activeBoardId,
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('default v3 round trips both event associations and task fields', () {
    final linked = ScheduleItem.event(
      id: 'linked',
      title: '评审',
      taskId: 't',
      startAt: _start,
      endAt: _start + 1,
      timeZoneId: 'America/New_York',
    );
    final data = ExportData(
      boards: [_board('b')],
      tasks: [_task('t')],
      scheduleItems: [_block('block'), _event('event'), linked],
      settings: AppSettings(),
      aiConfig: AIConfig(),
      timestamp: 1,
    );
    final json = data.toJson();
    expect(json['version'], 3);
    expect(ExportData.fromJson(json).toJson(), json);
    final migration = DataMigrator.migratePayload(json);
    expect(migration.targetVersion, 3);
    expect(
      migration.scheduleItems.map((s) => s.toJson()).toList(),
      json['scheduleItems'],
    );
    expect(migration.tasks.single.toJson(), _task('t').toJson());
  });

  for (final version in [null, 1, 2]) {
    test(
      'legacy $version ignores and reports a coincidental schedule field',
      () {
        final payload = _payload()..['scheduleItems'] = 'corrupt unknown field';
        if (version == null) {
          payload.remove('version');
        } else {
          payload['version'] = version;
        }
        final plan = _inspect(payload);
        expect(plan.scheduleItems, isEmpty);
        expect(plan.warnings.join(' '), contains('scheduleItems'));
        expect(DataMigrator.migratePayload(payload).scheduleItems, isEmpty);
        expect(ExportData.fromJson(payload).scheduleItems, isEmpty);
        expect(plan.tasks.single.plannedDate, _task('t').plannedDate);
      },
    );
  }

  for (final value in [null, {}, '[]', 1]) {
    test('v3 requires an array: $value', () {
      final payload = _payload()..['scheduleItems'] = value;
      expect(() => _inspect(payload), throwsFormatException);
      expect(() => DataMigrator.migratePayload(payload), throwsFormatException);
      expect(() => ExportData.fromJson(payload), throwsFormatException);
    });
  }

  final corruptions = <String, Map<String, dynamic>>{
    'blank id': {'id': ' '},
    'unknown kind': {'kind': 'recurring'},
    'fractional time': {'startAt': _start + 0.5},
    'time type': {'startAt': '1790701200000'},
    'zero interval': {'endAt': _start},
    'reversed interval': {'endAt': _start - 1},
    'out of range': {'endAt': 8640000000000001},
    'unknown timezone': {'timeZoneId': 'Mars/Olympus'},
    'missing parent': {'taskId': 'gone'},
    'child is not parent': {'taskId': 'child'},
    'block with board': {'boardId': 'b'},
    'block with title': {'title': 'x'},
  };
  for (final entry in corruptions.entries) {
    test('rejects schedule corruption: ${entry.key}', () {
      final payload = _payload(items: [_block('block')]);
      (payload['tasks'] as List).single['subtasks'] = [
        {'id': 'child', 'title': 'Child', 'completed': false},
      ];
      (payload['scheduleItems'] as List).single.addAll(entry.value);
      expect(() => _inspect(payload), throwsFormatException);
      expect(() => DataMigrator.migratePayload(payload), throwsFormatException);
    });
  }

  test('rejects invalid independent event association and blank title', () {
    for (final patch in [
      {'boardId': 'gone'},
      {'taskId': 't'},
      {'title': ' '},
      {'boardId': null},
    ]) {
      final payload = _payload(items: [_event('event')]);
      (payload['scheduleItems'] as List).single.addAll(patch);
      expect(() => _inspect(payload), throwsFormatException);
    }
  });

  test(
    'duplicate schedule id in a file is rejected even for identical content',
    () {
      for (final duplicate in [_block('block'), _block('block', delta: 1)]) {
        final payload = _payload(items: [_block('block'), duplicate]);
        expect(() => _inspect(payload), throwsFormatException);
        expect(
          () => DataMigrator.migratePayload(payload),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'unknown schedule fields are warned and removed from canonical output',
    () {
      final payload = _payload();
      (payload['scheduleItems'] as List).first['futureField'] = 7;
      final plan = _inspect(payload);
      expect(plan.warnings.join(' '), contains('Schedule 1: futureField'));
      expect(
        plan.scheduleItems.first.toJson().containsKey('futureField'),
        isFalse,
      );
    },
  );

  test(
    'schedule title limit counts JSON escaping and UTF8 with exact boundary',
    () {
      for (final title in ['a' * 4096, '${'\n' * 2047}aa', '${'会' * 1365}a']) {
        expect(
          _inspect(
            _payload(items: [_event('e', title: title)]),
          ).addedScheduleItems,
          1,
        );
        expect(
          () => _inspect(_payload(items: [_event('e', title: '${title}a')])),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'schedule count caps cover input and merged library; recovery is explicit',
    () {
      final items = [
        for (var i = 0; i < ImportPreflight.maxScheduleItems; i++)
          _block('s$i'),
      ];
      final atCap = _payload(items: items);
      expect(
        _inspect(atCap).scheduleItems.length,
        ImportPreflight.maxScheduleItems,
      );
      final above = _payload(items: [...items, _block('extra')]);
      expect(() => _inspect(above), throwsA(isA<BackupRejectedException>()));
      expect(
        _inspect({...above, 'recovery': true}).scheduleItems.length,
        items.length + 1,
      );
      expect(
        () => _inspect(
          _payload(items: [_block('extra')]),
          mode: 'merge',
          boards: [_board('b')],
          tasks: [_task('t')],
          items: items,
        ),
        throwsA(isA<BackupRejectedException>()),
      );
    },
  );

  for (final version in [1, 2]) {
    test(
      'lossy v$version needs caller opt in and returns displayable count',
      () async {
        final store = await _seed();
        addTearDown(store.dispose);
        expect(
          () => store.exportJson(version: version),
          throwsA(
            isA<ScheduleExportLossException>().having(
              (e) => e.lostScheduleItems,
              'loss',
              1,
            ),
          ),
        );
        expect(
          () => store.exportJsonResult(version: version),
          throwsA(isA<ScheduleExportLossException>()),
        );
        final result = store.exportJsonResult(
          version: version,
          allowScheduleLoss: true,
        );
        expect(result.lostScheduleItems, 1);
        expect(result.version, version);
        final payload = jsonDecode(result.json) as Map<String, dynamic>;
        expect(payload.containsKey('scheduleItems'), isFalse);
        expect(
          (payload['tasks'] as List).single.containsKey('plannedDate'),
          version == 2,
        );
        expect(jsonDecode(store.exportJson())['scheduleItems'], hasLength(1));
        expect(
          () => ExportData(
            boards: store.boards,
            tasks: store.tasks,
            scheduleItems: store.scheduleItems,
            settings: store.settings,
            aiConfig: store.aiConfig,
          ).toJson(targetVersion: version),
          throwsA(isA<ScheduleExportLossException>()),
        );
      },
    );
  }

  test(
    'legacy export without schedules has no loss; unknown output version refuses',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = await _open();
      addTearDown(store.dispose);
      expect(store.exportJsonResult(version: 2).lostScheduleItems, 0);
      expect(() => store.exportJson(version: 4), throwsFormatException);
      expect(
        () => DataMigrator.migratePayload({..._payload(), 'version': 4}),
        throwsFormatException,
      );
    },
  );

  test(
    'credential export has the same v3 default and explicit loss result',
    () async {
      final credentials = race.GatedCredentials()..value = 'synthetic-key';
      final store = await _seed(credentials: credentials);
      addTearDown(store.dispose);
      final current = jsonDecode(await store.exportJsonWithCredential());
      expect(current['version'], 3);
      expect(current['scheduleItems'], hasLength(1));
      expect(current['aiConfig']['customApiKey'], 'synthetic-key');
      await expectLater(
        store.exportJsonWithCredential(version: 2),
        throwsA(isA<ScheduleExportLossException>()),
      );
      final legacy = await store.exportJsonResultWithCredential(
        version: 2,
        allowScheduleLoss: true,
      );
      expect(legacy.lostScheduleItems, 1);
      expect(
        jsonDecode(legacy.json)['aiConfig']['customApiKey'],
        'synthetic-key',
      );
    },
  );

  test(
    'rebase detects schedule conflict while waiting for a prior credential edit',
    () async {
      final credentials = race.GatedCredentials();
      final store = await _seed(credentials: credentials);
      addTearDown(store.dispose);
      final payload = _payload(items: [_block('old')]);
      final merge = store.previewImport(payload, 'merge');
      credentials.writeGate = Completer<void>();
      final updating = store.updateAIConfig(
        store.copyAIConfig()..apiKey = 'synthetic-key',
      );
      await credentials.entered.future;
      final merging = store.applyImport(merge);
      store.updateScheduleItem(
        _block('old', delta: 1),
        expectedRevision: store.scheduleRevision('old'),
      );
      credentials.writeGate!.complete();
      expect(await updating, isTrue);
      expect((await merging).success, isFalse);
      expect(store.scheduleItems.single.startAt, _start + 1);
      expect(credentials.value, 'synthetic-key');
      await store.flush();
    },
  );

  test(
    'failed v3 import retains a later schedule edit and its imported dependencies',
    () async {
      final barrier = race.SlotBarrier()..failSlot(0);
      final store = await _seed(writer: barrier.write);
      final payload = _payload(items: []);
      payload['boards'] = [_board('imported-board').toJson()];
      payload['tasks'] = [
        _task('imported', boardId: 'imported-board').toJson(),
      ];
      payload['scheduleItems'] = [
        _block('incoming', taskId: 'imported').toJson(),
      ];
      final plan = store.previewImport(payload, 'overwrite');
      barrier.armed = true;
      final importing = store.applyImport(plan);
      await barrier.enteredAt(0);
      expect(
        store.updateScheduleItem(
          _block('incoming', taskId: 'imported', delta: 1),
          expectedRevision: store.scheduleRevision('incoming'),
        ),
        isTrue,
      );
      barrier.release(0);
      expect((await importing).success, isFalse);
      expect(store.scheduleItems.map((s) => s.id).toSet(), {'old', 'incoming'});
      expect(store.tasks.map((t) => t.id).toSet(), {'t', 'imported'});
      expect(store.boards.map((b) => b.id).toSet(), {'b', 'imported-board'});
      expect((await store.flush()).success, isTrue);
      final expected = _canonical(store);
      store.dispose();
      final reopened = await _open();
      addTearDown(reopened.dispose);
      expect(_canonical(reopened), expected);
    },
  );

  test(
    'rollback invalidates editors opened on the uncommitted imported schedule',
    () async {
      final barrier = race.SlotBarrier()..failSlot(0);
      final store = await _seed(writer: barrier.write);
      addTearDown(store.dispose);
      final plan = store.previewImport(
        _payload(items: [_block('old', delta: 1)]),
        'overwrite',
      );
      barrier.armed = true;
      final importing = store.applyImport(plan);
      await barrier.enteredAt(0);
      final importedRevision = store.scheduleRevision('old');
      expect(store.scheduleItems.single.startAt, _start + 1);
      barrier.release(0);
      expect((await importing).success, isFalse);
      expect(store.scheduleItems.single.startAt, _start);
      expect(store.scheduleRevision('old'), greaterThan(importedRevision));
      expect(
        store.updateScheduleItem(
          _block('old', delta: 2),
          expectedRevision: importedRevision,
        ),
        isFalse,
      );
      expect(
        store.deleteScheduleItem('old', expectedRevision: importedRevision),
        isFalse,
      );
      await store.flush();
    },
  );

  test(
    'Store exports a v3 bundle, restores every volume and reopens all content',
    () async {
      final source = await _seed();
      source.addTasks([
        for (var i = 0; i < 5; i++)
          _task('large-$i')..notesMarkdown = '备' * (800 * 1024),
      ]);
      for (var i = 0; i < 5; i++) {
        source.addScheduleItem(_block('s$i', taskId: 'large-$i'));
      }
      source.addScheduleItem(_event('meeting'));
      expect((await source.flush()).success, isTrue);
      final expected = _canonical(source);
      final bundle = await source.exportBackup();
      expect(bundle.recoverable, isTrue);
      expect(bundle.parts.length, greaterThan(1));
      source.dispose();
      SharedPreferences.setMockInitialValues({});
      final target = await _open();
      for (final part in bundle.parts) {
        final plan = target.previewImport(
          jsonDecode(part.json) as Map<String, dynamic>,
          part.index == 1 ? 'overwrite' : 'merge',
        );
        expect(plan.conflicts, 0);
        expect((await target.applyImport(plan)).success, isTrue);
      }
      // Packing can reorder records by board; compare canonical sets explicitly.
      final expectedMap = jsonDecode(expected) as Map<String, dynamic>;
      void assertContents(Store actual) {
        final actualMap =
            jsonDecode(_canonical(actual)) as Map<String, dynamic>;
        for (final field in ['boards', 'tasks', 'scheduleItems']) {
          expect(
            (actualMap[field] as List).map(jsonEncode).toSet(),
            (expectedMap[field] as List).map(jsonEncode).toSet(),
            reason: field,
          );
        }
        for (final field in ['settings', 'aiConfig', 'activeBoardId']) {
          expect(actualMap[field], expectedMap[field], reason: field);
        }
      }

      assertContents(target);
      target.dispose();
      final reopened = await _open();
      addTearDown(reopened.dispose);
      assertContents(reopened);
    },
  );

  test(
    'merge skips identical schedule and previews differing id content as conflict',
    () {
      final payload = _payload(items: [_block('s')]);
      final same = _inspect(
        payload,
        mode: 'merge',
        boards: [_board('b')],
        tasks: [_task('t')],
        items: [_block('s')],
      );
      expect(same.skippedScheduleItems, 1);
      expect(same.addedScheduleItems, 0);
      final conflict = _inspect(
        payload,
        mode: 'merge',
        boards: [_board('b')],
        tasks: [_task('t')],
        items: [_block('s', delta: 1)],
      );
      expect(conflict.conflicts, 1);
      expect(conflict.conflictingScheduleItems, 1);
      expect(conflict.scheduleItems.single.startAt, _start + 1);
    },
  );

  test(
    'target board merge maps standalone event and keeps linked task identity',
    () {
      final plan = _inspect(
        _payload(),
        mode: 'merge',
        boards: [_board('target')],
        tasks: [_task('t', boardId: 'target')],
        target: 'target',
      );
      expect(plan.addedTasks, 0);
      expect(plan.addedScheduleItems, 2);
      expect(plan.scheduleItems.first.taskId, 't');
      expect(plan.scheduleItems.last.boardId, 'target');
      expect(plan.boards.map((b) => b.id), ['target']);
    },
  );

  test(
    'a parent task conflict or invalid board rejects the linked schedule batch',
    () {
      final different = _task('t')..title = 'different';
      expect(
        () => _inspect(
          _payload(),
          mode: 'merge',
          boards: [_board('b')],
          tasks: [different],
        ),
        throwsFormatException,
      );
      final orphan = _payload();
      (orphan['tasks'] as List).single['boardId'] = 'gone';
      expect(() => _inspect(orphan, mode: 'merge'), throwsFormatException);
      expect(
        () => _inspect(
          orphan,
          mode: 'merge',
          boards: [_board('target')],
          target: 'target',
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'overwrite previews removed schedules and persists the whole new v3 batch',
    () async {
      final store = await _seed();
      final oldRevision = store.scheduleRevision('old');
      final plan = store.previewImport(_payload(), 'overwrite');
      expect(plan.removedScheduleItems, 1);
      expect(plan.addedScheduleItems, 2);
      expect((await store.applyImport(plan)).success, isTrue);
      expect(store.scheduleRevision('old'), greaterThan(oldRevision));
      final expected = _canonical(store);
      final prefs = await SharedPreferences.getInstance();
      expect(
        jsonDecode(
          SaveProtocol(prefs).load()!.values[SaveProtocol.scheduleKey]!,
        ),
        hasLength(2),
      );
      store.dispose();
      final reopened = await _open();
      addTearDown(reopened.dispose);
      expect(_canonical(reopened), expected);
    },
  );

  for (final version in [1, 2]) {
    test(
      'legacy v$version overwrite reports deletion and clears schedule',
      () async {
        final store = await _seed();
        addTearDown(store.dispose);
        final payload = _payload()
          ..['version'] = version
          ..remove('scheduleItems');
        final merge = store.previewImport(payload, 'merge');
        expect(merge.scheduleItems, hasLength(1));
        final plan = store.previewImport(payload, 'overwrite');
        expect(plan.removedScheduleItems, 1);
        expect((await store.applyImport(plan)).success, isTrue);
        expect(store.scheduleItems, isEmpty);
      },
    );
  }

  test(
    'stale merge is recalculated and fails when a schedule changed after preview',
    () async {
      final store = await _seed();
      addTearDown(store.dispose);
      final payload = _payload(items: [_block('old')]);
      final plan = store.previewImport(payload, 'merge');
      (payload['scheduleItems'] as List).clear();
      final revision = store.scheduleRevision('old');
      expect(
        store.updateScheduleItem(
          _block('old', delta: 1),
          expectedRevision: revision,
        ),
        isTrue,
      );
      await store.flush();
      expect((await store.applyImport(plan)).success, isFalse);
      expect(store.scheduleItems.single.startAt, _start + 1);
      expect(plan.payload!['scheduleItems'], hasLength(1));
    },
  );

  test(
    'recalculated merge retains schedules added after preview; skips keep revision',
    () async {
      final store = await _seed();
      addTearDown(store.dispose);
      final oldRevision = store.scheduleRevision('old');
      final plan = store.previewImport(
        _payload(items: [_block('old'), _event('incoming')]),
        'merge',
      );
      store.addScheduleItem(_event('newer'));
      expect((await store.applyImport(plan)).success, isTrue);
      expect(store.scheduleItems.map((s) => s.id).toSet(), {
        'old',
        'newer',
        'incoming',
      });
      expect(store.scheduleRevision('old'), oldRevision);
    },
  );

  for (final mode in ['overwrite', 'merge']) {
    for (final failure in ['slot', 'pointer']) {
      test(
        '$mode v3 $failure failure rolls back memory and committed schedule',
        () async {
          var reject = false;
          final store = await _seed(
            writer: (key, value) async {
              if (reject &&
                  (failure == 'pointer'
                      ? key == SaveProtocol.pointerKey
                      : key.startsWith('matrixflow-save-') &&
                            key != SaveProtocol.pointerKey)) {
                return false;
              }
              return (await SharedPreferences.getInstance()).setString(
                key,
                value,
              );
            },
          );
          final before = _canonical(store);
          final prefs = await SharedPreferences.getInstance();
          final pointer = prefs.getString(SaveProtocol.pointerKey);
          final slot = prefs.getString(pointer!);
          final plan = store.previewImport(_payload(), mode);
          reject = true;
          expect((await store.applyImport(plan)).success, isFalse);
          expect(_canonical(store), before);
          expect(prefs.getString(SaveProtocol.pointerKey), pointer);
          expect(prefs.getString(pointer), slot);
          store.dispose();
          final reopened = await _open();
          addTearDown(reopened.dispose);
          expect(_canonical(reopened), before);
        },
      );
    }
  }
}
