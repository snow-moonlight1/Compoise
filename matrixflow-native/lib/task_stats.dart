import 'models.dart';
import 'task_query.dart';

/// Represents aggregated task and subtask statistics for a given board or all boards.
class TaskStats {
  final int totalTasks;
  final int completedTasks;
  final int incompleteTasks;
  final int overdueTasks;
  final double completionRate;

  final int subtaskTotal;
  final int subtaskCompleted;
  final double subtaskCompletionRate;

  const TaskStats({
    required this.totalTasks,
    required this.completedTasks,
    required this.incompleteTasks,
    required this.overdueTasks,
    required this.completionRate,
    required this.subtaskTotal,
    required this.subtaskCompleted,
    required this.subtaskCompletionRate,
  });

  /// Formatted completion percentage string (e.g. "45%" or "0%").
  String get percentageText => '${(completionRate * 100).round()}%';

  /// Formatted subtask completion percentage string (e.g. "60%" or "0%").
  String get subtaskPercentageText => '${(subtaskCompletionRate * 100).round()}%';
}

/// Computes task and subtask statistics.
/// If [boardId] is provided, restricts calculations to that specific board.
/// If [boardId] is null, calculates across all tasks in all boards.
/// Note: Hiding completed tasks ([hideCompleted]) only affects screen visibility
/// and NEVER skews or distorts this statistical calculation.
TaskStats computeTaskStats({
  required List<Task> tasks,
  String? boardId,
  DateTime? now,
}) {
  final refNow = now ?? DateTime.now();
  final scopedTasks =
      boardId == null
          ? tasks
          : tasks.where((t) => t.boardId == boardId).toList();

  final totalTasks = scopedTasks.length;
  var completedTasks = 0;
  var overdueTasks = 0;
  var subtaskTotal = 0;
  var subtaskCompleted = 0;

  for (final task in scopedTasks) {
    if (task.completed) {
      completedTasks++;
    } else {
      if (task.deadline != null) {
        final daysLeft = calendarDaysLeft(task.deadline!, now: refNow);
        if (daysLeft < 0 || task.deadline! < refNow.millisecondsSinceEpoch) {
          overdueTasks++;
        }
      }
    }

    for (final subtask in task.subtasks) {
      subtaskTotal++;
      if (subtask.completed) {
        subtaskCompleted++;
      }
    }
  }

  final incompleteTasks = totalTasks - completedTasks;
  // Zero tasks returns 0.0, preventing false 100% on empty boards.
  final completionRate = totalTasks == 0 ? 0.0 : (completedTasks / totalTasks);
  final subtaskCompletionRate =
      subtaskTotal == 0 ? 0.0 : (subtaskCompleted / subtaskTotal);

  return TaskStats(
    totalTasks: totalTasks,
    completedTasks: completedTasks,
    incompleteTasks: incompleteTasks,
    overdueTasks: overdueTasks,
    completionRate: completionRate,
    subtaskTotal: subtaskTotal,
    subtaskCompleted: subtaskCompleted,
    subtaskCompletionRate: subtaskCompletionRate,
  );
}

/// Represents completion count on a specific calendar day.
class DailyCompletionBucket {
  final String dateString; // 'YYYY-MM-DD'
  final DateTime date;
  final int count; // Parent tasks completed on this date
  final int subtaskCount; // Subtasks completed on this date
  final List<Task> tasks; // Completed parent tasks on this date

  const DailyCompletionBucket({
    required this.dateString,
    required this.date,
    required this.count,
    required this.subtaskCount,
    this.tasks = const [],
  });

  DailyCompletionBucket copyWith({
    int? count,
    int? subtaskCount,
    List<Task>? tasks,
  }) {
    return DailyCompletionBucket(
      dateString: dateString,
      date: date,
      count: count ?? this.count,
      subtaskCount: subtaskCount ?? this.subtaskCount,
      tasks: tasks ?? this.tasks,
    );
  }
}

/// Aggregated historical completion trends.
/// Tracks distribution of currently completed tasks by day.
class CompletionHistoryStats {
  /// Daily buckets in chronological order (e.g. 7 days ending with today).
  final List<DailyCompletionBucket> dailyBuckets;
  final int totalCompleted;
  final int totalCompletedWithDate;
  final int unknownDateCount;
  final int todayCount;
  final int past7DaysCount;

