import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/data_migrations.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/storage.dart';

import 'helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, dynamic> v1FixtureJson;
  late Map<String, dynamic> v2FixtureJson;

  setUpAll(() {
    final v1File = File('test/fixtures/export-v1-minimal.json');
    v1FixtureJson = jsonDecode(v1File.readAsStringSync()) as Map<String, dynamic>;

    final v2File = File('test/fixtures/export-v2-minimal.json');
    v2FixtureJson = jsonDecode(v2File.readAsStringSync()) as Map<String, dynamic>;
  });

  group('WP11-N: DataMigrator unit tests', () {
    test('migrates v1 fixture to v2 with safe defaults', () {
      final result = DataMigrator.migratePayload(v1FixtureJson);

      expect(result.sourceVersion, 1);
      expect(result.targetVersion, 2);
      expect(result.boards.length, 1);
      expect(result.boards.first.id, 'b-v1-test');
      expect(result.boards.first.name, 'Legacy V1 Board');

      expect(result.tasks.length, 1);
      final task = result.tasks.first;
      expect(task.id, 't-v1-task');
      expect(task.title, 'Legacy V1 Task');
      expect(task.quadrant, qDo);
      expect(task.subtasks.length, 1);
      expect(task.subtasks.first.title, 'Legacy V1 Subtask');
      expect(task.subtasks.first.completed, isTrue);

      // Verify v2 new fields safely defaulted
      expect(result.settings, isNotNull);
      expect(result.settings!.language, Language.zh);
      expect(result.settings!.theme, ThemeModePref.dark);
      expect(result.settings!.viewMode, ViewMode.grid); // default fallback
      expect(result.settings!.fontSize, FontSizePref.standard); // default fallback
      expect(result.settings!.fontFamily, FontFamilyPref.system); // default fallback
      expect(result.settings!.closeToTray, isFalse); // default fallback
      expect(result.settings!.globalShortcut, 'Ctrl+Alt+M'); // default fallback

      expect(result.warnings.any((w) => w.contains('v1') && w.contains('v2')), isTrue);
    });

    test('treats payload without explicit version as legacy v1', () {
      final unversioned = Map<String, dynamic>.from(v1FixtureJson)..remove('version');
      final result = DataMigrator.migratePayload(unversioned);

      expect(result.sourceVersion, 1);
      expect(result.targetVersion, 2);
      expect(result.tasks.first.id, 't-v1-task');
    });

    test('parses v2 fixture directly with all v2 settings preserved', () {
      final result = DataMigrator.migratePayload(v2FixtureJson);

      expect(result.sourceVersion, 2);
      expect(result.targetVersion, 2);
      expect(result.boards.first.id, 'b-v2-test');
      expect(result.tasks.first.id, 't-v2-task');
      expect(result.tasks.first.isLongTerm, isTrue);

      expect(result.settings!.viewMode, ViewMode.list);
      expect(result.settings!.fontSize, FontSizePref.large);
      expect(result.settings!.fontFamily, FontFamilyPref.sansSerif);
      expect(result.settings!.closeToTray, isTrue);
      expect(result.settings!.globalShortcut, 'Ctrl+Shift+M');
    });

    test('deduplicates duplicate board and task IDs (keeps first occurrence)', () {
      final payload = {
        'version': 2,
        'boards': [
          {'id': 'b1', 'name': 'First Board', 'createdAt': 100},
          {'id': 'b1', 'name': 'Duplicate Board', 'createdAt': 200},
          {'id': 'b2', 'name': 'Second Board', 'createdAt': 300},
        ],
        'tasks': [
          {'id': 't1', 'boardId': 'b1', 'title': 'First Task', 'quadrant': 1, 'createdAt': 100},
          {'id': 't1', 'boardId': 'b1', 'title': 'Duplicate Task', 'quadrant': 2, 'createdAt': 200},
          {'id': 't2', 'boardId': 'b2', 'title': 'Second Task', 'quadrant': 3, 'createdAt': 300},
        ],
      };

      final result = DataMigrator.migratePayload(payload);
      expect(result.boards.length, 2);
      expect(result.boards.map((b) => b.name), ['First Board', 'Second Board']);

      expect(result.tasks.length, 2);
      expect(result.tasks.map((t) => t.title), ['First Task', 'Second Task']);

      expect(result.warnings.any((w) => w.contains('Duplicate board ID removed: b1')), isTrue);
      expect(result.warnings.any((w) => w.contains('Duplicate task ID removed: t1')), isTrue);
    });

    test('strictly rejects unsupported future versions (e.g. version 3, 99)', () {
      final futurePayloadV3 = Map<String, dynamic>.from(v2FixtureJson)..['version'] = 3;
      expect(
        () => DataMigrator.migratePayload(futurePayloadV3),
        throwsA(isA<UnsupportedDataVersionException>().having(
          (e) => e.version,
          'version',
          3,
        )),
      );

      final futurePayloadV99 = Map<String, dynamic>.from(v2FixtureJson)..['version'] = 99;
      expect(
        () => DataMigrator.migratePayload(futurePayloadV99),
        throwsA(isA<UnsupportedDataVersionException>().having(
          (e) => e.version,
          'version',
          99,
        )),
      );
    });

    test('rejects negative or zero versions', () {
      final invalidZero = Map<String, dynamic>.from(v2FixtureJson)..['version'] = 0;
      expect(() => DataMigrator.migratePayload(invalidZero), throwsA(isA<UnsupportedDataVersionException>()));

      final invalidNegative = Map<String, dynamic>.from(v2FixtureJson)..['version'] = -1;
      expect(() => DataMigrator.migratePayload(invalidNegative), throwsA(isA<UnsupportedDataVersionException>()));
    });

    test('rejects non-integer version values', () {
      final invalidType = Map<String, dynamic>.from(v2FixtureJson)..['version'] = '2.0';
      expect(() => DataMigrator.migratePayload(invalidType), throwsFormatException);
    });

    test('rejects payloads missing boards or tasks arrays', () {
      expect(() => DataMigrator.migratePayload({'tasks': []}), throwsFormatException);
      expect(() => DataMigrator.migratePayload({'boards': []}), throwsFormatException);
      expect(() => DataMigrator.migratePayload({'boards': 'invalid', 'tasks': []}), throwsFormatException);
      expect(() => DataMigrator.migratePayload({'boards': [], 'tasks': 'invalid'}), throwsFormatException);
    });

    test('migration is idempotent: migrating v2 twice produces identical result', () {
      final firstPass = DataMigrator.migratePayload(v2FixtureJson);
      final serializedAgain = ExportData(
        boards: firstPass.boards,
        tasks: firstPass.tasks,
        settings: firstPass.settings!,
        aiConfig: firstPass.aiConfig!,
      ).toJson();

      final secondPass = DataMigrator.migratePayload(serializedAgain);
      expect(secondPass.targetVersion, 2);
      expect(secondPass.boards.length, firstPass.boards.length);
      expect(secondPass.tasks.length, firstPass.tasks.length);
      expect(secondPass.tasks.first.title, firstPass.tasks.first.title);
      expect(secondPass.settings!.viewMode, firstPass.settings!.viewMode);
      expect(secondPass.settings!.fontSize, firstPass.settings!.fontSize);
    });
  });

  group('WP11-N: Store integration, atomicity & backward compatibility', () {
    test('store.importData successfully imports v1 payload and upgrades in memory', () async {
      final (store, _) = await makeStore(
        boards: [Board(id: 'init-b', name: 'Initial', createdAt: 1)],
      );

      final count = store.importData(v1FixtureJson, 'overwrite');
      expect(count, 1);
      expect(store.boards.single.id, 'b-v1-test');
      expect(store.tasks.single.id, 't-v1-task');
      expect(store.settings.language, Language.zh);
      expect(store.settings.viewMode, ViewMode.grid); // Safe default for v1
      expect(store.settings.closeToTray, isFalse);
    });

    test('store.importData in overwrite mode is atomic: invalid payload leaves previous state 100% intact', () async {
      final (store, _) = await makeStore(
        boards: [Board(id: 'safe-b', name: 'Safe Board', createdAt: 10)],
        tasks: [Task(id: 'safe-t', boardId: 'safe-b', title: 'Protected Task', quadrant: qPlan, createdAt: 10)],
        settings: AppSettings(language: Language.ja, viewMode: ViewMode.list),
      );

      // Attempt 1: Unsupported future version
      expect(
        () => store.importData({'version': 3, 'boards': [], 'tasks': []}, 'overwrite'),
        throwsFormatException,
      );
      expect(store.boards.single.id, 'safe-b');
      expect(store.tasks.single.id, 'safe-t');
      expect(store.settings.language, Language.ja);

      // Attempt 2: Missing boards list
      expect(
        () => store.importData({'tasks': []}, 'overwrite'),
        throwsFormatException,
      );
      expect(store.boards.single.id, 'safe-b');
      expect(store.tasks.single.id, 'safe-t');

      // Attempt 3: Task referencing missing board in overwrite
      expect(
        () => store.importData({
          'version': 2,
          'boards': [{'id': 'b1', 'name': 'B1', 'createdAt': 1}],
          'tasks': [{'id': 't1', 'boardId': 'non-existent-board', 'title': 'T1', 'quadrant': 1, 'createdAt': 1}],
        }, 'overwrite'),
        throwsFormatException,
      );
      expect(store.boards.single.id, 'safe-b');
      expect(store.tasks.single.id, 'safe-t');
    });

    test('store.importData in merge mode drops orphan tasks and skips existing IDs', () async {
      final (store, _) = await makeStore(
        boards: [Board(id: 'b1', name: 'Board 1', createdAt: 1)],
        tasks: [Task(id: 't1', boardId: 'b1', title: 'Task 1', quadrant: qPlan, createdAt: 1)],
      );

      final imported = store.importData({
        'version': 2,
        'boards': [
          {'id': 'b1', 'name': 'Board 1 Dup', 'createdAt': 1},
          {'id': 'b2', 'name': 'Board 2', 'createdAt': 2},
        ],
        'tasks': [
          {'id': 't1', 'boardId': 'b1', 'title': 'Task 1 Dup', 'quadrant': 1, 'createdAt': 1},
          {'id': 't2', 'boardId': 'b2', 'title': 'Task 2 New', 'quadrant': 2, 'createdAt': 2},
          {'id': 't3', 'boardId': 'orphan-board', 'title': 'Orphan', 'quadrant': 3, 'createdAt': 3},
        ],
      }, 'merge');

      expect(imported, 1);
      expect(store.boards.length, 2);
      expect(store.tasks.map((t) => t.id), ['t1', 't2']);
    });

    test('Flutter Android <-> Windows roundtrip interchangeability is 100% lossless', () async {
      // Create source store (e.g. simulated Android device)
      final (androidStore, _) = await makeStore(
        boards: [
          Board(id: 'b-cross-1', name: 'Work Board', createdAt: 1000),
          Board(id: 'b-cross-2', name: 'Life Board', createdAt: 2000),
        ],
        tasks: [
          Task(
            id: 't-cross-1',
            boardId: 'b-cross-1',
            title: 'Refactor Architecture',
            quadrant: qDo,
            isLongTerm: true,
            createdAt: 1000,
            deadline: 5000,
            subtasks: [
              SubTask(id: 's-cross-1', title: 'Design interfaces', completed: true, deadline: 3000),
              SubTask(id: 's-cross-2', title: 'Write unit tests', completed: false),
            ],
          ),
          Task(
            id: 't-cross-2',
            boardId: 'b-cross-2',
            title: 'Read Books',
            quadrant: qPlan,
            createdAt: 2000,
          ),
        ],
        settings: AppSettings(
          language: Language.zh,
          theme: ThemeModePref.dark,
          themeColor: ThemeColor.green,
          viewMode: ViewMode.list,
          fontSize: FontSizePref.large,
          fontFamily: FontFamilyPref.monospace,
          closeToTray: true,
          globalShortcut: 'Ctrl+Alt+F',
          autoCompleteParent: true,
        ),
        aiConfig: AIConfig(
          provider: 'bailian',
          protocol: AIProtocol.openai,
          baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
          model: 'qwen-plus',
          enableThinking: true,
        ),
      );

      // Export JSON from Android
      final exportedJsonStr = androidStore.exportJson();
      final exportedMap = jsonDecode(exportedJsonStr) as Map<String, dynamic>;

      expect(exportedMap['version'], 2);

      // Create target store (e.g. simulated Windows desktop)
      final (windowsStore, _) = await makeStore();

      // Import JSON into Windows store
      final importedCount = windowsStore.importData(exportedMap, 'overwrite');
      expect(importedCount, 2);

      // Verify Windows store has identical state
      expect(windowsStore.boards.length, 2);
      expect(windowsStore.boards[0].id, 'b-cross-1');
      expect(windowsStore.boards[1].id, 'b-cross-2');

      expect(windowsStore.tasks.length, 2);
      final t1 = windowsStore.tasks.firstWhere((t) => t.id == 't-cross-1');
      expect(t1.title, 'Refactor Architecture');
      expect(t1.quadrant, qDo);
      expect(t1.isLongTerm, isTrue);
      expect(t1.deadline, 5000);
      expect(t1.subtasks.length, 2);
      expect(t1.subtasks[0].title, 'Design interfaces');
      expect(t1.subtasks[0].completed, isTrue);
      expect(t1.subtasks[0].deadline, 3000);
      expect(t1.subtasks[1].title, 'Write unit tests');
      expect(t1.subtasks[1].completed, isFalse);

      expect(windowsStore.settings.language, Language.zh);
      expect(windowsStore.settings.theme, ThemeModePref.dark);
      expect(windowsStore.settings.themeColor, ThemeColor.green);
      expect(windowsStore.settings.viewMode, ViewMode.list);
      expect(windowsStore.settings.fontSize, FontSizePref.large);
      expect(windowsStore.settings.fontFamily, FontFamilyPref.monospace);
      expect(windowsStore.settings.closeToTray, isTrue);
      expect(windowsStore.settings.globalShortcut, 'Ctrl+Alt+F');
      expect(windowsStore.settings.autoCompleteParent, isTrue);

      expect(windowsStore.aiConfig.provider, 'bailian');
      expect(windowsStore.aiConfig.baseUrl, 'https://dashscope.aliyuncs.com/compatible-mode/v1');
      expect(windowsStore.aiConfig.model, 'qwen-plus');
      expect(windowsStore.aiConfig.enableThinking, isTrue);

      // Export back from Windows to Android
      final roundtripExport = windowsStore.exportJson();
      final (androidStore2, _) = await makeStore();
      androidStore2.importData(jsonDecode(roundtripExport) as Map<String, dynamic>, 'overwrite');

      expect(androidStore2.tasks.length, 2);
      expect(androidStore2.settings.viewMode, ViewMode.list);
      expect(androidStore2.settings.globalShortcut, 'Ctrl+Alt+F');
    });

    test('downgrade export v1 produces compatible format and can be imported back', () async {
      final (store, _) = await makeStore(
        boards: [Board(id: 'b1', name: 'Board', createdAt: 1)],
        tasks: [Task(id: 't1', boardId: 'b1', title: 'Task', quadrant: 1, createdAt: 1)],
        settings: AppSettings(
          language: Language.en,
          viewMode: ViewMode.list,
          fontSize: FontSizePref.large,
          closeToTray: true,
        ),
      );

      final v1ExportStr = store.exportJson(version: 1);
      final v1Map = jsonDecode(v1ExportStr) as Map<String, dynamic>;

      expect(v1Map['version'], 1);
      final settingsMap = v1Map['settings'] as Map<String, dynamic>;
      expect(settingsMap.containsKey('viewMode'), isFalse);
      expect(settingsMap.containsKey('fontSize'), isFalse);
      expect(settingsMap.containsKey('closeToTray'), isFalse);

      // Can be imported into fresh store and safely falls back
      final (newStore, _) = await makeStore();
      newStore.importData(v1Map, 'overwrite');
      expect(newStore.tasks.single.id, 't1');
      expect(newStore.settings.viewMode, ViewMode.grid); // Safe default for v1
    });

    test('completedAt serialization in v2 and stripping on downgrade to v1', () {
      final task = Task(
        id: 't_comp',
        boardId: 'b1',
        title: 'Task completed',
        quadrant: 1,
        createdAt: 100,
        completed: true,
        completedAt: 5000,
        subtasks: [
          SubTask(
            id: 's_comp',
            title: 'Sub completed',
            completed: true,
            completedAt: 5000,
          ),
        ],
      );

      // V2 serialization preserves completedAt
      final v2Json = task.toJson(targetVersion: 2);
      expect(v2Json['completedAt'], 5000);
      expect((v2Json['subtasks'] as List)[0]['completedAt'], 5000);

      // V1 downgrade serialization strips completedAt
      final v1Json = task.toJson(targetVersion: 1);
      expect(v1Json.containsKey('completedAt'), isFalse);
      expect((v1Json['subtasks'] as List)[0].containsKey('completedAt'), isFalse);

      // Deserializing v1 leaves completedAt null without synthesizing from createdAt
      final fromV1 = Task.fromJson(v1Json);
      expect(fromV1.completedAt, isNull);
      expect(fromV1.subtasks.first.completedAt, isNull);

      // Deserializing v2 restores completedAt
      final fromV2 = Task.fromJson(v2Json);
      expect(fromV2.completedAt, 5000);
      expect(fromV2.subtasks.first.completedAt, 5000);
    });
  });
}
