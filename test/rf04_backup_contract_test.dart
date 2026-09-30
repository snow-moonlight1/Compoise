// RF04: a backup this app exports successfully must be restorable by this app.
// Synthetic data only: no real user library, no real API key.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/screens/settings_backup_flow.dart';
import 'package:matrixflow_native/storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _cjk = '整';

int _bytes(String value) => utf8.encode(value).length;

/// A valid one-board, one-task backup document with [notes] in the task notes.
String _doc({String notes = '', int tasks = 1, int boards = 1}) => jsonEncode({
  'version': 2,
  'timestamp': 1726000000000,
  'boards': [
    for (var b = 0; b < boards; b++)
      {'id': 'board-$b', 'name': 'B$b', 'createdAt': 1726000000000},
  ],
  'tasks': [
    for (var i = 0; i < boards; i++)
      for (var t = 0; t < tasks; t++)
        {
          'id': 'task-$i-$t',
          'boardId': 'board-$i',
          'title': 'T$i$t',
          'quadrant': 1,
          'createdAt': 1726000000000,
          if (notes.isNotEmpty) 'notesMarkdown': notes,
        },
  ],
  'settings': {'language': 'zh'},
  'aiConfig': {'providerId': 'custom', 'protocol': 'openai'},
});

/// Pads [document] with trailing whitespace to exactly [bytes] UTF-8 bytes, so
/// a ceiling can be tested at, one under and one over.
String _paddedTo(String document, int bytes) {
  final pad = bytes - _bytes(document);
  expect(pad, greaterThanOrEqualTo(0));
  return '$document${' ' * pad}';
}

/// A file payload at the record caps: [boards] boards, [tasksPerBoard] tasks
/// each, [subtasksPerTask] children each. [prefix] keeps the ids distinct from
/// an already populated library so a merge really adds records.
Map<String, dynamic> _atCaps({
  required int boards,
  required int tasksPerBoard,
  required int subtasksPerTask,
  String prefix = 'b',
}) => {
  'version': 2,
  'timestamp': 1726000000000,
  'boards': [
    for (var b = 0; b < boards; b++)
      {'id': '$prefix$b', 'name': 'B$b', 'createdAt': 1},
  ],
  'tasks': [
    for (var b = 0; b < boards; b++)
      for (var t = 0; t < tasksPerBoard; t++)
        {
          'id': '$prefix${b}t$t',
          'boardId': '$prefix$b',
          'title': 'T',
          'quadrant': 1,
          'createdAt': 1,
          'subtasks': [
            for (var s = 0; s < subtasksPerTask; s++)
              {'id': '$prefix${b}t${t}s$s', 'title': 'S', 'completed': false},
          ],
        },
  ],
};

/// A backup document shaped like a real export: [tasks] tasks on one board,
/// each carrying [note] and [subtasks] children. Ids are offset by [offset] so
/// two volumes of one library never collide.
String _volume({
  required int tasks,
  String note = '',
  int subtasks = 0,
  int offset = 0,
}) => jsonEncode({
  'version': 2,
  'timestamp': 1726000000000,
  'boards': [
    {'id': 'board-0', 'name': 'B', 'createdAt': 1},
  ],
  'tasks': [
    for (var i = 0; i < tasks; i++)
      {
        'id': 'task-${offset + i}',
        'boardId': 'board-0',
        'title': 'T',
        'quadrant': 1,
        'createdAt': 1,
        'notesMarkdown': note,
        'subtasks': [
          for (var s = 0; s < subtasks; s++)
            {'id': 'sub-${offset + i}-$s', 'title': 'S', 'completed': false},
        ],
      },
  ],
});

Map<String, dynamic> _payload(String document) =>
    ImportPreflight.decode(Uint8List.fromList(utf8.encode(document)));

/// One task per board on the live library: [count] boards besides the default
/// one, each holding a single sizeable task. Used for the board-count cases.
void _addBoardTasks(Store store, int count, {int cjkNotes = 3400}) {
  for (var b = 0; b < count; b++) {
    store.createBoard('B$b');
  }
  store.addTasks([
    for (var b = 0; b < count; b++)
      Task(
        id: 't$b',
        boardId: store.boards[b + 1].id,
        title: 'T$b',
        quadrant: 1,
        createdAt: 1,
        notesMarkdown: _cjk * cjkNotes,
      ),
  ]);
}

/// The 10,599-task library RF10 measured on a real device: 599 tasks past the
/// supported cap, and about 5.7 MiB of text, so it does split into two volumes.
const overCapTasks = 10599;

/// Builds that library through the store, on the same path a user exports from.
/// About 5.7 MiB, which is why these cases use moderate notes instead of the
/// multi-megabyte fixtures elsewhere.
Future<Store> _restoreBundle(BackupBundle bundle) async {
  SharedPreferences.setMockInitialValues({});
  final target = Store();
  await target.init();
  addTearDown(target.dispose);
  for (var i = 0; i < bundle.parts.length; i++) {
    final plan = target.previewImport(
      jsonDecode(bundle.parts[i].json) as Map<String, dynamic>,
      i == 0 ? 'overwrite' : 'merge',
    );
    expect((await target.applyImport(plan)).success, isTrue, reason: 'part $i');
  }
  await target.flush();
  return target;
}

Set<String> _taskCanon(Store store) =>
    store.tasks.map((task) => jsonEncode(task.toJson())).toSet();

