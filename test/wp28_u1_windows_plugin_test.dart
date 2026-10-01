import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
// Real locked FFI implementation, isolated from the user profile and from
// Credential Manager by useBackwardCompatibility=false.
// ignore: depend_on_referenced_packages
import 'package:flutter_secure_storage_windows/flutter_secure_storage_windows.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:matrixflow_native/services/windows_data_upgrade.dart';

import 'wp28_u1_support.dart';

class _IsolatedSupport extends PathProviderPlatform {
  final String path;
  _IsolatedSupport(this.path);
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

class _NoEncryptedReads extends WindowsUpgradeFiles {
  @override
  Future<Uint8List> read(String path) async {
    if (path.endsWith('.dat') || path.endsWith('.secure')) {
      throw StateError('Upgrade must not decrypt or copy encrypted files');
    }
    return super.read(path);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'real Windows DPAPI source stays intact; reconfiguration writes target',
    () async {
      final fixture = await UpgradeFixture.create();
      final original = PathProviderPlatform.instance;
      const options = {'useBackwardCompatibility': 'false'};
      const key = 'matrixflow-custom-api-key';
      const sourceValue = 'SYNTHETIC_DPAPI_UPGRADE_SOURCE_INVALID';
      const targetValue = 'SYNTHETIC_DPAPI_UPGRADE_RECONFIGURED_INVALID';
      try {
        PathProviderPlatform.instance = _IsolatedSupport(fixture.paths.source);
        final plugin = FlutterSecureStorageWindows();
        await plugin.write(key: key, value: sourceValue, options: options);
        expect(await plugin.read(key: key, options: options), sourceValue);
        final sourceFile = File(
          '${fixture.paths.source}/flutter_secure_storage.dat',
        );
        final encryptedBefore = await sourceFile.readAsBytes();
        await fixture.writeSource(mirrorEnvelope(syntheticSnapshot()));
        final result = await fixture
            .adapter(files: _NoEncryptedReads())
            .prepare();
        expect(result.credentialsNeedSetup, isTrue);
        expect(await sourceFile.readAsBytes(), encryptedBefore);
        PathProviderPlatform.instance = _IsolatedSupport(fixture.paths.current);
        final targetPlugin = FlutterSecureStorageWindows();
        expect(await targetPlugin.read(key: key, options: options), isNull);
        await targetPlugin.write(
          key: key,
          value: targetValue,
          options: options,
        );
        expect(
          await targetPlugin.read(key: key, options: options),
          targetValue,
        );
        expect(await sourceFile.readAsBytes(), encryptedBefore);
      } finally {
        PathProviderPlatform.instance = original;
        await fixture.dispose();
      }
    },
    skip: !Platform.isWindows,
  );
}
