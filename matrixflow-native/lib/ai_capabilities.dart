import 'models.dart';

/// Fields to merge into a protocol body, plus an optional settings hint.
///
/// [hintCode] is a localization key. It is set only when the thinking switch
/// cannot be honored without sending a parameter the model is known to reject
/// or ignore. The key is never a credential or response body.
class ThinkingPlan {
  final Map<String, dynamic> fields;
  final String? hintCode;

  const ThinkingPlan({this.fields = const {}, this.hintCode});
}

/// Lightweight provider/model rules for the three wire protocols.
///
/// OpenAI-compatible requests send only `model`, `messages` and, when the
/// caller asks for JSON, `response_format`. DeepSeek's `thinking` object is
/// added only for the DeepSeek API (or a custom model id that is a DeepSeek
/// model). Volcengine and Bailian never receive that extension.
///
/// Responses reasoning follows the Responses API `reasoning.effort` field.
/// Values vary by model, so unknown models omit it. The o-series does not
/// receive `none` (support is model-specific). `gpt-5` ids receive `none`
/// when thinking is off, which the Responses effort enum documents as a
/// supported value.
///
/// Anthropic manual extended thinking (`thinking.type = enabled` plus
/// `budget_tokens`) and adaptive thinking (`thinking.type = adaptive` plus
/// `output_config.effort`) are chosen from the model id. `output_config.effort`
/// alone is not treated as a universal on-switch. Models that reject
/// `thinking.type = disabled` do not receive that field.
///
/// Sources checked 2026-09-23:
/// - https://api-docs.deepseek.com/guides/thinking_mode
/// - https://developers.openai.com/api/reference/resources/responses/methods/create
/// - https://platform.claude.com/docs/en/build-with-claude/extended-thinking
/// - https://platform.claude.com/docs/en/build-with-claude/effort
ThinkingPlan planThinking(AIConfig config) {
  final model = config.model.trim();
  switch (config.protocol) {
    case AIProtocol.openai:
      return _openAiCompatible(config, model);
    case AIProtocol.openaiResponses:
      return _responses(config, model);
    case AIProtocol.anthropic:
      return _anthropic(config, model);
  }
}

ThinkingPlan _openAiCompatible(AIConfig config, String model) {
  if (config.provider == 'volcengine' || config.provider == 'bailian') {
    return ThinkingPlan(
      hintCode: config.enableThinking ? 'aiThinkingUnsupported' : null,
    );
  }
  final deepseekHost = config.provider == 'deepseek';
  final deepseekModel = RegExp(
    r'^deepseek([\-.]|$)',
    caseSensitive: false,
  ).hasMatch(model);
  if (deepseekHost || deepseekModel) {
    // Official default is enabled, so off must be sent explicitly.
    return ThinkingPlan(
      fields: {
        'thinking': {'type': config.enableThinking ? 'enabled' : 'disabled'},
      },
    );
  }
  return ThinkingPlan(
    hintCode: config.enableThinking ? 'aiThinkingUnsupported' : null,
  );
}

ThinkingPlan _responses(AIConfig config, String model) {
  final id = model.toLowerCase();
  final oSeries = RegExp(r'^(o1|o3|o4)([\-.]|$)').hasMatch(id);
  final gpt5 = RegExp(r'^gpt-5([\-.]|$)').hasMatch(id);
  if (!oSeries && !gpt5) {
    return ThinkingPlan(
      hintCode: config.enableThinking ? 'aiThinkingUnsupported' : null,
    );
  }
  if (config.enableThinking) {
    return const ThinkingPlan(
      fields: {
        'reasoning': {'effort': 'high'},
      },
    );
  }
  if (gpt5) {
    return const ThinkingPlan(
      fields: {
        'reasoning': {'effort': 'none'},
      },
    );
  }
  return const ThinkingPlan(hintCode: 'aiThinkingNotForciblyOff');
}

ThinkingPlan _anthropic(AIConfig config, String model) {
  final id = model.trim().toLowerCase().replaceAllMapped(
    RegExp(r'(\d)\.(\d)'),
    (match) => '${match[1]}-${match[2]}',
  );
  if (id.isEmpty) {
    return ThinkingPlan(
      hintCode: config.enableThinking ? 'aiThinkingUnsupported' : null,
    );
  }
  if (RegExp(r'^claude-(fable|mythos)-5([\-.]|$)').hasMatch(id)) {
    if (config.enableThinking) {
      return const ThinkingPlan(
        fields: {
          'output_config': {'effort': 'high'},
        },
      );
    }
    return const ThinkingPlan(hintCode: 'aiThinkingAlwaysOn');
  }
  final adaptive = RegExp(
    r'^claude-(opus|sonnet)-4-([6-9]|[1-9]\d)([\-.]|$)',
  ).hasMatch(id) ||
      RegExp(
        r'^claude-(opus|sonnet|fable|mythos)-([5-9]|[1-9]\d)([\-.]|$)',
      ).hasMatch(id);
  if (adaptive) {
    if (config.enableThinking) {
      return const ThinkingPlan(
        fields: {
          'thinking': {'type': 'adaptive'},
          'output_config': {'effort': 'high'},
        },
      );
    }
    return const ThinkingPlan(
      fields: {
        'thinking': {'type': 'disabled'},
      },
    );
  }
  final manual = RegExp(
    r'^claude-(3-7|opus-4-5|sonnet-4-5|opus-4|sonnet-4)([\-.]|$)',
  ).hasMatch(id);
  if (manual) {
    if (config.enableThinking) {
      return const ThinkingPlan(
        fields: {
          'thinking': {'type': 'enabled', 'budget_tokens': 4096},
        },
      );
    }
    return const ThinkingPlan(
      fields: {
        'thinking': {'type': 'disabled'},
      },
    );
  }
  return ThinkingPlan(
    hintCode: config.enableThinking ? 'aiThinkingUnsupported' : null,
  );
}
