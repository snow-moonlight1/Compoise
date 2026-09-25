import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../models.dart';
import 'desktop_shell_service.dart';

/// Generates a deterministic 31-bit non-negative integer notification ID
/// using FNV-1a hash algorithm to prevent collisions and fit within Android's 32-bit int.
int generateNotificationId(String taskId, {String? subtaskId}) {
  final compositeKey =
      subtaskId == null ? 'task_$taskId' : 'sub_${taskId}_$subtaskId';
  var hash = 0x811c9dc5;
  for (var i = 0; i < compositeKey.length; i++) {
    hash ^= compositeKey.codeUnitAt(i);
    hash = (hash * 0x01000193) & 0x7fffffff;
  }
  return hash;
}

/// Reminder permissions and platform availability status.
enum ReminderPermissionStatus {
  /// Notification and exact alarm permissions granted.
  granted,

  /// Notification permission denied (POST_NOTIFICATIONS not allowed).
  denied,

  /// Notifications allowed, but exact alarms restricted (Android 12+ Inexact fallback).
  inexactOnly,

  /// Current platform does not support local reminders.
  unsupported,

  /// The platform exposes no queryable state, so the answer is not known.
  unknown,
}

/// Outcome of one scheduling attempt.
enum ReminderScheduleStatus {
  /// The operating system accepted a future trigger.
  scheduled,

  /// Only an in-app timer could be armed, so delivery needs a running app.
  scheduledInApp,

  /// The trigger had passed, so the notification was shown immediately.
  displayed,

  /// A newer edit or cancel replaced this request before it reached the OS.
  superseded,

  /// The trigger is older than the delivery grace window and was dropped.
  expired,

  /// The service is not ready, so nothing reached the operating system.
  unavailable,

  /// The platform rejected the request.
  failed,
}

/// Result of a scheduling attempt. [errorKind] is an exception category only and
/// never carries task titles, notes or credentials.
@immutable
class ReminderScheduleResult {
  const ReminderScheduleResult(
    this.status, {
    required this.notificationId,
    this.errorKind,
  });

  final ReminderScheduleStatus status;
  final int notificationId;
  final String? errorKind;

  bool get accepted =>
      status == ReminderScheduleStatus.scheduled ||
      status == ReminderScheduleStatus.scheduledInApp ||
      status == ReminderScheduleStatus.displayed;

  bool get needsRetry =>
      status == ReminderScheduleStatus.failed ||
      status == ReminderScheduleStatus.unavailable;
}

/// Outcome of one cancellation attempt.
enum ReminderCancelStatus {
  /// The operating system no longer has this notification pending.
  cancelled,

  /// The service is not ready yet; the cancellation still owes a retry.
  unavailable,

  /// The platform rejected the cancellation, so a ghost notification may remain.
  failed,
}

@immutable
class ReminderCancelResult {
  const ReminderCancelResult(
    this.status, {
    required this.notificationId,
    this.errorKind,
  });

  final ReminderCancelStatus status;
  final int notificationId;
  final String? errorKind;

  bool get succeeded => status == ReminderCancelStatus.cancelled;

  bool get needsRetry =>
      status == ReminderCancelStatus.failed ||
      status == ReminderCancelStatus.unavailable;
}

/// Which kind of work the operating system still owes us.
enum ReminderPendingKind {
  /// A reminder the user expects but that was never armed.
  reschedule,

  /// A notification that must still be cancelled.
  cancel,
}

/// Retryable reminder work kept in a local ledger so a restart can finish it.
class ReminderPendingJob {
  const ReminderPendingJob({
    required this.kind,
    required this.notificationId,
    required this.boardId,
    required this.taskId,
    this.subtaskId,
    this.triggerAtMs,
    this.attempts = 0,
    this.updatedAtMs = 0,
    this.errorKind,
  });

  final ReminderPendingKind kind;
  final int notificationId;
  final String boardId;
  final String taskId;
  final String? subtaskId;
  final int? triggerAtMs;
  final int attempts;
  final int updatedAtMs;
  final String? errorKind;

  String get key => '${kind.name}:$notificationId';

  ReminderPayload get payload =>
      ReminderPayload(boardId: boardId, taskId: taskId, subtaskId: subtaskId);

  ReminderPendingJob withAttempt({int? failedAtMs, String? errorKind}) =>
      ReminderPendingJob(
        kind: kind,
        notificationId: notificationId,
        boardId: boardId,
        taskId: taskId,
        subtaskId: subtaskId,
        triggerAtMs: triggerAtMs,
        attempts: attempts + 1,
        updatedAtMs: failedAtMs ?? updatedAtMs,
        errorKind: errorKind ?? this.errorKind,
      );

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'id': notificationId,
    'boardId': boardId,
    'taskId': taskId,
    if (subtaskId != null) 'subtaskId': subtaskId,
    if (triggerAtMs != null) 'triggerAtMs': triggerAtMs,
    'attempts': attempts,
    'updatedAtMs': updatedAtMs,
    if (errorKind != null) 'errorKind': errorKind,
  };

  static ReminderPendingJob? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final json = raw.cast<String, dynamic>();
    final kind = switch (json['kind']) {
      'reschedule' => ReminderPendingKind.reschedule,
      'cancel' => ReminderPendingKind.cancel,
      _ => null,
    };
    final id = json['id'];
    final taskId = json['taskId'];
    if (kind == null || id is! int || taskId is! String || taskId.isEmpty) {
      return null;
    }
    return ReminderPendingJob(
      kind: kind,
      notificationId: id,
      boardId: (json['boardId'] as String?) ?? '',
      taskId: taskId,
      subtaskId: json['subtaskId'] as String?,
      triggerAtMs: json['triggerAtMs'] is int ? json['triggerAtMs'] as int : null,
      attempts: json['attempts'] is int ? json['attempts'] as int : 0,
      updatedAtMs: json['updatedAtMs'] is int ? json['updatedAtMs'] as int : 0,
      errorKind: json['errorKind'] is String ? json['errorKind'] as String : null,
    );
  }
}

/// Where the retry ledger is kept. Production persists it locally so an app
/// restart can still finish pending reminder work.
abstract class ReminderLedgerStore {
  Future<String?> read();

  /// `null` clears the ledger.
  Future<void> write(String? value);
}

