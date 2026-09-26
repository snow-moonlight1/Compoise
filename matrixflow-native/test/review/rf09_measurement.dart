// RF09 measurement harness — save/query cost of the Store at 3 / 100 / 1000 / 10000 tasks.
//
// This is a measurement tool, not a regression test. It asserts nothing about
// product behaviour and is deliberately NOT named `*_test.dart`, so the default
// `flutter test` run never collects it. Execute by explicit path:
//
//   flutter test --no-pub test/review/rf09_measurement.dart
//
// Knobs, all via --dart-define:
//   RF09_SCALES=3,100,1000,10000                  library sizes to walk
//   RF09_ONLY=dead,encode,io,e2e,query,mem,build  sections to run (default: all)
//   RF09_REPS=9 / RF09_WARMUP=3                   timed / untimed samples
//   RF09_BATCH=50                                 tasks per batch operation
//   RF09_SEED=20260926                            synthetic data seed
//
// Every number comes from the Dart VM in JIT mode (`flutter test`). Release/AOT is
// a different machine model; docs/RF09_MEASUREMENT.md states what may not be
// transferred between them.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/screens/matrix_screen.dart';
import 'package:matrixflow_native/storage.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _scalesDefine = String.fromEnvironment('RF09_SCALES');
const int _reps = int.fromEnvironment('RF09_REPS', defaultValue: 9);
const int _warmup = int.fromEnvironment('RF09_WARMUP', defaultValue: 3);
const int _batchSize = int.fromEnvironment('RF09_BATCH', defaultValue: 50);
const int _seed = int.fromEnvironment('RF09_SEED', defaultValue: 20260926);
const String _only = String.fromEnvironment('RF09_ONLY');

final List<int> scales = _parseInts(_scalesDefine, const <int>[3, 100, 1000, 10000]);

const String boardId = 'board-measure';

/// Keeps encoded results observable so the VM cannot delete measured work.
int sink = 0;

List<int> _parseInts(String raw, List<int> fallback) {
  if (raw.trim().isEmpty) return fallback;
  final parsed = raw
      .split(',')
      .map((part) => int.tryParse(part.trim()))
      .whereType<int>()
      .where((value) => value > 0)
      .toList();
  return parsed.isEmpty ? fallback : parsed;
}

bool wanted(String section) =>
    _only.trim().isEmpty ||
    _only
        .split(',')
        .map((part) => part.trim().toLowerCase())
        .contains(section.toLowerCase());

/// Per-edit cost grows linearly with the library, so the number of samples has
/// to shrink as the scale grows or the 10000 rows would never finish. The
/// sample count actually used is emitted with every row.
int repsFor(int n, {bool heavy = false}) {
  if (heavy) {
    if (n >= 10000) return 1;
    if (n >= 1000) return 3;
    return max(3, _reps ~/ 3);
  }
  if (n >= 10000) return 3;
  if (n >= 1000) return max(4, _reps ~/ 2);
  return _reps;
}

/// Mutations per batch scenario, capped so an awaited batch stays runnable.
int batchFor(int n) {
  if (n >= 10000) return 5;
  if (n >= 1000) return 20;
  return _batchSize;
}

// ---------------------------------------------------------------------------
// Synthetic data
// ---------------------------------------------------------------------------

const List<String> _zhTitles = <String>[
  '整理季度复盘材料',
  '给供应商发送对账单',
  '修复登录页焦点丢失',
  '预约体检并确认空腹要求',
  '重写导入模块的错误提示',
  '和客户确认交付时间',
];

const List<String> _enTitles = <String>[
  'Ship the Windows tray menu copy review',
  'Refactor the deadline promotion pass',
  'Double-check backup restore on a second device',
  'Triage the reminder ledger failures',
  'Write release notes for the beta build',
];

