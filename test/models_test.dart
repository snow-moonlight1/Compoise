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
      expect(restored.urgencyMode, UrgencyMode.auto);
      expect(restored.notesMarkdown, isNull);

      final taskWithNotes = Task(
        id: 't-notes',
        boardId: 'b1',
        title: '任务备注测试',
        quadrant: qDo,
        createdAt: 1700000000000,
        notesMarkdown: '这是父任务详细纯文本备注\n第二行内容',
        subtasks: [
          SubTask(
            id: 's-notes',
            title: '子任务A',
            notesMarkdown: '子任务备注详情',
          ),
        ],
      );
      final restoredWithNotes = Task.fromJson(taskWithNotes.toJson());
      expect(restoredWithNotes.notesMarkdown, '这是父任务详细纯文本备注\n第二行内容');
      expect(restoredWithNotes.subtasks.first.notesMarkdown, '子任务备注详情');

      // v2 export retains notesMarkdown
      final v2Json = taskWithNotes.toJson(targetVersion: 2);
      expect(v2Json['notesMarkdown'], '这是父任务详细纯文本备注\n第二行内容');
      expect((v2Json['subtasks'] as List).first['notesMarkdown'], '子任务备注详情');

      // v1 downgrade export strips notesMarkdown from parent and subtasks
      final v1Json = taskWithNotes.toJson(targetVersion: 1);
      expect(v1Json.containsKey('notesMarkdown'), isFalse);
      expect((v1Json['subtasks'] as List).first.containsKey('notesMarkdown'), isFalse);

      final manualTask = Task(
        id: 't-manual',
        boardId: 'b1',
        title: '手动紧急',
        quadrant: qDo,
        createdAt: 1700000000000,
        urgencyMode: UrgencyMode.manual,
      );
      final restoredManual = Task.fromJson(manualTask.toJson());
      expect(restoredManual.urgencyMode, UrgencyMode.manual);
      expect(manualTask.toJson(targetVersion: 2)['urgencyMode'], 'manual');
      expect(manualTask.toJson(targetVersion: 1).containsKey('urgencyMode'), isFalse);

      final reminderTask = Task(
        id: 't-reminder',
        boardId: 'b1',
        title: '准时提醒测试',
        quadrant: qPlan,
        createdAt: 1700000000000,
        reminderAt: 1700005000000,
        reminderTimezone: 'Asia/Shanghai',
        subtasks: [
          SubTask(
            id: 's-reminder',
            title: '子任务提醒',
            reminderAt: 1700004000000,
          ),
        ],
      );
      final restoredReminder = Task.fromJson(reminderTask.toJson());
      expect(restoredReminder.reminderAt, 1700005000000);
      expect(restoredReminder.reminderTimezone, 'Asia/Shanghai');
      expect(restoredReminder.subtasks.first.reminderAt, 1700004000000);

      // v2 export retains reminderAt and reminderTimezone
      final reminderV2Json = reminderTask.toJson(targetVersion: 2);
      expect(reminderV2Json['reminderAt'], 1700005000000);
      expect(reminderV2Json['reminderTimezone'], 'Asia/Shanghai');
      expect(
        (reminderV2Json['subtasks'] as List).first['reminderAt'],
        1700004000000,
      );

      // v1 downgrade export strips reminderAt and reminderTimezone
      final reminderV1Json = reminderTask.toJson(targetVersion: 1);
      expect(reminderV1Json.containsKey('reminderAt'), isFalse);
      expect(reminderV1Json.containsKey('reminderTimezone'), isFalse);
      expect(
        (reminderV1Json['subtasks'] as List).first.containsKey('reminderAt'),
        isFalse,
      );
    });

    test('tolerates missing optional fields (old exports)', () {
      final restored = Task.fromJson({'id': 't2', 'title': 'x'});
      expect(restored.quadrant, qEliminate);
      expect(restored.completed, isFalse);
      expect(restored.subtasks, isEmpty);
      expect(restored.urgencyMode, UrgencyMode.auto);
      expect(restored.notesMarkdown, isNull);
      expect(restored.reminderAt, isNull);
      expect(restored.reminderTimezone, isNull);

      final restoredSub = SubTask.fromJson({'id': 's-old', 'title': 'old sub'});
      expect(restoredSub.completed, isFalse);
      expect(restoredSub.deadline, isNull);
      expect(restoredSub.notesMarkdown, isNull);
      expect(restoredSub.reminderAt, isNull);
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
      expect(cfg.model, 'deepseek-flash');
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
      expect(defaultCfg.model, 'deepseek-flash');
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
    test('standard v3 export shape', () {
      final json = ExportData(
        boards: [Board(id: 'b1', name: 'My Tasks', createdAt: 1)],
        tasks: [Task(id: 't1', boardId: 'b1', title: 'x', quadrant: 1, createdAt: 1)],
        settings: AppSettings(),
        aiConfig: AIConfig(),
      ).toJson();
      expect(json['version'], 3);
      expect(json['boards'], isA<List>());
      expect(json['tasks'], isA<List>());
      expect(json['settings'], isA<Map>());
      expect(json['aiConfig'], isA<Map>());
      expect((json['settings'] as Map)['viewMode'], 'grid');
      expect((json['settings'] as Map)['fontSize'], 'standard');
    });

    test('v1 downgrade export shape excludes v2-only settings', () {
      final json = ExportData(
        boards: [Board(id: 'b1', name: 'My Tasks', createdAt: 1)],
        tasks: [Task(id: 't1', boardId: 'b1', title: 'x', quadrant: 1, createdAt: 1)],
        settings: AppSettings(),
        aiConfig: AIConfig(),
      ).toJson(targetVersion: 1);
      expect(json['version'], 1);
      expect(json['boards'], isA<List>());
      expect(json['tasks'], isA<List>());
      expect(json['settings'], isA<Map>());
      expect(json['aiConfig'], isA<Map>());
      expect((json['settings'] as Map).containsKey('viewMode'), isFalse);
      expect((json['settings'] as Map).containsKey('fontSize'), isFalse);
      expect((json['settings'] as Map).containsKey('closeToTray'), isFalse);
      expect((json['settings'] as Map).containsKey('showCompletionRate'), isFalse);
    });
  });

  group('WP06-N resolveDeviceLanguage & AppSettings language resolution', () {
    test('resolves zh variants to Language.zh', () {
      expect(resolveDeviceLanguage([const Locale('zh')]), Language.zh);
      expect(resolveDeviceLanguage([const Locale('zh', 'CN')]), Language.zh);
      expect(resolveDeviceLanguage([const Locale('zh', 'TW')]), Language.zh);
      expect(resolveDeviceLanguage([const Locale('zh', 'HK')]), Language.zh);
      expect(resolveDeviceLanguage([const Locale('zh-CN')]), Language.zh);
      expect(resolveDeviceLanguage([const Locale('zh_TW')]), Language.zh);
      expect(
        resolveDeviceLanguage([
          const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans', countryCode: 'CN'),
        ]),
        Language.zh,
      );
    });

    test('resolves ja variants to Language.ja', () {
      expect(resolveDeviceLanguage([const Locale('ja')]), Language.ja);
      expect(resolveDeviceLanguage([const Locale('ja', 'JP')]), Language.ja);
      expect(resolveDeviceLanguage([const Locale('ja-JP')]), Language.ja);
    });

    test('resolves en variants to Language.en', () {
      expect(resolveDeviceLanguage([const Locale('en')]), Language.en);
      expect(resolveDeviceLanguage([const Locale('en', 'US')]), Language.en);
      expect(resolveDeviceLanguage([const Locale('en', 'GB')]), Language.en);
    });

    test('falls back to Language.en for unsupported locales or empty/null list', () {
      expect(resolveDeviceLanguage([const Locale('fr', 'FR')]), Language.en);
      expect(resolveDeviceLanguage([const Locale('de', 'DE')]), Language.en);
      expect(resolveDeviceLanguage([const Locale('ru')]), Language.en);
      expect(resolveDeviceLanguage([]), Language.en);
      expect(resolveDeviceLanguage(null), Language.en);
    });

    test('picks the first supported language according to priority order', () {
      expect(
        resolveDeviceLanguage([
          const Locale('fr', 'FR'),
          const Locale('zh', 'CN'),
          const Locale('en', 'US'),
        ]),
        Language.zh,
      );
      expect(
        resolveDeviceLanguage([
          const Locale('de', 'DE'),
          const Locale('ja', 'JP'),
          const Locale('zh', 'CN'),
        ]),
        Language.ja,
      );
      expect(
        resolveDeviceLanguage([
          const Locale('ko', 'KR'),
          const Locale('en', 'US'),
          const Locale('zh', 'CN'),
        ]),
        Language.en,
      );
    });

    test('AppSettings.fromJson preserves explicit language even when defaultLanguage differs', () {
      // Explicit en on zh device
      final enSettings = AppSettings.fromJson(
        {'language': 'en'},
        defaultLanguage: Language.zh,
      );
      expect(enSettings.language, Language.en);

      // Explicit zh on en device
      final zhSettings = AppSettings.fromJson(
        {'language': 'zh'},
        defaultLanguage: Language.en,
      );
      expect(zhSettings.language, Language.zh);

      // Explicit ja on zh device
      final jaSettings = AppSettings.fromJson(
        {'language': 'ja'},
        defaultLanguage: Language.zh,
      );
      expect(jaSettings.language, Language.ja);
    });

    test('AppSettings.fromJson uses defaultLanguage when language key is missing or invalid', () {
      final missingSettings = AppSettings.fromJson(
        {'theme': 'dark'},
        defaultLanguage: Language.zh,
      );
      expect(missingSettings.language, Language.zh);

      final nullSettings = AppSettings.fromJson(
        {'language': null},
        defaultLanguage: Language.ja,
      );
      expect(nullSettings.language, Language.ja);

      final invalidSettings = AppSettings.fromJson(
        {'language': 'fr'},
        defaultLanguage: Language.zh,
      );
      expect(invalidSettings.language, Language.zh);
    });
  });

  group('WP08-V-N ViewMode', () {
    test('default viewMode is grid', () {
      final s = AppSettings();
      expect(s.viewMode, ViewMode.grid);
      expect(s.toJson()['viewMode'], 'grid');
    });

    test('fromJson deserializes grid and list correctly', () {
      final gridSettings = AppSettings.fromJson({'viewMode': 'grid'});
      expect(gridSettings.viewMode, ViewMode.grid);

      final listSettings = AppSettings.fromJson({'viewMode': 'list'});
      expect(listSettings.viewMode, ViewMode.list);
      expect(listSettings.toJson()['viewMode'], 'list');
    });

    test('fromJson falls back to grid when viewMode is missing or invalid', () {
      final missing = AppSettings.fromJson({});
      expect(missing.viewMode, ViewMode.grid);

      final invalid = AppSettings.fromJson({'viewMode': 'unknown_mode'});
      expect(invalid.viewMode, ViewMode.grid);
    });
  });

  group('WP08-T-N FontSize and FontFamily', () {
    test('default fontSize is standard and fontFamily is system', () {
      final s = AppSettings();
      expect(s.fontSize, FontSizePref.standard);
      expect(s.fontFamily, FontFamilyPref.system);
      expect(s.toJson()['fontSize'], 'standard');
      expect(s.toJson()['fontFamily'], 'system');
    });

    test('fromJson deserializes fontSize and fontFamily correctly', () {
      final s = AppSettings.fromJson({
        'fontSize': 'large',
        'fontFamily': 'serif',
      });
      expect(s.fontSize, FontSizePref.large);
      expect(s.fontFamily, FontFamilyPref.serif);
      expect(s.toJson()['fontSize'], 'large');
      expect(s.toJson()['fontFamily'], 'serif');
    });

    test('fromJson falls back to standard and system when keys are missing or invalid', () {
      final missing = AppSettings.fromJson({});
      expect(missing.fontSize, FontSizePref.standard);
      expect(missing.fontFamily, FontFamilyPref.system);
      expect(missing.showCompletionRate, isFalse);

      final invalid = AppSettings.fromJson({
        'fontSize': 'huge',
        'fontFamily': 'comic-sans',
      });
      expect(invalid.fontSize, FontSizePref.standard);
      expect(invalid.fontFamily, FontFamilyPref.system);
    });

    test('comicOutline defaults off and stays out of a v1 export', () {
      final missing = AppSettings.fromJson({});
      expect(missing.comicOutline, isFalse);
      expect(missing.toJson().containsKey('comicOutline'), isFalse);
      final enabled = AppSettings.fromJson({'comicOutline': true});
      expect(enabled.comicOutline, isTrue);
      expect(enabled.toJson()['comicOutline'], isTrue);
      expect(enabled.toJson(targetVersion: 1).containsKey('comicOutline'), isFalse);
      final cleared = AppSettings.fromJson(enabled.toJson()..['comicOutline'] = false);
      expect(cleared.comicOutline, isFalse);
    });

    test('showCompletionRate defaults false and round-trips on v2', () {
      final missing = AppSettings.fromJson({});
      expect(missing.showCompletionRate, isFalse);
      expect(missing.toJson()['showCompletionRate'], isFalse);
      final enabled = AppSettings.fromJson({'showCompletionRate': true});
      expect(enabled.showCompletionRate, isTrue);
      expect(enabled.toJson()['showCompletionRate'], isTrue);
      expect(
        enabled.toJson(targetVersion: 1).containsKey('showCompletionRate'),
        isFalse,
      );
    });
  });
}
