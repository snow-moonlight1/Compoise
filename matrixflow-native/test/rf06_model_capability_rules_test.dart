// RF06: model version, endpoint and thinking-capability rules, plus how the
// short generation probe classifies what came back.
//
// Every expectation here is read off the vendor's own model page on
// 2026-09-26 — see the source list at the top of lib/ai_capabilities.dart.
// Synthetic keys and MockClient only: no real credential, no paid call.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrixflow_native/ai_capabilities.dart';
import 'package:matrixflow_native/ai_service.dart';
import 'package:matrixflow_native/l10n.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/screens/settings_model_request.dart';
import 'package:matrixflow_native/storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _key = 'synthetic-rf06-key';
const _customBase = 'https://proxy.invalid';
const _deepSeekBase = 'https://api.deepseek.com';
const _tasksJson = '[{"title":"Task","quadrant":1,"isLongTerm":false}]';

AIConfig cfg({
  String provider = 'custom',
  AIProtocol protocol = AIProtocol.openai,
  String model = 'gpt-4o-mini',
  bool thinking = false,
  String base = _customBase,
}) => AIConfig(
  provider: provider,
  protocol: protocol,
  baseUrl: base,
  apiKey: _key,
  model: model,
  enableThinking: thinking,
);

AIConfig responses(String model, {bool thinking = false}) => cfg(
  protocol: AIProtocol.openaiResponses,
  model: model,
  thinking: thinking,
);

AIConfig anthropic(String model, {bool thinking = false}) =>
    cfg(protocol: AIProtocol.anthropic, model: model, thinking: thinking);

/// The responses ids whose model page lists effort `none`.
const _documentedNone = [
  'gpt-5.1',
  'gpt-5.5',
  'gpt-5.6',
  'gpt-6-sol',
  'gpt-6-luna',
];

/// Reasoning ids with no documented value set, so nothing may be assumed.
const _unverifiedReasoning = ['gpt-5.2', 'gpt-5-mini', 'gpt-5-chat', 'gpt-6-mira'];

const _alwaysOn = [
  'claude-fable-5',
  'claude-fable-5-1',
  'claude-mythos-5',
  'claude-mythos-5-1',
  'claude-opus-5-5',
];

const _adaptive = [
  'claude-opus-4-6',
  'claude-opus-4-7',
  'claude-opus-4-8',
  'claude-sonnet-4-6',
];

const _manual = [
  'claude-3-7-sonnet-20250219',
  'claude-haiku-4-5-20251001',
  'claude-sonnet-4-5',
  'claude-opus-4-5',
];

const _undocumentedClaude = ['claude-nova-9', 'claude-opus-9-9', 'claude-mythos-preview'];

class _Capture {
  final requests = <http.Request>[];

  Map<String, dynamic>? get body =>
      requests.isEmpty
          ? null
          : jsonDecode(requests.last.body) as Map<String, dynamic>;

  MockClient get client => MockClient((request) async {
    requests.add(request);
    if (request.method == 'GET') {
      return http.Response(jsonEncode({'data': [{'id': 'gpt-5'}]}), 200);
    }
    if (request.url.path.endsWith('/responses')) {
      return http.Response(jsonEncode({'output_text': _tasksJson}), 200);
    }
    if (request.url.path.endsWith('/messages')) {
      return http.Response(
        jsonEncode({
          'content': [
            {'type': 'text', 'text': _tasksJson},
          ],
        }),
        200,
      );
    }
    return http.Response(
      jsonEncode({
        'choices': [
          {'message': {'content': _tasksJson}, 'finish_reason': 'stop'},
        ],
      }),
      200,
    );
  });
}