/// A library of [count] parent tasks with a realistic field mix: mixed CJK/ASCII
/// titles, subtasks on ~30%, long-tail notes on ~15%, deadlines, reminders.
List<Task> synthLibrary(int count, int seed) {
  final rnd = Random(seed);
  final base = DateTime(2026, 3, 1).millisecondsSinceEpoch;
  return List<Task>.generate(count, (i) {
    final useZh = rnd.nextBool();
    final pool = useZh ? _zhTitles : _enTitles;
    final reminderAt = rnd.nextInt(12) == 0
        ? base + 86400000 + rnd.nextInt(400000)
        : null;
    return Task(
      id: 't$i',
      boardId: boardId,
      title: '${pool[i % pool.length]}${useZh ? '#' : ' #'}$i',
      quadrant: 1 + (i % 4),
      isLongTerm: rnd.nextInt(10) == 0,
      completed: rnd.nextInt(10) == 0,
      createdAt: base + i * 60000,
      deadline: rnd.nextInt(4) == 0 ? base + rnd.nextInt(40) * 86400000 : null,
      subtasks: rnd.nextInt(10) < 3
          ? List<SubTask>.generate(
              1 + rnd.nextInt(3),
              (s) => SubTask(
                id: 't$i-s$s',
                title: '子步骤 $i-$s',
                completed: rnd.nextInt(5) == 0,
                deadline: rnd.nextInt(6) == 0
                    ? base + rnd.nextInt(30) * 86400000
                    : null,
              ),
            )
          : <SubTask>[],
      reasoning: rnd.nextInt(8) == 0 ? '拆分依据：按交付阶段切分' : null,
      notesMarkdown: rnd.nextInt(100) < 15
          ? List<String>.filled(24, '背景与约束说明，需要保留上下文。').join('\n')
          : null,
      reminderAt: reminderAt,
      reminderTimezone: reminderAt == null ? null : 'Asia/Shanghai',
    );
  });
}

int utf8Len(String value) => utf8.encode(value).length;

int libraryBytes(List<Task> library) =>
    utf8Len(jsonEncode(library.map((t) => t.toJson()).toList()));

/// AppSettings has no copyWith, so a settings mutation rebuilds the whole value.
AppSettings withFontSize(AppSettings s, FontSizePref size) => AppSettings(
  language: s.language,
  theme: s.theme,
  themeColor: s.themeColor,
  defaultInputMode: s.defaultInputMode,
  viewMode: s.viewMode,
  fontSize: size,
  fontFamily: s.fontFamily,
  autoGroupAI: s.autoGroupAI,
  autoDecomposeAI: s.autoDecomposeAI,
  autoCompleteParent: s.autoCompleteParent,
  suppressGroupPrompt: s.suppressGroupPrompt,
  suppressLongTermPrompt: s.suppressLongTermPrompt,
  hideCompleted: s.hideCompleted,
  showCompletionRate: s.showCompletionRate,
  reduceMotion: s.reduceMotion,
  urgencyThresholdDays: s.urgencyThresholdDays,
  closeToTray: s.closeToTray,
  globalShortcut: s.globalShortcut,
);

// ---------------------------------------------------------------------------
// Timing / reporting plumbing
// ---------------------------------------------------------------------------

void emit(String section, Map<String, Object?> fields) {
  final parts = <String>['RF09', section];
  fields.forEach((key, value) => parts.add('$key=${_oneLine(value)}'));
  final line = parts.join(',');
  // The harness reports through stdout; nothing is asserted.
  // ignore: avoid_print
  print(line);
}

String _oneLine(Object? value) =>
    '$value'.replaceAll(',', ';').replaceAll('\n', ' ');

class Stats {
  final List<int> sortedUs;
  Stats._(this.sortedUs);

  factory Stats.of(List<int> raw) => Stats._(raw.toList()..sort());

  int get count => sortedUs.length;
  int get min => sortedUs.isEmpty ? 0 : sortedUs.first;
  int get max => sortedUs.isEmpty ? 0 : sortedUs.last;
  int get median => _at(0.5);
  int get p95 => _at(0.95);
  double get mean =>
      sortedUs.isEmpty ? 0 : sortedUs.reduce((a, b) => a + b) / sortedUs.length;

  /// Inter-quartile range as a fraction of the median: run-to-run spread.
  double get spread {
    if (sortedUs.length < 4 || median == 0) return 0;
    return (_at(0.75) - _at(0.25)) / median;
  }

  int _at(double q) {
    if (sortedUs.isEmpty) return 0;
    return sortedUs[((sortedUs.length - 1) * q).round()];
  }

