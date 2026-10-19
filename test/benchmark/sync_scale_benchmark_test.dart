// Scale benchmark for v1.2.0 sync (docs/implementation-plan.md 6.1).
//
// Skipped unless COMPOISE_BENCH=1, so the normal suite stays fast:
//
//   COMPOISE_BENCH=1 flutter test --no-pub test/benchmark/sync_scale_benchmark_test.dart
//
// Set COMPOISE_BENCH_OUT to also write the Markdown table to a file. Numbers
// come from the JIT test runner, which is slower than a release build; use
// them to compare sizes and trends, not as device frame times.
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:compoise/models.dart';
import 'package:compoise/schedule_item.dart';
import 'package:compoise/storage.dart';
import 'package:compoise/sync/sync_crypto.dart';
import 'package:compoise/sync/sync_files.dart';
import 'package:compoise/sync/sync_library.dart';
import 'package:compoise/sync/sync_round.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final bool _enabled = Platform.environment['COMPOISE_BENCH'] == '1';

List<Board> _boards() => [
  for (var i = 0; i < 4; i++)
    Board(id: 'board$i', name: 'Board $i', createdAt: i),
];

List<Task> _tasks(int count, Random random) {
  const words = [
    'report',
    'call',
    'review',
    'plan',
    'buy',
    'fix',
    'email',
    'draft',
    '整理',
    '复习',
    '会议',
    '提交',
  ];
  String phrase(int n) =>
      List.generate(n, (_) => words[random.nextInt(words.length)]).join(' ');
  final base = DateTime.utc(2025).millisecondsSinceEpoch;
  return [
    for (var i = 0; i < count; i++)
      Task(
        id: 'task-${i.toString().padLeft(6, '0')}-${random.nextInt(1 << 30)}',
        boardId: 'board${i % 4}',
        title: phrase(3 + random.nextInt(4)),
        quadrant: 1 + random.nextInt(4),
        completed: random.nextInt(5) == 0,
        createdAt: base + i * 60000,
        deadline: random.nextBool() ? base + random.nextInt(1 << 30) : null,
        notesMarkdown: random.nextInt(3) == 0 ? phrase(30) : null,
        tags: random.nextInt(4) == 0 ? ['work', 'q${random.nextInt(4)}'] : null,
        subtasks: [
          for (var j = 0; j < random.nextInt(5); j++)
            SubTask(
              id: 'sub$j',
              title: phrase(3),
              completed: random.nextBool(),
            ),
        ],
      ),
  ];
}

List<ScheduleItem> _schedule(List<Task> tasks, Random random) {
  final base = DateTime.utc(2025).millisecondsSinceEpoch;
  return [
    for (var i = 0; i < tasks.length ~/ 5; i++)
      ScheduleItem.timeBlock(
        id: 'block$i',
        taskId: tasks[random.nextInt(tasks.length)].id,
        startAt: base + i * 3600000,
        endAt: base + i * 3600000 + 1800000,
        timeZoneId: 'Asia/Shanghai',
      ),
  ];
}

Future<double> _ms(Future<void> Function() body, {int runs = 3}) async {
  final samples = <int>[];
  for (var i = 0; i < runs; i++) {
    final watch = Stopwatch()..start();
    await body();
    samples.add(watch.elapsedMicroseconds);
  }
  samples.sort();
  return samples[samples.length ~/ 2] / 1000;
}

String _kb(int bytes) => (bytes / 1024).toStringAsFixed(0);

const _device = SyncDeviceInfo(
  id: 'benchdevice1',
  name: 'bench',
  platform: 'test',
  appVersion: 'bench',
);

