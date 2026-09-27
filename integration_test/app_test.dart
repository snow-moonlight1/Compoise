import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:matrixflow_native/main.dart' as app;
import 'package:matrixflow_native/screens/matrix_screen.dart';
import 'package:matrixflow_native/services/desktop_shell_windows.dart';
import 'package:matrixflow_native/storage.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Mock integration entry. Real notification and tray behavior lives in
/// `tool/os25_platform_smoke.dart` and is not started here.
Future<void> main() async {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  late HttpServer server;
  late int port;
  final requests = <String>[];
  final credentials = _MemoryCredentialStore();

  setUpAll(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    port = server.port;
    server.listen((request) async {
      requests.add('${request.method.toUpperCase()} ${request.uri.path}');
      await _routeMockAi(request);
    });
  });

  tearDownAll(() async {
    await server.close(force: true);
    debugUseRealWindowsShellOverride = null;
    ReminderService.resetForTest();
    Store.testCredentialStore = null;
  });

  setUp(() {
    requests.clear();
    credentials.value = null;
    debugUseRealWindowsShellOverride = false;
    ReminderService.resetForTest(NoopReminderService());
    Store.testCredentialStore = credentials;
  });

  Future<void> boot(WidgetTester tester, {required bool seenOnboarding}) async {
    SharedPreferences.setMockInitialValues({
      'matrixflow-config': jsonEncode({
        'providerId': 'custom',
        'provider': 'openai',
        'protocol': 'openai',
        'customBaseUrl': 'http://127.0.0.1:$port',
        'customApiKey': 'test-key',
        'customModel': 'mock-model',
        'enableThinking': false,
      }),
      'matrixflow-settings': jsonEncode({
        'language': 'en',
        'suppressGroupPrompt': true,
        'suppressLongTermPrompt': true,
      }),
      if (seenOnboarding) 'matrixflow-has-seen-onboarding': true,
    });
    await tester.binding.setSurfaceSize(const Size(400, 900));
    await app.main();
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  testWidgets('production init uses the current add key and routed mock AI', (
    tester,
  ) async {
    try {
      await boot(tester, seenOnboarding: true);
      await _waitFor(tester, find.byKey(const ValueKey('add-task-btn')));

      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.byKey(const ValueKey('onboarding-skip-btn')), findsNothing);
      expect(shouldUseRealWindowsShell(), isFalse);
      expect(ReminderService.instance, isA<NoopReminderService>());
      expect(await credentials.read(), 'test-key');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('matrixflow-has-seen-onboarding'), isTrue);
      expect(prefs.getString('matrixflow-os25-user-profile'), isNull);

      final models = await _get(port, '/models');
      expect(models.status, 200);
      expect(models.body, contains('mock-model'));
      expect(models.body, isNot(contains('Mocked AI Task')));
      final wrongProtocol = await _post(port, '/responses');
      expect(wrongProtocol.status, 404);
      requests.clear();

      await tester.tap(find.byKey(const ValueKey('add-task-btn')));
      await _waitFor(tester, find.byKey(const ValueKey('task-input')));
      await tester.enterText(
        find.byKey(const ValueKey('task-input')),
        'Manual Flutter Task',
      );
      await tester.tap(find.byKey(const ValueKey('submit-tasks')));
      await _waitFor(tester, find.text('Manual Flutter Task'));
      await _waitUntilGone(tester, find.byKey(const ValueKey('task-input')));

      await tester.tap(find.byKey(const ValueKey('add-task-btn')));
      await _waitFor(tester, find.text('AI Sort'));
      await tester.tap(find.text('AI Sort'));
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('task-input')),
        'anything',
      );
      await tester.tap(find.byKey(const ValueKey('submit-tasks')));
      await _waitFor(tester, find.text('Mocked AI Task'));

      expect(find.text('mock reasoning'), findsNothing);
      expect(requests, ['POST /chat/completions']);
      final store = Provider.of<Store>(
        tester.element(find.byType(MatrixHome)),
        listen: false,
      );
      expect(store.hasSeenOnboarding, isTrue);
    } finally {
      await unmount(tester);
      await tester.binding.setSurfaceSize(null);
    }
  });

  testWidgets('missing onboarding flag opens the current first-run guide', (
    tester,
  ) async {
    try {
      await boot(tester, seenOnboarding: false);
      await _waitFor(tester, find.byKey(const ValueKey('onboarding-skip-btn')));
      expect(
        find.byKey(const ValueKey('onboarding-skip-btn')).hitTestable(),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('add-task-btn')).hitTestable(),
        findsNothing,
      );
      expect(find.byType(FloatingActionButton), findsNothing);

      await tester.tap(find.byKey(const ValueKey('onboarding-skip-btn')));
      await _waitFor(
        tester,
        find.byKey(const ValueKey('add-task-btn')).hitTestable(),
      );
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      final store = Provider.of<Store>(
        tester.element(find.byType(MatrixHome)),
        listen: false,
      );
      expect(store.hasSeenOnboarding, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('matrixflow-has-seen-onboarding'), isTrue);
    } finally {
      await unmount(tester);
      await tester.binding.setSurfaceSize(null);
    }
  });
}

Future<void> _routeMockAi(HttpRequest request) async {
  final method = request.method.toUpperCase();
  final path = request.uri.path;
  if (method == 'GET' && path == '/models') {
    await _writeJson(request, 200, {
      'object': 'list',
      'data': [
        {'id': 'mock-model'},
      ],
    });
    return;
  }
  if (method == 'POST' && path == '/chat/completions') {
    await _writeJson(request, 200, {
      'choices': [
        {
          'message': {
            'content': jsonEncode({
              'tasks': [
                {
                  'title': 'Mocked AI Task',
                  'quadrant': 1,
                  'isLongTerm': false,
                  'isGrouped': false,
                  'reasoning': 'mock reasoning',
                  'subtasks': <String>[],
                },
              ],
            }),
          },
        },
      ],
    });
    return;
  }
  await _writeJson(request, 404, {'error': 'unrouted'});
}

Future<void> _writeJson(
  HttpRequest request,
  int status,
  Map<String, Object?> body,
) async {
  request.response.statusCode = status;
  request.response.headers.contentType = ContentType.json;
  request.response.write(jsonEncode(body));
  await request.response.close();
}

Future<({int status, String body})> _get(int port, String path) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(
      Uri.parse('http://127.0.0.1:$port$path'),
    );
    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();
    return (status: response.statusCode, body: body);
  } finally {
    client.close(force: true);
  }
}

Future<({int status, String body})> _post(int port, String path) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(
      Uri.parse('http://127.0.0.1:$port$path'),
    );
    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();
    return (status: response.statusCode, body: body);
  } finally {
    client.close(force: true);
  }
}

Future<void> _waitFor(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 80; attempt++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) return;
    if (attempt.isOdd) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
    }
  }
  fail('Timed out waiting for $finder');
}

Future<void> _waitUntilGone(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 80; attempt++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isEmpty) return;
    if (attempt.isOdd) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
    }
  }
  fail('Timed out waiting for $finder to disappear');
}

class _MemoryCredentialStore implements CredentialStore {
  String? value;

  @override
  Future<void> delete() async {
    value = null;
  }

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async {
    this.value = value;
  }
}
