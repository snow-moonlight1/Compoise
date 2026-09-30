import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/l10n.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/schedule_item.dart';
import 'package:matrixflow_native/screens/settings_backup_flow.dart';
import 'package:matrixflow_native/storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _secret = 'SYNTHETIC_PRIVATE_KEY';
const _privateTitle = 'SYNTHETIC_PRIVATE_TASK';
const _start = 1790701200000;
final _board = Board(id: 'b', name: 'Board', createdAt: 1);
final _task = Task(
  id: 't',
  boardId: 'b',
  title: _privateTitle,
  quadrant: 2,
  createdAt: 1,
);
ScheduleItem _block(String id, {int delta = 0}) => ScheduleItem.timeBlock(
  id: id,
  taskId: 't',
  startAt: _start + delta,
  endAt: _start + delta + 1,
  timeZoneId: 'Asia/Shanghai',
);
ScheduleItem _event(String id) => ScheduleItem.event(
  id: id,
  title: 'SYNTHETIC_PRIVATE_EVENT',
  boardId: 'b',
  startAt: _start,
  endAt: _start + 2,
  timeZoneId: 'UTC',
);
Map<String, dynamic> _payload({List<ScheduleItem>? items}) => {
  'version': 3,
  'boards': [_board.toJson()],
  'tasks': [_task.toJson()],
  'scheduleItems': (items ?? [_block('incoming'), _event('meeting')])
      .map((s) => s.toJson())
      .toList(),
  'aiConfig': {'customApiKey': _secret},
};

class _Credentials implements CredentialStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async => this.value = value;
  @override
  Future<void> delete() async => value = null;
}

class _Picker extends FilePicker {
  _Picker({this.payload, this.cancelSave = false});
  final Map<String, dynamic>? payload;
  final bool cancelSave;
  Completer<FilePickerResult?>? pickGate;
  int picked = 0;
  int saved = 0;
  Uint8List? savedBytes;
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
  }) async {
    picked++;
    if (pickGate != null) return pickGate!.future;
    if (payload == null) return null;
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(payload)));
    return FilePickerResult([
      PlatformFile(name: 'synthetic.json', size: bytes.length, bytes: bytes),
    ]);
  }

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    saved++;
    savedBytes = bytes;
    return cancelSave ? null : 'synthetic.json';
  }
}

Future<Store> _seed(Language language, {SaveWrite? writer}) async {
  SharedPreferences.setMockInitialValues({
    'matrixflow-boards': jsonEncode([_board.toJson()]),
    'matrixflow-tasks': jsonEncode([_task.toJson()]),
    'matrixflow-settings': jsonEncode(AppSettings(language: language).toJson()),
    SaveProtocol.scheduleKey: jsonEncode([
      _block('same').toJson(),
      _block('conflict').toJson(),
      _event('local').toJson(),
    ]),
  });
  final store = Store(saveWriter: writer, credentialStore: _Credentials());
  await store.init();
  await store.flush();
  return store;
}

String _state(Store store) => jsonEncode({
  'boards': store.boards.map((b) => b.toJson()).toList(),
  'tasks': store.tasks.map((t) => t.toJson()).toList(),
  'schedule': store.scheduleItems.map((s) => s.toJson()).toList(),
});
Future<BuildContext> _host(WidgetTester tester, {bool narrow = false}) async {
  if (narrow) {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }
  late BuildContext context;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (value) {
          context = value;
          return const Scaffold(body: SizedBox.shrink());
        },
      ),
    ),
  );
  return context;
}

void _privateDataAbsent(WidgetTester tester) {
  expect(find.textContaining(_secret), findsNothing);
  expect(find.textContaining(_privateTitle), findsNothing);
  expect(find.textContaining('SYNTHETIC_PRIVATE_EVENT'), findsNothing);
}