  Map<String, Object?> fields(String prefix) => <String, Object?>{
    '${prefix}_med': median,
    '${prefix}_mean': _round1(mean),
    '${prefix}_min': min,
    '${prefix}_p95': p95,
    '${prefix}_max': max,
    '${prefix}_spread': _round3(spread),
  };
}

double _round1(num value) => (value * 10).round() / 10;
double _round3(num value) => (value * 1000).round() / 1000;

int timeUs(void Function() body) {
  final sw = Stopwatch()..start();
  body();
  sw.stop();
  return sw.elapsedMicroseconds;
}

Future<int> timeUsAsync(Future<void> Function() body) async {
  final sw = Stopwatch()..start();
  await body();
  sw.stop();
  return sw.elapsedMicroseconds;
}

Future<List<int>> sample(
  Future<int> Function() body, {
  int reps = _reps,
  int warmup = _warmup,
}) async {
  for (var i = 0; i < warmup; i++) {
    await body();
  }
  final out = <int>[];
  for (var i = 0; i < reps; i++) {
    out.add(await body());
  }
  return out;
}

/// Records every write the Store issues: key, payload size, and the wall-clock
/// offset/duration relative to the probe's own stopwatch.
class WriteLog {
  final List<String> keys = <String>[];
  final List<int> bytes = <int>[];
  final List<int> startUs = <int>[];
  final List<int> durUs = <int>[];

  int get totalBytes => bytes.fold(0, (a, b) => a + b);
  int get slotWrites =>
      keys.where((k) => k.startsWith('matrixflow-save-')).length;

  int bytesFor(String key) {
    var total = 0;
    for (var i = 0; i < keys.length; i++) {
      if (keys[i] == key) total += bytes[i];
    }
    return total;
  }

  void reset() {
    keys.clear();
    bytes.clear();
    startUs.clear();
    durUs.clear();
  }
}

class CommitProbe {
  final WriteLog log = WriteLog();
  final Stopwatch clock = Stopwatch();
  final Duration ioDelay;

  CommitProbe({this.ioDelay = Duration.zero});

  Future<bool> write(String key, String value) async {
    log.keys.add(key);
    log.bytes.add(utf8Len(value));
    log.startUs.add(clock.elapsedMicroseconds);
    final local = Stopwatch()..start();
    if (ioDelay > Duration.zero) await Future<void>.delayed(ioDelay);
    local.stop();
    log.durUs.add(local.elapsedMicroseconds);
    return true;
  }
}

/// A Store whose library is [library] and whose disk writes are observed by
/// [probe]. Seeding goes through `debugReplaceTasks` so setup work never lands
/// in the measured revision/commit counters.
Future<Store> openStore(
  List<Task> library, {
  CommitProbe? probe,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'matrixflow-boards': jsonEncode(<Object>[
      Board(id: boardId, name: '测量板', createdAt: 0).toJson(),
    ]),
    'matrixflow-tasks': '[]',
    'matrixflow-settings': jsonEncode(AppSettings(language: Language.zh).toJson()),
    'matrixflow-config': jsonEncode(AIConfig().toJson(includeCredential: false)),
    'matrixflow-active-board': boardId,
    'matrixflow-has-seen-onboarding': true,
  });
  final store = Store(
    deviceLocales: const <Locale>[Locale('zh')],
    reminders: InMemoryReminderService(),
    saveWriter: probe?.write,
  );
  await store.init();
  store.debugReplaceTasks(library);
  await store.flush();
  probe?.log.reset();
  return store;
}

// ---------------------------------------------------------------------------
// M1 — the encode whose result is thrown away
// ---------------------------------------------------------------------------

