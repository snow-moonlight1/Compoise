/// The three AI wire protocols (OpenAI compatible / OpenAI Responses / Anthropic
/// Messages). Request and response shapes follow the provider ecosystems — the
/// same conventions the web app's aiService.ts uses.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'ai_capabilities.dart';
import 'ai_presets.dart';
import 'model_discovery.dart';
import 'models.dart';

enum AiProbeKind { endpointAuth, modelDiscovery, modelGeneration }

/// One connection-test stage. [code] is a localization key, never a credential
/// or response body.
class AiProbeStep {
  final AiProbeKind kind;
  final bool attempted;
  final bool ok;
  final String code;
  final int? status;

  const AiProbeStep({
    required this.kind,
    required this.attempted,
    required this.ok,
    required this.code,
    this.status,
  });

  @override
  String toString() =>
      'AiProbeStep(${kind.name}, attempted: $attempted, ok: $ok, code: $code, status: $status)';
}

/// Endpoint/auth and model discovery only. Generation is a separate call.
class ConnectionProbe {
  final AiProbeStep endpointAuth;
  final AiProbeStep modelDiscovery;

  const ConnectionProbe({
    required this.endpointAuth,
    required this.modelDiscovery,
  });

  @override
  String toString() =>
      'ConnectionProbe(endpoint: $endpointAuth, discovery: $modelDiscovery)';
}

class AIException implements Exception {
  final String code;
  final int? status;
  const AIException(this.code, [this.status]);
  @override
  String toString() => status == null ? code : '$code ($status)';
}

class AICancellation {
  final _completer = Completer<void>();
  Future<void> get whenCancelled => _completer.future;
  bool get isCancelled => _completer.isCompleted;
  void cancel() {
    if (!isCancelled) _completer.complete();
  }
}

String aiErrorMessage(Object error, Map<String, String> t) {
  if (error is AIException) {
    return '${t[error.code] ?? t['error']}${error.status == null ? '' : ' (${error.status})'}';
  }
  if (error is TimeoutException) return t['requestTimeout']!;
  if (error is FormatException || error is TypeError) {
    return t['aiInvalidResponse']!;
  }
  return t['aiNetworkError']!;
}

const aiRequestTimeout = Duration(seconds: 30);

class AIService {
  AIService({http.Client? client, this.timeout = aiRequestTimeout})
    : _client = client ?? http.Client();
  final http.Client _client;
  final Duration timeout;
  final _requests = <Completer<void>>{};

  void close() {
    for (final request in _requests) {
      if (!request.isCompleted) request.complete();
    }
    _client.close();
  }

  static const _anthropicVersion = '2023-06-01';
  static const _anthropicMaxTokens = 8192;

  Future<List<AIAnalysisResult>> analyzeTasks({
    required List<String> inputs,
    required AIConfig config,
    required Language language,
    required bool autoDecompose,
    AICancellation? cancellation,
  }) async {
    final text = await requestCompletion(
      config: config,
      systemInstruction: _sortInstruction(language, autoDecompose),
      userPrompt:
          'Here are the tasks to analyze: ${jsonEncode(inputs)}. \n\nImportant: ${_languageSuffix(language)}',
      forceJsonObject: config.protocol != AIProtocol.anthropic,
      cancellation: cancellation,
    );
    final items = extractJsonArray(text);
    if (items.isEmpty ||
        items.any(
          (item) =>
              item is! Map<String, dynamic> ||
              item['title'] is! String ||
              (item['title'] as String).trim().isEmpty,
        )) {
      throw const AIException('aiInvalidResponse');
    }
    return items
        .cast<Map<String, dynamic>>()
        .map(
          (item) => AIAnalysisResult(
            title: (item['title'] as String).trim(),
            quadrant: normalizeQuadrant(item['quadrant']),
            isLongTerm: (item['isLongTerm'] as bool?) ?? false,
            isGrouped:
                (item['isGrouped'] as bool?) ??
                (item['isLongTerm'] != true &&
                    item['subtasks'] is List &&
                    (item['subtasks'] as List).isNotEmpty),
            reasoning: item['reasoning'] as String?,
            subtasks: _subtaskTitles(item['subtasks']),
          ),
        )
        .where((r) => r.title.isNotEmpty)
        .toList();
  }