Set<String> _boardCanon(Store store) =>
    store.boards.map((board) => jsonEncode(board.toJson())).toSet();
Future<Store> overCapLibrary() async {
  SharedPreferences.setMockInitialValues({});
  final store = Store();
  await store.init();
  addTearDown(store.dispose);
  final boardId = store.boards.first.id;
  final note = _cjk * 170;
  store.addTasks([
    for (var i = 0; i < overCapTasks; i++)
      Task(
        id: 't$i',
        boardId: boardId,
        title: 'T$i',
        quadrant: 1,
        createdAt: 1,
        notesMarkdown: note,
      ),
  ]);
  return store;
}

Task _taskOn(String id, String boardId, String notes) => Task(
  id: id,
  boardId: boardId,
  title: id,
  quadrant: 1,
  createdAt: 1,
  notesMarkdown: notes,
);

List<Task> _library({
  required int boards,
  required int tasks,
  required int subtasks,
}) => [
  for (var b = 0; b < boards; b++)
    for (var t = 0; t < tasks; t++)
      Task(
        id: 'live-b${b}t$t',
        boardId: 'b$b',
        title: 'T',
        quadrant: 1,
        createdAt: 1,
        subtasks: [
          for (var s = 0; s < subtasks; s++)
            SubTask(id: 'live-b${b}t${t}s$s', title: 'S'),
        ],
      ),
];

class _Recorder extends FilePicker {
  _Recorder({this.saves = 0, this.pickBytes});

  /// How many save dialogs the user completes before cancelling the picker.
  final int saves;
  final Uint8List? pickBytes;
  final asked = <String>[];
  int calls = 0;

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    if (calls >= saves) return null;
    asked.add(fileName!);
    calls++;
    return 'synthetic://$fileName';
  }

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async => pickBytes == null
      ? null
      : FilePickerResult([
          PlatformFile(
            name: 'backup.json',
            size: pickBytes!.length,
            bytes: pickBytes,
          ),
        ]);
}

class _Credential implements CredentialStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async => this.value = value;
  @override
  Future<void> delete() async => value = null;
}