/// `Store._saveTasks()` is
///   `_write(_kTasks, jsonEncode(tasks.map((t) => t.toJson()).toList()))`
/// while `Store._write(key, value)` ignores both parameters and only bumps the
/// dirty revision. This measures the discarded value's production cost.
Future<void> measureDiscardedEncode() async {
  if (!wanted('dead')) return;
  for (final n in scales) {
    final library = synthLibrary(n, _seed);
    final bytes = libraryBytes(library);
    final encode = Stats.of(
      await sample(
        () async => timeUs(() {
          final encoded = jsonEncode(library.map((t) => t.toJson()).toList());
          sink += encoded.length;
        }),
      ),
    );
    final cloneTask = Stats.of(
      await sample(
        () async => timeUs(() {
          final one = Task.fromJson(library.first.toJson());
          sink += one.subtasks.length;
        }),
      ),
    );
    emit('m1_discarded_encode', <String, Object?>{
      'tasks': n,
      'tasks_json_bytes': bytes,
      'bytes_per_task': n == 0 ? 0 : (bytes / n).round(),
      ...encode.fields('discarded_full_encode'),
      ...cloneTask.fields('edited_task_clone'),
      'discarded_per_encoded_byte_us_x1000': encode.median == 0 || bytes == 0
          ? 0
          : _round3(encode.median * 1000 / bytes),
    });
  }
}

// ---------------------------------------------------------------------------
// M2 — stage-by-stage attribution of one commit's encode chain
// ---------------------------------------------------------------------------

/// Mirrors the real chain so each encode can be priced separately instead of
/// asserted: `_snapshotValues()` encodes every key; `SaveProtocol._commitOnce`
/// then encodes `body` (whose only consumer is the checksum), then `payload`
/// (the bytes actually written), then UTF-8 encodes `body` once more inside
/// `_checksum`.
Future<void> measureEncodeStages() async {
  if (!wanted('encode')) return;
  for (final n in scales) {
    final library = synthLibrary(n, _seed);
    final boards = <Board>[Board(id: boardId, name: '测量板', createdAt: 0)];
    final settings = AppSettings(language: Language.zh);
    final config = AIConfig();

    Map<String, String> snapshot() => <String, String>{
      'matrixflow-tasks': jsonEncode(
        library.map((t) => t.toJson()).toList(),
      ),
      'matrixflow-boards': jsonEncode(
        boards.map((b) => b.toJson()).toList(),
      ),
      'matrixflow-config': jsonEncode(
        config.toJson(includeCredential: false),
      ),
      'matrixflow-settings': jsonEncode(settings.toJson()),
      'matrixflow-active-board': boardId,
      'matrixflow-has-seen-onboarding': 'true',
    };

    final snap = Stats.of(
      await sample(() async => timeUs(() {
        final v = snapshot();
        sink += v.length;
      })),
    );

    final values = snapshot();
    final rawTasks = utf8Len(values['matrixflow-tasks']!);

    final body = Stats.of(
      await sample(() async => timeUs(() {
        final encoded = jsonEncode(<String, Object>{
          'revision': 1,
          'values': values,
        });
        sink += encoded.length;
      })),
    );

    final payload = Stats.of(
      await sample(() async => timeUs(() {
        final encoded = jsonEncode(<String, Object>{
          'revision': 1,
          'values': values,
          'check': 12345,
        });
        sink += encoded.length;
      })),
    );

    final bodyStr = jsonEncode(<String, Object>{
      'revision': 1,
      'values': values,
    });
    final checksum = Stats.of(
      await sample(() async => timeUs(() {
        var a = 1;
        var b = 0;
        for (final byte in utf8.encode(bodyStr)) {
          a = (a + byte) % 65521;
          b = (b + a) % 65521;
        }
        sink += a + b;
      })),
    );

    // What an encode-minimal commit of the same state would cost at best:
    // one snapshot plus one payload encode, no second body and no checksum.
    final ideal = Stats.of(
      await sample(() async => timeUs(() {
        final v = snapshot();
        final encoded = jsonEncode(<String, Object>{
          'revision': 1,
          'values': v,
          'check': 12345,
        });
        sink += encoded.length;
      })),
    );

    final bodyBytes = utf8Len(bodyStr);
    final chain =
        snap.median + body.median + payload.median + checksum.median;
    emit('m2_encode_stages', <String, Object?>{
      'tasks': n,
      'raw_tasks_bytes': rawTasks,
      'batch_body_bytes': bodyBytes,
      'escaping_overhead_bytes': bodyBytes - rawTasks,
      ...snap.fields('snap'),
      ...body.fields('body_encode'),
      ...payload.fields('payload_encode'),
      ...checksum.fields('utf8_checksum'),
      'chain_total_med': chain,
      ...ideal.fields('snapshot_plus_one_payload'),
      'chain_over_minimal_x': ideal.median == 0
          ? 0
          : _round3(chain / ideal.median),
    });
  }
}

