import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Keeps the verified Flutter toolchain pin aligned across CI and pubspec.
void main() {
  late Map<String, dynamic> pin;

  String text(String path) =>
      File(path).readAsStringSync().replaceAll('\r\n', '\n');

  Map<String, dynamic> map(Object? value) => value as Map<String, dynamic>;

  setUp(() {
    pin = jsonDecode(text('toolchain.json')) as Map<String, dynamic>;
  });

  test('records the verified stable toolchain without machine paths', () {
    final verified = map(pin['verified']);
    expect(verified['flutterVersion'], '3.32.8');
    expect(verified['channel'], 'stable');
    expect(verified['revision'], 'edada7c56edf4a183c1735310e123c7f923584f1');
    expect(
      verified['engineRevision'],
      'ef0cd000916d64fa0c5d09cc809fa7ad244a5767',
    );
    expect(verified['dartVersion'], '3.8.1');
    expect(jsonEncode(pin), isNot(contains(RegExp(r'[A-Za-z]:[/\\]'))));
    expect(pin.containsKey('fallback'), isFalse);
  });

  test('pubspec and lockfile agree with the toolchain metadata', () {
    final pubspec = text('pubspec.yaml');
    final lock = text('pubspec.lock');
    expect(text('.flutter-version').trim(), '3.32.8');
    expect(pubspec.contains("sdk: '>=3.8.0-197.0.dev <4.0.0'"), isTrue);

    const constraints = <String, String>{
      'provider': '^6.1.2',
      'http': '^1.6.0',
      'shared_preferences': '^2.3.4',
      'flutter_secure_storage': '^10.3.4',
      'path_provider': '^2.1.5',
      'file_picker': '^8.1.7',
      'flutter_local_notifications': '^19.5.0',
      'timezone': '^0.10.1',
      'window_manager': '^0.5.2',
      'tray_manager': '^0.5.3',
      'flutter_lints': '^5.0.0',
    };
    for (final entry in constraints.entries) {
      expect(pubspec.contains('  ${entry.key}: ${entry.value}'), isTrue);
    }

    final lockMeta = map(pin['lockfile']);
    expect(lock.contains('dart: "${lockMeta['dart']}"'), isTrue);
    expect(lock.contains('flutter: "${lockMeta['flutter']}"'), isTrue);
    final locked = map(pin['lockedDirect']);
    for (final entry in locked.entries) {
      final section = lock.split('  ${entry.key}:\n');
      expect(section.length, 2, reason: entry.key);
      final block = section.last.split(RegExp(r'\n  \S')).first;
      final match = RegExp(r'    version: "([^"]+)"').firstMatch(block);
      expect(match, isNotNull, reason: entry.key);
      expect(match!.group(1), entry.value);
    }
  });

  test('CI, docs, and release tooling share the Flutter version pin', () {
    final workflow = text('.github/workflows/release.yml');
    expect('flutter-version: \'3.32.8\''.allMatches(workflow).length, 2);
    expect(
      'flutter --version --machine | node scripts/verify_flutter_version.js'
          .allMatches(workflow)
          .length,
      2,
    );
    final verifier = text('scripts/verify_flutter_version.js');
    expect(
      verifier.contains("fs.readFileSync('toolchain.json', 'utf8')"),
      isTrue,
    );
    expect(verifier.contains('frameworkVersion: pin.flutterVersion'), isTrue);
    expect(verifier.contains('dartSdkVersion: pin.dartVersion'), isTrue);
    expect(verifier.contains('frameworkRevision: pin.revision'), isTrue);
    expect(verifier.contains('engineRevision: pin.engineRevision'), isTrue);
    expect(verifier.contains('channel: pin.channel'), isTrue);

    for (final path in [
      'README.md',
      'docs/DEVELOPMENT.md',
      'scripts/build_release.ps1',
      'toolchain.json',
    ]) {
      final body = text(path);
      if (path == 'scripts/build_release.ps1') {
        expect(body.contains('toolchain.json'), isTrue, reason: path);
        expect(body.contains('Dev_SDKs'), isFalse, reason: path);
      } else {
        expect(body.contains('3.32.8'), isTrue, reason: path);
        expect(body.contains(RegExp(r'[A-Za-z]:\\')), isFalse, reason: path);
      }
      expect(body.contains('Flutter_SDK'), isFalse, reason: path);
    }

    expect(
      Platform.version.startsWith('3.8.1 '),
      isTrue,
      reason: 'Platform.version=${Platform.version}',
    );
  });
}
