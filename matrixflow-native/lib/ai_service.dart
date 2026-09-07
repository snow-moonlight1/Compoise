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

const aiRequestTimeout = Duration(seconds: 30);

class AIService {
  AIService({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  static const _anthropicVersion = '2023-06-01';
  static const _anthropicMaxTokens = 8192;

  Future<List<AIAnalysisResult>> analyzeTasks({
    required List<String> inputs,
    required AIConfig config,
    required Language language,
    required bool autoDecompose,
  }) async {
    final text = await requestCompletion(
      config: config,
      systemInstruction: _sortInstruction(language, autoDecompose),
      userPrompt:
          'Here are the tasks to analyze: ${jsonEncode(inputs)}. \n\nImportant: ${_languageSuffix(language)}',
      forceJsonObject: config.protocol != AIProtocol.anthropic,
    );
    return extractJsonArray(text)
        .whereType<Map<String, dynamic>>()
        .map((item) => AIAnalysisResult(
              title: (item['title'] as String?) ?? '',
              quadrant: normalizeQuadrant(item['quadrant']),
              isLongTerm: (item['isLongTerm'] as bool?) ?? false,
              reasoning: item['reasoning'] as String?,
              subtasks: ((item['subtasks'] as List?) ?? [])
                  .map((e) => e.toString())
                  .toList(),
            ))
        .where((r) => r.title.isNotEmpty)
        .toList();
  }

  Future<List<DecomposeResult>> decomposeBatch({
    required List<String> taskTitles,
    required AIConfig config,
    required Language language,
  }) async {
    final text = await requestCompletion(
      config: config,
      systemInstruction: _batchInstruction(language),
      userPrompt:
          'Break down these tasks: ${jsonEncode(taskTitles)}. \n\nImportant: ${_languageSuffix(language)}',
      forceJsonObject: config.protocol != AIProtocol.anthropic,
    );
    return extractJsonArray(text)
        .whereType<Map<String, dynamic>>()
        .where((item) => item['originalTitle'] is String)
        .map((item) => DecomposeResult(
              originalTitle: item['originalTitle'] as String,
              subtasks: ((item['subtasks'] as List?) ?? [])
                  .map((e) => e.toString())
                  .toList(),
            ))
        .toList();
  }

  Future<TestResult> testConnection(AIConfig config) async {
    final base = _normalizeBase(config.baseUrl);
    if (base.isEmpty || config.apiKey.isEmpty) {
      return TestResult(false, 'URL / KEY');
    }
    try {
      if (config.protocol == AIProtocol.anthropic) {
        var res = await _send(_get('$base/v1/models', config));
        if (res.statusCode == 404 || res.statusCode == 405) {
          // Proxy without a models list: prove liveness with a 1-token completion.
          res = await _send(_postJson('$base/v1/messages', config, {
            'model': config.model.isEmpty ? 'claude-3-5-haiku-latest' : config.model,
            'max_tokens': 1,
            'messages': [
              {'role': 'user', 'content': 'hi'}
            ],
          }));
        }
        return _fromStatus(res, 'Anthropic');
      }
      final res = await _send(_get('$base/models', config));
      return _fromStatus(res, AIProtocolX.toWire(config.protocol));
    } catch (e) {
      return TestResult(false, _friendly(e));
    } finally {
      // keep client alive for reuse
    }
  }

  /// One chat-style request against the configured protocol; returns the
  /// assistant text.
  Future<String> requestCompletion({
    required AIConfig config,
    required String systemInstruction,
    required String userPrompt,
    required bool forceJsonObject,
  }) async {
    final base = _normalizeBase(config.baseUrl);
    if (base.isEmpty || config.apiKey.isEmpty) {
      throw Exception('Missing AI endpoint configuration');
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
          if (forceJsonObject) 'text': {
            'format': {'type': 'json_object'}
          },
        };
      case AIProtocol.anthropic:
        uri = Uri.parse('$base/v1/messages');
        body = {
          'model': config.model.isEmpty ? 'claude-3-5-haiku-latest' : config.model,
          'max_tokens': _anthropicMaxTokens,
          'system': systemInstruction,
          'messages': [
            {'role': 'user', 'content': userPrompt},
          ],
        };
    }

    final req = _postJson(uri.toString(), config, body);

    final res = await _send(req);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('API Error ${res.statusCode}: ${res.body.length > 200 ? res.body.substring(0, 200) : res.body}');
    }
    return extractResponseText(config.protocol, jsonDecode(utf8.decode(res.bodyBytes)));
  }

