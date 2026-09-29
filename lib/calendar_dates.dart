/// Civil calendar dates and the date/reminder picker windows.
///
/// "Tomorrow" and "this week" follow the local year/month/day. They do not
/// add a fixed 24-hour [Duration], so a 23-hour or 25-hour civil day still
/// lands on the intended date. A reminder timestamp stays an absolute instant.
library;

/// Inclusive civil years a reminder picker can offer, starting today.
const int reminderPickerYearSpan = 5;

/// Dates passed to [showDatePicker] after clamping the preferred day.
class DatePickerWindow {
  const DatePickerWindow({
    required this.first,
    required this.last,
    required this.initial,
  });

  final DateTime first;
  final DateTime last;
  final DateTime initial;
}

/// Local calendar date of [instant], at local midnight.
DateTime civilDate(DateTime instant) =>
    DateTime(instant.year, instant.month, instant.day);

/// Whether [a] and [b] fall on the same local year/month/day. The two instants
/// do not have to agree: a plan stored at midnight and a deadline stored at the
/// end of the day still describe the same civil day.
bool isSameCivilDay(DateTime? a, DateTime? b) {
  if (a == null || b == null) return false;
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

/// Moves [days] civil dates. [days] may be negative.
DateTime addCivilDays(DateTime instant, int days) {
  final day = civilDate(instant);
  return DateTime(day.year, day.month, day.day + days);
}

/// Moves [years] civil years. A leap day lands on the last valid day of the
/// target month when the target year has no February 29.
DateTime addCivilYears(DateTime instant, int years) {
  final day = civilDate(instant);
  final candidate = DateTime(day.year + years, day.month, day.day);
  if (candidate.month != day.month) {
    return DateTime(day.year + years, day.month + 1, 0);
  }
  return candidate;
}

/// Clamps [value] to the inclusive civil range `[first, last]`.
DateTime clampCivilDate(DateTime value, DateTime first, DateTime last) {
  final day = civilDate(value);
  final start = civilDate(first);
  final end = civilDate(last);
  if (day.isBefore(start)) return start;
  if (day.isAfter(end)) return end;
  return day;
}

/// Deadline picker range. A stored deadline outside this range is only
/// clamped for the dialog's initial day; callers must not write that day
/// back unless the user confirms a selection.
DatePickerWindow deadlinePickerWindow({
  required DateTime now,
  DateTime? selected,
}) {
  final first = DateTime(1900, 1, 1);
  final last = DateTime(2200, 12, 31);
  return DatePickerWindow(
    first: first,
    last: last,
    initial: clampCivilDate(selected ?? now, first, last),
  );
}

/// Reminder picker range: today through the same civil day five years later.
///
/// The preferred day is the existing reminder, then the deadline, then [now].
/// The returned [DatePickerWindow.initial] is only a safe dialog value.
DatePickerWindow reminderPickerWindow({
  required DateTime now,
  int? reminderAt,
  DateTime? deadline,
}) {
  final first = civilDate(now);
  final last = addCivilYears(first, reminderPickerYearSpan);
  final DateTime preferred;
  if (reminderAt != null) {
    preferred = DateTime.fromMillisecondsSinceEpoch(reminderAt);
  } else if (deadline != null) {
    preferred = deadline;
  } else {
    preferred = now;
  }
  return DatePickerWindow(
    first: first,
    last: last,
    initial: clampCivilDate(preferred, first, last),
  );
}

/// Whether [deadlineMs] falls on Monday through Sunday of the local week
/// that contains [now]. Comparison uses calendar dates, not elapsed hours.
bool deadlineInCivilWeek(int deadlineMs, DateTime now) {
  final when = DateTime.fromMillisecondsSinceEpoch(deadlineMs);
  final days = _civilDaysBetween(now, when);
  final fromMonday = now.weekday - DateTime.monday;
  final untilSunday = DateTime.sunday - now.weekday;
  return days >= -fromMonday && days <= untilSunday;
}

int _civilDaysBetween(DateTime from, DateTime to) {
  final start = DateTime.utc(from.year, from.month, from.day);
  final end = DateTime.utc(to.year, to.month, to.day);
  return end.difference(start).inDays;
}
