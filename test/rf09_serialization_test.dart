// RF09 (C1/C2) serialization lock.
//
// These tests pin the behaviour the C1/C2 optimizations must not change:
//   S1  the exact bytes a committed slot holds, and what the mirror keys hold;
//   S2  checksum verification and every damaged-batch rejection in `load()`;
//   S3  failed writes, retry and the exit flush barrier;
//   S4  which commands dirty the store, and the order imports and edits commit.
//
// The goldens were captured from the pre-optimization implementation:
//   flutter test --no-pub test/rf09_serialization_test.dart -t rf09-golden \
//     --dart-define=RF09_CAPTURE=1
// They are literals on purpose. A change that moved the writer and the reader
// together would still pass a self-consistent round trip, but not these, and a
// database an older build already wrote must stay readable.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

// `--dart-define=RF09_CAPTURE=1` arrives as a string, so both spellings work.
const bool _capture =
    bool.fromEnvironment('RF09_CAPTURE') ||
    String.fromEnvironment('RF09_CAPTURE') == '1';

// --- locked format goldens ---------------------------------------------------

const String goldenSlotRev1 = '{"revision":1,"values":{"matrixflow-tasks":"[{\\"id\\":\\"t1\\",\\"title\\":\\"整理季度复盘 \\\\\\"Q1\\\\\\" 🎯\\",\\"notes\\":\\"第一行\\\\n第二行\\\\t制表\\\\u0001\\\\u0007bell\\",\\"path\\":\\"C:\\\\\\\\Dev\\\\\\\\martix\\\\\\\\src\\",\\"markup\\":\\"\\\\\\"<b>&amp;</b>\\\\\\" 100% \$free {not interpolated}\\",\\"empty\\":\\"\\",\\"subtasks\\":[{\\"id\\":\\"s1\\",\\"title\\":\\"子步骤 \\\\\\\\ 1 \\\\\\"x\\\\\\"\\"}]}]","matrixflow-boards":"[{\\"id\\":\\"board-1\\",\\"name\\":\\"测量 \\\\\\"板\\\\\\"\\",\\"createdAt\\":0}]","matrixflow-config":"{\\"provider\\":\\"custom\\",\\"baseUrl\\":\\"https://example.invalid/v1\\",\\"model\\":\\"synthetic \\\\\\"模型\\\\\\" 🎯\\"}","matrixflow-settings":"{\\"language\\":\\"zh\\",\\"fontSize\\":\\"large\\",\\"reduceMotion\\":true}","matrixflow-active-board":"board \\"quoted\\" \\\\ back 🎯","matrixflow-has-seen-onboarding":"true"},"check":274342734}';
const int goldenCheckRev1 = 274342734;
const String goldenSlotRev2 = '{"revision":2,"values":{"matrixflow-tasks":"[{\\"id\\":\\"t1\\",\\"title\\":\\"整理季度复盘 \\\\\\"Q1\\\\\\" 🎯\\",\\"notes\\":\\"第一行\\\\n第二行\\\\t制表\\\\u0001\\\\u0007bell\\",\\"path\\":\\"C:\\\\\\\\Dev\\\\\\\\martix\\\\\\\\src\\",\\"markup\\":\\"\\\\\\"<b>&amp;</b>\\\\\\" 100% \$free {not interpolated}\\",\\"empty\\":\\"\\",\\"subtasks\\":[{\\"id\\":\\"s1\\",\\"title\\":\\"子步骤 \\\\\\\\ 1 \\\\\\"x\\\\\\"\\"}]}]","matrixflow-boards":"[{\\"id\\":\\"board-1\\",\\"name\\":\\"测量 \\\\\\"板\\\\\\"\\",\\"createdAt\\":0}]","matrixflow-config":"{\\"provider\\":\\"custom\\",\\"baseUrl\\":\\"https://example.invalid/v1\\",\\"model\\":\\"synthetic \\\\\\"模型\\\\\\" 🎯\\"}","matrixflow-settings":"{\\"language\\":\\"zh\\",\\"fontSize\\":\\"large\\",\\"reduceMotion\\":true}","matrixflow-active-board":"board \\"quoted\\" \\\\ back 🎯","matrixflow-has-seen-onboarding":"true"},"check":325067599}';
const int goldenCheckRev2 = 325067599;
const String goldenScrubSlotA = '{"revision":1,"values":{"matrixflow-tasks":"[{\\"id\\":\\"t1\\",\\"title\\":\\"整理季度复盘 \\\\\\"Q1\\\\\\" 🎯\\",\\"notes\\":\\"第一行\\\\n第二行\\\\t制表\\\\u0001\\\\u0007bell\\",\\"path\\":\\"C:\\\\\\\\Dev\\\\\\\\martix\\\\\\\\src\\",\\"markup\\":\\"\\\\\\"<b>&amp;</b>\\\\\\" 100% \$free {not interpolated}\\",\\"empty\\":\\"\\",\\"subtasks\\":[{\\"id\\":\\"s1\\",\\"title\\":\\"子步骤 \\\\\\\\ 1 \\\\\\"x\\\\\\"\\"}]}]","matrixflow-boards":"[{\\"id\\":\\"board-1\\",\\"name\\":\\"测量 \\\\\\"板\\\\\\"\\",\\"createdAt\\":0}]","matrixflow-config":"{\\"provider\\":\\"custom\\",\\"baseUrl\\":\\"https://example.invalid/v1\\",\\"model\\":\\"synthetic \\\\\\"模型\\\\\\" 🎯\\",\\"headers\\":{\\"X-Note\\":\\"中文 \\\\\\\\ back\\\\nsecond line\\"}}","matrixflow-settings":"{\\"language\\":\\"zh\\",\\"fontSize\\":\\"large\\",\\"reduceMotion\\":true}","matrixflow-active-board":"board \\"quoted\\" \\\\ back 🎯","matrixflow-has-seen-onboarding":"true"},"check":2729130440}';
const String goldenScrubSlotB = '{"revision":2,"values":{"matrixflow-tasks":"[{\\"id\\":\\"t1\\",\\"title\\":\\"整理季度复盘 \\\\\\"Q1\\\\\\" 🎯\\",\\"notes\\":\\"第一行\\\\n第二行\\\\t制表\\\\u0001\\\\u0007bell\\",\\"path\\":\\"C:\\\\\\\\Dev\\\\\\\\martix\\\\\\\\src\\",\\"markup\\":\\"\\\\\\"<b>&amp;</b>\\\\\\" 100% \$free {not interpolated}\\",\\"empty\\":\\"\\",\\"subtasks\\":[{\\"id\\":\\"s1\\",\\"title\\":\\"子步骤 \\\\\\\\ 1 \\\\\\"x\\\\\\"\\"}]}]","matrixflow-boards":"[{\\"id\\":\\"board-1\\",\\"name\\":\\"测量 \\\\\\"板\\\\\\"\\",\\"createdAt\\":0}]","matrixflow-config":"{\\"provider\\":\\"custom\\",\\"baseUrl\\":\\"https://example.invalid/v1\\",\\"model\\":\\"synthetic \\\\\\"模型\\\\\\" 🎯\\",\\"headers\\":{\\"X-Note\\":\\"中文 \\\\\\\\ back\\\\nsecond line\\"}}","matrixflow-settings":"{\\"language\\":\\"zh\\",\\"fontSize\\":\\"large\\",\\"reduceMotion\\":true}","matrixflow-active-board":"board \\"quoted\\" \\\\ back 🎯","matrixflow-has-seen-onboarding":"true"},"check":2783787465}';
const String goldenScrubMirror = '{"provider":"custom","baseUrl":"https://example.invalid/v1","model":"synthetic \\"模型\\" 🎯","headers":{"X-Note":"中文 \\\\ back\\nsecond line"}}';
const int goldenBigPayloadBytes = 279801;
const int goldenBigPayloadFingerprint = 1267241698;
const int goldenBigCheck = 3791606609;
const int goldenBigMirrorBytes = 236865;

