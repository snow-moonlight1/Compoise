/// Planning-day semantics for the Today list. Kept apart from the urgency rules
/// in `deadline_policy.dart` on purpose: a plan says *when the user intends to
/// work*, a deadline says *how late it may slip*.
library;

import 'calendar_dates.dart';
import 'deadline_policy.dart';
import 'models.dart';

/// A task's place on the Today list. Sections are date buckets, not quadrants:
/// one bucket mixes tasks from every quadrant and board in scope.
enum TodaySection {
  /// Planned for an earlier day and still open, so it carried over.
  carriedOver,

  /// Planned for today.
  plannedToday,

  /// Nothing is planned for today, but the deadline is today or already past.
  dueNow,
}

/// Stored form of a planned day: local civil midnight. A plan is a whole day, so
/// midnight keeps it from reading as "already past" while that same day runs.
int? plannedDayMs(DateTime? day) =>
    day == null ? null : civilDate(day).millisecondsSinceEpoch;

/// Whole civil days from [now] to the stored plan: 0 today, 1 tomorrow, negative
/// for a carried-over day. Null when nothing is planned.
int? plannedDaysLeft(int? plannedDateMs, {DateTime? now}) => plannedDateMs == null
    ? null
    : calendarDaysLeft(plannedDateMs, now: now);

/// Which bucket [task] belongs to, or null when it does not belong on Today.
///
/// A plan wins over a deadline so a task is listed once; the row still shows the
/// deadline. A task planned for a later day still surfaces when its deadline
/// arrives, because the two fields answer different questions.
TodaySection? todaySectionOf(Task task, {DateTime? now}) {
  if (task.completed) return null;
  final ref = now ?? DateTime.now();
  final plan = plannedDaysLeft(task.plannedDate, now: ref);
  if (plan != null) {
    if (plan == 0) return TodaySection.plannedToday;
    if (plan < 0) return TodaySection.carriedOver;
  }
  final due = task.deadline == null
      ? null
      : calendarDaysLeft(task.deadline!, now: ref);
  if (due != null && due <= 0) return TodaySection.dueNow;
  return null;
}

/// Whether [task] was completed on the civil day of [now].
bool completedOnDay(Task task, {DateTime? now}) {
  if (!task.completed || task.completedAt == null) return false;
  final ref = now ?? DateTime.now();
  return isSameCivilDay(
    DateTime.fromMillisecondsSinceEpoch(task.completedAt!),
    ref,
  );
}

/// Stable order inside one bucket: the nearest commitment first, then the
/// earliest plan, then the oldest task. Null dates sort last.
int compareTodayTasks(Task a, Task b) {
  final byDeadline = _compareNullableMs(a.deadline, b.deadline);
  if (byDeadline != 0) return byDeadline;
  final byPlan = _compareNullableMs(a.plannedDate, b.plannedDate);
  if (byPlan != 0) return byPlan;
  return a.createdAt.compareTo(b.createdAt);
}

/// Display order of the buckets.
const List<TodaySection> todaySectionOrder = [
  TodaySection.carriedOver,
  TodaySection.plannedToday,
  TodaySection.dueNow,
];

/// One bucket of the Today list with its tasks in display order.
class TodayGroup {
  const TodayGroup({required this.section, required this.tasks});

  final TodaySection section;
  final List<Task> tasks;
}

/// Buckets [tasks] for the Today list in [todaySectionOrder], dropping the empty
/// ones. Quadrants and boards are mixed inside a bucket: the caller shows each
/// task's own quadrant and board rather than grouping by either.
List<TodayGroup> groupForToday(
  Iterable<Task> tasks, {
  DateTime? now,
}) {
  final ref = now ?? DateTime.now();
  final bySection = <TodaySection, List<Task>>{};
  for (final task in tasks) {
    final section = todaySectionOf(task, now: ref);
    if (section == null) continue;
    bySection.putIfAbsent(section, () => <Task>[]).add(task);
  }
  final groups = <TodayGroup>[];
  for (final section in todaySectionOrder) {
    final listed = bySection[section];
    if (listed == null || listed.isEmpty) continue;
    listed.sort(compareTodayTasks);
    groups.add(TodayGroup(section: section, tasks: listed));
  }
  return groups;
}

int _compareNullableMs(int? left, int? right) {
  if (left == right) return 0;
  if (left == null) return 1;
  if (right == null) return -1;
  return left.compareTo(right);
}
