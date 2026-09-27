import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrixflow_native/ai_service.dart';
import 'package:matrixflow_native/models.dart';

AIConfig cfg([String protocol = 'openai', String model = 'm']) =>
    AIConfig.fromJson({
      'provider': protocol,
      'customBaseUrl': 'https://api.test.com',
      'customApiKey': 'k',
      'customModel': model,
      'enableThinking': true,
    });

http.Response jsonResp(Map<String, dynamic> json) =>
    http.Response.bytes(utf8.encode(jsonEncode(json)), 200, headers: {
      'content-type': 'application/json',
    });

void main() {
  group('protocol request shapes', () {
    test('openai: posts chat/completions with system+user and json_object', () async {
      Uri? captured;
      late Map<String, String> headers;
      late Map<String, dynamic> body;
      final service = AIService(
        client: MockClient((req) async {
          captured = req.url;
          headers = req.headers;
          body = jsonDecode(req.body) as Map<String, dynamic>;
          return jsonResp({
            'choices': [
              {'message': {'content': '[{"title":"买牛奶","quadrant":3,"isLongTerm":false}]'}}
            ]
          });
        }),
      );

      final result = await service.analyzeTasks(
        inputs: ['买牛奶'],
        config: cfg('openai'),
        language: Language.zh,
        autoDecompose: false,
      );

      expect(captured.toString(), 'https://api.test.com/chat/completions');
      expect(headers['authorization'], 'Bearer k');
      expect(body['response_format'], {'type': 'json_object'});
      expect(body.containsKey('thinking'), isFalse);
      expect(body['messages'][0]['role'], 'system');
      expect(result.single.title, '买牛奶');
      expect(result.single.quadrant, 3);
    });

    test('openai-responses: posts /responses with instructions+input, parses output[]', () async {
      Uri? captured;
      late Map<String, dynamic> body;
      final service = AIService(
        client: MockClient((req) async {
          captured = req.url;
          body = jsonDecode(req.body) as Map<String, dynamic>;
          return jsonResp({
            'output': [
              {
                'type': 'message',
                'content': [
                  {'type': 'output_text', 'text': '[{"title":"A","quadrant":1,"isLongTerm":false}]'}
                ]
              }
            ]
          });
        }),
      );

      final result = await service.analyzeTasks(
        inputs: ['A'],
        config: cfg('openai-responses', 'o3-mini'),
        language: Language.en,
        autoDecompose: false,
      );

      expect(captured.toString(), 'https://api.test.com/responses');
      expect(body['instructions'], contains('Eisenhower'));
      expect(body['input'], contains('A'));
      expect(body.containsKey('reasoning'), isFalse);
      expect(body['text']['format'], {'type': 'json_object'});
      expect(result.single.title, 'A');
    });

    test('anthropic: posts /v1/messages with x-api-key + version + system, parses content[]', () async {
      Uri? captured;
      late Map<String, String> headers;
      late Map<String, dynamic> body;
      final service = AIService(
        client: MockClient((req) async {
          captured = req.url;
          headers = req.headers;
          body = jsonDecode(req.body) as Map<String, dynamic>;
          return jsonResp({
            'content': [
              {'type': 'text', 'text': '```json\n[{"title":"B","quadrant":"Q2","isLongTerm":true,"subtasks":["s1"]}]```'}
            ]
          });
        }),
      );

      final result = await service.analyzeTasks(
        inputs: ['B'],
        config: cfg('anthropic', 'claude-sonnet-4-6'),
        language: Language.ja,
        autoDecompose: false,
      );

      expect(captured.toString(), 'https://api.test.com/v1/messages');
      expect(headers['x-api-key'], 'k');
      expect(headers['anthropic-version'], '2023-06-01');
      expect(body['system'], contains('Eisenhower'));
      expect(body['max_tokens'], 8192);
      expect(body['thinking'], {'type': 'adaptive'});
      expect(body['output_config'], {'effort': 'high'});
      expect(body.containsKey('response_format'), isFalse);
      // fence stripping + Q-string quadrant + long-term flag all survive
      expect(result.single.title, 'B');
      expect(result.single.quadrant, 2);
      expect(result.single.isLongTerm, isTrue);
      expect(result.single.subtasks, ['s1']);
    });

    test('thinking off sends only the fields each endpoint documents', () async {
      late Map<String, dynamic> openAiBody;
      late Map<String, dynamic> responsesBody;
      late Map<String, dynamic> anthropicBody;

      final service = AIService(
        client: MockClient((req) async {
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          if (req.url.path.contains('completions')) {
            openAiBody = body;
            return jsonResp({'choices': [{'message': {'content': '[{"title":"X","quadrant":1,"isLongTerm":false}]'}}]});
          } else if (req.url.path.contains('responses')) {
            responsesBody = body;
            return jsonResp({'output': [{'type': 'message', 'content': [{'type': 'output_text', 'text': '[{"title":"X","quadrant":1,"isLongTerm":false}]'}]}]});
          } else {
            anthropicBody = body;
            return jsonResp({'content': [{'type': 'text', 'text': '[{"title":"X","quadrant":1,"isLongTerm":false}]'}]});
          }
        }),
      );

      // A model id that merely looks like DeepSeek's is no proof the endpoint
      // understands the vendor extension, so this custom endpoint gets
      // compatible fields only. The official API still sends `disabled`
      // (ai_regression_test.dart).
      final aliasOnProxy = cfg('openai', 'deepseek-flash')..enableThinking = false;
      await service.analyzeTasks(inputs: ['X'], config: aliasOnProxy, language: Language.en, autoDecompose: false);
      expect(openAiBody.containsKey('thinking'), isFalse);

      final disabledResponses = cfg('openai-responses', 'gpt-5.1')..enableThinking = false;
      await service.analyzeTasks(inputs: ['X'], config: disabledResponses, language: Language.en, autoDecompose: false);
      expect(responsesBody['reasoning'], {'effort': 'none'});

      // Manual extended thinking is opt-in and `type: disabled` is not
      // documented for it, so off omits the field.
      final disabledAnthropic = cfg('anthropic', 'claude-sonnet-4-5')..enableThinking = false;
      await service.analyzeTasks(inputs: ['X'], config: disabledAnthropic, language: Language.en, autoDecompose: false);
      expect(anthropicBody.containsKey('thinking'), isFalse);
      expect(anthropicBody.containsKey('output_config'), isFalse);
    });

    test('decomposeBatch maps originalTitle/subtasks', () async {
      final service = AIService(
        client: MockClient((req) async => jsonResp({
              'choices': [
                {'message': {'content': '[{"originalTitle":"A","subtasks":["a1","a2"]}]'}}
              ]
            })),
      );

      final result = await service.decomposeBatch(
        taskTitles: ['A'],
        config: cfg(),
        language: Language.en,
      );
      expect(result.single.originalTitle, 'A');
      expect(result.single.subtasks, ['a1', 'a2']);
    });
  });

  group('error paths', () {
    test('missing config throws', () async {
      final service = AIService(
        client: MockClient((req) async => jsonResp({})),
      );
      await expectLater(
        service.requestCompletion(
          config: AIConfig(baseUrl: '', apiKey: ''),
          systemInstruction: 's',
          userPrompt: 'u',
          forceJsonObject: true,
        ),
        throwsException,
      );
    });

    test('HTTP error surfaces status + body snippet', () async {
      final service = AIService(
        client: MockClient((req) async => http.Response('{"error":"bad key"}', 401)),
      );
      await expectLater(
        service.analyzeTasks(
          inputs: ['x'],
          config: cfg(),
          language: Language.en,
          autoDecompose: false,
        ),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('401'),
        )),
      );
    });
  });

  group('extractJsonArray robustness', () {
    test('handles fenced, plain, object-wrapped and garbage', () {
      expect(extractJsonArray('```json\n[{"a":1}]\n```'), hasLength(1));
      expect(extractJsonArray('[{"a":1}]'), hasLength(1));
      expect(extractJsonArray('{"tasks":[{"a":1}]}'), hasLength(1));
      expect(extractJsonArray('no json here'), isEmpty);
      expect(extractJsonArray(''), isEmpty);
    });
  });
}
