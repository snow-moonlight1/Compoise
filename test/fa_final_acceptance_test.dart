// FA01–FA04. The 2026-09-27 probe stays untouched in test/review/.
// Synthetic data and in-memory platforms only.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/ai_capabilities.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'rf02_import_commit_race_test.dart' as fixture;

Future<void> settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void expectRefs(Store store) {
  final ids = store.boards.map((board) => board.id).toSet();
  expect(ids, isNotEmpty);
  expect(ids, contains(store.activeBoardId));
  for (final task in store.tasks) {
    expect(ids, contains(task.boardId), reason: task.id);
  }
}

Future<void> expectRestartAgrees(Store store) async {
  expectRefs(store);
  final tasks = store.tasks.map((task) => jsonEncode(task.toJson())).toList();
  final boards = store.boards.map((board) => board.id).toList();
  final active = store.activeBoardId;
  expect((await store.flush()).success, isTrue);
  expectRefs(store);
  store.dispose();
  final restarted = await fixture.openStore();
  addTearDown(restarted.dispose);
  expect(
    restarted.tasks.map((task) => jsonEncode(task.toJson())).toList(),
    tasks,
  );
  expect(restarted.boards.map((board) => board.id).toList(), boards);
  expect(restarted.activeBoardId, active);
  expectRefs(restarted);
}

int futureMs() =>
    DateTime.now().add(const Duration(days: 2)).millisecondsSinceEpoch;

class HoldingReminders extends InMemoryReminderService {
  Completer<void>? holdCancel;
  Completer<void>? holdSchedule;
  int cancelAlls = 0;
  bool holdNextSchedule = false;

  @override
  Future<void> cancelAll() async {
    cancelAlls++;
    final gate = holdCancel;
    if (gate != null) await gate.future;
    await super.cancelAll();
  }

