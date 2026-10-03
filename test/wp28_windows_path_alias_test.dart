import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/services/windows_data_upgrade.dart';

import 'wp28_u1_support.dart';

String _shortPath(String path) => using((arena) {
  final getShortPath = DynamicLibrary.open('kernel32.dll')
      .lookupFunction<
        Uint32 Function(Pointer<Utf16>, Pointer<Utf16>, Uint32),
        int Function(Pointer<Utf16>, Pointer<Utf16>, int)
      >('GetShortPathNameW');
  final output = arena<Uint16>(32768).cast<Utf16>();
  final length = getShortPath(
    path.toNativeUtf16(allocator: arena),
    output,
    32768,
  );
  if (length == 0 || length >= 32768) {
    throw StateError('Unable to obtain an isolated Windows short path');
  }
  return output.toDartString(length: length);
});

void main() {
  test(
    'real 8.3 roaming alias preserves migration and current-library priority',
    () async {
      final fixture = await UpgradeFixture.create();
      try {
        final canonical = await fixture.root.resolveSymbolicLinks();
        final alias = _shortPath(canonical);
        if (alias.toLowerCase() == canonical.toLowerCase()) {
          markTestSkipped('This volume does not generate 8.3 directory names');
          return;
        }
        expect(await Directory(alias).resolveSymbolicLinks(), canonical);
        await fixture.writeSource(mirrorEnvelope(syntheticSnapshot()));
        final before = await File(fixture.sourceFile).readAsBytes();
        final adapter = WindowsDataUpgrade(
          paths: () async => WindowsUpgradePaths(alias),
        );
        expect((await adapter.prepare()).status, WindowsUpgradeStatus.migrated);
        expect(await File(fixture.sourceFile).readAsBytes(), before);
        expect(await File(fixture.targetFile).readAsBytes(), before);
        await fixture.writeSource({'flutter.matrixflow-tasks': '[]'});
        expect(
          (await adapter.prepare()).status,
          WindowsUpgradeStatus.currentProfile,
        );
        expect(await File(fixture.targetFile).readAsBytes(), before);
      } finally {
        await fixture.dispose();
      }
    },
    skip: !Platform.isWindows,
  );

  test(
    'real Windows directory junction cannot redirect an upgrade',
    () async {
      final fixture = await UpgradeFixture.create();
      try {
        await fixture.writeSource(mirrorEnvelope(syntheticSnapshot()));
        final canonical = await fixture.root.resolveSymbolicLinks();
        final destination = Directory('$canonical\\isolated-junction-target');
        await destination.create();
        final marker = File('${destination.path}/shared_preferences.json');
        await marker.writeAsString(jsonEncode({'synthetic': 'preserve'}));
        final before = await marker.readAsBytes();
        await Directory(fixture.paths.stagingParent).create();
        final junction = await Process.run('cmd.exe', [
          '/d',
          '/c',
          'mklink',
          '/J',
          fixture.paths.current,
          destination.path,
        ]);
        expect(
          junction.exitCode,
          0,
          reason: '${junction.stdout}${junction.stderr}',
        );
        expect(
          (await fixture.adapter().prepare()).status,
          WindowsUpgradeStatus.failed,
        );
        expect(await marker.readAsBytes(), before);
        // Delete only the junction, never traverse its target during cleanup.
        await Link(fixture.paths.current).delete();
        expect(await marker.readAsBytes(), before);
      } finally {
        await fixture.dispose();
      }
    },
    skip: !Platform.isWindows,
  );
}
