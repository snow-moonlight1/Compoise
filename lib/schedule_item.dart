/// Standalone WP15 records. Store and backup integration belong to later packs.
library;

import 'schedule_time.dart';

enum ScheduleItemKind { timeBlock, event }

class ScheduleItem {
  ScheduleItem._({
    required this.id,
    required this.kind,
    required this.startAt,
    required this.endAt,
    required this.timeZoneId,
    this.taskId,
    this.boardId,
    this.title,
  }) {
    if (id.trim().isEmpty) throw const FormatException('Missing schedule id');
    if (startAt.abs() > maxScheduleTimestampMs ||
        endAt.abs() > maxScheduleTimestampMs ||
        startAt >= endAt) {
      throw const FormatException('Invalid schedule interval');
    }
    scheduleLocation(timeZoneId);
    if (kind == ScheduleItemKind.timeBlock) {
      if (taskId == null ||
          taskId!.trim().isEmpty ||
          boardId != null ||
          title != null) {
        throw const FormatException('Invalid time block association');
      }
    } else {
      if (title == null ||
          title!.trim().isEmpty ||
          (taskId == null) == (boardId == null) ||
          (taskId != null && taskId!.trim().isEmpty) ||
          (boardId != null && boardId!.trim().isEmpty)) {
        throw const FormatException('Invalid event association or title');
      }
    }
  }

  /// A reserved interval for one parent task; taskId cannot be a subtask id.
  factory ScheduleItem.timeBlock({
    required String id,
    required String taskId,
    required int startAt,
    required int endAt,
    required String timeZoneId,
  }) => ScheduleItem._(
    id: id,
    kind: ScheduleItemKind.timeBlock,
    taskId: taskId,
    startAt: startAt,
    endAt: endAt,
    timeZoneId: timeZoneId,
  );

  /// An event has its own title and either a parent task or a board, never both.
  factory ScheduleItem.event({
    required String id,
    required String title,
    String? taskId,
    String? boardId,
    required int startAt,
    required int endAt,
    required String timeZoneId,
  }) => ScheduleItem._(
    id: id,
    kind: ScheduleItemKind.event,
    title: title,
    taskId: taskId,
    boardId: boardId,
    startAt: startAt,
    endAt: endAt,
    timeZoneId: timeZoneId,
  );

  /// Strictly reads known fields. A2 preflight owns unknown-field warnings.
  factory ScheduleItem.fromJson(Map<String, dynamic> json) {
    String requiredString(String field) {
      final value = json[field];
      if (value is! String) throw FormatException('Invalid $field');
      return value;
    }

    String? optionalString(String field) {
      final value = json[field];
      if (value == null) return null;
      if (value is! String) throw FormatException('Invalid $field');
      return value;
    }

    int requiredTime(String field) {
      final value = json[field];
      if (value is! int) throw FormatException('Invalid $field');
      return value;
    }

    final id = requiredString('id');
    final kind = requiredString('kind');
    final startAt = requiredTime('startAt');
    final endAt = requiredTime('endAt');
    final timeZoneId = requiredString('timeZoneId');
    if (kind == ScheduleItemKind.timeBlock.name) {
      if (json.containsKey('boardId') || json.containsKey('title')) {
        throw const FormatException('Invalid time block fields');
      }
      return ScheduleItem.timeBlock(
        id: id,
        taskId: requiredString('taskId'),
        startAt: startAt,
        endAt: endAt,
        timeZoneId: timeZoneId,
      );
    }
    if (kind == ScheduleItemKind.event.name) {
      if (json.containsKey('taskId') == json.containsKey('boardId')) {
        throw const FormatException('Event requires one association field');
      }
      return ScheduleItem.event(
        id: id,
        title: requiredString('title'),
        taskId: optionalString('taskId'),
        boardId: optionalString('boardId'),
        startAt: startAt,
        endAt: endAt,
        timeZoneId: timeZoneId,
      );
    }
    throw const FormatException('Invalid schedule kind');
  }

  final String id;
  final ScheduleItemKind kind;
  final String? taskId;
  final String? boardId;
  final String? title;
  final int startAt;
  final int endAt;
  final String timeZoneId;

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.name,
    if (title != null) 'title': title,
    if (taskId != null) 'taskId': taskId,
    if (boardId != null) 'boardId': boardId,
    'startAt': startAt,
    'endAt': endAt,
    'timeZoneId': timeZoneId,
  };
}

/// Referential integrity is a collection concern. A2 supplies the parent
/// task and board IDs from the proposed transaction, not the current Store.
void validateScheduleCollection(
  Iterable<ScheduleItem> items, {
  required Set<String> parentTaskIds,
  required Set<String> boardIds,
}) {
  final ids = <String>{};
  for (final item in items) {
    if (!ids.add(item.id)) throw const FormatException('Duplicate schedule id');
    if (item.taskId != null && !parentTaskIds.contains(item.taskId)) {
      throw const FormatException('Missing parent task');
    }
    if (item.boardId != null && !boardIds.contains(item.boardId)) {
      throw const FormatException('Missing event board');
    }
  }
}

/// Conflicts are advisory. Preserve input order for a stable UI list.
List<ScheduleItem> overlappingScheduleItems(
  Iterable<ScheduleItem> items,
  ScheduleItem candidate,
) => [
  for (final item in items)
    if (item.id != candidate.id &&
        scheduleIntervalsOverlap(
          item.startAt,
          item.endAt,
          candidate.startAt,
          candidate.endAt,
        ))
      item,
];
