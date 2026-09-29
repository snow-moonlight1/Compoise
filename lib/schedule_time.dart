/// Pure calendar and interval rules for WP15. No Store or platform clock access.
library;

import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

const int maxScheduleTimestampMs = 8640000000000000;
const int _dayMs = Duration.millisecondsPerDay;

enum ScheduleTimeError {
  invalidDate,
  invalidClock,
  unknownZone,
  gap,
  fold,
  offset,
}

class ScheduleTimeException implements Exception {
  const ScheduleTimeException(this.reason);
  final ScheduleTimeError reason;

  @override
  String toString() => 'ScheduleTimeException: ${reason.name}';
}

/// Initialized lazily so model decoding and pure queries work without an app
/// startup hook. The same bundled IANA database is used on all three platforms.
tz.Location scheduleLocation(String id) {
  if (id.isEmpty || id.trim() != id) {
    throw const ScheduleTimeException(ScheduleTimeError.unknownZone);
  }
  if (!tz.timeZoneDatabase.isInitialized) tz_data.initializeTimeZones();
  try {
    return tz.getLocation(id);
  } on tz.LocationNotFoundException {
    throw const ScheduleTimeException(ScheduleTimeError.unknownZone);
  }
}

class ScheduleCivilDate {
  ScheduleCivilDate(this.year, this.month, this.day) {
    if (year < 1 ||
        year > 9999 ||
        month < 1 ||
        month > 12 ||
        day < 1 ||
        day > 31) {
      throw const ScheduleTimeException(ScheduleTimeError.invalidDate);
    }
    final normalized = DateTime.utc(year, month, day);
    if (normalized.year != year ||
        normalized.month != month ||
        normalized.day != day) {
      throw const ScheduleTimeException(ScheduleTimeError.invalidDate);
    }
  }

  final int year;
  final int month;
  final int day;

  ScheduleCivilDate addDays(int days) {
    final next = DateTime.utc(year, month, day + days);
    return ScheduleCivilDate(next.year, next.month, next.day);
  }
}

class ScheduleWallTime {
  ScheduleWallTime(
    this.date, {
    required this.hour,
    required this.minute,
    this.second = 0,
    this.millisecond = 0,
  }) {
    if (hour < 0 ||
        hour > 23 ||
        minute < 0 ||
        minute > 59 ||
        second < 0 ||
        second > 59 ||
        millisecond < 0 ||
        millisecond > 999) {
      throw const ScheduleTimeException(ScheduleTimeError.invalidClock);
    }
  }

  final ScheduleCivilDate date;
  final int hour;
  final int minute;
  final int second;
  final int millisecond;
}

class ScheduleWallCandidate {
  const ScheduleWallCandidate(this.instantMs, this.offset, this.abbreviation);
  final int instantMs;
  final Duration offset;
  final String abbreviation;
}

/// Returns zero candidates for a DST gap and two for a normal DST fold.
/// Enumerating database offsets and round-tripping each instant avoids the
/// timezone package's constructor silently choosing a gap/fold interpretation.
List<ScheduleWallCandidate> wallTimeCandidates(
  ScheduleWallTime wall,
  String timeZoneId,
) {
  final location = scheduleLocation(timeZoneId);
  final naiveMs = DateTime.utc(
    wall.date.year,
    wall.date.month,
    wall.date.day,
    wall.hour,
    wall.minute,
    wall.second,
    wall.millisecond,
  ).millisecondsSinceEpoch;
  final offsets = location.zones.map((zone) => zone.offset).toSet();
  final results = <ScheduleWallCandidate>[];
  for (final offset in offsets) {
    final instantMs = naiveMs - offset;
    if (instantMs.abs() > maxScheduleTimestampMs) continue;
    final local = tz.TZDateTime.from(
      DateTime.fromMillisecondsSinceEpoch(instantMs, isUtc: true),
      location,
    );
    if (local.year == wall.date.year &&
        local.month == wall.date.month &&
        local.day == wall.date.day &&
        local.hour == wall.hour &&
        local.minute == wall.minute &&
        local.second == wall.second &&
        local.millisecond == wall.millisecond) {
      results.add(
        ScheduleWallCandidate(
          instantMs,
          Duration(milliseconds: offset),
          local.timeZoneName,
        ),
      );
    }
  }
  results.sort((a, b) => a.instantMs.compareTo(b.instantMs));
  return List.unmodifiable(results);
}

