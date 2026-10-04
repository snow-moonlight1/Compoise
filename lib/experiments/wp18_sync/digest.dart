/// Content tags and civil-day helpers for the WP18-R sync experiment.
///
/// The digests here are prototype-grade: FNV-1a plus a djb2 second stream is
/// enough to notice a torn or reordered payload inside this offline lab, and it
/// is not a security property. A real transport has to negotiate a stronger
/// digest before any of this is wired to the Store.
library;

import 'dart:convert';

const _fnvOffset = 0x811c9dc5;
const _fnvPrime = 16777619;
const _mask32 = 0xffffffff;

/// Encumes [value] so equal content always produces equal text, regardless of
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

/// A 16-hex-character content tag over the canonical form of [value].
String contentDigest(Object? value) => _digestOf(canonicalJson(value));

String _digestOf(String text) {
  var fnv = _fnvOffset;
  var djb = 5381;
  for (final byte in utf8.encode(text)) {
    fnv = ((fnv ^ byte) * _fnvPrime) & _mask32;
    djb = ((djb * 33) + byte) & _mask32;
  }
  return '${fnv.toRadixString(16).padLeft(8, '0')}'
      '${djb.toRadixString(16).padLeft(8, '0')}';
}

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
