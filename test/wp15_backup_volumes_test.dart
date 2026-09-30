// Synthetic libraries only; the configuration credential below is test data.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/backup_export.dart';
import 'package:matrixflow_native/import_preflight.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/recovery_text.dart';
import 'package:matrixflow_native/schedule_item.dart';

const _mib = 1024 * 1024;
const _start = 1790701200000;

Map<String, dynamic> _board(String id) => {
  'id': id,
  'name': 'Board $id',
  'createdAt': 1,
};

Map<String, dynamic> _task(String id, String board, {String notes = ''}) =>
    Task(
      id: id,
      boardId: board,
      title: 'Task $id',
      quadrant: 2,
      createdAt: 1,
      plannedDate: DateTime(2026, 9, 30).millisecondsSinceEpoch,
      deadline: _start + 86400000,
      reminderAt: _start - 60000,
      notesMarkdown: notes,
      subtasks: [SubTask(id: '$id-child', title: 'Child $id')],
    ).toJson();

Map<String, dynamic> _block(String id, String task) => ScheduleItem.timeBlock(
  id: id,
  taskId: task,
  startAt: _start,
  endAt: _start + 3600000,
  timeZoneId: 'Asia/Shanghai',
).toJson();

Map<String, dynamic> _event(
  String id, {
  String? board,
  String? task,
  String title = 'Review 整😀 "quoted"\n',
}) => ScheduleItem.event(
  id: id,
  title: title,
  boardId: board,
  taskId: task,
  startAt: _start,
  endAt: _start + 7200000,
  timeZoneId: 'America/New_York',
).toJson();

Map<String, dynamic> _document({
  List<Map<String, dynamic>>? boards,
  List<Map<String, dynamic>>? tasks,
  List<Map<String, dynamic>>? schedules,
}) => {
  'version': 3,
  'timestamp': _start,
  'boards': boards ?? [_board('b')],
  'tasks': tasks ?? [_task('t', 'b')],
  'scheduleItems': schedules ?? [_block('block', 't')],
  'settings': AppSettings.fromJson({
    'language': 'ja',
    'theme': 'dark',
    'hideCompleted': true,
    'reduceMotion': true,
    'urgencyThresholdDays': 9,
  }).toJson(),
  'aiConfig': AIConfig(
    provider: 'custom',
    protocol: AIProtocol.anthropic,
    baseUrl: 'https://example.invalid/v1',
    model: 'synthetic-model',
    apiKey: 'synthetic-credential',
    enableThinking: true,
  ).toJson(includeCredential: true),
};

Map<String, dynamic> _decode(String json) =>
    ImportPreflight.decode(Uint8List.fromList(utf8.encode(json)));

class _Restored {
  List<Board> boards = [];
  List<Task> tasks = [];
  List<ScheduleItem> schedules = [];
  AppSettings? settings;
  AIConfig? config;

  void apply(Map<String, dynamic> payload, {required bool first}) {
    final plan = ImportPreflight.inspect(
      payload,
      first ? 'overwrite' : 'merge',
      currentBoards: boards,
      currentTasks: tasks,
      currentScheduleItems: schedules,
      revision: 0,
    );
    expect(plan.conflicts, 0);
    expect(
      plan.warnings.where((warning) => warning.contains('Orphan')),
      isEmpty,
    );
    boards = plan.boards;
    tasks = plan.tasks;
    schedules = plan.scheduleItems;
    if (first) {
      settings = plan.settings;
      config = plan.aiConfig;
    }
  }
}

Set<String> _canonical(Iterable<Map<String, dynamic>> records) =>
    records.map(jsonEncode).toSet();

