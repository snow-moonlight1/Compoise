import 'models.dart';

/// Thrown when a base URL cannot be used as an AI endpoint.
class AiBaseUrlException implements Exception {
  const AiBaseUrlException();
}

/// Thrown when provider identity cannot be formed because URL or key is missing.
class ModelDiscoveryInputException implements Exception {
  const ModelDiscoveryInputException();
}

/// Canonical HTTP(S) base URL: trimmed, scheme/host lowercased, default port and
/// trailing slash removed. Query, fragment and userinfo are rejected.
///
/// Empty input returns an empty string. Invalid input throws [AiBaseUrlException].
String normalizeAiBaseUrl(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return '';
  final withScheme = trimmed.contains('://') ? trimmed : 'https://$trimmed';
  final stripped = _stripTrailingSlashes(withScheme);
  final uri = Uri.tryParse(stripped);
  if (uri == null ||
      !['http', 'https'].contains(uri.scheme.toLowerCase()) ||
      uri.host.isEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      uri.userInfo.isNotEmpty) {
    throw const AiBaseUrlException();
  }
  final scheme = uri.scheme.toLowerCase();
  final host = uri.host.toLowerCase();
  final dropPort =
      !uri.hasPort ||
      (scheme == 'https' && uri.port == 443) ||
      (scheme == 'http' && uri.port == 80);
  final port = dropPort ? '' : ':${uri.port}';
  return '$scheme://$host$port${uri.path}';
}

String? tryNormalizeAiBaseUrl(String raw) {
  try {
    return normalizeAiBaseUrl(raw);
  } on AiBaseUrlException {
    return null;
  }
}

String _stripTrailingSlashes(String value) {
  var base = value;
  while (base.endsWith('/')) {
    base = base.substring(0, base.length - 1);
  }
  return base;
}

/// Identity of a model-discovery request.
///
/// Provider, normalized base URL, protocol and credential all participate in
/// equality. The credential is not part of [diagnosticLabel] or [toString].
class ModelDiscoveryIdentity {
  final String provider;
  final String normalizedBaseUrl;
  final AIProtocol protocol;
  final String _credential;

  ModelDiscoveryIdentity._({
    required this.provider,
    required this.normalizedBaseUrl,
    required this.protocol,
    required String credential,
  }) : _credential = credential;

  String get diagnosticLabel =>
      '$provider|${AIProtocolX.toWire(protocol)}|$normalizedBaseUrl|credential:redacted';

  @override
  String toString() => 'ModelDiscoveryIdentity($diagnosticLabel)';

  @override
  bool operator ==(Object other) =>
      other is ModelDiscoveryIdentity &&
      provider == other.provider &&
      normalizedBaseUrl == other.normalizedBaseUrl &&
      protocol == other.protocol &&
      _credential == other._credential;

  @override
  int get hashCode =>
      Object.hash(provider, normalizedBaseUrl, protocol, _credential);
}

/// Null when the URL is invalid or the base URL / credential is empty.
ModelDiscoveryIdentity? tryModelDiscoveryIdentity(AIConfig config) {
  final base = tryNormalizeAiBaseUrl(config.baseUrl);
  final credential = config.apiKey.trim();
  if (base == null || base.isEmpty || credential.isEmpty) return null;
  return ModelDiscoveryIdentity._(
    provider: config.provider,
    normalizedBaseUrl: base,
    protocol: config.protocol,
    credential: credential,
  );
}

ModelDiscoveryIdentity requireModelDiscoveryIdentity(AIConfig config) {
  final base = normalizeAiBaseUrl(config.baseUrl);
  final credential = config.apiKey.trim();
  if (base.isEmpty || credential.isEmpty) {
    throw const ModelDiscoveryInputException();
  }
  return ModelDiscoveryIdentity._(
    provider: config.provider,
    normalizedBaseUrl: base,
    protocol: config.protocol,
    credential: credential,
  );
}
