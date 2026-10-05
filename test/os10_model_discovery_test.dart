import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrixflow_native/ai_service.dart';
import 'package:matrixflow_native/model_discovery.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/screens/settings_screen.dart';
import 'package:matrixflow_native/storage.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/settings_panels.dart';

const _secret = 'synthetic-os10-key';

AIConfig sample({
  String provider = 'custom',
  AIProtocol protocol = AIProtocol.openai,
  String base = 'https://example.invalid',
  String key = _secret,
  String model = 'test-model',
}) => AIConfig(
  provider: provider,
  protocol: protocol,
  baseUrl: base,
  apiKey: key,
  model: model,
);

http.Response modelsNamed(String id) => http.Response(
  jsonEncode({
    'data': [
      {'id': id},
    ],
  }),
  200,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('OS-R04: model discovery cache separates protocols', () async {
    var calls = 0;
    final service = AIService(
      client: MockClient((request) async {
        calls++;
        return modelsNamed(
          request.url.path == '/v1/models' ? 'anthropic-model' : 'chat-model',
        );
      }),
    );
    addTearDown(service.close);
    final config = sample();
    await service.fetchModels(config: config);
    config.protocol = AIProtocol.anthropic;
    final models = await service.fetchModels(config: config);
    expect(models, ['anthropic-model']);
    expect(calls, 2);
    expect(service.modelCacheDiagnostic, isNot(contains(_secret)));
  });

  test('identity normalizes URL and redacts the credential', () {
    final a = tryModelDiscoveryIdentity(
      sample(base: 'HTTPS://Example.Invalid/v1/'),
    );
    final b = tryModelDiscoveryIdentity(
      sample(base: 'https://example.invalid/v1'),
    );
    expect(a, b);
    expect(a.toString(), isNot(contains(_secret)));
    expect(a!.diagnosticLabel, contains('credential:redacted'));
    expect(tryModelDiscoveryIdentity(sample(key: '   ')), isNull);
    expect(
      tryModelDiscoveryIdentity(
        sample(base: 'https://example.invalid?token=$_secret'),
      ),
      isNull,
    );
  });

  test('each identity dimension misses the cache', () async {
    final paths = <String>[];
    final service = AIService(
      client: MockClient((request) async {
        paths.add('${request.url}|${request.headers['authorization']}');
        return modelsNamed('m${paths.length}');
      }),
    );
    addTearDown(service.close);
    final base = sample();
    expect(await service.fetchModels(config: base), ['m1']);
    expect(await service.fetchModels(config: sample()), ['m1']);

    expect(await service.fetchModels(config: sample(provider: 'deepseek')), [
      'm2',
    ]);
    expect(
      await service.fetchModels(config: sample(base: 'https://other.invalid')),
      ['m3'],
    );
    expect(
      await service.fetchModels(
        config: sample(protocol: AIProtocol.openaiResponses),
      ),
      ['m4'],
    );
    expect(
      await service.fetchModels(config: sample(key: 'synthetic-other-key')),
      ['m5'],
    );
    expect(paths, hasLength(5));
    final urls = paths.map((entry) => entry.split('|').first).join('\n');
    expect(urls, contains('other.invalid'));
    expect(urls, isNot(contains(_secret)));
    expect(service.modelCacheDiagnostic, isNot(contains(_secret)));
    expect(
      service.modelCacheDiagnostic,
      isNot(contains('synthetic-other-key')),
    );
  });

  test(
    'same normalized URL reuses the cache; force refresh does not',
    () async {
      var calls = 0;
      final service = AIService(
        client: MockClient((request) async {
          calls++;
          return modelsNamed('once');
        }),
      );
      addTearDown(service.close);
      await service.fetchModels(
        config: sample(base: 'https://Example.Invalid/'),
      );
      final cached = await service.fetchModels(
        config: sample(base: 'https://example.invalid'),
      );
      expect(cached, ['once']);
      expect(calls, 1);
      await service.fetchModels(
        config: sample(base: 'https://example.invalid'),
        forceRefresh: true,
      );
      expect(calls, 2);
    },
  );

  test(
    'failures are not cached and the next attempt hits the network',
    () async {
      var calls = 0;
      final service = AIService(
        client: MockClient((request) async {
          calls++;
          if (calls == 1) return http.Response('nope', 500);
          return modelsNamed('retried');
        }),
      );
      addTearDown(service.close);
      await expectLater(
        service.fetchModels(config: sample()),
        throwsA(
          isA<AIException>().having(
            (error) => error.code,
            'code',
            'aiHttpError',
          ),
        ),
      );
      expect(await service.fetchModels(config: sample()), ['retried']);
      expect(calls, 2);
      expect(service.modelCacheDiagnostic, isNot(contains(_secret)));
    },
  );

  test('returning to a previous identity reuses that identity cache', () async {
    var calls = 0;
    final service = AIService(
      client: MockClient((request) async {
        calls++;
        return modelsNamed(request.url.path == '/v1/models' ? 'anth' : 'chat');
      }),
    );
    addTearDown(service.close);
    final config = sample();
    expect(await service.fetchModels(config: config), ['chat']);
    config.protocol = AIProtocol.anthropic;
    expect(await service.fetchModels(config: config), ['anth']);
    config.protocol = AIProtocol.openai;
    expect(await service.fetchModels(config: config), ['chat']);
    expect(calls, 2);
  });

  test('a late response from a retired identity is not cached', () async {
    final gates = <Completer<http.Response>>[];
    final service = AIService(
      client: MockClient((request) async {
        final gate = Completer<http.Response>();
        gates.add(gate);
        return gate.future;
      }),
    );
    addTearDown(service.close);
    final first = sample();
    final second = sample(protocol: AIProtocol.anthropic);
    final futureA = service.fetchModels(config: first);
    await Future<void>.delayed(Duration.zero);
    final futureB = service.fetchModels(config: second);
    await Future<void>.delayed(Duration.zero);
    expect(gates, hasLength(2));
    final stale = expectLater(
      futureA,
      throwsA(
        isA<AIException>().having((error) => error.code, 'code', 'aiCancelled'),
      ),
    );
    gates[0].complete(modelsNamed('stale-chat'));
    await stale;
    gates[1].complete(modelsNamed('fresh-anthropic'));
    expect(await futureB, ['fresh-anthropic']);
    final futureA2 = service.fetchModels(config: first);
    await Future<void>.delayed(Duration.zero);
    expect(gates, hasLength(3));
    gates[2].complete(modelsNamed('fresh-chat'));
    expect(await futureA2, ['fresh-chat']);
    expect(service.modelCacheDiagnostic, isNot(contains(_secret)));
  });

  test('mutating the config during discovery discards the response', () async {
    final gate = Completer<http.Response>();
    final service = AIService(
      client: MockClient((request) async => gate.future),
    );
    addTearDown(service.close);
    final config = sample();
    final future = service.fetchModels(config: config);
    await Future<void>.delayed(Duration.zero);
    config.apiKey = 'synthetic-changed-key';
    gate.complete(modelsNamed('should-drop'));
    await expectLater(
      future,
      throwsA(
        isA<AIException>().having((error) => error.code, 'code', 'aiCancelled'),
      ),
    );
    expect(service.modelCacheDiagnostic, isEmpty);
  });

  testWidgets(
    'settings clears discovery when protocol or advanced URL changes',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 2200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final gates = <Completer<http.Response>>[];
      final paths = <String>[];
      final service = AIService(
        client: MockClient((request) async {
          paths.add(request.url.path);
          final gate = Completer<http.Response>();
          gates.add(gate);
          return gate.future;
        }),
      );
      final store = await _openStore(tester, service);
      await tester.pumpWidget(_app(store));
      await tester.pumpAndSettle();
      await openSettingsPanel(tester, 'settings-assistant-row');

      await _chooseProvider(tester, store.t['providerCustom']!);
      await tester.enterText(
        find.byKey(const ValueKey('base-url-input')),
        'https://example.invalid',
      );
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('api-key-input')),
        _secret,
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(gates, hasLength(1));
      gates[0].complete(modelsNamed('chat-model'));
      await tester.pumpAndSettle();
      expect(find.text('chat-model'), findsWidgets);

      await tester.tap(find.byKey(const ValueKey('protocol-selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(store.t['providerAnthropic']!).last);
      await tester.pump();
      expect(find.byKey(const ValueKey('model-selector')), findsNothing);
      expect(find.byKey(const ValueKey('model-input')), findsOneWidget);
      expect(paths, ['/models']);
      await tester.tap(find.byKey(const ValueKey('refresh-models-btn')));
      await tester.pump();
      expect(paths, ['/models', '/v1/models']);
      gates[1].complete(modelsNamed('anthropic-model'));
      await tester.pumpAndSettle();
      expect(find.text('anthropic-model'), findsWidgets);
      expect(find.text('chat-model'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('protocol-selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(store.t['providerOpenAI']!).last);
      await tester.pump();
      expect(find.byKey(const ValueKey('model-selector')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('api-key-input')));
      await tester.pump();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      await tester.pump();
      expect(paths, ['/models', '/v1/models']);
      expect(find.text('chat-model'), findsWidgets);
      expect(find.text('anthropic-model'), findsNothing);
    },
  );

  testWidgets('advanced preset URL edit drops the previous model list', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final gates = <Completer<http.Response>>[];
    final hosts = <String>[];
    final service = AIService(
      client: MockClient((request) async {
        hosts.add(request.url.host);
        final gate = Completer<http.Response>();
        gates.add(gate);
        return gate.future;
      }),
    );
    final store = await _openStore(tester, service);
    await tester.pumpWidget(_app(store));
    await tester.pumpAndSettle();
    await openSettingsPanel(tester, 'settings-assistant-row');
    await tester.enterText(
      find.byKey(const ValueKey('api-key-input')),
      _secret,
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    gates.single.complete(modelsNamed('deepseek-flash'));
    await tester.pumpAndSettle();
    expect(find.text('deepseek-flash'), findsWidgets);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('advanced-settings-tile')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const ValueKey('advanced-settings-tile')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('base-url-input')),
      'https://other.invalid',
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('model-selector')), findsNothing);
    expect(gates, hasLength(1));
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    expect(gates, hasLength(2));
    expect(hosts.last, 'other.invalid');
    gates[1].complete(modelsNamed('other-model'));
    await tester.pumpAndSettle();
    expect(find.text('other-model'), findsWidgets);
    expect(find.text('deepseek-flash'), findsNothing);
  });

  testWidgets('dispose does not apply a late discovery result', (tester) async {
    final gate = Completer<http.Response>();
    final service = AIService(
      client: MockClient((request) async => gate.future),
    );
    await tester.binding.setSurfaceSize(const Size(900, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = await _openStore(tester, service);
    await tester.pumpWidget(_app(store));
    await tester.pumpAndSettle();
    await openSettingsPanel(tester, 'settings-assistant-row');
    await tester.enterText(
      find.byKey(const ValueKey('api-key-input')),
      _secret,
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    gate.complete(modelsNamed('late-model'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}

Future<Store> _openStore(WidgetTester tester, AIService service) async {
  SharedPreferences.setMockInitialValues({
    'matrixflow-has-seen-onboarding': true,
  });
  late Store store;
  await tester.runAsync(() async {
    store = Store(aiService: service);
    await store.init();
  });
  addTearDown(store.dispose);
  return store;
}

Widget _app(Store store) => ChangeNotifierProvider.value(
  value: store,
  child: MaterialApp(home: const SettingsScreen()),
);

Future<void> _chooseProvider(WidgetTester tester, String label) async {
  await tester.tap(find.byKey(const ValueKey('provider-selector')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}
