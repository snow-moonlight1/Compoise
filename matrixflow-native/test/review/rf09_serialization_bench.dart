// RF09 serialization bench — byte fingerprint + real-code cost of the save path.
//
// This is a measurement and golden-format tool, not a regression test. It asserts
// nothing and is deliberately NOT named `*_test.dart`, so the default
// `flutter test` run never collects it. Execute by explicit path:
//
//   flutter test --no-pub test/review/rf09_serialization_bench.dart
//
// Knobs, all via --dart-define:
//   RF09S_ONLY=format,protocol,command      sections to run (default: all)
//   RF09S_SCALES=3,100,1000,10000           library sizes for protocol/command
//   RF09S_REPS=7 / RF09S_WARMUP=3           timed / untimed samples
//
// Unlike docs/RF09_MEASUREMENT.md's M1/M2, which price *copies* of the encode
// chain, every number here comes from calling the production APIs:
// `SaveProtocol.commit` (protocol) and `Store` commands (command). That is what
// makes a before/after run of this file a fair A/B for C1/C2, and it is why the
// `format` section prints byte fingerprints of what production actually wrote.
//
// All timings are Dart VM JIT (`flutter test`). Run this file alone: a
// concurrent suite reverses conclusions (docs/RF09_MEASUREMENT.md §5).
import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _onlyDefine = String.fromEnvironment('RF09S_ONLY');
const int _reps = int.fromEnvironment('RF09S_REPS', defaultValue: 7);
const int _warmup = int.fromEnvironment('RF09S_WARMUP', defaultValue: 3);
const int _seed = int.fromEnvironment('RF09S_SEED', defaultValue: 20260926);
final List<int> scales = _parseInts(
  String.fromEnvironment('RF09S_SCALES'),
  const <int>[3, 100, 1000, 10000],
);

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
    _onlyDefine.trim().isEmpty ||
    _onlyDefine
        .split(',')
        .map((part) => part.trim().toLowerCase())
        .contains(section.toLowerCase());

/// Per-edit cost grows linearly with the library, so the sample count shrinks as
/// the scale grows. Same schedule as rf09_measurement.dart so the two files can
/// be read side by side.
int repsFor(int n) {
  if (n >= 10000) return 3;
  if (n >= 1000) return max(4, _reps ~/ 2);
  return _reps;
}

// ---------------------------------------------------------------------------
// Synthetic data — same generator, seed and field mix as rf09_measurement.dart
// so absolute µs and byte counts line up with docs/RF09_MEASUREMENT.md.
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
// Reporting / timing plumbing — same shape as rf09_measurement.dart
// ---------------------------------------------------------------------------

