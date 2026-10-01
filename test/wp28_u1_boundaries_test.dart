import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:path/path.dart' as p;
import 'package:matrixflow_native/services/windows_data_upgrade.dart';

import 'wp28_u1_support.dart';

class _WrongStage extends WindowsUpgradeFiles {
  final String path;
  _WrongStage(this.path);
  @override
  Future<String> createStage(String parent) async => path;
}

class _ReadFailure extends WindowsUpgradeFiles {
  final String source;
  _ReadFailure(this.source);
  @override
  Future<Uint8List> read(String path) async {
    if (path == source) {
      throw const FileSystemException('synthetic read failure');
    }
    return super.read(path);
  }
}

class _CleanupFailure extends WindowsUpgradeFiles {
  @override
  Future<void> removeDirectory(String path) async {
    throw const FileSystemException('synthetic cleanup failure');
  }
}

class _CredentialAlias extends WindowsUpgradeFiles {
  final String path;
  _CredentialAlias(this.path);
  @override
  Future<String> canonicalDirectory(String path) async =>
      p.equals(path, this.path)
      ? '$path-other-profile'
      : super.canonicalDirectory(path);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late UpgradeFixture fixture;
  setUp(() async {
    fixture = await UpgradeFixture.create();
  });
  tearDown(() async {
    await fixture.dispose();
  });

  test(
    'missing old library does not create a database in preparation',
    () async {
      expect(
        (await fixture.adapter().prepare()).status,
        WindowsUpgradeStatus.noLegacyData,
      );
      expect(await File(fixture.targetFile).exists(), isFalse);
    },
  );

  test('out-of-range staging path cannot write or clean the source', () async {
    await fixture.writeSource(mirrorEnvelope(syntheticSnapshot()));
    final before = await File(fixture.sourceFile).readAsBytes();
    expect(
      (await fixture
              .adapter(files: _WrongStage(fixture.paths.source))
              .prepare())
          .canOpen,
      isFalse,
    );
    expect(await File(fixture.sourceFile).readAsBytes(), before);
    expect(await File(fixture.targetFile).exists(), isFalse);
  });

  test(
    'source read failure blocks startup without creating defaults',
    () async {
      await fixture.writeSource(mirrorEnvelope(syntheticSnapshot()));
      final before = await File(fixture.sourceFile).readAsBytes();
      expect(
        (await fixture
                .adapter(files: _ReadFailure(fixture.sourceFile))
                .prepare())
            .canOpen,
        isFalse,
      );
      expect(await File(fixture.sourceFile).readAsBytes(), before);
      expect(await File(fixture.targetFile).exists(), isFalse);
    },
  );

  test('current profile wins before attempting a failed old read', () async {
    await fixture.writeSource(mirrorEnvelope(syntheticSnapshot()));
    await fixture.writeTarget('{}');
    expect(
      (await fixture.adapter(files: _ReadFailure(fixture.sourceFile)).prepare())
          .status,
      WindowsUpgradeStatus.currentProfile,
    );
    expect(await File(fixture.targetFile).readAsString(), '{}');
  });

  test(
    'abandoned stages and unknown files are never swept',
    () async {
      await fixture.writeSource(mirrorEnvelope(syntheticSnapshot()));
      final abandoned = Directory(
        '${fixture.paths.stagingParent}/.wp28-u1-abandoned',
      );
      await abandoned.create(recursive: true);
      final unknown = File('${abandoned.path}/shared_preferences.json');
      await unknown.writeAsString('SYNTHETIC_PRESERVE_UNKNOWN');
      expect(
        (await fixture.adapter().prepare()).status,
        WindowsUpgradeStatus.migrated,
      );
      expect(await unknown.readAsString(), 'SYNTHETIC_PRESERVE_UNKNOWN');
    },
    skip: !Platform.isWindows,
  );

  test(
    'cleanup failure cannot roll back a committed library or block restart',
    () async {
      await fixture.writeSource(mirrorEnvelope(syntheticSnapshot()));
      final before = await File(fixture.sourceFile).readAsBytes();
      expect(
        (await fixture.adapter(files: _CleanupFailure()).prepare()).status,
        WindowsUpgradeStatus.migrated,
      );
      expect(
        (await fixture.adapter().prepare()).status,
        WindowsUpgradeStatus.currentProfile,
      );
      expect(await File(fixture.sourceFile).readAsBytes(), before);
    },
    skip: !Platform.isWindows,
  );

  test(
    'current credential file aliases are rejected before plugin access',
    () async {
      await fixture.writeTarget('{}');
      final credential = File(
        '${fixture.paths.current}/flutter_secure_storage.dat',
      );
      await credential.writeAsString('SYNTHETIC_OPAQUE');
      expect(
        (await fixture
                .adapter(files: _CredentialAlias(credential.path))
                .prepare())
            .canOpen,
        isFalse,
      );
      expect(await credential.readAsString(), 'SYNTHETIC_OPAQUE');
      expect(await File(fixture.targetFile).readAsString(), '{}');
    },
  );
}