  const CompletionHistoryStats({
    required this.dailyBuckets,
    required this.totalCompleted,
    required this.totalCompletedWithDate,
    required this.unknownDateCount,
    required this.todayCount,
    required this.past7DaysCount,
  });
}

String _formatDateString(DateTime dt) {
  final y = dt.year.toString().padLeft(4, '0');
  final m = dt.month.toString().padLeft(2, '0');
  final d = dt.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

/// Computes daily completion distribution and trends for completed tasks.
/// If [boardId] is specified, restricts to that board.
/// [days] specifies the window size ending on [now] (default 7 days).
CompletionHistoryStats computeCompletionHistoryStats({
  required List<Task> tasks,
  String? boardId,
  int days = 7,
  DateTime? now,
}) {
  final refNow = now ?? DateTime.now();
  final todayMidnight = DateTime(refNow.year, refNow.month, refNow.day);

  final scopedTasks =
      tasks
          .where((t) => t.completed && (boardId == null || t.boardId == boardId))
          .toList();

  // Create date buckets for the last [days] calendar days (chronological)
  final bucketList = <DailyCompletionBucket>[];
  final bucketMap = <String, DailyCompletionBucket>{};

  for (int i = days - 1; i >= 0; i--) {
    final dayDate = todayMidnight.subtract(Duration(days: i));
    final key = _formatDateString(dayDate);
    final bucket = DailyCompletionBucket(
      dateString: key,
      date: dayDate,
      count: 0,
      subtaskCount: 0,
      tasks: [],
    );
    bucketList.add(bucket);
    bucketMap[key] = bucket;
  }

  var unknownDateCount = 0;
  var totalCompletedWithDate = 0;

  for (final task in scopedTasks) {
    if (task.completedAt == null) {
      unknownDateCount++;
    } else {
      totalCompletedWithDate++;
      final cDate = DateTime.fromMillisecondsSinceEpoch(task.completedAt!);
      final key = _formatDateString(cDate);
      if (bucketMap.containsKey(key)) {
        final existing = bucketMap[key]!;
        bucketMap[key] = existing.copyWith(
          count: existing.count + 1,
          tasks: [...existing.tasks, task],
        );
      }
    }

    // Process subtasks completion count
    for (final sub in task.subtasks) {
      if (sub.completed && sub.completedAt != null) {
        final sDate = DateTime.fromMillisecondsSinceEpoch(sub.completedAt!);
        final key = _formatDateString(sDate);
        if (bucketMap.containsKey(key)) {
          final existing = bucketMap[key]!;
          bucketMap[key] = existing.copyWith(
            subtaskCount: existing.subtaskCount + 1,
          );
        }
      }
    }
  }

  final updatedBuckets =
      bucketList.map((b) => bucketMap[b.dateString]!).toList();

  final todayKey = _formatDateString(todayMidnight);
  final todayCount = bucketMap[todayKey]?.count ?? 0;
  final past7DaysCount = updatedBuckets.fold<int>(0, (sum, b) => sum + b.count);

  return CompletionHistoryStats(
    dailyBuckets: updatedBuckets,
    totalCompleted: scopedTasks.length,
    totalCompletedWithDate: totalCompletedWithDate,
    unknownDateCount: unknownDateCount,
    todayCount: todayCount,
    past7DaysCount: past7DaysCount,
  );
}

/// Sorts completed tasks with most recently completed first.
/// Tasks without [completedAt] are sorted by [createdAt] at the end.
List<Task> sortCompletedTasks(List<Task> tasks) {
  final copy = List<Task>.from(tasks);
  copy.sort((a, b) {
    if (a.completedAt != null && b.completedAt != null) {
      return b.completedAt!.compareTo(a.completedAt!);
    }
    if (a.completedAt != null && b.completedAt == null) {
      return -1;
    }
    if (a.completedAt == null && b.completedAt != null) {
      return 1;
    }
    return b.createdAt.compareTo(a.createdAt);
  });
  return copy;
}
