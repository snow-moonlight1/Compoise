import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../models.dart';

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

/// Abstract cross-platform reminder service.
abstract class ReminderService {
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
    if (defaultTargetPlatform == TargetPlatform.android) {
      return FlutterLocalNotificationsReminderService();
    }
    return NoopReminderService();
  }

  @visibleForTesting
  static void resetForTest([ReminderService? testInstance]) {
    _instance = testInstance;
  }

  /// Initializes local notification service and binds notification tap handler.
  Future<void> init({
    required void Function(ReminderPayload payload) onNotificationSelected,
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
class NoopReminderService implements ReminderService {
  @override
  Future<void> init({
    required void Function(ReminderPayload payload) onNotificationSelected,
  }) async {}

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
class InMemoryReminderService implements ReminderService {
  final Map<int, ScheduledReminderRecord> scheduled = {};
  final List<int> cancelledIds = [];
  int cancelAllCount = 0;
  void Function(ReminderPayload payload)? _onNotificationSelected;

  void triggerNotificationTap(ReminderPayload payload) {
    _onNotificationSelected?.call(payload);
  }

  @override
  Future<void> init({
    required void Function(ReminderPayload payload) onNotificationSelected,
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

/// Production Android implementation using flutter_local_notifications.
class FlutterLocalNotificationsReminderService implements ReminderService {
  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;
  void Function(ReminderPayload payload)? _onNotificationSelected;

  FlutterLocalNotificationsReminderService({
    FlutterLocalNotificationsPlugin? plugin,
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  @override
  Future<void> init({
    required void Function(ReminderPayload payload) onNotificationSelected,
  }) async {
    _onNotificationSelected = onNotificationSelected;
    if (_initialized) return;

    try {
      tz.initializeTimeZones();
    } catch (_) {}

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const initSettings = InitializationSettings(android: androidSettings);

    try {
      await _plugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (response) {
          final raw = response.payload;
          final payload = ReminderPayload.deserialize(raw);
          if (payload != null) {
            _onNotificationSelected?.call(payload);
          }
        },
      );
      _initialized = true;
    } catch (e) {
      debugPrint('Failed to initialize local notifications: $e');
    }
  }

  @override
  Future<ReminderPermissionStatus> checkPermission() async {
    try {
      final androidImpl = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
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
      final androidImpl = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
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
    if (!_initialized) return;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    // Overdue suppression: discard if older than 5 minutes
    if (nowMs - triggerAtMs > 5 * 60 * 1000) {
      return;
    }

    final notifId = generateNotificationId(taskId, subtaskId: subtaskId);
    final payload = ReminderPayload(
      boardId: boardId,
      taskId: taskId,
      subtaskId: subtaskId,
    ).serialize();

    final androidDetails = AndroidNotificationDetails(
      'matrixflow_reminders',
      'MatrixFlow Reminders',
      channelDescription: 'Task and subtask deadline reminders',
      importance: Importance.max,
      priority: Priority.high,
      playSound: sound,
      enableVibration: vibrate,
    );
    final notifDetails = NotificationDetails(android: androidDetails);

    try {
      if (triggerAtMs <= nowMs) {
        // Immediate notification for near-past window (< 5m)
        await _plugin.show(
          notifId,
          title,
          body,
          notifDetails,
          payload: payload,
        );
      } else {
        final androidImpl = _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        final canExact =
            await androidImpl?.canScheduleExactNotifications() ?? true;
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
          // Fallback to inexact if exact schedule threw SecurityException
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
    } catch (e) {
      debugPrint('Error scheduling notification: $e');
    }
  }

  @override
  Future<void> cancelReminder(String taskId, {String? subtaskId}) async {
    if (!_initialized) return;
    final notifId = generateNotificationId(taskId, subtaskId: subtaskId);
    try {
      await _plugin.cancel(notifId);
    } catch (e) {
      debugPrint('Error canceling notification: $e');
    }
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
    if (!_initialized) return;
    try {
      await _plugin.cancelAll();
    } catch (e) {
      debugPrint('Error canceling all notifications: $e');
    }
  }

  @override
  Future<void> rescheduleAllFuture(List<Task> allTasks) async {
    if (!_initialized) return;
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
