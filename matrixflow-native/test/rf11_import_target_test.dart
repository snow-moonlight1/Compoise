import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/screens/settings_backup_flow.dart';
import 'package:matrixflow_native/storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _backup({String taskId = 'imported'}) => {
  'version': 2,
  'boards': [
    {'id': 'source-a', 'name': 'From A', 'createdAt': 1},
    {'id': 'source-b', 'name': 'From B', 'createdAt': 2},
  ],
  'tasks': [
    {
      'id': taskId,
      'boardId': 'source-a',
      'title': 'Imported A',
      'quadrant': 1,
      'createdAt': 1,
      'subtasks': <Object>[],
    },
    {
      'id': 'imported-b',
      'boardId': 'source-b',
      'title': 'Imported B',
      'quadrant': 2,
      'createdAt': 2,
      'subtasks': <Object>[],
    },
  ],
  'settings': {'theme': 'dark'},
};

Future<Store> _open() async {
  final store = Store();
  await store.init();
  await store.flush();
  return store;
}

class _ImportPicker extends FilePicker {
  _ImportPicker(this.bytes);
  final Uint8List bytes;

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
  }) async => FilePickerResult([
    PlatformFile(name: 'synthetic.json', size: bytes.length, bytes: bytes),
  ]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'merge into a selected existing board routes every source board there',
    () async {
      final store = await _open();
      final target = store.boards.first;
      store.addTasks([
        Task(
          id: 'local',
          boardId: target.id,
          title: 'Keep me',
          quadrant: 1,
          createdAt: 1,
        ),
      ]);
      store.updateSettings((settings) => settings..theme = ThemeModePref.light);
      final plan = store.previewImport(
        _backup(),
        'merge',
        targetBoardId: target.id,
      );
      expect(plan.targetBoardId, target.id);
      expect(plan.addedBoards, 0);
      expect(plan.addedTasks, 2);
      expect(plan.settings, isNull);
      expect(plan.tasks.map((task) => task.boardId).toSet(), {target.id});
      expect((await store.applyImport(plan)).success, isTrue);
      expect((await store.flush()).success, isTrue);
      expect(store.boards, hasLength(1));
      expect(store.tasks, hasLength(3));
      expect(store.tasks.map((task) => task.boardId).toSet(), {target.id});
      expect(store.settings.theme, ThemeModePref.light);
      store.dispose();

      final restarted = await _open();
      addTearDown(restarted.dispose);
      expect(restarted.boards, hasLength(1));
      expect(restarted.tasks.map((task) => task.title).toSet(), {
        'Keep me',
        'Imported A',
        'Imported B',
      });
      expect(restarted.tasks.map((task) => task.boardId).toSet(), {target.id});
    },
  );

  test(
    'selected target is retained when another task arrives after preview',
    () async {
      final store = await _open();
      addTearDown(store.dispose);
      final target = store.boards.first.id;
      final plan = store.previewImport(
        _backup(),
        'merge',
        targetBoardId: target,
      );
      store.addTasks([
        Task(
          id: 'during-preview',
          boardId: target,
          title: 'New local',
          quadrant: 3,
          createdAt: 3,
        ),
      ]);
      expect((await store.applyImport(plan)).success, isTrue);
      expect(store.tasks.map((task) => task.id).toSet(), {
        'during-preview',
        'imported',
        'imported-b',
      });
      expect(store.boards, hasLength(1));
    },
  );

  test(
    'selected target deleted after preview rejects the whole import',
    () async {
      final store = await _open();
      addTearDown(store.dispose);
      store.createBoard('Temporary');
      final target = store.activeBoardId;
      final plan = store.previewImport(
        _backup(),
        'merge',
        targetBoardId: target,
      );
      store.deleteBoard(target);
      expect((await store.applyImport(plan)).success, isFalse);
      expect(store.tasks, isEmpty);
      expect(store.boards.any((board) => board.id == target), isFalse);
    },
  );

  test(
    'repeated target merge skips identical tasks; conflicting ID blocks',
    () async {
      final store = await _open();
      addTearDown(store.dispose);
      final target = store.boards.first.id;
      final first = store.previewImport(
        _backup(),
        'merge',
        targetBoardId: target,
      );
      expect((await store.applyImport(first)).success, isTrue);
      final duplicate = store.previewImport(
        _backup(),
        'merge',
        targetBoardId: target,
      );
      expect(duplicate.addedTasks, 0);
      expect(duplicate.conflicts, 0);
      final changed = _backup();
      (changed['tasks'] as List).first['title'] = 'Changed elsewhere';
      final conflict = store.previewImport(
        changed,
        'merge',
        targetBoardId: target,
      );
      expect(conflict.conflicts, 1);
      expect((await store.applyImport(conflict)).success, isFalse);
      expect(
        store.tasks.firstWhere((task) => task.id == 'imported').title,
        'Imported A',
      );
    },
  );

  test(
    'backup-board merge keeps source boards; overwrite replaces everything',
    () async {
      final store = await _open();
      addTearDown(store.dispose);
      final backup = _backup();
      final merge = store.previewImport(backup, 'merge');
      expect(merge.addedBoards, 2);
      expect((await store.applyImport(merge)).success, isTrue);
      expect(
        store.boards.map((board) => board.id).toSet(),
        containsAll(['source-a', 'source-b']),
      );
      expect(store.settings.theme, ThemeModePref.system);

      store.updateSettings((settings) => settings..theme = ThemeModePref.light);
      final overwrite = store.previewImport(backup, 'overwrite');
      expect((await store.applyImport(overwrite)).success, isTrue);
      expect(store.boards.map((board) => board.id).toSet(), {
        'source-a',
        'source-b',
      });
      expect(store.tasks, hasLength(2));
      expect(store.settings.theme, ThemeModePref.dark);
      expect(store.activeBoardId, 'source-a');
    },
  );

  test('target merge keeps the existing orphan-data rejection rule', () async {
    final store = await _open();
    addTearDown(store.dispose);
    final backup = _backup();
    (backup['tasks'] as List).first['boardId'] = 'missing-source-board';
    final plan = store.previewImport(
      backup,
      'merge',
      targetBoardId: store.boards.first.id,
    );
    expect(plan.addedTasks, 1);
    expect(plan.skipped, 1);
    expect(plan.warnings, contains('Orphan task skipped'));
    expect((await store.applyImport(plan)).success, isTrue);
    expect(store.tasks.single.id, 'imported-b');
  });

  test(
    'successive backup parts reuse the chosen board without duplicating',
    () async {
      final store = await _open();
      addTearDown(store.dispose);
      final target = store.boards.first.id;
      final first = _backup();
      final second = _backup(taskId: 'second-part');
      for (final payload in [first, second, first]) {
        final plan = store.previewImport(
          payload,
          'merge',
          targetBoardId: target,
        );
        expect((await store.applyImport(plan)).success, isTrue);
      }
      expect(store.boards, hasLength(1));
      expect(store.tasks.map((task) => task.id).toSet(), {
        'imported',
        'second-part',
        'imported-b',
      });
      expect(store.tasks.map((task) => task.boardId).toSet(), {target});
    },
  );

  testWidgets('file import asks for a board and previews that exact target', (
    tester,
  ) async {
    final store = await _open();
    store.createBoard('Target A');
    final targetA = store.activeBoardId;
    store.createBoard('Target B');
    final targetB = store.activeBoardId;
    FilePicker.platform = _ImportPicker(
      Uint8List.fromList(utf8.encode(jsonEncode(_backup()))),
    );
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
    final flow = SettingsBackupFlow(onBusyChanged: (_) {});
    final running = flow.importBackup(context, store, syncAiFields: () {});
    await tester.pumpAndSettle();
    expect(find.text(store.t['importModeMerge']!), findsOneWidget);
    expect(find.text(store.t['importModeMergeInto']!), findsOneWidget);
    expect(find.text(store.t['importModeOverwrite']!), findsOneWidget);
    await tester.tap(find.text(store.t['importModeMergeInto']!));
    await tester.pumpAndSettle();
    expect(find.text(store.t['importSelectBoard']!), findsOneWidget);
    await tester.tap(find.text('Target A'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Target A'), findsWidgets);
    expect(find.textContaining('Target B'), findsNothing);
    await tester.tap(find.text(store.t['confirm']!).last);
    await tester.pumpAndSettle();
    expect((await running).outcome, BackupOutcome.succeeded);
    expect(store.boards.any((board) => board.id == 'source-a'), isFalse);
    expect(store.tasks.map((task) => task.boardId).toSet(), {targetA});
    expect(store.activeBoardId, targetB);
    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
  });
}
