import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
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
      current == ReminderPermissionStatus.unsupported) {
    return current;
  }
  await service.requestPermission();
  return service.checkPermission();
}

/// Abstract cross-platform reminder service.
abstract class ReminderService {
  final ValueNotifier<Map<int, ReminderPayload>> scheduleFailures =
      ValueNotifier({});

  void _setScheduleFailure(int id, ReminderPayload? payload) {
    final next = Map<int, ReminderPayload>.from(scheduleFailures.value);
    if (payload == null) {
      if (next.remove(id) == null) return;
    } else {
      next[id] = payload;
    }
    scheduleFailures.value = Map.unmodifiable(next);
  }

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

  /// Initializes local notification service and binds notification tap handler.
  Future<void> init({
    void Function(ReminderPayload payload)? onNotificationSelected,
  });

  /// Checks notification and alarm permissions status.
  Future<ReminderPermissionStatus> checkPermission();

  /// Requests runtime notification permission.
  Future<bool> requestPermission();

  /// Schedules a local notification reminder for a task or subtask.
  Future<void> scheduleReminder({
    required String boardId,
    required String taskId,
    String? subtaskId,
    required String title,
    String? body,
    required int triggerAtMs,
    bool sound = true,
    bool vibrate = true,
  });

  /// Cancels an existing scheduled reminder.
  Future<void> cancelReminder(String taskId, {String? subtaskId});

  /// Cancels all reminders for all tasks on a specific board.
  Future<void> cancelAllForBoard(String boardId, List<Task> tasksOnBoard);

  /// Cancels all scheduled reminders across the entire system.
  Future<void> cancelAll();

  /// Reschedules all future uncompleted reminders (e.g. after reboot or import).
  Future<void> rescheduleAllFuture(List<Task> allTasks);
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
  Future<ReminderPermissionStatus> checkPermission() async =>
      ReminderPermissionStatus.granted;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> scheduleReminder({
    required String boardId,
    required String taskId,
    String? subtaskId,
    required String title,
    String? body,
    required int triggerAtMs,
    bool sound = true,
    bool vibrate = true,
  }) async {}

  @override
  Future<void> cancelReminder(String taskId, {String? subtaskId}) async {}

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
  final Map<int, ScheduledReminderRecord> scheduled = {};
  final List<int> cancelledIds = [];
  int cancelAllCount = 0;
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
  Future<ReminderPermissionStatus> checkPermission() async =>
      ReminderPermissionStatus.granted;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> scheduleReminder({
    required String boardId,
    required String taskId,
    String? subtaskId,
    required String title,
    String? body,
    required int triggerAtMs,
    bool sound = true,
    bool vibrate = true,
  }) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    // Overdue suppression: discard if older than 5 minutes
    if (nowMs - triggerAtMs > 5 * 60 * 1000) {
      return;
    }

