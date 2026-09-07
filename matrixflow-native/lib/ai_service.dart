/// The three AI wire protocols (OpenAI compatible / OpenAI Responses / Anthropic
/// Messages). Request and response shapes follow the provider ecosystems — the
/// same conventions the web app's aiService.ts uses.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

class TestResult {
  final bool ok;
  final String message;
  TestResult(this.ok, this.message);
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

  Future<TestResult> testConnection(AIConfig config) async {
    try {
      final base = _normalizeBase(config.baseUrl);
      if (base.isEmpty || config.apiKey.trim().isEmpty) {
        return TestResult(false, 'aiMissingConfig');
      }
      if (config.protocol == AIProtocol.anthropic) {
        var res = await _send(_get('${_anthropicBase(base)}/models', config));
        if (res.statusCode == 404 || res.statusCode == 405) {
          // Proxy without a models list: prove liveness with a 1-token completion.
          res = await _send(
            _postJson('${_anthropicBase(base)}/messages', config, {
              'model':
                  config.model.isEmpty
                      ? 'claude-3-5-haiku-latest'
                      : config.model,
              'max_tokens': 1,
              'messages': [
                {'role': 'user', 'content': 'hi'},
              ],
            }),
          );
        }
        return _fromStatus(res, 'Anthropic');
      }
      final res = await _send(_get('$base/models', config));
      return _fromStatus(res, AIProtocolX.toWire(config.protocol));
    } catch (e) {
      return TestResult(
        false,
        e is TimeoutException
            ? 'requestTimeout'
            : e is AIException
            ? e.code
            : 'aiNetworkError',
      );
    }
  }

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

    Uri uri;
    Map<String, dynamic> body;
    switch (config.protocol) {
      case AIProtocol.openai:
        uri = Uri.parse('$base/chat/completions');
        body = {
          'model': config.model.isEmpty ? 'gpt-4o-mini' : config.model,
          'messages': [
            {'role': 'system', 'content': systemInstruction},
            {'role': 'user', 'content': userPrompt},
          ],
          if (forceJsonObject) 'response_format': {'type': 'json_object'},
        };
      case AIProtocol.openaiResponses:
        uri = Uri.parse('$base/responses');
        body = {
          'model': config.model.isEmpty ? 'gpt-4o-mini' : config.model,
          'instructions': systemInstruction,
          'input': userPrompt,
          if (forceJsonObject)
            'text': {
              'format': {'type': 'json_object'},
            },
        };
      case AIProtocol.anthropic:
        uri = Uri.parse('${_anthropicBase(base)}/messages');
        body = {
          'model':
              config.model.isEmpty ? 'claude-3-5-haiku-latest' : config.model,
          'max_tokens': _anthropicMaxTokens,
          'system': systemInstruction,
          'messages': [
            {'role': 'user', 'content': userPrompt},
          ],
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

  TestResult _fromStatus(http.Response res, String label) {
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return TestResult(true, 'OK ($label)');
    }
    return TestResult(
      false,
      '${res.statusCode} ${res.reasonPhrase ?? ''}'.trim(),
    );
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
    var base = baseUrl.trim();
    if (base.isEmpty) return '';
    if (!base.contains('://')) base = 'https://$base';
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    final uri = Uri.tryParse(base);
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.userInfo.isNotEmpty) {
      throw const AIException('aiInvalidUrl');
    }
    return base;
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
Analyze the user's tasks and categorize them into four quadrants:
1. Urgent & Important (Do First)
2. Not Urgent & Important (Schedule)
3. Urgent & Not Important (Delegate)
4. Not Urgent & Not Important (Don't Do/Delete)

STRICT RULES:
1. Identify if a task is "Long Term" (requires breakdown). Set isLongTerm=true.
2. ${autoDecompose ? 'IMMEDIATE DECOMPOSITION REQUIRED: If a task is "Long Term" (isLongTerm=true), you MUST break it down NOW into 3-5 actionable, short-term steps and populate the "subtasks" array. DO NOT leave subtasks empty for long term tasks.' : 'DO NOT decompose a single task into steps in this phase. If the input is "Running", just return "Running" with isLongTerm=true and subtasks=[].'}
3. GROUPING LOGIC: Always look for multiple DISTINCT input lines that belong to the same project or category (e.g. inputs "Buy milk", "Buy eggs", "Buy soap"). Merge them into one task titled "Shopping" (or appropriate category) with subtasks ["Buy milk", "Buy eggs", "Buy soap"]. Set isGrouped=true ONLY for merging distinct input lines; decomposition of one task must set isGrouped=false.
4. If an input is a standalone short-term task, leave subtasks empty.
5. The "quadrant" field MUST be the integer 1, 2, 3, or 4 — never a string like "Q1".

Important: Respond with ONLY a JSON object {"tasks": [...]}, no markdown fences, no extra commentary.
The "title", "reasoning", and "subtasks" fields MUST be in the user's language: ${_langName(lang)}.
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
