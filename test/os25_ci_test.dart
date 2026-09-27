import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// OS25 keeps keyless PR checks, the formal release signing gate, and the
/// mock-versus-real platform test boundary aligned with the source.
void main() {
  String text(String path) =>
      File(path).readAsStringSync().replaceAll('\r\n', '\n');

  late Map<String, dynamic> pin;
  late String workflow;
  late String release;
  late String gradle;
  late String integration;
  late String smoke;

  setUp(() {
    pin = jsonDecode(text('toolchain.json')) as Map<String, dynamic>;
    workflow = text('.github/workflows/pr.yml');
    release = text('.github/workflows/release.yml');
    gradle = text('android/app/build.gradle.kts');
    integration = text('integration_test/app_test.dart');
    smoke = text('tool/os25_platform_smoke.dart');
  });

  Map<String, dynamic> verified() => pin['verified'] as Map<String, dynamic>;

  test('PR checks pin OS24 Flutter and run before any release', () {
    const setup = """
          flutter-version: '3.32.8'
          channel: 'stable'
          cache: true
""";
    expect(workflow.contains('pull_request:'), isTrue);
    expect(workflow.contains('push:'), isTrue);
    expect(workflow.contains("tags:"), isFalse);
    expect(workflow.contains('contents: read'), isTrue);
    expect(workflow.contains('contents: write'), isFalse);
    expect(setup.allMatches(workflow).length, 4);
    expect(workflow.contains('toolchain.json'), isTrue);
    expect('flutter --version --machine'.allMatches(workflow).length, 4);
    expect(workflow.contains('pin.flutterVersion'), isTrue);
    expect(workflow.contains('pin.dartVersion'), isTrue);
    expect(workflow.contains('pin.revision'), isTrue);
    expect(workflow.contains('frameworkRevision:pin.revision'), isTrue);
    expect(workflow.contains('engineRevision:pin.engineRevision'), isTrue);
    expect(verified()['flutterVersion'], '3.32.8');
    expect(verified()['revision'], 'edada7c56edf4a183c1735310e123c7f923584f1');
    expect(workflow.contains('flutter analyze --no-pub'), isTrue);
    expect(workflow.contains('flutter test --no-pub'), isTrue);
    expect(
      workflow.contains('flutter test --no-pub integration_test/app_test.dart'),
      isTrue,
    );
    expect(workflow.contains('continue-on-error'), isFalse);
    expect(workflow.contains('|| true'), isFalse);
    expect(workflow.contains('flutter build apk --debug'), isTrue);
    expect(workflow.contains('flutter build windows --debug'), isTrue);
    expect(workflow.contains('flutter build apk --release'), isFalse);
    expect(workflow.contains('ANDROID_KEYSTORE'), isFalse);
    expect(workflow.contains('REQUIRE_RELEASE_SIGNING: \'true\''), isFalse);
    expect(workflow.contains('REQUIRE_RELEASE_SIGNING: \'false\''), isTrue);
    expect(
      workflow.contains(
        'Real notification and tray smoke is not part of this PR check.',
      ),
      isTrue,
    );
    expect(
      workflow.contains('This record is not a passing smoke result.'),
      isTrue,
    );
    expect(
      workflow.contains(
        "github.event_name == 'workflow_dispatch' && inputs.run_platform_smoke",
      ),
      isTrue,
    );
  });

  test('missing signing blocks only a formal release build', () {
    expect(gradle.contains('System.getenv("CI")'), isFalse);
    expect(gradle.contains('verifyFormalReleaseSigning'), isTrue);
    expect(
      gradle.contains('System.getenv("REQUIRE_RELEASE_SIGNING") != "true"'),
      isTrue,
    );
    expect(gradle.contains('assembleRelease'), isTrue);
    expect(gradle.contains('bundleRelease'), isTrue);
    expect(release.contains("REQUIRE_RELEASE_SIGNING: 'true'"), isTrue);
    final releaseBuild = release.split('Build Android Release APK').last;
    expect(releaseBuild.contains('flutter build apk --release'), isTrue);
    expect(
      releaseBuild.indexOf("REQUIRE_RELEASE_SIGNING: 'true'"),
      lessThan(releaseBuild.indexOf('flutter build apk --release')),
    );
  });

  test('mock integration and real platform smoke stay apart', () {
    expect(integration.contains('FloatingActionButton'), isTrue);
    expect(integration.contains('find.byType(FloatingActionButton)'), isTrue);
    expect(integration.contains('8123'), isFalse);
    expect(
      integration.contains("HttpServer.bind(InternetAddress.loopbackIPv4, 0)"),
      isTrue,
    );
    expect(integration.contains("path == '/models'"), isTrue);
    expect(integration.contains("path == '/chat/completions'"), isTrue);
    expect(integration.contains("path == '/responses'"), isFalse);
    expect(integration.contains("await _writeJson(request, 404"), isTrue);
    expect(integration.contains("ValueKey('add-task-btn')"), isTrue);
    expect(integration.contains("ValueKey('task-input')"), isTrue);
    expect(integration.contains("ValueKey('submit-tasks')"), isTrue);
    expect(integration.contains("ValueKey('onboarding-skip-btn')"), isTrue);
    expect(integration.contains('matrixflow-has-seen-onboarding'), isTrue);
    expect(integration.contains('seenOnboarding: false'), isTrue);
    expect(integration.contains('await app.main()'), isTrue);
    expect(
      integration.contains('debugUseRealWindowsShellOverride = false'),
      isTrue,
    );
    expect(integration.contains('NoopReminderService()'), isTrue);
    expect(integration.contains('setMockInitialValues'), isTrue);
    expect(
      integration.contains('shared_preferences_platform_interface'),
      isFalse,
    );
    expect(integration.contains('tray_manager'), isFalse);
    expect(
      integration.contains('FlutterLocalNotificationsReminderService'),
      isFalse,
    );

    expect(smoke.contains('FlutterLocalNotificationsReminderService'), isTrue);
    expect(smoke.contains('WindowsDesktopShellHost'), isTrue);
    expect(smoke.contains('trayManager'), isFalse);
    expect(smoke.contains('host?.destroy()'), isTrue);
    expect(smoke.contains('SharedPreferences'), isFalse);
    expect(smoke.contains('Store('), isFalse);
    expect(smoke.contains('setMockInitialValues'), isFalse);
    expect(smoke.contains('MATRIXFLOW_OS25_SMOKE_RESULT'), isTrue);
    expect(smoke.contains('exit(2)'), isTrue);
    expect(integration.contains('tool/os25_platform_smoke.dart'), isTrue);
  });
}
