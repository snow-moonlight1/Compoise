/// Today queries, apart from deadline-driven urgency promotion.
library;

import 'calendar_dates.dart';
import 'deadline_policy.dart';
import 'models.dart';

/// A task's place on the Today list. Sections are date buckets, not quadrants:
/// one bucket mixes tasks from every quadrant and board in scope.
enum TodaySection {
  /// Linked to a schedule interval occupying today.
  scheduledToday,

  /// Due today or overdue, without a schedule occupying today.
  dueNow,
}

/// Timestamp helpers for preserving retired planning-day data in fixtures.
int? plannedDayMs(DateTime? day) => day == null ? null : civilDate(day).millisecondsSinceEpoch;
int? plannedDaysLeft(int? day, {DateTime? now}) => day == null ? null : calendarDaysLeft(day, now: now);

/// Which bucket [task] belongs to, or null when it does not belong on Today.
///
/// Schedule membership is supplied by the Store to [groupForToday].
TodaySection? todaySectionOf(Task task, {DateTime? now}) {
  if (task.completed) return null;
  final ref = now ?? DateTime.now();
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
/// oldest task. Null deadlines sort last.
int compareTodayTasks(Task a, Task b) {
  final byDeadline = _compareNullableMs(a.deadline, b.deadline);
  if (byDeadline != 0) return byDeadline;
  return a.createdAt.compareTo(b.createdAt);
}

/// Display order of the buckets.
const List<TodaySection> todaySectionOrder = [
  TodaySection.scheduledToday,
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
/// Tasks in [scheduledTaskIds] belong to today's schedule and take precedence
/// over their due-date group, without modifying any task field.
List<TodayGroup> groupForToday(
  Iterable<Task> tasks, {
  DateTime? now,
  Set<String> scheduledTaskIds = const {},
}) {
  final ref = now ?? DateTime.now();
  final bySection = <TodaySection, List<Task>>{};
  for (final task in tasks) {
    final section = !task.completed && scheduledTaskIds.contains(task.id)
        ? TodaySection.scheduledToday
        : todaySectionOf(task, now: ref);
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
