import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/services/windows_data_upgrade.dart';
import 'package:matrixflow_native/storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'wp28_u1_support.dart';

class _FaultFiles extends WindowsUpgradeFiles {
  String? fault;
  final UpgradeFixture fixture;
  final List<String> writes = [];
  _FaultFiles(this.fixture, this.fault);

  @override
  Future<void> write(String path, List<int> bytes) async {
    writes.add(path);
    if (fault == 'write') {
      await super.write(path, bytes.take(9).toList());
      throw const FileSystemException('synthetic failure');
    }
    await super.write(path, bytes);
    if (fault == 'profileRace') {
      await fixture.writeTarget('{}');
    }
    if (fault == 'sourceRace') {
      await fixture.writeSource({'flutter.matrixflow-tasks': '[]'});
    }
  }

  @override
  Future<Uint8List> read(String path) async {
    if (fault == 'verify' && path.contains('.wp28-u1-')) {
      return Uint8List.fromList(utf8.encode('{}'));
    }
    return super.read(path);
  }

  @override
  Future<void> publish(String staged, String target) async {
    if (fault == 'beforeCommit') throw const FileSystemException('interrupted');
    if (fault == 'commitRace') await fixture.writeTarget('{}');
    if (fault == 'badCommitRace') {
      await fixture.writeTarget('broken synthetic target');
    }
    await super.publish(staged, target);
    if (fault == 'afterCommit') throw const FileSystemException('interrupted');
  }

  @override
  Future<void> removeFile(String path) async {
    writes.add(path);
    await super.removeFile(path);
  }
}

class _AliasFiles extends WindowsUpgradeFiles {
  final String aliased;
  final bool link;
  _AliasFiles(this.aliased, {this.link = false});

  @override
  Future<FileSystemEntityType> type(String path) async =>
      path == aliased && link ? FileSystemEntityType.link : super.type(path);

  @override
  Future<String> canonicalDirectory(String path) async =>
      path == aliased ? '$path-other-profile' : super.canonicalDirectory(path);
}

class _Credential implements CredentialStore {
  String? value;
  bool fail = false;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async {
    if (fail) throw StateError('synthetic failure');
    this.value = value;
  }