  Future<List<DecomposeResult>> decomposeBatch({
    required List<String> taskTitles,
    required AIConfig config,
    required Language language,
    AICancellation? cancellation,
  }) async {
    final text = await requestCompletion(
      config: config,
      systemInstruction: _batchInstruction(language),
      userPrompt:
          'Break down these tasks: ${jsonEncode(taskTitles)}. \n\nImportant: ${_languageSuffix(language)}',
      forceJsonObject: config.protocol != AIProtocol.anthropic,
      cancellation: cancellation,
    );
    final results =
        extractJsonArray(text)
            .whereType<Map<String, dynamic>>()
            .where((item) => item['originalTitle'] is String)
            .map(
              (item) => DecomposeResult(
                originalTitle: item['originalTitle'] as String,
                subtasks: _subtaskTitles(item['subtasks']),
              ),
            )
            .toList();
    for (final title in taskTitles) {
      final matches = results.where((r) => r.originalTitle == title);
      if (matches.isEmpty || matches.any((r) => r.subtasks.isEmpty)) {
        throw const AIException('aiInvalidResponse');
      }
    }
    return results;
  }

  final _modelCache = <ModelDiscoveryIdentity, List<String>>{};
  final _inflight = <ModelDiscoveryIdentity, Future<List<String>>>{};
  final _flightCancel = <ModelDiscoveryIdentity, AICancellation>{};
  final _flightEpoch = <ModelDiscoveryIdentity, int>{};

  void clearModelCache() {
    _modelCache.clear();
    for (final cancel in _flightCancel.values.toList()) {
      cancel.cancel();
    }
    _flightCancel.clear();
    _flightEpoch.clear();
    _inflight.clear();
  }

  /// Redacted cache identities. Safe to log: credentials are not included.
  String get modelCacheDiagnostic =>
      _modelCache.keys.map((id) => id.diagnosticLabel).join('\n');

  /// Dynamically fetches available models from the provider's discovery API.
  ///
  /// The cache identity is provider + normalized base URL + protocol +
  /// credential. The same identity is reused unless [forceRefresh] is set.
  /// A newer discovery retires older in-flight calls so late bodies are not
  /// stored. Failures are not cached.
  Future<List<String>> fetchModels({
    required AIConfig config,
    bool forceRefresh = false,
    AICancellation? cancellation,
  }) {
    final identity = _identity(config);
    if (!forceRefresh) {
      final cached = _modelCache[identity];
      if (cached != null) return Future.value(List<String>.from(cached));
      final pending = _inflight[identity];
      if (pending != null) {
        return pending.then((models) => List<String>.from(models));
      }
    } else {
      _retireDiscovery(identity);
    }
    for (final other in _flightCancel.keys.toList()) {
      if (other != identity) _retireDiscovery(other);
    }
    _flightEpoch.putIfAbsent(identity, () => 0);
    final epoch = _flightEpoch[identity]!;
    final cancel = AICancellation();
    _linkCancel(cancellation, cancel);
    _flightCancel[identity] = cancel;
    final future = _fetchAndStore(config, identity, epoch, cancel);
    _inflight[identity] = future;
    return future.whenComplete(() {
      if (identical(_inflight[identity], future)) _inflight.remove(identity);
      if (identical(_flightCancel[identity], cancel)) {
        _flightCancel.remove(identity);
      }
    });
  }