  @override
  Future<ReminderScheduleResult> scheduleReminder({
    required String boardId,
    required String taskId,
    String? subtaskId,
    required String title,
    String? body,
    required int triggerAtMs,
    bool sound = true,
    bool vibrate = true,
    bool recordRetry = true,
    bool userInitiated = false,
  }) async {
    if (holdNextSchedule) {
      holdNextSchedule = false;
      final gate = holdSchedule;
      if (gate != null) await gate.future;
    }
    return super.scheduleReminder(
      boardId: boardId,
      taskId: taskId,
      subtaskId: subtaskId,
      title: title,
      body: body,
      triggerAtMs: triggerAtMs,
      sound: sound,
      vibrate: vibrate,
      recordRetry: recordRetry,
      userInitiated: userInitiated,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('FR02 kept task still has its board after a failed merge', () async {
    SharedPreferences.setMockInitialValues({});
    final barrier = fixture.SlotBarrier()..failSlot(0);
    final store = await fixture.openStore(barrier: barrier);
    addTearDown(store.dispose);
    final plan = store.previewImport(
      fixture.payload(fixture.newBoards('import-board'), []),
      'merge',
    );
    barrier.armed = true;
    final importing = store.applyImport(plan);
    await barrier.enteredAt(0);
    store.setActiveBoard('import-board');
    final added = store.newTask('Accepted concurrent task');
    store.addTasks([added]);
    barrier.release(0);
    expect((await importing).success, isFalse);
    await store.flush();
    expect(store.tasks.map((task) => task.id), contains(added.id));
    expect(store.boards.map((board) => board.id), contains(added.boardId));
    expect(store.activeBoardId, added.boardId);
    expectRefs(store);
  });

  test('FA01 overwrite edit keeps the imported task and its board', () async {
    SharedPreferences.setMockInitialValues({});
    final barrier = fixture.SlotBarrier()..failSlot(0);
    final store = await fixture.openStore(barrier: barrier);
    addTearDown(store.dispose);
    final original = store.activeBoardId;
    store.addTasks([store.newTask('Local')]);
    await store.flush();
    final plan = store.previewImport(
      fixture.payload(fixture.newBoards('import-board'), [
        fixture.taskJson('import-task', 'import-board', 'Imported'),
      ]),
      'overwrite',
    );
    barrier.armed = true;
    final importing = store.applyImport(plan);
    await barrier.enteredAt(0);
    final edited = Task.fromJson(
      store.tasks.firstWhere((task) => task.id == 'import-task').toJson(),
    )..title = 'Edited during commit';
    store.updateTask(edited);
    barrier.release(0);
    expect((await importing).success, isFalse);
    await store.flush();
    final kept = store.tasks.firstWhere((task) => task.id == 'import-task');
    expect(kept.title, 'Edited during commit');
    expect(store.boards.map((board) => board.id), contains(kept.boardId));
    expect(store.tasks.map((task) => task.title), contains('Local'));
    expect(store.boards.map((board) => board.id), contains(original));
    expectRefs(store);
  });

  test(
    'FA01 a same-byte edit does not anchor the uncommitted import',
    () async {
      SharedPreferences.setMockInitialValues({});
      final barrier = fixture.SlotBarrier()..failSlot(0);
      final store = await fixture.openStore(barrier: barrier);
      addTearDown(store.dispose);
      store.addTasks([store.newTask('Local')]);
      await store.flush();
      final plan = store.previewImport(
        fixture.payload(fixture.newBoards('import-board'), [
          fixture.taskJson('import-task', 'import-board', 'Imported'),
        ]),
        'overwrite',
      );
      barrier.armed = true;
      final importing = store.applyImport(plan);
      await barrier.enteredAt(0);
      final same = Task.fromJson(
        store.tasks.firstWhere((task) => task.id == 'import-task').toJson(),
      );
      store.updateTask(same);
      barrier.release(0);
      expect((await importing).success, isFalse);
      await store.flush();
      expect(
        store.tasks.map((task) => task.id),
        isNot(contains('import-task')),
      );
      expect(
        store.boards.map((board) => board.id),
        isNot(contains('import-board')),
      );
      expect(store.tasks.map((task) => task.title), contains('Local'));
      expectRefs(store);
    },
  );

  test('FA01 deleting the imported board stays deleted', () async {
    SharedPreferences.setMockInitialValues({});
    final barrier = fixture.SlotBarrier()..failSlot(0);
    final store = await fixture.openStore(barrier: barrier);
    addTearDown(store.dispose);
    final plan = store.previewImport(
      fixture.payload(fixture.newBoards('import-board'), [
        fixture.taskJson('import-task', 'import-board', 'Imported'),
      ]),
      'merge',
    );
    barrier.armed = true;
    final importing = store.applyImport(plan);
    await barrier.enteredAt(0);
    store.setActiveBoard('import-board');
    store.addTasks([store.newTask('On imported board')]);
    store.deleteBoard('import-board');
    barrier.release(0);
    expect((await importing).success, isFalse);
    await store.flush();
    expect(
      store.boards.map((board) => board.id),
      isNot(contains('import-board')),
    );
    expect(
      store.tasks.map((task) => task.title),
      isNot(contains('On imported board')),
    );
    expectRefs(store);
  });

  test(
    'FA01 switching to an unreferenced imported board is not a ghost',
    () async {
      SharedPreferences.setMockInitialValues({});
      final barrier = fixture.SlotBarrier()..failSlot(0);
      final store = await fixture.openStore(barrier: barrier);
      addTearDown(store.dispose);
      final original = store.activeBoardId;
      final plan = store.previewImport(
        fixture.payload(fixture.newBoards('import-board'), []),
        'merge',
      );
      barrier.armed = true;
      final importing = store.applyImport(plan);
      await barrier.enteredAt(0);
      store.setActiveBoard('import-board');
      barrier.release(0);
      expect((await importing).success, isFalse);
      await store.flush();
      expect(
        store.boards.map((board) => board.id),
        isNot(contains('import-board')),
      );
      expect(store.activeBoardId, original);
      expectRefs(store);
    },
  );

  test('FA01 pointer failure keeps the new task on a real board', () async {
    SharedPreferences.setMockInitialValues({});
    final barrier = fixture.SlotBarrier()..failSlot(0);
    final store = await fixture.openStore(barrier: barrier);
    final plan = store.previewImport(
      fixture.payload(fixture.newBoards('import-board'), []),
      'merge',
    );
    barrier.armed = true;
    barrier.failPointer = true;
    final importing = store.applyImport(plan);
    await barrier.enteredAt(0);
    store.setActiveBoard('import-board');
    final added = store.newTask('Pointer window');
    store.addTasks([added]);
    barrier.release(0);
    expect((await importing).success, isFalse);
    barrier.failPointer = false;
    expect((await store.retrySave()).success, isTrue);
    expect(store.tasks.map((task) => task.id), contains(added.id));
    expect(store.boards.map((board) => board.id), contains(added.boardId));
    await expectRestartAgrees(store);
  });

  test('FA01 credential failure never exposes the imported board', () async {
    SharedPreferences.setMockInitialValues({});
    final credentials = fixture.GatedCredentials()
      ..writeGate = Completer<void>()
      ..failWrite = true;
    final store = await fixture.openStore(credentials: credentials);
    addTearDown(store.dispose);
    final added = store.newTask('Local');
    store.addTasks([added]);
    await store.flush();
    final plan = store.previewImport(
      fixture.payload(
        fixture.newBoards('import-board'),
        [fixture.taskJson('import-task', 'import-board', 'Imported')],
        aiConfig: {
          'provider': 'custom',
          'protocol': 'openai-compatible',
          'customApiKey': 'synthetic-backup-key',
        },
      ),
      'overwrite',
    );
    final importing = store.applyImport(plan, importCredential: true);
    await credentials.entered.future;
    final during = store.newTask('During credential');
    store.addTasks([during]);
    credentials.writeGate!.complete();
    expect((await importing).success, isFalse);
    await store.flush();
    expect(
      store.tasks.map((task) => task.id),
      containsAll([added.id, during.id]),
    );
    expect(
      store.boards.map((board) => board.id),
      isNot(contains('import-board')),
    );
    expectRefs(store);
  });

  test('FA01 a later import sees the repaired library', () async {
    SharedPreferences.setMockInitialValues({});
    final barrier = fixture.SlotBarrier()..failSlot(0);
    final store = await fixture.openStore(barrier: barrier);
    final plan = store.previewImport(
      fixture.payload(fixture.newBoards('import-board'), []),
      'merge',
    );
    barrier.armed = true;
    final importing = store.applyImport(plan);
    await barrier.enteredAt(0);
    store.setActiveBoard('import-board');
    final added = store.newTask('Kept');
    store.addTasks([added]);
    barrier.release(0);
    expect((await importing).success, isFalse);
    await store.flush();
    final second = store.previewImport(
      fixture.payload(fixture.newBoards('second-board'), [
        fixture.taskJson('second-task', 'second-board', 'Second'),
      ]),
      'merge',
    );
    expect((await store.applyImport(second)).success, isTrue);
    await store.flush();
    expect(
      store.tasks.map((task) => task.id),
      containsAll([added.id, 'second-task']),
    );
    expectRefs(store);
    final bundle = await store.exportBackup();
    expect(bundle.recoverable, isTrue);
    SharedPreferences.setMockInitialValues({});
    final empty = Store();
    await empty.init();
    addTearDown(empty.dispose);
    for (var i = 0; i < bundle.parts.length; i++) {
      final restored = empty.previewImport(
        jsonDecode(bundle.parts[i].json) as Map<String, dynamic>,
        i == 0 ? 'overwrite' : 'merge',
      );
      expect((await empty.applyImport(restored)).success, isTrue);
    }
    expect(
      empty.tasks.map((task) => task.id).toSet(),
      store.tasks.map((task) => task.id).toSet(),
    );
    expectRefs(empty);
    store.dispose();
  });

  test('FA01 export refuses a backup that would skip an orphan task', () {
    final bundle = buildBackupBundle(
      jsonEncode({
        'version': 2,
        'boards': [
          {'id': 'b', 'name': 'B', 'createdAt': 1},
        ],
        'tasks': [fixture.taskJson('orphan', 'missing', 'Orphan')],
      }),
    );
    expect(bundle.recoverable, isFalse);
    expect(bundle.status, BackupStatus.incomplete);
    expect(bundle.parts, isEmpty);
  });

  test('FR01 failed overwrite keeps the original reminder', () async {
    SharedPreferences.setMockInitialValues({});
    final barrier = fixture.SlotBarrier()..failSlot(0);
    final reminders = InMemoryReminderService();
    final store = Store(saveWriter: barrier.write, reminders: reminders);
    addTearDown(store.dispose);
    await store.init();
    final when = futureMs();
    final old = store.newTask('Synthetic original')..reminderAt = when;
    store.addTasks([old]);
    await store.flush();
    await settle();
    expect(
      reminders.scheduled.values.map((item) => item.taskId),
      contains(old.id),
    );
    final plan = store.previewImport(
      fixture.payload(fixture.newBoards('import-board'), [
        fixture.taskJson('import-task', 'import-board', 'Synthetic imported'),
      ]),
      'overwrite',
    );
    barrier.armed = true;
    final importing = store.applyImport(plan);
    await barrier.enteredAt(0);
    await settle();
    expect(
      reminders.scheduled.values.map((item) => item.taskId),
      contains(old.id),
    );
    barrier.release(0);
    expect((await importing).success, isFalse);
    await store.flush();
    await settle();
    final record = reminders.scheduled.values.firstWhere(
      (item) => item.taskId == old.id,
    );
    expect(record.triggerAtMs, when);
    expect(
      reminders.scheduled.values.map((item) => item.taskId),
      isNot(contains('import-task')),
    );
  });

  test(
    'FA02 a failed import does not leave the reminders it carried',
    () async {
      SharedPreferences.setMockInitialValues({});
      final barrier = fixture.SlotBarrier()..failSlot(0);
      final reminders = HoldingReminders();
      final store = Store(saveWriter: barrier.write, reminders: reminders);
      addTearDown(store.dispose);
      await store.init();
      final old = store.newTask('Original')..reminderAt = futureMs();
      final child = SubTask(
        id: 'child',
        title: 'Child',
        reminderAt: futureMs(),
      );
      old.subtasks = [child];
      store.addTasks([old]);
      await store.flush();
      await settle();
      final carried = futureMs();
      final plan = store.previewImport(
        fixture.payload(fixture.newBoards('import-board'), [
          {
            ...fixture.taskJson('import-task', 'import-board', 'Imported'),
            'reminderAt': carried,
            'subtasks': [
              {
                'id': 'import-child',
                'title': 'Imported child',
                'reminderAt': carried,
              },
            ],
          },
        ]),
        'overwrite',
      );
      barrier.armed = true;
      final importing = store.applyImport(plan);
      await barrier.enteredAt(0);
      await settle();
      barrier.release(0);
      expect((await importing).success, isFalse);
      await store.flush();
      await settle();
      expect(reminders.cancelAlls, 0);
      final ids = reminders.scheduled.values.map((item) => item.taskId).toSet();
      expect(ids, {old.id});
      expect(
        reminders.scheduled.values.map((item) => item.subtaskId).toSet(),
        contains(child.id),
      );
      expect(ids, isNot(contains('import-task')));
    },
  );

  test(
    'FA02 a successful overwrite replaces parent and child reminders',
    () async {
      SharedPreferences.setMockInitialValues({});
      final reminders = InMemoryReminderService();
      final store = Store(reminders: reminders);
      addTearDown(store.dispose);
      await store.init();
      final oldWhen = futureMs();
      final old = store.newTask('Original')..reminderAt = oldWhen;
      old.subtasks = [
        SubTask(id: 'old-child', title: 'Old child', reminderAt: oldWhen),
      ];
      store.addTasks([old]);
      await store.flush();
      await settle();
      final next = futureMs();
      final plan = store.previewImport(
        fixture.payload(fixture.newBoards('import-board'), [
          {
            ...fixture.taskJson('import-task', 'import-board', 'Imported'),
            'reminderAt': next,
            'subtasks': [
              {
                'id': 'import-child',
                'title': 'Imported child',
                'reminderAt': next,
              },
            ],
          },
        ]),
        'overwrite',
      );
      expect((await store.applyImport(plan)).success, isTrue);
      await store.flush();
      await settle();
      final scheduled = reminders.scheduled.values.toList();
      expect(scheduled.map((item) => item.taskId), isNot(contains(old.id)));
      expect(
        scheduled.where(
          (item) => item.taskId == 'import-task' && item.subtaskId == null,
        ),
        hasLength(1),
      );
      expect(
        scheduled
            .firstWhere((item) => item.subtaskId == 'import-child')
            .triggerAtMs,
        next,
      );
    },
  );

  test('FA02 a late rebuild does not cover a newer reminder edit', () async {
    SharedPreferences.setMockInitialValues({});
    final reminders = HoldingReminders();
    final store = Store(reminders: reminders);
    addTearDown(store.dispose);
    await store.init();
    await store.flush();
    final first = futureMs();
    final plan = store.previewImport(
      fixture.payload(fixture.currentBoards(store), [
        {
          ...fixture.taskJson('imported', store.activeBoardId, 'Imported'),
          'reminderAt': first,
        },
      ]),
      'merge',
    );
    reminders.holdNextSchedule = true;
    reminders.holdSchedule = Completer<void>();
    final importing = store.applyImport(plan);
    await Future<void>.delayed(Duration.zero);
    await settle();
    expect((await importing).success, isTrue);
    final edited = first + const Duration(days: 1).inMilliseconds;
    final task = Task.fromJson(
      store.tasks.firstWhere((item) => item.id == 'imported').toJson(),
    )..reminderAt = edited;
    store.updateTask(task);
    reminders.holdSchedule!.complete();
    await store.flush();
    await settle();
    expect(
      reminders.scheduled.values
          .firstWhere(
            (item) => item.taskId == 'imported' && item.subtaskId == null,
          )
          .triggerAtMs,
      edited,
    );
  });

  test('FA02 an exhausted reminder budget survives a failed import', () async {
    SharedPreferences.setMockInitialValues({});
    final barrier = fixture.SlotBarrier()..failSlot(0);
    final reminders = InMemoryReminderService();
    final store = Store(saveWriter: barrier.write, reminders: reminders);
    addTearDown(store.dispose);
    await store.init();
    final when = futureMs();
    final old = store.newTask('Budget')..reminderAt = when;
    reminders.scheduleFault = StateError('synthetic platform failure');
    store.addTasks([old]);
    await store.flush();
    await settle();
    final id = reminders.pendingJobs.values.first.notificationId;
    for (var i = 0; i < ReminderService.maxAutomaticRetries; i++) {
      await reminders.scheduleReminder(
        boardId: old.boardId,
        taskId: old.id,
        title: old.title,
        triggerAtMs: when,
      );
    }
    final before = reminders.pendingJobs.values.first;
    expect(before.exhausted, isTrue);
    reminders.scheduleFault = null;
    final plan = store.previewImport(
      fixture.payload(fixture.newBoards('import-board'), [
        fixture.taskJson('import-task', 'import-board', 'Imported'),
      ]),
      'overwrite',
    );
    barrier.armed = true;
    final importing = store.applyImport(plan);
    await barrier.enteredAt(0);
    barrier.release(0);
    expect((await importing).success, isFalse);
    await store.flush();
    await settle();
    final after = reminders.pendingJobs.values.firstWhere(
      (job) => job.notificationId == id,
    );
    expect(after.exhausted, isTrue);
    expect(after.attempts, before.attempts);
  });

  test('FR03 claude-opus-4-99 does not inherit manual thinking', () {
    final plan = planThinking(
      AIConfig(
        provider: 'custom',
        baseUrl: 'https://synthetic.invalid',
        apiKey: '',
        model: 'claude-opus-4-99',
        protocol: AIProtocol.anthropic,
        enableThinking: true,
      ),
    );
    expect(plan.fields, isEmpty);
    expect(plan.hintCode, 'aiThinkingModelUnverified');
  });

  test('FR03 gpt-5.1-unverified does not inherit effort none', () {
    final plan = planThinking(
      AIConfig(
        provider: 'custom',
        baseUrl: 'https://synthetic.invalid',
        apiKey: '',
        model: 'gpt-5.1-unverified',
        protocol: AIProtocol.openaiResponses,
        enableThinking: false,
      ),
    );
    expect(plan.fields, isEmpty);
    expect(plan.hintCode, 'aiThinkingModelUnverified');
  });

  test('FR03 an unknown gpt or o id does not inherit high', () {
    for (final model in ['gpt-9-preview', 'o9-custom']) {
      for (final thinking in [false, true]) {
        final plan = planThinking(
          AIConfig(
            provider: 'custom',
            baseUrl: 'https://synthetic.invalid',
            apiKey: '',
            model: model,
            protocol: AIProtocol.openaiResponses,
            enableThinking: thinking,
          ),
        );
        expect(plan.fields, isEmpty, reason: '$model/$thinking');
        expect(
          plan.hintCode,
          'aiThinkingModelUnverified',
          reason: '$model/$thinking',
        );
      }
    }
  });

  test('FR03 exact ids and legal date snapshots keep their parameters', () {
    final opus = planThinking(
      AIConfig(
        provider: 'custom',
        baseUrl: 'https://synthetic.invalid',
        apiKey: '',
        model: 'claude-opus-4',
        protocol: AIProtocol.anthropic,
        enableThinking: true,
      ),
    );
    expect(opus.fields['thinking'], {'type': 'enabled', 'budget_tokens': 4096});
    final dated = planThinking(
      AIConfig(
        provider: 'custom',
        baseUrl: 'https://synthetic.invalid',
        apiKey: '',
        model: 'claude-opus-4-20250514',
        protocol: AIProtocol.anthropic,
        enableThinking: true,
      ),
    );
    expect(dated.fields['thinking'], opus.fields['thinking']);
    final gpt = planThinking(
      AIConfig(
        provider: 'custom',
        baseUrl: 'https://synthetic.invalid',
        apiKey: '',
        model: 'gpt-5.1-2026-02-01',
        protocol: AIProtocol.openaiResponses,
      ),
    );
    expect(gpt.fields['reasoning'], {'effort': 'none'});
  });

  test('FR03 illegal snapshots and Claude 3.5 do not inherit parameters', () {
    for (final model in [
      'gpt-5.1-20260201',
      'gpt-5.1-2026-02-01-extra',
      'claude-opus-4-5-99',
      'claude-3-5-sonnet',
      'claude-3-5-haiku-20241022',
    ]) {
      final plan = planThinking(
        AIConfig(
          provider: 'custom',
          baseUrl: 'https://synthetic.invalid',
          apiKey: '',
          model: model,
          protocol: model.startsWith('claude')
              ? AIProtocol.anthropic
              : AIProtocol.openaiResponses,
          enableThinking: true,
        ),
      );
      expect(plan.fields, isEmpty, reason: model);
      expect(plan.hintCode, 'aiThinkingModelUnverified', reason: model);
    }
  });

  test('FR04 tasks accepted past the count cap remain exportable', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await fixture.openStore();
    addTearDown(store.dispose);
    final input = [
      for (var i = 0; i <= ImportPreflight.maxTasks; i++)
        Task(
          id: 'synthetic-$i',
          boardId: store.activeBoardId,
          title: 'T',
          quadrant: 2,
          createdAt: 1,
        ),
    ];
    store.addTasks(input);
    expect(input, hasLength(ImportPreflight.maxTasks + 1));
    await store.flush();
    expect(store.tasks, hasLength(ImportPreflight.maxTasks + 1));
    final bundle = await store.exportBackup();
    expect(bundle.recoverable, isTrue);
    expect(bundle.status, BackupStatus.recovery);
    SharedPreferences.setMockInitialValues({});
    final empty = Store();
    await empty.init();
    addTearDown(empty.dispose);
    final plan = empty.previewImport(
      jsonDecode(bundle.parts.single.json) as Map<String, dynamic>,
      'overwrite',
    );
    expect((await empty.applyImport(plan)).success, isTrue);
    expect(
      empty.tasks.map((task) => task.id).toSet(),
      store.tasks.map((task) => task.id).toSet(),
    );
  });

  test(
    'FA04 one-by-one growth past each count cap still round-trips',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = await fixture.openStore();
      addTearDown(store.dispose);
      final boardId = store.activeBoardId;
      store.addTasks([
        for (var i = 0; i < ImportPreflight.maxTasks - 1; i++)
          Task(
            id: 'n$i',
            boardId: boardId,
            title: 'T',
            quadrant: 1,
            createdAt: 1,
          ),
      ]);
      store.addTasks([
        Task(
          id: 'n-last',
          boardId: boardId,
          title: 'T',
          quadrant: 1,
          createdAt: 1,
        ),
      ]);
      expect(store.tasks, hasLength(ImportPreflight.maxTasks));
      expect((await store.exportBackup()).status, BackupStatus.single);
      store.addTasks([
        Task(
          id: 'n-extra',
          boardId: boardId,
          title: 'T',
          quadrant: 1,
          createdAt: 1,
        ),
      ]);
      final tasks = await store.exportBackup();
      expect(tasks.recoverable, isTrue);
      expect(tasks.status, BackupStatus.recovery);

      for (var i = 0; i < ImportPreflight.maxBoards; i++) {
        store.createBoard('Board $i');
      }
      final boards = await store.exportBackup();
      expect(boards.recoverable, isTrue);

      store.addTasks([
        Task(
          id: 'many-children',
          boardId: boardId,
          title: 'Parent',
          quadrant: 1,
          createdAt: 1,
          subtasks: [
            for (var i = 0; i <= ImportPreflight.maxSubtasks; i++)
              SubTask(id: 'c$i', title: 'S'),
          ],
        ),
      ]);
      final children = await store.exportBackup();
      expect(children.recoverable, isTrue);
      expect(
        children.parts.every(
          (part) => part.bytes <= ImportPreflight.maxFileBytes,
        ),
        isTrue,
      );
    },
  );