// ---------------------------------------------------------------------------
// M3 — what one accepted mutation actually writes
// ---------------------------------------------------------------------------

Future<void> measureCommitIo() async {
  if (!wanted('io')) return;
  for (final n in scales) {
    final probe = CommitProbe();
    final store = await openStore(synthLibrary(n, _seed), probe: probe);
    final rawTasks = libraryBytes(store.tasks);

    probe.clock
      ..reset()
      ..start();
    store.updateTask(Task.fromJson(store.tasks.first.toJson())..title = '改名');
    await store.flush();
    probe.clock.stop();

    final log = probe.log;
    emit('m3_commit_io', <String, Object?>{
      'tasks': n,
      'raw_tasks_bytes': rawTasks,
      'writes_per_edit': log.keys.length,
      'write_order': log.keys.join('/'),
      'bytes_per_edit': log.totalBytes,
      'bytes_slot_batch': log.bytesFor('matrixflow-save-a') +
          log.bytesFor('matrixflow-save-b'),
      'bytes_tasks_mirror': log.bytesFor('matrixflow-tasks'),
      'written_over_raw_x': rawTasks == 0
          ? 0
          : _round3(log.totalBytes / rawTasks),
      'cpu_before_first_write': log.startUs.isEmpty ? 0 : log.startUs.first,
      'io_total': log.durUs.fold<int>(0, (a, b) => a + b),
      'e2e': probe.clock.elapsedMicroseconds,
    });
    store.dispose();
  }
}

// ---------------------------------------------------------------------------
// M4 — the four scenarios, split into sync / pre-IO CPU / IO / visible
// ---------------------------------------------------------------------------

Future<void> measureCommands() async {
  if (!wanted('e2e')) return;
  const scenarios = <String>[
    'local_edit',
    'settings_toggle',
    'batch_coalesced',
    'batch_awaited',
  ];
  for (final n in scales) {
    for (final scenario in scenarios) {
      final probe = CommitProbe(ioDelay: const Duration(microseconds: 150));
      final store = await openStore(synthLibrary(n, _seed), probe: probe);
      final ids = store.tasks.map((t) => t.id).toList();
      final sync = <int>[];
      final preIo = <int>[];
      final io = <int>[];
      final visible = <int>[];
      final writes = <int>[];
      final bytesWritten = <int>[];
      var tick = 0;
      final isBatch = scenario.startsWith('batch');
      final k = min(batchFor(n), ids.length);

      Future<int> run() async {
        probe.log.reset();
        probe.clock
          ..reset()
          ..start();
        var syncUs = 0;
        if (scenario == 'batch_awaited') {
          // Worst case: every mutation is given a chance to commit on its own,
          // which is what happens when the UI awaits between edits.
          for (var i = 0; i < k; i++) {
            syncUs += timeUs(() {
              store.setTaskCompleted(ids[(tick + i) % ids.length], (tick + i).isEven);
            });
            await store.flush();
          }
        } else {
          syncUs = timeUs(() {
            switch (scenario) {
              case 'local_edit':
                final id = ids[tick % ids.length];
                final task = store.tasks.firstWhere((t) => t.id == id);
                store.updateTask(
                  Task.fromJson(task.toJson())..title = '改名 $tick',
                );
              case 'settings_toggle':
                store.updateSettings(
                  (s) => withFontSize(
                    s,
                    tick.isEven ? FontSizePref.large : FontSizePref.standard,
                  ),
                );
              default:
                // A multi-select completion arrives as K mutations inside one
                // synchronous frame.
                for (var i = 0; i < k; i++) {
                  store.setTaskCompleted(ids[(tick + i) % ids.length], (tick + i).isEven);
                }
            }
          });
          await store.flush();
        }
        probe.clock.stop();
        tick++;
        sync.add(syncUs);
        writes.add(probe.log.slotWrites);
        bytesWritten.add(probe.log.totalBytes);
        preIo.add(probe.log.startUs.isEmpty ? 0 : probe.log.startUs.first);
        io.add(probe.log.durUs.fold(0, (a, b) => a + b));
        visible.add(probe.clock.elapsedMicroseconds);
        return 0;
      }

      final reps = repsFor(n, heavy: isBatch);
      await sample(run, reps: reps, warmup: isBatch ? 1 : max(1, reps ~/ 3));

      emit('m4_command', <String, Object?>{
        'tasks': n,
        'scenario': scenario,
        'batch': k,
        'samples': reps,
        'slot_writes_med': Stats.of(writes).median,
        'bytes_written_med': Stats.of(bytesWritten).median,
        ...Stats.of(sync).fields('sync'),
        ...Stats.of(preIo).fields('pre_io'),
        ...Stats.of(io).fields('io'),
        ...Stats.of(visible).fields('visible'),
      });
      store.dispose();
    }
  }
}

