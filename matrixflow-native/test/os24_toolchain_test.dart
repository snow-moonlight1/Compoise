import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// OS24 keeps the verified stable toolchain, the CI pin, pubspec, and the
/// local fallback SDK pointing at the same recorded versions.
void main() {
  late Map<String, dynamic> pin;

  String text(String path) =>
      File(path).readAsStringSync().replaceAll('\r\n', '\n');

  Map<String, dynamic> map(Object? value) => value as Map<String, dynamic>;

  setUp(() {
    pin = jsonDecode(text('toolchain.json')) as Map<String, dynamic>;
  });

  test('pin records Flutter 3.32.8 stable and the untouched fallback SDK', () {
    final verified = map(pin['verified']);
    final fallback = map(pin['fallback']);

    expect(verified['flutterVersion'], '3.32.8');
    expect(verified['channel'], 'stable');
    expect(verified['revision'], 'edada7c56edf4a183c1735310e123c7f923584f1');
    expect(verified['engineRevision'], 'ef0cd000916d64fa0c5d09cc809fa7ad244a5767');
    expect(verified['dartVersion'], '3.8.1');
    expect(
      verified['archiveSha256'],
      '6d61d2fbb3afe68675864088937ad84b45920974b12cf71a12b4d18d02eb1186',
    );
    expect(verified['installPath'], 'D:/Dev_SDKs/Flutter_3.32.8');

    expect(fallback['flutterVersion'], '3.31.0-1.0.pre.88');
    expect(fallback['channel'], 'master');
    expect(fallback['revision'], '082a761570e89f67a56f50de1c4cb843a2e452af');
    expect(fallback['dartVersion'], '3.8.0-197.0.dev');
    expect(fallback['installPath'], 'D:/Dev_SDKs/Flutter_SDK');
    expect(pin['pubspecSdk'], '>=3.8.0-197.0.dev <4.0.0');
  });

  test('pubspec, lockfile, and .flutter-version agree with the pin', () {
    final pubspec = text('pubspec.yaml');
    final lock = text('pubspec.lock');
    expect(text('.flutter-version').trim(), '3.32.8');
    expect(pubspec.contains("sdk: '>=3.8.0-197.0.dev <4.0.0'"), isTrue);
    expect(pubspec.contains('sdk: ^3.8.0-197.0.dev'), isFalse);

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

  test('CI, docs, and the build script use the pin and keep the fallback', () {
    final workflow = text('../.github/workflows/release.yml');
    const pinnedSetup = """
          flutter-version: '3.32.8'
          channel: 'stable'
          cache: true
""";
    expect('flutter-version: \'3.32.8\''.allMatches(workflow).length, 2);
    expect(pinnedSetup.allMatches(workflow).length, 2);
    expect(RegExp("with:\\n\\s+channel: 'stable'").allMatches(workflow), isEmpty);

    final readme = text('../README.md');
    expect(readme.contains('3.32.8'), isTrue);
    expect(readme.contains('3.8.1'), isTrue);
    expect(readme.contains('3.16+'), isFalse);
    expect(readme.contains('D:\\Dev_SDKs\\Flutter_SDK'), isTrue);

    for (final path in [
      '../docs/DEVELOPMENT.md',
      '../docs/IMPLEMENTATION_PLAN_2026-09-22_OPEN_SOURCE_READINESS.md',
      '../AGENTS.md',
      '../scripts/build_release.ps1',
    ]) {
      final body = text(path);
      expect(body.contains('3.32.8'), isTrue, reason: path);
      expect(body.contains('Flutter_3.32.8'), isTrue, reason: path);
      expect(body.contains('Flutter_SDK'), isTrue, reason: path);
    }
  });

  test('the process Dart SDK is the verified pin or the documented fallback', () {
    final version = Platform.version;
    final pinned = map(pin['verified'])['dartVersion'] as String;
    final fallback = map(pin['fallback'])['dartVersion'] as String;
    final allowed = version.startsWith('$pinned ') || version.contains(fallback);
    expect(allowed, isTrue, reason: 'Platform.version=$version');
  });
}