  Future<List<String>> _fetchAndStore(
    AIConfig config,
    ModelDiscoveryIdentity identity,
    int epoch,
    AICancellation cancel,
  ) async {
    try {
      final res = await _send(
        _modelsRequest(config, identity.normalizedBaseUrl),
        cancellation: cancel,
      );
      _ensureDiscoveryCurrent(config, identity, epoch, cancel);
      if (res.statusCode == 401 || res.statusCode == 403) {
        throw AIException('aiUnauthorized', res.statusCode);
      }
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw AIException('aiHttpError', res.statusCode);
      }
      final dynamic json;
      try {
        json = jsonDecode(utf8.decode(res.bodyBytes));
      } catch (_) {
        throw const AIException('aiInvalidResponse');
      }
      final models = _parseModelList(json);
      _ensureDiscoveryCurrent(config, identity, epoch, cancel);
      _modelCache[identity] = List<String>.from(models);
      return List<String>.from(models);
    } on AIException {
      rethrow;
    } on TimeoutException {
      rethrow;
    } catch (error) {
      if (cancel.isCancelled || error is http.RequestAbortedException) {
        throw const AIException('aiCancelled');
      }
      throw const AIException('aiNetworkError');
    }
  }

  void _retireDiscovery(ModelDiscoveryIdentity identity) {
    _flightEpoch[identity] = (_flightEpoch[identity] ?? 0) + 1;
    _flightCancel.remove(identity)?.cancel();
    _inflight.remove(identity);
  }

  void _ensureDiscoveryCurrent(
    AIConfig config,
    ModelDiscoveryIdentity identity,
    int epoch,
    AICancellation cancel,
  ) {
    if (cancel.isCancelled || _flightEpoch[identity] != epoch) {
      throw const AIException('aiCancelled');
    }
    if (tryModelDiscoveryIdentity(config) != identity) {
      throw const AIException('aiCancelled');
    }
  }

  static List<String> _parseModelList(dynamic json) {
    if (json == null) return [];
    List items = [];
    if (json is List) {
      items = json;
    } else if (json is Map) {
      if (json['data'] is List) {
        items = json['data'] as List;
      } else if (json['models'] is List) {
        items = json['models'] as List;
      }
    }
    final result = <String>[];
    final seen = <String>{};
    for (final item in items) {
      String? id;
      if (item is String) {
        id = item.trim();
      } else if (item is Map && item['id'] != null) {
        id = item['id'].toString().trim();
      }
      if (id != null && id.isNotEmpty && seen.add(id)) {
        result.add(id);
      }
    }
    return result;
  }

  /// Checks endpoint/auth and model discovery. Does not generate text.
  Future<ConnectionProbe> testConnection(
    AIConfig config, {
    AICancellation? cancellation,
  }) async {
    const skipped = AiProbeStep(
      kind: AiProbeKind.modelDiscovery,
      attempted: false,
      ok: false,
      code: 'aiCheckSkipped',
    );
    final ModelDiscoveryIdentity identity;
    try {
      identity = _identity(config);
    } on AIException catch (error) {
      return ConnectionProbe(
        endpointAuth: AiProbeStep(
          kind: AiProbeKind.endpointAuth,
          attempted: false,
          ok: false,
          code: error.code,
        ),
        modelDiscovery: skipped,
      );
    }
    try {
      final res = await _send(
        _modelsRequest(config, identity.normalizedBaseUrl),
        cancellation: cancellation,
      );
      if (_probeStale(config, identity, cancellation)) return _cancelledProbe();
      return _interpretDiscovery(res);
    } on TimeoutException {
      return ConnectionProbe(
        endpointAuth: const AiProbeStep(
          kind: AiProbeKind.endpointAuth,
          attempted: true,
          ok: false,
          code: 'requestTimeout',
        ),
        modelDiscovery: skipped,
      );
    } catch (error) {
      if (_probeStale(config, identity, cancellation) ||
          error is http.RequestAbortedException ||
          error is AIException && error.code == 'aiCancelled') {
        return _cancelledProbe();
      }
      return ConnectionProbe(
        endpointAuth: const AiProbeStep(
          kind: AiProbeKind.endpointAuth,
          attempted: true,
          ok: false,
          code: 'aiNetworkError',
        ),
        modelDiscovery: skipped,
      );
    }
  }

  /// Sends one short completion to the selected model.
  ///
  /// Callers must invoke this only from an explicit user action. The request
  /// can be billed. It is not part of startup, focus loss, or [testConnection].
  /// Success requires generated text; a model list is not treated as success.
  Future<AiProbeStep> testModelGeneration(
    AIConfig config, {
    AICancellation? cancellation,
  }) async {
    final model = config.model.trim();
    final ModelDiscoveryIdentity identity;
    try {
      identity = _identity(config);
    } on AIException catch (error) {
      return AiProbeStep(
        kind: AiProbeKind.modelGeneration,
        attempted: false,
        ok: false,
        code: error.code,
      );
    }
    if (model.isEmpty) {
      return const AiProbeStep(
        kind: AiProbeKind.modelGeneration,
        attempted: false,
        ok: false,
        code: 'aiMissingModel',
      );
    }
    try {
      final res = await _send(
        _generationRequest(config, identity.normalizedBaseUrl, model),
        cancellation: cancellation,
      );
      if (_generationStale(config, identity, model, cancellation)) {
        return _cancelledGeneration();
      }
      if (res.statusCode == 401 || res.statusCode == 403) {
        return AiProbeStep(
          kind: AiProbeKind.modelGeneration,
          attempted: true,
          ok: false,
          code: 'aiUnauthorized',
          status: res.statusCode,
        );
      }
      if (res.statusCode == 429 ||
          res.statusCode < 200 ||
          res.statusCode >= 300) {
        return AiProbeStep(
          kind: AiProbeKind.modelGeneration,
          attempted: true,
          ok: false,
          code: 'aiHttpError',
          status: res.statusCode,
        );
      }
      final dynamic json;
      try {
        json = jsonDecode(utf8.decode(res.bodyBytes));
      } catch (_) {
        return const AiProbeStep(
          kind: AiProbeKind.modelGeneration,
          attempted: true,
          ok: false,
          code: 'aiInvalidResponse',
        );
      }
      if (_generationStale(config, identity, model, cancellation)) {
        return _cancelledGeneration();
      }
      try {
        final text = extractResponseText(config.protocol, json).trim();
        if (text.isEmpty) {
          return const AiProbeStep(
            kind: AiProbeKind.modelGeneration,
            attempted: true,
            ok: false,
            code: 'aiGenerationEmpty',
          );
        }
        return const AiProbeStep(
          kind: AiProbeKind.modelGeneration,
          attempted: true,
          ok: true,
          code: 'aiGenerationOk',
        );
      } on AIException {
        return const AiProbeStep(
          kind: AiProbeKind.modelGeneration,
          attempted: true,
          ok: false,
          code: 'aiInvalidResponse',
        );
      }
    } on TimeoutException {
      return const AiProbeStep(
        kind: AiProbeKind.modelGeneration,
        attempted: true,
        ok: false,
        code: 'requestTimeout',
      );
    } catch (error) {
      if (_generationStale(config, identity, model, cancellation) ||
          error is http.RequestAbortedException) {
        return _cancelledGeneration();
      }
      return const AiProbeStep(
        kind: AiProbeKind.modelGeneration,
        attempted: true,
        ok: false,
        code: 'aiNetworkError',
      );
    }
  }

  ConnectionProbe _interpretDiscovery(http.Response res) {
    final status = res.statusCode;
    AiProbeStep endpoint({required bool ok, required String code}) =>
        AiProbeStep(
          kind: AiProbeKind.endpointAuth,
          attempted: true,
          ok: ok,
          code: code,
          status: status,
        );
    AiProbeStep discovery({required bool ok, required String code}) =>
        AiProbeStep(
          kind: AiProbeKind.modelDiscovery,
          attempted: true,
          ok: ok,
          code: code,
          status: status,
        );
    if (status == 401 || status == 403) {
      return ConnectionProbe(
        endpointAuth: endpoint(ok: false, code: 'aiUnauthorized'),
        modelDiscovery: discovery(ok: false, code: 'aiUnauthorized'),
      );
    }
    if (status == 404 || status == 405) {
      return ConnectionProbe(
        endpointAuth: endpoint(ok: true, code: 'aiEndpointReachable'),
        modelDiscovery: discovery(ok: false, code: 'aiDiscoveryUnavailable'),
      );
    }
    if (status == 429) {
      return ConnectionProbe(
        endpointAuth: endpoint(ok: true, code: 'aiEndpointReachable'),
        modelDiscovery: discovery(ok: false, code: 'aiHttpError'),
      );
    }
    if (status < 200 || status >= 300) {
      return ConnectionProbe(
        endpointAuth: endpoint(ok: false, code: 'aiHttpError'),
        modelDiscovery: discovery(ok: false, code: 'aiHttpError'),
      );
    }
    try {
      final models = _parseModelList(jsonDecode(utf8.decode(res.bodyBytes)));
      return ConnectionProbe(
        endpointAuth: endpoint(ok: true, code: 'aiEndpointReachable'),
        modelDiscovery:
            models.isEmpty
                ? discovery(ok: false, code: 'aiNoModels')
                : discovery(ok: true, code: 'aiDiscoveryOk'),
      );
    } catch (_) {
      return ConnectionProbe(
        endpointAuth: endpoint(ok: true, code: 'aiEndpointReachable'),
        modelDiscovery: discovery(ok: false, code: 'aiInvalidResponse'),
      );
    }
  }

  bool _probeStale(
    AIConfig config,
    ModelDiscoveryIdentity identity,
    AICancellation? cancellation,
  ) =>
      (cancellation?.isCancelled ?? false) ||
      tryModelDiscoveryIdentity(config) != identity;

  bool _generationStale(
    AIConfig config,
    ModelDiscoveryIdentity identity,
    String model,
    AICancellation? cancellation,
  ) =>
      _probeStale(config, identity, cancellation) ||
      config.model.trim() != model;

  ConnectionProbe _cancelledProbe() => const ConnectionProbe(
    endpointAuth: AiProbeStep(
      kind: AiProbeKind.endpointAuth,
      attempted: true,
      ok: false,
      code: 'aiCancelled',
    ),
    modelDiscovery: AiProbeStep(
      kind: AiProbeKind.modelDiscovery,
      attempted: false,
      ok: false,
      code: 'aiCancelled',
    ),
  );

  AiProbeStep _cancelledGeneration() => const AiProbeStep(
    kind: AiProbeKind.modelGeneration,
    attempted: true,
    ok: false,
    code: 'aiCancelled',
  );

  /// One chat-style request against the configured protocol; returns the
  /// assistant text.
  Future<String> requestCompletion({
    required AIConfig config,
    required String systemInstruction,
    required String userPrompt,
    required bool forceJsonObject,
    AICancellation? cancellation,
  }) async {
    final base = _normalizeBase(config.baseUrl);
    if (base.isEmpty || config.apiKey.trim().isEmpty) {
      throw const AIException('aiMissingConfig');
    }

    final selectedModel = config.model;
    if (selectedModel.trim().isEmpty) {
      throw const AIException('aiMissingModel');
    }
    final thinking = planThinking(config);

    Uri uri;
    Map<String, dynamic> body;
    switch (config.protocol) {
      case AIProtocol.openai:
        uri = Uri.parse('$base/chat/completions');
        body = {
          'model': selectedModel,
          'messages': [
            {'role': 'system', 'content': systemInstruction},
            {'role': 'user', 'content': userPrompt},
          ],
          ...thinking.fields,
          if (forceJsonObject) 'response_format': {'type': 'json_object'},
        };
      case AIProtocol.openaiResponses:
        uri = Uri.parse('$base/responses');
        body = {
          'model': selectedModel,
          'instructions': systemInstruction,
          'input': userPrompt,
          ...thinking.fields,
          if (forceJsonObject)
            'text': {
              'format': {'type': 'json_object'},
            },
        };
      case AIProtocol.anthropic:
        uri = Uri.parse('${_anthropicBase(base)}/messages');
        body = {
          'model': selectedModel,
          'max_tokens': _anthropicMaxTokens,
          'system': systemInstruction,
          'messages': [
            {'role': 'user', 'content': userPrompt},
          ],
          ...thinking.fields,
        };
    }

    final req = _postJson(uri.toString(), config, body);

    final res = await _send(req, cancellation: cancellation);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw AIException('aiHttpError', res.statusCode);
    }
    return extractResponseText(
      config.protocol,
      jsonDecode(utf8.decode(res.bodyBytes)),
    );
  }

  // --- internals ---

  http.Request _get(String url, AIConfig config) =>
      http.Request('GET', Uri.parse(url))..headers.addAll(_authHeaders(config));

  http.Request _postJson(
    String url,
    AIConfig config,
    Map<String, dynamic> body,
  ) =>
      http.Request('POST', Uri.parse(url))
        ..headers.addAll({
          'content-type': 'application/json',
          ..._authHeaders(config),
        })
        ..body = jsonEncode(body);

  Future<http.Response> _send(
    http.Request req, {
    AICancellation? cancellation,
  }) async {
    final abort = Completer<void>();
    _requests.add(abort);
    void cancel() {
      if (!abort.isCompleted) abort.complete();
    }

    cancellation?.whenCancelled.then((_) => cancel());
    if (cancellation?.isCancelled ?? false) cancel();
    final request =
        http.AbortableRequest(req.method, req.url, abortTrigger: abort.future)
          ..headers.addAll(req.headers)
          ..bodyBytes = req.bodyBytes;
    try {
      return await (() async =>
              http.Response.fromStream(await _client.send(request)))()
          .timeout(
            timeout,
            onTimeout: () {
              cancel();
              throw TimeoutException('AI timeout');
            },
          );
    } finally {
      _requests.remove(abort);
    }
  }

  ModelDiscoveryIdentity _identity(AIConfig config) {
    try {
      return requireModelDiscoveryIdentity(config);
    } on AiBaseUrlException {
      throw const AIException('aiInvalidUrl');
    } on ModelDiscoveryInputException {
      throw const AIException('aiMissingConfig');
    }
  }

  void _linkCancel(AICancellation? external, AICancellation internal) {
    if (external == null) return;
    if (external.isCancelled) {
      internal.cancel();
      return;
    }
    external.whenCancelled.then((_) => internal.cancel());
  }

  http.Request _modelsRequest(AIConfig config, String base) {
    final preset = getAIProviderPreset(config.provider);
    final path = preset.modelsPath.isNotEmpty ? preset.modelsPath : '/models';
    final root =
        config.protocol == AIProtocol.anthropic ? _anthropicBase(base) : base;
    return _get('$root$path', config);
  }

  /// Minimal generation probe. Thinking extensions are omitted so the call
  /// stays small and does not depend on a model-specific thinking budget.
  http.Request _generationRequest(AIConfig config, String base, String model) {
    switch (config.protocol) {
      case AIProtocol.openai:
        return _postJson('$base/chat/completions', config, {
          'model': model,
          'messages': [
            {'role': 'user', 'content': 'ping'},
          ],
          'max_tokens': 16,
        });
      case AIProtocol.openaiResponses:
        return _postJson('$base/responses', config, {
          'model': model,
          'input': 'ping',
          'max_output_tokens': 16,
        });
      case AIProtocol.anthropic:
        return _postJson('${_anthropicBase(base)}/messages', config, {
          'model': model,
          'max_tokens': 16,
          'messages': [
            {'role': 'user', 'content': 'ping'},
          ],
        });
    }
  }

  Map<String, String> _authHeaders(AIConfig config) {
    if (config.protocol == AIProtocol.anthropic) {
      // x-api-key is the official header; Bearer is added for OpenAI-style proxies.
      return {
        'x-api-key': config.apiKey.trim(),
        'anthropic-version': _anthropicVersion,
        'authorization': 'Bearer ${config.apiKey.trim()}',
      };
    }
    return {'authorization': 'Bearer ${config.apiKey.trim()}'};
  }

  String _normalizeBase(String baseUrl) {
    try {
      return normalizeAiBaseUrl(baseUrl);
    } on AiBaseUrlException {
      throw const AIException('aiInvalidUrl');
    }
  }

  String _anthropicBase(String base) =>
      base.endsWith('/v1') ? base : '$base/v1';

  String _languageSuffix(Language lang) {
    switch (lang) {
      case Language.zh:
        return 'Please answer in Simplified Chinese.';
      case Language.ja:
        return 'Please answer in Japanese.';
      case Language.en:
        return 'Please answer in English.';
    }
  }

  String _sortInstruction(Language lang, bool autoDecompose) => '''
You are an expert productivity assistant based on the Eisenhower Matrix.
Analyze the user's tasks and categorize them into four quadrants by urgency and importance:
1. Urgent and Important (quadrant 1)
2. Not Urgent but Important (quadrant 2)
3. Urgent but Not Important (quadrant 3)
4. Neither Urgent nor Important (quadrant 4)

STRICT RULES:
1. Identify if a task is "Long Term" (requires breakdown). Set isLongTerm=true.
2. ${autoDecompose ? 'IMMEDIATE DECOMPOSITION REQUIRED: If a task is "Long Term" (isLongTerm=true), you MUST break it down NOW into 3-5 actionable, short-term steps and populate the "subtasks" array. DO NOT leave subtasks empty for long term tasks.' : 'DO NOT decompose a single task into steps in this phase. If the input is "Running", just return "Running" with isLongTerm=true and subtasks=[].'}
3. GROUPING LOGIC: Always look for multiple DISTINCT input lines that belong to the same project or category (e.g. inputs "Buy milk", "Buy eggs", "Buy soap"). Merge them into one task titled "Shopping" (or appropriate category) with subtasks ["Buy milk", "Buy eggs", "Buy soap"]. Set isGrouped=true ONLY for merging distinct input lines; decomposition of one task must set isGrouped=false.
4. If an input is a standalone short-term task, leave subtasks empty.
5. The "quadrant" field MUST be the integer 1, 2, 3, or 4 — never a string like "Q1".
6. DO NOT include opinions, advice, preaching, moralizing, or reasons to delete tasks. Keep titles factual and clean. Life, leisure, or entertainment tasks are not a priori "not worth doing". Quadrant 4 is neither-urgent-nor-important, not a command to delete.

Important: Respond with ONLY a JSON object {"tasks": [...]}, no markdown fences, no extra commentary.
The "title" and "subtasks" fields MUST be in the user's language: ${_langName(lang)}.
''';

  String _batchInstruction(Language lang) => '''
You are an expert project manager.
You will receive a list of long-term tasks.
For EACH task, break it down into 3-5 immediate, actionable, short-term steps (subtasks) that can be done in under 2 hours each.

Respond with ONLY a JSON object containing a "tasks" array, no markdown fences, no extra commentary. Copy originalTitle EXACTLY from the input; do not translate or rename it.
Format:
{"tasks": [
  { "originalTitle": "Task Name", "subtasks": ["Step 1", "Step 2", "Step 3"] }
]}

The strings MUST be in the user's language: ${_langName(lang)}.
''';

  String _langName(Language lang) {
    switch (lang) {
      case Language.zh:
        return 'Simplified Chinese';
      case Language.ja:
        return 'Japanese';
      case Language.en:
        return 'English';
    }
  }
}