// ---------------------------------------------------------------------------
// M5 — read side: the containers pages touch during build
// ---------------------------------------------------------------------------

/// `Store.tasks` is `List.unmodifiable(_tasks)`, which copies rather than wraps,
/// and `visibleTasks` / `tasksIn` are built on top of it. A grid build calls
/// `tasksIn` four times plus one `tasks.map` in `MatrixHome.build`.
Future<void> measureQueries() async {
  if (!wanted('query')) return;
  for (final n in scales) {
    final library = synthLibrary(n, _seed);
    final store = await openStore(library);
    final copy = Stats.of(
      await sample(() async => timeUs(() {
        sink += store.tasks.length;
      })),
    );
    final visible = Stats.of(
      await sample(() async => timeUs(() {
        sink += store.visibleTasks.length;
      })),
    );
    final gridScan = Stats.of(
      await sample(() async => timeUs(() {
        for (var q = 1; q <= 4; q++) {
          sink += store.tasksIn(q).length;
        }
      })),
    );
    final lookup = Stats.of(
      await sample(() async => timeUs(() {
        sink += store.tasks.indexWhere((t) => t.id == 't${n - 1}');
      })),
    );
    // Candidate shape: one index built per revision, then O(1) lookups. The
    // build is measured separately because it is the cost a fix would pay once
    // instead of once per lookup.
    final byId = <String, Task>{for (final t in library) t.id: t};
    final indexBuild = Stats.of(
      await sample(() async => timeUs(() {
        final fresh = <String, Task>{for (final t in store.tasks) t.id: t};
        sink += fresh.length;
      })),
    );
    final lookupCached = Stats.of(
      await sample(() async => timeUs(() {
        sink += byId.containsKey('t${n - 1}') ? 1 : 0;
      })),
    );
    emit('m5_query', <String, Object?>{
      'tasks': n,
      'visible': store.visibleTasks.length,
      ...copy.fields('tasks_getter_copy'),
      ...visible.fields('visible_tasks'),
      ...gridScan.fields('four_quadrants'),
      ...lookup.fields('linear_lookup_worst'),
      ...indexBuild.fields('index_build_from_scratch'),
      ...lookupCached.fields('cached_index_lookup'),
      'grid_build_library_copies': 6,
    });
    store.dispose();
  }
}

// ---------------------------------------------------------------------------
// M6 — resident cost of a save burst
// ---------------------------------------------------------------------------

Future<void> measureMemory() async {
  if (!wanted('mem')) return;
  for (final n in scales) {
    final budget = n >= 10000 ? 8 : (n >= 1000 ? 25 : 120);
    final probe = CommitProbe(ioDelay: const Duration(microseconds: 120));
    final store = await openStore(synthLibrary(n, _seed), probe: probe);
    final ids = store.tasks.map((t) => t.id).toList();
    final run = min(budget, ids.length);
    await store.flush();
    probe.log.reset();
    final before = ProcessInfo.currentRss;
    final wallUs = await timeUsAsync(() async {
      for (var i = 0; i < run; i++) {
        final task = store.tasks.firstWhere((t) => t.id == ids[i]);
        store.updateTask(Task.fromJson(task.toJson())..title = 'mem $i');
        await store.flush();
      }
    });
    final after = ProcessInfo.currentRss;
    emit('m6_memory', <String, Object?>{
      'tasks': n,
      'commands': run,
      'rss_before_kb': before ~/ 1024,
      'rss_after_kb': after ~/ 1024,
      'rss_delta_kb': (after - before) ~/ 1024,
      'kb_per_edit': run == 0 ? 0 : ((after - before) ~/ 1024) ~/ run,
      'burst_wall_us': wallUs,
      'us_per_edit': run == 0 ? 0 : (wallUs / run).round(),
      'bytes_written_total': probe.log.totalBytes,
      'writes_total': probe.log.keys.length,
    });
    store.dispose();
  }
}

