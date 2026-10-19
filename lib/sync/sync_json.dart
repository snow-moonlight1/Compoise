/// JSON helpers shared by the sync engine.
///
/// Two devices must agree on whether a value changed and on which of two
/// values wins a tie, so comparisons of structured values go through one
/// encoding with sorted object keys. Plain values compare directly, which is
/// most of them.
library;

import 'dart:convert';

/// Encodes [value] with object keys sorted at every level.
String canonicalJson(Object? value) => jsonEncode(_canonical(value));

Object? _canonical(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((k) => '$k').toList()..sort();
    return {for (final key in keys) key: _canonical(value[key])};
  }
  if (value is List) return [for (final item in value) _canonical(item)];
  if (value is double && value == value.truncateToDouble()) {
    // JSON decoding can produce 3.0 for 3; treat them as the same value.
    if (value.abs() < 9007199254740992) return value.toInt();
  }
  return value;
}

bool _isStructured(Object? value) => value is Map || value is List;

/// True when [a] and [b] encode to the same canonical JSON.
bool sameJson(Object? a, Object? b) {
  if (!_isStructured(a) && !_isStructured(b)) {
    // num == num already treats 3 and 3.0 as equal.
    return a == b;
  }
  return canonicalJson(a) == canonicalJson(b);
}

/// Deep copy of a JSON value, so callers can never mutate shared state.
Object? jsonCopy(Object? value) {
  if (value is Map) {
    return <String, Object?>{
      for (final entry in value.entries) '${entry.key}': jsonCopy(entry.value),
    };
  }
  if (value is List) return [for (final item in value) jsonCopy(item)];
  return value;
}