Future<void> _mode(WidgetTester tester, Store store, String key) async {
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text(store.t[key]!));
  await tester.tap(find.text(store.t[key]!));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FilePicker.platform = _Picker());

  for (final language in Language.values) {
    testWidgets(
      '$language v3 export explains compatibility and writes all schedules',
      (tester) async {
        final store = await _seed(language);
        final picker = _Picker();
        FilePicker.platform = picker;
        final context = await _host(tester);
        var writes = 0;
        final flow = SettingsBackupFlow(
          onBusyChanged: (_) {},
          writeFile: (_, __) async => writes++,
        );
        final running = flow.export(context, store);
        await tester.pumpAndSettle();
        expect(
          find.textContaining(store.t['backupVersionInfo']!),
          findsOneWidget,
        );
        expect(picker.saved, 0);
        _privateDataAbsent(tester);
        await tester.tap(find.text(store.t['exportWithoutCredential']!));
        await tester.pumpAndSettle();
        expect((await running).outcome, BackupOutcome.succeeded);
        final json = jsonDecode(utf8.decode(picker.savedBytes!));
        expect(json['version'], 3);
        expect(json['scheduleItems'], hasLength(3));
        expect(json['aiConfig'].containsKey('customApiKey'), isFalse);
        expect(writes, 1);
        expect(flow.busy, isFalse);
        await tester.pumpWidget(const SizedBox.shrink());
        store.dispose();
      },
    );

    testWidgets(
      '$language v3 overwrite shows four schedule counts before cancel',
      (tester) async {
        final store = await _seed(language);
        final before = _state(store);
        FilePicker.platform = _Picker(payload: _payload());
        final context = await _host(tester, narrow: true);
        final flow = SettingsBackupFlow(onBusyChanged: (_) {});
        final running = flow.importBackup(context, store, syncAiFields: () {});
        await _mode(tester, store, 'importModeOverwrite');
        expect(
          find.textContaining(
            store.t['backupImportVersion']!.replaceAll('{version}', '3'),
          ),
          findsOneWidget,
        );
        for (final entry in {
          'importScheduleAdded': 2,
          'importScheduleSkipped': 0,
          'importScheduleConflicts': 0,
          'importScheduleRemoved': 3,
        }.entries) {
          expect(
            find.textContaining('${store.t[entry.key]}: ${entry.value}'),
            findsOneWidget,
          );
        }
        _privateDataAbsent(tester);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text(store.t['cancel']!));
        await tester.pumpAndSettle();
        expect((await running).outcome, BackupOutcome.cancelled);
        expect(_state(store), before);
        await tester.pumpWidget(const SizedBox.shrink());
        store.dispose();
      },
    );

    testWidgets('$language schedule-only conflict blocks confirmation', (
      tester,
    ) async {
      final store = await _seed(language);
      final before = _state(store);
      FilePicker.platform = _Picker(
        payload: _payload(
          items: [_block('same'), _block('conflict', delta: 1), _event('new')],
        ),
      );
      final context = await _host(tester);
      final flow = SettingsBackupFlow(onBusyChanged: (_) {});
      final running = flow.importBackup(context, store, syncAiFields: () {});
      await _mode(tester, store, 'importModeMerge');
      for (final entry in {
        'importAddedTasks': 0,
        'importScheduleAdded': 1,
        'importScheduleSkipped': 1,
        'importScheduleConflicts': 1,
        'importScheduleRemoved': 0,
      }.entries) {
        expect(
          find.textContaining('${store.t[entry.key]}: ${entry.value}'),
          findsOneWidget,
        );
      }
      expect(
        find.textContaining(store.t['importScheduleConflictBlocked']!),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, store.t['confirm']!),
            )
            .onPressed,
        isNull,
      );
      // Merge does not import settings or credentials.
      expect(find.text(store.t['importReplaceCredential']!), findsNothing);
      _privateDataAbsent(tester);
      await tester.tap(find.text(store.t['cancel']!));
      await tester.pumpAndSettle();
      expect((await running).outcome, BackupOutcome.cancelled);
      expect(_state(store), before);
      await tester.pumpWidget(const SizedBox.shrink());
      store.dispose();
    });

    testWidgets(
      '$language unknown field names and values stay out of the preview',
      (tester) async {
        final store = await _seed(language);
        final payload = _payload();
        payload[_secret] = _privateTitle;
        (payload['boards'] as List).first[_secret] = _privateTitle;
        (payload['tasks'] as List).first[_secret] = _privateTitle;
        (payload['scheduleItems'] as List).first[_secret] = _privateTitle;
        (payload['aiConfig'] as Map)[_secret] = _privateTitle;
        payload['settings'] = {'fontSize': _secret, _secret: _privateTitle};
        FilePicker.platform = _Picker(payload: payload);
        final context = await _host(tester);
        final flow = SettingsBackupFlow(onBusyChanged: (_) {});
        final running = flow.importBackup(context, store, syncAiFields: () {});
        await _mode(tester, store, 'importModeOverwrite');
        expect(
          find.textContaining(store.t['importWarningUnknown']!),
          findsOneWidget,
        );
        expect(
          find.textContaining(store.t['importWarningNormalized']!),
          findsOneWidget,
        );
        _privateDataAbsent(tester);
        await tester.tap(find.text(store.t['cancel']!));
        await tester.pumpAndSettle();
        expect((await running).outcome, BackupOutcome.cancelled);
        await tester.pumpWidget(const SizedBox.shrink());
        store.dispose();
      },
    );

    testWidgets('$language v3 merge restores schedules without new tasks', (
      tester,
    ) async {
      final store = await _seed(language);
      FilePicker.platform = _Picker(payload: _payload());
      final context = await _host(tester);
      final flow = SettingsBackupFlow(onBusyChanged: (_) {});
      final running = flow.importBackup(context, store, syncAiFields: () {});
      await _mode(tester, store, 'importModeMerge');
      expect(
        find.textContaining('${store.t['importAddedTasks']}: 0'),
        findsOneWidget,
      );
      expect(
        find.textContaining('${store.t['importScheduleAdded']}: 2'),
        findsOneWidget,
      );
      await tester.tap(find.text(store.t['confirm']!));
      await tester.pumpAndSettle();
      expect((await running).outcome, BackupOutcome.succeeded);
      expect(store.scheduleItems.map((item) => item.id).toSet(), {
        'same',
        'conflict',
        'local',
        'incoming',
        'meeting',
      });
      await tester.pumpWidget(const SizedBox.shrink());
      store.dispose();
    });

    testWidgets('$language legacy merge preserves local schedules', (
      tester,
    ) async {
      final store = await _seed(language);
      final scheduleBefore = store.scheduleItems
          .map((s) => s.toJson())
          .toList();
      FilePicker.platform = _Picker(payload: {..._payload(), 'version': 2});
      final context = await _host(tester);
      final flow = SettingsBackupFlow(onBusyChanged: (_) {});
      final running = flow.importBackup(context, store, syncAiFields: () {});
      await _mode(tester, store, 'importModeMerge');
      expect(
        find.textContaining('${store.t['importScheduleAdded']}: 0'),
        findsOneWidget,
      );
      expect(
        find.textContaining('${store.t['importScheduleRemoved']}: 0'),
        findsOneWidget,
      );
      expect(
        find.textContaining(store.t['importScheduleLegacyIgnored']!),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          store.t['importScheduleLegacyOverwrite']!.replaceAll('{n}', '3'),
        ),
        findsNothing,
      );
      await tester.tap(find.text(store.t['confirm']!));
      await tester.pumpAndSettle();
      final result = await running;
      expect(result.outcome, BackupOutcome.succeeded);
      expect(
        result.message,
        contains(store.t['importScheduleLegacyRestoredNone']),
      );
      expect(
        store.scheduleItems.map((s) => s.toJson()).toList(),
        scheduleBefore,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      store.dispose();
    });

    for (final version in [null, 1, 2]) {
      testWidgets(
        '$language legacy $version overwrite warns deletion and ignores hidden fields',
        (tester) async {
          final store = await _seed(language);
          final payload = _payload();
          if (version == null) {
            payload.remove('version');
          } else {
            payload['version'] = version;
          }
          payload['scheduleItems'] = 'SYNTHETIC_PRIVATE_EVENT';
          for (var i = 0; i < 12; i++) {
            payload['unknown$i'] = _secret;
            (payload['tasks'] as List).add({
              ..._task.toJson(),
              'id': 'legacy-task-$i',
              'unknown': _secret,
            });
          }
          expect(
            store.previewImport(payload, 'overwrite').warnings.length,
            greaterThan(8),
          );
          FilePicker.platform = _Picker(payload: payload);
          final context = await _host(tester);
          final flow = SettingsBackupFlow(onBusyChanged: (_) {});
          final running = flow.importBackup(
            context,
            store,
            syncAiFields: () {},
          );
          await _mode(tester, store, 'importModeOverwrite');
          expect(
            find.textContaining(
              store.t['importScheduleLegacyOverwrite']!.replaceAll('{n}', '3'),
            ),
            findsOneWidget,
          );
          expect(
            find.textContaining(store.t['importScheduleLegacyIgnored']!),
            findsOneWidget,
          );
          expect(
            find.textContaining('${store.t['importScheduleAdded']}: 0'),
            findsOneWidget,
          );
          _privateDataAbsent(tester);
          await tester.tap(find.text(store.t['importKeepCredential']!));
          await tester.pumpAndSettle();
          final result = await running;
          expect(result.outcome, BackupOutcome.succeeded);
          expect(
            result.message,
            contains(store.t['importScheduleLegacyRestoredNone']),
          );
          expect(result.message, isNot(contains(_secret)));
          expect(store.scheduleItems, isEmpty);
          await tester.pumpWidget(const SizedBox.shrink());
          store.dispose();
        },
      );
    }

    testWidgets(
      '$language invalid schedules and versions give safe localized errors',
      (tester) async {
        final store = await _seed(language);
        final context = await _host(tester);
        final before = _state(store);
        final cases = <(Map<String, dynamic>, String)>[
          ({..._payload(), 'version': 99}, 'backupUnsupportedVersion'),
          ({..._payload(), 'version': _secret}, 'backupUnsupportedVersion'),
          ({..._payload(), 'scheduleItems': null}, 'importScheduleInvalid'),
          (
            _payload(items: [_block('s'), _block('s')]),
            'importScheduleInvalid',
          ),
          (
            {
              ..._payload(),
              'scheduleItems': [
                {..._block('s').toJson(), 'taskId': 'gone'},
              ],
            },
            'importScheduleInvalid',
          ),
          (
            {
              ..._payload(),
              'scheduleItems': [
                {..._event('e').toJson(), 'boardId': 'gone'},
              ],
            },
            'importScheduleInvalid',
          ),
          (
            {
              ..._payload(),
              'scheduleItems': [
                {..._block('s').toJson(), 'timeZoneId': _secret},
              ],
            },
            'importScheduleInvalid',
          ),
          (
            {
              ..._payload(),
              'scheduleItems': [
                {..._block('s').toJson(), 'endAt': _start},
              ],
            },
            'importScheduleInvalid',
          ),
        ];
        for (final entry in cases) {
          FilePicker.platform = _Picker(payload: entry.$1);
          final flow = SettingsBackupFlow(onBusyChanged: (_) {});
          final running = flow.importBackup(
            context,
            store,
            syncAiFields: () {},
          );
          await _mode(tester, store, 'importModeOverwrite');
          final result = await running;
          expect(result.outcome, BackupOutcome.failed);
          expect(result.message, store.t[entry.$2]);
          expect(result.message, isNot(contains(_secret)));
          expect(_state(store), before);
          expect(find.byType(AlertDialog), findsNothing);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        store.dispose();
      },
    );
  }

  testWidgets(
    'file cancel, export failure and flow reentry never claim success',
    (tester) async {
      final store = await _seed(Language.en);
      final context = await _host(tester);
      final picker = _Picker(cancelSave: true);
      FilePicker.platform = picker;
      var writes = 0;
      final busy = <bool>[];
      final flow = SettingsBackupFlow(
        onBusyChanged: busy.add,
        writeFile: (_, __) async {
          writes++;
          throw StateError(_secret);
        },
      );
      final exporting = flow.export(context, store);
      await tester.pumpAndSettle();
      expect(
        (await flow.importBackup(context, store, syncAiFields: () {})).outcome,
        BackupOutcome.cancelled,
      );
      expect(picker.picked, 0);
      await tester.tap(find.text(store.t['exportWithoutCredential']!));
      await tester.pumpAndSettle();
      expect((await exporting).outcome, BackupOutcome.cancelled);
      expect(writes, 0);
      FilePicker.platform = _Picker();
      final failing = flow.export(context, store);
      await tester.pumpAndSettle();
      await tester.tap(find.text(store.t['exportWithoutCredential']!));
      await tester.pumpAndSettle();
      expect((await failing).message, store.t['exportError']);
      expect(writes, 1);
      expect(busy, [true, false, true, false]);
      expect(
        (await flow.importBackup(context, store, syncAiFields: () {})).outcome,
        BackupOutcome.cancelled,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      store.dispose();
    },
  );

  testWidgets('unmounted host and closed flow stop a pending picker', (
    tester,
  ) async {
    final store = await _seed(Language.en);
    final context = await _host(tester);
    final picker = _Picker()..pickGate = Completer<FilePickerResult?>();
    FilePicker.platform = picker;
    final busy = <bool>[];
    var synced = 0;
    final flow = SettingsBackupFlow(onBusyChanged: busy.add);
    final running = flow.importBackup(
      context,
      store,
      syncAiFields: () => synced++,
    );
    await tester.pump();
    flow.close();
    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
    picker.pickGate!.complete(
      FilePickerResult([
        PlatformFile(
          name: 'synthetic.json',
          size: 2,
          bytes: Uint8List.fromList([123, 125]),
        ),
      ]),
    );
    await tester.pumpAndSettle();
    expect((await running).outcome, BackupOutcome.cancelled);
    expect(synced, 0);
    expect(busy, [true]);
    expect(flow.busy, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed overwrite presents save failure and retains schedule', (
    tester,
  ) async {
    var reject = false;
    final store = await _seed(
      Language.en,
      writer: (key, value) async {
        if (reject && key == SaveProtocol.pointerKey) return false;
        return (await SharedPreferences.getInstance()).setString(key, value);
      },
    );
    final before = _state(store);
    FilePicker.platform = _Picker(payload: _payload());
    final context = await _host(tester);
    final flow = SettingsBackupFlow(onBusyChanged: (_) {});
    final running = flow.importBackup(context, store, syncAiFields: () {});
    await _mode(tester, store, 'importModeOverwrite');
    reject = true;
    await tester.tap(find.text(store.t['importKeepCredential']!));
    await tester.pumpAndSettle();
    final result = await running;
    expect(result.outcome, BackupOutcome.failed);
    expect(result.message, store.t['importSaveError']);
    expect(_state(store), before);
    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
  });

  test(
    'three languages retain v3 compatibility and loss-count placeholders',
    () {
      for (final language in Language.values) {
        final t = dictOf(language);
        expect(t['backupVersionInfo'], contains('v3'));
        expect(t['backupVersionInfo'], contains('v1/v2'));
        expect(t['importWarningLegacy'], contains('v3'));
        expect(t['backupImportVersion'], contains('{version}'));
        expect(t['exportScheduleLossBlocked'], contains('{n}'));
        expect(t['importScheduleLegacyOverwrite'], contains('{n}'));
      }
    },
  );
}
