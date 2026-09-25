// RF04 measurement harness: sizes and timings of app-produced backups.
// Run explicitly (`flutter test test/review/rf04_size_measurement.dart`); it is
// not part of the default suite and asserts nothing, it only reports. Its
// numbers are the evidence behind the limits in `lib/import_preflight.dart`.
// Synthetic data only: no real user library, no real key.
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _zh = '整理季度报销单并核对发票';
const _ja = '四半期の経費精算をまとめる';

int _bytes(String value) => utf8.encode(value).length;

String _miB(int bytes) => '${(bytes / 1048576).toStringAsFixed(2)} MiB';

Task _task(
  int index,
  String boardId, {
  int children = 5,
  int notesChars = 0,
  bool structureOnly = false,
}) {
  return Task(
    id: structureOnly ? 'i' : 'mf-task-$index',
    boardId: boardId,
    title: structureOnly ? '' : '$_zh ${'タスク' * 2}$index',
    quadrant: (index % 4) + 1,
    createdAt: 1726000000000 + index,
    notesMarkdown: notesChars == 0 ? null : 'あ' * notesChars,
    subtasks: [
      for (var child = 0; child < children; child++)
        SubTask(
          id: structureOnly ? 'c' : 'mf-step-$index-$child',
          title: structureOnly ? '' : '$_ja$child',
          completed: child.isEven,
        ),
    ],
  );
}