class InMemoryReminderLedgerStore implements ReminderLedgerStore {
  String? value;
  int writeCount = 0;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String? value) async {
    this.value = value;
    writeCount++;
  }
}

/// Local-only key: never part of ExportData, backups or credential migration.
class SharedPreferencesReminderLedgerStore implements ReminderLedgerStore {
  static const String storageKey = 'matrixflow-reminder-pending';

  @override
  Future<String?> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(storageKey);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String? value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (value == null) {
        await prefs.remove(storageKey);
      } else {
        await prefs.setString(storageKey, value);
      }
    } catch (_) {
      // A lost ledger only means the next start cannot compensate automatically.
    }
  }
}

/// Counts from one restart reconciliation pass.
@immutable
class ReminderReconcileReport {
  const ReminderReconcileReport({
    this.recovered = 0,
    this.retried = 0,
    this.dropped = 0,
    this.stillPending = 0,
  });

  final int recovered;
  final int retried;
  final int dropped;
  final int stillPending;

  @override
  String toString() =>
      'ReminderReconcileReport(recovered: $recovered, retried: $retried, '
      'dropped: $dropped, stillPending: $stillPending)';
}

/// Payload included with notification for deep-linking back to the task.
class ReminderPayload {
  final String boardId;
  final String taskId;
  final String? subtaskId;

  const ReminderPayload({
    required this.boardId,
    required this.taskId,
    this.subtaskId,
  });

  Map<String, dynamic> toJson() => {
    'boardId': boardId,
    'taskId': taskId,
    if (subtaskId != null) 'subtaskId': subtaskId,
  };

  factory ReminderPayload.fromJson(Map<String, dynamic> json) =>
      ReminderPayload(
        boardId: (json['boardId'] as String?) ?? '',
        taskId: (json['taskId'] as String?) ?? '',
        subtaskId: json['subtaskId'] as String?,
      );

  String serialize() => jsonEncode(toJson());

  static ReminderPayload? deserialize(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return ReminderPayload.fromJson(decoded);
      }
    } catch (_) {}
    return null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReminderPayload &&
          runtimeType == other.runtimeType &&
          boardId == other.boardId &&
          taskId == other.taskId &&
          subtaskId == other.subtaskId;

  @override
  int get hashCode => Object.hash(boardId, taskId, subtaskId);
}

/// Record of a scheduled reminder for in-memory and test tracking.
class ScheduledReminderRecord {
  final int id;
  final String boardId;
  final String taskId;
  final String? subtaskId;
  final String title;
  final String? body;
  final int triggerAtMs;
  final bool sound;
  final bool vibrate;

  const ScheduledReminderRecord({
    required this.id,
    required this.boardId,
    required this.taskId,
    this.subtaskId,
    required this.title,
    this.body,
    required this.triggerAtMs,
    this.sound = true,
    this.vibrate = true,
  });
}

/// Requests notification access the first time a reminder is chosen.
/// Callers still persist the reminder even when permission is denied.
Future<ReminderPermissionStatus> requestReminderAccess() async {
  final service = ReminderService.instance;
  final current = await service.checkPermission();
  if (current == ReminderPermissionStatus.granted ||
      current == ReminderPermissionStatus.unsupported ||
      current == ReminderPermissionStatus.unknown) {
    return current;
  }
  return service.requestPermission();
}

/// Abstract cross-platform reminder service.
abstract class ReminderService {
  ReminderService({ReminderLedgerStore? ledgerStore})
    : ledgerStore = ledgerStore ?? InMemoryReminderLedgerStore();

  /// A reminder keeps at most this many automatic retries, so a permanently
  /// broken channel cannot be retried on every start.
  static const int maxAutomaticRetries = 5;
  static const int maxPendingJobs = 64;
  static const int maxTrackedReminders = 512;
  static const int pendingTtlMs = 7 * 24 * 60 * 60 * 1000;
  static const int deliveryGraceMs = 5 * 60 * 1000;

  final ReminderLedgerStore ledgerStore;

  final ValueNotifier<Map<int, ReminderPayload>> scheduleFailures =
      ValueNotifier({});

  /// Reminders whose cancellation the platform never confirmed.
  final ValueNotifier<Map<int, ReminderPayload>> cancelFailures =
      ValueNotifier({});

  /// Permission state from the most recent real probe, `null` when never probed.
  final ValueNotifier<ReminderPermissionStatus?> observedPermission =
      ValueNotifier(null);

  final Map<String, ReminderPendingJob> _pendingJobs = {};
  bool _pendingLoaded = false;
  Future<void>? _pendingLoadFuture;
  Future<void> _pendingWrites = Future.value();

  /// Failed schedules, projected from the ledger and keyed by notification id.
  Map<String, ReminderPendingJob> get pendingJobs =>
      Map.unmodifiable(_pendingJobs);

  /// Reads persisted retry records once per process. Safe to call repeatedly.
  Future<void> loadPendingJobs() {
    if (_pendingLoaded) return Future.value();
    return _pendingLoadFuture ??= _readPendingJobs().whenComplete(() {
      _pendingLoadFuture = null;
    });
  }

  Future<void> _readPendingJobs() async {
    final raw = await ledgerStore.read();
    _pendingLoaded = true;
    if (raw == null || raw.trim().isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final jobs = decoded['jobs'];
      if (jobs is! List) return;
      var merged = false;
      for (final entry in jobs) {
        final job = ReminderPendingJob.fromJson(entry);
        if (job == null) continue;
        // In-memory records are newer than anything still on disk.
        if (_pendingJobs.containsKey(job.key) ||
            _pendingJobs.length >= maxPendingJobs) {
          continue;
        }
        _pendingJobs[job.key] = job;
        merged = true;
      }
      if (merged) _publishPendingJobs();
    } catch (e) {
      debugPrint('Ignored unreadable reminder ledger: ${e.runtimeType}');
    }
  }

  void _publishPendingJobs() {
    final schedules = <int, ReminderPayload>{};
    final cancels = <int, ReminderPayload>{};
    for (final job in _pendingJobs.values) {
      if (job.kind == ReminderPendingKind.reschedule) {
        schedules[job.notificationId] = job.payload;
      } else {
        cancels[job.notificationId] = job.payload;
      }
    }
    if (!mapEquals(scheduleFailures.value, schedules)) {
      scheduleFailures.value = Map.unmodifiable(schedules);
    }
    if (!mapEquals(cancelFailures.value, cancels)) {
      cancelFailures.value = Map.unmodifiable(cancels);
    }
  }

