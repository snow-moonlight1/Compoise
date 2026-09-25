import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrixflow_native/ai_capabilities.dart';
import 'package:matrixflow_native/ai_service.dart';
import 'package:matrixflow_native/l10n.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/screens/settings_screen.dart';
import 'package:matrixflow_native/storage.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

const _secret = 'synthetic-os11-key';

AIConfig cfg({
  String provider = 'custom',
  AIProtocol protocol = AIProtocol.openai,
  String model = 'gpt-4o-mini',
  bool thinking = false,
  String base = 'https://example.invalid',
  String key = _secret,
}) => AIConfig(
  provider: provider,
  protocol: protocol,
  baseUrl: base,
  apiKey: key,
  model: model,
  enableThinking: thinking,
);

class _Captured {
  _Captured(this.request) : body = _decode(request);
  final http.Request request;
  final Map<String, dynamic>? body;

  static Map<String, dynamic>? _decode(http.Request request) {
    if (request.body.isEmpty) return null;
    return jsonDecode(request.body) as Map<String, dynamic>;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('new connection copy exists in en, zh and ja', () {
    const keys = [
      'aiEndpointReachable',
      'aiDiscoveryOk',
      'aiDiscoveryUnavailable',
      'aiCheckSkipped',
      'aiNoModels',
      'aiGenerationOk',
      'aiGenerationEmpty',
      'aiGenerationPartial',
      'aiGenerationThinkingOnly',
      'aiGenerationNotRun',
      'testGeneration',
      'testGenerationBilling',
      'testGenerationConfirm',
      'testGenerationConfirmAction',
      'aiCancelled',
      'aiThinkingUnsupported',
      'aiThinkingAlwaysOn',
      'aiThinkingNotForciblyOff',
      'aiThinkingLowestEffort',
      'aiThinkingCapabilityUnverified',
      'connectionEndpointLabel',
      'connectionDiscoveryLabel',
      'connectionGenerationLabel',
    ];
    for (final language in Language.values) {
      final dict = dictOf(language);
      for (final key in keys) {
        expect(dict[key], isNotEmpty, reason: '${language.name}.$key');
        expect(dict[key], isNot(contains(_secret)));
      }
    }
  });

  test('thinking plans follow provider and model capability', () {
    expect(
      planThinking(cfg(thinking: true)).fields.containsKey('thinking'),
      isFalse,
    );
    expect(planThinking(cfg(thinking: true)).hintCode, 'aiThinkingUnsupported');

    final deepseek = planThinking(
      cfg(provider: 'deepseek', model: 'deepseek-flash', thinking: false),
    );
    expect(deepseek.fields['thinking'], {'type': 'disabled'});
    expect(deepseek.hintCode, isNull);

    expect(
      planThinking(
        cfg(provider: 'volcengine', model: 'doubao-pro-32k', thinking: true),
      ).fields,
      isEmpty,
    );
    expect(
      planThinking(
        cfg(provider: 'bailian', model: 'qwen-plus', thinking: true),
      ).fields,
      isEmpty,
    );

    expect(
      planThinking(
        cfg(
          protocol: AIProtocol.openaiResponses,
          model: 'o3-mini',
          thinking: true,
        ),
      ).fields['reasoning'],
      {'effort': 'high'},
    );
    expect(
      planThinking(
        cfg(
          protocol: AIProtocol.openaiResponses,
          model: 'o3-mini',
          thinking: false,
        ),
      ).hintCode,
      'aiThinkingNotForciblyOff',
    );
    expect(
      planThinking(
        cfg(
          protocol: AIProtocol.openaiResponses,
          model: 'gpt-5.1',
          thinking: false,
        ),
      ).fields['reasoning'],
      {'effort': 'none'},
    );
    expect(
      planThinking(
        cfg(
          protocol: AIProtocol.openaiResponses,
          model: 'mystery-model',
          thinking: true,
        ),
      ).fields.containsKey('reasoning'),
      isFalse,
    );

    final manual = planThinking(
      cfg(
        protocol: AIProtocol.anthropic,
        model: 'claude-sonnet-4-5',
        thinking: true,
      ),
    );
    expect(manual.fields['thinking'], {
      'type': 'enabled',
      'budget_tokens': 4096,
    });
    expect(manual.fields.containsKey('output_config'), isFalse);

    final adaptive = planThinking(
      cfg(
        protocol: AIProtocol.anthropic,
        model: 'claude-opus-4-6',
        thinking: true,
      ),
    );
    expect(adaptive.fields['thinking'], {'type': 'adaptive'});
    expect(adaptive.fields['output_config'], {'effort': 'high'});
    // RF06: `thinking: {type: disabled}` is documented as rejected for this
    // generation, so an off switch omits the field and says reasoning may go on.
    final sonnetOff = planThinking(
      cfg(
        protocol: AIProtocol.anthropic,
        model: 'claude-sonnet-4-6',
        thinking: false,
      ),
    );
    expect(sonnetOff.fields, isEmpty);
    expect(sonnetOff.hintCode, 'aiThinkingNotForciblyOff');

    final alwaysOn = planThinking(
      cfg(
        protocol: AIProtocol.anthropic,
        model: 'claude-fable-5',
        thinking: false,
      ),
    );
    expect(alwaysOn.fields.containsKey('thinking'), isFalse);
    expect(alwaysOn.hintCode, 'aiThinkingAlwaysOn');

    final unknown = planThinking(
      cfg(protocol: AIProtocol.anthropic, model: 'claude-unknown', thinking: true),
    );
    expect(unknown.fields, isEmpty);
    expect(unknown.hintCode, 'aiThinkingUnsupported');
  });

  test('requests send capability fields only, with redacted failures', () async {
    final seen = <_Captured>[];
    var mode = 'completion';
    final service = AIService(
      client: MockClient((request) async {
        seen.add(_Captured(request));
        switch (mode) {
          case 'empty':
            return http.Response('', 200);
          case 'bad-json':
            return http.Response('not-json', 200);
          case 'unauthorized':
            return http.Response('{"error":"$_secret"}', 401);
          case 'limited':
            return http.Response('slow down $_secret', 429);
          default:
            return http.Response(
              jsonEncode({
                'choices': [
                  {
                    'message': {
                      'content':
                          '[{"title":"Task","quadrant":1,"isLongTerm":false}]',
                    },
                  },
                ],
              }),
              200,
            );
        }
      }),
    );
    addTearDown(service.close);

    await service.analyzeTasks(
      inputs: ['Task'],
      config: cfg(thinking: true),
      language: Language.en,
      autoDecompose: false,
    );
    final compatible = seen.single;
    expect(compatible.request.method, 'POST');
    expect(
      compatible.request.url.toString(),
      'https://example.invalid/chat/completions',
    );
    expect(compatible.request.url.query, isEmpty);
    expect(compatible.request.headers['authorization'], 'Bearer $_secret');
    expect(compatible.body!.keys.toSet(), {'model', 'messages', 'response_format'});
    expect(compatible.body!['response_format'], {'type': 'json_object'});
    expect(compatible.request.body, isNot(contains(_secret)));

    mode = 'empty';
    final emptyProbe = await service.testConnection(cfg());
    expect(emptyProbe.endpointAuth.ok, isTrue);
    expect(emptyProbe.modelDiscovery.code, 'aiInvalidResponse');
    expect(emptyProbe.toString(), isNot(contains(_secret)));

    mode = 'bad-json';
    final badJson = await service.testConnection(cfg());
    expect(badJson.modelDiscovery.code, 'aiInvalidResponse');

    mode = 'unauthorized';
    final denied = await service.testConnection(cfg());
    expect(denied.endpointAuth.ok, isFalse);
    expect(denied.endpointAuth.code, 'aiUnauthorized');
    expect(denied.endpointAuth.status, 401);
    expect(denied.modelDiscovery.ok, isFalse);
    expect(denied.toString(), isNot(contains(_secret)));

    mode = 'limited';
    final limited = await service.testConnection(cfg());
    expect(limited.endpointAuth.ok, isTrue);
    expect(limited.modelDiscovery.ok, isFalse);
    expect(limited.modelDiscovery.code, 'aiHttpError');
    expect(limited.modelDiscovery.status, 429);

    mode = 'completion';

    await service.analyzeTasks(
      inputs: ['Task'],
      config: cfg(provider: 'deepseek', model: 'deepseek-flash', thinking: true),
      language: Language.en,
      autoDecompose: false,
    );
    expect(seen.last.body!['thinking'], {'type': 'enabled'});
    expect(seen.last.request.body, contains('Eisenhower'));
    expect(seen.last.request.body, contains('DO NOT include opinions'));
  });

  test('Responses and Anthropic bodies match the capability for the model', () async {
    final seen = <_Captured>[];
    final service = AIService(
      client: MockClient((request) async {
        seen.add(_Captured(request));
        if (request.url.path.endsWith('/responses')) {
          return http.Response(
            jsonEncode({
              'output_text': '[{"title":"R","quadrant":2,"isLongTerm":false}]',
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'content': [
              {'type': 'text', 'text': '[{"title":"A","quadrant":3,"isLongTerm":false}]'},
            ],
          }),
          200,
        );
      }),
    );
    addTearDown(service.close);

    Future<void> run(AIConfig config) => service.analyzeTasks(
      inputs: ['Task'],
      config: config,
      language: Language.en,
      autoDecompose: false,
    );

    await run(cfg(protocol: AIProtocol.openaiResponses, model: 'o3-mini', thinking: true));
    expect(seen.last.request.url.path, '/responses');
    expect(seen.last.request.headers['authorization'], 'Bearer $_secret');
    expect(seen.last.body!['reasoning'], {'effort': 'high'});
    expect(seen.last.body!['text'], {
      'format': {'type': 'json_object'},
    });
    expect(seen.last.body!.containsKey('thinking'), isFalse);

    await run(cfg(protocol: AIProtocol.openaiResponses, model: 'mystery', thinking: true));
    expect(seen.last.body!.containsKey('reasoning'), isFalse);

    await run(
      cfg(protocol: AIProtocol.anthropic, model: 'claude-sonnet-4-5', thinking: true),
    );
    expect(seen.last.request.url.path, '/v1/messages');
    expect(seen.last.request.headers['x-api-key'], _secret);
    expect(seen.last.request.headers['anthropic-version'], '2023-06-01');
    expect(seen.last.body!['thinking'], {'type': 'enabled', 'budget_tokens': 4096});
    expect(seen.last.body!.containsKey('output_config'), isFalse);
    expect(seen.last.body!.containsKey('response_format'), isFalse);

    await run(
      cfg(protocol: AIProtocol.anthropic, model: 'claude-fable-5', thinking: false),
    );
    expect(seen.last.body!.containsKey('thinking'), isFalse);
    expect(seen.last.body!.containsKey('output_config'), isFalse);
    expect(seen.last.request.body, isNot(contains(_secret)));
  });

  test('discovery success is not generation, and probes cover empty, auth, rate, timeout, cancel', () async {
    final calls = <String>[];
    final gate = Completer<http.Response>();
    var mode = 'list';
    final service = AIService(
      timeout: const Duration(milliseconds: 40),
      client: MockClient((request) async {
        calls.add('${request.method} ${request.url.path}');
        if (mode == 'hang') return gate.future;
        if (mode == 'empty-text') {
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {'content': '   '},
                },
              ],
            }),
            200,
          );
        }
        if (mode == 'bad-generation') return http.Response('{', 200);
        if (mode == 'unauthorized') return http.Response('secret-body', 401);
        if (mode == 'limited') return http.Response('secret-body', 429);
        if (request.method == 'GET') {
          return http.Response(
            jsonEncode({
              'data': [
                {'id': 'listed-model'},
              ],
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': 'pong'},
              },
            ],
          }),
          200,
        );
      }),
    );
    addTearDown(service.close);

    final listed = await service.testConnection(cfg(model: 'listed-model'));
    expect(listed.endpointAuth.ok, isTrue);
    expect(listed.modelDiscovery.ok, isTrue);
    expect(listed.modelDiscovery.code, 'aiDiscoveryOk');
    expect(calls, ['GET /models']);
    expect(listed.toString(), isNot(contains('modelGeneration')));

    mode = 'empty-text';
    final empty = await service.testModelGeneration(cfg(model: 'listed-model', thinking: true));
    expect(empty.ok, isFalse);
    expect(empty.code, 'aiGenerationEmpty');
    expect(calls.last, 'POST /chat/completions');
    expect(empty.toString(), isNot(contains(_secret)));

    mode = 'bad-generation';
    expect((await service.testModelGeneration(cfg())).code, 'aiInvalidResponse');

    mode = 'unauthorized';
    final denied = await service.testModelGeneration(cfg());
    expect(denied.code, 'aiUnauthorized');
    expect(denied.status, 401);
    expect(denied.toString(), isNot(contains('secret-body')));

    mode = 'limited';
    final limited = await service.testModelGeneration(cfg());
    expect(limited.code, 'aiHttpError');
    expect(limited.status, 429);

    mode = 'hang';
    final timed = await service.testModelGeneration(cfg());
    expect(timed.code, 'requestTimeout');
    if (!gate.isCompleted) {
      gate.complete(http.Response('{}', 200));
    }
  });

  test('cancelling a discovery probe reports cancellation', () async {
    final service = AIService(
      client: MockClient.streaming((request, _) {
        final pending = Completer<http.StreamedResponse>();
        (request as http.Abortable).abortTrigger!.then((_) {
          if (!pending.isCompleted) {
            pending.completeError(http.RequestAbortedException());
          }
        });
        return pending.future;
      }),
    );
    addTearDown(service.close);
    final cancel = AICancellation();
    final pending = service.testConnection(cfg(), cancellation: cancel);
    await Future<void>.delayed(Duration.zero);
    cancel.cancel();
    final cancelled = await pending;
    expect(cancelled.endpointAuth.code, 'aiCancelled');
    expect(cancelled.modelDiscovery.ok, isFalse);
    expect(cancelled.toString(), isNot(contains(_secret)));
  });

  test('Anthropic discovery 404 does not call generation', () async {
    final calls = <String>[];
    final service = AIService(
      client: MockClient((request) async {
        calls.add('${request.method} ${request.url.path}');
        return http.Response('{}', 404);
      }),
    );
    addTearDown(service.close);
    final probe = await service.testConnection(
      cfg(protocol: AIProtocol.anthropic, model: 'claude-sonnet-4-6'),
    );
    expect(probe.endpointAuth.ok, isTrue);
    expect(probe.modelDiscovery.code, 'aiDiscoveryUnavailable');
    expect(calls, ['GET /v1/models']);
  });

  test('generation omits thinking extensions and drops a changed config', () async {
    final gate = Completer<http.Response>();
    Map<String, dynamic>? body;
    final service = AIService(
      client: MockClient((request) async {
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return gate.future;
      }),
    );
    addTearDown(service.close);
    final config = cfg(model: 'gpt-4o-mini', thinking: true);
    final future = service.testModelGeneration(config);
    await Future<void>.delayed(Duration.zero);
    expect(body!.keys.toSet(), {'model', 'messages', 'max_tokens'});
    expect(body!['max_tokens'], 16);
    config.model = 'other-model';
    gate.complete(
      http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {'content': 'pong'},
            },
          ],
        }),
        200,
      ),
    );
    final result = await future;
    expect(result.ok, isFalse);
    expect(result.code, 'aiCancelled');
  });

  test('Responses and Anthropic generation use official minimal bodies', () async {
    final seen = <_Captured>[];
    final service = AIService(
      client: MockClient((request) async {
        seen.add(_Captured(request));
        if (request.url.path.endsWith('/responses')) {
          return http.Response(jsonEncode({'output_text': 'pong'}), 200);
        }
        return http.Response(
          jsonEncode({
            'content': [
              {'type': 'text', 'text': 'pong'},
            ],
          }),
          200,
        );
      }),
    );
    addTearDown(service.close);
    final responses = await service.testModelGeneration(
      cfg(protocol: AIProtocol.openaiResponses, model: 'o3-mini', thinking: true),
    );
    expect(responses.ok, isTrue);
    expect(responses.code, 'aiGenerationOk');
    expect(seen.single.request.url.path, '/responses');
    expect(seen.single.body!.keys.toSet(), {'model', 'input', 'max_output_tokens'});
    expect(seen.single.body!.containsKey('reasoning'), isFalse);

    final anthropic = await service.testModelGeneration(
      cfg(protocol: AIProtocol.anthropic, model: 'claude-sonnet-4-6', thinking: true),
    );
    expect(anthropic.ok, isTrue);
    expect(seen.last.request.url.path, '/v1/messages');
    expect(seen.last.body!.keys.toSet(), {'model', 'max_tokens', 'messages'});
    expect(seen.last.body!.containsKey('thinking'), isFalse);
    expect(seen.last.body!.containsKey('output_config'), isFalse);
  });

  testWidgets('startup and blur do not generate; generation waits for confirmation', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final calls = <String>[];
    final service = AIService(
      client: MockClient((request) async {
        calls.add(request.method);
        if (request.method == 'GET') {
          return http.Response(
            jsonEncode({
              'data': [
                {'id': 'listed-model'},
              ],
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': 'pong'},
              },
            ],
          }),
          200,
        );
      }),
    );
    final store = await _openStore(tester, service);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: store,
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(calls, isEmpty);

    await tester.enterText(find.byKey(const ValueKey('api-key-input')), _secret);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    expect(calls, ['GET']);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('test-connection-btn')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const ValueKey('test-connection-btn')));
    await tester.pumpAndSettle();
    expect(calls.where((call) => call == 'POST'), isEmpty);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('connection-discovery-status'))).data,
      contains(store.t['aiDiscoveryOk']),
    );
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('connection-generation-status'))).data,
      contains(store.t['aiGenerationNotRun']),
    );

    await tester.tap(find.byKey(const ValueKey('test-generation-btn')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('generation-billing-dialog')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('generation-billing-cancel')));
    await tester.pumpAndSettle();
    expect(calls.where((call) => call == 'POST'), isEmpty);

    await tester.tap(find.byKey(const ValueKey('test-generation-btn')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('generation-billing-confirm')));
    await tester.pumpAndSettle();
    expect(calls.where((call) => call == 'POST'), ['POST']);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('connection-generation-status'))).data,
      contains(store.t['aiGenerationOk']),
    );
    expect(find.text(store.t['testOk']!), findsNothing);
  });

  testWidgets('a generation result is dropped when the key changes', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final gate = Completer<http.Response>();
    final service = AIService(
      client: MockClient((request) async => gate.future),
    );
    final store = await _openStore(tester, service);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: store,
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('api-key-input')), _secret);
    await tester.pump();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('test-generation-btn')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const ValueKey('test-generation-btn')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('generation-billing-confirm')));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('api-key-input')),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(
      find.byKey(const ValueKey('api-key-input')),
      'synthetic-other-key',
    );
    await tester.pump();
    gate.complete(
      http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {'content': 'pong'},
            },
          ],
        }),
        200,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('connection-generation-status'))).data,
      contains(store.t['aiGenerationNotRun']),
    );
  });
}
