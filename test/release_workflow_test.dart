import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:compoise/l10n.dart';
import 'package:compoise/models.dart';

/// keeps the release workflow, the packaging script, the Android release
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
    expect('permissions:\n      contents: write'.allMatches(release).length, 1);
    expect(
      release.indexOf('contents: write'),
      greaterThan(release.indexOf('  publish:')),
    );

    // Each signing secret enters through a step environment only.
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
    expect(release.contains('group: release-\${{ github.ref }}-'), isTrue);
    expect('needs: preflight'.allMatches(release).length, 3);
    expect(
      release.contains(
        'needs: [preflight, build-windows, build-linux, build-android]',
      ),
      isTrue,
    );
    // Tags must match pubspec unless they are vX.Y.Z-ci.N test tags.
    expect(release.contains('does not match pubspec.yaml version'), isTrue);
    expect(release.contains(r'-ci\.[0-9]+$'), isTrue);
    expect(release.contains('workflow_dispatch:'), isTrue);
    expect(release.contains('gh release create'), isTrue);
    expect(release.contains('--draft'), isTrue);
    expect(release.contains('Not code-signed'), isTrue);
    expect(release.contains('apksigner'), isTrue);
    expect(release.contains('test_*.py'), isTrue);
  });

  test('packaging script stages one version and refuses unsigned releases', () {
    expect(
      script.contains("\$StagingDirName = \"compoise-v\$VersionLabel\""),
      isTrue,
    );
    expect(
      script.contains(r'Remove-Item -LiteralPath $StagingDir -Recurse -Force'),
      isTrue,
    );
    expect(script.contains('release_candidate.py'), isTrue);
    expect(script.contains('seal @GateArgs'), isTrue);
    expect(script.contains('verify @GateArgs'), isTrue);
    final validator = text('scripts/release_candidate.py');
    expect(validator.contains('RELEASE_MANIFEST.txt'), isTrue);
    expect(validator.contains('RELEASE_METADATA.txt'), isTrue);
    expect(validator.contains('SHA256SUMS.txt'), isTrue);
    expect(validator.contains('Candidate file set differs'), isTrue);
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

      expect(gradle.contains('applicationId = "com.compoise.app"'), isTrue);
      expect(gradle.contains('namespace = "com.compoise.app"'), isTrue);
      expect(gradle.contains('verifyFormalReleaseSigning'), isTrue);
      expect(gradle.contains('android/key.properties.example'), isTrue);
      expect(gradle.contains('docs/development.md'), isTrue);
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

  test('release workflow traces the build and states each platform fact', () {
    // The Android gate pins the certificate, not just "not the debug key".
    expect('secrets.ANDROID_RELEASE_CERT_SHA256'.allMatches(release).length, 2);
    expect(release.contains('Refusing to publish a debug-signed APK.'), isTrue);
    expect(
      release.contains('is not signed with the pinned release certificate'),
      isTrue,
    );
    expect(script.contains(r'SignerDigest -ne $AndroidCertSha256'), isTrue);

    // Published provenance and checksums.
    expect(release.contains('RELEASE_METADATA.txt'), isTrue);
    expect(release.contains('commit=\$GITHUB_SHA'), isTrue);
    expect(release.contains('SHA256SUMS.txt'), isTrue);
    expect(release.contains('Not code-signed'), isTrue);
    expect(release.contains('License: GPL-3.0-only'), isTrue);

    // The OCR runtime ships in every package; the models never do.
    expect(release.contains('compoise_ocr.dll'), isTrue);
    expect(release.contains('libcompoise_ocr.so'), isTrue);
    expect(release.contains('OCR models must not be bundled'), isTrue);
    expect(release.contains('WP17_OCR_MODELS_DIR'), isFalse);
  });

  test('Linux ships DEB, RPM and AppImage with declared dependencies', () {
    final linuxJob = release
        .split('build-linux:')
        .last
        .split('build-android:')
        .first;
    expect(linuxJob.contains('flutter build linux --release --no-pub'), isTrue);
    expect(linuxJob.contains('scripts/ci/package_linux.sh'), isTrue);
    final packager = text('scripts/ci/package_linux.sh');
    for (final dep in ['libsecret', 'appindicator', 'gtk', 'noto']) {
      expect(packager.toLowerCase().contains(dep), isTrue, reason: dep);
    }
    for (final out in ['.deb', '.rpm', '.AppImage']) {
      expect(packager.contains(out), isTrue, reason: out);
    }
    expect(
      text('linux/CMakeLists.txt').contains('set(BINARY_NAME "compoise")'),
      isTrue,
    );
  });

  test('packaging script stays runnable on the Linux preflight runner', () {
    expect(script.contains('function Join-RepoPath'), isTrue);
    expect(script.contains(r'[System.IO.Path]::Combine'), isTrue);
    expect(
      script.contains(r'[System.IO.Path]::DirectorySeparatorChar'),
      isTrue,
    );
    expect(script.contains('[System.PlatformID]::Win32NT'), isTrue);

    // A backslash baked into a joined path silently stops existing on POSIX,
    // which is what made the release preflight unrunnable on ubuntu runners.
    for (final windowsOnly in [
      r"$StagingDir.StartsWith(",
      r"Join-Path $FlutterDir 'android\",
      r"Join-Path $FlutterDir 'build\",
      r"Join-Path $FlutterSdk 'bin\",
    ]) {
      expect(script.contains(windowsOnly), isFalse, reason: windowsOnly);
    }
    expect(script.contains(r'Split-Path -Parent $StagingDir'), isTrue);

    // storeFile resolves the way android/app/build.gradle.kts resolves it, so a
    // documented layout is never refused by the packaging gate.
    expect(script.contains(r"@('android', 'app', $Declared)"), isTrue);
    expect(
      script.contains(
        r"Join-RepoPath $FlutterDir @('android', 'app', 'key.properties')",
      ),
      isTrue,
    );
    expect(script.contains("'data/app.so'"), isTrue);
    expect(script.contains(r"'data\app.so'"), isFalse);
  });

  test('packaging script never claims an unprobed toolchain or platform', () {
    expect(script.contains(r'$ToolchainMatch'), isFalse);
    expect(
      script.contains("'not probed (Flutter SDK not found)'"),
      isTrue,
      reason: 'a missing SDK must not read as pin compliance',
    );
    expect(script.contains(r"$ToolchainPinState -ne 'matches'"), isTrue);
    expect(script.contains('toolchainPinState='), isTrue);
    expect(script.contains('Linux desktop: preview only.'), isTrue);
    expect(script.contains('license=GPL-3.0-only'), isTrue);
  });

  test(
    'Windows identity fields are the library location and are documented',
    () {
      // path_provider_windows builds %APPDATA%\<CompanyName>\<ProductName> from
      // these fields, so changing either one moves the task library on upgrade.
      expect(runnerRc.contains('"CompanyName", "Compoise"'), isTrue);
      expect(runnerRc.contains('"ProductName", "Compoise"'), isTrue);
      expect(
        script.contains(r"if ($ExeInfo.CompanyName -ne 'Compoise')"),
        isTrue,
      );
      expect(script.contains('appDataDir='), isTrue);
      expect(release.contains('appDataDir='), isTrue);

      final validation = text('docs/release-process.md');
      expect(validation.contains(r'%APPDATA%\Compoise\Compoise'), isTrue);
      expect(
        text('docs/README.md').contains('release-process.md'),
        isTrue,
        reason: 'the release checklist has to be reachable from the doc index',
      );
    },
  );

  test('GPL-3.0-only is the license every release surface states', () {
    final license = text('LICENSE');
    // The FSF boilerplate carries no SPDX identifier; "only" is declared by the
    // surfaces below, and the file must stay the version 3 text itself.
    expect(license.contains('GNU GENERAL PUBLIC LICENSE'), isTrue);
    expect(license.contains('Version 3, 29 June 2007'), isTrue);
    expect(license.contains('either version 3 of the License, or'), isTrue);
    expect(text('CONTRIBUTING.md').contains('GPL-3.0-only'), isTrue);
    expect(text('README.md').contains('GPL--3.0--only'), isTrue);
    expect(script.contains('license=GPL-3.0-only'), isTrue);
    expect(release.contains('license=GPL-3.0-only'), isTrue);
    expect(text('docs/release-process.md').contains('GPL-3.0-only'), isTrue);
    expect(pubspec.contains('license:'), isFalse);
  });

  test('release notes open with the CHANGELOG entry the checks require', () {
    final preflight = release.substring(
      release.indexOf('  preflight:'),
      release.indexOf('  build-windows:'),
    );
    expect(
      preflight.contains(
        'python3 scripts/changelog_notes.py check --tag "\$TAG"',
      ),
      isTrue,
    );
    final notes = release.substring(
      release.indexOf('- name: Write release notes'),
    );
    expect(
      notes.contains(
        'python3 scripts/changelog_notes.py notes --tag "\$TAG" > whats-new.md',
      ),
      isTrue,
    );
    expect(notes.contains('cat whats-new.md notes.md > notes-full.md'), isTrue);
    expect(
      text(
        '.github/workflows/pr.yml',
      ).contains('python3 scripts/changelog_notes.py check\n'),
      isTrue,
    );
  });
}