  /// Serializes the ledger to disk after the one-time load, so a record written
  /// during startup cannot erase the records still on disk. Never awaited by a
  /// schedule or cancel result: reminder results must not depend on storage.
  void _persistPendingJobs() {
    _pendingWrites = _pendingWrites
        .then((_) async {
          await loadPendingJobs();
          final payload = jsonEncode({
            'v': 1,
            'jobs': [for (final job in _pendingJobs.values) job.toJson()],
          });
          await ledgerStore.write(_pendingJobs.isEmpty ? null : payload);
        })
        .catchError((Object error) {
          debugPrint(
            'Reminder ledger write failed: ${reminderErrorKind(error)}',
          );
        });
  }

  /// Updates the in-memory ledger and notifies the UI synchronously.
  Future<void> trackPendingJob(ReminderPendingJob job) async {
    if (_pendingJobs.length >= maxPendingJobs &&
        !_pendingJobs.containsKey(job.key)) {
      return;
    }
    _pendingJobs[job.key] = job;
    _publishPendingJobs();
    _persistPendingJobs();
  }

  Future<void> clearPendingJob(String key) async {
    if (_pendingJobs.remove(key) == null) return;
    _publishPendingJobs();
    _persistPendingJobs();
  }

  Future<void> clearPendingForNotification(int notificationId) async {
    final suffix = ':$notificationId';
    final keys = _pendingJobs.keys.where((k) => k.endsWith(suffix)).toList();
    if (keys.isEmpty) return;
    for (final key in keys) {
      _pendingJobs.remove(key);
    }
    _publishPendingJobs();
    _persistPendingJobs();
  }

  Future<void> clearAllPendingJobs() async {
    // Let an in-flight read settle before wiping, or it could repopulate the
    // in-memory ledger after the clear has already reached disk.
    try {
      await loadPendingJobs();
    } catch (_) {
      // A deliberate full wipe can proceed even when the old ledger is unreadable.
    }
    _pendingLoaded = true;
    _pendingJobs.clear();
    _publishPendingJobs();
    _persistPendingJobs();
  }

  /// Completes once every queued ledger write has been attempted.
  @visibleForTesting
  Future<void> pendingLedgerWrites() => _pendingWrites;

  static ReminderService? _instance;
  static ReminderService get instance => _instance ??= _createDefault();
  static set instance(ReminderService service) => _instance = service;

  static ReminderService _createDefault() {
    if (kIsWeb) return NoopReminderService();
    try {
      if (Platform.environment.containsKey('FLUTTER_TEST')) {
        return NoopReminderService();
      }
    } catch (_) {}
    if (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.windows) {
      return FlutterLocalNotificationsReminderService();
    }
    return NoopReminderService();
  }

  @visibleForTesting
  static void resetForTest([ReminderService? testInstance]) {
    _instance = testInstance;
  }

  /// Current notification tap handler callback.
  void Function(ReminderPayload payload)? get onNotificationSelected;
  set onNotificationSelected(void Function(ReminderPayload payload)? handler);

  /// Stores a payload forwarded by a later Windows process.
  ///
  /// The running instance delivers it when a screen handler is attached.
  void acceptExternalActivation(ReminderPayload payload) {}

  /// Initializes local notification service and binds notification tap handler.
  Future<void> init({
    void Function(ReminderPayload payload)? onNotificationSelected,
  });

  /// Permission state as reported by the platform, then cached for the UI.
  Future<ReminderPermissionStatus> checkPermission() async {
    final status = await probePermission();
    observedPermission.value = status;
    return status;
  }

  /// Platform-specific permission probe.
  Future<ReminderPermissionStatus> probePermission();

  /// Requests runtime notification permission and reports the resulting state.
  Future<ReminderPermissionStatus> requestPermission();

  /// Schedules a local notification reminder for a task or subtask.
  Future<ReminderScheduleResult> scheduleReminder({
    required String boardId,
    required String taskId,
    String? subtaskId,
    required String title,
    String? body,
    required int triggerAtMs,
    bool sound = true,
    bool vibrate = true,
    bool recordRetry = true,
  });

  /// Cancels an existing scheduled reminder.
  Future<ReminderCancelResult> cancelReminder(
    String taskId, {
    String? subtaskId,
  });

  /// Cancels all reminders for all tasks on a specific board.
  Future<void> cancelAllForBoard(String boardId, List<Task> tasksOnBoard);

  /// Cancels all scheduled reminders across the entire system.
  Future<void> cancelAll();

  /// Reschedules all future uncompleted reminders (e.g. after reboot or import).
  Future<void> rescheduleAllFuture(List<Task> allTasks);

  /// Replays ledger work that a previous run could not finish, dropping records
  /// the current task data no longer backs. Runs after [rescheduleAllFuture].
  Future<ReminderReconcileReport> reconcilePending(List<Task> allTasks) async {
    await loadPendingJobs();
    var recovered = 0, retried = 0, dropped = 0, stillPending = 0;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    for (final key in _pendingJobs.keys.toList()) {
      final job = _pendingJobs[key];
      if (job == null) continue;
      final tooOld =
          job.updatedAtMs > nowMs ||
          nowMs - job.updatedAtMs > pendingTtlMs;
      if (tooOld || job.attempts >= maxAutomaticRetries) {
        await clearPendingJob(key);
        dropped++;
        continue;
      }
      final source = _reminderSource(allTasks, job);
      if (job.kind == ReminderPendingKind.reschedule) {
        if (source.triggerAtMs != job.triggerAtMs ||
            source.triggerAtMs == null ||
            source.triggerAtMs! <= nowMs) {
          // Removed, completed or re-edited: the live edit path owns the
          // notification now, so never resurrect an outdated reminder.
          await clearPendingJob(key);
          dropped++;
          continue;
        }
        retried++;
        final result = await scheduleReminder(
          boardId: job.boardId,
          taskId: job.taskId,
          subtaskId: job.subtaskId,
          title: source.title ?? '',
          body: source.body,
          triggerAtMs: job.triggerAtMs!,
        );
        if (result.accepted) {
          recovered++;
        } else if (_pendingJobs.containsKey(key)) {
          await trackPendingJob(
            job.withAttempt(failedAtMs: nowMs, errorKind: result.errorKind),
          );
          stillPending++;
        } else {
          dropped++;
        }
        continue;
      }

      if (source.triggerAtMs != null && source.triggerAtMs! > nowMs) {
        // A reminder was re-added for this notification id, which replaces the
        // ghost instead of leaving it to cancel.
        await clearPendingJob(key);
        dropped++;
        continue;
      }
      retried++;
      final result = await cancelReminder(job.taskId, subtaskId: job.subtaskId);
      if (result.succeeded) {
        recovered++;
      } else if (_pendingJobs.containsKey(key)) {
        await trackPendingJob(
          job.withAttempt(failedAtMs: nowMs, errorKind: result.errorKind),
        );
        stillPending++;
      } else {
        dropped++;
      }
    }
    return ReminderReconcileReport(
      recovered: recovered,
      retried: retried,
      dropped: dropped,
      stillPending: stillPending,
    );
  }

