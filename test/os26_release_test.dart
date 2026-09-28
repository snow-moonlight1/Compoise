import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/l10n.dart';
import 'package:matrixflow_native/models.dart';

/// OS26 keeps the release workflow, the packaging script, the Android release
/// gate and the release identity metadata aligned with the source tree.
void main() {
  String text(String path) =>
      File(path).readAsStringSync().replaceAll('\r\n', '\n');

  late String release;
  late String script;
  late String gradle;
  late String example;
  late String runnerRc;
  late String cmake;
  late String pubspec;
  late String gitignore;

  setUp(() {
    release = text('.github/workflows/release.yml');
    script = text('scripts/build_release.ps1');
    gradle = text('android/app/build.gradle.kts');
    example = text('android/key.properties.example');
    runnerRc = text('windows/runner/Runner.rc');
    cmake = text('windows/CMakeLists.txt');
    pubspec = text('pubspec.yaml');
    gitignore = text('.gitignore');
  });

  test('release workflow keeps least privilege and never inlines secrets', () {
    expect(release.contains('permissions:\n  contents: read'), isTrue);
    expect(release.contains('write-all'), isFalse);
    expect(release.contains('contents: write'), isTrue);
    expect(
      release.indexOf('contents: write'),
      greaterThan(release.indexOf('publish-release:')),
    );
    expect('permissions:\n      contents: write'.allMatches(release).length, 1);

    // Each secret is referenced exactly once: in the step environment, never
    // inside a shell script body.
    for (final secret in [
      'ANDROID_KEYSTORE_BASE64',
      'ANDROID_STORE_PASSWORD',
      'ANDROID_KEY_PASSWORD',
      'ANDROID_KEY_ALIAS',
    ]) {
      expect('secrets.$secret'.allMatches(release).length, 1, reason: secret);
      expect(release.contains('$secret: \${{ secrets.$secret }}'), isTrue);
    }
    expect(release.contains('echo "\${{ secrets.'), isFalse);
    expect(
      release.contains(
        'printf \'%s\' "\$ANDROID_KEYSTORE_BASE64" | base64 --decode',
      ),
      isTrue,
    );
    expect(release.contains('chmod 600'), isTrue);
    expect(release.contains('Values are not printed'), isTrue);

    expect(release.contains('Remove release signing material'), isTrue);
    expect(
      release.contains('rm -f android/key.properties android/app/release.jks'),
      isTrue,
    );
    expect(release.contains('if: always()'), isTrue);
  });

  test('release workflow stages one platform set and discloses signing', () {
    expect(release.contains('concurrency:'), isTrue);
    expect(release.contains('group: release-\${{ github.ref }}'), isTrue);

    expect(release.contains('needs: preflight'), isTrue);
    expect('needs: preflight'.allMatches(release).length, 3);
    expect(release.contains('build-linux:'), isTrue);
    expect(release.contains('needs: [preflight, build-android, build-windows, build-linux]'), isTrue);
    expect(release.contains('Verify tag against pubspec.yaml'), isTrue);
    expect(release.contains('-ValidateOnly'), isTrue);
    expect(release.contains('-ExpectedTag'), isTrue);

    // The Android build still opts into the formal signing gate.
    final androidBuild = release.split('Build Android Release APK').last;
    expect(androidBuild.contains("REQUIRE_RELEASE_SIGNING: 'true'"), isTrue);
    expect(androidBuild.contains('flutter build apk --release'), isTrue);
    expect(
      androidBuild.indexOf("REQUIRE_RELEASE_SIGNING: 'true'"),
      lessThan(androidBuild.indexOf('flutter build apk --release')),
    );
    expect(release.contains('CN=Android Debug'), isTrue);
    expect(release.contains('apksigner'), isTrue);

    expect(
      release.contains('compoise-v\${{ steps.version.outputs.VERSION }}'),
      isTrue,
    );
    expect(release.contains('steps.version.outputs.BUILD'), isTrue);
    expect(
      release.contains('\${ANDROID_SDK_ROOT:-\${ANDROID_HOME:-}}'),
      isTrue,
    );

    expect(release.contains('sha256sum \$artifacts > SHA256SUMS.txt'), isTrue);
    expect(
      release.contains(
        'Refusing to publish: expected exactly one APK and one '
        'Windows ZIP, nothing else.',
      ),
      isTrue,
    );
    expect(release.contains('draft: true'), isTrue);
    expect(release.contains('prerelease: false'), isTrue);
    expect(release.contains('RELEASE_NOTES.md'), isTrue);
    expect(release.contains('not code-signed'), isTrue);
  });

  test('packaging script stages one version and refuses unsigned releases', () {
    expect(
      script.contains("\$StagingDirName = \"compoise-v\$VersionLabel\""),
      isTrue,
    );
    expect(
      script.contains('Remove-Item -Path \$StagingDir -Recurse -Force'),
      isTrue,
    );
    expect(
      script.contains('The staging directory contains an unexpected file:'),
      isTrue,
    );
    expect(script.contains("'SHA256SUMS.txt'"), isTrue);
    expect(script.contains("'RELEASE_MANIFEST.txt'"), isTrue);
    expect(script.contains('Get-FileHash'), isTrue);

    // Checksums come from this run's artifact list, not from a directory glob.
    expect(
      script.contains('foreach (\$Artifact in \$ExpectedArtifacts)'),
      isTrue,
    );
    expect(script.contains('sha256sum *'), isFalse);
    expect(script.contains('\$ChecksumLines = @(Get-ChildItem'), isFalse);

    expect(script.contains('ExpectedTag'), isTrue);
    expect(
      script.contains(
        'Refusing to stage a release whose tag and version disagree',
      ),
      isTrue,
    );
    expect(script.contains('ValidateOnly'), isTrue);
    expect(script.contains('\$env:REQUIRE_RELEASE_SIGNING = \'true\''), isTrue);
    expect(
      script.contains('Refusing to build a debug-signed release APK.'),
      isTrue,
    );
    expect(script.contains('key.properties.example'), isTrue);
    expect(script.contains('apksigner'), isTrue);
    expect(script.contains('CN=Android Debug'), isTrue);
    expect(script.contains('aapt2'), isTrue);
    expect(script.contains("Find-BuildToolsExe 'aapt2'"), isTrue);
    expect(script.contains('dump badging'), isTrue);
    expect(script.contains('versionCode'), isTrue);
    expect(script.contains('FileVersion'), isTrue);
    expect(script.contains('Get-AuthenticodeSignature'), isTrue);
    expect(script.contains('Authenticode is not configured'), isTrue);

    // Secrets are never read back for output.
    expect(script.contains('keyPassword=\$'), isFalse);
    expect(script.contains('storePassword=\$'), isFalse);
    expect(script.contains('Get-Content \$KeyPropertiesPath'), isFalse);
    expect(script.contains('Password values are never read'), isTrue);
  });

  test(
    'key.properties template stays untracked and matches the gradle gate',
    () {
      for (final key in [
        'keyAlias',
        'keyPassword',
        'storePassword',
        'storeFile',
      ]) {
        expect(example.contains('$key='), isTrue, reason: key);
      }
      expect(example.contains('REPLACE_WITH'), isTrue);
      expect(example.contains('PRIVATE KEY'), isFalse);
      expect(gitignore.contains('key.properties\n'), isTrue);
      expect(gitignore.contains('*.jks'), isTrue);
      expect(gitignore.contains('key.properties.example'), isFalse);

      expect(gradle.contains('applicationId = "com.matrixflow.app"'), isTrue);
      expect(
        gradle.contains('namespace = "com.matrixflow.matrixflow_native"'),
        isTrue,
      );
      expect(gradle.contains('verifyFormalReleaseSigning'), isTrue);
      expect(gradle.contains('android/key.properties.example'), isTrue);
      expect(gradle.contains('docs/DEVELOPMENT.md'), isTrue);
      expect(gradle.contains('System.getenv("CI")'), isFalse);
    },
  );

  test('Windows identity metadata and pubspec version agree', () {
    expect(cmake.contains('set(BINARY_NAME "compoise")'), isTrue);
    expect(runnerRc.contains('"ProductName", "Compoise"'), isTrue);
    expect(runnerRc.contains('"OriginalFilename", "compoise.exe"'), isTrue);
    expect(
      runnerRc.contains(
        '"LegalCopyright", "Copyright (C) 2026 Compoise contributors.',
      ),
      isTrue,
    );
    expect(runnerRc.contains('VERSION_AS_NUMBER'), isTrue);

    final versionLine = pubspec
        .split('\n')
        .firstWhere((line) => line.startsWith('version:'));
    final match = RegExp(
      r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)$',
    ).firstMatch(versionLine.trim());
    expect(match, isNotNull, reason: versionLine);
    expect(int.parse(match!.group(2)!), greaterThanOrEqualTo(1));

    expect(gitignore.contains('*.jks'), isTrue);
    expect(gitignore.contains('*.keystore'), isTrue);
  });

  test('localized Android names and Compoise icons are packaged', () {
    expect(dictOf(Language.zh)['appTitle'], '方寸');
    expect(dictOf(Language.en)['appTitle'], 'Compoise');
    expect(dictOf(Language.ja)['appTitle'], 'Compoise');
    final manifest = text('android/app/src/main/AndroidManifest.xml');
    expect(manifest.contains('android:label="@string/app_name"'), isTrue);
    expect(manifest.contains('android:icon="@mipmap/ic_launcher"'), isTrue);
    expect(
      manifest.contains('android:roundIcon="@mipmap/ic_launcher_round"'),
      isTrue,
    );
    expect(
      text(
        'android/app/src/main/res/values/strings.xml',
      ).contains('<string name="app_name">方寸</string>'),
      isTrue,
    );
    expect(
      text(
        'android/app/src/main/res/values-en/strings.xml',
      ).contains('<string name="app_name">Compoise</string>'),
      isTrue,
    );
    expect(
      text(
        'android/app/src/main/res/values-ja/strings.xml',
      ).contains('<string name="app_name">Compoise</string>'),
      isTrue,
    );

    final densitySizes = [48, 72, 96, 144, 192];
    final densityFolders = ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi'];
    for (var index = 0; index < densitySizes.length; index++) {
      for (final suffix in ['ic_launcher.png', 'ic_launcher_round.png']) {
        final icon = File(
          'android/app/src/main/res/mipmap-${densityFolders[index]}/$suffix',
        );
        expect(icon.existsSync(), isTrue, reason: icon.path);
        expect(icon.lengthSync(), greaterThan(1000), reason: icon.path);
      }
    }

    final ico = File('windows/runner/resources/app_icon.ico').readAsBytesSync();
    expect(ico[0], 0);
    expect(ico[1], 0);
    expect(ico[2], 1);
    expect(ico[4] + (ico[5] << 8), 7);
    expect(File('assets/tray_icon.ico').lengthSync(), greaterThan(1000));
    expect(
      text(
        'tool/generate_brand_icons.ps1',
      ).contains('assets/branding/CompoiseLogo.png'),
      isTrue,
    );
  });
}