// --- fixtures ----------------------------------------------------------------

const String slotA = 'matrixflow-save-a';
const String slotB = 'matrixflow-save-b';
const String kTasks = 'matrixflow-tasks';
const String kBoards = 'matrixflow-boards';
const String kConfig = 'matrixflow-config';
const String kSettings = 'matrixflow-settings';
const String kActiveBoard = 'matrixflow-active-board';
const String kOnboarding = 'matrixflow-has-seen-onboarding';

/// Escape-heavy values chosen so any change in JSON framing or in where a value
/// is re-encoded shows up as a byte difference: quotes, backslashes, control
/// characters, CJK, a non-BMP code point, `$`, braces, and a non-JSON value.
Map<String, String> fixtureValues() => <String, String>{
  kTasks: jsonEncode(<Object?>[
    <String, Object?>{
      'id': 't1',
      'title': '整理季度复盘 "Q1" 🎯',
      'notes': '第一行\n第二行\t制表\u0001\u0007bell',
      'path': r'C:\Dev\martix\src',
      'markup': r'"<b>&amp;</b>" 100% $free {not interpolated}',
      'empty': '',
      'subtasks': <Object?>[
        <String, Object?>{'id': 's1', 'title': r'子步骤 \ 1 "x"'},
      ],
    },
  ]),
  kBoards: jsonEncode(<Object?>[
    Board(id: 'board-1', name: '测量 "板"', createdAt: 0).toJson(),
  ]),
  kConfig: jsonEncode(<String, Object?>{
    'provider': 'custom',
    'baseUrl': 'https://example.invalid/v1',
    'model': 'synthetic "模型" 🎯',
  }),
  kSettings: jsonEncode(<String, Object?>{
    'language': 'zh',
    'fontSize': 'large',
    'reduceMotion': true,
  }),
  kActiveBoard: r'board "quoted" \ back 🎯',
  kOnboarding: 'true',
};

/// The config fixture plus a plaintext synthetic key, which is what
/// `scrubCredentials` removes. Never a real credential.
Map<String, String> fixtureValuesWithKey() => <String, String>{
  ...fixtureValues(),
  kConfig: jsonEncode(<String, Object?>{
    'provider': 'custom',
    'baseUrl': 'https://example.invalid/v1',
    'model': 'synthetic "模型" 🎯',
    'customApiKey': 'sk-synthetic-never-real',
    'headers': <String, Object?>{'X-Note': '中文 \\ back\nsecond line'},
  }),
};

/// A 1,000-task library: byte identity has to hold at the scale C1/C2 target,
/// not only on the small fixture.
List<Task> largeLibrary(int count) => List<Task>.generate(count, (i) {
  return Task(
    id: 't$i',
    boardId: 'board-1',
    title: '任务 "$i" 🎯 \\ ${i % 7}',
    quadrant: 1 + (i % 4),
    createdAt: 1740000000000 + i,
    deadline: i % 3 == 0 ? 1750000000000 + i : null,
    completed: i % 5 == 0,
    subtasks: i % 4 == 0
        ? <SubTask>[
            SubTask(id: 't$i-s0', title: r'子 "步骤" \n ' '$i'),
            SubTask(id: 't$i-s1', title: '制表\t换行\n$i', completed: true),
          ]
        : <SubTask>[],
    notesMarkdown: i % 6 == 0 ? '长笔记\n第二行\t"引号" 🎯' : null,
    reminderAt: i % 9 == 0 ? 1760000000000 + i : null,
    reminderTimezone: i % 9 == 0 ? 'Asia/Shanghai' : null,
  );
});

