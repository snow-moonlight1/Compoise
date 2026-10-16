import 'dart:convert';
import 'dart:io';

import 'package:compoise/app_version.dart';
import 'package:compoise/services/device_prefs.dart';
import 'package:compoise/services/update_check.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

http.Response release(
  String tag, {
  bool prerelease = false,
  String? url,
  int status = 200,
}) => http.Response(
  jsonEncode({
    'tag_name': tag,
    'prerelease': prerelease,
    'draft': false,
    'html_url':
        url ?? 'https://github.com/snow-moonlight1/Compoise/releases/tag/$tag',
  }),
  status,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('the version constant matches pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final line = RegExp(
      r'^version:\s*(\S+)',
      multiLine: true,
    ).firstMatch(pubspec)!;
    expect(line.group(1), appVersionLabel);
  });

  test('release versions compare by number, then pre-release, then build', () {
    ReleaseVersion v(String s) => ReleaseVersion.parse(s)!;
    expect(v('v1.0.1') > v('1.0.0+1'), isTrue);
    expect(v('v1.0.0') > v('1.0.0+1'), isFalse);
    expect(v('v1.0.0+2') > v('1.0.0+1'), isTrue);
    expect(v('v1.10.0') > v('v1.9.9'), isTrue);
    expect(v('v1.0.1-ci.3') > v('v1.0.0'), isTrue);
    expect(v('v1.0.1-ci.3') > v('v1.0.1'), isFalse);
    expect(v('v1.0.1-ci.3').isPreRelease, isTrue);
    expect(v('v2.3.4+9').label, '2.3.4');
    expect(ReleaseVersion.parse('latest'), isNull);
    expect(ReleaseVersion.parse('v1.0'), isNull);
  });

  test('a newer release is offered with its GitHub page', () async {
    late http.Request seen;
    final checker = UpdateChecker(
      currentVersion: '1.0.0+1',
      client: MockClient((request) async {
        seen = request;
        return release('v1.0.1');
      }),
    );
    final result = await checker.check();
    expect(result.status, UpdateCheckStatus.available);
    expect(result.latest, '1.0.1');
    expect(
      result.url,
      'https://github.com/snow-moonlight1/Compoise/releases/tag/v1.0.1',
    );
    expect(seen.url.toString(), latestReleaseApi);
    expect(seen.headers['User-Agent'], startsWith('Compoise/'));
    expect(seen.body, isEmpty);
  });

  test('same, older and pre-release tags are up to date', () async {
    for (final response in [
      release('v1.0.0'),
      release('v0.9.0'),
      release('v1.0.1-ci.1'),
      release('v1.0.1', prerelease: true),
    ]) {
      final checker = UpdateChecker(
        currentVersion: '1.0.0+1',
        client: MockClient((_) async => response),
      );
      expect((await checker.check()).status, UpdateCheckStatus.upToDate);
    }
  });

  test(
    'a release page off the project falls back to the latest page',
    () async {
      final checker = UpdateChecker(
        currentVersion: '1.0.0+1',
        client: MockClient(
          (_) async => release('v1.0.1', url: 'https://example.com/fake'),
        ),
      );
      expect((await checker.check()).url, latestReleasePage);
    },
  );

  test('rate limits, bad bodies and network errors fail quietly', () async {
    for (final client in [
      MockClient((_) async => http.Response('{"message":"rate"}', 403)),
      MockClient((_) async => http.Response('not json', 200)),
      MockClient((_) async => release('nightly')),
      MockClient((_) async => throw const SocketException('offline')),
    ]) {
      final checker = UpdateChecker(currentVersion: '1.0.0+1', client: client);
      expect((await checker.check()).status, UpdateCheckStatus.failed);
    }
  });

  test('the automatic check is off by default and runs once a day', () async {
    var calls = 0;
    var now = DateTime(2026, 10, 20, 9);
    final prefs = DevicePrefs();
    await prefs.load();
    final checker = UpdateChecker(
      prefs: prefs,
      currentVersion: '1.0.0+1',
      now: () => now,
      client: MockClient((_) async {
        calls++;
        return release('v1.0.1');
      }),
    );

    expect(await checker.checkIfDue(), isNull);
    expect(calls, 0);

    await prefs.setUpdateCheckEnabled(true);
    expect((await checker.checkIfDue())?.latest, '1.0.1');
    expect(calls, 1);

    now = now.add(const Duration(hours: 23));
    expect(await checker.checkIfDue(), isNull);
    expect(calls, 1);

    now = now.add(const Duration(hours: 2));
    expect(await checker.checkIfDue(), isNotNull);
    expect(calls, 2);

    final reloaded = DevicePrefs();
    await reloaded.load();
    expect(reloaded.updateCheckEnabled, isTrue);
    expect(reloaded.lastUpdateCheck, now);
  });

  test('the AI wait time keeps to the offered choices', () async {
    SharedPreferences.setMockInitialValues({DevicePrefs.aiTimeoutKey: 45});
    final prefs = DevicePrefs();
    await prefs.load();
    expect(prefs.aiTimeoutSeconds, DevicePrefs.defaultAiTimeoutSeconds);
    await prefs.setAiTimeoutSeconds(120);
    final reloaded = DevicePrefs();
    await reloaded.load();
    expect(reloaded.aiTimeout, const Duration(seconds: 120));
  });
}
