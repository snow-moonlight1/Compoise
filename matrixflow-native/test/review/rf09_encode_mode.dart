// RF09 run-mode cross-check for the encode chain (JIT vs AOT).
//
// `models.dart` imports `dart:ui`, so the real Store cannot be compiled ahead of
// time and measured by `dart run` / `dart compile exe`. This file therefore
// rebuilds the *same map shapes* that `Task.toJson` / `SubTask.toJson` produce,
// with the same synthetic content as rf09_measurement.dart, and re-times the
// four encode stages of one commit.
//
// It is not a measurement of the app. It only answers one question: how much of
// a JIT (`flutter test`) encode cost survives AOT (Release) compilation, so the
// JIT numbers in docs/RF09_MEASUREMENT.md are not silently read as Release
// numbers.
//
//   dart run    test/review/rf09_encode_mode.dart jit
//   dart compile exe -o ../../build/rf09_encode_mode.exe test/review/rf09_encode_mode.dart
//   ../../build/rf09_encode_mode.exe aot
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'dart:math';

const List<int> _scales = <int>[3, 100, 1000, 10000];
const int _reps = 15;
const int _warmup = 5;
const int _seed = 20260926;

/// Field-for-field replica of `Task.toJson()` (current version, not v1).
Map<String, Object> taskMap(int i, Random rnd, int base) {
  final useZh = rnd.nextBool();
  final titles = useZh
      ? <String>[
          '整理季度复盘材料',
          '给供应商发送对账单',
          '修复登录页焦点丢失',
          '预约体检并确认空腹要求',
          '重写导入模块的错误提示',
          '和客户确认交付时间',
        ]
      : <String>[
          'Ship the Windows tray menu copy review',
          'Refactor the deadline promotion pass',
          'Double-check backup restore on a second device',
          'Triage the reminder ledger failures',
          'Write release notes for the beta build',
        ];
  final reminderAt = rnd.nextInt(12) == 0
      ? base + 86400000 + rnd.nextInt(400000)
      : null;
  return <String, Object>{
    'id': 't$i',
    'boardId': 'board-measure',
    'title': '${titles[i % titles.length]}${useZh ? '#' : ' #'}$i',
    'quadrant': 1 + (i % 4),
    'isLongTerm': rnd.nextInt(10) == 0,
    'completed': rnd.nextInt(10) == 0,
    'createdAt': base + i * 60000,
    if (rnd.nextInt(4) == 0) 'deadline': base + rnd.nextInt(40) * 86400000,
    'subtasks': rnd.nextInt(10) < 3
        ? List<Object>.generate(
            1 + rnd.nextInt(3),
            (s) => <String, Object>{
              'id': 't$i-s$s',
              'title': '子步骤 $i-$s',
              'completed': rnd.nextInt(5) == 0,
              if (rnd.nextInt(6) == 0)
                'deadline': base + rnd.nextInt(30) * 86400000,
            },
          )
        : <Object>[],
    if (rnd.nextInt(8) == 0) 'reasoning': '拆分依据：按交付阶段切分',
    'urgencyMode': rnd.nextInt(6) == 0 ? 'manual' : 'auto',
    if (rnd.nextInt(100) < 15)
      'notesMarkdown': List<String>.filled(24, '背景与约束说明，需要保留上下文。').join('\n'),
    if (reminderAt != null) 'reminderAt': reminderAt,
    if (reminderAt != null) 'reminderTimezone': 'Asia/Shanghai',
  };
}

int sink = 0;

int timeUs(void Function() body) {
  final sw = Stopwatch()..start();
  body();
  sw.stop();
  return sw.elapsedMicroseconds;
}

List<int> reps(void Function() body) {
  for (var i = 0; i < _warmup; i++) {
    body();
  }
  return List<int>.generate(_reps, (_) => timeUs(body));
}

int median(List<int> sorted) => sorted[(sorted.length - 1) ~/ 2];

void main(List<String> args) {
  // The mode is passed in explicitly rather than guessed: a compiled exe and the
  // `dart` launcher are not reliably distinguishable from inside the isolate.
  final mode = args.isEmpty ? 'unknown' : args.first;
  print('MODE,$mode,${Platform.version.replaceAll('\n', ' | ')}');
  print('REPS,$_reps,WARMUP,$_warmup');

  for (final n in _scales) {
    final rnd = Random(_seed);
    final base = DateTime(2026, 3, 1).millisecondsSinceEpoch;
    final tasks = List<Map<String, Object>>.generate(n, (i) => taskMap(i, rnd, base));
    final snapshot = timeUs(() {
      final v = jsonEncode(tasks);
      sink += v.length;
    });
    Map<String, String> values() => <String, String>{
      'matrixflow-tasks': jsonEncode(tasks),
      'matrixflow-boards': jsonEncode(<Object>[
        <String, Object>{'id': 'board-measure', 'name': '测量板', 'createdAt': 0},
      ]),
      'matrixflow-config': jsonEncode(<String, Object>{
        'provider': 'openai_compatible',
        'baseUrl': 'https://api.example.invalid/v1',
        'model': 'some-model',
      }),
      'matrixflow-settings': jsonEncode(<String, Object>{
        'language': 'zh',
        'theme': 'system',
        'viewMode': 'grid',
      }),
      'matrixflow-active-board': 'board-measure',
      'matrixflow-has-seen-onboarding': 'true',
    };
    final v = values();
    final snap = median(reps(() {
      final s = values();
      sink += s.length;
    }));
    final body = median(reps(() {
      final s = jsonEncode(<String, Object>{'revision': 1, 'values': v});
      sink += s.length;
    }));
    final payload = median(reps(() {
      final s = jsonEncode(<String, Object>{
        'revision': 1,
        'values': v,
        'check': 12345,
      });
      sink += s.length;
    }));
    final bodyStr = jsonEncode(<String, Object>{'revision': 1, 'values': v});
    final checksum = median(reps(() {
      var a = 1;
      var b = 0;
      for (final byte in utf8.encode(bodyStr)) {
        a = (a + byte) % 65521;
        b = (b + a) % 65521;
      }
      sink += a + b;
    }));
    final rawBytes = utf8.encode(jsonEncode(tasks)).length;
    print(
      'ENCODE,$n,raw_bytes,$rawBytes,snapshot,$snap,body,$body,payload,$payload,'
      'checksum,$checksum,chain,${snap + body + payload + checksum},'
      'single_warm_snapshot,$snapshot,sink,$sink',
    );
  }
}