  ({int? triggerAtMs, String? title, String? body}) _reminderSource(
    List<Task> allTasks,
    ReminderPendingJob job,
  ) {
    final task = allTasks.where((t) => t.id == job.taskId).firstOrNull;
    // A cancel job recorded without board context still has to be resolved.
    if (task == null ||
        (job.boardId.isNotEmpty && task.boardId != job.boardId)) {
      return (triggerAtMs: null, title: null, body: null);
    }
    if (job.subtaskId == null) {
      if (task.completed) return (triggerAtMs: null, title: null, body: null);
      return (
        triggerAtMs: task.reminderAt,
        title: task.title,
        body: task.notesMarkdown,
      );
    }
    final sub = task.subtasks.where((s) => s.id == job.subtaskId).firstOrNull;
    if (sub == null || sub.completed) {
      return (triggerAtMs: null, title: null, body: null);
    }
    return (
      triggerAtMs: sub.reminderAt,
      title: sub.title,
      body: task.notesMarkdown,
    );
  }

  /// Notification id shared by a task or subtask reminder.
  static int notificationIdFor(String taskId, {String? subtaskId}) =>
      generateNotificationId(taskId, subtaskId: subtaskId);

  /// Live reminders this process believes the platform holds, so a bulk cancel
  /// failure can be retried one notification at a time.
  final Map<int, ReminderPayload> trackedReminders = {};

  @protected
  Future<ReminderScheduleResult> recordScheduleOutcome({
    required ReminderPayload payload,
    required int triggerAtMs,
    required ReminderScheduleResult result,
    required bool recordRetry,
  }) async {
    switch (result.status) {
      case ReminderScheduleStatus.scheduled:
      case ReminderScheduleStatus.scheduledInApp:
      case ReminderScheduleStatus.displayed:
        if (trackedReminders.containsKey(result.notificationId) ||
            trackedReminders.length < maxTrackedReminders) {
          trackedReminders[result.notificationId] = payload;
        }
        // The same id replaces any earlier notification, so a pending cancel
        // for it is resolved too.
        await clearPendingForNotification(result.notificationId);
      case ReminderScheduleStatus.superseded:
      case ReminderScheduleStatus.expired:
        await clearPendingJob(
          '${ReminderPendingKind.reschedule.name}:${result.notificationId}',
        );
      case ReminderScheduleStatus.unavailable:
      case ReminderScheduleStatus.failed:
        if (recordRetry) {
          await trackPendingJob(
            ReminderPendingJob(
              kind: ReminderPendingKind.reschedule,
              notificationId: result.notificationId,
              boardId: payload.boardId,
              taskId: payload.taskId,
              subtaskId: payload.subtaskId,
              triggerAtMs: triggerAtMs,
              updatedAtMs: DateTime.now().millisecondsSinceEpoch,
              errorKind: result.errorKind,
            ),
          );
        }
    }
    return result;
  }

  @protected
  Future<ReminderCancelResult> recordCancelOutcome({
    required ReminderPayload payload,
    required ReminderCancelResult result,
  }) async {
    final key = '${ReminderPendingKind.cancel.name}:${result.notificationId}';
    if (result.succeeded) {
      trackedReminders.remove(result.notificationId);
      await clearPendingJob(key);
    } else {
      await trackPendingJob(
        ReminderPendingJob(
          kind: ReminderPendingKind.cancel,
          notificationId: result.notificationId,
          boardId: payload.boardId,
          taskId: payload.taskId,
          subtaskId: payload.subtaskId,
          updatedAtMs: DateTime.now().millisecondsSinceEpoch,
          errorKind: result.errorKind,
        ),
      );
    }
    return result;
  }
}

/// Only exception categories are kept: never task content, notes or keys.
String reminderErrorKind(Object error) {
  if (error is PlatformException) {
    final code = error.code;
    return code.trim().isEmpty
        ? 'PlatformException'
        : 'PlatformException/${code.replaceAll(RegExp(r'\s+'), '_')}';
  }
  return error.runtimeType.toString();
}

/// Default no-op reminder service (used for unsupported platforms or headless default).
class NoopReminderService extends ReminderService {
  void Function(ReminderPayload payload)? _onNotificationSelected;

  @override
  void Function(ReminderPayload payload)? get onNotificationSelected =>
      _onNotificationSelected;

  @override
  set onNotificationSelected(void Function(ReminderPayload payload)? handler) =>
      _onNotificationSelected = handler;

  @override
  Future<void> init({
    void Function(ReminderPayload payload)? onNotificationSelected,
  }) async {
    _onNotificationSelected = onNotificationSelected;
  }

  @override
  Future<ReminderPermissionStatus> probePermission() async =>
      ReminderPermissionStatus.granted;

  @override
  Future<ReminderPermissionStatus> requestPermission() async =>
      ReminderPermissionStatus.granted;

  @override
  Future<ReminderScheduleResult> scheduleReminder({
    required String boardId,
    required String taskId,
    String? subtaskId,
    required String title,
    String? body,
    required int triggerAtMs,
    bool sound = true,
    bool vibrate = true,
    bool recordRetry = true,
  }) async => ReminderScheduleResult(
    ReminderScheduleStatus.scheduled,
    notificationId: generateNotificationId(taskId, subtaskId: subtaskId),
  );

  @override
  Future<ReminderCancelResult> cancelReminder(
    String taskId, {
    String? subtaskId,
  }) async => ReminderCancelResult(
    ReminderCancelStatus.cancelled,
    notificationId: generateNotificationId(taskId, subtaskId: subtaskId),
  );