// ---------------------------------------------------------------------------
// M7 — home screen build cost
// ---------------------------------------------------------------------------

Widget wrapApp(Store store, Widget child) => ChangeNotifierProvider.value(
  value: store,
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    supportedLocales: const <Locale>[
      Locale('en'),
      Locale('zh'),
      Locale('ja'),
    ],
    home: child,
  ),
);

/// Build + layout + paint of the real home screen under the widget-test clock.
///
/// The earlier version of this measurement timed "mutate then pump" as one
/// number, which silently folded the queued commit into the rebuild and made
/// the series non-monotonic. It now settles the commit outside the timed
/// window, so [rebuild] is the pure build cost, and the first mount of each
/// scale is discarded as framework warm-up.
Future<void> measureBuild(WidgetTester tester) async {
  if (!wanted('build')) return;
  for (final n in scales) {
    late Store store;
    var visibleCount = 0;
    final mount = <int>[];
    final syncCmd = <int>[];
    final settle = <int>[];
    final rebuild = <int>[];
    final idle = <int>[];
    final reps = n >= 10000 ? 2 : (n >= 1000 ? 3 : 5);
    await tester.runAsync(() async {
      store = await openStore(synthLibrary(n, _seed));
      visibleCount = store.visibleTasks.length;
      await tester.binding.setSurfaceSize(const Size(1400, 950));
      // Untimed warm-up mount.
      await tester.pumpWidget(wrapApp(store, const MatrixHome()));
      await store.flush();
      await tester.pump();
      for (var i = 0; i < reps; i++) {
        await tester.pumpWidget(const SizedBox());
        mount.add(
          await timeUsAsync(
            () => tester.pumpWidget(wrapApp(store, const MatrixHome())),
          ),
        );
        syncCmd.add(
          timeUs(() {
            store.updateTask(
              Task.fromJson(store.tasks.first.toJson())..title = 'build $i',
            );
          }),
        );
        // Drain the commit and its listener rebuild outside the timed rebuild.
        settle.add(await timeUsAsync(() => store.flush()));
        await tester.pump();
        rebuild.add(await timeUsAsync(() => tester.pump()));
        idle.add(await timeUsAsync(() => tester.pump()));
      }
      await tester.pumpWidget(const SizedBox());
      store.dispose();
      await tester.binding.setSurfaceSize(null);
    });
    emit('m7_widget_build', <String, Object?>{
      'tasks': n,
      'visible': visibleCount,
      'samples': reps,
      ...Stats.of(mount).fields('mount'),
      ...Stats.of(syncCmd).fields('sync_command'),
      ...Stats.of(settle).fields('commit_settle'),
      ...Stats.of(rebuild).fields('rebuild'),
      ...Stats.of(idle).fields('idle_pump'),
    });
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('RF09 M1 discarded encode per task mutation', () async {
    await measureDiscardedEncode();
  }, timeout: const Timeout(Duration(minutes: 25)));

  test('RF09 M2 commit encode stages', () async {
    await measureEncodeStages();
  }, timeout: const Timeout(Duration(minutes: 25)));

  test('RF09 M3 writes and bytes per accepted edit', () async {
    await measureCommitIo();
  }, timeout: const Timeout(Duration(minutes: 25)));

  test('RF09 M4 command end to end by scenario', () async {
    await measureCommands();
  }, timeout: const Timeout(Duration(minutes: 45)));

  test('RF09 M5 read-side containers', () async {
    await measureQueries();
  }, timeout: const Timeout(Duration(minutes: 25)));

  test('RF09 M6 resident memory over a save burst', () async {
    await measureMemory();
  }, timeout: const Timeout(Duration(minutes: 30)));

  testWidgets('RF09 M7 home screen build cost', (tester) async {
    await measureBuild(tester);
  }, timeout: const Timeout(Duration(minutes: 40)));
}