SyncRoundInput _input({
  required String? state,
  required SyncLibrary live,
  AbsorbMode absorb = AbsorbMode.edits,
  List<PeerBlob> peers = const [],
  Uint8List? key,
  String? uploadedDigest,
}) => SyncRoundInput(
  localState: state,
  live: live,
  absorb: absorb,
  nowMs: DateTime.now().millisecondsSinceEpoch,
  peers: peers,
  key: key,
  encrypted: key != null,
  vaultId: 'benchvault1',
  device: _device,
  uploadedDigest: uploadedDigest,
  forceUpload: false,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'sync scale benchmark',
    () async {
      final rows = <String>[
        '| Tasks | Subtasks | Startup load | Edit → commit | Capture | First upload (plain / encrypted) | Edit → absorb | Edit → round | Join from file | Library JSON | State JSON | File plain / encrypted |',
        '|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|',
      ];
      final key = Uint8List.fromList(List<int>.generate(32, (i) => i));
      for (final count in [1000, 5000, 20000]) {
        final random = Random(count);
        final boards = _boards();
        final tasks = _tasks(count, random);
        final schedule = _schedule(tasks, random);
        final libraryJson = jsonEncode([
          for (final task in tasks) task.toJson(),
        ]);

        // Store: cold load and one edit committed (mock preferences, so this is
        // the encode/validate cost, not the platform file write).
        late Store store;
        final load = await _ms(() async {
          SharedPreferences.setMockInitialValues({
            'compoise-boards': jsonEncode([for (final b in boards) b.toJson()]),
            'compoise-tasks': libraryJson,
            'compoise-has-seen-onboarding': true,
          });
          store = Store();
          await store.init();
          await store.flush(waitForReminders: false);
        }, runs: 1);
        var n = 0;
        final commit = await _ms(() async {
          final task = Task.fromJson(store.tasks[count ~/ 2].toJson())
            ..title = 'edited ${n++}';
          store.updateTask(task);
          await store.flush(waitForReminders: false);
        }, runs: 5);

        late SyncLibrary live;
        final capture = await _ms(() async {
          live = SyncLibrary.fromModels(
            boards: store.boards,
            tasks: store.tasks,
            scheduleItems: schedule,
            settings: store.settings,
          );
        });
        store.dispose();

        late SyncRoundOutput plain;
        late SyncRoundOutput sealed;
        final firstPlain = await _ms(() async {
          plain = await computeSyncRound(_input(state: null, live: live));
        }, runs: 1);
        final firstSealed = await _ms(() async {
          sealed = await computeSyncRound(
            _input(state: null, live: live, key: key),
          );
        }, runs: 1);

        // One edit afterwards: absorb only, and a full round with no peers.
        final edited = SyncLibrary(
          boards: live.boards,
          tasks: [
            for (final (i, task) in live.tasks.indexed)
              i == 7 ? {...task, 'title': 'changed'} : task,
          ],
          scheduleItems: live.scheduleItems,
          settings: live.settings,
        );
        final absorb = await _ms(() async {
          computeAbsorb(
            sealed.state,
            edited,
            DateTime.now().millisecondsSinceEpoch,
          );
        });
        final round = await _ms(() async {
          await computeSyncRound(
            _input(
              state: sealed.state,
              live: edited,
              key: key,
              uploadedDigest: sealed.digest,
            ),
          );
        });

        // A second device joining: decrypt, merge and derive the whole vault.
        final join = await _ms(() async {
          final out = await computeSyncRound(
            _input(
              state: null,
              live: SyncLibrary(
                boards: [boards.first.toJson()],
                tasks: const [],
                scheduleItems: const [],
              ),
              absorb: AbsorbMode.none,
              key: key,
              peers: [
                PeerBlob(
                  name: deviceFileName(_device.id),
                  version: '1',
                  bytes: sealed.upload!,
                ),
              ],
            ),
          );
          expect(out.derived!.tasks, hasLength(count));
        }, runs: 1);

        final subtasks = tasks.fold<int>(
          0,
          (sum, task) => sum + task.subtasks.length,
        );
        final stateBytes = utf8.encode(sealed.state).length;
        rows.add(
          '| $count | $subtasks | ${load.toStringAsFixed(0)} ms | ${commit.toStringAsFixed(1)} ms | ${capture.toStringAsFixed(0)} ms '
          '| ${firstPlain.toStringAsFixed(0)} / ${firstSealed.toStringAsFixed(0)} ms | ${absorb.toStringAsFixed(0)} ms '
          '| ${round.toStringAsFixed(0)} ms | ${join.toStringAsFixed(0)} ms | ${_kb(libraryJson.length)} KB '
          '| ${_kb(stateBytes)} KB | ${_kb(plain.upload!.length)} / ${_kb(sealed.upload!.length)} KB |',
        );
        expect(isEncryptedEnvelope(sealed.upload!), isTrue);
      }
      final table = rows.join('\n');
      // ignore: avoid_print
      print('\n$table\n');
      final out = Platform.environment['COMPOISE_BENCH_OUT'];
      if (out != null) File(out).writeAsStringSync('$table\n');
    },
    skip: _enabled ? false : 'Set COMPOISE_BENCH=1 to run',
    timeout: const Timeout(Duration(minutes: 20)),
  );
}
