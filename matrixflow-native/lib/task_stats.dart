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