/// Extract the assistant text from each protocol's response envelope.
String extractResponseText(AIProtocol protocol, dynamic data) {
  if (data is! Map) throw const AIException('aiInvalidResponse');
  if (protocol == AIProtocol.openai) {
    final choices = data['choices'];
    if (choices is! List || choices.isEmpty || choices.first is! Map) {
      throw const AIException('aiInvalidResponse');
    }
    final message = choices.first['message'];
    if (message is! Map || message['content'] is! String) {
      throw const AIException('aiInvalidResponse');
    }
    return message['content'] as String;
  }
  if (protocol == AIProtocol.openaiResponses) {
    final outputText = data['output_text'];
    if (outputText is String && outputText.isNotEmpty) return outputText;
    final parts = <String>[];
    for (final item in (data['output'] as List? ?? [])) {
      if (item is Map && item['type'] == 'message' && item['content'] is List) {
        for (final c in (item['content'] as List)) {
          if (c is Map && c['type'] == 'output_text' && c['text'] is String) {
            parts.add(c['text'] as String);
          }
        }
      }
    }
    return parts.join('');
  }
  if (protocol == AIProtocol.anthropic) {
    final parts = <String>[];
    for (final c in (data['content'] as List? ?? [])) {
      if (c is Map && c['type'] == 'text' && c['text'] is String) {
        parts.add(c['text'] as String);
      }
    }
    return parts.join('');
  }
  return '';
}