/// Runs the short generation probe for [config] against one canned [reply].
Future<AiProbeStep> probeReply(AIConfig config, http.Response reply) async {
  final service = AIService(
    client: MockClient((request) async {
      if (request.method == 'GET') {
        return http.Response(jsonEncode({'data': [{'id': 'm'}]}), 200);
      }
      return reply;
    }),
  );
  addTearDown(service.close);
  return service.testModelGeneration(config);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Responses effort follows the documented model version', () {
    test('original GPT-5 never receives effort none', () {
      // Review probe RF-R07 asserts the same rule; this is its default home.
      for (final id in ['gpt-5', 'gpt-5-2025-08-07']) {
        final plan = planThinking(responses(id));
        expect(plan.fields['reasoning'], isNot({'effort': 'none'}), reason: id);
        expect(plan.fields['reasoning'], {'effort': 'minimal'}, reason: id);
        expect(plan.hintCode, 'aiThinkingLowestEffort', reason: id);
      }
    });

    test('versions documenting none get exactly none', () {
      for (final id in _documentedNone) {
        final off = planThinking(responses(id));
        expect(off.fields['reasoning'], {'effort': 'none'}, reason: id);
        expect(off.hintCode, isNull, reason: id);
        expect(
          planThinking(responses(id, thinking: true)).fields['reasoning'],
          {'effort': 'high'},
          reason: id,
        );
      }
    });

    test('GPT-6 Astra rejects none, so the field is omitted', () {
      final off = planThinking(responses('gpt-6-astra'));
      expect(off.fields.containsKey('reasoning'), isFalse);
      expect(off.hintCode, 'aiThinkingNotForciblyOff');
      expect(
        planThinking(responses('gpt-6-astra', thinking: true)).fields['reasoning'],
        {'effort': 'high'},
      );
    });

    test('unverified versions omit effort and say thinking may continue', () {
      for (final id in _unverifiedReasoning) {
        final off = planThinking(responses(id));
        expect(off.fields.containsKey('reasoning'), isFalse, reason: id);
        expect(off.hintCode, 'aiThinkingNotForciblyOff', reason: id);
        expect(
          planThinking(responses(id, thinking: true)).fields['reasoning'],
          {'effort': 'high'},
          reason: id,
        );
      }
    });

    test('the o series has no documented off switch', () {
      for (final id in ['o1', 'o3', 'o3-mini', 'o4-mini']) {
        final off = planThinking(responses(id));
        expect(off.fields.containsKey('reasoning'), isFalse, reason: id);
        expect(off.hintCode, 'aiThinkingNotForciblyOff', reason: id);
      }
      expect(
        planThinking(responses('o3-mini', thinking: true)).fields['reasoning'],
        {'effort': 'high'},
      );
    });

    test('non-reasoning ids never get a reasoning field', () {
      for (final id in ['gpt-4o', 'mystery-model', '']) {
        expect(
          planThinking(responses(id)).fields.containsKey('reasoning'),
          isFalse,
          reason: id,
        );
        expect(planThinking(responses(id)).hintCode, isNull, reason: id);
        final on = planThinking(responses(id, thinking: true));
        expect(on.fields.containsKey('reasoning'), isFalse, reason: id);
        expect(on.hintCode, 'aiThinkingUnsupported', reason: id);
      }
    });

    test('effort none reaches only a version that documents it', () {
      final ids = [
        ..._documentedNone,
        'gpt-5.1-2026-02-01',
        'gpt-5',
        'gpt-5-2025-08-07',
        'gpt-5.10',
        'gpt-6-astra',
        ..._unverifiedReasoning,
        'o3',
        'gpt-4o',
      ];
      for (final id in ids) {
        final effort = planThinking(responses(id)).fields['reasoning']?['effort'];
        if (effort != 'none') continue;
        final documented = _documentedNone.any(
          (prefix) => id == prefix || id.startsWith('$prefix-'),
        );
        expect(documented, isTrue, reason: '$id is not documented for none');
      }
    });
  });

  group('DeepSeek thinking extension follows the endpoint, not the name', () {
    test('the official API gets enabled and disabled explicitly', () {
      final on = planThinking(
        cfg(
          provider: 'deepseek',
          base: _deepSeekBase,
          model: 'deepseek-flash',
          thinking: true,
        ),
      );
      expect(on.fields['thinking'], {'type': 'enabled'});
      expect(on.hintCode, isNull);

      final off = planThinking(
        cfg(provider: 'deepseek', base: _deepSeekBase, model: 'deepseek-v4-pro'),
      );
      expect(off.fields['thinking'], {'type': 'disabled'});
      expect(off.hintCode, isNull);
    });

    test('a custom provider pointed at the official host still qualifies', () {
      final plan = planThinking(
        cfg(base: '$_deepSeekBase/v1', model: 'deepseek-flash', thinking: true),
      );
      expect(plan.fields['thinking'], {'type': 'enabled'});
    });

    test('a same-named model on a reverse proxy never gets the extension', () {
      for (final thinking in [true, false]) {
        final plan = planThinking(
          cfg(model: 'deepseek-v4-pro', thinking: thinking),
        );
        expect(plan.fields.containsKey('thinking'), isFalse);
        // The vendor default is thinking-on, so neither position is confirmable.
        expect(plan.hintCode, 'aiThinkingCapabilityUnverified');
      }
      final otherModel = planThinking(
        cfg(provider: 'deepseek', base: _deepSeekBase, model: 'llama-3.3-70b', thinking: true),
      );
      expect(otherModel.fields.containsKey('thinking'), isFalse);
      expect(otherModel.hintCode, 'aiThinkingUnsupported');
    });

    test('volcengine and bailian stay on compatible fields only', () {
      for (final provider in ['volcengine', 'bailian']) {
        final plan = planThinking(
          cfg(provider: provider, model: 'doubao-pro-32k', thinking: true),
        );
        expect(plan.fields, isEmpty, reason: provider);
        expect(plan.hintCode, 'aiThinkingUnsupported', reason: provider);
      }
    });
  });

  group('Anthropic uses the documented model list', () {
    test('Sonnet 5 and Opus 5 can explicitly disable thinking', () {
      for (final id in ['claude-sonnet-5', 'claude-opus-5']) {
        final off = planThinking(anthropic(id));
        expect(off.fields['thinking'], {'type': 'disabled'}, reason: id);
        expect(off.hintCode, isNull, reason: id);
        final on = planThinking(anthropic(id, thinking: true));
        expect(on.fields['thinking'], {'type': 'adaptive'}, reason: id);
        expect(on.fields['output_config'], {'effort': 'high'}, reason: id);
      }
    });

    test('always-on models send no thinking field at either switch position', () {
      for (final id in _alwaysOn) {
        final off = planThinking(anthropic(id));
        expect(off.fields.containsKey('thinking'), isFalse, reason: id);
        expect(off.hintCode, 'aiThinkingAlwaysOn', reason: id);
        final on = planThinking(anthropic(id, thinking: true));
        expect(on.fields.containsKey('thinking'), isFalse, reason: id);
        expect(on.fields['output_config'], {'effort': 'high'}, reason: id);
      }
    });

    test('4.x adaptive models ask for adaptive and omit it when off',
        () {
      for (final id in _adaptive) {
        final on = planThinking(anthropic(id, thinking: true));
        expect(on.fields['thinking'], {'type': 'adaptive'}, reason: id);
        expect(on.fields['output_config'], {'effort': 'high'}, reason: id);
        final off = planThinking(anthropic(id));
        expect(off.fields, isEmpty, reason: id);
        expect(off.hintCode, isNull, reason: id);
      }
    });

    test('manual models keep a budget inside the documented window', () {
      for (final id in _manual) {
        final thinking =
            planThinking(anthropic(id, thinking: true)).fields['thinking'];
        expect(thinking, isNotNull, reason: id);
        expect(thinking!['type'], 'enabled', reason: id);
        final budget = thinking['budget_tokens'];
        expect(budget, isA<int>(), reason: id);
        expect(budget, greaterThanOrEqualTo(1024), reason: id);
        expect(budget, lessThan(8192), reason: id);
        expect(
          planThinking(anthropic(id, thinking: true)).fields.containsKey('output_config'),
          isFalse,
          reason: id,
        );
        final off = planThinking(anthropic(id));
        expect(off.fields, isEmpty, reason: id);
        expect(off.hintCode, isNull, reason: id);
      }
    });

    test('undocumented Claude ids get no vendor parameter', () {
      for (final id in _undocumentedClaude) {
        final on = planThinking(anthropic(id, thinking: true));
        expect(on.fields, isEmpty, reason: id);
        expect(on.hintCode, 'aiThinkingUnsupported', reason: id);
        final off = planThinking(anthropic(id));
        expect(off.fields, isEmpty, reason: id);
        expect(off.hintCode, isNull, reason: id);
      }
    });

    test('a dotted id normalizes to the documented family spelling', () {
      expect(planThinking(anthropic('Claude.Opus.5.5')).hintCode, 'aiThinkingAlwaysOn');
      expect(
        planThinking(anthropic('claude-sonnet-4.6', thinking: true)).fields['thinking'],
        {'type': 'adaptive'},
      );
    });

    test('always-on and unsupported Anthropic models never receive disabled', () {
      for (final id in [..._alwaysOn, ..._adaptive, ..._manual, ..._undocumentedClaude, '']) {
        for (final thinking in [true, false]) {
          final fields = planThinking(anthropic(id, thinking: thinking)).fields;
          expect(
            (fields['thinking'] as Map?)?['type'],
            isNot('disabled'),
            reason: '$id/$thinking',
          );
        }
      }
    });
  });

  group('mock request bodies carry exactly what the model documents', () {
    for (final caseName in [
      'gpt-5',
      'gpt-5.1',
      'gpt-5-mini',
      'o3',
      'official-deepseek',
      'deepseek-alias-on-proxy',
      'claude-known',
      'claude-sonnet-5-off',
      'claude-opus-5-off',
      'claude-unknown',
    ]) {
      test(caseName, () async {
        final capture = _Capture();
        final service = AIService(client: capture.client);
        addTearDown(service.close);
        final config = switch (caseName) {
          'gpt-5' => responses('gpt-5'),
          'gpt-5.1' => responses('gpt-5.1'),
          'gpt-5-mini' => responses('gpt-5-mini'),
          'o3' => responses('o3', thinking: true),
          'official-deepseek' => cfg(
            provider: 'deepseek',
            base: _deepSeekBase,
            model: 'deepseek-flash',
          ),
          'deepseek-alias-on-proxy' => cfg(model: 'deepseek-v4-pro', thinking: true),
          'claude-known' => anthropic('claude-opus-5-5'),
          'claude-sonnet-5-off' => anthropic('claude-sonnet-5'),
          'claude-opus-5-off' => anthropic('claude-opus-5'),
          _ => anthropic('claude-nova-9', thinking: true),
        };
        await service.analyzeTasks(
          inputs: ['Task'],
          config: config,
          language: Language.en,
          autoDecompose: false,
        );
        final body = capture.body!;
        expect(body['model'], config.model);
        expect(capture.requests.last.body, isNot(contains(_key)));
        switch (caseName) {
          case 'gpt-5':
            expect(body['reasoning'], {'effort': 'minimal'});
          case 'gpt-5.1':
            expect(body['reasoning'], {'effort': 'none'});
          case 'gpt-5-mini':
            expect(body.containsKey('reasoning'), isFalse);
            expect(body['text'], {
              'format': {'type': 'json_object'},
            });
          case 'o3':
            expect(body['reasoning'], {'effort': 'high'});
          case 'official-deepseek':
            expect(body['thinking'], {'type': 'disabled'});
          case 'deepseek-alias-on-proxy':
            expect(body.containsKey('thinking'), isFalse);
            expect(body.keys.toSet(), {'model', 'messages', 'response_format'});
          case 'claude-sonnet-5-off':
          case 'claude-opus-5-off':
            expect(body['thinking'], {'type': 'disabled'});
            expect(body.containsKey('output_config'), isFalse);
            expect(body.keys.toSet(), {
              'model', 'max_tokens', 'system', 'messages', 'thinking',
            });
          default:
            expect(body.containsKey('reasoning'), isFalse);
            expect(body.containsKey('thinking'), isFalse);
            expect(body.containsKey('output_config'), isFalse);
            expect(body.keys.toSet(), {'model', 'max_tokens', 'system', 'messages'});
        }
      });
    }
  });

  group('the short probe reports partial results as partial', () {
    const reasoningOnlyResponses = '''
{"status":"incomplete","incomplete_details":{"reason":"max_output_tokens"},
 "output":[{"type":"reasoning","id":"rs_1","summary":[]}]}
''';

    test('reasoning-only is neither an empty reply nor an auth failure', () async {
      final result = await probeReply(
        responses('o3'),
        http.Response(reasoningOnlyResponses, 200),
      );
      expect(result.attempted, isTrue);
      expect(result.ok, isFalse);
      expect(result.code, 'aiGenerationThinkingOnly');
      expect(result.toString(), isNot(contains(_key)));
    });

    test('text cut by the 16-token budget counts as working generation',
        () async {
      final result = await probeReply(
        responses('gpt-5.1'),
        http.Response(
          jsonEncode({
            'status': 'incomplete',
            'incomplete_details': {'reason': 'max_output_tokens'},
            'output_text': 'par',
          }),
          200,
        ),
      );
      expect(result.ok, isTrue);
      expect(result.code, 'aiGenerationPartial');
    });

    test('anthropic thinking blocks and a max_tokens stop are read together',
        () async {
      final thinkingOnly = await probeReply(
        anthropic('claude-sonnet-4-5'),
        http.Response(
          jsonEncode({
            'stop_reason': 'max_tokens',
            'content': [
              {'type': 'thinking', 'thinking': 'hmm', 'signature': 'sig'},
            ],
          }),
          200,
        ),
      );
      expect(thinkingOnly.ok, isFalse);
      expect(thinkingOnly.code, 'aiGenerationThinkingOnly');

      final truncatedText = await probeReply(
        anthropic('claude-sonnet-4-5'),
        http.Response(
          jsonEncode({
            'stop_reason': 'max_tokens',
            'content': [
              {'type': 'text', 'text': 'pi'},
            ],
          }),
          200,
        ),
      );
      expect(truncatedText.ok, isTrue);
      expect(truncatedText.code, 'aiGenerationPartial');
    });

    test('chat reasoning_content with finish length is a partial reply', () async {
      final reasoningOnly = await probeReply(
        cfg(model: 'deepseek-flash', base: _deepSeekBase, provider: 'deepseek'),
        http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': '', 'reasoning_content': 'thinking'},
                'finish_reason': 'length',
              },
            ],
          }),
          200,
        ),
      );
      expect(reasoningOnly.code, 'aiGenerationThinkingOnly');

      final answered = await probeReply(
        cfg(),
        http.Response(
          jsonEncode({
            'choices': [
              {'message': {'content': 'pong'}, 'finish_reason': 'stop'},
            ],
          }),
          200,
        ),
      );
      expect(answered.ok, isTrue);
      expect(answered.code, 'aiGenerationOk');
    });

    test('a 200 that held nothing stays empty, and 401 stays unauthorized',
        () async {
      final empty = await probeReply(
        cfg(),
        http.Response(
          jsonEncode({
            'choices': [
              {'message': {'content': '   '}, 'finish_reason': 'stop'},
            ],
          }),
          200,
        ),
      );
      expect(empty.ok, isFalse);
      expect(empty.code, 'aiGenerationEmpty');

      final denied = await probeReply(
        responses('o3'),
        http.Response('{"error":"$_key"}', 401),
      );
      expect(denied.code, 'aiUnauthorized');
      expect(denied.status, 401);
      expect(denied.toString(), isNot(contains(_key)));
    });

    test('a body that is not an object stays an invalid response', () async {
      expect(
        () => classifyGenerationProbe(AIProtocol.openaiResponses, 'nope'),
        throwsA(isA<AIException>()),
      );
      final result = await probeReply(
        responses('o3'),
        http.Response('$_key is not json', 200),
      );
      expect(result.code, 'aiInvalidResponse');
      expect(result.toString(), isNot(contains(_key)));
    });

    test('the classifier reads a complete answer as success', () {
      expect(
        classifyGenerationProbe(AIProtocol.openaiResponses, {
          'status': 'completed',
          'output_text': 'pong',
        }).code,
        'aiGenerationOk',
      );
      expect(
        classifyGenerationProbe(AIProtocol.anthropic, {
          'stop_reason': 'end_turn',
          'content': [
            {'type': 'text', 'text': 'pong'},
          ],
        }).code,
        'aiGenerationOk',
      );
    });

    testWidgets('the connection panel shows the partial result and keeps the fee note',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        'matrixflow-has-seen-onboarding': true,
      });
      final service = AIService(
        client: MockClient((request) async {
          if (request.method == 'GET') {
            return http.Response(jsonEncode({'data': [{'id': 'o3'}]}), 200);
          }
          return http.Response(reasoningOnlyResponses, 200);
        }),
      );
      addTearDown(service.close);
      late Store store;
      // The Store's reminder timer must live outside the fake-async zone, or
      // the framework reports it as a leak at teardown.
      await tester.runAsync(() async {
        store = Store(aiService: service);
        await store.init();
        await store.updateAIConfig(
          store.copyAIConfig()
            ..protocol = AIProtocol.openaiResponses
            ..baseUrl = _customBase
            ..apiKey = _key
            ..model = 'o3',
        );
      });
      addTearDown(store.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: TestConnectionButton(t: store.t, store: store),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('test-generation-btn')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('generation-billing-confirm')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('connection-generation-status')),
            )
            .data,
        contains(store.t['aiGenerationThinkingOnly']),
      );
      // The call that produced this partial answer was confirmed as billable,
      // and a truncated reply does not retire that notice.
      expect(find.text(store.t['testGenerationBilling']!), findsOneWidget);
    });
  });

  group('capability hints resolve in every language', () {
    test('each documented hint code has copy', () {
      const codes = [
        'aiThinkingUnsupported',
        'aiThinkingAlwaysOn',
        'aiThinkingNotForciblyOff',
        'aiThinkingLowestEffort',
        'aiThinkingCapabilityUnverified',
        'aiGenerationPartial',
        'aiGenerationThinkingOnly',
      ];
      for (final language in Language.values) {
        final dict = dictOf(language);
        for (final code in codes) {
          expect(dict[code], isNotEmpty, reason: '${language.name}.$code');
          expect(dict[code], isNot(contains(_key)), reason: '${language.name}.$code');
        }
      }
    });

    test('plans only emit hint codes the dictionaries define', () {
      final defined = dictOf(Language.en).keys.toSet();
      final configs = <AIConfig>[
        for (final id in [
          ..._documentedNone,
          ..._unverifiedReasoning,
          'gpt-5',
          'gpt-6-astra',
          'o3',
          'gpt-4o',
        ])
          for (final thinking in [true, false]) responses(id, thinking: thinking),
        for (final id in [..._alwaysOn, ..._adaptive, ..._manual, ..._undocumentedClaude])
          for (final thinking in [true, false]) anthropic(id, thinking: thinking),
        for (final thinking in [true, false]) cfg(
          provider: 'deepseek',
          base: _deepSeekBase,
          model: 'deepseek-flash',
          thinking: thinking,
        ),
        for (final thinking in [true, false]) cfg(
          model: 'deepseek-v4-pro',
          thinking: thinking,
        ),
        for (final thinking in [true, false]) cfg(thinking: thinking),
      ];
      for (final config in configs) {
        final hint = planThinking(config).hintCode;
        if (hint != null) expect(defined, contains(hint));
      }
    });
  });
}