void emit(String section, Map<String, Object?> fields) {
  final parts = <String>['RF09S', section];
  fields.forEach((key, value) => parts.add('$key=${_oneLine(value)}'));
  // The harness reports through stdout; nothing is asserted.
  // ignore: avoid_print
  print(parts.join(','));
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

Future<List<int>> sample(
  Future<int> Function() body, {
  required int reps,
  required int warmup,
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

/// Independent Adler-32 over UTF-8 bytes, used only to fingerprint the exact
/// bytes production wrote. It mirrors nothing in `SaveProtocol`: this one runs on
/// the whole payload, so any change in framing or escaping shows up here.
int payloadFingerprint(String payload) {
  var a = 5381;
  for (final byte in utf8.encode(payload)) {
    a = ((a << 5) + a + byte) & 0x7FFFFFFF;
  }
  return a;
}

/// The six persisted keys, in the order `_snapshotValues` builds them.
const List<String> persistedKeys = <String>[
  'matrixflow-tasks',
  'matrixflow-boards',
  'matrixflow-config',
  'matrixflow-settings',
  'matrixflow-active-board',
  'matrixflow-has-seen-onboarding',
];

Map<String, String> snapshotValues(List<Task> library) => <String, String>{
  'matrixflow-tasks': jsonEncode(
    library.map((task) => task.toJson()).toList(),
  ),
  'matrixflow-boards': jsonEncode(<Object>[
    Board(id: boardId, name: '测量板', createdAt: 0).toJson(),
  ]),
  'matrixflow-config': jsonEncode(AIConfig().toJson(includeCredential: false)),
  'matrixflow-settings': jsonEncode(
    AppSettings(language: Language.zh).toJson(),
  ),
  'matrixflow-active-board': boardId,
  'matrixflow-has-seen-onboarding': 'true',
};

// ---------------------------------------------------------------------------
// F1 — byte fingerprints of what production writes
// ---------------------------------------------------------------------------

Future<void> measureFormat() async {
  if (!wanted('format')) return;
  for (final n in scales) {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final writes = <String, String>{};
    final order = <String>[];
    final protocol = SaveProtocol(
      prefs,
      writer: (key, value) async {
        order.add(key);
        writes[key] = value;
        return prefs.setString(key, value);
      },
    );
    final values = snapshotValues(synthLibrary(n, _seed));
    final result = await protocol.commit(values);
    final slotA = writes['matrixflow-save-a']!;
    final decoded = jsonDecode(slotA) as Map<String, dynamic>;
    final mirror = prefs.getString('matrixflow-tasks')!;
    emit('f1_slot', <String, Object?>{
      'tasks': n,
      'revision': result.revision,
      'payload_bytes': utf8Len(slotA),
      'payload_fp': payloadFingerprint(slotA),
      'check': decoded['check'],
      'keys': (decoded['values'] as Map<String, dynamic>).keys.join('/'),
      'write_order': order.join('/'),
      'mirror_bytes': utf8Len(mirror),
      'mirror_fp': payloadFingerprint(mirror),
      'mirror_equals_input': mirror == values['matrixflow-tasks'],
      'payload_head': slotA.substring(0, min(64, slotA.length)),
      'payload_tail': slotA.substring(max(0, slotA.length - 48)),
    });
    final reloaded = SaveProtocol(prefs).load();
    emit('f1_reload', <String, Object?>{
      'tasks': n,
      'loads': reloaded != null,
      'loaded_revision': reloaded?.revision,
      'loaded_values_fp': reloaded == null
          ? 0
          : payloadFingerprint(jsonEncode(reloaded.values)),
    });
  }
}

// ---------------------------------------------------------------------------
// F2 — real SaveProtocol.commit cost, split into CPU-before-first-write and IO
// ---------------------------------------------------------------------------

Future<void> measureProtocol() async {
  if (!wanted('protocol')) return;
  for (final n in scales) {
    final values = snapshotValues(synthLibrary(n, _seed));
    final payloadSizes = <int>{};
    final clock = Stopwatch();
    final preIo = <int>[];
    var slotWrites = 0;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final protocol = SaveProtocol(
      prefs,
      writer: (key, value) async {
        if (key == 'matrixflow-save-a' || key == 'matrixflow-save-b') {
          slotWrites++;
          preIo.add(clock.elapsedMicroseconds);
          payloadSizes.add(utf8Len(value));
        }
        return true;
      },
    );
    final reps = repsFor(n);
    final warmups = _warmup;
    final totals = Stats.of(
      await sample(
        () async {
          slotWrites = 0;
          clock
            ..reset()
            ..start();
          final sw = Stopwatch()..start();
          final result = await protocol.commit(values);
          sw.stop();
          clock.stop();
          sink += result.success ? 1 : 0;
          return sw.elapsedMicroseconds;
        },
        reps: reps,
        warmup: warmups,
      ),
    );
    // `sample` records through the warmup runs too, so the untimed prefix is
    // dropped before reporting.
    emit('f2_protocol_commit', <String, Object?>{
      'tasks': n,
      'samples': reps,
      'raw_values_bytes': utf8Len(values['matrixflow-tasks']!),
      'payload_bytes': payloadSizes.isEmpty
          ? 0
          : (payloadSizes.reduce((a, b) => a + b) / payloadSizes.length).round(),
      'distinct_payload_sizes': payloadSizes.length,
      'slot_writes': slotWrites,
      'revision': protocol.revision,
      // pre_io is the encode chain C2 targets: commit() call -> first slot write.
      ...Stats.of(preIo.sublist(warmups)).fields('cpu_before_first_write'),
      ...totals.fields('commit_total'),
    });
  }
}

// ---------------------------------------------------------------------------
// F3 — real Store command path: sync return, CPU before first write, visible
// ---------------------------------------------------------------------------

Future<Store> openStore(List<Task> library, Probe probe) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'matrixflow-boards': jsonEncode(<Object>[
      Board(id: boardId, name: '测量板', createdAt: 0).toJson(),
    ]),
    'matrixflow-tasks': '[]',
    'matrixflow-settings': jsonEncode(
      AppSettings(language: Language.zh).toJson(),
    ),
    'matrixflow-config': jsonEncode(AIConfig().toJson(includeCredential: false)),
    'matrixflow-active-board': boardId,
    'matrixflow-has-seen-onboarding': true,
  });
  final store = Store(
    deviceLocales: const <Locale>[Locale('zh')],
    reminders: InMemoryReminderService(),
    saveWriter: probe.write,
  );
  await store.init();
  store.debugReplaceTasks(library);
  await store.flush();
  probe.reset();
  return store;
}

class Probe {
  final Stopwatch clock = Stopwatch();
  final List<String> keys = <String>[];
  final List<int> bytes = <int>[];
  final List<int> starts = <int>[];
  String? lastSlotPayload;

  void reset() {
    keys.clear();
    bytes.clear();
    starts.clear();
    lastSlotPayload = null;
  }

  Future<bool> write(String key, String value) async {
    keys.add(key);
    bytes.add(utf8Len(value));
    starts.add(clock.elapsedMicroseconds);
    if (key == 'matrixflow-save-a' || key == 'matrixflow-save-b') {
      lastSlotPayload = value;
    }
    return true;
  }
}

