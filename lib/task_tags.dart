/// Canonical tag handling shared by the task model, queries and editors.
///
/// Tags only ever live on a parent task, and a multi-tag filter is an AND: a
/// task matches when it owns every requested tag. Comparison ignores case and
/// surrounding whitespace, while the first spelling the user typed is what gets
/// stored and displayed.
library;

/// The comparable form of a tag: trimmed and lower-cased.
String tagKey(String tag) => tag.trim().toLowerCase();

/// Normalises raw input — a decoded JSON value or an editor draft — into the
/// stored shape: trimmed entries, blanks dropped, and for tags that differ only
/// by case the first spelling wins.
///
/// The result is always a growable list so callers can keep editing it. Throws
/// [FormatException] when [raw] is neither null nor a list of strings, so a
/// corrupt backup field is rejected instead of silently discarded.
List<String> normalizeTags(Object? raw) {
  if (raw == null) return <String>[];
  if (raw is! List) throw const FormatException('Invalid tags');
  final seen = <String>{};
  final tags = <String>[];
  for (final entry in raw) {
    if (entry is! String) throw const FormatException('Invalid tags');
    final tag = entry.trim();
    if (tag.isEmpty) continue;
    if (!seen.add(tag.toLowerCase())) continue;
    tags.add(tag);
  }
  return tags;
}

/// The comparable keys of [tags], blanks dropped.
Set<String> tagKeys(Iterable<String> tags) {
  final keys = <String>{};
  for (final tag in tags) {
    final key = tagKey(tag);
    if (key.isEmpty) continue;
    keys.add(key);
  }
  return keys;
}

/// Whether [taskTags] satisfies every key in [required]. An empty requirement
/// matches every task, so an unfiltered query keeps its original path.
bool taskHasAllTags(List<String> taskTags, Set<String> required) {
  if (required.isEmpty) return true;
  return required.difference(tagKeys(taskTags)).isEmpty;
}

/// Whether two tag lists hold the same tags in the same order. Tag values are
/// user text, so this compares spellings exactly; use [tagKeys] to compare
/// case-insensitively.
bool sameTagList(List<String> left, List<String> right) {
  if (identical(left, right)) return true;
  if (left.length != right.length) return false;
  for (var i = 0; i < left.length; i++) {
    if (left[i] != right[i]) return false;
  }
  return true;
}
