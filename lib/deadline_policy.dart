/// Deadline calculation, urgency policy, and Eisenhower quadrant promotion rules.
library;

import 'models.dart';

/// Checks if quadrant is in the urgent dimension (Q1 or Q3).
bool isUrgentQuadrant(int quadrant) =>
    quadrant == qDo || quadrant == qDelegate;

/// Checks if quadrant is in the important dimension (Q1 or Q2).
bool isImportantQuadrant(int quadrant) =>
    quadrant == qDo || quadrant == qPlan;

/// Returns the urgent counterpart for a given quadrant, preserving importance.
///
/// - Q2 (Important, Not Urgent) -> Q1 (Important, Urgent)
/// - Q4 (Not Important, Not Urgent) -> Q3 (Not Important, Urgent)
/// - Q1 and Q3 remain unchanged.
int promoteToUrgent(int quadrant) {
  if (quadrant == qPlan) return qDo;
  if (quadrant == qEliminate) return qDelegate;
  return quadrant;
}

/// Calculates local calendar days difference between [deadlineMs] and [now].
///
/// Uses midnight-aligned UTC dates constructed from local year/month/day
/// to guarantee that daylight saving time (DST) clock changes (e.g. 23h or 25h days)
/// and time-of-day offsets do not cause calendar-day discrepancies.
///
/// - 0: Deadline is today.
/// - 1: Deadline is tomorrow.
/// - Negative: Deadline is overdue by N days.
int calendarDaysLeft(int deadlineMs, {DateTime? now}) {
  final date = DateTime.fromMillisecondsSinceEpoch(deadlineMs);
  final ref = now ?? DateTime.now();
  final utcDate = DateTime.utc(date.year, date.month, date.day);
  final utcRef = DateTime.utc(ref.year, ref.month, ref.day);
  return utcDate.difference(utcRef).inDays;
}

/// Determines whether a task's deadline has reached or passed the urgency threshold.
///
/// - Returns false if [deadlineMs] is null.
/// - Returns true if the task is overdue (days < 0) or due within [thresholdDays]
///   in advance (inclusive of today: 0 <= days <= thresholdDays).
bool isDeadlineUrgent(int? deadlineMs, int thresholdDays, {DateTime? now}) {
  if (deadlineMs == null) return false;
  final days = calendarDaysLeft(deadlineMs, now: now);
  return days <= thresholdDays;
}