Future<void> measureCommands() async {
  if (!wanted('command')) return;
  for (final n in scales) {
    for (final scenario in <String>['local_edit', 'settings_toggle']) {
      final probe = Probe();
      final store = await openStore(synthLibrary(n, _seed), probe);
      final ids = store.tasks.map((task) => task.id).toList();
      final sync = <int>[];
      final preIo = <int>[];
      final visible = <int>[];
      final payloadBytes = <int>{};
      final payloadFps = <int>{};
      var tick = 0;
      final reps = repsFor(n);
      final warmups = max(1, reps ~/ 3);
      await sample(
        () async {
          probe.reset();
          probe.clock
            ..reset()
            ..start();
          final syncUs = timeUs(() {
            if (scenario == 'local_edit') {
              final id = ids[tick % ids.length];
              final task = store.tasks.firstWhere((t) => t.id == id);
              // A constant replacement title keeps the resulting snapshot, and
              // therefore the written bytes, identical from rep to rep.
              store.updateTask(Task.fromJson(task.toJson())..title = '改名');
            } else {
              store.updateSettings(
                (s) => withFontSize(s, FontSizePref.large),
              );
            }
          });
          await store.flush();
          probe.clock.stop();
          sync.add(syncUs);
          preIo.add(probe.starts.isEmpty ? 0 : probe.starts.first);
          visible.add(probe.clock.elapsedMicroseconds);
          if (probe.lastSlotPayload != null) {
            payloadBytes.add(utf8Len(probe.lastSlotPayload!));
            payloadFps.add(payloadFingerprint(probe.lastSlotPayload!));
          }
          tick++;
          return 0;
        },
        reps: reps,
        warmup: warmups,
      );
      final totalBytes = probe.bytes.fold<int>(0, (a, b) => a + b);
      emit('f3_command', <String, Object?>{
        'tasks': n,
        'scenario': scenario,
        'samples': reps,
        'writes_last_run': probe.keys.length,
        'write_order': probe.keys.join('/'),
        'bytes_last_run': totalBytes,
        'payload_bytes': payloadBytes.isEmpty ? 0 : payloadBytes.last,
        'payload_fps': payloadFps.length,
        // Revision digits differ per rep, so the fingerprint set is reported for
        // transparency; cross-run byte identity is proven by f1_slot.
        'check_last': probe.lastSlotPayload == null
            ? 0
            : (jsonDecode(probe.lastSlotPayload!) as Map)['check'],
        ...Stats.of(sync.sublist(warmups)).fields('sync'),
        ...Stats.of(preIo.sublist(warmups)).fields('pre_io'),
        ...Stats.of(visible.sublist(warmups)).fields('visible'),
      });
      store.dispose();
    }
  }
}

// ---------------------------------------------------------------------------
// Scrub fingerprint — the other place that recomputes a slot's check
// ---------------------------------------------------------------------------

Future<void> measureScrub() async {
  if (!wanted('format')) return;
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  final written = <String, String>{};
  final protocol = SaveProtocol(
    prefs,
    writer: (key, value) async {
      written[key] = value;
      return prefs.setString(key, value);
    },
  );
  final values = snapshotValues(const <Task>[]);
  final withKey = Map<String, String>.of(values);
  withKey['matrixflow-config'] = jsonEncode(<String, Object?>{
    'provider': 'custom',
    'baseUrl': 'https://example.invalid/v1',
    'model': 'synthetic"model',
    'customApiKey': 'sk-synthetic-never-real',
    'headers': {'X-Note': '中文 \\ back\nnewline'},
  });
  await protocol.commit(withKey);
  await protocol.commit(withKey);
  final beforeA = written['matrixflow-save-a']!;
  final ok = await protocol.scrubCredentials();
  final slotA = prefs.getString('matrixflow-save-a')!;
  final slotB = prefs.getString('matrixflow-save-b')!;
  final mirror = prefs.getString('matrixflow-config')!;
  emit('f4_scrub', <String, Object?>{
    'ok': ok,
    'before_fp': payloadFingerprint(beforeA),
    'slot_a_bytes': utf8Len(slotA),
    'slot_a_fp': payloadFingerprint(slotA),
    'slot_b_fp': payloadFingerprint(slotB),
    'mirror_fp': payloadFingerprint(mirror),
    'check_a': (jsonDecode(slotA) as Map)['check'],
    'loads_after': SaveProtocol(prefs).load() != null,
    'key_removed': !slotA.contains('sk-synthetic-never-real'),
  });
}

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Every section runs inside a test body: a `Store` cannot be built during
  // file loading, where flutter_test has no current invoker for its mocked
  // HttpClient. The sections print; they assert nothing.
  test('rf09 serialization bench', () async {
    if (wanted('format')) {
      await measureFormat();
      await measureScrub();
    }
    if (wanted('protocol')) await measureProtocol();
    if (wanted('command')) await measureCommands();
  });
}
