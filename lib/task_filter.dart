import 'models.dart';
import 'task_query.dart';
import 'task_tags.dart';

/// Whether a filter editor shows the full search dimensions or archive scope only.
enum TaskFilterKind { search, archive }

/// Applied or draft filter values. Query execution still goes through [queryTasks].
class TaskFilterCriteria {
  final TaskScopeFilter scope;
  final int? quadrant;
  final TaskStatusFilter status;
  final TaskDateFilter date;

  /// Parent-task tags that must all be present. Stored as the display
  /// spellings; [queryTasks] compares them case-insensitively.
  final List<String> tags;

  const TaskFilterCriteria({
    this.scope = TaskScopeFilter.currentBoard,
    this.quadrant,
    this.status = TaskStatusFilter.all,
    this.date = TaskDateFilter.all,
    this.tags = const [],
  });

  static const defaults = TaskFilterCriteria();

  bool get isDefault =>
      scope == TaskScopeFilter.currentBoard &&
      quadrant == null &&
      status == TaskStatusFilter.all &&
      date == TaskDateFilter.all &&
      tags.isEmpty;

  /// Non-default dimensions. All-boards counts as one; chips are not counted.
  int get searchDimensionCount {
    var n = 0;
    if (scope != TaskScopeFilter.currentBoard) n++;
    if (quadrant != null) n++;
    if (status != TaskStatusFilter.all) n++;
    if (date != TaskDateFilter.all) n++;
    if (tags.isNotEmpty) n++;
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
    List<String>? Function()? tags,
  }) {
    return TaskFilterCriteria(
      scope: scope ?? this.scope,
      quadrant: quadrant != null ? quadrant() : this.quadrant,
      status: status ?? this.status,
      date: date ?? this.date,
      tags: tags != null ? tags() ?? const <String>[] : this.tags,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TaskFilterCriteria &&
      other.scope == scope &&
      other.quadrant == quadrant &&
      other.status == status &&
      other.date == date &&
      sameTagList(other.tags, tags);

  @override
  int get hashCode =>
      Object.hash(scope, quadrant, status, date, Object.hashAll(tags));
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