Future<Store> _open(
  List<Task> tasks, {
  int boards = 1,
  bool structureOnly = false,
}) async {
  final seed = <String, Object>{
    'matrixflow-tasks': jsonEncode(tasks.map((t) => t.toJson()).toList()),
    'matrixflow-boards': jsonEncode([
      for (var b = 0; b < boards; b++)
        structureOnly
            ? {'id': 'b', 'name': '', 'createdAt': 0}
            : {'id': 'board-$b', 'name': '板 $b', 'createdAt': 1726000000000},
    ]),
    'matrixflow-active-board': structureOnly ? 'b' : 'board-0',
    'matrixflow-has-seen-onboarding': true,
  };
  SharedPreferences.setMockInitialValues(seed);
  final store = Store();
  await store.init();
  return store;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('measure per-record structural overhead', () async {
    SharedPreferences.setMockInitialValues({});
    final store = Store();
    await store.init();
    final empty = store.exportJson();
    final oneTask = store.newTask('');
    store.addTasks([oneTask]);
    final withTask = store.exportJson();
    print('RF04M emptyLibraryBytes=${_bytes(empty)} (${_miB(_bytes(empty))})');
    print('RF04M oneTaskDeltaBytes=${_bytes(withTask) - _bytes(empty)}');
    final childless = Task(
      id: 'x',
      boardId: 'b',
      title: '',
      quadrant: 1,
      createdAt: 1726000000000,
    );
    print('RF04M bareTaskRecordBytes=${_bytes(jsonEncode(childless.toJson()))}');
    final child = SubTask(id: 'c', title: '');
    print(
      'RF04M bareSubtaskBytes=${_bytes(jsonEncode(child.toJson()))} '
      'bareBoardBytes=${_bytes(jsonEncode(Board(id: 'b', name: '', createdAt: 0).toJson()))}',
    );
    store.dispose();
  });

  test('measure structure at the exact count caps', () async {
    final tasks = [
      for (var i = 0; i < ImportPreflight.maxTasks; i++)
        _task(i, 'b', children: ImportPreflight.maxSubtasks ~/ ImportPreflight.maxTasks, structureOnly: true),
    ];
    final store = await _open(tasks, boards: ImportPreflight.maxBoards, structureOnly: true);
    final backup = store.exportJson();
    print(
      'RF04M structureAtCaps boards=${ImportPreflight.maxBoards} '
      'tasks=${tasks.length} subtasks=${tasks.fold(0, (s, t) => s + t.subtasks.length)} '
      'fileBytes=${_bytes(backup)} (${_miB(_bytes(backup))})',
    );
    store.dispose();
  });

  for (final count in [500, 1000, 5000, 10000]) {
    test('measure realistic library of $count tasks', () async {
      final tasks = [
        for (var i = 0; i < count; i++) _task(i, 'board-0'),
      ];
      final store = await _open(tasks);
      final started = Stopwatch()..start();
      final backup = store.exportJson();
      started.stop();
      final encodeMicros = started.elapsedMicroseconds;
      final bytes = utf8.encode(backup);
      final raw = Uint8List.fromList(bytes);
      final decodeStarted = Stopwatch()..start();
      Map<String, dynamic>? payload;
      Object? decodeError;
      try {
        payload = ImportPreflight.decode(raw);
      } catch (error) {
        decodeError = error;
        utf8.decode(bytes);
        jsonDecode(utf8.decode(bytes));
      }
      decodeStarted.stop();
      SharedPreferences.setMockInitialValues({});
      final fresh = Store();
      await fresh.init();
      final inspectStarted = Stopwatch()..start();
      ImportPlan? plan;
      Object? inspectError;
      try {
        plan = fresh.previewImport(payload!, 'overwrite');
      } catch (error) {
        inspectError = error;
      }
      inspectStarted.stop();
      print(
        'RF04M tasks=$count subtasks=${count * 5} '
        'fileBytes=${bytes.length} (${_miB(bytes.length)}) '
        'encodeMs=${(encodeMicros / 1000).toStringAsFixed(0)} '
        'decodeMs=${(decodeStarted.elapsedMicroseconds / 1000).toStringAsFixed(0)} '
        'inspectMs=${(inspectStarted.elapsedMicroseconds / 1000).toStringAsFixed(0)} '
        'passesGate=${bytes.length <= ImportPreflight.maxBytes} '
        'decodeError=$decodeError inspectError=$inspectError '
        'planTasks=${plan?.tasks.length}',
      );
      fresh.dispose();
      store.dispose();
    });
  }

  test('measure CJK record cost and gate headroom', () async {
    final ascii = _task(0, 'board-0');
    final cjkBytes = _bytes(jsonEncode(ascii.toJson()));
    print('RF04M realisticTaskWith5SubtasksBytes=$cjkBytes');
    final tasks = [
      for (var i = 0; i < 2000; i++) _task(i, 'board-0'),
    ];
    final store = await _open(tasks);
    final backup = store.exportJson();
    print(
      'RF04M tasks=2000 fileBytes=${_bytes(backup)} '
      '(${_miB(_bytes(backup))}) passes4MiB=${_bytes(backup) <= ImportPreflight.maxBytes}',
    );
    store.dispose();
  });

  for (final notesChars in [1024, 16384, 65536, 262144]) {
    test('measure notes amplification at $notesChars chars', () async {
      final tasks = [
        for (var i = 0; i < 50; i++)
          _task(i, 'board-0', notesChars: notesChars),
      ];
      final store = await _open(tasks);
      final backup = store.exportJson();
      final fileBytes = _bytes(backup);
      final textBytes = notesChars * 3 * 50;
      print(
        'RF04M notesChars=$notesChars records=50 fileBytes=$fileBytes '
        '(${_miB(fileBytes)}) notesUtf8Bytes=$textBytes '
        'cjkBytesPerChar=${(fileBytes / (notesChars * 50)).toStringAsFixed(2)}',
      );
      store.dispose();
    });
  }

  test('measure escaping cost', () {
    final plain = 'a' * 100000;
    final quotes = '"' * 100000;
    final newlines = '\n' * 100000;
    final cjk = 'あ' * 100000;
    final emoji = '😀' * 100000;
    print(
      'RF04M escapeRatio ascii=${_bytes(jsonEncode(plain)) / plain.length} '
      'quote=${_bytes(jsonEncode(quotes)) / quotes.length} '
      'newline=${_bytes(jsonEncode(newlines)) / newlines.length} '
      'cjk=${_bytes(jsonEncode(cjk)) / cjk.length} '
      'emoji=${_bytes(jsonEncode(emoji)) / emoji.length}',
    );
  });

  test('measure single-record 4 MiB note', () async {
    SharedPreferences.setMockInitialValues({});
    final store = Store();
    await store.init();
    final task = store.newTask('Large valid notes')
      ..notesMarkdown = 'x' * ImportPreflight.maxBytes;
    store.addTasks([task]);
    final backup = store.exportJson();
    final bytes = utf8.encode(backup).length;
    Object? error;
    try {
      ImportPreflight.decode(Uint8List.fromList(utf8.encode(backup)));
    } catch (e) {
      error = e;
    }
    print(
      'RF04M singleNoteChars=${ImportPreflight.maxBytes} fileBytes=$bytes '
      '(${_miB(bytes)}) wrappingBytes=${bytes - ImportPreflight.maxBytes} '
      'gate=${ImportPreflight.maxBytes} error=$error',
    );
    store.dispose();
  });
}