/// A fold requires an explicit offset. The returned millisecond is absolute.
int resolveWallTime(
  ScheduleWallTime wall,
  String timeZoneId, {
  Duration? offset,
}) {
  final candidates = wallTimeCandidates(wall, timeZoneId);
  if (candidates.isEmpty) {
    throw const ScheduleTimeException(ScheduleTimeError.gap);
  }
  if (offset == null && candidates.length > 1) {
    throw const ScheduleTimeException(ScheduleTimeError.fold);
  }
  if (offset != null) {
    for (final candidate in candidates) {
      if (candidate.offset == offset) return candidate.instantMs;
    }
    throw const ScheduleTimeException(ScheduleTimeError.offset);
  }
  return candidates.single.instantMs;
}

/// Half-open intervals: touching endpoints do not overlap.
bool scheduleIntervalsOverlap(int aStart, int aEnd, int bStart, int bEnd) =>
    aStart < aEnd && bStart < bEnd && aStart < bEnd && bStart < aEnd;

class ScheduleSlice {
  const ScheduleSlice({
    required this.startAt,
    required this.endAt,
    required this.continuesBefore,
    required this.continuesAfter,
  });

  final int startAt;
  final int endAt;
  final bool continuesBefore;
  final bool continuesAfter;
}

ScheduleSlice? clipScheduleInterval(
  int startAt,
  int endAt,
  int windowStart,
  int windowEnd,
) {
  if (startAt >= endAt ||
      windowStart >= windowEnd ||
      !scheduleIntervalsOverlap(startAt, endAt, windowStart, windowEnd)) {
    return null;
  }
  return ScheduleSlice(
    startAt: startAt > windowStart ? startAt : windowStart,
    endAt: endAt < windowEnd ? endAt : windowEnd,
    continuesBefore: startAt < windowStart,
    continuesAfter: endAt > windowEnd,
  );
}

/// First instant on or after the given local civil date. Binary search also
/// handles transitions at midnight without silently resolving a user time.
int _civilBoundary(ScheduleCivilDate date, tz.Location location) {
  final approximate = DateTime.utc(
    date.year,
    date.month,
    date.day,
  ).millisecondsSinceEpoch;
  var low = approximate - 2 * _dayMs;
  var high = approximate + 2 * _dayMs;
  while (low < high) {
    final mid = low + (high - low) ~/ 2;
    final local = tz.TZDateTime.from(
      DateTime.fromMillisecondsSinceEpoch(mid, isUtc: true),
      location,
    );
    final before =
        local.year < date.year ||
        (local.year == date.year && local.month < date.month) ||
        (local.year == date.year &&
            local.month == date.month &&
            local.day < date.day);
    if (before) {
      low = mid + 1;
    } else {
      high = mid;
    }
  }
  return low;
}

ScheduleSlice dayWindow(ScheduleCivilDate date, String displayTimeZoneId) {
  final location = scheduleLocation(displayTimeZoneId);
  final start = _civilBoundary(date, location);
  final end = _civilBoundary(date.addDays(1), location);
  if (start >= end) {
    throw const ScheduleTimeException(ScheduleTimeError.invalidDate);
  }
  return ScheduleSlice(
    startAt: start,
    endAt: end,
    continuesBefore: false,
    continuesAfter: false,
  );
}

/// Monday-through-Sunday window in the supplied display zone.
ScheduleSlice weekWindow(ScheduleCivilDate date, String displayTimeZoneId) {
  final weekday = DateTime.utc(date.year, date.month, date.day).weekday;
  final monday = date.addDays(DateTime.monday - weekday);
  final nextMonday = monday.addDays(7);
  final location = scheduleLocation(displayTimeZoneId);
  return ScheduleSlice(
    startAt: _civilBoundary(monday, location),
    endAt: _civilBoundary(nextMonday, location),
    continuesBefore: false,
    continuesAfter: false,
  );
}

ScheduleSlice? clipToDay(
  int startAt,
  int endAt,
  ScheduleCivilDate date,
  String displayTimeZoneId,
) {
  final window = dayWindow(date, displayTimeZoneId);
  return clipScheduleInterval(startAt, endAt, window.startAt, window.endAt);
}

ScheduleSlice? clipToWeek(
  int startAt,
  int endAt,
  ScheduleCivilDate date,
  String displayTimeZoneId,
) {
  final window = weekWindow(date, displayTimeZoneId);
  return clipScheduleInterval(startAt, endAt, window.startAt, window.endAt);
}