  test('FA04 an oversized note round-trips without deleting it', () async {
    SharedPreferences.setMockInitialValues({});
    final giant = await fixture.openStore();
    addTearDown(giant.dispose);
    final note = '整' * 3000000;
    giant.addTasks([
      Task(
        id: 'giant',
        boardId: giant.activeBoardId,
        title: 'Giant',
        quadrant: 1,
        createdAt: 1,
        notesMarkdown: note,
      ),
    ]);
    final oversized = await giant.exportBackup();
    expect(oversized.recoverable, isTrue);
    expect(
      oversized.parts.every(
        (part) => part.bytes <= ImportPreflight.maxFileBytes,
      ),
      isTrue,
    );
    expect(giant.tasks.single.notesMarkdown, note);
    SharedPreferences.setMockInitialValues({});
    final empty = Store();
    await empty.init();
    addTearDown(empty.dispose);
    for (var i = 0; i < oversized.parts.length; i++) {
      final plan = empty.previewImport(
        jsonDecode(oversized.parts[i].json) as Map<String, dynamic>,
        i == 0 ? 'overwrite' : 'merge',
      );
      expect((await empty.applyImport(plan)).success, isTrue);
    }
    expect(empty.tasks.single.notesMarkdown, note);
    expect(empty.tasks.single.title, 'Giant');
  });

  test('FA04 an ordinary file still cannot walk past the count cap', () {
    final over = {
      'version': 2,
      'boards': [
        {'id': 'b', 'name': 'B', 'createdAt': 1},
      ],
      'tasks': [
        for (var i = 0; i <= ImportPreflight.maxTasks; i++)
          fixture.taskJson('t$i', 'b', 'T'),
      ],
    };
    expect(
      () => ImportPreflight.inspect(
        over,
        'overwrite',
        currentBoards: const [],
        currentTasks: const [],
        revision: 0,
      ),
      throwsA(isA<BackupRejectedException>()),
    );
    final marked = {...over, 'recovery': true};
    expect(
      () => ImportPreflight.inspect(
        marked,
        'overwrite',
        currentBoards: const [],
        currentTasks: const [],
        revision: 0,
      ),
      returnsNormally,
    );
  });
}
