import 'models.dart';

/// Pre-configured service provider metadata and discovery endpoints.
///
/// NOTE: Presets define ONLY the service endpoints and protocol metadata;
/// they DO NOT include a hardcoded model catalog. Available models are always
/// dynamically fetched from the provider's official discovery API.
class AIProviderPreset {
  final String id;
  final String Function(Map<String, String> t) name;
  final String defaultBaseUrl;
  final AIProtocol defaultProtocol;
  final String defaultModel;
  final String modelsPath;
  final bool isCustom;
  final bool supportsThinking;
  final String keyHint;

  const AIProviderPreset({
    required this.id,
    required this.name,
    required this.defaultBaseUrl,
    required this.defaultProtocol,
    required this.defaultModel,
    this.modelsPath = '/models',
    this.isCustom = false,
    this.supportsThinking = false,
    this.keyHint = 'sk-...',
  });
}

final List<AIProviderPreset> aiProviderPresets = [
  AIProviderPreset(
    id: 'deepseek',
    name: (t) => t['providerDeepSeek'] ?? 'DeepSeek',
    defaultBaseUrl: 'https://api.deepseek.com',
    defaultProtocol: AIProtocol.openai,
    defaultModel: 'deepseek-flash',
    modelsPath: '/models',
    isCustom: false,
    supportsThinking: true,
    keyHint: 'sk-...',
  ),
  AIProviderPreset(
    id: 'volcengine',
    name: (t) => t['providerVolcengine'] ?? '火山引擎 (Doubao)',
    defaultBaseUrl: 'https://ark.cn-beijing.volces.com/api/v3',
    defaultProtocol: AIProtocol.openai,
    defaultModel: 'doubao-pro-32k',
    modelsPath: '/models',
    isCustom: false,
    supportsThinking: false,
    keyHint: '...',
  ),
  AIProviderPreset(
    id: 'bailian',
    name: (t) => t['providerBailian'] ?? '阿里云百炼 (Qwen)',
    defaultBaseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
    defaultProtocol: AIProtocol.openai,
    defaultModel: 'qwen-plus',
    modelsPath: '/models',
    isCustom: false,
    supportsThinking: false,
    keyHint: 'sk-...',
  ),
  AIProviderPreset(
    id: 'custom',
    name: (t) => t['providerCustom'] ?? '自定义 (Custom)',
    defaultBaseUrl: '',
    defaultProtocol: AIProtocol.openai,
    defaultModel: '',
    modelsPath: '/models',
    isCustom: true,
    supportsThinking: false,
    keyHint: 'sk-...',
  ),
];

AIProviderPreset getAIProviderPreset(String? id) {
  if (id == null || id.isEmpty) return aiProviderPresets.first;
  return aiProviderPresets.firstWhere(
    (p) => p.id == id,
    orElse: () => aiProviderPresets.last,
  );
}

AIProviderPreset? findAIProviderPreset(String? id) {
  for (final preset in aiProviderPresets) {
    if (preset.id == id) return preset;
  }
  return null;
}

/// Chooses the preferred model from dynamic discovery response.
///
/// 1. If [currentModel] is already present in [availableModels], preserves it.
/// 2. If provider has a recognized default, prioritizes it.
/// 3. Otherwise picks the first available model.
String pickPreferredModel(
  String providerId,
  List<String> availableModels, {
  String? currentModel,
}) {
  if (availableModels.isEmpty) {
    return getAIProviderPreset(providerId).defaultModel;
  }
  if (currentModel != null &&
      currentModel.isNotEmpty &&
      availableModels.contains(currentModel)) {
    return currentModel;
  }
  if (providerId == 'deepseek') {
    if (availableModels.contains(
      getAIProviderPreset(providerId).defaultModel,
    )) {
      return getAIProviderPreset(providerId).defaultModel;
    }
    if (availableModels.contains('deepseek-v4-flash')) {
      return 'deepseek-v4-flash';
    }
    if (availableModels.contains('deepseek-chat')) {
      return 'deepseek-chat';
    }
  } else if (providerId == 'bailian') {
    if (availableModels.contains('qwen-plus')) {
      return 'qwen-plus';
    }
    if (availableModels.contains('qwen-turbo')) {
      return 'qwen-turbo';
    }
  } else if (providerId == 'volcengine') {
    final doubao = availableModels.where((m) => m.toLowerCase().contains('doubao')).firstOrNull;
    if (doubao != null) return doubao;
  }
  return availableModels.first;
}
