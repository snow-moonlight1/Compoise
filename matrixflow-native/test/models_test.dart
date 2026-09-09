import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/l10n.dart';
import 'package:matrixflow_native/models.dart';

void main() {
  group('Task JSON round-trip', () {
    test('preserves all fields', () {
      final task = Task(
        id: 't1',
        boardId: 'b1',
        title: '写周报',
        quadrant: qPlan,
        isLongTerm: true,
        createdAt: 1700000000000,
        deadline: 1700001000000,
        reasoning: '需要拆解',
        subtasks: [
          SubTask(id: 's1', title: '收集数据', completed: true, deadline: 1700000500000),
          SubTask(id: 's2', title: '撰写'),
        ],
      );
      final restored = Task.fromJson(task.toJson());
      expect(restored.id, 't1');
      expect(restored.boardId, 'b1');
      expect(restored.title, '写周报');
      expect(restored.quadrant, qPlan);
      expect(restored.isLongTerm, isTrue);
      expect(restored.deadline, 1700001000000);
      expect(restored.reasoning, '需要拆解');
      expect(restored.subtasks.length, 2);
      expect(restored.subtasks.first.completed, isTrue);
      expect(restored.subtasks.first.deadline, 1700000500000);
    });

    test('tolerates missing optional fields (old exports)', () {
      final restored = Task.fromJson({'id': 't2', 'title': 'x'});
      expect(restored.quadrant, qEliminate);
      expect(restored.completed, isFalse);
      expect(restored.subtasks, isEmpty);
    });
  });

  group('AIConfig legacy migration', () {
    test('custom maps to openai', () {
      final cfg = AIConfig.fromJson({
        'provider': 'custom',
        'customBaseUrl': 'https://api.deepseek.com',
        'customApiKey': 'k',
        'customModel': 'deepseek-v4-flash',
      });
      expect(cfg.protocol, AIProtocol.openai);
      expect(cfg.baseUrl, 'https://api.deepseek.com');
      expect(cfg.model, 'deepseek-v4-flash');
    });

    test('gemini maps to openai', () {
      final cfg = AIConfig.fromJson({'provider': 'gemini'});
      expect(cfg.protocol, AIProtocol.openai);
    });

    test('wire round-trip for all three protocols', () {
      for (final p in AIProtocol.values) {
        expect(AIProtocolX.fromString(AIProtocolX.toWire(p)), p);
      }
    });

    test('defaults and round-trip for enableThinking, baseUrl, model', () {
      final defaultCfg = AIConfig();
      expect(defaultCfg.enableThinking, isFalse);
      expect(defaultCfg.baseUrl, 'https://api.deepseek.com');
      expect(defaultCfg.model, 'deepseek-v4-flash');
      expect(defaultCfg.toJson()['enableThinking'], isFalse);

      final enabledCfg = AIConfig.fromJson({'enableThinking': true});
      expect(enabledCfg.enableThinking, isTrue);
      expect(enabledCfg.toJson()['enableThinking'], isTrue);
    });
  });

  group('normalizeQuadrant', () {
    test('accepts ints and Q-strings, defaults invalid to eliminate', () {
      expect(normalizeQuadrant(1), qDo);
      expect(normalizeQuadrant('3'), qDelegate);
      expect(normalizeQuadrant('Q2'), qPlan);
      expect(normalizeQuadrant(9), qEliminate);
      expect(normalizeQuadrant(null), qEliminate);
    });
  });

  group('quadrant labels', () {
    test('keep urgency and importance in zh/en/ja without action short names', () {
      const expected = {
        Language.zh: {
          'q1': '紧急且重要',
          'q2': '不紧急但重要',
          'q3': '紧急但不重要',
          'q4': '不紧急也不重要',
        },
        Language.en: {
          'q1': 'Urgent and Important',
          'q2': 'Not Urgent but Important',
          'q3': 'Urgent but Not Important',
          'q4': 'Neither Urgent nor Important',
        },
        Language.ja: {
          'q1': '緊急かつ重要',
          'q2': '緊急でないが重要',
          'q3': '緊急だが重要ではない',
          'q4': '緊急でも重要でもない',
        },
      };
      for (final language in Language.values) {
        final t = dictOf(language);
        expected[language]!.forEach((key, value) {
          expect(t[key], value);
          expect(t['${key}Short'], value);
        });
        expect(t['q1Short'], isNot(anyOf('Do', '马上做', 'すぐやる')));
        expect(t['q4'], isNot(contains('不要做')));
        expect(t['q4'], isNot(contains("Don't Do")));
        expect(t['q2'], contains(language == Language.en ? 'Not' : language == Language.zh ? '不' : 'ない'));
        expect(t['q3'], contains(language == Language.en ? 'Not' : language == Language.zh ? '不' : 'ない'));
        expect(t['q4'], contains(language == Language.en ? 'nor' : language == Language.zh ? '不' : 'ない'));
      }
    });
  });

  group('ExportData', () {
    test('web-compatible shape', () {
      final json = ExportData(
        boards: [Board(id: 'b1', name: 'My Tasks', createdAt: 1)],
        tasks: [Task(id: 't1', boardId: 'b1', title: 'x', quadrant: 1, createdAt: 1)],
        settings: AppSettings(),
        aiConfig: AIConfig(),
      ).toJson();
      expect(json['version'], 1);
      expect(json['boards'], isA<List>());
      expect(json['tasks'], isA<List>());
      expect(json['settings'], isA<Map>());
      expect(json['aiConfig'], isA<Map>());
    });
  });
}