  // --- internals ---

  http.Request _get(String url, AIConfig config) =>
      http.Request('GET', Uri.parse(url))..headers.addAll(_authHeaders(config));

  http.Request _postJson(String url, AIConfig config, Map<String, dynamic> body) =>
      http.Request('POST', Uri.parse(url))
        ..headers.addAll({'content-type': 'application/json', ..._authHeaders(config)})
        ..body = jsonEncode(body);

  Future<http.Response> _send(http.Request req) async {
    final res = await _client.send(req).timeout(aiRequestTimeout, onTimeout: () {
      throw TimeoutException('Request timed out (30s)');
    });
    return http.Response.fromStream(res).timeout(aiRequestTimeout);
  }

  TestResult _fromStatus(http.Response res, String label) {
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return TestResult(true, 'OK ($label)');
    }
    return TestResult(false, '${res.statusCode} ${res.reasonPhrase ?? ''}'.trim());
  }

  String _friendly(Object e) {
    if (e is TimeoutException) return e.message ?? 'Request timed out (30s)';
    return e.toString();
  }

  Map<String, String> _authHeaders(AIConfig config) {
    if (config.protocol == AIProtocol.anthropic) {
      // x-api-key is the official header; Bearer is added for OpenAI-style proxies.
      return {
        'x-api-key': config.apiKey,
        'anthropic-version': _anthropicVersion,
        'authorization': 'Bearer ${config.apiKey}',
      };
    }
    return {'authorization': 'Bearer ${config.apiKey}'};
  }

  String _normalizeBase(String baseUrl) {
    var base = baseUrl.trim();
    if (base.isNotEmpty && !base.toLowerCase().startsWith('http')) base = 'https://$base';
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    return base;
  }

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
3. GROUPING LOGIC: Always look for multiple DISTINCT input lines that belong to the same project or category (e.g. inputs "Buy milk", "Buy eggs", "Buy soap"). Merge them into one task titled "Shopping" (or appropriate category) with subtasks ["Buy milk", "Buy eggs", "Buy soap"].
4. If an input is a standalone short-term task, leave subtasks empty.
5. The "quadrant" field MUST be the integer 1, 2, 3, or 4 — never a string like "Q1".

Important: Respond with ONLY the JSON array, no markdown fences, no extra commentary.
The "title", "reasoning", and "subtasks" fields MUST be in the user's language: ${_langName(lang)}.
''';

  String _batchInstruction(Language lang) => '''
You are an expert project manager.
You will receive a list of long-term tasks.
For EACH task, break it down into 3-5 immediate, actionable, short-term steps (subtasks) that can be done in under 2 hours each.

Respond with ONLY a JSON array of objects, no markdown fences, no extra commentary.
Format:
[
  { "originalTitle": "Task Name", "subtasks": ["Step 1", "Step 2", "Step 3"] }
]

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
  if (protocol == AIProtocol.openai) {
    return (data?['choices']?[0]?['message']?['content'] as String?) ?? '';
  }
  if (protocol == AIProtocol.openaiResponses) {
    final outputText = data?['output_text'];
    if (outputText is String && outputText.isNotEmpty) return outputText;
    final parts = <String>[];
    for (final item in (data?['output'] as List? ?? [])) {
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
    for (final c in (data?['content'] as List? ?? [])) {
      if (c is Map && c['type'] == 'text' && c['text'] is String) {
        parts.add(c['text'] as String);
      }
    }
    return parts.join('');
  }
  return '';
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