  @override
  Future<void> delete() async {
    value = null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late UpgradeFixture fixture;
  late SharedPreferencesStorePlatform previousPlugin;

  setUp(() async {
    previousPlugin = SharedPreferencesStorePlatform.instance;
    fixture = await UpgradeFixture.create();
  });
  tearDown(() async {
    SharedPreferences.resetStatic();
    SharedPreferencesStorePlatform.instance = previousPlugin;
    await fixture.dispose();
  });

  Future<Store> open({CredentialStore? credential}) async {
    await openIsolatedWindowsPreferences(fixture.paths.current);
    final store = Store(credentialStore: credential);
    await store.init();
    await store.flush();
    addTearDown(store.dispose);
    return store;
  }

  for (final withSchedule in [false, true]) {
    test(
      'legacy mirrors preserve full library and reopen (schedule=$withSchedule)',
      () async {
        await fixture.writeSource(
          mirrorEnvelope(syntheticSnapshot(schedule: withSchedule)),
        );
        final before = await File(fixture.sourceFile).readAsBytes();
        final result = await fixture.adapter().prepare();
        expect(result.status, WindowsUpgradeStatus.migrated);
        expect(await File(fixture.targetFile).readAsBytes(), before);
        final first = await open();
        expect(first.hasStartupRecovery, isFalse);
        expect(first.tasks.single.id, 'synthetic-task');
        expect(first.tasks.single.subtasks.single.id, 'synthetic-subtask');
        expect(first.tasks.single.plannedDate, 1790812800000);
        expect(first.boards.single.id, 'synthetic-board');
        expect(first.aiConfig.model, 'synthetic-model');
        expect(first.hasSeenOnboarding, isTrue);
        expect(first.scheduleItems, hasLength(withSchedule ? 1 : 0));
        final second = await open();
        expect(second.tasks.single.plannedDate, first.tasks.single.plannedDate);
        expect(second.scheduleItems, hasLength(withSchedule ? 1 : 0));
        expect(await File(fixture.sourceFile).readAsBytes(), before);
        expect(
          (await fixture.adapter().prepare()).status,
          WindowsUpgradeStatus.currentProfile,
        );
      },
      skip: !Platform.isWindows,
    );
  }

  for (final optionalSchedule in [false, true]) {
    test(
      'real plugin double slots keep pointer authoritative (schedule=$optionalSchedule)',
      () async {
        final prefs = await openIsolatedWindowsPreferences(
          fixture.paths.source,
        );
        final protocol = SaveProtocol(prefs);
        await protocol.commit(syntheticSnapshot(schedule: optionalSchedule));
        await protocol.commit(syntheticSnapshot(schedule: optionalSchedule));
        await prefs.setString('matrixflow-tasks', '[]');
        // A stale optional mirror must never fill an older committed slot.
        if (!optionalSchedule) {
          await prefs.setString('matrixflow-schedule', 'bad stale mirror');
        }
        final before = await File(fixture.sourceFile).readAsBytes();
        expect((await fixture.adapter().prepare()).canOpen, isTrue);
        final store = await open();
        expect(store.hasStartupRecovery, isFalse);
        expect(store.tasks.single.id, 'synthetic-task');
        expect(store.scheduleItems, hasLength(optionalSchedule ? 1 : 0));
        expect(await File(fixture.sourceFile).readAsBytes(), before);
      },
      skip: !Platform.isWindows,
    );
  }

  test(
    'legal empty source library stays valid and original stays unchanged',
    () async {
      await fixture.writeSource({
        'flutter.matrixflow-tasks': '[]',
        'flutter.matrixflow-boards': '[]',
      });
      final before = await File(fixture.sourceFile).readAsBytes();
      expect(
        (await fixture.adapter().prepare()).status,
        WindowsUpgradeStatus.migrated,
      );
      final store = await open();
      expect(store.tasks, isEmpty);
      expect(store.hasStartupRecovery, isFalse);
      expect(await File(fixture.sourceFile).readAsBytes(), before);
    },
    skip: !Platform.isWindows,
  );

  for (final target in ['{}', '[]', '', '{broken']) {
    test(
      'current target always wins even empty/unreadable: ${target.length}',
      () async {
        await fixture.writeSource(mirrorEnvelope(syntheticSnapshot()));
        await fixture.writeTarget(target);
        final result = await fixture.adapter().prepare();
        expect(
          result.status,
          target == '{}'
              ? WindowsUpgradeStatus.currentProfile
              : WindowsUpgradeStatus.currentUnreadable,
        );
        expect(await File(fixture.targetFile).readAsString(), target);
      },
    );
  }

  test('any current user profile prevents automatic adoption', () async {
    await fixture.writeSource(mirrorEnvelope(syntheticSnapshot()));
    await Directory(fixture.paths.current).create(recursive: true);
    await File(
      '${fixture.paths.current}/flutter_secure_storage.dat',
    ).writeAsString('SYNTHETIC_OPAQUE');
    final result = await fixture.adapter().prepare();
    expect(result.status, WindowsUpgradeStatus.currentProfile);
    expect(await File(fixture.targetFile).exists(), isFalse);
  });

  for (final location in ['source', 'target']) {
    for (final corruption in [
      'pointer',
      'slot',
      'checksum',
      'tasks',
      'schedule',
    ]) {
      test(
        '$location $corruption damage retains bytes and enters Store recovery',
        () async {
          final directory = location == 'source'
              ? fixture.paths.source
              : fixture.paths.current;
          await Directory(directory).create(recursive: true);
          final prefs = await openIsolatedWindowsPreferences(directory);
          await SaveProtocol(prefs).commit(syntheticSnapshot());
          final pointer = prefs.getString(SaveProtocol.pointerKey)!;
          if (corruption == 'pointer') {
            await prefs.setString(SaveProtocol.pointerKey, 'damaged');
          }
          if (corruption == 'slot') {
            await prefs.setString(pointer, '{unfinished');
          }
          if (corruption == 'checksum') {
            final batch =
                jsonDecode(prefs.getString(pointer)!) as Map<String, dynamic>;
            batch['check'] = 0;
            await prefs.setString(pointer, jsonEncode(batch));
          }
          if (corruption == 'tasks' || corruption == 'schedule') {
            final values = syntheticSnapshot();
            values['matrixflow-$corruption'] = corruption == 'tasks'
                ? '[{"id":"unfinished"'
                : '[{"id":"broken"}]';
            await SaveProtocol(prefs).commit(values);
          }
          final rawFile = location == 'source'
              ? fixture.sourceFile
              : fixture.targetFile;
          final before = await File(rawFile).readAsBytes();
          final result = await fixture.adapter().prepare();
          expect(result.canOpen, isTrue);
          final targetBefore = await File(fixture.targetFile).readAsBytes();
          final store = await open();
          expect(store.hasStartupRecovery, isTrue);
          expect(await File(fixture.targetFile).readAsBytes(), targetBefore);
          expect(await File(rawFile).readAsBytes(), before);
        },
        skip: !Platform.isWindows,
      );
    }
  }

  for (final raw in [
    '',
    '[]',
    '{truncated',
    '{"flutter.matrixflow-tasks":null}',
  ]) {
    test(
      'unreadable source envelope blocks default database (${raw.length})',
      () async {
        await File(fixture.sourceFile).writeAsString(raw);
        expect(
          (await fixture.adapter().prepare()).status,
          WindowsUpgradeStatus.sourceUnreadable,
        );
        expect(await File(fixture.targetFile).exists(), isFalse);
        expect(await File(fixture.sourceFile).readAsString(), raw);
        await fixture.writeSource(mirrorEnvelope(syntheticSnapshot()));
        expect((await fixture.adapter().prepare()).canOpen, isTrue);
      },
      skip: !Platform.isWindows,
    );
  }

  for (final fault in ['write', 'verify', 'beforeCommit']) {
    test(
      '$fault failure preserves source, owns cleanup and retries',
      () async {
        await fixture.writeSource(mirrorEnvelope(syntheticSnapshot()));
        final before = await File(fixture.sourceFile).readAsBytes();
        final files = _FaultFiles(fixture, fault);
        expect(
          (await fixture.adapter(files: files).prepare()).status,
          WindowsUpgradeStatus.failed,
        );
        expect(await File(fixture.targetFile).exists(), isFalse);
        expect(await File(fixture.sourceFile).readAsBytes(), before);
        expect(
          files.writes.every((path) => path.contains('.wp28-u1-')),
          isTrue,
        );
        final company = Directory(fixture.paths.stagingParent);
        expect(
          (await company.list().toList()).where(
            (entry) => entry.path.contains('.wp28-u1-'),
          ),
          isEmpty,
        );
        files.fault = null;
        expect(
          (await fixture.adapter(files: files).prepare()).status,
          WindowsUpgradeStatus.migrated,
        );
      },
      skip: !Platform.isWindows,
    );
  }

  test(
    'interruption after commit is detected and retry never overwrites',
    () async {
      await fixture.writeSource(mirrorEnvelope(syntheticSnapshot()));
      final result = await fixture
          .adapter(files: _FaultFiles(fixture, 'afterCommit'))
          .prepare();
      expect(result.status, WindowsUpgradeStatus.currentProfile);
      final committed = await File(fixture.targetFile).readAsBytes();
      expect(
        (await fixture.adapter().prepare()).status,
        WindowsUpgradeStatus.currentProfile,
      );
      expect(await File(fixture.targetFile).readAsBytes(), committed);
    },
    skip: !Platform.isWindows,
  );

  for (final fault in ['profileRace', 'commitRace', 'badCommitRace']) {
    test('$fault never overwrites a racing target', () async {
      await fixture.writeSource(mirrorEnvelope(syntheticSnapshot()));
      final before = await File(fixture.sourceFile).readAsBytes();
      final result = await fixture
          .adapter(files: _FaultFiles(fixture, fault))
          .prepare();
      expect(
        result.status,
        fault == 'badCommitRace'
            ? WindowsUpgradeStatus.currentUnreadable
            : WindowsUpgradeStatus.currentProfile,
      );
      expect(
        await File(fixture.targetFile).readAsString(),
        fault == 'badCommitRace' ? 'broken synthetic target' : '{}',
      );
      expect(await File(fixture.sourceFile).readAsBytes(), before);
    }, skip: !Platform.isWindows);
  }

  test('source changes during preparation block publication', () async {
    await fixture.writeSource(mirrorEnvelope(syntheticSnapshot()));
    expect(
      (await fixture
              .adapter(files: _FaultFiles(fixture, 'sourceRace'))
              .prepare())
          .canOpen,
      isFalse,
    );
    expect(await File(fixture.targetFile).exists(), isFalse);
  });

  for (final location in ['source', 'current', 'sourceFile']) {
    for (final link in [true, false]) {
      test('reject $location ${link ? 'link' : 'canonical alias'}', () async {
        await fixture.writeSource(mirrorEnvelope(syntheticSnapshot()));
        await Directory(fixture.paths.current).create(recursive: true);
        final path = switch (location) {
          'source' => fixture.paths.source,
          'current' => fixture.paths.current,
          _ => fixture.sourceFile,
        };
        final before = await File(fixture.sourceFile).readAsBytes();
        expect(
          (await fixture
                  .adapter(files: _AliasFiles(path, link: link))
                  .prepare())
              .canOpen,
          isFalse,
        );
        expect(await File(fixture.targetFile).exists(), isFalse);
        expect(await File(fixture.sourceFile).readAsBytes(), before);
      });
    }
  }

  test('relative and traversing roots are rejected', () async {
    for (final root in ['relative', '${fixture.root.path}/../other']) {
      final adapter = WindowsDataUpgrade(
        paths: () async => WindowsUpgradePaths(root),
      );
      expect((await adapter.prepare()).canOpen, isFalse);
    }
  });

  test(
    'opaque encrypted credentials are retained and notice survives restart',
    () async {
      await fixture.writeSource(mirrorEnvelope(syntheticSnapshot()));
      final credentialFile = File(
        '${fixture.paths.source}/flutter_secure_storage.dat',
      );
      final oldSecureFile = File('${fixture.paths.source}/synthetic.secure');
      final bytes = Uint8List.fromList([0, 1, 2, 255, 9]);
      await credentialFile.writeAsBytes(bytes);
      await oldSecureFile.writeAsBytes(bytes);
      final before = await File(fixture.sourceFile).readAsBytes();
      final first = await fixture.adapter().prepare();
      expect(first.credentialsNeedSetup, isTrue);
      expect(await credentialFile.readAsBytes(), bytes);
      expect(await oldSecureFile.readAsBytes(), bytes);
      expect(
        await File(
          '${fixture.paths.current}/flutter_secure_storage.dat',
        ).exists(),
        isFalse,
      );
      expect((await fixture.adapter().prepare()).credentialsNeedSetup, isTrue);
      expect(await File(fixture.sourceFile).readAsBytes(), before);
    },
    skip: !Platform.isWindows,
  );

  test(
    'plaintext credential migration still gates secure write/readback and scrub',
    () async {
      const key = 'SYNTHETIC_UPGRADE_INVALID';
      final source = mirrorEnvelope(syntheticSnapshot());
      source['flutter.matrixflow-config'] = '{"customApiKey":"$key"}';
      await fixture.writeSource(source);
      final before = await File(fixture.sourceFile).readAsBytes();
      expect((await fixture.adapter().prepare()).canOpen, isTrue);
      final credential = _Credential()..fail = true;
      final store = await open(credential: credential);
      expect(store.credentialError, isNotNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('matrixflow-config'), contains(key));
      credential.fail = false;
      expect(await store.retryCredential(), isTrue);
      expect((await store.retrySave()).success, isTrue);
      expect(credential.value, key);
      expect(prefs.getString('matrixflow-config'), isNot(contains(key)));
      expect(await File(fixture.sourceFile).readAsBytes(), before);
    },
    skip: !Platform.isWindows,
  );

  test(
    'read-only protocol validation matches load and ignores inactive damage',
    () async {
      final prefs = await openIsolatedWindowsPreferences(fixture.paths.source);
      await SaveProtocol(prefs).commit(syntheticSnapshot());
      await prefs.setString('matrixflow-save-b', '{unfinished');
      final envelope = WindowsDataUpgrade.decodePreferences(
        await File(fixture.sourceFile).readAsBytes(),
      );
      final readOnly = SaveProtocol.readCommitted(
        (key) => envelope['flutter.$key'],
      );
      expect(readOnly!.values, SaveProtocol(prefs).load()!.values);
      expect(
        (await fixture.adapter().prepare()).protocolNeedsRecovery,
        isFalse,
      );
      final store = await open();
      expect(store.hasStartupRecovery, isFalse);
      expect(store.tasks, hasLength(1));
    },
    skip: !Platform.isWindows,
  );

  test(
    'uncommitted first slot falls back to legacy mirrors unchanged',
    () async {
      final prefs = await openIsolatedWindowsPreferences(fixture.paths.source);
      for (final entry in syntheticSnapshot(schedule: false).entries) {
        if (entry.key == 'matrixflow-has-seen-onboarding') {
          await prefs.setBool(entry.key, entry.value == 'true');
        } else {
          await prefs.setString(entry.key, entry.value);
        }
      }
      await prefs.setString('matrixflow-save-a', '{unfinished');
      expect(
        (await fixture.adapter().prepare()).protocolNeedsRecovery,
        isFalse,
      );
      expect((await open()).tasks.single.id, 'synthetic-task');
    },
    skip: !Platform.isWindows,
  );
}
