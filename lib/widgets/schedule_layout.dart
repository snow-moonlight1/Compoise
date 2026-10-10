/// Read-only schedule projection and geometry. No commands or persistence.
library;

import 'dart:math' as math;

import 'package:timezone/timezone.dart' as tz;

import '../models.dart';
import '../schedule_item.dart';
import '../schedule_time.dart';

String scheduleDateLabel(ScheduleCivilDate date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

String scheduleOffsetLabel(Duration offset) {
  final minutes = offset.inMinutes.abs();
  return 'UTC${offset.isNegative ? '-' : '+'}'
      '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
      '${(minutes % 60).toString().padLeft(2, '0')}';
}

DateTime scheduleLocalTime(int instant, String displayTimeZoneId) =>
    tz.TZDateTime.fromMillisecondsSinceEpoch(
      scheduleLocation(displayTimeZoneId),
      instant,
    );

String scheduleClockLabel(int instant, String zone) {
  final local = scheduleLocalTime(instant, zone);
  final seconds = local.second == 0 && local.millisecond == 0
      ? ''
      : ':${local.second.toString().padLeft(2, '0')}'
            '${local.millisecond == 0 ? '' : '.${local.millisecond.toString().padLeft(3, '0')}'}';
  return '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}$seconds '
      '${scheduleOffsetLabel(local.timeZoneOffset)}';
}

/// Short clock painted on the planner axis and blocks. The offset stays in
/// [scheduleClockLabel] and in semantics; a 23- or 25-hour day still uses the
/// real instants, this only changes the painted digits.
String scheduleAxisLabel(int instant, String zone) {
  final local = scheduleLocalTime(instant, zone);
  return '${local.hour}:${local.minute.toString().padLeft(2, '0')}';
}

String scheduleInstantLabel(int instant, String zone) {
  final local = scheduleLocalTime(instant, zone);
  return '${scheduleDateLabel(ScheduleCivilDate(local.year, local.month, local.day))} '
      '${scheduleClockLabel(instant, zone)}';
}

/// Captures current association labels, including completed parent tasks.
/// Task-linked events retain their own title and derive board/quadrant from
/// the current parent, just like time blocks.
class ScheduleEntry {
  const ScheduleEntry({
    required this.item,
    required this.title,
    required this.boardId,
    required this.boardName,
    this.taskTitle,
    this.quadrant,
    this.completed = false,
  });

  final ScheduleItem item;
  final String title;
  final String boardId;
  final String? boardName;
  final String? taskTitle;
  final int? quadrant;
  final bool completed;
}

List<ScheduleEntry> scheduleEntries({
  required Iterable<ScheduleItem> items,
  required Iterable<Task> tasks,
  required Iterable<Board> boards,
  String? boardId,
}) {
  final taskById = {for (final task in tasks) task.id: task};
  final boardById = {for (final board in boards) board.id: board};
  return List.unmodifiable([
    for (final item in items)
      if (boardId == null ||
          (item.taskId == null
                  ? item.boardId
                  : taskById[item.taskId]?.boardId) ==
              boardId)
        ScheduleEntry(
          item: item,
          title: item.title ?? taskById[item.taskId]?.title ?? item.taskId!,
          boardId: item.taskId == null
              ? item.boardId!
              : taskById[item.taskId]?.boardId ?? '',
          boardName:
              boardById[item.taskId == null
                      ? item.boardId
                      : taskById[item.taskId]?.boardId]
                  ?.name,
          taskTitle: taskById[item.taskId]?.title,
          quadrant: taskById[item.taskId]?.quadrant,
          completed: taskById[item.taskId]?.completed ?? false,
        ),
  ]);
}

class ScheduleTick {
  const ScheduleTick(this.instant, this.label, this.top);
  final int instant;
  final String label;
  final double top;
}

class SchedulePlacement {
  const SchedulePlacement({
    required this.entry,
    required this.slice,
    required this.lane,
    required this.top,
    required this.height,
  });
  final ScheduleEntry entry;
  final ScheduleSlice slice;
  final int lane;
  final double top;
  final double height;
}

/// The axis measures elapsed time, so folds get two distinct positions and
/// gaps get none. Minimum hit heights also participate in lane allocation:
/// very short adjacent records cannot paint over each other's touch targets.
class ScheduleDayLayout {
  ScheduleDayLayout({
    required this.date,
    required this.timeZoneId,
    required Iterable<ScheduleEntry> entries,
    this.pixelsPerHour = 80,
    this.minimumItemHeight = 56,
  }) {
    window = dayWindow(date, timeZoneId);
    axisHeight =
        (window.endAt - window.startAt) /
        Duration.millisecondsPerHour *
        pixelsPerHour;
    double position(int instant) =>
        (instant - window.startAt) /
        Duration.millisecondsPerHour *
        pixelsPerHour;

    // Enumerate wall-hour candidates using A1's bundled IANA rules. This also
    // handles half-hour DST changes rather than fabricating hourly instants.
    final instants = <int>{window.startAt, window.endAt};
    for (var hour = 0; hour < 24; hour++) {
      for (final candidate in wallTimeCandidates(
        ScheduleWallTime(date, hour: hour, minute: 0),
        timeZoneId,
      )) {
        if (candidate.instantMs >= window.startAt &&
            candidate.instantMs < window.endAt) {
          instants.add(candidate.instantMs);
        }
      }
    }
    ticks = List.unmodifiable([
      for (final instant in instants.toList()..sort())
        ScheduleTick(
          instant,
          // Include the next date at the endpoint; never label it as 24:00
          // with the previous day's offset.
          instant == window.endAt
              ? scheduleInstantLabel(instant, timeZoneId)
              : scheduleClockLabel(instant, timeZoneId),
          position(instant),
        ),
    ]);

    final clipped = <(ScheduleEntry, ScheduleSlice)>[];
    for (final entry in entries) {
      final slice = clipScheduleInterval(
        entry.item.startAt,
        entry.item.endAt,
        window.startAt,
        window.endAt,
      );
      if (slice != null) clipped.add((entry, slice));
    }
    clipped.sort((a, b) {
      final start = a.$2.startAt.compareTo(b.$2.startAt);
      if (start != 0) return start;
      final end = a.$2.endAt.compareTo(b.$2.endAt);
      return end != 0 ? end : a.$1.item.id.compareTo(b.$1.item.id);
    });

    final laneEnds = <double>[];
    final result = <SchedulePlacement>[];
    for (final (entry, slice) in clipped) {
      final top = position(slice.startAt);
      final height = math.max(minimumItemHeight, position(slice.endAt) - top);
      var lane = laneEnds.indexWhere((end) => end <= top);
      if (lane == -1) {
        lane = laneEnds.length;
        laneEnds.add(top + height);
      } else {
        laneEnds[lane] = top + height;
      }
      result.add(
        SchedulePlacement(
          entry: entry,
          slice: slice,
          lane: lane,
          top: top,
          height: height,
        ),
      );
    }
    placements = List.unmodifiable(result);
    laneCount = math.max(1, laneEnds.length);
    // Short records at the final millisecond remain entirely reachable.
    height = math.max(
      axisHeight + minimumItemHeight,
      laneEnds.fold<double>(0, math.max),
    );
  }

  final ScheduleCivilDate date;
  final String timeZoneId;
  final double pixelsPerHour;
  final double minimumItemHeight;
  late final ScheduleSlice window;
  late final double axisHeight;
  late final double height;
  late final List<ScheduleTick> ticks;
  late final List<SchedulePlacement> placements;
  late final int laneCount;
}