  @override
  Future<void> cancelAllForBoard(
    String boardId,
    List<Task> tasksOnBoard,
  ) async {}

  @override
  Future<void> cancelAll() async {}

  @override
  Future<void> rescheduleAllFuture(List<Task> allTasks) async {}
}

/// In-memory implementation of ReminderService for unit and widget testing.
class InMemoryReminderService extends ReminderService {
  InMemoryReminderService({
    ReminderPermissionStatus permission = ReminderPermissionStatus.granted,
    super.ledgerStore,
  }) : permissionStatus = permission;

  final Map<int, ScheduledReminderRecord> scheduled = {};
  final List<int> cancelledIds = [];
  int cancelAllCount = 0;
  int requestPermissionCount = 0;

  /// State the fake platform reports when asked.
  ReminderPermissionStatus permissionStatus;

  /// When non-null, every schedule/cancel reports it as a platform rejection.
  Object? scheduleFault;
  Object? cancelFault;
  void Function(ReminderPayload payload)? _onNotificationSelected;

  @override
  void Function(ReminderPayload payload)? get onNotificationSelected =>
      _onNotificationSelected;

  @override
  set onNotificationSelected(void Function(ReminderPayload payload)? handler) =>
      _onNotificationSelected = handler;

  void triggerNotificationTap(ReminderPayload payload) {
    _onNotificationSelected?.call(payload);
  }

  @override
  Future<void> init({
    void Function(ReminderPayload payload)? onNotificationSelected,
  }) async {
    _onNotificationSelected = onNotificationSelected;
  }

  @override
  Future<ReminderPermissionStatus> probePermission() async =>
      permissionStatus;

  @override
  Future<ReminderPermissionStatus> requestPermission() async {
    requestPermissionCount++;
    return permissionStatus;
  }

  @override
  Future<ReminderScheduleResult> scheduleReminder({
    required String boardId,
    required String taskId,
    String? subtaskId,
    required String title,
    String? body,
    required int triggerAtMs,
    bool sound = true,
    bool vibrate = true,
    bool recordRetry = true,
  }) async {
    final id = generateNotificationId(taskId, subtaskId: subtaskId);
    final payload = ReminderPayload(
      boardId: boardId,
      taskId: taskId,
      subtaskId: subtaskId,
    );
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    ReminderScheduleResult result;
    if (nowMs - triggerAtMs > ReminderService.deliveryGraceMs) {
      // Overdue suppression: discard if older than the grace window.
      result = ReminderScheduleResult(
        ReminderScheduleStatus.expired,
        notificationId: id,
      );
    } else if (scheduleFault != null) {
      result = ReminderScheduleResult(
        ReminderScheduleStatus.failed,
        notificationId: id,
        errorKind: reminderErrorKind(scheduleFault!),
      );
    } else {
      scheduled[id] = ScheduledReminderRecord(
        id: id,
        boardId: boardId,
        taskId: taskId,
        subtaskId: subtaskId,
        title: title,
        body: body,
        triggerAtMs: triggerAtMs,
        sound: sound,
        vibrate: vibrate,
      );
      result = ReminderScheduleResult(
        triggerAtMs <= nowMs
            ? ReminderScheduleStatus.displayed
            : ReminderScheduleStatus.scheduled,
        notificationId: id,
      );
    }
    return recordScheduleOutcome(
      payload: payload,
      triggerAtMs: triggerAtMs,
      result: result,
      recordRetry: recordRetry,
    );
  }

  @override
  Future<ReminderCancelResult> cancelReminder(
    String taskId, {
    String? subtaskId,
  }) async {
    final id = generateNotificationId(taskId, subtaskId: subtaskId);
    final payload =
        trackedReminders[id] ??
        ReminderPayload(boardId: '', taskId: taskId, subtaskId: subtaskId);
    ReminderCancelResult result;
    if (cancelFault != null) {
      result = ReminderCancelResult(
        ReminderCancelStatus.failed,
        notificationId: id,
        errorKind: reminderErrorKind(cancelFault!),
      );
    } else {
      scheduled.remove(id);
      cancelledIds.add(id);
      result = ReminderCancelResult(
        ReminderCancelStatus.cancelled,
        notificationId: id,
      );
    }
    return recordCancelOutcome(payload: payload, result: result);
  }

  @override
  Future<void> cancelAllForBoard(
    String boardId,
    List<Task> tasksOnBoard,
  ) async {
    for (final t in tasksOnBoard) {
      if (t.reminderAt != null) {
        await cancelReminder(t.id);
      }
      for (final s in t.subtasks) {
        if (s.reminderAt != null) {
          await cancelReminder(t.id, subtaskId: s.id);
        }
      }
    }
  }

  @override
  Future<void> cancelAll() async {
    scheduled.clear();
    trackedReminders.clear();
    await clearAllPendingJobs();
    cancelAllCount++;
  }

  @override
  Future<void> rescheduleAllFuture(List<Task> allTasks) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    for (final t in allTasks) {
      if (t.completed) continue;
      if (t.reminderAt != null && t.reminderAt! > nowMs) {
        await scheduleReminder(
          boardId: t.boardId,
          taskId: t.id,
          title: t.title,
          body: t.notesMarkdown,
          triggerAtMs: t.reminderAt!,
        );
      }
      for (final s in t.subtasks) {
        if (s.completed) continue;
        if (s.reminderAt != null && s.reminderAt! > nowMs) {
          await scheduleReminder(
            boardId: t.boardId,
            taskId: t.id,
            subtaskId: s.id,
            title: s.title,
            body: s.notesMarkdown,
            triggerAtMs: s.reminderAt!,
          );
        }
      }
    }
  }
}

/// Production Android and Windows implementation using flutter_local_notifications.
class FlutterLocalNotificationsReminderService extends ReminderService {
  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;

  /// Set only when the platform explicitly declined to initialise. Until then
  /// the notification state is simply not known.
  bool _platformDeclined = false;
  Completer<void>? _initCompleter;
  void Function(ReminderPayload payload)? _onNotificationSelected;
  final Map<int, Timer> _activeTimers = {};
  final Map<int, int> _revision = {};
  Future<void> _chain = Future.value();
  List<Task>? _queuedReschedule;
  ReminderPayload? _pendingLaunchPayload;
  bool _consumedLaunchPayload = false;
  int _restoreGeneration = 0;

