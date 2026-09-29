import 'calendar_dates.dart';

/// Session latch for the Today-page completion celebration.
///
/// The latch lives only in memory. It is not a setting and is not written into
/// the save snapshot or a backup, so a new process starts with no day recorded.
/// Within one process it records the local civil day of a celebration and
/// refuses another one until that day has passed.
class TodayCelebrationMemory {
  TodayCelebrationMemory({DateTime Function()? clock})
    : clock = clock ?? DateTime.now;

  /// Clock used for the civil day. Tests replace it; the product uses the
  /// device clock. List membership itself still follows [DateTime.now] inside
  /// the Today query — this clock only decides whether today was already
  /// celebrated.
  DateTime Function() clock;

  int? _celebratedDayMs;

  /// Local midnight of the civil day that already consumed its celebration,
  /// or null when this process has not celebrated yet.
  int? get celebratedDayMs => _celebratedDayMs;

  /// Whether the Today page should present the celebration for this
  /// observation. A `true` result records the clock's civil day.
  ///
  /// [scopeUnchanged] is false when the board or the all-boards filter changed;
  /// those transitions never celebrate and never consume the day.
  /// [openBefore] / [openAfter] are the incomplete Today rows in the current
  /// scope. [removedIds] must be exactly the rows that left, and every one of
  /// them must now be completed — a row that left because its plan was cleared,
  /// its date moved, or it was deleted does not qualify.
  bool consider({
    required bool scopeUnchanged,
    required int openBefore,
    required int openAfter,
    required Set<String> removedIds,
    required bool Function(String id) isCompleted,
  }) {
    if (!scopeUnchanged) return false;
    if (openBefore <= 0 || openAfter != 0) return false;
    if (removedIds.length != openBefore - openAfter) return false;
    if (!removedIds.every(isCompleted)) return false;
    final day = civilDate(clock());
    if (_celebratedDayMs != null &&
        isSameCivilDay(
          DateTime.fromMillisecondsSinceEpoch(_celebratedDayMs!),
          day,
        )) {
      return false;
    }
    _celebratedDayMs = day.millisecondsSinceEpoch;
    return true;
  }
}