class _DelayedCredential implements CredentialStore {
  String? value;
  final entered = Completer<void>();
  final release = Completer<void>();
  bool delayNextWrite = false;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String next) async {
    if (delayNextWrite) {
      delayNextWrite = false;
      entered.complete();
      await release.future;
    }
    value = next;
  }

  @override
  Future<void> delete() async => value = null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<Store> open({Map<String, Object> seed = const {}}) async {
    SharedPreferences.setMockInitialValues(seed);
    final store = Store();
    await store.init();
    addTearDown(store.dispose);
    return store;
  }

  Store fresh() {
    SharedPreferences.setMockInitialValues({});
    final store = Store();
    addTearDown(store.dispose);
    return store;
  }

  test(
    'RF04 keeps a record at the content budget inside the file ceiling',
    () async {
      // Migrated from RF-R04: this exact shape exported fine and could not be
      // read back, because the JSON around 4 MiB of notes is already over 4 MiB.
      SharedPreferences.setMockInitialValues({});
      final store = Store();
      await store.init();
      final task = store.newTask('Large valid notes')
        ..notesMarkdown = 'x' * ImportPreflight.maxBytes;
      store.addTasks([task]);
      final backup = store.exportJson();
      Object? error;
      try {
        ImportPreflight.decode(Uint8List.fromList(utf8.encode(backup)));
      } catch (e) {
        error = e;
      }
      await store.flush();
      store.dispose();
      expect(error, isNull);

      // And the whole round trip: preflight and restore into an empty library.
      final target = fresh();
      await target.init();
      final payload = ImportPreflight.decode(
        Uint8List.fromList(utf8.encode(backup)),
      );
      final plan = target.previewImport(payload, 'overwrite');
      expect(plan.conflicts, 0);
      expect((await target.applyImport(plan)).success, isTrue);
      expect(
        target.tasks.single.notesMarkdown,
        hasLength(ImportPreflight.maxBytes),
      );
    },
  );

  test(
    'RF04 file ceiling is checked before, at and one over the limit',
    () async {
      final document = _doc(notes: 'x' * 1024);
      final ceiling = ImportPreflight.maxFileBytes;
      for (final size in [ceiling - 1, ceiling]) {
        final bytes = Uint8List.fromList(
          utf8.encode(_paddedTo(document, size)),
        );
        expect(bytes, hasLength(size));
        final plan = ImportPreflight.inspect(
          ImportPreflight.decode(bytes),
          'merge',
          currentBoards: const [],
          currentTasks: const [],
          revision: 0,
        );
        expect(plan.tasks, hasLength(1));
      }
      final over = Uint8List.fromList(
        utf8.encode(_paddedTo(document, ceiling + 1)),
      );
      final error = _rejection(() => ImportPreflight.decode(over));
      expect(error.copy, 'importErrorTooLarge');
      // The same document one byte smaller still preflights cleanly.
      final store = await open();
      expect(
        () => store.previewImport(
          ImportPreflight.decode(Uint8List.fromList(utf8.encode(document))),
          'merge',
        ),
        returnsNormally,
      );
    },
  );

  test('RF04 limits count UTF-8 bytes, so CJK text costs three times more', () {
    final chars = 3 * 1024 * 1024 + 1;
    final ascii = Uint8List.fromList(utf8.encode(_doc(notes: 'a' * chars)));
    final cjk = Uint8List.fromList(utf8.encode(_doc(notes: _cjk * chars)));
    expect(ascii, hasLength(lessThan(ImportPreflight.maxFileBytes)));
    expect(cjk.length, greaterThan(ImportPreflight.maxFileBytes));
    expect(ImportPreflight.decode(ascii)['tasks'], hasLength(1));
    final error = _rejection(() => ImportPreflight.decode(cjk));
    expect(error.copy, 'importErrorTooLarge');
    // Japanese text costs the same as Chinese: 3 bytes per character.
    final ja = utf8.encode('四半期の経費精算').length;
    expect(ja, 3 * '四半期の経費精算'.length);
  });

  test(
    'RF04 accepts a library at the record caps and rejects one more',
    () async {
      const caps = ImportPreflight.maxTasks ~/ ImportPreflight.maxBoards;
      final atCaps = _atCaps(
        boards: ImportPreflight.maxBoards,
        tasksPerBoard: caps,
        subtasksPerTask:
            ImportPreflight.maxSubtasks ~/ ImportPreflight.maxTasks,
      );
      final bytes = utf8.encode(jsonEncode(atCaps)).length;
      expect(bytes, lessThan(ImportPreflight.maxFileBytes));
      final empty = <Board>[];
      final plan = ImportPreflight.inspect(
        atCaps,
        'overwrite',
        currentBoards: empty,
        currentTasks: const [],
        revision: 0,
      );
      expect(plan.boards, hasLength(ImportPreflight.maxBoards));
      expect(plan.tasks, hasLength(ImportPreflight.maxTasks));

      final oneMoreBoard = _rejection(
        () => ImportPreflight.inspect(
          _atCaps(
            boards: ImportPreflight.maxBoards + 1,
            tasksPerBoard: 1,
            subtasksPerTask: 0,
          ),
          'overwrite',
          currentBoards: empty,
          currentTasks: const [],
          revision: 0,
        ),
      );
      expect(oneMoreBoard.copy, 'importErrorTooManyRecords');
      final oneMoreTask = _rejection(
        () => ImportPreflight.inspect(
          _atCaps(
            boards: 1,
            tasksPerBoard: ImportPreflight.maxTasks + 1,
            subtasksPerTask: 0,
          ),
          'overwrite',
          currentBoards: empty,
          currentTasks: const [],
          revision: 0,
        ),
      );
      expect(oneMoreTask.copy, 'importErrorTooManyRecords');
      final oneMoreSubtask = _rejection(
        () => ImportPreflight.inspect(
          _atCaps(
            boards: 1,
            tasksPerBoard: 1,
            subtasksPerTask: ImportPreflight.maxSubtasks + 1,
          ),
          'overwrite',
          currentBoards: empty,
          currentTasks: const [],
          revision: 0,
        ),
      );
      expect(oneMoreSubtask.copy, 'importErrorTooManyRecords');
    },
  );

  test(
    'RF04 repeated legal merges cannot walk past the supported library',
    () async {
      const full = ImportPreflight.maxBoards - 1;
      final boards = [
        for (var b = 0; b < full; b++)
          Board(id: 'b$b', name: 'B$b', createdAt: 1),
      ];
      final tasks = _library(boards: full, tasks: 1, subtasks: 0);
      // Two new boards would land on 501: each merge was legal, the library is
      // not, and a library past the caps is one no backup can carry.
      final tooMany = _rejection(
        () => ImportPreflight.inspect(
          _atCaps(
            boards: 2,
            tasksPerBoard: 1,
            subtasksPerTask: 0,
            prefix: 'new',
          ),
          'merge',
          currentBoards: boards,
          currentTasks: tasks,
          revision: 0,
        ),
      );
      expect(tooMany.copy, 'importErrorTooManyRecords');
      // One board fills the library exactly and stays legal.
      final fills = ImportPreflight.inspect(
        _atCaps(boards: 1, tasksPerBoard: 1, subtasksPerTask: 0, prefix: 'new'),
        'merge',
        currentBoards: boards,
        currentTasks: tasks,
        revision: 0,
      );
      expect(fills.boards, hasLength(ImportPreflight.maxBoards));
      Map<String, dynamic> extraTask({List<Map<String, String>>? children}) => {
        'version': 2,
        'boards': [],
        'tasks': [
          {
            'id': 'extra',
            'boardId': 'b0',
            'title': 'T',
            'quadrant': 1,
            'createdAt': 1,
            if (children != null) 'subtasks': children,
          },
        ],
      };
      // Task and subtask totals are counted over the resulting library too.
      final nearFullTasks = _library(
        boards: 1,
        tasks: ImportPreflight.maxTasks,
        subtasks: 0,
      );
      expect(
        _rejection(
          () => ImportPreflight.inspect(
            extraTask(),
            'merge',
            currentBoards: [Board(id: 'b0', name: 'B', createdAt: 1)],
            currentTasks: nearFullTasks,
            revision: 0,
          ),
        ).copy,
        'importErrorTooManyRecords',
      );
      final nearFullSubtasks = _library(
        boards: 1,
        tasks: ImportPreflight.maxTasks,
        subtasks: 5,
      );
      expect(
        _rejection(
          () => ImportPreflight.inspect(
            extraTask(
              children: [
                {'id': 's', 'title': 'S'},
              ],
            ),
            'merge',
            currentBoards: [Board(id: 'b0', name: 'B', createdAt: 1)],
            currentTasks: nearFullSubtasks,
            revision: 0,
          ),
        ).copy,
        'importErrorTooManyRecords',
      );

      // Through the store: the refused merge leaves the library untouched, and a
      // plan confirmed while there was still room is refused when it is committed
      // against the live library.
      final store = await open(
        seed: {
          'matrixflow-boards': jsonEncode([
            for (var b = 0; b < 499; b++)
              {'id': 'b$b', 'name': 'B$b', 'createdAt': 1},
          ]),
          'matrixflow-tasks': jsonEncode([]),
          'matrixflow-active-board': 'b0',
          'matrixflow-has-seen-onboarding': true,
        },
      );
      expect(store.boards, hasLength(499));
      final fillsLast = store.previewImport(
        _atCaps(boards: 1, tasksPerBoard: 1, subtasksPerTask: 0, prefix: 'm1'),
        'merge',
      );
      final previewedTogether = store.previewImport(
        _atCaps(boards: 1, tasksPerBoard: 1, subtasksPerTask: 0, prefix: 'm2'),
        'merge',
      );
      expect((await store.applyImport(fillsLast)).success, isTrue);
      expect(store.boards, hasLength(500));
      expect((await store.applyImport(previewedTogether)).success, isFalse);
      expect(store.boards, hasLength(500));
      expect(
        () => store.previewImport(
          _atCaps(
            boards: 1,
            tasksPerBoard: 1,
            subtasksPerTask: 0,
            prefix: 'm3',
          ),
          'merge',
        ),
        throwsFormatException,
      );
      final prefs = await SharedPreferences.getInstance();
      expect(
        (jsonDecode(prefs.getString('matrixflow-boards')!) as List).length,
        500,
      );
    },
  );

  test('RF04 a too big library exports parts that restore in order', () async {
    SharedPreferences.setMockInitialValues({});
    final store = Store();
    await store.init();
    // Board A alone is larger than one part, so its record repeats across the
    // parts that carry its tasks; B and C each fit a part.
    final notes = _cjk * 440000;
    store.createBoard('A');
    final aId = store.boards.last.id;
    store.createBoard('B');
    final bId = store.boards.last.id;
    store.createBoard('C');
    final cId = store.boards.last.id;
    store.addTasks([
      for (var i = 0; i < 4; i++) _taskOn('a$i', aId, '$notes-A$i'),
      for (var i = 0; i < 2; i++) _taskOn('b$i', bId, '$notes-B$i'),
      for (var i = 0; i < 2; i++) _taskOn('c$i', cId, '$notes-C$i'),
    ]);
    expect(
      _bytes(store.exportJson()),
      greaterThan(ImportPreflight.maxFileBytes),
    );

    final bundle = await store.exportBackup();
    expect(bundle.status, BackupStatus.split);
    expect(bundle.recoverable, isTrue);
    expect(bundle.parts.length, greaterThan(1));
    expect(bundle.parts.length, lessThanOrEqualTo(ImportPreflight.maxParts));
    for (final part in bundle.parts) {
      expect(part.bytes, lessThanOrEqualTo(ImportPreflight.maxFileBytes));
      expect(
        ImportPreflight.decode(Uint8List.fromList(utf8.encode(part.json))),
        isA<Map<String, dynamic>>(),
      );
    }
    final first = jsonDecode(bundle.parts.first.json) as Map<String, dynamic>;
    expect(first['settings'], isNotNull);
    expect(first['aiConfig'], isNotNull);
    for (final part in bundle.parts.skip(1)) {
      final payload = jsonDecode(part.json) as Map<String, dynamic>;
      expect(payload.containsKey('settings'), isFalse);
      expect(payload.containsKey('aiConfig'), isFalse);
    }
    expect(_tasksOf(bundle.parts), hasLength(8));
    store.dispose();

    // Restore into an independent empty library, exactly as the docs tell the
    // user to: first part overwrites, the rest merge.
    final target = fresh();
    await target.init();
    var repeatedBoardSkipped = false;
    for (final part in bundle.parts) {
      final plan = target.previewImport(
        ImportPreflight.decode(Uint8List.fromList(utf8.encode(part.json))),
        part.index == 1 ? 'overwrite' : 'merge',
      );
      expect(plan.conflicts, 0, reason: 'part ${part.index}');
      expect(
        plan.addedTasks + plan.addedBoards,
        greaterThan(0),
        reason: 'part ${part.index}',
      );
      repeatedBoardSkipped |= plan.skipped > 0;
      expect((await target.applyImport(plan)).success, isTrue);
    }
    expect(
      repeatedBoardSkipped,
      isTrue,
      reason: 'a repeated board header is a skip, not a conflict',
    );
    // The library this fixture exported holds its default board plus A, B, C.
    expect(target.boards, hasLength(4));
    expect(target.tasks, hasLength(8));
    for (var i = 0; i < 4; i++) {
      final restored = target.tasks
          .firstWhere((task) => task.id == 'a$i')
          .notesMarkdown;
      expect(restored, '$notes-A$i');
    }
    expect(
      target.tasks.firstWhere((task) => task.id == 'c1').notesMarkdown,
      '$notes-C1',
    );
    expect(
      backupFileName('2026-09-26', bundle.parts.first),
      contains('part1of${bundle.parts.length}'),
    );
  });

  test('RF04 a library past eight volumes or one file still restores', () async {
    SharedPreferences.setMockInitialValues({});
    final store = Store();
    await store.init();
    addTearDown(store.dispose);
    // Nine boards of just over one part each need nine parts; eight is the
    // supported library ceiling, so export stops rather than writing a set
    // that could not be restored.
    final notes = _cjk * 1400000;
    for (var b = 0; b < 9; b++) {
      store.createBoard('B$b');
      store.addTasks([_taskOn('b${b}t', store.boards.last.id, notes)]);
    }
    final tooLarge = await store.exportBackup();
    expect(tooLarge.recoverable, isTrue);
    expect(tooLarge.parts.length, greaterThan(ImportPreflight.maxParts));
    expect(
      tooLarge.parts.every(
        (part) => part.bytes <= ImportPreflight.maxFileBytes,
      ),
      isTrue,
    );
    final restoredVolumes = await _restoreBundle(tooLarge);
    expect(_taskCanon(restoredVolumes), _taskCanon(store));

    // A note larger than one file is carried in bounded pieces and read back
    // whole. The source task is not deleted to make the export fit.
    SharedPreferences.setMockInitialValues({});
    final giant = Store();
    await giant.init();
    addTearDown(giant.dispose);
    giant.createBoard('Big');
    giant.addTasks([_taskOn('g1', giant.boards.last.id, _cjk * 3000000)]);
    final oversized = await giant.exportBackup();
    expect(oversized.recoverable, isTrue);
    expect(oversized.status, BackupStatus.recovery);
    expect(
      oversized.parts.every(
        (part) => part.bytes <= ImportPreflight.maxFileBytes,
      ),
      isTrue,
    );
    expect(giant.tasks, hasLength(1));
    final restoredGiant = await _restoreBundle(oversized);
    expect(_taskCanon(restoredGiant), _taskCanon(giant));

    // Too many children is a record-limit problem, not an oversized note: the
    // two cases get different advice, so the reason has to survive splitting.
    SharedPreferences.setMockInitialValues({});
    final crowded = Store();
    await crowded.init();
    addTearDown(crowded.dispose);
    crowded.createBoard('Crowded');
    crowded.addTasks([
      Task(
        id: 'crowded',
        boardId: crowded.boards.last.id,
        title: 'T',
        quadrant: 1,
        createdAt: 1,
        subtasks: [
          for (var i = 0; i < ImportPreflight.maxSubtasks + 1; i++)
            SubTask(id: 's$i', title: 'S'),
        ],
      ),
    ]);
    final crowdedBundle = await crowded.exportBackup();
    expect(crowdedBundle.recoverable, isTrue);
    expect(crowdedBundle.status, BackupStatus.recovery);
    final restoredCrowded = await _restoreBundle(crowdedBundle);
    expect(restoredCrowded.tasks, hasLength(1));
    expect(
      restoredCrowded.tasks.single.subtasks,
      hasLength(ImportPreflight.maxSubtasks + 1),
    );
    expect(_taskCanon(restoredCrowded), _taskCanon(crowded));
  });

  test(
    'RF04 volumes that restore one at a time still add up past the cap',
    () async {
      // What RF10 measured on a real 10,599-task library: export reported a
      // recoverable two-volume set, the first volume restored 7,066 tasks and the
      // second was refused by the result-library gate. Each volume is inside the
      // cap on its own, which is exactly why a per-volume export self check
      // cannot see this: only the whole library can.
      const total = 10599;
      const firstVolume = 7066;
      final note = _cjk * 170;
      final first = _volume(tasks: firstVolume, note: note);
      final second = _volume(
        tasks: total - firstVolume,
        note: note,
        offset: firstVolume,
      );

      // Both files pass the gate on their own, so an export that only validates
      // one volume at a time would hand them out as a working backup.
      for (final document in [first, second]) {
        expect(
          utf8.encode(document).length,
          lessThan(ImportPreflight.maxFileBytes),
        );
        expect(
          () => ImportPreflight.inspect(
            _payload(document),
            'merge',
            currentBoards: const [],
            currentTasks: const [],
            revision: 0,
          ),
          returnsNormally,
        );
      }

      // Restoring them in the order the settings screen prints is refused on the
      // second one, and the refusal drops nothing.
      final store = await open();
      final applied = store.previewImport(_payload(first), 'overwrite');
      expect((await store.applyImport(applied)).success, isTrue);
      expect(store.tasks, hasLength(firstVolume));
      final refused = _rejection(
        () => store.previewImport(_payload(second), 'merge'),
      );
      expect(refused.copy, 'importErrorTooManyRecords');
      expect(store.tasks, hasLength(firstVolume));
    },
  );

  test(
    'RF04 an over-cap library exports as a recovery archive and restores',
    () async {
      // The 10,599-task library RF10 W7 measured on a real device. About 5.7 MiB
      // of text. It used to be refused up front, or split into volumes the second
      // of which the count cap rejected. The recovery marker is what lets every
      // task come back without deleting any.
      final store = await overCapLibrary();
      expect(
        utf8.encode(store.exportJson()).length,
        greaterThan(ImportPreflight.maxBytes),
      );
      final bundle = await store.exportBackup();
      expect(bundle.recoverable, isTrue);
      expect(bundle.status, BackupStatus.recovery);
      expect(bundle.parts, isNotEmpty);
      expect(
        bundle.parts.every(
          (part) => (jsonDecode(part.json) as Map)['recovery'] == true,
        ),
        isTrue,
      );

      expect(store.tasks, hasLength(overCapTasks));
      expect((await store.flush()).success, isTrue);
      final restarted = Store();
      await restarted.init();
      addTearDown(restarted.dispose);
      expect(restarted.tasks, hasLength(overCapTasks));

      final restored = await _restoreBundle(bundle);
      expect(restored.tasks, hasLength(overCapTasks));
      expect(_taskCanon(restored), _taskCanon(store));
      expect(_boardCanon(restored), _boardCanon(store));
      expect(restored.settings.toJson(), store.settings.toJson());
    },
  );

  testWidgets('RF04 export of an over-cap library writes a recovery archive', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final store = Store();
    // `Store.init` starts a periodic timer, so the library is built on the
    // real clock. Nothing here awaits persistence: a save awaited inside
    // `runAsync` has no event loop to complete it.
    await tester.runAsync(() async {
      await store.init();
      final boardId = store.boards.first.id;
      final note = _cjk * 170;
      store.addTasks([
        for (var i = 0; i < overCapTasks; i++)
          Task(
            id: 't$i',
            boardId: boardId,
            title: 'T$i',
            quadrant: 1,
            createdAt: 1,
            notesMarkdown: note,
          ),
      ]);
    });
    addTearDown(store.dispose);
    expect(store.tasks, hasLength(overCapTasks));

    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (inner) {
              context = inner;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    final written = <String, Uint8List>{};
    final flow = SettingsBackupFlow(
      onBusyChanged: (_) {},
      writeFile: (path, bytes) async => written[path] = bytes,
    );
    final picker = _Recorder(saves: 4);
    FilePicker.platform = picker;
    final result = await _exportWithChoice(tester, flow, context, store);

    // The over-count library is written as a recovery archive, not refused with
    // advice to delete tasks. Every saved file stays inside the byte ceiling.
    expect(result.outcome, BackupOutcome.succeeded);
    expect(picker.asked, isNotEmpty);
    expect(written, isNotEmpty);
    expect(store.tasks, hasLength(overCapTasks));
    final savedIds = <String>{};
    for (final bytes in written.values) {
      expect(bytes.length, lessThanOrEqualTo(ImportPreflight.maxFileBytes));
      final payload = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      expect(payload['recovery'], isTrue);
      savedIds.addAll(
        (payload['tasks'] as List).map((task) => (task as Map)['id'] as String),
      );
    }
    expect(savedIds, hasLength(overCapTasks));
  });

  test('RF04 over-cap boards and subtasks round-trip without deletion', () async {
    // 501 boards with one sizeable task each is about 5.2 MiB, so the library
    // splits into two volumes carrying roughly 250 boards each: well inside the
    // 500 board cap, and only the cumulative count is over it.
    final boards = await open();
    _addBoardTasks(boards, ImportPreflight.maxBoards);
    expect(boards.boards, hasLength(ImportPreflight.maxBoards + 1));
    expect(
      utf8.encode(boards.exportJson()).length,
      greaterThan(ImportPreflight.maxBytes),
    );
    final boardBundle = await boards.exportBackup();
    expect(boardBundle.recoverable, isTrue);
    expect(boardBundle.status, BackupStatus.recovery);
    expect(boards.boards, hasLength(ImportPreflight.maxBoards + 1));
    expect(boards.tasks, hasLength(ImportPreflight.maxBoards));
    final restoredBoards = await _restoreBundle(boardBundle);
    expect(_boardCanon(restoredBoards), _boardCanon(boards));
    expect(_taskCanon(restoredBoards), _taskCanon(boards));

    // 9,000 tasks with 6 children each: 54,000 subtasks against the 50,000 cap,
    // split so that every volume carries about half of them. Under the task cap
    // and over the subtask cap, refused for the same reason.
    const crowdedTasks = 9000;
    const perTask = 6;
    final crowded = await open();
    crowded.addTasks([
      for (var i = 0; i < crowdedTasks; i++)
        Task(
          id: 'c$i',
          boardId: crowded.boards.first.id,
          title: 'C$i',
          quadrant: 1,
          createdAt: 1,
          notesMarkdown: _cjk * 100,
          subtasks: [
            for (var s = 0; s < perTask; s++)
              SubTask(id: 'cs$i-$s', title: 'S$s'),
          ],
        ),
    ]);
    expect(
      crowded.tasks.fold(0, (sum, task) => sum + task.subtasks.length),
      ImportPreflight.maxSubtasks + 4000,
    );
    expect(
      utf8.encode(crowded.exportJson()).length,
      greaterThan(ImportPreflight.maxBytes),
    );
    final crowdedBundle = await crowded.exportBackup();
    expect(crowdedBundle.recoverable, isTrue);
    expect(crowdedBundle.status, BackupStatus.recovery);
    expect(crowded.tasks, hasLength(crowdedTasks));
    final restoredCrowded = await _restoreBundle(crowdedBundle);
    expect(
      restoredCrowded.tasks.fold<int>(
        0,
        (sum, task) => sum + task.subtasks.length,
      ),
      ImportPreflight.maxSubtasks + 4000,
    );
    expect(_taskCanon(restoredCrowded), _taskCanon(crowded));

    // Under the caps the very same shape is refused by nothing: the same
    // 9,000 tasks, 4 children each and the same 5.7 MiB of text, so the
    // refusal above is the cumulative count and not the size. 36,000 subtasks
    // and 9,000 tasks are both inside the caps, so this stays exportable.
    final supported = await open();
    supported.addTasks([
      for (var i = 0; i < crowdedTasks; i++)
        Task(
          id: 's$i',
          boardId: supported.boards.first.id,
          title: 'S$i',
          quadrant: 1,
          createdAt: 1,
          notesMarkdown: _cjk * 100,
          subtasks: [
            for (
              var s = 0;
              s < ImportPreflight.maxSubtasks ~/ crowdedTasks - 1;
              s++
            )
              SubTask(id: 'ss$i-$s', title: 'S$s'),
          ],
        ),
    ]);
    final supportedBundle = await supported.exportBackup();
    expect(supportedBundle.recoverable, isTrue);
    expect(supportedBundle.status, BackupStatus.single);
  });

  test(
    'RF04 a library at every cap still exports as volumes and restores whole',
    () async {
      // 1 board, 10,000 tasks and 50,000 subtasks: the largest library the app
      // supports, and about 9.3 MiB of text, so it needs three volumes.
      const perTask = ImportPreflight.maxSubtasks ~/ ImportPreflight.maxTasks;
      final store = await open();
      final boardId = store.boards.first.id;
      store.addTasks([
        for (var i = 0; i < ImportPreflight.maxTasks; i++)
          Task(
            id: 't$i',
            boardId: boardId,
            title: 'T$i',
            quadrant: 1,
            createdAt: 1,
            notesMarkdown: _cjk * 200,
            subtasks: [
              for (var s = 0; s < perTask; s++)
                SubTask(id: 's$i-$s', title: 'S$s'),
            ],
          ),
      ]);
      expect(store.tasks, hasLength(ImportPreflight.maxTasks));
      expect(
        utf8.encode(store.exportJson()).length,
        greaterThan(ImportPreflight.maxFileBytes),
      );

      final bundle = await store.exportBackup();
      expect(bundle.status, BackupStatus.split);
      expect(bundle.recoverable, isTrue);
      expect(bundle.parts.length, greaterThan(1));
      for (final part in bundle.parts) {
        expect(part.bytes, lessThanOrEqualTo(ImportPreflight.maxFileBytes));
      }

      // Restoring every volume in order, the way the screen tells the user to,
      // keeps the result library inside the caps at every step and ends with the
      // whole library back.
      final target = fresh();
      await target.init();
      var children = 0;
      for (final part in bundle.parts) {
        final plan = target.previewImport(
          _payload(part.json),
          part.index == 1 ? 'overwrite' : 'merge',
        );
        expect(plan.conflicts, 0, reason: 'volume ${part.index}');
        expect(
          (await target.applyImport(plan)).success,
          isTrue,
          reason: 'volume ${part.index}',
        );
        expect(
          target.tasks.length,
          lessThanOrEqualTo(ImportPreflight.maxTasks),
        );
        children = target.tasks.fold(
          0,
          (sum, task) => sum + task.subtasks.length,
        );
        expect(children, lessThanOrEqualTo(ImportPreflight.maxSubtasks));
      }
      expect(target.tasks, hasLength(ImportPreflight.maxTasks));
      expect(children, ImportPreflight.maxSubtasks);
      expect(
        target.tasks.firstWhere((task) => task.id == 't0').notesMarkdown,
        _cjk * 200,
      );
      expect(
        target.tasks.firstWhere((task) => task.id == 't7').subtasks,
        hasLength(perTask),
      );
    },
  );

  testWidgets('RF04 export writes one file per part', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = Store();
    late String aId;
    late String bId;
    final notes = _cjk * 440000;
    // 10.6 MB of text cannot be carried by the 8 MiB file ceiling. The v3
    // content/dependency budget determines the volume count. `Store.init` starts a
    // periodic timer, so it is built on the real clock.
    await tester.runAsync(() async {
      await store.init();
      store.createBoard('A');
      aId = store.boards.last.id;
      store.createBoard('B');
      bId = store.boards.last.id;
      store.addTasks([
        for (var i = 0; i < 6; i++)
          Task(
            id: 'a$i',
            boardId: aId,
            title: 'A$i',
            quadrant: 1,
            createdAt: 1,
            notesMarkdown: notes,
          ),
        for (var i = 0; i < 2; i++)
          Task(
            id: 'b$i',
            boardId: bId,
            title: 'B$i',
            quadrant: 1,
            createdAt: 1,
            notesMarkdown: notes,
          ),
      ]);
    });
    addTearDown(store.dispose);
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (inner) {
              context = inner;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    final written = <String, Uint8List>{};
    final flow = SettingsBackupFlow(
      onBusyChanged: (_) {},
      writeFile: (path, bytes) async => written[path] = bytes,
    );
    final total = (await tester.runAsync(store.exportBackup))!.parts.length;
    expect(total, greaterThan(1));
    final picker = _Recorder(saves: total);
    FilePicker.platform = picker;
    final result = await _exportWithChoice(tester, flow, context, store);
    expect(result.outcome, BackupOutcome.succeeded);
    expect(picker.asked, hasLength(total));
    expect(picker.asked.first, contains('part1of$total'));
    expect(picker.asked.last, contains('part${total}of$total'));
    expect(result.message, contains('$total'));
    expect(result.message, contains(store.t['exportPartsHint']));
    // What the files carry is a part set a fresh library can restore: every
    // file is inside the ceiling and together they hold all eight tasks.
    expect(written, hasLength(total));
    final ids = <String>{};
    for (final bytes in written.values) {
      expect(bytes, hasLength(lessThanOrEqualTo(ImportPreflight.maxFileBytes)));
      final payload = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      ids.addAll(
        (payload['tasks'] as List).map((task) => (task as Map)['id'] as String),
      );
    }
    expect(ids, hasLength(8));

    // Cancelling halfway reports a cancellation, not a finished backup.
    FilePicker.platform = _Recorder(saves: 1);
    final partial = <String, Uint8List>{};
    final cancelled = await _exportWithChoice(
      tester,
      SettingsBackupFlow(
        onBusyChanged: (_) {},
        writeFile: (path, bytes) async => partial[path] = bytes,
      ),
      context,
      store,
    );
    expect(cancelled.outcome, BackupOutcome.cancelled);
    expect(cancelled.message, isNull);
    expect(partial, hasLength(1));

    // A write that fails is reported as a failure with the export copy.
    FilePicker.platform = _Recorder(saves: 1);
    final broken = await _exportWithChoice(
      tester,
      SettingsBackupFlow(
        onBusyChanged: (_) {},
        writeFile: (path, bytes) async =>
            throw StateError('synthetic write failure'),
      ),
      context,
      store,
    );
    expect(broken.outcome, BackupOutcome.failed);
    expect(broken.message, store.t['exportError']);

    // An import over the ceiling names the limit, and the library survives it.
    FilePicker.platform = _Recorder(
      pickBytes: Uint8List.fromList(
        utf8.encode(_paddedTo(_doc(), ImportPreflight.maxFileBytes + 1)),
      ),
    );
    final imported = await flow.importBackup(
      context,
      store,
      syncAiFields: () {},
    );
    expect(imported.outcome, BackupOutcome.failed);
    expect(imported.message, store.t['importErrorTooLarge']);
    expect(store.tasks, hasLength(8));
  });

  test(
    'RF04 splitting keeps the credential choice to exactly one part',
    () async {
      SharedPreferences.setMockInitialValues({});
      const sentinel = 'SYNTHETIC_RF04_SENTINEL_INVALID';
      final credential = _Credential();
      final store = Store(credentialStore: credential);
      await store.init();
      addTearDown(store.dispose);
      expect(await store.updateAIConfig(AIConfig(apiKey: sentinel)), isTrue);
      final notes = _cjk * 440000;
      store.createBoard('A');
      final aId = store.boards.last.id;
      store.addTasks([
        for (var i = 0; i < 8; i++)
          Task(
            id: 'a$i',
            boardId: aId,
            title: 'A$i',
            quadrant: 1,
            createdAt: 1,
            notesMarkdown: notes,
          ),
      ]);

      final defaultBundle = await store.exportBackup();
      expect(defaultBundle.status, BackupStatus.split);
      expect(
        defaultBundle.parts.any((part) => part.json.contains('customApiKey')),
        isFalse,
      );

      final withKey = await store.exportBackup(includeCredential: true);
      expect(withKey.status, BackupStatus.split);
      expect(
        withKey.parts.where((part) => part.json.contains(sentinel)),
        hasLength(1),
      );
      final firstConfig =
          jsonDecode(withKey.parts.first.json)['aiConfig']
              as Map<String, dynamic>;
      expect(firstConfig['customApiKey'], sentinel);
      expect(
        withKey.parts.skip(1).every((part) => !part.json.contains(sentinel)),
        isTrue,
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('matrixflow-config'), isNot(contains(sentinel)));
    },
  );

  test('RF03/RF04 explicit export waits for the latest credential', () async {
    SharedPreferences.setMockInitialValues({});
    final credentials = _DelayedCredential();
    final store = Store(credentialStore: credentials);
    await store.init();
    addTearDown(store.dispose);
    expect(
      await store.updateAIConfig(AIConfig(apiKey: 'synthetic-old')),
      isTrue,
    );

    credentials.delayNextWrite = true;
    final updating = store.updateAIConfig(AIConfig(apiKey: 'synthetic-new'));
    await credentials.entered.future;
    var exportFinished = false;
    final exporting = store.exportBackup(includeCredential: true).then((value) {
      exportFinished = true;
      return value;
    });
    await Future<void>.delayed(Duration.zero);
    expect(exportFinished, isFalse);

    credentials.release.complete();
    expect(await updating, isTrue);
    final bundle = await exporting;
    expect(bundle.recoverable, isTrue);
    final payload =
        jsonDecode(bundle.parts.single.json) as Map<String, dynamic>;
    final config = payload['aiConfig'] as Map<String, dynamic>;
    expect(config['customApiKey'], 'synthetic-new');
    expect(credentials.value, 'synthetic-new');
  });
}

Future<BackupResult> _exportWithChoice(
  WidgetTester tester,
  SettingsBackupFlow flow,
  BuildContext context,
  Store store,
) async {
  final running = flow.export(context, store);
  await tester.pumpAndSettle();
  await tester.tap(find.text(store.t['exportWithoutCredential']!).last);
  await tester.pumpAndSettle();
  return running;
}

List<String> _tasksOf(List<BackupPart> parts) => [
  for (final part in parts)
    for (final task in (jsonDecode(part.json)['tasks'] as List))
      (task as Map)['id'] as String,
];

BackupRejectedException _rejection(void Function() body) {
  Object? thrown;
  try {
    body();
  } catch (error) {
    thrown = error;
  }
  expect(thrown, isA<FormatException>());
  return thrown as BackupRejectedException;
}