Map<String, String> largeValues(int count) => <String, String>{
  kTasks: jsonEncode(largeLibrary(count).map((t) => t.toJson()).toList()),
  kBoards: jsonEncode(<Object?>[
    Board(id: 'board-1', name: '大板', createdAt: 0).toJson(),
  ]),
  kConfig: jsonEncode(AIConfig().toJson(includeCredential: false)),
  kSettings: jsonEncode(AppSettings(language: Language.zh).toJson()),
  kActiveBoard: 'board-1',
  kOnboarding: 'true',
};

/// Independent fingerprint of the exact bytes written to a slot. Deliberately
/// not the production checksum: this one runs over the whole payload, so it
/// sees framing, escaping and check-value changes alike.
int fingerprint(String payload) {
  var hash = 5381;
  for (final byte in utf8.encode(payload)) {
    hash = ((hash << 5) + hash + byte) & 0x7FFFFFFF;
  }
  return hash;
}

/// The writer's format before C1/C2: encode `{"revision":R,"values":V}` once,
/// Adler-32 those UTF-8 bytes, and append the result. Written out here, from
/// test-owned code, so production is measured against a second source.
String referencePayload(int revision, Map<String, String> values) {
  final body = jsonEncode(<String, Object?>{
    'revision': revision,
    'values': values,
  });
  var a = 1;
  var b = 0;
  for (final byte in utf8.encode(body)) {
    a = (a + byte) % 65521;
    b = (b + a) % 65521;
  }
  final check = (b << 16) | a;
  return '${body.substring(0, body.length - 1)},"check":$check}';
}

/// A single-quoted Dart literal carrying only the escapes the value needs, so a
/// printed golden can be pasted straight back and the file stays lint-clean
/// (`jsonEncode` would escape every `"` in a JSON payload for no reason).
String dartLiteral(String value) {
  final out = StringBuffer();
  for (final rune in value.runes) {
    final text = String.fromCharCode(rune);
    if (text == r'\') {
      out.write(r'\\');
    } else if (text == "'") {
      out.write(r"\'");
    } else if (text == r'$') {
      out.write(r'\$');
    } else if (text == '\n') {
      out.write(r'\n');
    } else if (text == '\r') {
      out.write(r'\r');
    } else if (text == '\t') {
      out.write(r'\t');
    } else if (rune < 0x20 || rune == 0x7f) {
      out.write('\\u${rune.toRadixString(16).padLeft(4, '0')}');
    } else {
      out.write(text);
    }
  }
  return out.toString();
}

void reportGolden(String name, Object? value) {
  // ignore: avoid_print
  print('RF09GOLDEN $name = '
      '${value is String ? "'${dartLiteral(value)}'" : value}');
}

/// Records every key/value a commit asks for, and can fail, throw or block.
class RecordingWriter {
  RecordingWriter({this.prefs});

  final Map<String, String> written = <String, String>{};
  final List<String> order = <String>[];

  /// Every batch payload in the order it was asked for, slot writes only.
  final List<String> batches = <String>[];
  final SharedPreferences? prefs;
  bool Function(String key, String value)? reject;
  Future<void>? Function(String key)? block;

  /// Throw instead of writing this key.
  String? throwOnKey;

  /// Land this key in [prefs], then throw: a writer that dies after the write.
  String? throwAfterWriteKey;

  bool get sawBatch => order.any((key) => key == slotA || key == slotB);

  Future<bool> call(String key, String value) async {
    order.add(key);
    written[key] = value;
    if (key == slotA || key == slotB) batches.add(value);
    if (throwOnKey == key) throw StateError('synthetic failure');
    if (reject?.call(key, value) ?? false) return false;
    await block?.call(key);
    final landed =
        await (prefs?.setString(key, value) ?? Future<bool>.value(true));
    if (throwAfterWriteKey == key) {
      throw StateError('synthetic failure after a landed write');
    }
    return landed;
  }

  void reset() {
    written.clear();
    order.clear();
    batches.clear();
  }
}

int byteLen(String value) => utf8.encode(value).length;

Matcher failsWith(String message) => throwsA(
  isA<FormatException>().having(
    (error) => error.message,
    'message',
    message,
  ),
);

/// Seeds the legacy keys only, so a store starts with no committed batch.
Future<void> seedLegacyPrefs(
  SharedPreferences prefs, {
  List<Task> tasks = const <Task>[],
}) async {
  await prefs.clear();
  await prefs.setString(kBoards, jsonEncode(<Object?>[
    Board(id: 'board-1', name: '板', createdAt: 0).toJson(),
  ]));
  await prefs.setString(kTasks, jsonEncode(<Object?>[
    for (final task in tasks) task.toJson(),
  ]));
  await prefs.setString(kActiveBoard, 'board-1');
  await prefs.setBool(kOnboarding, true);
}

Future<Store> openStore(
  SharedPreferences prefs,
  RecordingWriter writer, {
  List<Task> tasks = const <Task>[],
}) async {
  await seedLegacyPrefs(prefs, tasks: tasks);
  final store = Store(
    reminders: InMemoryReminderService(),
    saveWriter: writer.call,
  );
  await store.init();
  return store;
}

