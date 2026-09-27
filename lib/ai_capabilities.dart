import 'ai_presets.dart';
import 'model_discovery.dart';
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

/// Capability rules for the three wire protocols, keyed by the concrete model
/// version and the endpoint it is being sent to.
///
/// A model *family* is not a capability. Every value below is read off the
/// vendor's own model page, and a version the vendor does not document falls
/// back to sending nothing plus a hint — including a fallback that cannot force
/// thinking off, which the settings switch states out loud.
///
/// OpenAI Compatible chat requests keep sending only `model`, `messages` and,
/// when JSON is asked for, `response_format`. DeepSeek's `thinking` object is a
/// vendor extension, so it goes only to an endpoint declared to be the official
/// DeepSeek API (the DeepSeek preset, or `api.deepseek.com`); a custom reverse
/// proxy that merely serves a `deepseek-*` model name never receives it.
/// Volcengine and Bailian never receive it either.
///
/// Responses reasoning uses `reasoning.effort`, whose value set differs per
/// model version, so `none` is sent only where the model page lists it:
/// - `gpt-5`, original: `minimal, low, medium, high` — no `none`, so off asks
///   for `minimal` and says the model still reasons.
/// - `gpt-5.1` / `gpt-5.5` / `gpt-5.6` / `gpt-6-sol` / `gpt-6-luna`: list
///   `none`, so off sends `none`.
/// - `gpt-6-astra`: no `none` and no `minimal`; `none` returns HTTP 400.
/// - `gpt-6-astra`: no `none` and no `minimal`; off omits the field and says it
///   cannot be forced off. On still sends `high`, which that model's page lists.
/// - Any other `gpt-5*` / `gpt-6*` / `o*` id, including an unknown suffix on a
///   known id: no parameter in either switch position, and a hint that the
///   version is not on the checked list. A family prefix is not a capability.
///
/// Anthropic thinking is chosen from an explicit list of documented model ids
/// instead of a version-range guess:
/// - `claude-fable-5*`, `claude-mythos-5*`, `claude-opus-5-5`: adaptive and
///   always on. `thinking: {type: "disabled"}` returns HTTP 400, so off sends
///   no thinking field and reports that the model cannot be switched off.
/// - `claude-sonnet-5`, `claude-opus-5`, `claude-opus-4-6/4-7/4-8`,
///   `claude-sonnet-4-6`: `thinking: {type: "adaptive"}` plus
///   `output_config.effort`. Sonnet 5 accepts `disabled`; Opus 5 accepts it at
///   effort high or below. These two use explicit `disabled` when off. On the
///   4.x models, omission leaves thinking off.
/// - `claude-3-7-sonnet`, `claude-opus-4`, `claude-sonnet-4`,
///   `claude-opus-4-5`, `claude-sonnet-4-5`, `claude-haiku-4-5`: manual
///   extended thinking, opt-in, and only those ids plus a `-YYYYMMDD` snapshot.
///   Claude 3.5 is not in this set. On sends `enabled` with `budget_tokens`
///   inside the documented `>= 1024` and `< max_tokens` window; off omits the
///   field.
/// - Anything else: no thinking field. An unrecognized Claude id says the
///   version was not checked; other ids say thinking controls are unsupported
///   when thinking was asked for.
///
/// Sources checked 2026-09-26, and the Anthropic generational rule again on
/// 2026-09-27 (extended thinking is per model generation, not a 3.x prefix).
/// No live vendor request was sent for the 2026-09-27 pass:
/// - https://developers.openai.com/api/docs/models/gpt-5
/// - https://developers.openai.com/api/docs/models/gpt-5.1
/// - https://developers.openai.com/api/docs/models/gpt-5.5
/// - https://developers.openai.com/api/docs/models/gpt-5.6
/// - https://developers.openai.com/api/docs/models/gpt-6-astra
/// - https://developers.openai.com/api/docs/models/gpt-6-sol
/// - https://developers.openai.com/api/docs/models/gpt-6-luna
/// - https://developers.openai.com/api/docs/models/o3
/// - https://developers.openai.com/api/docs/guides/reasoning
/// - https://developers.openai.com/api/docs/deprecations
/// - https://api-docs.deepseek.com/guides/thinking_mode
/// - https://api-docs.deepseek.com/quick_start/pricing
/// - https://platform.claude.com/docs/en/about-claude/models/overview
/// - https://platform.claude.com/docs/en/build-with-claude/extended-thinking
/// - https://platform.claude.com/docs/en/build-with-claude/thinking
/// - https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-sonnet-5
/// - https://platform.claude.com/docs/en/build-with-claude/effort
/// - https://platform.claude.com/docs/en/models/fable-5-1/migration-guide
/// - https://platform.claude.com/docs/en/api/messages
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

