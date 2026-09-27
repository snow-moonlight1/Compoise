import 'calendar_dates.dart';
import 'deadline_policy.dart';
import 'models.dart';

export 'deadline_policy.dart' show calendarDaysLeft, isDeadlineUrgent;

/// Scope of boards to include in task search.
enum TaskScopeFilter {
  currentBoard,
  allBoards,
}

/// Completion status filter for task search.
enum TaskStatusFilter {
  all,
  incomplete,
  completed,
}

/// Deadline calendar filter for task search.
enum TaskDateFilter {
  all,
  today,
  thisWeek,
  thisMonth,
  overdue,
  noDate,
}

/// Represents a single search result match, either a parent task or a child subtask.
class TaskSearchResult {
  final Task task;
  final Board board;
  final SubTask? matchedSubtask;

  const TaskSearchResult({
    required this.task,
    required this.board,
    this.matchedSubtask,
  });

  bool get isSubtaskMatch => matchedSubtask != null;

  /// Unique identifier for this search hit.
  String get resultKey =>
      isSubtaskMatch ? '${task.id}:${matchedSubtask!.id}' : task.id;

  /// Display title for the result item.
  String get displayTitle =>
      isSubtaskMatch ? matchedSubtask!.title : task.title;

  /// Breadcrumb path displaying board and parent task when applicable.
  String get pathDisplay =>
      isSubtaskMatch ? '${board.name} / ${task.title}' : board.name;

  /// Completion status of this hit.
  bool get isCompleted =>
      isSubtaskMatch ? matchedSubtask!.completed : task.completed;

  /// Deadline associated with this hit.
  int? get deadline =>
      isSubtaskMatch
          ? (matchedSubtask!.deadline ?? task.deadline)
          : task.deadline;
}

/// Checks if [deadline] satisfies [filter] relative to [now].
bool matchesDateFilter(
  int? deadline,
  bool completed,
  TaskDateFilter filter, {
  DateTime? now,
}) {
  if (filter == TaskDateFilter.all) return true;
  if (filter == TaskDateFilter.noDate) return deadline == null;
  if (deadline == null) return false;

  final ref = now ?? DateTime.now();
  switch (filter) {
    case TaskDateFilter.all:
    case TaskDateFilter.noDate:
      return true;
    case TaskDateFilter.today:
      return calendarDaysLeft(deadline, now: ref) == 0;
    case TaskDateFilter.thisWeek:
      return deadlineInCivilWeek(deadline, ref);
    case TaskDateFilter.thisMonth:
      final startOfMonth = DateTime(ref.year, ref.month, 1);
      final startOfNextMonth = DateTime(ref.year, ref.month + 1, 1);
      final d = DateTime.fromMillisecondsSinceEpoch(deadline);
      return !d.isBefore(startOfMonth) && d.isBefore(startOfNextMonth);
    case TaskDateFilter.overdue:
      return !completed &&
          (calendarDaysLeft(deadline, now: ref) < 0 ||
              deadline < ref.millisecondsSinceEpoch);
  }
}

/// Performs a local in-memory search and multi-dimensional filter across tasks.
List<TaskSearchResult> queryTasks({
  required List<Task> tasks,
  required List<Board> boards,
  required String activeBoardId,
  String query = '',
  TaskScopeFilter scope = TaskScopeFilter.currentBoard,
  int? quadrant,
  TaskStatusFilter status = TaskStatusFilter.all,
  TaskDateFilter dateFilter = TaskDateFilter.all,
  DateTime? now,
}) {
  final boardMap = {for (final b in boards) b.id: b};
  final trimmed = query.trim().toLowerCase();
  final results = <TaskSearchResult>[];
  final seenKeys = <String>{};

  for (final task in tasks) {
    if (scope == TaskScopeFilter.currentBoard && task.boardId != activeBoardId) {
      continue;
    }
    final board = boardMap[task.boardId];
    if (board == null) continue;

    // Quadrant filter
    if (quadrant != null && task.quadrant != quadrant) {
      continue;
    }

    // 1. Check parent task
    final parentKeywordMatches =
        trimmed.isEmpty ||
        task.title.toLowerCase().contains(trimmed) ||
        (task.notesMarkdown != null &&
            task.notesMarkdown!.toLowerCase().contains(trimmed));
    final parentStatusMatches = switch (status) {
      TaskStatusFilter.all => true,
      TaskStatusFilter.completed => task.completed,
      TaskStatusFilter.incomplete => !task.completed,
    };
    final parentDateMatches = matchesDateFilter(
      task.deadline,
      task.completed,
      dateFilter,
      now: now,
    );

    if (parentKeywordMatches && parentStatusMatches && parentDateMatches) {
      final res = TaskSearchResult(task: task, board: board);
      if (seenKeys.add(res.resultKey)) {
        results.add(res);
      }
    }

    // 2. Check child subtasks (only when keyword query is non-empty)
    if (trimmed.isNotEmpty) {
      for (final subtask in task.subtasks) {
        final subtaskKeywordMatches =
            subtask.title.toLowerCase().contains(trimmed) ||
            (subtask.notesMarkdown != null &&
                subtask.notesMarkdown!.toLowerCase().contains(trimmed));
        if (!subtaskKeywordMatches) {
          continue;
        }
        final subStatusMatches = switch (status) {
          TaskStatusFilter.all => true,
          TaskStatusFilter.completed => subtask.completed,
          TaskStatusFilter.incomplete => !subtask.completed,
        };
        final subDateMatches = matchesDateFilter(
          subtask.deadline ?? task.deadline,
          subtask.completed,
          dateFilter,
          now: now,
        );

        if (subStatusMatches && subDateMatches) {
          final res = TaskSearchResult(
            task: task,
            board: board,
            matchedSubtask: subtask,
          );
          if (seenKeys.add(res.resultKey)) {
            results.add(res);
          }
        }
      }
    }
  }

  return results;
}
