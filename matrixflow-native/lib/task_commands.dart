import 'models.dart';

/// The type of action that can be undone.
enum TaskUndoType {
  complete,
  restore,
  delete,
}

/// A lightweight snapshot capturing the necessary data to undo a task mutation.
/// Only retains the affected task and its position, strictly avoiding full-board copies.
class TaskUndoSnapshot {
  final TaskUndoType actionType;
  final String taskId;
  final String boardId;
  final int boardEpoch;
  final Task task;
  final int originalIndex;
  final DateTime timestamp;
  final int commandSeq;

  TaskUndoSnapshot({
    required this.actionType,
    required this.taskId,
    required this.boardId,
    required this.boardEpoch,
    required this.task,
    required this.originalIndex,
    this.commandSeq = 0,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Captures a deep copy of [task] for an undoable action.
  factory TaskUndoSnapshot.capture({
    required TaskUndoType actionType,
    required Task task,
    required int boardEpoch,
    required int originalIndex,
    int commandSeq = 0,
  }) {
    return TaskUndoSnapshot(
      actionType: actionType,
      taskId: task.id,
      boardId: task.boardId,
      boardEpoch: boardEpoch,
      task: Task.fromJson(task.toJson()),
      originalIndex: originalIndex,
      commandSeq: commandSeq,
    );
  }
}
