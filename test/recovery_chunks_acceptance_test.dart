import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/recovery_text.dart';
import 'package:matrixflow_native/storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'rf02_import_commit_race_test.dart' as fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('recovery hash and JSON string size match known values', () {
    expect(
      recoverySha256Hex(utf8.encode('')),
      'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
    );
    expect(
      recoverySha256Hex(utf8.encode('abc')),
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
    final samples = <String>[
      '',
      'a',
      '"',
      r'\',
      '\n',
      '\u0001',
      '整',
      '😀',
      'say "hello"\n\\next',
    ];
    for (var unit = 0; unit < 128; unit++) {
      samples.add(String.fromCharCode(unit));
    }
    for (final sample in samples) {
      expect(
        jsonStringUtf8Length(sample),
        utf8.encode(jsonEncode(sample)).length - 2,
        reason: sample,
      );
    }
    const budget = 8;
    final sliced = sliceJsonText('"${'\\' * 20}整😀', budget);
    expect(sliced.join(), '"${'\\' * 20}整😀');
    for (final part in sliced) {
      expect(jsonStringUtf8Length(part), lessThanOrEqualTo(budget));
    }
  });

  test(
    're-importing a recovery continuation must not duplicate note text',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = await fixture.openStore();
      addTearDown(store.dispose);
      final task = store.newTask('Synthetic');
      task.notesMarkdown = 'first-';
      store.addTasks([task]);
      await store.flush();
      final continuation = {
        ...fixture.payload(fixture.currentBoards(store), []),
        'recovery': true,
        'recoveryChunks': [
          {
            'taskId': task.id,
            'field': 'notesMarkdown',
            'index': 1,
            'text': 'second',
          },
        ],
      };
      expect(
        (await store.applyImport(
          store.previewImport(continuation, 'merge'),
        )).success,
        isTrue,
      );
      expect(store.tasks.single.notesMarkdown, 'first-second');
      try {
        await store.applyImport(store.previewImport(continuation, 'merge'));
      } catch (_) {
        // Explicit rejection is also safe; silently appending twice is not.
      }
      expect(store.tasks.single.notesMarkdown, 'first-second');
    },
  );

  test(
    'combined parent and child notes exceeding one file remain recoverable',
    () {
      final note = '整' * 1000000;
      final document = fixture.payload(fixture.newBoards('board'), [
        {
          ...fixture.taskJson('task', 'board', 'Synthetic'),
          'notesMarkdown': note,
          'subtasks': [
            for (var i = 0; i < 2; i++)
              {
                'id': 'child$i',
                'title': 'Synthetic child',
                'notesMarkdown': note,
              },
          ],
        },
      ]);
      final bundle = buildBackupBundle(jsonEncode(document));
      expect(
        bundle.recoverable,
        isTrue,
        reason: 'Each note is 3 MB, but the accepted task totals 9 MB.',
      );
    },
  );

  test(
    'a positioned chunk is idempotent and rejects a broken sequence',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = await fixture.openStore();
      addTearDown(store.dispose);
      final task = store.newTask('Synthetic');
      task.subtasks = [SubTask(id: 'child', title: 'Child')];
      store.addTasks([task]);
      await store.flush();
      const parent = 'AAAA-BBBB-CCCC';
      const child = 'aaaa-bbbb';
      final parentParts = ['AAAA', '-BBBB', '-CCCC'];
      final childParts = ['aaaa', '-bbbb'];

      Map<String, dynamic> piece(
        String full,
        List<String> parts,
        int index, {
        String? subtaskId,
      }) {
        var offset = 0;
        for (var i = 0; i < index; i++) {
          offset += parts[i].length;
        }
        return {
          'taskId': task.id,
          if (subtaskId != null) 'subtaskId': subtaskId,
          'field': 'notesMarkdown',
          'index': index,
          'offset': offset,
          'length': full.length,
          'archiveId': recoverySha256Hex(utf8.encode(full)),
          'prefixSha256': recoverySha256Hex(
            utf8.encode(full.substring(0, offset)),
          ),
          'text': parts[index],
        };
      }

      Future<void> merge(List<Map<String, dynamic>> chunks) async {
        expect(
          (await store.applyImport(
            store.previewImport(_continuation(store, chunks), 'merge'),
          )).success,
          isTrue,
        );
      }

      expect(
        () => store.previewImport(
          _continuation(store, [piece(parent, parentParts, 2)]),
          'merge',
        ),
        throwsA(
          isA<BackupRejectedException>().having(
            (error) => error.copy,
            'copy',
            'importErrorRecoveryChunk',
          ),
        ),
      );
      expect(store.tasks.single.notesMarkdown, isNull);

      await merge([
        piece(parent, parentParts, 0),
        piece(child, childParts, 0, subtaskId: 'child'),
      ]);
      await merge([piece(child, childParts, 1, subtaskId: 'child')]);
      expect(store.tasks.single.notesMarkdown, 'AAAA');
      expect(store.tasks.single.subtasks.single.notesMarkdown, child);

      final forged = piece(parent, parentParts, 1);
      forged['archiveId'] = recoverySha256Hex(utf8.encode('other-archive'));
      forged['text'] = '-XXXX';
      expect(
        () => store.previewImport(_continuation(store, [forged]), 'merge'),
        throwsA(isA<BackupRejectedException>()),
      );
      expect(store.tasks.single.notesMarkdown, 'AAAA');

      final edited = Task.fromJson(store.tasks.single.toJson())
        ..notesMarkdown = 'AAAX';
      store.updateTask(edited);
      expect(
        () => store.previewImport(
          _continuation(store, [piece(parent, parentParts, 1)]),
          'merge',
        ),
        throwsA(isA<BackupRejectedException>()),
      );
      expect(store.tasks.single.notesMarkdown, 'AAAX');

      store.updateTask(
        Task.fromJson(store.tasks.single.toJson())..notesMarkdown = 'AAAA',
      );
      await merge([piece(parent, parentParts, 0)]);
      expect(store.tasks.single.notesMarkdown, 'AAAA');
      expect(store.tasks.single.subtasks.single.notesMarkdown, child);
    },
  );

  test(
    'a partial restore continues after restart and does not repeat',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = await fixture.openStore();
      final task = store.newTask('Synthetic');
      task.subtasks = [SubTask(id: 'child', title: 'Child')];
      store.addTasks([task]);
      await store.flush();
      const full = 'AAAA-BBBB-CCCC';
      final parts = ['AAAA', '-BBBB', '-CCCC'];
      Map<String, dynamic> piece(int index) {
        var offset = 0;
        for (var i = 0; i < index; i++) {
          offset += parts[i].length;
        }
        return {
          'taskId': task.id,
          'field': 'notesMarkdown',
          'index': index,
          'offset': offset,
          'length': full.length,
          'archiveId': recoverySha256Hex(utf8.encode(full)),
          'prefixSha256': recoverySha256Hex(
            utf8.encode(full.substring(0, offset)),
          ),
          'text': parts[index],
        };
      }

      expect(
        (await store.applyImport(
          store.previewImport(_continuation(store, [piece(0)]), 'merge'),
        )).success,
        isTrue,
      );
      expect(store.tasks.single.notesMarkdown, 'AAAA');
      expect((await store.flush()).success, isTrue);
      store.dispose();

      final restarted = await fixture.openStore();
      addTearDown(restarted.dispose);
      expect(restarted.tasks.single.notesMarkdown, 'AAAA');
      expect(
        (await restarted.applyImport(
          restarted.previewImport(
            _continuation(restarted, [piece(0)]),
            'merge',
          ),
        )).success,
        isTrue,
      );
      expect(restarted.tasks.single.notesMarkdown, 'AAAA');
      expect(
        () => restarted.previewImport(
          _continuation(restarted, [piece(2)]),
          'merge',
        ),
        throwsA(isA<BackupRejectedException>()),
      );
      expect(restarted.tasks.single.notesMarkdown, 'AAAA');
      expect(
        (await restarted.applyImport(
          restarted.previewImport(
            _continuation(restarted, [piece(1)]),
            'merge',
          ),
        )).success,
        isTrue,
      );
      expect(
        (await restarted.applyImport(
          restarted.previewImport(
            _continuation(restarted, [piece(2)]),
            'merge',
          ),
        )).success,
        isTrue,
      );
      expect(restarted.tasks.single.notesMarkdown, full);
      expect(
        (await restarted.applyImport(
          restarted.previewImport(
            _continuation(restarted, [piece(1), piece(2)]),
            'merge',
          ),
        )).success,
        isTrue,
      );
      expect(restarted.tasks.single.notesMarkdown, full);
      expect(restarted.tasks.single.recoveryPending, isNull);
    },
  );

  test(
    'several notes that each fit, but not together, round-trip',
    () async {
      final note = '\\' * 1500000;
      final bundle = await _library({
        'notesMarkdown': note,
        'subtasks': [
          for (var i = 0; i < 2; i++)
            {
              'id': 'child$i',
              'title': 'Synthetic child',
              'notesMarkdown': note,
            },
        ],
      });
      expect(bundle.recoverable, isTrue);
      expect(
        bundle.parts.every(
          (part) => part.bytes <= ImportPreflight.maxFileBytes,
        ),
        isTrue,
      );
      final restored = await _restore(bundle);
      expect(restored.store.tasks.single.notesMarkdown, note);
      expect(restored.store.tasks.single.title, 'Synthetic');
      expect(restored.store.tasks.single.boardId, _exportedBoardId(bundle));
      expect(
        restored.store.tasks.single.subtasks.map((sub) => sub.notesMarkdown),
        [note, note],
      );
      expect(restored.store.settings.language, Language.ja);
      expect(restored.store.settings.globalShortcut, 'Ctrl+Alt+J');
      expect(restored.store.aiConfig.model, 'synthetic-recovery-model');
      expect(restored.store.tasks.single.recoveryPending, isNull);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'quotes that expand past one file round-trip as recovery chunks',
    () async {
      final note = '"' * 4300000;
      final bundle = await _library({'notesMarkdown': note});
      expect(bundle.recoverable, isTrue);
      expect(
        bundle.parts.every(
          (part) => part.bytes <= ImportPreflight.maxFileBytes,
        ),
        isTrue,
      );
      expect(utf8.encode(note).length < ImportPreflight.maxFileBytes, isTrue);
      final restored = await _restore(bundle);
      expect(restored.store.tasks.single.notesMarkdown, note);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'oversized parent and child titles round-trip',
    () async {
      final title = '\\' * 2300000;
      final bundle = await _library({
        'title': title,
        'subtasks': [
          {'id': 'child', 'title': title},
        ],
      });
      expect(bundle.recoverable, isTrue);
      expect(
        bundle.parts.every(
          (part) => part.bytes <= ImportPreflight.maxFileBytes,
        ),
        isTrue,
      );
      final restored = await _restore(bundle);
      expect(restored.store.tasks.single.title, title);
      expect(restored.store.tasks.single.subtasks.single.title, title);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'a multi-volume note survives a repeated import and a restart',
    () async {
      final note = 'a' * (ImportPreflight.maxBytes * 2);
      final built = await _library({'notesMarkdown': note});
      expect(built.parts.length, greaterThan(1));
      final store = (await _restore(built)).store;
      expect(store.tasks.single.notesMarkdown, note);

      final first = jsonDecode(built.parts.first.json) as Map<String, dynamic>;
      final last = jsonDecode(built.parts.last.json) as Map<String, dynamic>;
      await store.applyImport(store.previewImport(first, 'merge'));
      expect(store.tasks.single.notesMarkdown, note);
      expect(
        (await store.applyImport(store.previewImport(last, 'merge'))).success,
        isTrue,
      );
      expect(store.tasks.single.notesMarkdown, note);
      expect((await store.flush()).success, isTrue);

      final restarted = await fixture.openStore();
      addTearDown(restarted.dispose);
      expect(restarted.tasks.single.notesMarkdown, note);
      expect(
        (await restarted.applyImport(
          restarted.previewImport(last, 'merge'),
        )).success,
        isTrue,
      );
      expect(restarted.tasks.single.notesMarkdown, note);

      SharedPreferences.setMockInitialValues({});
      final fresh = Store();
      await fresh.init();
      addTearDown(fresh.dispose);
      expect(
        () => fresh.previewImport(last, 'overwrite'),
        throwsA(isA<BackupRejectedException>()),
      );
      expect(fresh.tasks.where((task) => task.notesMarkdown == note), isEmpty);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

String _exportedBoardId(BackupBundle bundle) {
  for (final part in bundle.parts) {
    final tasks = (jsonDecode(part.json) as Map)['tasks'];
    if (tasks is List && tasks.isNotEmpty) {
      return (tasks.first as Map)['boardId'] as String;
    }
  }
  throw StateError('Exported bundle has no task');
}

Map<String, dynamic> _continuation(
  Store store,
  List<Map<String, dynamic>> chunks,
) => {
  ...fixture.payload(fixture.currentBoards(store), []),
  'recovery': true,
  'recoveryChunks': chunks,
};

class _Restored {
  const _Restored(this.store);
  final Store store;
}

Future<BackupBundle> _library(Map<String, dynamic> task) async {
  SharedPreferences.setMockInitialValues({});
  final store = await fixture.openStore();
  try {
    store.updateSettings(
      (settings) => settings
        ..language = Language.ja
        ..globalShortcut = 'Ctrl+Alt+J',
    );
    final config = AIConfig(
      provider: store.aiConfig.provider,
      protocol: store.aiConfig.protocol,
      baseUrl: store.aiConfig.baseUrl,
      apiKey: '',
      model: 'synthetic-recovery-model',
      enableThinking: store.aiConfig.enableThinking,
    );
    expect(await store.updateAIConfig(config), isTrue);
    store.addTasks([
      Task(
        id: 'task',
        boardId: store.activeBoardId,
        title: task['title'] as String? ?? 'Synthetic',
        quadrant: 1,
        createdAt: 1,
        notesMarkdown: task['notesMarkdown'] as String?,
        subtasks: [
          for (final raw in (task['subtasks'] as List?) ?? const [])
            SubTask(
              id: raw['id'] as String,
              title: raw['title'] as String? ?? 'Synthetic child',
              notesMarkdown: raw['notesMarkdown'] as String?,
            ),
        ],
      ),
    ]);
    final document = jsonDecode(store.exportJson()) as Map<String, dynamic>;
    return buildBackupBundle(jsonEncode(document));
  } finally {
    store.dispose();
  }
}

Future<_Restored> _restore(BackupBundle bundle) async {
  SharedPreferences.setMockInitialValues({});
  final store = Store();
  await store.init();
  addTearDown(store.dispose);
  for (var i = 0; i < bundle.parts.length; i++) {
    final plan = store.previewImport(
      jsonDecode(bundle.parts[i].json) as Map<String, dynamic>,
      i == 0 ? 'overwrite' : 'merge',
    );
    expect((await store.applyImport(plan)).success, isTrue, reason: 'part $i');
  }
  return _Restored(store);
}
