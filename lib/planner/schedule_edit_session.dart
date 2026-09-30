import 'dart:convert';

import '../models.dart';
import '../schedule_item.dart';
import '../schedule_time.dart';
import '../storage.dart';
import '../widgets/schedule_layout.dart';

enum ScheduleEditMode { edit, move, resizeStart, resizeEnd }

enum ScheduleSubmitResult {
  saved,
  unsaved,
  stale,
  recovery,
  invalid,
  reviewChanged,
  busy,
}

/// Transient form input only. The library remains owned by Store.
class ScheduleEndpointInput {
  ScheduleEndpointInput({required this.date, this.time = '', this.offset});
  factory ScheduleEndpointInput.fromInstant(int instant, String zone) {
    final local = scheduleLocalTime(instant, zone);
    return ScheduleEndpointInput(
      date: scheduleDateLabel(
        ScheduleCivilDate(local.year, local.month, local.day),
      ),
      time:
          '${local.hour.toString().padLeft(2, '0')}:'
          '${local.minute.toString().padLeft(2, '0')}:'
          '${local.second.toString().padLeft(2, '0')}.'
          '${local.millisecond.toString().padLeft(3, '0')}',
      offset: local.timeZoneOffset,
    );
  }
  String date;
  String time;
  Duration? offset;

  ScheduleWallTime get wall {
    final d = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(date);
    final t = RegExp(
      r'^(\d{2}):(\d{2})(?::(\d{2})(?:\.(\d{1,3}))?)?$',
    ).firstMatch(time);
    if (d == null || t == null) {
      throw const ScheduleTimeException(ScheduleTimeError.invalidClock);
    }
    return ScheduleWallTime(
      ScheduleCivilDate(int.parse(d[1]!), int.parse(d[2]!), int.parse(d[3]!)),
      hour: int.parse(t[1]!),
      minute: int.parse(t[2]!),
      second: int.parse(t[3] ?? '0'),
      millisecond: int.parse((t[4] ?? '0').padRight(3, '0')),
    );
  }

  List<ScheduleWallCandidate> candidates(String zone) =>
      wallTimeCandidates(wall, zone);
  int resolve(String zone) => resolveWallTime(wall, zone, offset: offset);
}

class ScheduleReview {
  ScheduleReview(this.item, this.overlaps)
    : fingerprint = _fingerprint(overlaps);
  final ScheduleItem item;
  final List<ScheduleItem> overlaps;
  final String fingerprint;
  static String _fingerprint(Iterable<ScheduleItem> items) => jsonEncode([
    for (final item in items.toList()..sort((a, b) => a.id.compareTo(b.id)))
      item.toJson(),
  ]);
}

class ScheduleEditSession {
  ScheduleEditSession.create(
    this.store,
    this.kind,
    String zone,
    ScheduleCivilDate date, {
    ScheduleWallTime? suggestedStart,
  }) : original = null,
       expectedRevision = null,
       mode = ScheduleEditMode.edit,
       id = newId(),
       timeZoneId = zone,
       start = ScheduleEndpointInput(date: scheduleDateLabel(date)),
       end = ScheduleEndpointInput(date: scheduleDateLabel(date)) {
    if (suggestedStart != null) {
      start.date = scheduleDateLabel(suggestedStart.date);
      start.time =
          '${suggestedStart.hour.toString().padLeft(2, '0')}:'
          '${suggestedStart.minute.toString().padLeft(2, '0')}';
      // A grid suggestion does not choose an offset in a fold.
    }
  }

  ScheduleEditSession.edit(
    this.store,
    ScheduleItem item, {
    this.mode = ScheduleEditMode.edit,
    String? displayZone,
    ScheduleWallTime? target,
    int? revision,
  }) : original = item,
       expectedRevision = revision ?? store.scheduleRevision(item.id),
       id = item.id,
       kind = item.kind,
       timeZoneId = mode == ScheduleEditMode.edit
           ? item.timeZoneId
           : displayZone!,
       title = item.title ?? '',
       taskId = item.taskId,
       boardId = item.boardId,
       start = ScheduleEndpointInput.fromInstant(
         item.startAt,
         mode == ScheduleEditMode.edit ? item.timeZoneId : displayZone!,
       ),
       end = ScheduleEndpointInput.fromInstant(
         item.endAt,
         mode == ScheduleEditMode.edit ? item.timeZoneId : displayZone!,
       ) {
    if (target != null) {
      final input = mode == ScheduleEditMode.resizeEnd ? end : start;
      input.date = scheduleDateLabel(target.date);
      input.time =
          '${target.hour.toString().padLeft(2, '0')}:'
          '${target.minute.toString().padLeft(2, '0')}';
      input.offset = null;
    }
  }

  final Store store;
  final ScheduleItem? original;
  final int? expectedRevision;
  final String id;
  final ScheduleItemKind kind;
  final ScheduleEditMode mode;
  String timeZoneId;
  String title = '';
  String? taskId;
  String? boardId;
  final ScheduleEndpointInput start;
  final ScheduleEndpointInput end;
  bool busy = false;
  bool accepted = false;
  bool _deleted = false;
  int? _acceptedRevision;
  ScheduleItem? _acceptedItem;

