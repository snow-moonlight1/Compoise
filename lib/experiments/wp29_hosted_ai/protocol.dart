import 'dart:convert';
import 'dart:typed_data';

/// Keyless hosted-AI envelope. No upstream provider key exists on this type.
///
/// `compoise.hosted-ai.v0` is an experiment contract. It is not wired into
/// the production AI client, and it is not a deployed service.
const hostedProtocolVersion = '0';

enum HostedErrorCode {
  selectionRequired,
  selectionTooLarge,
  consentRequired,
  confirmationPending,
  notReady,
  wrongPhase,
  budgetExceeded,
  capabilityRejected,
  capabilityChanged,
  timeout,
  rateLimited,
  authInvalid,
  quotaExhausted,
  duplicate,
  maxResponseExceeded,
  schemaInvalid,
  incomplete,
  transport,
  cancelled,
  closed,
  lateResultDropped,
}

class HostedFailure implements Exception {
  final HostedErrorCode code;

  const HostedFailure(this.code);

  @override
  String toString() => 'HostedFailure(${code.name})';
}

/// Text the user explicitly chose to send, plus an optional image opt-in.
class TaskSelection {
  final String text;
  final bool includeImage;
  final Uint8List? image;

  TaskSelection({
    required this.text,
    Uint8List? imageBytes,
    this.includeImage = false,
  }) : image = includeImage ? imageBytes : null {
    if (text.trim().isEmpty) {
      throw const HostedFailure(HostedErrorCode.selectionRequired);
    }
    if (includeImage && (imageBytes == null || imageBytes.isEmpty)) {
      throw const HostedFailure(HostedErrorCode.selectionRequired);
    }
    if (!includeImage && imageBytes != null) {
      throw const HostedFailure(HostedErrorCode.selectionRequired);
    }
  }

  @override
  String toString() =>
      'TaskSelection(chars:${text.length},image:${image?.length ?? 0})';
}

class CapabilitySnapshot {
  final String modelId;
  final bool vision;
  final int maxOutputTokens;

  const CapabilitySnapshot({
    required this.modelId,
    required this.vision,
    required this.maxOutputTokens,
  });

  String get fingerprint =>
      fnv1a64('$modelId|vision=$vision|maxOut=$maxOutputTokens');

  @override
  String toString() => 'CapabilitySnapshot($fingerprint)';
}

class ConsentRecord {
  final String id;
  final String purpose;
  final String selectionFingerprint;
  final String capabilityFingerprint;
  final DateTime at;

  const ConsentRecord({
    required this.id,
    required this.purpose,
    required this.selectionFingerprint,
    required this.capabilityFingerprint,
    required this.at,
  });

  @override
  String toString() => 'ConsentRecord($id,purposeChars:${purpose.length})';
}

/// Fields a human may apply after schema validation. Quadrant values match
/// the app's 1..4 ids without importing production code.
class TaskSuggestion {
  final String title;
  final String? notes;
  final int? quadrant;

  const TaskSuggestion({required this.title, this.notes, this.quadrant});

  @override
  String toString() => 'TaskSuggestion(chars:${title.length})';
}

const suggestionKeys = {'title', 'notes', 'quadrant'};

TaskSuggestion parseSuggestion(String raw) {
  Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException {
    throw const HostedFailure(HostedErrorCode.schemaInvalid);
  }
  if (decoded is! Map) {
    throw const HostedFailure(HostedErrorCode.schemaInvalid);
  }
  final map = <String, Object?>{};
  for (final entry in decoded.entries) {
    final key = entry.key;
    if (key is! String || !suggestionKeys.contains(key)) {
      throw const HostedFailure(HostedErrorCode.schemaInvalid);
    }
    map[key] = entry.value;
  }
  final title = map['title'];
  if (title is! String || title.trim().isEmpty || title.length > 200) {
    throw const HostedFailure(HostedErrorCode.schemaInvalid);
  }
  final notes = map['notes'];
  if (notes != null && (notes is! String || notes.length > 2000)) {
    throw const HostedFailure(HostedErrorCode.schemaInvalid);
  }
  final quadrant = map['quadrant'];
  int? quadrantValue;
  if (quadrant != null) {
    if (quadrant is! int || quadrant < 1 || quadrant > 4) {
      throw const HostedFailure(HostedErrorCode.schemaInvalid);
    }
    quadrantValue = quadrant;
  }
  return TaskSuggestion(
    title: title,
    notes: notes as String?,
    quadrant: quadrantValue,
  );
}

class HostedRequest {
  final String requestId;
  final String consentId;
  final String selectionFingerprint;
  final bool stream;
  final int maxOutputTokens;
  final String capabilityFingerprint;
  final String taskText;
  final Uint8List? imageBytes;
  final int attempt;

  HostedRequest({
    required this.requestId,
    required this.consentId,
    required this.selectionFingerprint,
    required this.stream,
    required this.maxOutputTokens,
    required this.capabilityFingerprint,
    required this.taskText,
    required this.imageBytes,
    required this.attempt,
  });

  String get imageFingerprint =>
      imageBytes == null ? '' : fnv1a64Bytes(imageBytes!);

  /// Body a transport may send. Image bytes stay off this map; they ride on
  /// [imageBytes] so a JSON log of the map cannot print them.
  Map<String, Object?> toJson() => {
    'v': hostedProtocolVersion,
    'request_id': requestId,
    'consent_id': consentId,
    'selection_fingerprint': selectionFingerprint,
    'stream': stream,
    'max_output_tokens': maxOutputTokens,
    'capability_fingerprint': capabilityFingerprint,
    'task_text': taskText,
    'image_present': imageBytes != null,
    'image_byte_length': imageBytes?.length ?? 0,
    'image_fingerprint': imageFingerprint,
    'attempt': attempt,
  };

  /// Ordinary log view. Task text is omitted on purpose.
  Map<String, Object?> logView() => {
    'v': hostedProtocolVersion,
    'request_id': requestId,
    'consent_id': consentId,
    'selection_fingerprint': selectionFingerprint,
    'stream': stream,
    'max_output_tokens': maxOutputTokens,
    'capability_fingerprint': capabilityFingerprint,
    'task_chars': taskText.length,
    'image_present': imageBytes != null,
    'image_byte_length': imageBytes?.length ?? 0,
    'image_fingerprint': imageFingerprint,
    'attempt': attempt,
  };

  @override
  String toString() => 'HostedRequest($requestId,attempt:$attempt)';
}

const envelopeSecretKeys = {
  'api_key',
  'apikey',
  'apiKey',
  'authorization',
  'secret',
  'token',
  'customApiKey',
};

String selectionFingerprint(TaskSelection selection) {
  final image = selection.image;
  final imageMark = image == null ? '' : fnv1a64Bytes(image);
  return fnv1a64(
    '${selection.text}\u0000${selection.includeImage}\u0000$imageMark',
  );
}

String fnv1a64(String input) {
  var hash = 0xcbf29ce484222325;
  for (final unit in input.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}

String fnv1a64Bytes(Uint8List bytes) {
  var hash = 0xcbf29ce484222325;
  for (final unit in bytes) {
    hash ^= unit;
    hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}
