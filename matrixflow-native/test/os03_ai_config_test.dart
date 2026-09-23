import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrixflow_native/ai_presets.dart';
import 'package:matrixflow_native/ai_service.dart';
import 'package:matrixflow_native/l10n.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/screens/settings_screen.dart';
import 'package:matrixflow_native/storage.dart';
import 'package:provider/provider.dart';

import 'helpers.dart';

Widget settingsApp(Store store) => ChangeNotifierProvider.value(
  value: store,
  child: const MaterialApp(home: SettingsScreen()),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('new install uses the single DeepSeek preset default', () {
    final preset = getAIProviderPreset('deepseek');
    expect(preset.defaultModel, 'deepseek-flash');
    expect(AIConfig().model, preset.defaultModel);
    expect(AIConfig.fromJson({}).model, preset.defaultModel);
    expect(
      pickPreferredModel('deepseek', ['deepseek-v4-flash', 'deepseek-flash']),
      preset.defaultModel,
    );
  });

  test('old explicit DeepSeek default migrates, custom names survive', () {
    final old = AIConfig.fromJson({
      'providerId': 'deepseek',
      'protocol': 'openai',
      'customBaseUrl': 'https://api.deepseek.com',
      'customModel': 'deepseek-v4-flash',
    });
    expect(old.model, 'deepseek-flash');
    final legacy = AIConfig.fromJson({
      'provider': 'openai',
      'customBaseUrl': 'https://api.deepseek.com',
      'customModel': 'deepseek-v4-flash',
    });
    expect(legacy.provider, 'deepseek');
    expect(legacy.model, 'deepseek-flash');
    for (final name in ['gpt-4o-mini', 'deepseek-v4-flash']) {
      final custom = AIConfig(
        provider: 'custom',
        baseUrl: 'https://example.invalid/v1',
        model: name,
      );
      expect(
        AIConfig.fromJson(custom.toJson()).model,
        name,
        reason: 'OS-R03: $name',
      );
    }
    expect(
      AIConfig.fromJson({
        'providerId': 'deepseek',
        'customBaseUrl': 'https://gateway.invalid/v1',
        'customModel': 'deepseek-v4-flash',
      }).model,
      'deepseek-v4-flash',
    );
  });

  test(
    'old v1 backup decodes the DeepSeek default without changing its format',
    () {
      final backup = ExportData.fromJson({
        'version': 1,
        'boards': <Map<String, dynamic>>[],
        'tasks': <Map<String, dynamic>>[],
        'aiConfig': {
          'provider': 'openai',
          'customBaseUrl': 'https://api.deepseek.com',
          'customModel': 'deepseek-v4-flash',
        },
      });
      expect(backup.aiConfig.provider, 'deepseek');
      expect(backup.aiConfig.model, 'deepseek-flash');
    },
  );

  test('unknown provider and parsed host preserve custom values', () {
    final unknown = AIConfig.fromJson({
      'providerId': 'future-provider',
      'protocol': 'openai',
      'customBaseUrl': 'https://api.deepseek.com.proxy.invalid/v1',
      'customModel': 'model-one',
    });
    expect(unknown.provider, 'custom');
    expect(unknown.baseUrl, 'https://api.deepseek.com.proxy.invalid/v1');
    expect(unknown.model, 'model-one');
    expect(AIConfig.fromJson(unknown.toJson()).toJson(), unknown.toJson());
    for (final url in [
      'https://example.invalid/path/api.deepseek.com',
      'https://api.deepseek.com.evil.invalid/v1',
      'https://example.invalid/?next=api.deepseek.com',
    ]) {
      expect(AIConfig.fromJson({'customBaseUrl': url}).provider, 'custom');
    }
    expect(
      AIConfig.fromJson({
        'customBaseUrl': 'https://api.deepseek.com/v1',
      }).provider,
      'deepseek',
    );
  });

  test('empty model uses preset default only for matching protocol', () {
    expect(
      AIConfig.fromJson({'providerId': 'bailian', 'customModel': ''}).model,
      'qwen-plus',
    );
    for (final protocol in AIProtocol.values) {
      expect(
        AIConfig.fromJson({
          'providerId': 'custom',
          'protocol': AIProtocolX.toWire(protocol),
          'customBaseUrl': 'https://example.invalid',
          'customModel': '',
        }).model,
        isEmpty,
      );
    }
    expect(
      AIConfig.fromJson({
        'providerId': 'deepseek',
        'protocol': 'openai-responses',
        'customModel': '',
      }).model,
      isEmpty,
    );
  });

  test(
    'three protocol configs round-trip and send the selected model',
    () async {
      final seen = <String>[];
      final service = AIService(
        client: MockClient((request) async {
          seen.add(
            (jsonDecode(request.body) as Map<String, dynamic>)['model']
                as String,
          );
          final payload =
              request.url.path.endsWith('/chat/completions')
                  ? {
                    'choices': [
                      {
                        'message': {'content': 'ok'},
                      },
                    ],
                  }
                  : request.url.path.endsWith('/responses')
                  ? {
                    'output': [
                      {
                        'type': 'message',
                        'content': [
                          {'type': 'output_text', 'text': 'ok'},
                        ],
                      },
                    ],
                  }
                  : {
                    'content': [
                      {'type': 'text', 'text': 'ok'},
                    ],
                  };
          return http.Response(jsonEncode(payload), 200);
        }),
      );
      addTearDown(service.close);
      for (final protocol in AIProtocol.values) {
        final original = AIConfig(
          provider: 'custom',
          protocol: protocol,
          baseUrl: 'https://example.invalid/v1',
          apiKey: 'synthetic',
          model: 'chosen-${protocol.name}',
        );
        final restored = AIConfig.fromJson(original.toJson());
        expect(restored.toJson(), original.toJson());
        await service.requestCompletion(
          config: restored,
          systemInstruction: 's',
          userPrompt: 'u',
          forceJsonObject: false,
        );
        expect(seen.last, restored.model);
      }
    expect(seen, [
      'chosen-openai',
      'chosen-openaiResponses',
      'chosen-anthropic',
    ]);
    final spaced = AIConfig(
      provider: 'custom',
      baseUrl: 'https://example.invalid/v1',
      apiKey: 'synthetic',
      model: ' selected-model ',
    );
    await service.requestCompletion(
      config: AIConfig.fromJson(spaced.toJson()),
      systemInstruction: 's',
      userPrompt: 'u',
      forceJsonObject: false,
    );
    expect(seen.last, spaced.model);
    },
  );

  test('empty custom model reports an error before sending', () async {
    var calls = 0;
    final service = AIService(
      client: MockClient((request) async {
        calls++;
        return http.Response('{}', 200);
      }),
    );
    addTearDown(service.close);
    for (final protocol in AIProtocol.values) {
      await expectLater(
        service.requestCompletion(
          config: AIConfig(
            provider: 'custom',
            protocol: protocol,
            baseUrl: 'https://example.invalid',
            apiKey: 'synthetic',
            model: '',
          ),
          systemInstruction: 's',
          userPrompt: 'u',
          forceJsonObject: false,
        ),
        throwsA(
          isA<AIException>().having((e) => e.code, 'code', 'aiMissingModel'),
        ),
      );
    }
    expect(calls, 0);
  });

  testWidgets(
    'OS-R05 unknown provider opens settings and request matches model field',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final (store, _) = await makeStore();
      store.importData({
        'version': 2,
        'boards': store.boards.map((b) => b.toJson()).toList(),
        'tasks': [],
        'aiConfig': {
          'providerId': 'future-provider',
          'protocol': 'openai',
          'customBaseUrl': 'https://example.invalid',
          'customModel': 'test-model',
        },
      }, 'overwrite');
      await tester.pumpWidget(settingsApp(store));
      expect(tester.takeException(), isNull);
      expect(store.aiConfig.provider, 'custom');
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('provider-selector')),
        350,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        tester
            .widget<DropdownButton<String>>(
              find.byKey(const ValueKey('provider-selector')),
            )
            .value,
        'custom',
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('model-input')),
        350,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('model-input')))
            .controller!
            .text,
        'test-model',
      );
      final models = <String>[];
      final service = AIService(
        client: MockClient((request) async {
          models.add(
            (jsonDecode(request.body) as Map<String, dynamic>)['model']
                as String,
          );
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {'content': 'ok'},
                },
              ],
            }),
            200,
          );
        }),
      );
      await service.requestCompletion(
        config: store.aiConfig..apiKey = 'synthetic',
        systemInstruction: 's',
        userPrompt: 'u',
        forceJsonObject: false,
      );
      expect(models.single, 'test-model');
      service.close();
      await tester.pumpWidget(const SizedBox.shrink());
      store.dispose();
    },
  );

  test('en/zh/ja recommendation reflects default without accuracy promise', () {
    for (final language in Language.values) {
      final tip = dictOf(language)['aiRecommendTip']!;
      expect(tip, contains(getAIProviderPreset('deepseek').defaultModel));
      expect(tip, isNot(contains('deepseek-v4-flash')));
      expect(tip, isNot(contains('最高')));
      expect(tip, isNot(contains('highest')));
      expect(tip, isNot(contains('最高の精度')));
      expect(dictOf(language)['aiMissingModel'], isNotEmpty);
    }
  });
}