/// OpenAI dated snapshots are `-YYYY-MM-DD` and nothing shorter or longer.
final _openAiSnapshotDate = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// Anthropic dated snapshots are `-YYYYMMDD`.
final _anthropicSnapshotDate = RegExp(r'^\d{8}$');

/// True for [canonical] itself or that id plus one vendor date snapshot.
///
/// A version suffix (`-99`, `-5`, `-mini`, `-unverified`) is a different model.
/// Dots are normalized by the caller before this runs, so they are not a
/// second way to spell a suffix.
bool _exactOrSnapshot(String id, String canonical, {required bool anthropic}) {
  if (id == canonical) return true;
  final marker = '$canonical-';
  if (!id.startsWith(marker)) return false;
  final rest = id.substring(marker.length);
  return (anthropic ? _anthropicSnapshotDate : _openAiSnapshotDate).hasMatch(
    rest,
  );
}

bool _matchesAny(
  String id,
  List<String> canonicals, {
  required bool anthropic,
}) => canonicals.any(
  (canonical) => _exactOrSnapshot(id, canonical, anthropic: anthropic),
);

/// Shape of a Responses id we might have been tempted to treat as a family.
/// It only selects the "not on the list" hint. It never grants a parameter.
final _unlistedResponsesShape = RegExp(r'^(gpt-[5-9]|o[1-9])([\-\._]|$)');

const _responsesEffortNone = [
  'gpt-5.1',
  'gpt-5.5',
  'gpt-5.6',
  'gpt-6-sol',
  'gpt-6-luna',
];

final _deepSeekModelId = RegExp(r'^deepseek([\-\._]|$)', caseSensitive: false);

const _deepSeekOfficialHost = 'api.deepseek.com';

bool _isDeepSeekOfficialEndpoint(AIConfig config) {
  if (getAIProviderPreset(config.provider).supportsThinking) return true;
  final base = tryNormalizeAiBaseUrl(config.baseUrl);
  if (base == null) return false;
  final host = Uri.tryParse(base)?.host.toLowerCase();
  return host == _deepSeekOfficialHost;
}

ThinkingPlan _openAiCompatible(AIConfig config, String model) {
  final deepseekModel = _deepSeekModelId.hasMatch(model);
  if (!deepseekModel) {
    return ThinkingPlan(
      hintCode: config.enableThinking ? 'aiThinkingUnsupported' : null,
    );
  }
  if (_isDeepSeekOfficialEndpoint(config)) {
    // Official default is enabled, so off must be sent explicitly.
    return ThinkingPlan(
      fields: {
        'thinking': {'type': config.enableThinking ? 'enabled' : 'disabled'},
      },
    );
  }
  // Same vendor namespace, different endpoint: proxies that re-host a DeepSeek
  // weight are free to reject the extension, and the vendor default is
  // thinking-on, so neither switch position can be confirmed here.
  return const ThinkingPlan(hintCode: 'aiThinkingCapabilityUnverified');
}

