/// Content tags and civil-day helpers for the WP18-R sync experiment.
///
/// The digest is the product's own pure-Dart SHA-256 (`recoverySha256Hex`, the
/// same function a recovery archive uses for its `archiveId` and
/// `prefixSha256`), so an envelope tag is comparable with the bytes the backup
/// flow already checks, and no new dependency is needed.
library;

import 'dart:convert';

import 'package:matrixflow_native/recovery_text.dart' show recoverySha256Hex;

/// Encodes [value] so equal content always produces equal text, regardless of
/// the order a device happened to write its JSON keys in.
String canonicalJson(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((k) => k.toString()).toList()..sort();
    final buffer = StringBuffer('{');
    for (var i = 0; i < keys.length; i++) {
      if (i > 0) buffer.write(',');
      buffer.write(jsonEncode(keys[i]));
      buffer.write(':');
      buffer.write(canonicalJson(value[keys[i]]));
    }
    return '$buffer}';
  }
  if (value is List) {
    return '[${value.map(canonicalJson).join(',')}]';
  }
  return jsonEncode(value);
}

/// Lowercase hex SHA-256 over the canonical form of [value].
String contentDigest(Object? value) =>
    recoverySha256Hex(utf8.encode(canonicalJson(value)));

const _msPerDay = 86400000;

/// Days since the epoch for an instant [epochMs] as seen at [zoneOffsetMinutes].
///
/// `plannedDate` and `deadline` in the backup contract are local civil
/// midnights (BACKUP_FORMAT.md), so two devices in different zones can write
/// different epoch values for the same planned day. Comparing the raw integers
/// alone manufactures a conflict that the user never made.
int civilDayNumber(int epochMs, int zoneOffsetMinutes) {
  final shifted = epochMs + zoneOffsetMinutes * 60000;
  return shifted >= 0
      ? shifted ~/ _msPerDay
      : -((-shifted + _msPerDay - 1) ~/ _msPerDay);
}

/// ISO-like `yyyy-mm-dd` label for [epochMs] at [zoneOffsetMinutes].
String civilDayLabel(int epochMs, int zoneOffsetMinutes) {
  final day = civilDayNumber(epochMs, zoneOffsetMinutes);
  final date = DateTime.utc(1970).add(Duration(days: day));
  String two(int v) => v.toString().padLeft(2, '0');
  return '${date.year}-${two(date.month)}-${two(date.day)}';
}

/// True when both instants name the same civil calendar day on their own zone.
bool isSameCivilDay({
  required int leftMs,
  required int rightMs,
  required int leftZoneOffsetMinutes,
  required int rightZoneOffsetMinutes,
}) => civilDayNumber(leftMs, leftZoneOffsetMinutes) ==
    civilDayNumber(rightMs, rightZoneOffsetMinutes);

/// Wall-clock label for reports. Deliberately derived, never trusted as order.
String instantLabel(int epochMs) =>
    DateTime.fromMillisecondsSinceEpoch(epochMs, isUtc: true).toIso8601String();