    final id = generateNotificationId(taskId, subtaskId: subtaskId);
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
  }

  @override
  Future<void> cancelReminder(String taskId, {String? subtaskId}) async {
    final id = generateNotificationId(taskId, subtaskId: subtaskId);
    scheduled.remove(id);
    cancelledIds.add(id);
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

  @visibleForTesting
  int get activeTimerCount => _activeTimers.length;

  @visibleForTesting
  String? lastScheduleError;

  @visibleForTesting
  void setInitializedForTest(bool val) {
    _initialized = val;
    _initCompleter ??= Completer<void>();
    if (val && !_initCompleter!.isCompleted) {
      _initCompleter!.complete();
    }
  }

  FlutterLocalNotificationsReminderService({
    FlutterLocalNotificationsPlugin? plugin,
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  int _bump(int notifId) => _revision[notifId] = (_revision[notifId] ?? 0) + 1;

  Future<void> _enqueue(Future<void> Function() op) {
    _chain = _chain.catchError((_) {}).then((_) => op());
    return _chain;
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

      await _plugin.initialize(
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
      _initialized = true;

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
        debugPrint('Failed to read notification launch details: $e');
      }

      final queued = _queuedReschedule;
      _queuedReschedule = null;
      if (queued != null) {
        await _rescheduleReady(queued);
      }
    } catch (e) {
      _initCompleter = null;
      debugPrint('Failed to initialize local notifications: $e');
    } finally {
      if (!gate.isCompleted) gate.complete();
    }
  }

  @override
  Future<ReminderPermissionStatus> checkPermission() async {
    try {
      if (defaultTargetPlatform == TargetPlatform.windows) {
        return ReminderPermissionStatus.granted;
      }
      final androidImpl =
          _plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >();
      if (androidImpl == null) return ReminderPermissionStatus.unsupported;

      final enabled = await androidImpl.areNotificationsEnabled() ?? false;
      if (!enabled) return ReminderPermissionStatus.denied;

      final canExact =
          await androidImpl.canScheduleExactNotifications() ?? false;
      if (!canExact) return ReminderPermissionStatus.inexactOnly;

      return ReminderPermissionStatus.granted;
    } catch (e) {
      debugPrint('Error checking notification permission: $e');
      return ReminderPermissionStatus.granted;
    }
  }

  @override
  Future<bool> requestPermission() async {
    try {
      if (defaultTargetPlatform == TargetPlatform.windows) {
        return true;
      }
      final androidImpl =
          _plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >();
      if (androidImpl == null) return false;

      final granted =
          await androidImpl.requestNotificationsPermission() ?? false;
      if (granted) {
        final canExact =
            await androidImpl.canScheduleExactNotifications() ?? true;
        if (!canExact) {
          try {
            await androidImpl.requestExactAlarmsPermission();
          } catch (_) {}
        }
      }
      return granted;
    } catch (e) {
      debugPrint('Error requesting notification permission: $e');
      return false;
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
  Future<void> scheduleReminder({
    required String boardId,
    required String taskId,
    String? subtaskId,
    required String title,
    String? body,
    required int triggerAtMs,
    bool sound = true,
    bool vibrate = true,
  }) {
    final notifId = generateNotificationId(taskId, subtaskId: subtaskId);
    final gen = _bump(notifId);
    _activeTimers[notifId]?.cancel();
    _activeTimers.remove(notifId);
    return _enqueue(() async {
      if (_revision[notifId] != gen) return;
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      if (nowMs - triggerAtMs > 5 * 60 * 1000) return;
      if (!_initialized) {
        _setScheduleFailure(
          notifId,
          ReminderPayload(
            boardId: boardId,
            taskId: taskId,
            subtaskId: subtaskId,
          ),
        );
        return;
      }
      if (_revision[notifId] != gen) return;

      final payload =
          ReminderPayload(
            boardId: boardId,
            taskId: taskId,
            subtaskId: subtaskId,
          ).serialize();
      final notifDetails = _details(body: body, sound: sound, vibrate: vibrate);

      var scheduled = false;
      try {
        if (triggerAtMs <= nowMs) {
          await _plugin.show(
            notifId,
            title,
            body,
            notifDetails,
            payload: payload,
          );
          scheduled = true;
          return;
        }
        if (defaultTargetPlatform == TargetPlatform.windows) {
          scheduled = await _scheduleWindows(
            notifId: notifId,
            gen: gen,
            title: title,
            body: body,
            triggerAtMs: triggerAtMs,
            notifDetails: notifDetails,
            payload: payload,
          );
          return;
        }
        await _scheduleAndroid(
          notifId: notifId,
          gen: gen,
          title: title,
          body: body,
          triggerAtMs: triggerAtMs,
          notifDetails: notifDetails,
          payload: payload,
        );
        scheduled = true;
      } catch (e) {
        lastScheduleError = e.toString();
        if (_revision[notifId] == gen) {
          _setScheduleFailure(
            notifId,
            ReminderPayload(
              boardId: boardId,
              taskId: taskId,
              subtaskId: subtaskId,
            ),
          );
        }
        debugPrint('Error scheduling notification: $e');
      } finally {
        if (scheduled && _revision[notifId] == gen) {
          _setScheduleFailure(notifId, null);
          lastScheduleError = null;
        }
        // A cancel can finish while the OS is still accepting this request.
        // Compensate before allowing the next queued schedule to start.
        if (_revision[notifId] != gen) {
          try {
            await _plugin.cancel(notifId);
          } catch (e) {
            debugPrint('Error cleaning up superseded notification: $e');
          }
        }
      }
    });
  }

  Future<bool> _scheduleWindows({
    required int notifId,
    required int gen,
    required String title,
    String? body,
    required int triggerAtMs,
    required NotificationDetails notifDetails,
    required String payload,
  }) async {
    var nativeOk = false;
    try {
      final scheduledDate = tz.TZDateTime.fromMillisecondsSinceEpoch(
        tz.local,
        triggerAtMs,
      );
      if (_revision[notifId] != gen) return false;
      await _plugin.zonedSchedule(
        notifId,
        title,
        body,
        scheduledDate,
        notifDetails,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: payload,
      );
      nativeOk = true;
    } catch (e) {
      if (_revision[notifId] == gen) {
        _setScheduleFailure(notifId, ReminderPayload.deserialize(payload));
      }
      debugPrint('Native Windows schedule unavailable: $e');
    }
    if (nativeOk || _revision[notifId] != gen) return nativeOk;
    final delayMs = triggerAtMs - DateTime.now().millisecondsSinceEpoch;
    if (delayMs <= 0) return false;
    _activeTimers[notifId] = Timer(Duration(milliseconds: delayMs), () async {
      _activeTimers.remove(notifId);
      if (_revision[notifId] != gen) return;
      try {
        await _plugin.show(
          notifId,
          title,
          body,
          notifDetails,
          payload: payload,
        );
      } catch (e) {
        debugPrint('Error showing scheduled Windows notification: $e');
      }
    });
    return false;
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
      } catch (second) {
        rethrow;
      }
    }
  }

  @override
  Future<void> cancelReminder(String taskId, {String? subtaskId}) {
    final notifId = generateNotificationId(taskId, subtaskId: subtaskId);
    _bump(notifId);
    _setScheduleFailure(notifId, null);
    _activeTimers[notifId]?.cancel();
    _activeTimers.remove(notifId);
    return _enqueue(() async {
      if (!_initialized) return;
      try {
        await _plugin.cancel(notifId);
      } catch (e) {
        debugPrint('Error canceling notification: $e');
      }
    });
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
    scheduleFailures.value = {};
    for (final id in _revision.keys.toList()) {
      _bump(id);
    }
    for (final timer in _activeTimers.values) {
      timer.cancel();
    }
    _activeTimers.clear();
    _queuedReschedule = null;
    return _enqueue(() async {
      if (!_initialized) return;
      try {
        await _plugin.cancelAll();
      } catch (e) {
        debugPrint('Error canceling all notifications: $e');
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