  bool get stale =>
      original != null &&
      (!store.scheduleItems.any((item) => item.id == id) ||
          store.scheduleRevision(id) != expectedRevision);
  bool get outdated => accepted ? !_matchesAccepted : stale;
  bool get startEditable => mode != ScheduleEditMode.resizeEnd;
  bool get endEditable =>
      mode == ScheduleEditMode.edit || mode == ScheduleEditMode.resizeEnd;
  int get resolvedStart =>
      startEditable ? start.resolve(timeZoneId) : original!.startAt;
  int get resolvedEnd => mode == ScheduleEditMode.move
      ? resolvedStart + original!.endAt - original!.startAt
      : endEditable
      ? end.resolve(timeZoneId)
      : original!.endAt;

  ScheduleReview review() {
    final startAt = resolvedStart;
    final endAt = resolvedEnd;
    final linkedTask = mode == ScheduleEditMode.edit
        ? taskId
        : original!.taskId;
    final linkedBoard = mode == ScheduleEditMode.edit
        ? boardId
        : original!.boardId;
    final eventTitle = mode == ScheduleEditMode.edit
        ? title
        : original!.title ?? '';
    final item = kind == ScheduleItemKind.timeBlock
        ? ScheduleItem.timeBlock(
            id: id,
            taskId: linkedTask ?? '',
            startAt: startAt,
            endAt: endAt,
            timeZoneId: timeZoneId,
          )
        : ScheduleItem.event(
            id: id,
            title: eventTitle,
            taskId: linkedTask,
            boardId: linkedBoard,
            startAt: startAt,
            endAt: endAt,
            timeZoneId: timeZoneId,
          );
    validateScheduleCollection(
      [
        for (final current in store.scheduleItems)
          if (current.id != id) current,
        item,
      ],
      parentTaskIds: {for (final task in store.tasks) task.id},
      boardIds: {for (final board in store.boards) board.id},
    );
    return ScheduleReview(
      item,
      overlappingScheduleItems(store.scheduleItems, item),
    );
  }

  bool get _matchesAccepted =>
      store.scheduleRevision(id) == _acceptedRevision &&
      (_deleted
          ? !store.scheduleItems.any((item) => item.id == id)
          : store.scheduleItems.any(
              (item) =>
                  item.id == id &&
                  jsonEncode(item.toJson()) ==
                      jsonEncode(_acceptedItem!.toJson()),
            ));

  Future<ScheduleSubmitResult> submit(
    ScheduleReview review, {
    bool allowOverlap = false,
  }) async {
    if (busy || accepted) return ScheduleSubmitResult.busy;
    if (!store.ready || store.hasStartupRecovery) {
      return ScheduleSubmitResult.recovery;
    }
    if (stale) return ScheduleSubmitResult.stale;
    try {
      final current = this.review();
      if (jsonEncode(current.item.toJson()) !=
              jsonEncode(review.item.toJson()) ||
          current.fingerprint != review.fingerprint) {
        return ScheduleSubmitResult.reviewChanged;
      }
      if (current.overlaps.isNotEmpty && !allowOverlap) {
        return ScheduleSubmitResult.reviewChanged;
      }
      return _commit(review.item, delete: false);
    } on FormatException {
      return ScheduleSubmitResult.invalid;
    } on ScheduleTimeException {
      return ScheduleSubmitResult.invalid;
    }
  }

  Future<ScheduleSubmitResult> delete() async {
    if (busy || accepted) return ScheduleSubmitResult.busy;
    if (!store.ready || store.hasStartupRecovery) {
      return ScheduleSubmitResult.recovery;
    }
    if (stale || original == null) return ScheduleSubmitResult.stale;
    return _commit(null, delete: true);
  }

  Future<ScheduleSubmitResult> _commit(
    ScheduleItem? item, {
    required bool delete,
  }) async {
    busy = true;
    try {
      final changed = delete
          ? store.deleteScheduleItem(id, expectedRevision: expectedRevision!)
          : original == null
          ? store.addScheduleItem(item!)
          : store.updateScheduleItem(
              item!,
              expectedRevision: expectedRevision!,
            );
      if (!changed) return ScheduleSubmitResult.stale;
      accepted = true;
      _deleted = delete;
      _acceptedItem = item;
      _acceptedRevision = store.scheduleRevision(id);
      final result = await store.flush(waitForReminders: false);
      if (!_matchesAccepted) return ScheduleSubmitResult.stale;
      return result.success
          ? ScheduleSubmitResult.saved
          : ScheduleSubmitResult.unsaved;
    } on StateError {
      return ScheduleSubmitResult.recovery;
    } on FormatException {
      return ScheduleSubmitResult.invalid;
    } finally {
      busy = false;
    }
  }

  Future<ScheduleSubmitResult> retry() async {
    if (busy || !accepted) return ScheduleSubmitResult.busy;
    if (!store.ready || store.hasStartupRecovery) {
      return ScheduleSubmitResult.recovery;
    }
    if (!_matchesAccepted) return ScheduleSubmitResult.stale;
    busy = true;
    try {
      final result = await store.retrySave(waitForReminders: false);
      if (!_matchesAccepted) return ScheduleSubmitResult.stale;
      return result.success
          ? ScheduleSubmitResult.saved
          : ScheduleSubmitResult.unsaved;
    } finally {
      busy = false;
    }
  }
}
