import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:matrixflow_native/main.dart';

Future<void> main() async {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  // In-process mock AI server: exercises the real HTTP stack on-device.
  HttpServer? mock;
  setUpAll(() async {
    mock = await HttpServer.bind(InternetAddress.loopbackIPv4, 8123);
    mock!.listen((req) async {
      final body = jsonEncode({
        'choices': [
          {
            'message': {
              'content': jsonEncode([
                {'title': 'Mocked AI Task', 'quadrant': 1, 'isLongTerm': false, 'reasoning': 'mock reasoning'},
              ]),
            },
          },
        ],
      });
      req.response.headers.contentType = ContentType.json;
      req.response.statusCode = 200;
      req.response.write(body);
      await req.response.close();
    });
  });

  tearDownAll(() async {
    await mock?.close(force: true);
  });

  testWidgets('boot → manual add → AI add (mock server)', (tester) async {
    // Seed config to point at the in-process mock; suppress AI dialogs.
    SharedPreferences.setMockInitialValues({
      'matrixflow-config': jsonEncode({
        'provider': 'openai',
        'customBaseUrl': 'http://127.0.0.1:8123',
        'customApiKey': 'test-key',
        'customModel': 'mock-model',
      }),
      'matrixflow-settings': jsonEncode({
        'language': 'en',
        'suppressGroupPrompt': true,
        'suppressLongTermPrompt': true,
      }),
    });

    runApp(const MatrixFlowApp());
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // 1) Manual add via FAB
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('task-input')), 'Manual Flutter Task');
    await tester.tap(find.text('Add Task').last);
    await tester.pumpAndSettle();
    expect(find.text('Manual Flutter Task'), findsOneWidget);

    // 2) AI sort against the in-process mock server
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('AI Sort'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('task-input')), 'anything');
    await tester.tap(find.text('Analyze & Sort'));
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    expect(find.text('Mocked AI Task'), findsOneWidget);
    expect(find.text('mock reasoning'), findsOneWidget);
  });
}