_Restored _assertRestore(BackupBundle bundle, Map<String, dynamic> source) {
  expect(bundle.recoverable, isTrue);
  expect(bundle.parts, isNotEmpty);
  final restored = _Restored();
  for (final part in bundle.parts) {
    expect(part.index, restored.boards.isEmpty ? 1 : greaterThan(1));
    expect(part.total, bundle.parts.length);
    expect(part.bytes, lessThanOrEqualTo(ImportPreflight.maxFileBytes));
    final payload = _decode(part.json);
    if (source['version'] == 3) expect(payload['scheduleItems'], isA<List>());
    if (part.index > 1) {
      expect(payload.containsKey('settings'), isFalse);
      expect(payload.containsKey('aiConfig'), isFalse);
    }
    restored.apply(payload, first: part.index == 1);
  }
  if ((source['boards'] as List).isEmpty) {
    expect(restored.boards, hasLength(1));
  } else {
    expect(
      _canonical(restored.boards.map((board) => board.toJson())),
      _canonical((source['boards'] as List).cast<Map<String, dynamic>>()),
    );
  }
  expect(
    _canonical(restored.tasks.map((task) => task.toJson())),
    _canonical(
      (source['tasks'] as List).cast<Map<String, dynamic>>().map(
        (task) => Task.fromJson(task).toJson(),
      ),
    ),
  );
  expect(
    _canonical(restored.schedules.map((item) => item.toJson())),
    source['version'] == 3
        ? _canonical(
            (source['scheduleItems'] as List).cast<Map<String, dynamic>>(),
          )
        : <String>{},
  );
  expect(
    restored.settings?.toJson(),
    AppSettings.fromJson(source['settings'] as Map<String, dynamic>).toJson(),
  );
  expect(
    restored.config?.toJson(includeCredential: true),
    AIConfig.fromJson(
      source['aiConfig'] as Map<String, dynamic>,
    ).toJson(includeCredential: true),
  );
  return restored;
}

void _assertOwnership(BackupBundle bundle, Map<String, dynamic> source) {
  final firstBoards = <String, int>{};
  final firstTasks = <String, int>{};
  final schedules = <String, int>{};
  for (final part in bundle.parts) {
    final payload = _decode(part.json);
    final boardIds = {
      for (final board in payload['boards'] as List) board['id'] as String,
    };
    final taskIds = {
      for (final task in payload['tasks'] as List) task['id'] as String,
    };
    for (final id in boardIds) {
      firstBoards.putIfAbsent(id, () => part.index);
    }
    for (final id in taskIds) {
      firstTasks.putIfAbsent(id, () => part.index);
    }
    for (final item in payload['scheduleItems'] as List) {
      final id = item['id'] as String;
      expect(schedules.containsKey(id), isFalse, reason: 'duplicate $id');
      schedules[id] = part.index;
      if (item['taskId'] != null) {
        expect(taskIds, contains(item['taskId']));
        expect(part.index, firstTasks[item['taskId']], reason: id);
      } else {
        expect(boardIds, contains(item['boardId']));
        expect(part.index, firstBoards[item['boardId']], reason: id);
      }
    }
  }
  expect(schedules.length, (source['scheduleItems'] as List).length);
}

void _assertRefusal(String document, {BackupStatus? status}) {
  final result = buildBackupBundle(document);
  expect(result.recoverable, isFalse);
  expect(result.parts, isEmpty);
  if (status != null) expect(result.status, status);
}

