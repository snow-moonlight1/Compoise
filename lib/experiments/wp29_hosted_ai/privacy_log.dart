import 'dart:convert';
import 'dart:typed_data';

/// Ordinary log for the hosted-AI experiment.
///
/// Task text, image bytes, prompts, and secrets are not accepted as field
/// values. A sealed secret is stripped even if a caller puts it in an
/// allowed field.
class PrivacyLog {
  final _lines = <String>[];
  final _secrets = <String>{};

  static const bannedKeys = {
    'text',
    'task_text',
    'body',
    'prompt',
    'image',
    'image_bytes',
    'title',
    'notes',
    'content',
    'purpose',
    'api_key',
    'apikey',
    'authorization',
    'secret',
    'token',
    'raw',
    'customapikey',
  };

  void seal(String secret) {
    if (secret.length >= 8) _secrets.add(secret);
  }

  void sealBytes(Uint8List bytes) {
    if (bytes.isEmpty) return;
    seal(base64Encode(bytes));
  }

  void event(String code, [Map<String, Object?> fields = const {}]) {
    final safe = <String, Object?>{};
    fields.forEach((key, value) {
      final normalized = key.toLowerCase().replaceAll('-', '_');
      if (bannedKeys.contains(normalized) || value is Map || value is List) {
        safe[normalized] = 'redacted';
        safe['${normalized}_span'] = _span(value);
        return;
      }
      if (value is String && _containsSecret(value)) {
        safe[normalized] = 'redacted';
        safe['${normalized}_span'] = value.length;
        return;
      }
      safe[normalized] = value;
    });
    final line = '$code ${jsonEncode(safe)}';
    _lines.add(_containsSecret(line) ? '$code {"redacted":true}' : line);
  }

  String dump() => _lines.join('\n');

  List<String> get lines => List.unmodifiable(_lines);

  bool _containsSecret(String value) {
    for (final secret in _secrets) {
      if (value.contains(secret)) return true;
    }
    return false;
  }

  int _span(Object? value) {
    if (value is String) return value.length;
    if (value is List) return value.length;
    if (value is Uint8List) return value.length;
    return 0;
  }
}