ThinkingPlan _responses(AIConfig config, String model) {
  final id = model.trim().toLowerCase();
  final originalGpt5 = _exactOrSnapshot(id, 'gpt-5', anthropic: false);
  final effortNone = _matchesAny(id, _responsesEffortNone, anthropic: false);
  final astra = _exactOrSnapshot(id, 'gpt-6-astra', anthropic: false);
  if (!originalGpt5 && !effortNone && !astra) {
    if (_unlistedResponsesShape.hasMatch(id)) {
      return const ThinkingPlan(hintCode: 'aiThinkingModelUnverified');
    }
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
  if (effortNone) {
    return const ThinkingPlan(
      fields: {
        'reasoning': {'effort': 'none'},
      },
    );
  }
  if (originalGpt5) {
    return const ThinkingPlan(
      fields: {
        'reasoning': {'effort': 'minimal'},
      },
      hintCode: 'aiThinkingLowestEffort',
    );
  }
  return const ThinkingPlan(hintCode: 'aiThinkingNotForciblyOff');
}

const _anthropicAlwaysOn = [
  'claude-fable-5',
  'claude-fable-5-1',
  'claude-mythos-5',
  'claude-mythos-5-1',
  'claude-opus-5-5',
];

const _anthropicAdaptive = [
  'claude-opus-4-8',
  'claude-opus-4-7',
  'claude-opus-4-6',
  'claude-sonnet-4-6',
];

/// Only these documented 5.0 models (and dated snapshots) have an explicit
/// off switch. Do not infer the same for 5.5 or a future minor version.
final _anthropicExplicitOff = RegExp(r'^claude-(sonnet|opus)-5(-\d{8})?$');

/// Manual extended thinking, each id checked on its own.
///
/// Claude 3.5 Sonnet and Haiku are not on this list: extended thinking starts
/// at Claude 3.7 Sonnet. A `3.x` prefix is not evidence. Re-checked 2026-09-27
/// against the generational rules in
/// https://platform.claude.com/docs/en/build-with-claude/extended-thinking
/// (the same distinction recorded by the 2026-09-27 acceptance review). No
/// live vendor request was sent.
const _anthropicManual = [
  'claude-3-7-sonnet',
  'claude-opus-4-5',
  'claude-sonnet-4-5',
  'claude-haiku-4-5',
  'claude-opus-4',
  'claude-sonnet-4',
];

/// Inside the documented window: at least 1024 and below the request's
/// `max_tokens` ([_anthropicMaxTokens] equivalent in `ai_service.dart`).
const _anthropicThinkingBudget = 4096;

ThinkingPlan _anthropic(AIConfig config, String model) {
  // Anthropic ids never spell a dot, so `claude-opus-4.6` and
  // `claude.opus.5.5` both normalize onto the documented spelling.
  final id = model.trim().toLowerCase().replaceAll('.', '-');
  if (id.isEmpty) {
    return ThinkingPlan(
      hintCode: config.enableThinking ? 'aiThinkingUnsupported' : null,
    );
  }
  if (_matchesAny(id, _anthropicAlwaysOn, anthropic: true)) {
    if (config.enableThinking) {
      return const ThinkingPlan(
        fields: {
          'output_config': {'effort': 'high'},
        },
      );
    }
    return const ThinkingPlan(hintCode: 'aiThinkingAlwaysOn');
  }
  if (_anthropicExplicitOff.hasMatch(id)) {
    return config.enableThinking
        ? const ThinkingPlan(
            fields: {
              'thinking': {'type': 'adaptive'},
              'output_config': {'effort': 'high'},
            },
          )
        : const ThinkingPlan(
            fields: {
              'thinking': {'type': 'disabled'},
            },
          );
  }
  if (_matchesAny(id, _anthropicAdaptive, anthropic: true)) {
    if (config.enableThinking) {
      return const ThinkingPlan(
        fields: {
          'thinking': {'type': 'adaptive'},
          'output_config': {'effort': 'high'},
        },
      );
    }
    // On these 4.x models, thinking is opt-in; omission is the documented off.
    return const ThinkingPlan();
  }
  if (_matchesAny(id, _anthropicManual, anthropic: true)) {
    // Extended thinking is opt-in, so leaving it out is the documented off.
    return config.enableThinking
        ? const ThinkingPlan(
            fields: {
              'thinking': {
                'type': 'enabled',
                'budget_tokens': _anthropicThinkingBudget,
              },
            },
          )
        : const ThinkingPlan();
  }
  if (id.startsWith('claude')) {
    return const ThinkingPlan(hintCode: 'aiThinkingModelUnverified');
  }
  return ThinkingPlan(
    hintCode: config.enableThinking ? 'aiThinkingUnsupported' : null,
  );
}