  @override
  void Function(ReminderPayload payload)? get onNotificationSelected =>
      _onNotificationSelected;

  @override
  set onNotificationSelected(void Function(ReminderPayload payload)? handler) {
    _onNotificationSelected = handler;
    final pending = _pendingLaunchPayload;
    if (handler != null && pending != null) {
      _pendingLaunchPayload = null;
      handler(pending);
    }
  }

  @override
  void acceptExternalActivation(ReminderPayload payload) {
    _deliverPayload(payload);
  }

  @visibleForTesting
  int get activeTimerCount => _activeTimers.length;

  @visibleForTesting
  String? lastScheduleError;

  @visibleForTesting
  void setInitializedForTest(bool val) {
    _initialized = val;
    _platformDeclined = !val;
    _initCompleter ??= Completer<void>();
    if (val && !_initCompleter!.isCompleted) {
      _initCompleter!.complete();
    }
  }

  FlutterLocalNotificationsReminderService({
    FlutterLocalNotificationsPlugin? plugin,
    ReminderLedgerStore? ledgerStore,
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin(),
       super(ledgerStore: ledgerStore ?? SharedPreferencesReminderLedgerStore());

  int _bump(int notifId) => _revision[notifId] = (_revision[notifId] ?? 0) + 1;

  Future<T> _enqueue<T>(Future<T> Function() op) {
    final next = _chain.then((_) => op());
    _chain = next.then<void>((_) {}).catchError((Object _) {});
    return next;
  }

  void _deliverPayload(ReminderPayload payload, {bool fromLaunch = false}) {
    if (fromLaunch) {
      if (_consumedLaunchPayload) return;
      _consumedLaunchPayload = true;
    }
    if (defaultTargetPlatform == TargetPlatform.windows) {
      DesktopShellService.instance.restoreWindow();
    }
    final handler = _onNotificationSelected;
    if (handler != null) {
      handler(payload);
    } else {
      _pendingLaunchPayload = payload;
    }
  }

  @override
  Future<void> init({
    void Function(ReminderPayload payload)? onNotificationSelected,
  }) async {
    if (onNotificationSelected != null) {
      _onNotificationSelected = onNotificationSelected;
    }
    if (_initialized) return;
    if (_initCompleter != null) return _initCompleter!.future;

    final gate = Completer<void>();
    _initCompleter = gate;

    try {
      try {
        tz.initializeTimeZones();
      } catch (_) {}

      const androidSettings = AndroidInitializationSettings(
        '@mipmap/ic_launcher',
      );
      const windowsSettings = WindowsInitializationSettings(
        appName: 'MatrixFlow AI',
        appUserModelId: 'MatrixFlow.MatrixFlowApp.1.0',
        guid: '69a03975-2989-4d05-b778-5e824707612f',
      );
      const initSettings = InitializationSettings(
        android: androidSettings,
        windows: windowsSettings,
      );

      final ready = await _plugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (response) {
          final payload = ReminderPayload.deserialize(response.payload);
          if (payload != null) {
            _deliverPayload(payload);
          } else if (defaultTargetPlatform == TargetPlatform.windows) {
            DesktopShellService.instance.restoreWindow();
          }
        },
      );
      // Only an explicit `false` means the platform declined: Android and iOS
      // answer through a channel that can also return nothing at all.
      final accepted = ready != false;
      _platformDeclined = !accepted;
      _initialized = accepted;
      if (!accepted) {
        // Allow a later call to retry initialization instead of latching a
        // completed gate that reports success.
        _initCompleter = null;
        debugPrint('Local notifications unavailable: platform init failed');
      }

      try {
        final dynamic raw =
            (_plugin as dynamic).getNotificationAppLaunchDetails();
        if (raw is Future) {
          final launch = await raw;
          if (launch is NotificationAppLaunchDetails &&
              launch.didNotificationLaunchApp) {
            final payload = ReminderPayload.deserialize(
              launch.notificationResponse?.payload,
            );
            if (payload != null) {
              _deliverPayload(payload, fromLaunch: true);
            }
          }
        }
      } catch (e) {
        debugPrint(
          'Failed to read notification launch details: ${reminderErrorKind(e)}',
        );
      }

      final queued = _queuedReschedule;
      _queuedReschedule = null;
      if (queued != null) {
        await _rescheduleReady(queued);
      }
    } catch (e) {
      _initCompleter = null;
      debugPrint(
        'Failed to initialize local notifications: ${reminderErrorKind(e)}',
      );
    } finally {
      if (!gate.isCompleted) gate.complete();
    }
  }

  @override
  Future<ReminderPermissionStatus> probePermission() async {
    try {
      if (defaultTargetPlatform == TargetPlatform.windows) {
        // Windows can report that the toast channel declined, but the user's
        // notification setting and Focus Assist state are not queryable
        // through this plugin, so the honest default answer is "unknown".
        return _platformDeclined
            ? ReminderPermissionStatus.unsupported
            : ReminderPermissionStatus.unknown;
      }
      final androidImpl =
          _plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >();
      if (androidImpl == null) return ReminderPermissionStatus.unsupported;

      final notificationsEnabled = await androidImpl.areNotificationsEnabled();
      if (notificationsEnabled == null) return ReminderPermissionStatus.unknown;
      if (!notificationsEnabled) return ReminderPermissionStatus.denied;

      final canExact = await androidImpl.canScheduleExactNotifications();
      if (canExact == null) return ReminderPermissionStatus.unknown;
      return canExact
          ? ReminderPermissionStatus.granted
          : ReminderPermissionStatus.inexactOnly;
    } catch (e) {
      debugPrint('Notification permission probe failed: ${e.runtimeType}');
      return ReminderPermissionStatus.unknown;
    }
  }

  @override
  Future<ReminderPermissionStatus> requestPermission() async {
    try {
      if (defaultTargetPlatform == TargetPlatform.windows) {
        return await checkPermission();
      }
      final androidImpl =
          _plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >();
      if (androidImpl == null) return ReminderPermissionStatus.unsupported;

      final granted = await androidImpl.requestNotificationsPermission();
      if (granted == null) return ReminderPermissionStatus.unknown;
      if (granted) {
        final canExact = await androidImpl.canScheduleExactNotifications();
        if (canExact == false) {
          try {
            await androidImpl.requestExactAlarmsPermission();
          } catch (_) {}
        }
      }
      return await checkPermission();
    } catch (e) {
      debugPrint('Notification permission request failed: ${e.runtimeType}');
      return ReminderPermissionStatus.unknown;
    }
  }

  NotificationDetails _details({
    String? body,
    required bool sound,
    required bool vibrate,
  }) {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        'matrixflow_reminders',
        'MatrixFlow Reminders',
        channelDescription: 'Task and subtask deadline reminders',
        importance: Importance.max,
        priority: Priority.high,
        playSound: sound,
        enableVibration: vibrate,
      ),
      windows: WindowsNotificationDetails(
        subtitle: (body != null && body.trim().isNotEmpty) ? body : null,
        duration: WindowsNotificationDuration.long,
      ),
    );
  }

  @override
  Future<ReminderScheduleResult> scheduleReminder({
    required String boardId,
    required String taskId,
    String? subtaskId,
    required String title,
    String? body,
    required int triggerAtMs,
    bool sound = true,
    bool vibrate = true,
    bool recordRetry = true,
  }) {
    final notifId = generateNotificationId(taskId, subtaskId: subtaskId);
    final gen = _bump(notifId);
    _activeTimers[notifId]?.cancel();
    _activeTimers.remove(notifId);
    final payload = ReminderPayload(
      boardId: boardId,
      taskId: taskId,
      subtaskId: subtaskId,
    );
    return _enqueue(() async {
      ReminderScheduleResult at(
        ReminderScheduleStatus status, {
        String? errorKind,
      }) => ReminderScheduleResult(
        status,
        notificationId: notifId,
        errorKind: errorKind,
      );

      Future<ReminderScheduleResult> settle(
        ReminderScheduleStatus status, {
        String? errorKind,
      }) => recordScheduleOutcome(
        payload: payload,
        triggerAtMs: triggerAtMs,
        recordRetry: recordRetry,
        result: at(status, errorKind: errorKind),
      );

      if (_revision[notifId] != gen) {
        return settle(ReminderScheduleStatus.superseded);
      }
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      if (nowMs - triggerAtMs > ReminderService.deliveryGraceMs) {
        return settle(ReminderScheduleStatus.expired);
      }
      if (!_initialized) {
        return settle(
          ReminderScheduleStatus.unavailable,
          errorKind: 'notInitialized',
        );
      }

      final serializedPayload = payload.serialize();
      final notifDetails = _details(body: body, sound: sound, vibrate: vibrate);
      ReminderScheduleResult result;
      try {
        if (triggerAtMs <= nowMs) {
          await _plugin.show(
            notifId,
            title,
            body,
            notifDetails,
            payload: serializedPayload,
          );
          result = ReminderScheduleResult(
            ReminderScheduleStatus.displayed,
            notificationId: notifId,
          );
        } else if (defaultTargetPlatform == TargetPlatform.windows) {
          result = await _scheduleWindows(
            payload: payload,
            notifId: notifId,
            gen: gen,
            title: title,
            body: body,
            triggerAtMs: triggerAtMs,
            notifDetails: notifDetails,
            serializedPayload: serializedPayload,
          );
        } else {
          await _scheduleAndroid(
            notifId: notifId,
            gen: gen,
            title: title,
            body: body,
            triggerAtMs: triggerAtMs,
            notifDetails: notifDetails,
            payload: serializedPayload,
          );
          result = ReminderScheduleResult(
            ReminderScheduleStatus.scheduled,
            notificationId: notifId,
          );
        }
      } catch (e) {
        lastScheduleError = reminderErrorKind(e);
        debugPrint('Notification scheduling failed: $lastScheduleError');
        result = ReminderScheduleResult(
          ReminderScheduleStatus.failed,
          notificationId: notifId,
          errorKind: lastScheduleError,
        );
      }

      if (_revision[notifId] != gen) {
        // A cancel or a newer edit took over while the OS was accepting this
        // request. Compensate before the next queued operation starts.
        try {
          await _plugin.cancel(notifId);
        } catch (e) {
          debugPrint(
            'Superseded notification cleanup failed: ${reminderErrorKind(e)}',
          );
        }
        result = ReminderScheduleResult(
          ReminderScheduleStatus.superseded,
          notificationId: notifId,
        );
      }
      return recordScheduleOutcome(
        payload: payload,
        triggerAtMs: triggerAtMs,
        recordRetry: recordRetry,
        result: result,
      );
    });
  }

  Future<ReminderScheduleResult> _scheduleWindows({
    required ReminderPayload payload,
    required int notifId,
    required int gen,
    required String title,
    String? body,
    required int triggerAtMs,
    required NotificationDetails notifDetails,
    required String serializedPayload,
  }) async {
    String? nativeErrorKind;
    try {
      final scheduledDate = tz.TZDateTime.fromMillisecondsSinceEpoch(
        tz.local,
        triggerAtMs,
      );
      if (_revision[notifId] != gen) {
        return ReminderScheduleResult(
          ReminderScheduleStatus.superseded,
          notificationId: notifId,
        );
      }
      await _plugin.zonedSchedule(
        notifId,
        title,
        body,
        scheduledDate,
        notifDetails,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: serializedPayload,
      );
      return ReminderScheduleResult(
        ReminderScheduleStatus.scheduled,
        notificationId: notifId,
      );
    } catch (e) {
      nativeErrorKind = reminderErrorKind(e);
      lastScheduleError = nativeErrorKind;
      debugPrint('Native Windows schedule failed: $nativeErrorKind');
    }
    if (_revision[notifId] != gen) {
      return ReminderScheduleResult(
        ReminderScheduleStatus.superseded,
        notificationId: notifId,
      );
    }
    final delayMs = triggerAtMs - DateTime.now().millisecondsSinceEpoch;
    if (delayMs <= 0) {
      return ReminderScheduleResult(
        ReminderScheduleStatus.failed,
        notificationId: notifId,
        errorKind: nativeErrorKind,
      );
    }
    // Keep-alive fallback: this toast is only reachable while the app runs.
    _activeTimers[notifId] = Timer(Duration(milliseconds: delayMs), () async {
      _activeTimers.remove(notifId);
      if (_revision[notifId] != gen) return;
      try {
        await _plugin.show(
          notifId,
          title,
          body,
          notifDetails,
          payload: serializedPayload,
        );
      } catch (e) {
        final kind = reminderErrorKind(e);
        lastScheduleError = kind;
        await recordScheduleOutcome(
          payload: payload,
          triggerAtMs: triggerAtMs,
          recordRetry: true,
          result: ReminderScheduleResult(
            ReminderScheduleStatus.failed,
            notificationId: notifId,
            errorKind: kind,
          ),
        );
        debugPrint('In-app Windows notification failed: $kind');
      }
    });
    return ReminderScheduleResult(
      ReminderScheduleStatus.scheduledInApp,
      notificationId: notifId,
      errorKind: nativeErrorKind,
    );
  }

  Future<void> _scheduleAndroid({
    required int notifId,
    required int gen,
    required String title,
    String? body,
    required int triggerAtMs,
    required NotificationDetails notifDetails,
    required String payload,
  }) async {
    final androidImpl =
        _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
    final canExact = await androidImpl?.canScheduleExactNotifications() ?? true;
    if (_revision[notifId] != gen) return;
    final scheduleMode =
        canExact
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle;
    final scheduledDate = tz.TZDateTime.fromMillisecondsSinceEpoch(
      tz.local,
      triggerAtMs,
    );
    try {
      await _plugin.zonedSchedule(
        notifId,
        title,
        body,
        scheduledDate,
        notifDetails,
        androidScheduleMode: scheduleMode,
        payload: payload,
      );
    } catch (_) {
      if (_revision[notifId] != gen) return;
      try {
        await _plugin.zonedSchedule(
          notifId,
          title,
          body,
          scheduledDate,
          notifDetails,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: payload,
        );
      } catch (_) {
        if (_revision[notifId] != gen) return;
        await _plugin.zonedSchedule(
          notifId,
          title,
          body,
          scheduledDate,
          notifDetails,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: payload,
        );
      }
    }
  }

  @override
  Future<ReminderCancelResult> cancelReminder(
    String taskId, {
    String? subtaskId,
  }) {
    final notifId = generateNotificationId(taskId, subtaskId: subtaskId);
    final payload =
        trackedReminders[notifId] ??
        ReminderPayload(boardId: '', taskId: taskId, subtaskId: subtaskId);
    _bump(notifId);
    unawaited(
      clearPendingJob('${ReminderPendingKind.reschedule.name}:$notifId'),
    );
    _activeTimers[notifId]?.cancel();
    _activeTimers.remove(notifId);
    return _enqueue(() => _cancelNow(payload, notifId));
  }

  /// Cancels without queueing, so [cancelAll] can retry per notification after a
  /// bulk failure without waiting on its own chain slot.
  Future<ReminderCancelResult> _cancelNow(
    ReminderPayload payload,
    int notifId,
  ) async {
    if (!_initialized) {
      return recordCancelOutcome(
        payload: payload,
        result: ReminderCancelResult(
          ReminderCancelStatus.unavailable,
          notificationId: notifId,
          errorKind: 'notInitialized',
        ),
      );
    }
    try {
      await _plugin.cancel(notifId);
      return recordCancelOutcome(
        payload: payload,
        result: ReminderCancelResult(
          ReminderCancelStatus.cancelled,
          notificationId: notifId,
        ),
      );
    } catch (e) {
      final kind = reminderErrorKind(e);
      debugPrint('Notification cancel failed: $kind');
      return recordCancelOutcome(
        payload: payload,
        result: ReminderCancelResult(
          ReminderCancelStatus.failed,
          notificationId: notifId,
          errorKind: kind,
        ),
      );
    }
  }

  @override
  Future<void> cancelAllForBoard(
    String boardId,
    List<Task> tasksOnBoard,
  ) async {
    await Future.wait([
      for (final t in tasksOnBoard) ...[
        cancelReminder(t.id),
        for (final s in t.subtasks) cancelReminder(t.id, subtaskId: s.id),
      ],
    ]);
  }

  @override
  Future<void> cancelAll() {
    _restoreGeneration++;
    final leftovers = Map<int, ReminderPayload>.of(trackedReminders);
    trackedReminders.clear();
    final clearPending = clearAllPendingJobs();
    for (final id in _revision.keys.toList()) {
      _bump(id);
    }
    for (final timer in _activeTimers.values) {
      timer.cancel();
    }
    _activeTimers.clear();
    _queuedReschedule = null;
    return _enqueue(() async {
      await clearPending;
      if (!_initialized) return;
      try {
        await _plugin.cancelAll();
      } catch (e) {
        debugPrint('Cancel-all failed: ${reminderErrorKind(e)}');
        // Re-issue each cancellation so every failure keeps a retry record
        // instead of leaving an untracked ghost notification.
        for (final entry in leftovers.entries) {
          await _cancelNow(entry.value, entry.key);
        }
      }
    });
  }

  @override
  Future<void> rescheduleAllFuture(List<Task> allTasks) async {
    if (!_initialized) {
      _queuedReschedule =
          allTasks.map((t) => Task.fromJson(t.toJson())).toList();
      return;
    }
    await _rescheduleReady(
      allTasks.map((t) => Task.fromJson(t.toJson())).toList(),
    );
  }

  Future<void> _rescheduleReady(List<Task> allTasks) async {
    final batch = _restoreGeneration;
    final revisions = Map<int, int>.from(_revision);
    bool current(String id, [String? sub]) {
      final key = generateNotificationId(id, subtaskId: sub);
      return (_revision[key] ?? 0) == (revisions[key] ?? 0);
    }

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    for (final t in allTasks) {
      if (batch != _restoreGeneration) return;
      if (t.completed) continue;
      if (current(t.id) && t.reminderAt != null && t.reminderAt! > nowMs) {
        await scheduleReminder(
          boardId: t.boardId,
          taskId: t.id,
          title: t.title,
          body: t.notesMarkdown,
          triggerAtMs: t.reminderAt!,
        );
      }
      for (final s in t.subtasks) {
        if (batch != _restoreGeneration) return;
        if (s.completed) continue;
        if (current(t.id, s.id) &&
            s.reminderAt != null &&
            s.reminderAt! > nowMs) {
          await scheduleReminder(
            boardId: t.boardId,
            taskId: t.id,
            subtaskId: s.id,
            title: s.title,
            body: t.notesMarkdown,
            triggerAtMs: s.reminderAt!,
          );
        }
      }
    }
  }
}