List<String> _subtaskTitles(dynamic raw) {
  if (raw == null) return [];
  if (raw is! List || raw.any((s) => s is! String || s.trim().isEmpty)) {
    throw const AIException('aiInvalidResponse');
  }
  return raw.cast<String>().map((s) => s.trim()).toList();
}

/// Robust JSON array extraction: direct parse, fence stripping, regex fallbacks.
List<dynamic> extractJsonArray(String text) {
  if (text.isEmpty) return [];
  final cleaned = text.replaceAll(RegExp(r'```[a-zA-Z]*\s*'), '').trim();
  final direct = _tryArray(cleaned);
  if (direct != null) return direct;
  final arrMatch = RegExp(r'\[[\s\S]*\]').firstMatch(cleaned);
  if (arrMatch != null) {
    final arr = _tryArray(arrMatch.group(0)!);
    if (arr != null) return arr;
  }
  final objMatch = RegExp(r'\{[\s\S]*\}').firstMatch(cleaned);
  if (objMatch != null) {
    final obj = _tryArray(objMatch.group(0)!);
    if (obj != null) return obj;
  }
  return [];
}

List<dynamic>? _tryArray(String raw) {
  try {
    final parsed = jsonDecode(raw);
    if (parsed is List) return parsed;
    if (parsed is Map) {
      if (parsed['tasks'] is List) return parsed['tasks'] as List;
      if (parsed['data'] is List) return parsed['data'] as List;
      return [parsed];
    }
  } catch (_) {}
  return null;
}
