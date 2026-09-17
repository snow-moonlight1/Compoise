import 'models.dart';
import 'task_query.dart';

/// Whether a filter editor shows the full search dimensions or archive scope only.
enum TaskFilterKind { search, archive }

/// Applied or draft filter values. Query execution still goes through [queryTasks].
class TaskFilterCriteria {
  final TaskScopeFilter scope;
  final int? quadrant;
  final TaskStatusFilter status;
  final TaskDateFilter date;

  const TaskFilterCriteria({
    this.scope = TaskScopeFilter.currentBoard,
    this.quadrant,
    this.status = TaskStatusFilter.all,
    this.date = TaskDateFilter.all,
  });

  static const defaults = TaskFilterCriteria();

  bool get isDefault =>
      scope == TaskScopeFilter.currentBoard &&
      quadrant == null &&
      status == TaskStatusFilter.all &&
      date == TaskDateFilter.all;

  /// Non-default dimensions. All-boards counts as one; chips are not counted.
  int get searchDimensionCount {
    var n = 0;
    if (scope != TaskScopeFilter.currentBoard) n++;
    if (quadrant != null) n++;
    if (status != TaskStatusFilter.all) n++;
    if (date != TaskDateFilter.all) n++;
    return n;
  }

  int get archiveDimensionCount =>
      scope == TaskScopeFilter.currentBoard ? 0 : 1;

  int dimensionCount(TaskFilterKind kind) =>
      kind == TaskFilterKind.archive
          ? archiveDimensionCount
          : searchDimensionCount;

  TaskFilterCriteria copyWith({
    TaskScopeFilter? scope,
    int? Function()? quadrant,
    TaskStatusFilter? status,
    TaskDateFilter? date,
  }) {
    return TaskFilterCriteria(
      scope: scope ?? this.scope,
      quadrant: quadrant != null ? quadrant() : this.quadrant,
      status: status ?? this.status,
      date: date ?? this.date,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TaskFilterCriteria &&
      other.scope == scope &&
      other.quadrant == quadrant &&
      other.status == status &&
      other.date == date;

  @override
  int get hashCode => Object.hash(scope, quadrant, status, date);
}

String resolveBoardName({
  required List<Board> boards,
  required String boardId,
  required String unknownLabel,
}) {
  for (final board in boards) {
    if (board.id == boardId) {
      final name = board.name.trim();
      return name.isEmpty ? unknownLabel : name;
    }
  }
  return unknownLabel;
}