Task seedTask(String id, {String title = '任务'}) => Task(
  id: id,
  boardId: 'board-1',
  title: title,
  quadrant: 1,
  createdAt: 1,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('S1 committed slot bytes', () {
    test('one commit writes the locked payload, check and mirror bytes', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final writer = RecordingWriter(prefs: prefs);
      final protocol = SaveProtocol(prefs, writer: writer.call);
      final values = fixtureValues();
      final result = await protocol.commit(values);

      expect(result.success, isTrue);
      expect(result.revision, 1);
      expect(writer.order, <String>[
        slotA,
        SaveProtocol.pointerKey,
        kTasks,
        kBoards,
        kConfig,
        kSettings,
        kActiveBoard,
      ]);
      final payload = writer.written[slotA]!;
      final decoded = jsonDecode(payload) as Map<String, Object?>;
      expect(decoded.keys.toList(), <String>['revision', 'values', 'check']);
      if (_capture) {
        reportGolden('goldenSlotRev1', payload);
        reportGolden('goldenCheckRev1', decoded['check']);
      } else {
        expect(payload, goldenSlotRev1);
        expect(decoded['check'], goldenCheckRev1);
      }
      // Production output equals the pre-C1/C2 reference construction exactly,
      // at the byte level, for every value including a non-JSON one.
      expect(payload, referencePayload(1, values));
      // Each value keeps the same escaping whether the encoder nested it or not.
      for (final entry in values.entries) {
        expect(payload, contains(jsonEncode(entry.value)), reason: entry.key);
      }
      expect(writer.written[SaveProtocol.pointerKey], slotA);
      // The compatibility mirrors hold the values verbatim, unescaped.
      for (final entry in values.entries) {
        if (entry.key == kOnboarding) continue;
        expect(writer.written[entry.key], entry.value, reason: entry.key);
      }
      // Onboarding is a bool on disk and bypasses the injected writer.
      expect(writer.written.containsKey(kOnboarding), isFalse);
      expect(prefs.getBool(kOnboarding), isTrue);
    });

    test('the second commit alternates slots and locks revision-2 bytes',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final writer = RecordingWriter(prefs: prefs);
      final protocol = SaveProtocol(prefs, writer: writer.call);
      final values = fixtureValues();
      await protocol.commit(values);
      final firstPayload = writer.written[slotA]!;
      writer.reset();
      final second = await protocol.commit(values);

      expect(second.revision, 2);
      expect(writer.order.first, slotB);
      final payload = writer.written[slotB]!;
      if (_capture) {
        reportGolden('goldenSlotRev2', payload);
        reportGolden(
          'goldenCheckRev2',
          (jsonDecode(payload) as Map<String, Object?>)['check'],
        );
      } else {
        expect(payload, goldenSlotRev2);
        expect(
          (jsonDecode(payload) as Map<String, Object?>)['check'],
          goldenCheckRev2,
        );
      }
      expect(payload, referencePayload(2, values));
      // Same framing and value bytes; only the revision digits and their check
      // differ between the two locked payloads.
      String bodyOf(String text) =>
          text.substring(0, text.indexOf(',"check":'));
      expect(
        bodyOf(payload),
        bodyOf(firstPayload).replaceAll('{"revision":1', '{"revision":2'),
      );
    });

    test('a 1,000-task library keeps its locked payload bytes and check',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final writer = RecordingWriter(prefs: prefs);
      final protocol = SaveProtocol(prefs, writer: writer.call);
      final values = largeValues(1000);
      await protocol.commit(values);
      final payload = writer.written[slotA]!;
      final decoded = jsonDecode(payload) as Map<String, Object?>;
      if (_capture) {
        reportGolden('goldenBigPayloadBytes', byteLen(payload));
        reportGolden('goldenBigPayloadFingerprint', fingerprint(payload));
        reportGolden('goldenBigCheck', decoded['check']);
        reportGolden('goldenBigMirrorBytes', byteLen(values[kTasks]!));
      } else {
        expect(byteLen(payload), goldenBigPayloadBytes);
        expect(fingerprint(payload), goldenBigPayloadFingerprint);
        expect(decoded['check'], goldenBigCheck);
        expect(byteLen(writer.written[kTasks]!), goldenBigMirrorBytes);
      }
      expect(payload, referencePayload(1, values));
      final restored = (decoded['values'] as Map<String, Object?>).map(
        (key, value) => MapEntry(key, value as String),
      );
      expect(restored.keys.toList(), values.keys.toList());
      for (final key in values.keys) {
        expect(restored[key], values[key], reason: key);
      }
    });

    test('scrubCredentials rewrites both slots and the mirror with locked bytes',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final writer = RecordingWriter(prefs: prefs);
      final protocol = SaveProtocol(prefs, writer: writer.call);
      final values = fixtureValuesWithKey();
      await protocol.commit(values);
      await protocol.commit(values);
      expect(prefs.getString(slotA), contains('sk-synthetic-never-real'));
      expect(prefs.getString(slotB), contains('sk-synthetic-never-real'));

      expect(await protocol.scrubCredentials(), isTrue);
      final scrubbedA = prefs.getString(slotA)!;
      final scrubbedB = prefs.getString(slotB)!;
      final scrubbedMirror = prefs.getString(kConfig)!;
      if (_capture) {
        reportGolden('goldenScrubSlotA', scrubbedA);
        reportGolden('goldenScrubSlotB', scrubbedB);
        reportGolden('goldenScrubMirror', scrubbedMirror);
      } else {
        expect(scrubbedA, goldenScrubSlotA);
        expect(scrubbedB, goldenScrubSlotB);
        expect(scrubbedMirror, goldenScrubMirror);
      }
      for (final text in <String>[scrubbedA, scrubbedB, scrubbedMirror]) {
        expect(text, isNot(contains('sk-synthetic-never-real')));
      }
      // A rewritten check must still satisfy the reader.
      final scrubbedValues = Map<String, String>.of(values)
        ..[kConfig] = jsonEncode(
          (<String, Object?>{...jsonDecode(values[kConfig]!) as Map<String, Object?>}
                ..remove('customApiKey')),
        );
      expect(scrubbedA, referencePayload(1, scrubbedValues));
      expect(scrubbedB, referencePayload(2, scrubbedValues));
      final batch = SaveProtocol(prefs).load();
      expect(batch, isNotNull);
      expect(batch!.revision, 2);
      expect(batch.values[kConfig], scrubbedValues[kConfig]);
    });
  });

  group('S2 checksum and damaged batch rejection', () {
    late SharedPreferences prefs;
    late String validPayload;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      final writer = RecordingWriter(prefs: prefs);
      await SaveProtocol(prefs, writer: writer.call).commit(fixtureValues());
      validPayload = writer.written[slotA]!;
      expect(validPayload, isNotEmpty);
    });

    Future<void> seed({
      String? payload,
      String pointer = slotA,
      bool slot = true,
    }) async {
      await prefs.remove(slotA);
      await prefs.remove(slotB);
      await prefs.remove(SaveProtocol.pointerKey);
      if (slot) await prefs.setString(slotA, payload ?? validPayload);
      if (pointer != '') {
        await prefs.setString(SaveProtocol.pointerKey, pointer);
      }
    }

    Map<String, Object?> parts(String payload) =>
        jsonDecode(payload) as Map<String, Object?>;

    Future<void> seedValues(Map<String, Object?> replacement) async {
      final batch = parts(validPayload);
      await seed(
        payload: jsonEncode(<String, Object?>{...batch, ...replacement}),
      );
    }

    test('a healthy batch loads with every value intact', () async {
      final batch = SaveProtocol(prefs).load();
      expect(batch, isNotNull);
      expect(batch!.revision, 1);
      final expected = fixtureValues();
      for (final key in expected.keys) {
        expect(batch.values[key], expected[key], reason: key);
      }
    });

    test('one flipped character inside a value fails the checksum', () async {
      final broken = validPayload.replaceFirst('整理季度复盘', '整理季度盘复');
      expect(broken, isNot(validPayload));
      await seed(payload: broken);
      expect(
        () => SaveProtocol(prefs).load(),
        failsWith('Committed batch checksum failed'),
      );
    });

    test('a value edited into valid JSON still fails the checksum', () async {
      final batch = parts(validPayload);
      final values = Map<String, Object?>.from(batch['values'] as Map)
        ..[kSettings] = '{"language":"en","fontSize":"standard"}';
      await seedValues(<String, Object?>{'values': values});
      expect(
        () => SaveProtocol(prefs).load(),
        failsWith('Committed batch checksum failed'),
      );
    });

    test('an off-by-one check fails', () async {
      await seedValues(
        <String, Object?>{'check': (parts(validPayload)['check'] as int) + 1},
      );
      expect(
        () => SaveProtocol(prefs).load(),
        failsWith('Committed batch checksum failed'),
      );
    });

    test('a truncated payload fails', () async {
      await seed(payload: validPayload.substring(0, validPayload.length - 9));
      expect(() => SaveProtocol(prefs).load(), throwsFormatException);
    });

    test('a dropped value fails as incomplete, not as a silent default',
        () async {
      final required = <String>[
        kTasks,
        kBoards,
        kConfig,
        kSettings,
        kActiveBoard,
        kOnboarding,
      ];
      for (final drop in required) {
        final batch = parts(validPayload);
        final values = Map<String, Object?>.from(batch['values'] as Map)
          ..remove(drop);
        // Re-checksummed, so only the missing key can be the reason it is refused.
        await seed(
          payload: referencePayload(batch['revision'] as int, values.cast()),
        );
        expect(
          () => SaveProtocol(prefs).load(),
          failsWith('Incomplete committed batch'),
          reason: 'dropped $drop',
        );
      }
      // The completeness check runs before the checksum, so a key that simply
      // vanished is refused even when the stored check still matches the body.
      final batch = parts(validPayload);
      final values = Map<String, Object?>.from(batch['values'] as Map)
        ..remove(kSettings);
      await seedValues(<String, Object?>{'values': values});
      expect(
        () => SaveProtocol(prefs).load(),
        failsWith('Incomplete committed batch'),
      );
    });

    test('a non-object payload is rejected', () async {
      await seed(payload: '[]');
      expect(() => SaveProtocol(prefs).load(),
          failsWith('Invalid committed batch'));
      await seed(payload: '"just a string"');
      expect(() => SaveProtocol(prefs).load(),
          failsWith('Invalid committed batch'));
    });

    test('wrong field types are rejected', () async {
      for (final replacement in <Map<String, Object?>>[
        <String, Object?>{'revision': '1'},
        <String, Object?>{'check': '123'},
        <String, Object?>{'values': 'nope'},
      ]) {
        await seedValues(replacement);
        expect(
          () => SaveProtocol(prefs).load(),
          failsWith('Invalid committed batch'),
          reason: '$replacement',
        );
      }
      // An empty values map has the right shape but not the right contents.
      await seedValues(<String, Object?>{'values': <String, Object?>{}});
      expect(
        () => SaveProtocol(prefs).load(),
        failsWith('Incomplete committed batch'),
      );
    });

    test('a batch value that is not a string is refused', () async {
      final batch = parts(validPayload);
      final values = Map<String, Object?>.from(batch['values'] as Map)
        ..[kSettings] = 7;
      await seedValues(<String, Object?>{'values': values});
      // The reader casts the values map before anything else, so this surfaces
      // as a type error rather than a FormatException; `Store.init` catches both
      // the same way, which the next test pins.
      expect(() => SaveProtocol(prefs).load(), throwsA(isA<TypeError>()));
    });

    test('a batch the reader cannot use lands on the startup recovery screen',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final recoveryPrefs = await SharedPreferences.getInstance();
      await recoveryPrefs.clear();
      final batch = parts(validPayload);
      final values = Map<String, Object?>.from(batch['values'] as Map)
        ..[kSettings] = 7;
      await recoveryPrefs.setString(
        slotA,
        jsonEncode(<String, Object?>{...batch, 'values': values}),
      );
      await recoveryPrefs.setString(SaveProtocol.pointerKey, slotA);
      final store = Store(reminders: InMemoryReminderService());
      await store.init();
      expect(store.hasStartupRecovery, isTrue);
      expect(
        store.startupDataStates[SaveProtocol.pointerKey],
        StartupDataState.corrupt,
      );
      // Nothing was rewritten: the damaged batch is still there untouched.
      expect(recoveryPrefs.getString(slotA), contains('"matrixflow-settings":7'));
      store.dispose();
    });

    test('an unknown pointer is rejected', () async {
      await seed(slot: false, pointer: 'matrixflow-save-c');
      expect(() => SaveProtocol(prefs).load(),
          failsWith('Invalid save pointer'));
    });

    test('a pointer without its committed batch is rejected', () async {
      await seed(slot: false, pointer: slotA);
      expect(
        () => SaveProtocol(prefs).load(),
        failsWith('Missing committed batch'),
      );
    });

    test('slots without a pointer fall back to the legacy keys', () async {
      await prefs.remove(SaveProtocol.pointerKey);
      await prefs.setString(slotB, validPayload);
      expect(SaveProtocol(prefs).load(), isNull);
      expect(prefs.getString(slotB), validPayload);
    });

    test('a batch assembled by the reference encoder is accepted', () async {
      // What an older build wrote, rebuilt here from test-owned code.
      final values = fixtureValues();
      await seed(slot: false);
      await prefs.setString(slotA, referencePayload(7, values));
      await prefs.setString(SaveProtocol.pointerKey, slotA);
      final batch = SaveProtocol(prefs).load();
      expect(batch, isNotNull);
      expect(batch!.revision, 7);
      expect(batch.values[kActiveBoard], values[kActiveBoard]);
      expect(batch.values[kTasks], values[kTasks]);
    });
  });

  group('S3 failure, retry and flush barrier', () {
    test('a rejected slot write advances nothing and retries at the free slot',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final writer = RecordingWriter(prefs: prefs);
      final protocol = SaveProtocol(prefs, writer: writer.call);
      await protocol.commit(fixtureValues());
      writer.reset();
      final next = largeValues(1);
      writer.reject = (key, _) => key == slotB;

      final failed = await protocol.commit(next);
      expect(failed.success, isFalse);
      expect(failed.committed, isFalse);
      expect(protocol.revision, 1);
      expect(writer.order, <String>[slotB]);
      expect(prefs.getString(SaveProtocol.pointerKey), slotA);
      expect(prefs.getString(slotB), isNull);
      expect(SaveProtocol(prefs).load()!.values[kTasks],
          fixtureValues()[kTasks]);

      writer.reject = null;
      final retried = await protocol.commit(next);
      expect(retried.success, isTrue);
      expect(retried.revision, 2);
      expect(prefs.getString(SaveProtocol.pointerKey), slotB);
      final batch = SaveProtocol(prefs).load()!;
      expect(batch.revision, 2);
      expect(batch.values[kTasks], next[kTasks]);
    });

    test('a rejected pointer write leaves the previous batch authoritative',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final writer = RecordingWriter(prefs: prefs);
      final protocol = SaveProtocol(prefs, writer: writer.call);
      final first = fixtureValues();
      await protocol.commit(first);
      final second = largeValues(1);
      writer.reset();
      writer.reject = (key, _) => key == SaveProtocol.pointerKey;

      final failed = await protocol.commit(second);
      expect(failed.success, isFalse);
      expect(protocol.revision, 1);
      // The slot was written but never pointed at, so startup still reads the
      // first batch and no mirror moved.
      final batch = SaveProtocol(prefs).load()!;
      expect(batch.revision, 1);
      expect(batch.values[kTasks], first[kTasks]);
      expect(writer.order.contains(kTasks), isFalse);
      // The mirror still shows the first batch: the rejected commit changed
      // nothing that a restart can observe.
      expect(prefs.getString(kTasks), first[kTasks]);

      writer.reject = null;
      expect((await protocol.commit(second)).success, isTrue);
      final afterRetry = SaveProtocol(prefs).load()!;
      expect(afterRetry.revision, 2);
      expect(afterRetry.values[kTasks], second[kTasks]);
    });

    test('a slot write that throws advances nothing', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final writer = RecordingWriter(prefs: prefs)..throwOnKey = slotA;
      final protocol = SaveProtocol(prefs, writer: writer.call);
      final result = await protocol.commit(fixtureValues());
      expect(result.success, isFalse);
      expect(protocol.revision, 0);
      expect(prefs.getString(SaveProtocol.pointerKey), isNull);
      expect(SaveProtocol(prefs).load(), isNull);
    });

    test('a write that throws after the pointer landed still commits', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final writer = RecordingWriter(prefs: prefs)
        ..throwAfterWriteKey = SaveProtocol.pointerKey;
      final protocol = SaveProtocol(prefs, writer: writer.call);
      final result = await protocol.commit(fixtureValues());
      expect(result.success, isTrue);
      expect(result.committed, isTrue);
      expect(protocol.revision, 1);
      expect(prefs.getString(SaveProtocol.pointerKey), slotA);
      expect(SaveProtocol(prefs).load(), isNotNull);
    });

    test('a mirror that refuses one key does not fail the commit', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final writer = RecordingWriter(prefs: prefs)
        ..reject = (key, _) => key == kActiveBoard;
      final protocol = SaveProtocol(prefs, writer: writer.call);
      final values = fixtureValues();
      final result = await protocol.commit(values);
      expect(result.success, isTrue);
      expect(result.committed, isTrue);
      expect(prefs.getString(kActiveBoard), isNull);
      expect(SaveProtocol(prefs).load()!.values[kActiveBoard],
          values[kActiveBoard]);
    });

    test('flush waits for a blocked commit and the edit survives a reopen',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      final gate = Completer<void>();
      var blocked = false;
      Future<bool> writer(String key, String value) async {
        if (blocked && key == slotB) await gate.future;
        return prefs.setString(key, value);
      }

      final store = Store(
        reminders: InMemoryReminderService(),
        saveWriter: writer,
      );
      await store.init();
      store.createBoard('Before');
      expect((await store.flush()).success, isTrue);
      store.dispose();

      final second = Store(
        reminders: InMemoryReminderService(),
        saveWriter: writer,
      );
      await second.init();
      blocked = true;
      second.createBoard('Blocked');
      var settled = false;
      final barrier = second.flush().then((result) {
        settled = true;
        return result;
      });
      await pumpEventQueue(times: 20);
      expect(settled, isFalse, reason: 'flush must wait for the blocked write');
      blocked = false;
      gate.complete();
      expect((await barrier).success, isTrue);
      expect(settled, isTrue);
      second.dispose();

      final reopened = Store(reminders: InMemoryReminderService());
      await reopened.init();
      expect(reopened.boards.map((b) => b.name), contains('Blocked'));
      reopened.dispose();
    });

    test('retrySave commits again even when nothing else is dirty', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final writer = RecordingWriter(prefs: prefs);
      final store = Store(
        reminders: InMemoryReminderService(),
        saveWriter: writer.call,
      );
      await store.init();
      final first = await store.flush();
      expect(first.success, isTrue);
      final openBatches = writer.batches.length;

      store.createBoard('Dirty');
      final second = await store.flush();
      expect(second.revision, greaterThan(first.revision));

      // A clean library still has to reach the disk once more: retrySave bumps
      // the dirty revision on purpose, so the gates and the bump must stay.
      final third = await store.retrySave();
      expect(third.success, isTrue);
      expect(third.revision, greaterThan(second.revision));
      // Exactly two batches left the store: the board change and the retry.
      expect(writer.batches.length, openBatches + 2);
      store.dispose();
      final reopened = Store(reminders: InMemoryReminderService());
      await reopened.init();
      expect(reopened.boards.map((b) => b.name), contains('Dirty'));
      reopened.dispose();
    });

    test('retrySave after a rejected pointer recovers the accepted edit',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      await seedLegacyPrefs(prefs);
      var reject = false;
      final store = Store(
        reminders: InMemoryReminderService(),
        saveWriter: (key, value) async {
          if (reject && key == SaveProtocol.pointerKey) return false;
          return prefs.setString(key, value);
        },
      );
      await store.init();
      await store.flush();
      reject = true;
      store.addTasks([seedTask('retry-task', title: '未落盘的编辑')]);
      expect((await store.flush()).success, isFalse);
      expect(store.persistenceError, isNotNull);
      reject = false;
      expect((await store.retrySave()).success, isTrue);
      expect(store.persistenceError, isNull);
      store.dispose();
      final reopened = Store(reminders: InMemoryReminderService());
      await reopened.init();
      expect(reopened.tasks.map((t) => t.title), contains('未落盘的编辑'));
      reopened.dispose();
    });
  });

  group('S4 dirtying and commit order', () {
    test('a single task edit produces exactly one whole-library batch',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final writer = RecordingWriter(prefs: prefs);
      final store = await openStore(
        prefs,
        writer,
        tasks: List<Task>.generate(50, (i) => seedTask('t$i')),
      );
      store.updateSettings((s) => s);
      await store.flush();
      writer.reset();

      final edited = Task.fromJson(store.tasks.first.toJson())
        ..title = '改名 🎯';
      store.updateTask(edited);
      expect((await store.flush()).success, isTrue);

      // The seed commit used slot A, so this one alternates to slot B.
      expect(writer.order, <String>[
        slotB,
        SaveProtocol.pointerKey,
        kTasks,
        kBoards,
        kConfig,
        kSettings,
        kActiveBoard,
      ]);
      final decoded =
          jsonDecode(writer.written[slotB]!) as Map<String, Object?>;
      expect(decoded['revision'], 2);
      final values = (decoded['values'] as Map<String, Object?>).map(
        (key, value) => MapEntry(key, value as String),
      );
      expect(values.keys.toList(), <String>[
        kTasks,
        kBoards,
        kConfig,
        kSettings,
        kActiveBoard,
        kOnboarding,
      ]);
      // Dropping the discarded per-command encode must not change what lands:
      // the batch still carries the full library, including the edit.
      final library = jsonDecode(values[kTasks]!) as List<Object?>;
      expect(library, hasLength(50));
      expect(
        (library.first as Map<String, Object?>)['title'],
        '改名 🎯',
      );
      store.dispose();
    });

    test('a settings-only change still rewrites the task mirror', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final writer = RecordingWriter(prefs: prefs);
      final store = await openStore(
        prefs,
        writer,
        tasks: List<Task>.generate(20, (i) => seedTask('t$i')),
      );
      store.updateSettings((s) => s);
      await store.flush();
      final libraryBytes = byteLen(prefs.getString(kTasks)!);
      final libraryText = prefs.getString(kTasks)!;
      writer.reset();

      store.updateSettings((s) => _withFontSize(s, FontSizePref.large));
      expect((await store.flush()).success, isTrue);
      expect(byteLen(writer.written[kTasks]!), libraryBytes);
      expect(writer.written[kTasks], libraryText);
      store.dispose();
    });

    test('a board change is one batch that carries the board and active id',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final writer = RecordingWriter(prefs: prefs);
      final store = await openStore(prefs, writer);
      store.updateSettings((s) => s);
      await store.flush();
      writer.reset();

      store.createBoard('第二个板');
      expect((await store.flush()).success, isTrue);
      expect(writer.sawBatch, isTrue);
      expect(
        writer.order.where((key) => key == slotA || key == slotB).length,
        1,
        reason: 'one command, one batch',
      );
      final batch = writer.written[writer.order.first]!;
      final values =
          ((jsonDecode(batch) as Map<String, Object?>)['values']
                  as Map<String, Object?>)
              .map((key, value) => MapEntry(key, value as String));
      expect(jsonDecode(values[kBoards]!), hasLength(2));
      expect(values[kActiveBoard], store.activeBoardId);
      final activeMirror = writer.written[kActiveBoard];
      expect(activeMirror, store.activeBoardId);
      store.dispose();

      final reopened = Store(reminders: InMemoryReminderService());
      await reopened.init();
      expect(reopened.boards.map((b) => b.name), contains('第二个板'));
      expect(reopened.activeBoardId, store.activeBoardId);
      reopened.dispose();
    });

    test('an unusable store writes nothing', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final writer = RecordingWriter(prefs: prefs);
      final damaged = Store(
        persistence: const _ThrowingPersistence(),
        reminders: InMemoryReminderService(),
        saveWriter: writer.call,
      );
      await damaged.init();
      expect(damaged.ready, isFalse);
      damaged.createBoard('ignored');
      damaged.updateSettings((s) => s);
      await damaged.flush();
      expect(writer.order, isEmpty);
      damaged.dispose();

      SharedPreferences.setMockInitialValues(<String, Object>{});
      await prefs.clear();
      await prefs.setString(SaveProtocol.pointerKey, 'not-a-slot');
      final recovery = Store(
        reminders: InMemoryReminderService(),
        saveWriter: writer.call,
      );
      await recovery.init();
      expect(recovery.hasStartupRecovery, isTrue);
      writer.reset();
      recovery.createBoard('ignored');
      recovery.updateSettings((s) => s);
      recovery.completeOnboarding();
      await recovery.flush();
      expect(writer.order, isEmpty);
      expect((await recovery.retrySave()).success, isFalse);
      expect(writer.order, isEmpty);
      recovery.dispose();
    });

    test('an import blocked in its slot write and a concurrent edit keep order',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final gate = Completer<void>();
      final writer = RecordingWriter(prefs: prefs);
      var blockNext = false;
      writer.block = (key) {
        final isSlot = key == slotA || key == slotB;
        return blockNext && isSlot ? gate.future : null;
      };
      final store = await openStore(prefs, writer);
      await store.flush();
      store.addTasks([seedTask('seed', title: '既有任务')]);
      expect((await store.flush()).success, isTrue);
      writer.reset();

      blockNext = true;
      final plan = store.previewImport(<String, Object?>{
        'version': 2,
        'boards': <Object?>[
          {'id': 'board-2', 'name': '导入板', 'createdAt': 1},
        ],
        'tasks': <Object?>[
          {
            'id': 'imported',
            'boardId': 'board-2',
            'title': '导入任务',
            'quadrant': 2,
            'createdAt': 1,
            'subtasks': <Object?>[],
          },
        ],
      }, 'merge');
      final import = store.applyImport(plan);
      await pumpEventQueue(times: 20);
      expect(writer.batches, hasLength(1), reason: 'the import holds the chain');
      // A command accepted while the import holds the commit chain must land
      // after it, not inside its batch.
      store.updateTask(
        Task.fromJson(store.tasks.firstWhere((t) => t.id == 'seed').toJson())
          ..title = '编辑后续',
      );
      gate.complete();
      blockNext = false;
      expect((await import).success, isTrue);
      expect((await store.flush()).success, isTrue);
      expect(writer.batches, hasLength(2));

      List<Object?> titlesOf(String batch) {
        final values =
            ((jsonDecode(batch) as Map<String, Object?>)['values']
                    as Map<String, Object?>)
                .cast<String, String>();
        return (jsonDecode(values[kTasks]!) as List<Object?>)
            .map((entry) => (entry as Map<String, Object?>)['title'])
            .toList();
      }

      expect(titlesOf(writer.batches[0]), contains('导入任务'));
      expect(titlesOf(writer.batches[0]), isNot(contains('编辑后续')));
      expect(titlesOf(writer.batches[1]), containsAll(<String>[
        '导入任务',
        '编辑后续',
      ]));
      store.dispose();

      final reopened = Store(reminders: InMemoryReminderService());
      await reopened.init();
      expect(reopened.tasks.map((t) => t.title), contains('导入任务'));
      expect(reopened.tasks.map((t) => t.title), contains('编辑后续'));
      expect(reopened.boards.map((b) => b.name), contains('导入板'));
      reopened.dispose();
    });
  });
}

AppSettings _withFontSize(AppSettings s, FontSizePref size) => AppSettings(
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

class _ThrowingPersistence extends StorePersistence {
  const _ThrowingPersistence();

  @override
  Future<SharedPreferences> open() => throw StateError('synthetic startup');
}
