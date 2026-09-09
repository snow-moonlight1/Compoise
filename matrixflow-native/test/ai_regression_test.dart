import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrixflow_native/ai_service.dart';
import 'package:matrixflow_native/models.dart';

AIConfig config({AIProtocol protocol = AIProtocol.openai, String? base}) =>
    AIConfig(
      protocol: protocol,
      baseUrl: base ?? 'https://example.test',
      apiKey: 'test-key',
    );

Future<List<AIAnalysisResult>> analyze(
  AIService service, {
  AIConfig? cfg,
  AICancellation? cancel,
}) => service.analyzeTasks(
  inputs: ['test'],
  config: cfg ?? config(),
  language: Language.en,
  autoDecompose: true,
  cancellation: cancel,
);

http.Response reply(String text) => http.Response(
  jsonEncode({
    'choices': [
      {
        'message': {'content': text},
      },
    ],
  }),
  200,
);

void main() {
  test(
    'Anthropic /v1 base does not duplicate version in completion or probe',
    () async {
      final paths = <String>[];
      final service = AIService(
        client: MockClient((request) async {
          paths.add(request.url.path);
          if (request.method == 'GET') return http.Response('{}', 404);
          return http.Response(
            jsonEncode({
              'content': [
                {'type': 'text', 'text': '[{"title":"test","quadrant":1}]'},
              ],
            }),
            200,
          );
        }),
      );
      addTearDown(service.close);
      final cfg = config(
        protocol: AIProtocol.anthropic,
        base: 'https://example.test/v1/',
      );
      await analyze(service, cfg: cfg);
      expect((await service.testConnection(cfg)).ok, isTrue);
      expect(paths, ['/v1/messages', '/v1/models', '/v1/messages']);
    },
  );

  test(
    'classification prompt names urgency/importance and omits action labels',
    () async {
      late String system;
      final service = AIService(
        client: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          system = body['messages'][0]['content'] as String;
          return reply(
            '[{"title":"a","quadrant":1},{"title":"b","quadrant":2},{"title":"c","quadrant":3},{"title":"d","quadrant":4}]',
          );
        }),
      );
      addTearDown(service.close);
      final results = await analyze(service);
      expect(system, contains('Urgent and Important'));
      expect(system, contains('Not Urgent but Important'));
      expect(system, contains('Urgent but Not Important'));
      expect(system, contains('Neither Urgent nor Important'));
      expect(system, isNot(contains('Do First')));
      expect(system, isNot(contains('(Schedule)')));
      expect(system, isNot(contains('(Delegate)')));
      expect(system, isNot(contains("Don't Do")));
      expect(system, isNot(contains('Delete)')));
      expect(system, contains('DO NOT include opinions, advice, preaching'));
      expect(results.map((item) => item.quadrant), [1, 2, 3, 4]);
    },
  );

  test('automatic decomposition is distinct from grouping', () async {
    final service = AIService(
      client: MockClient((request) async {
        final body = jsonDecode(request.body);
        expect(body['messages'][0]['content'], contains('JSON object'));
        return reply(
          '[{"title":"project","quadrant":2,"isLongTerm":true,"subtasks":["step"]}]',
        );
      }),
    );
    addTearDown(service.close);
    final results = await analyze(service);
    expect(results.single.isGrouped, isFalse);
    expect(results.single.subtasks.single, 'step');
  });

  for (final content in [
    '[]',
    '[{"title":"ok"},null]',
    '[{"title":"x","subtasks":[{"title":"bad"}]}]',
    '[{"title":"   "}]',
  ]) {
    test(
      'invalid or partially invalid classification fails atomically: $content',
      () async {
        final service = AIService(
          client: MockClient((_) async => reply(content)),
        );
        addTearDown(service.close);
        await expectLater(analyze(service), throwsA(isA<AIException>()));
      },
    );
  }

  test('empty response choices produce a controlled error', () {
    expect(
      () => extractResponseText(AIProtocol.openai, {'choices': []}),
      throwsA(isA<AIException>()),
    );
  });

  test(
    'missing decomposition titles fail instead of partially applying',
    () async {
      final service = AIService(
        client: MockClient(
          (_) async => reply('[{"originalTitle":"a","subtasks":["step"]}]'),
        ),
      );
      addTearDown(service.close);
      await expectLater(
        service.decomposeBatch(
          taskTitles: ['a', 'b'],
          config: config(),
          language: Language.en,
        ),
        throwsA(isA<AIException>()),
      );
    },
  );

  test('HTTP errors never include the raw response body', () async {
    final service = AIService(
      client: MockClient(
        (_) async => http.Response('server echoed private-content-marker', 401),
      ),
    );
    addTearDown(service.close);
    await expectLater(
      analyze(service),
      throwsA(
        isA<AIException>()
            .having((error) => error.status, 'status', 401)
            .having(
              (error) => error.toString(),
              'message',
              isNot(contains('private-content-marker')),
            ),
      ),
    );
  });

  test('invalid URL is rejected before sending requests', () async {
    var sent = false;
    final service = AIService(
      client: MockClient((_) async {
        sent = true;
        return reply('[]');
      }),
    );
    addTearDown(service.close);
    expect(
      (await service.testConnection(config(base: 'ftp://example.test'))).ok,
      isFalse,
    );
    await expectLater(
      analyze(service, cfg: config(base: 'https://example.test?token=x')),
      throwsA(isA<AIException>()),
    );
    expect(sent, isFalse);
  });

  testWidgets(
    '30 second timeout covers both headers and body and aborts transport',
    (tester) async {
      final headers = Completer<http.StreamedResponse>();
      final body = StreamController<List<int>>();
      var aborted = false;
      final service = AIService(
        client: MockClient.streaming((request, _) {
          (request as http.Abortable).abortTrigger!.then((_) => aborted = true);
          return headers.future;
        }),
      );
      final pending = expectLater(
        analyze(service),
        throwsA(isA<TimeoutException>()),
      );
      await tester.pump(const Duration(seconds: 20));
      headers.complete(http.StreamedResponse(body.stream, 200));
      await tester.pump();
      await tester.pump(const Duration(seconds: 10));
      await pending;
      expect(aborted, isTrue);
      await body.close();
      service.close();
    },
  );

  testWidgets('cancel signal is forwarded to the HTTP transport', (
    tester,
  ) async {
    final pendingResponse = Completer<http.StreamedResponse>();
    final service = AIService(
      client: MockClient.streaming((request, _) {
        (request as http.Abortable).abortTrigger!.then(
          (_) => pendingResponse.completeError(http.RequestAbortedException()),
        );
        return pendingResponse.future;
      }),
    );
    final cancel = AICancellation();
    final pending = expectLater(
      analyze(service, cancel: cancel),
      throwsA(isA<http.RequestAbortedException>()),
    );
    await tester.pump();
    cancel.cancel();
    await tester.pump();
    await pending;
    service.close();
  });
}