void main() {
  test('v3 single file preserves all content and original bytes', () {
    final source = _document(
      schedules: [
        _block('block', 't'),
        _event('linked', task: 't'),
        _event('independent', board: 'b'),
      ],
    );
    final json =
        '\uFEFF${const JsonEncoder.withIndent('  ').convert(source)}\n';
    final bundle = buildBackupBundle(json);
    expect(bundle.status, BackupStatus.single);
    expect(bundle.parts.single.json, json);
    _assertRestore(bundle, source);
    _assertOwnership(bundle, source);
  });

  group('ordinary volumes', () {
    late Map<String, dynamic> source;
    late BackupBundle bundle;
    setUpAll(() {
      source = _document(
        boards: [_board('small'), _board('large'), _board('empty')],
        tasks: [
          _task('small-task', 'small'),
          for (var i = 0; i < 5; i++)
            _task('large-$i', 'large', notes: 'x' * (2 * _mib)),
        ],
        schedules: [
          _event('small-event', board: 'small'),
          _event('large-event', board: 'large'),
          _event('empty-event', board: 'empty'),
          for (var i = 0; i < 5; i++) ...[
            _block('block-$i', 'large-$i'),
            _event('linked-$i', task: 'large-$i'),
          ],
        ],
      );
      bundle = buildBackupBundle(jsonEncode(source));
    });

    test('events accompany the first board, including after a small group', () {
      expect(bundle.status, BackupStatus.split);
      expect(bundle.parts.length, greaterThan(2));
      expect(
        (_decode(bundle.parts.first.json)['boards'] as List).single['id'],
        'small',
      );
      _assertOwnership(bundle, source);
    });

    test(
      'every ordinary volume passes standalone preflight with dependencies',
      () {
        expect(bundle.recoverable, isTrue);
        for (final part in bundle.parts) {
          final payload = _decode(part.json);
          final plan = ImportPreflight.inspect(
            payload,
            'merge',
            currentBoards: const [],
            currentTasks: const [],
            revision: 0,
          );
          expect(plan.conflicts, 0);
          expect(plan.skipped, 0);
          expect(plan.tasks.length, (payload['tasks'] as List).length);
          expect(
            plan.scheduleItems.length,
            (payload['scheduleItems'] as List).length,
          );
        }
      },
    );

    test(
      'ordered restore preserves boards, tasks, schedules and configuration',
      () {
        _assertRestore(bundle, source);
      },
    );
  });

  test('schedule bytes split independent events even with no tasks', () {
    final source = _document(
      boards: [for (var i = 0; i < 3; i++) _board('b$i')],
      tasks: [],
      schedules: [
        for (var b = 0; b < 3; b++)
          for (var i = 0; i < 800; i++)
            _event('e$b-$i', board: 'b$b', title: '\u0001' * 640),
      ],
    );
    expect(jsonStringUtf8Length('\u0001' * 640), 3840);
    final bundle = buildBackupBundle(jsonEncode(source));
    expect(bundle.status, BackupStatus.split);
    expect(bundle.parts, hasLength(3));
    _assertOwnership(bundle, source);
    _assertRestore(bundle, source);
  });

  test(
    'linked schedule bytes force text recovery and empty v3 continuation lists',
    () {
      final source = _document(
        tasks: [_task('t', 'b', notes: '😀"\n' * (5 * _mib ~/ 8))],
        schedules: [
          for (var i = 0; i < 1200; i++)
            _event('linked-$i', task: 't', title: '整' * 1200),
          _block('block', 't'),
          _event('independent', board: 'b'),
        ],
      );
      final bundle = buildBackupBundle(jsonEncode(source));
      expect(bundle.status, BackupStatus.recovery);
      final firstTask = bundle.parts
          .map((part) => _decode(part.json)['tasks'] as List)
          .firstWhere((tasks) => tasks.isNotEmpty)
          .single;
      expect(firstTask.containsKey('notesMarkdown'), isFalse);
      _assertOwnership(bundle, source);
      final continuations = bundle.parts.where((part) {
        final payload = _decode(part.json);
        return (payload['tasks'] as List).isEmpty &&
            payload.containsKey('recoveryChunks');
      });
      expect(continuations, isNotEmpty);
      for (final part in continuations) {
        final payload = _decode(part.json);
        expect(payload['version'], 3);
        expect(payload['scheduleItems'], isEmpty);
        expect(payload['recoveryChunks'], isNotEmpty);
      }
      final restored = _assertRestore(bundle, source);
      expect(restored.tasks.single.recoveryPending, isNull);
      expect(restored.tasks.single.subtasks.single.recoveryPending, isNull);
    },
  );

  test(
    'v3 recovery refuses reordered, corrupted and orphan continuation files',
    () {
      final source = _document(
        tasks: [_task('t', 'b', notes: '整😀"\n' * (13 * _mib ~/ 11))],
        schedules: [
          _block('block', 't'),
          _event('linked', task: 't'),
          _event('independent', board: 'b'),
        ],
      );
      final bundle = buildBackupBundle(jsonEncode(source));
      expect(bundle.status, BackupStatus.recovery);
      expect(bundle.parts.length, greaterThanOrEqualTo(3));
      _assertOwnership(bundle, source);
      _assertRestore(bundle, source);
      final first = _decode(bundle.parts.first.json);
      final last = _decode(bundle.parts.last.json);
      final state = _Restored()..apply(first, first: true);
      var beforeTasks = _canonical(state.tasks.map((task) => task.toJson()));
      var beforeSchedules = _canonical(
        state.schedules.map((item) => item.toJson()),
      );
      void refuses(Map<String, dynamic> payload, {List<Task>? tasks}) {
        expect(
          () => ImportPreflight.inspect(
            payload,
            'merge',
            currentBoards: state.boards,
            currentTasks: tasks ?? state.tasks,
            currentScheduleItems: tasks == null ? state.schedules : const [],
            revision: 0,
          ),
          throwsA(isA<FormatException>()),
        );
        expect(
          _canonical(state.tasks.map((task) => task.toJson())),
          beforeTasks,
        );
        expect(
          _canonical(state.schedules.map((item) => item.toJson())),
          beforeSchedules,
        );
      }

      refuses(last); // Missing the middle volume: offsets cannot skip a prefix.
      final next = _decode(bundle.parts[1].json);
      final corrupt = _decode(bundle.parts[1].json);
      final piece =
          (corrupt['recoveryChunks'] as List).first as Map<String, dynamic>;
      piece['prefixSha256'] = '0' * 64;
      refuses(corrupt);
      refuses(next, tasks: []);
      _assertRefusal(jsonEncode(corrupt), status: BackupStatus.incomplete);
      for (final part in bundle.parts.skip(1).take(bundle.parts.length - 2)) {
        state.apply(_decode(part.json), first: false);
      }
      beforeTasks = _canonical(state.tasks.map((task) => task.toJson()));
      beforeSchedules = _canonical(
        state.schedules.map((item) => item.toJson()),
      );
      final corruptFinal = _decode(bundle.parts.last.json);
      final finalPiece =
          (corruptFinal['recoveryChunks'] as List).last as Map<String, dynamic>;
      final text = finalPiece['text'] as String;
      finalPiece['text'] = 'X${text.substring(1)}';
      refuses(
        corruptFinal,
      ); // Final content must match the complete archive hash.
    },
  );

  test(
    'all independent events must fit with the first board or export refuses',
    () {
      final source = _document(
        tasks: [],
        schedules: [
          for (var i = 0; i < 2200; i++)
            _event('e$i', board: 'b', title: 'a' * 4096),
        ],
      );
      _assertRefusal(jsonEncode(source), status: BackupStatus.oversizedRecord);
    },
  );

  test(
    'an indivisible task schedule unit over the file ceiling refuses all parts',
    () {
      final source = _document(
        schedules: [
          for (var i = 0; i < 2200; i++)
            _event('e$i', task: 't', title: 'a' * 4096),
        ],
      );
      _assertRefusal(jsonEncode(source), status: BackupStatus.oversizedRecord);
    },
  );

  test(
    'schedule title ceiling uses escaped UTF8 even in recovery archives',
    () {
      for (final title in ['\u0001' * 683, '整' * 1366, '"' * 2049]) {
        final source = _document(
          schedules: [_event('event', board: 'b', title: title)],
        )..['recovery'] = true;
        _assertRefusal(
          jsonEncode(source),
          status: BackupStatus.oversizedRecord,
        );
      }
      final source = _document(
        schedules: [_event('event', board: 'b', title: '"' * 2048)],
      );
      _assertRestore(buildBackupBundle(jsonEncode(source)), source);
    },
  );

  test('ordinary schedule count cap becomes a complete recovery archive', () {
    final source = _document(
      schedules: [
        for (var i = 0; i <= ImportPreflight.maxScheduleItems; i++)
          _block('block-$i', 't'),
      ],
    );
    final bundle = buildBackupBundle(jsonEncode(source));
    expect(bundle.status, BackupStatus.recovery);
    expect(_decode(bundle.parts.single.json)['recovery'], isTrue);
    _assertRestore(bundle, source);
    _assertOwnership(bundle, source);
  });

  test(
    'malformed JSON, invalid envelopes and future versions return failure',
    () {
      for (final document in ['{', 'null', '[]', '42', '{"boards":[]}']) {
        _assertRefusal(document, status: BackupStatus.incomplete);
      }
      for (final version in [null, '3', 3.5, 4]) {
        final source = _document()..['version'] = version;
        _assertRefusal(jsonEncode(source), status: BackupStatus.incomplete);
      }
      final missing = _document()..remove('scheduleItems');
      _assertRefusal(jsonEncode(missing), status: BackupStatus.incomplete);
    },
  );

  test(
    'duplicates, corruption and orphan schedules refuse both single and split',
    () {
      for (final notes in ['', 'x' * (9 * _mib)]) {
        final valid = _block('s', 't');
        for (final schedules in <List<Map<String, dynamic>>>[
          [valid, valid],
          [
            valid,
            {...valid, 'endAt': _start + 1},
          ],
          [
            {...valid, 'taskId': 'missing'},
          ],
          [
            {...valid, 'taskId': 't-child'},
          ],
          [_event('s', board: 'missing')],
          [
            {...valid, 'kind': 'unknown'},
          ],
          [
            {...valid, 'endAt': _start},
          ],
          [
            {...valid, 'startAt': 'bad'},
          ],
          [
            {...valid, 'timeZoneId': 'Invalid/Zone'},
          ],
          [
            {...valid, 'boardId': 'b'},
          ],
        ]) {
          final source = _document(
            tasks: [_task('t', 'b', notes: notes)],
            schedules: schedules,
          );
          _assertRefusal(jsonEncode(source), status: BackupStatus.incomplete);
        }
      }
    },
  );

  test(
    'duplicate boards/tasks and corrupt settings/config cannot be concealed',
    () {
      for (final notes in ['', 'x' * (9 * _mib)]) {
        final source = _document(tasks: [_task('t', 'b', notes: notes)]);
        final bad = <Map<String, dynamic>>[
          {
            ...source,
            'boards': [_board('b'), _board('b')],
          },
          {
            ...source,
            'tasks': [source['tasks'][0], source['tasks'][0]],
          },
          {
            ...source,
            'boards': [_board('other')],
            'scheduleItems': [],
          },
          {...source, 'settings': 'bad'},
          {...source, 'aiConfig': []},
          {
            ...source,
            'aiConfig': {'customApiKey': 7},
          },
        ];
        for (final payload in bad) {
          _assertRefusal(jsonEncode(payload), status: BackupStatus.incomplete);
        }
      }
    },
  );

  test('oversized configuration returns no partial volumes', () {
    final source = _document()
      ..['aiConfig'] = {
        ...(_document()['aiConfig'] as Map<String, dynamic>),
        'customModel': 'x' * (9 * _mib),
      };
    _assertRefusal(jsonEncode(source), status: BackupStatus.oversizedRecord);
  });

  for (final version in [1, 2]) {
    test('v$version volumes continue to restore without scheduleItems', () {
      final source = _document(
        tasks: [
          for (var i = 0; i < 5; i++)
            _task('t$i', 'b', notes: 'x' * (2 * _mib)),
        ],
        schedules: [],
      )..['version'] = version;
      source.remove('scheduleItems');
      final bundle = buildBackupBundle(jsonEncode(source));
      expect(bundle.status, BackupStatus.split);
      for (final part in bundle.parts) {
        expect(_decode(part.json)['version'], version);
        expect(_decode(part.json).containsKey('scheduleItems'), isFalse);
      }
      _assertRestore(bundle, source);
    });
  }

  test('an unversioned legacy file still restores', () {
    final source = _document()
      ..remove('version')
      ..remove('scheduleItems');
    final bundle = buildBackupBundle(jsonEncode(source));
    expect(bundle.status, BackupStatus.single);
    _assertRestore(bundle, source);
  });

  test(
    'legacy documents with unknown schedules cannot claim lossless export',
    () {
      for (final version in [null, 1, 2]) {
        final source = _document();
        if (version == null) {
          source.remove('version');
        } else {
          source['version'] = version;
        }
        _assertRefusal(jsonEncode(source), status: BackupStatus.incomplete);
      }
    },
  );

  test(
    'empty v1/v2/v3 libraries tolerate the generated overwrite default board',
    () {
      for (final version in [1, 2, 3]) {
        final source = _document(boards: [], tasks: [], schedules: [])
          ..['version'] = version;
        if (version != 3) source.remove('scheduleItems');
        final bundle = buildBackupBundle(jsonEncode(source));
        expect(bundle.status, BackupStatus.single);
        _assertRestore(bundle, source);
      }
    },
  );
}
