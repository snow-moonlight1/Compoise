/// Central app store: all state, persistence (same localStorage keys as the web
/// app), CRUD operations and the deadline auto-promotion loop.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ai_service.dart';
import 'credential_store.dart';
import 'deadline_policy.dart';
import 'l10n.dart';
import 'import_preflight.dart';
import 'models.dart';
import 'save_protocol.dart';
import 'services/reminder_service.dart';
import 'task_commands.dart';

export 'data_migrations.dart';
export 'credential_store.dart';
export 'deadline_policy.dart';
export 'import_preflight.dart';
export 'save_protocol.dart';
export 'services/reminder_service.dart';
export 'task_commands.dart';

enum StartupDataState { missing, valid, migrated, corrupt }

class Store extends ChangeNotifier with WidgetsBindingObserver {
  static const _kTasks = 'matrixflow-tasks';
  static const _kBoards = 'matrixflow-boards';
  static const _kConfig = 'matrixflow-config';
  static const _kSettings = 'matrixflow-settings';
  static const _kActiveBoard = 'matrixflow-active-board';
  static const _kHasSeenOnboarding = 'matrixflow-has-seen-onboarding';

  final AIService ai;
  final CredentialStore credentialStore;
  static CredentialStore? testCredentialStore;
  String _confirmedCredential = '';
  String? _pendingCredentialValue;
  String? _pendingCredentialRollback;
  String? _legacyCredentialForMigration;
  Future<void> _credentialWrites = Future.value();
  String? credentialError;
  bool _credentialMigrationPending = false;
  late SharedPreferences _prefs;
  SaveProtocol? _saveProtocol;
  Map<String, String>? _savedValues;
  final SaveWrite? saveWriter;

  bool ready = false;
  bool _disposed = false;
  bool hasSeenOnboarding = false;
  String? startupError;
  String? persistenceError;
  Future<void> _pendingWrites = Future.value();
  bool _saveScheduled = false;
  int _dirtyRevision = 0;
  int _savedRevision = 0;
  SaveResult lastSaveResult = const SaveResult(true, 0);
  List<Board> boards = [];
  List<Task> tasks = [];
  String activeBoardId = '';
  AIConfig aiConfig = AIConfig();
  AppSettings settings = AppSettings();
  String? corruptNotice; // set when a persisted blob failed to parse
  final Map<String, StartupDataState> startupDataStates = {};
  final Set<String> _protectedStartupKeys = {};
  bool get hasStartupRecovery => _protectedStartupKeys.isNotEmpty;
  List<String> get recoveryKeys => List.unmodifiable(_protectedStartupKeys);

  Map<String, String> get t => dictOf(settings.language);

  Timer? _deadlineTimer;

  final List<Locale>? initialDeviceLocales;

  Store({
    AIService? aiService,
    List<Locale>? deviceLocales,
    this.saveWriter,
    CredentialStore? credentialStore,
  }) : ai = aiService ?? AIService(),
       credentialStore =
           credentialStore ??
           testCredentialStore ??
           const SystemCredentialStore(),
       initialDeviceLocales = deviceLocales;

  Future<void> retryReminder(ReminderPayload payload) async {
    final service = ReminderService.instance;
    await service.init();
    if (_disposed) return;
    final task = tasks.where((t) => t.id == payload.taskId).firstOrNull;
    final sub =
        task?.subtasks.where((s) => s.id == payload.subtaskId).firstOrNull;
    final when = payload.subtaskId == null ? task?.reminderAt : sub?.reminderAt;
    if (task == null ||
        task.completed ||
        (payload.subtaskId != null && (sub == null || sub.completed)) ||
        when == null) {
      await service.cancelReminder(
        payload.taskId,
        subtaskId: payload.subtaskId,
      );
      return;
    }
    await service.scheduleReminder(
      boardId: task.boardId,
      taskId: task.id,
      subtaskId: payload.subtaskId,
      title: sub?.title ?? task.title,
      body: sub?.notesMarkdown ?? task.notesMarkdown,
      triggerAtMs: when,
    );
  }

  Future<void> init({List<Locale>? deviceLocales}) async {
    startupError = null;
    startupDataStates.clear();
    _protectedStartupKeys.clear();
    corruptNotice = null;
    final resolvedDeviceLang = resolveDeviceLanguage(
      deviceLocales ?? initialDeviceLocales ?? _resolvePlatformLocales(),
    );
    try {
      _prefs = await SharedPreferences.getInstance();
    } catch (_) {
      if (_disposed) return;
      settings = AppSettings(language: resolvedDeviceLang);
      startupError = t['storageReadError'];
      notifyListeners();
      return;
    }
    if (_disposed) return;
    _saveProtocol = SaveProtocol(_prefs, writer: saveWriter);
    try {
      _savedValues = _saveProtocol!.load()?.values;
    } catch (_) {
      _protectedStartupKeys.add(SaveProtocol.pointerKey);
      startupDataStates[SaveProtocol.pointerKey] = StartupDataState.corrupt;
      _savedValues = null;
    }
    var corrupted = 0;

    void mark(String key, StartupDataState state) {
      startupDataStates[key] = state;
      if (state == StartupDataState.corrupt) _protectedStartupKeys.add(key);
    }

    T read<T>(
      String key,
      T fallback,
      T Function(dynamic) parse,
      Object? Function(T) serialize,
    ) {
      final present = _savedValues?.containsKey(key) ?? _prefs.containsKey(key);
      final raw = _loadJson(key);
      if (raw == null && !present) {
        mark(key, StartupDataState.missing);
        return fallback;
      }
      try {
        final previousErrors = corrupted;
        final value = parse(raw);
        mark(
          key,
          corrupted > previousErrors
              ? StartupDataState.corrupt
              : jsonEncode(raw) == jsonEncode(serialize(value))
              ? StartupDataState.valid
              : StartupDataState.migrated,
        );
        return value;
      } catch (_) {
        corrupted++;
        mark(key, StartupDataState.corrupt);
        return fallback;
      }
    }

    List<T> records<T>(
      dynamic raw,
      T Function(Map<String, dynamic>) parse,
      String Function(T) id,
    ) {
      if (raw is! List) throw const FormatException('Invalid list');
      final result = <T>[];
      final seen = <String>{};
      for (final item in raw) {
        try {
          final record = parse(item as Map<String, dynamic>);
          if (seen.add(id(record))) {
            result.add(record);
          } else {
            corrupted++;
          }
        } catch (_) {
          corrupted++;
        }
      }
      return result;
    }

    aiConfig = read(
      _kConfig,
      AIConfig(),
      (raw) => AIConfig.fromJson(raw as Map<String, dynamic>),
      (value) => value.toJson(),
    );
    settings = read(
      _kSettings,
      AppSettings(language: resolvedDeviceLang),
      (raw) => AppSettings.fromJson(
        raw as Map<String, dynamic>,
        defaultLanguage: resolvedDeviceLang,
      ),
      (value) => value.toJson(),
    );
    boards = read(
      _kBoards,
      <Board>[],
      (raw) => records(raw, Board.fromJson, (b) => b.id),
      (value) => value.map((b) => b.toJson()).toList(),
    );
    tasks = read(
      _kTasks,
      <Task>[],
      (raw) => records(raw, Task.fromJson, (task) => task.id),
      (value) => value.map((task) => task.toJson()).toList(),
    );

    if (boards.isEmpty) {
      if (startupDataStates[_kBoards] == StartupDataState.valid) {
        startupDataStates[_kBoards] = StartupDataState.migrated;
      }
      boards = [
        Board(id: newId(), name: t['defaultBoardName']!, createdAt: _now()),
      ];
    }
    final validIds = boards.map((b) => b.id).toSet();
    for (final task in tasks) {
      if (!validIds.contains(task.boardId)) {
        if (startupDataStates[_kTasks] == StartupDataState.valid) {
          startupDataStates[_kTasks] = StartupDataState.migrated;
        }
        task.boardId = boards.first.id;
      }
    }
    final savedActive =
        _savedValues?[_kActiveBoard] ?? _prefs.get(_kActiveBoard);
    mark(
      _kActiveBoard,
      savedActive == null
          ? StartupDataState.missing
          : savedActive is String
          ? StartupDataState.valid
          : StartupDataState.corrupt,
    );
    activeBoardId = savedActive is String ? savedActive : '';
    if (!boards.any((b) => b.id == activeBoardId)) {
      if (startupDataStates[_kActiveBoard] == StartupDataState.valid) {
        startupDataStates[_kActiveBoard] = StartupDataState.migrated;
      }
      activeBoardId = boards.first.id;
    }
    final onboardingRaw = _savedValues?[_kHasSeenOnboarding];
    final onboarding =
        onboardingRaw == null
            ? _prefs.get(_kHasSeenOnboarding)
            : onboardingRaw == 'true'
            ? true
            : onboardingRaw == 'false'
            ? false
            : onboardingRaw;
    mark(
      _kHasSeenOnboarding,
      onboarding == null
          ? StartupDataState.missing
          : onboarding is bool
          ? StartupDataState.valid
          : StartupDataState.corrupt,
    );
    hasSeenOnboarding = onboarding is bool ? onboarding : false;
    if (hasStartupRecovery) corruptNotice = t['corruptData'];

    ready = true;
    if (hasStartupRecovery) {
      // Keep every original key untouched until the user explicitly resolves
      // the recovery state. Even a valid sibling key may depend on bad boards.
      notifyListeners();
      return;
    }
    if (!await retryCredentialMigration()) {
      notifyListeners();
      return;
    }
    _persistAll();
    _applyDeadlinePromotion();
    ReminderService.instance.rescheduleAllFuture(tasks);
    notifyListeners();

    _deadlineTimer = Timer.periodic(
      const Duration(hours: 1),
      (_) => _applyDeadlinePromotion(),
    );
    WidgetsBinding.instance.addObserver(this);
  }

  /// Recovery-only copy of all original values, including possible credentials.
  /// Never display or log this string. It is not an importable ExportData file.
  String recoveryCopyJson() {
    if (!hasStartupRecovery) throw StateError('No startup recovery pending');
    return jsonEncode({
      'format': 'matrixflow-startup-recovery-v1',
      'entries': [
        for (final key in [
          _kTasks,
          _kBoards,
          _kConfig,
          _kSettings,
          _kActiveBoard,
          _kHasSeenOnboarding,
          SaveProtocol.pointerKey,
          'matrixflow-save-a',
          'matrixflow-save-b',
        ])
          if (_prefs.containsKey(key)) {'key': key, 'value': _prefs.get(key)},
      ],
    });
  }

  /// Called only after an explicit recovery decision in the UI.
  Future<bool> discardDamagedStartupData() async {
    if (!hasStartupRecovery) return false;
    for (final key in _protectedStartupKeys) {
      if (!await _prefs.remove(key)) return false;
    }
    _saveProtocol = SaveProtocol(_prefs, writer: saveWriter);
    for (final key in _protectedStartupKeys) {
      startupDataStates[key] = StartupDataState.missing;
    }
    _protectedStartupKeys.clear();
    corruptNotice = null;
    final validIds = boards.map((board) => board.id).toSet();
    for (final task in tasks) {
      if (!validIds.contains(task.boardId)) task.boardId = boards.first.id;
    }
    if (!await retryCredentialMigration()) {
      notifyListeners();
      return false;
    }
    _persistAll();
    _applyDeadlinePromotion();
    ReminderService.instance.rescheduleAllFuture(tasks);
    _deadlineTimer = Timer.periodic(
      const Duration(hours: 1),
      (_) => _applyDeadlinePromotion(),
    );
    WidgetsBinding.instance.addObserver(this);
    notifyListeners();
    return true;
  }

  @override
  void dispose() {
    _disposed = true;
    _deadlineTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    ai.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && ready && !_disposed) {
      _applyDeadlinePromotion();
      notifyListeners(); // refresh calendar badges after midnight
    }
  }

  // --- derived ---

  Board? get activeBoard =>
      boards.where((b) => b.id == activeBoardId).firstOrNull;

  List<Task> get visibleTasks {
    final list =
        tasks
            .where((task) => task.boardId == activeBoardId)
            .where((task) => !settings.hideCompleted || !task.completed)
            .toList();
    return list;
  }

  List<Task> tasksIn(int quadrant) =>
      visibleTasks.where((task) => task.quadrant == quadrant).toList();

  List<Task> longTermPending() =>
      visibleTasks
          .where(
            (task) => task.isLongTerm && !task.hasSubtasks && !task.completed,
          )
          .toList();

  /// Direct query for completed tasks without copying or synthetic timestamps.
  /// If [boardId] is specified, returns completed tasks on that board;
  /// otherwise returns completed tasks across all boards.
  /// Unaffected by [settings.hideCompleted].
  List<Task> completedTasks({String? boardId}) =>
      tasks
          .where(
            (t) => t.completed && (boardId == null || t.boardId == boardId),
          )
          .toList();

  /// Total number of completed tasks on [boardId] (or across all boards if null).
  int completedTaskCount({String? boardId}) =>
      tasks
          .where(
            (t) => t.completed && (boardId == null || t.boardId == boardId),
          )
          .length;

  // --- mutations ---

  void setViewMode(ViewMode mode) {
    if (settings.viewMode == mode) return;
    updateSettings((s) => s..viewMode = mode);
  }

  void toggleViewMode() {
    final next =
        settings.viewMode == ViewMode.grid ? ViewMode.list : ViewMode.grid;
    setViewMode(next);
  }

  void setFontSize(FontSizePref size) {
    if (settings.fontSize == size) return;
    updateSettings((s) => s..fontSize = size);
  }

  void setFontFamily(FontFamilyPref family) {
    if (settings.fontFamily == family) return;
    updateSettings((s) => s..fontFamily = family);
  }

  void resetDisplayPreferences() {
    updateSettings(
      (s) =>
          s
            ..fontSize = FontSizePref.standard
            ..fontFamily = FontFamilyPref.system
            ..viewMode = ViewMode.grid,
    );
  }

  void completeOnboarding() {
    hasSeenOnboarding = true;
    _write(_kHasSeenOnboarding, 'true');
    notifyListeners();
  }

  void resetOnboardingForTest() {
    hasSeenOnboarding = false;
    _write(_kHasSeenOnboarding, 'false');
    notifyListeners();
  }

  void setActiveBoard(String id) {
    if (!boards.any((b) => b.id == id)) return;
    activeBoardId = id;
    _saveBoardsMeta();
    notifyListeners();
  }

  void addTasks(List<Task> newTasks) {
    final seen = tasks.map((task) => task.id).toSet();
    final boardIds = boards.map((board) => board.id).toSet();
    final added =
        newTasks
            .where(
              (task) => boardIds.contains(task.boardId) && seen.add(task.id),
            )
            .toList();
    tasks.insertAll(0, added);
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final task in added) {
      if (!task.completed &&
          task.reminderAt != null &&
          task.reminderAt! > now) {
        ReminderService.instance.scheduleReminder(
          boardId: task.boardId,
          taskId: task.id,
          title: task.title,
          body: task.notesMarkdown,
          triggerAtMs: task.reminderAt!,
        );
      }
      for (final sub in task.subtasks) {
        if (!sub.completed && sub.reminderAt != null && sub.reminderAt! > now) {
          ReminderService.instance.scheduleReminder(
            boardId: task.boardId,
            taskId: task.id,
            subtaskId: sub.id,
            title: sub.title,
            body: task.title,
            triggerAtMs: sub.reminderAt!,
          );
        }
      }
    }
    _applyDeadlinePromotion();
    _saveTasks();
    notifyListeners();
  }

  Task newTask(
    String title, {
    int quadrant = qDo,
    bool isLongTerm = false,
    int? deadline,
  }) => Task(
    id: newId(),
    boardId: activeBoardId,
    title: title,
    quadrant: quadrant,
    isLongTerm: isLongTerm,
    createdAt: _now(),
    deadline: deadline,
  );

  void _insertAtFrontOfQuadrant(Task task) {
    final firstTargetIndex = tasks.indexWhere(
      (t) => t.boardId == task.boardId && t.quadrant == task.quadrant,
    );
    if (firstTargetIndex != -1) {
      tasks.insert(firstTargetIndex, task);
    } else {
      final firstBoardIndex = tasks.indexWhere(
        (t) => t.boardId == task.boardId,
      );
      if (firstBoardIndex != -1) {
        tasks.insert(firstBoardIndex, task);
      } else {
        tasks.insert(0, task);
      }
    }
  }

  void _copyTaskFields(Task from, Task to) {
    to.boardId = from.boardId;
    to.title = from.title;
    to.quadrant = from.quadrant;
    to.isLongTerm = from.isLongTerm;
    to.completed = from.completed;
    to.createdAt = from.createdAt;
    to.deadline = from.deadline;
    to.subtasks = from.subtasks;
    to.reasoning = from.reasoning;
    to.urgencyMode = from.urgencyMode;
    to.notesMarkdown = from.notesMarkdown;
    to.reminderAt = from.reminderAt;
    to.reminderTimezone = from.reminderTimezone;
    to.completedAt = from.completedAt;
  }

  void updateTask(Task updated) {
    final i = tasks.indexWhere((t) => t.id == updated.id);
    if (i == -1) return;
    _touchTask(updated.id);
    final live = tasks[i];
    final oldTask = Task.fromJson(live.toJson());
    if (!identical(updated, live)) {
      _copyTaskFields(updated, live);
      updated = live;
    }
    final oldQuadrant = oldTask.quadrant;
    final quadrantChanged = oldQuadrant != updated.quadrant;

    if (quadrantChanged &&
        isUrgentQuadrant(oldQuadrant) != isUrgentQuadrant(updated.quadrant) &&
        oldTask.urgencyMode == updated.urgencyMode) {
      updated.urgencyMode = UrgencyMode.manual;
    }

    final now = DateTime.now().millisecondsSinceEpoch;

    // Preserve or set completedAt for subtasks
    final oldSubMap = {for (final s in oldTask.subtasks) s.id: s};
    for (final sub in updated.subtasks) {
      final oldSub = oldSubMap[sub.id];
      if (sub.completed) {
        if (oldSub == null || !oldSub.completed) {
          sub.completedAt ??= now;
        } else {
          sub.completedAt ??= oldSub.completedAt;
        }
      } else {
        sub.completedAt = null;
      }
    }

    if (settings.autoCompleteParent && updated.subtasks.isNotEmpty) {
      final allDone = updated.subtasks.every((s) => s.completed);
      if (allDone) {
        if (!updated.completed) {
          updated.completed = true;
          updated.completedAt = now;
        }
      }
      if (updated.completed && updated.subtasks.any((s) => !s.completed)) {
        updated.completed = false;
        updated.completedAt = null;
      }
    }

    // Preserve or set completedAt for parent task
    if (updated.completed) {
      if (!oldTask.completed) {
        updated.completedAt ??= now;
      } else {
        updated.completedAt ??= oldTask.completedAt;
      }
    } else {
      updated.completedAt = null;
    }

    if (quadrantChanged) {
      tasks.removeAt(i);
      _insertAtFrontOfQuadrant(updated);
    } else {
      tasks[i] = updated;
    }

    final oldSubIds = {for (final s in oldTask.subtasks) s.id};
    final newSubIds = {for (final s in updated.subtasks) s.id};
    for (final removedId in oldSubIds.difference(newSubIds)) {
      ReminderService.instance.cancelReminder(updated.id, subtaskId: removedId);
    }

    if (updated.completed) {
      ReminderService.instance.cancelReminder(updated.id);
      for (final sub in updated.subtasks) {
        ReminderService.instance.cancelReminder(updated.id, subtaskId: sub.id);
      }
    } else {
      if (updated.reminderAt != null && updated.reminderAt! > now) {
        ReminderService.instance.scheduleReminder(
          boardId: updated.boardId,
          taskId: updated.id,
          title: updated.title,
          body: updated.notesMarkdown,
          triggerAtMs: updated.reminderAt!,
        );
      } else {
        ReminderService.instance.cancelReminder(updated.id);
      }
      for (final sub in updated.subtasks) {
        if (!sub.completed && sub.reminderAt != null && sub.reminderAt! > now) {
          ReminderService.instance.scheduleReminder(
            boardId: updated.boardId,
            taskId: updated.id,
            subtaskId: sub.id,
            title: sub.title,
            body: updated.title,
            triggerAtMs: sub.reminderAt!,
          );
        } else {
          ReminderService.instance.cancelReminder(
            updated.id,
            subtaskId: sub.id,
          );
        }
      }
    }

    _applyDeadlinePromotion();
    _saveTasks();
    notifyListeners();
  }

  void deleteTask(String id) {
    _touchTask(id);
    final existing = tasks.where((t) => t.id == id).firstOrNull;
    if (existing != null) {
      ReminderService.instance.cancelReminder(existing.id);
      for (final s in existing.subtasks) {
        ReminderService.instance.cancelReminder(existing.id, subtaskId: s.id);
      }
    }
    tasks.removeWhere((t) => t.id == id);
    _saveTasks();
    notifyListeners();
  }

  void moveTask(String id, int quadrant) {
    final i = tasks.indexWhere((t) => t.id == id);
    if (i == -1) return;
    if (tasks[i].quadrant == quadrant) {
      // Same quadrant: do not reorder
      return;
    }
    final oldQuadrant = tasks[i].quadrant;
    final task = Task.fromJson(tasks[i].toJson())..quadrant = quadrant;
    if (isUrgentQuadrant(oldQuadrant) != isUrgentQuadrant(quadrant)) {
      task.urgencyMode = UrgencyMode.manual;
    }
    tasks.removeAt(i);
    _insertAtFrontOfQuadrant(task);
    _saveTasks();
    notifyListeners();
  }

  void resetTaskUrgencyMode(String taskId) {
    final i = tasks.indexWhere((t) => t.id == taskId);
    if (i == -1) return;
    tasks[i].urgencyMode = UrgencyMode.auto;
    _applyDeadlinePromotion();
    _saveTasks();
    notifyListeners();
  }

  void appendSubtasks(String taskId, List<SubTask> subs) {
    final i = tasks.indexWhere((t) => t.id == taskId);
    if (i == -1) return;
    final updated = Task.fromJson(tasks[i].toJson())..subtasks.addAll(subs);
    updateTask(updated);
  }

  final Map<String, int> _taskSeq = {};
  int taskSeq(String id) => _taskSeq[id] ?? 0;
  void _touchTask(String id) => _taskSeq[id] = taskSeq(id) + 1;
  void _touchCommand() {
    // Board-wide mutations bump every known task so stale undos cannot revive them.
    for (final task in tasks) {
      _touchTask(task.id);
    }
  }

  final Map<String, int> _boardEpoch = {};

  /// Returns the current mutation generation/epoch for the given board.
  int boardEpoch(String boardId) => _boardEpoch[boardId] ?? 0;

  /// Explicitly bumps the mutation generation/epoch for [boardId].
  void bumpBoardEpoch(String boardId) {
    _boardEpoch[boardId] = boardEpoch(boardId) + 1;
  }

  /// Explicitly bumps the mutation generation/epoch for all known boards.
  void bumpAllBoardEpochs() {
    for (final b in boards) {
      bumpBoardEpoch(b.id);
    }
  }

  /// Returns the total number of tasks (across all quadrants, completed or not) for [boardId].
  int boardTaskCount(String boardId) =>
      tasks.where((t) => t.boardId == boardId).length;

  /// Atomically removes all tasks on [boardId] across all four quadrants,
  /// including completed and hidden tasks. Bumps [boardEpoch] to invalidate
  /// in-flight async results and undo snapshots. Returns the number of removed tasks.
  int clearBoard(String boardId) {
    bumpBoardEpoch(boardId);
    final boardTasks = tasks.where((t) => t.boardId == boardId).toList();
    ReminderService.instance.cancelAllForBoard(boardId, boardTasks);
    final before = tasks.length;
    tasks.removeWhere((t) => t.boardId == boardId);
    final removed = before - tasks.length;
    if (removed > 0) {
      _saveTasks();
      notifyListeners();
    }
    return removed;
  }

  void clearQuadrant(int quadrant, {String? boardId}) {
    final bId = boardId ?? activeBoardId;
    bumpBoardEpoch(bId);
    final quadTasks =
        tasks.where((t) => t.boardId == bId && t.quadrant == quadrant).toList();
    ReminderService.instance.cancelAllForBoard(bId, quadTasks);
    tasks.removeWhere((t) => t.boardId == bId && t.quadrant == quadrant);
    _saveTasks();
    notifyListeners();
  }

  /// Parent checkbox cascade: set self + every subtask to [completed].
  void setParentCompleted(Task task, bool completed) {
    final stored = tasks.where((t) => t.id == task.id).firstOrNull ?? task;
    final now = DateTime.now().millisecondsSinceEpoch;
    final wasCompleted = stored.completed;
    final previousAt = stored.completedAt;
    final subWas =
        stored.subtasks.map((s) => (s.completed, s.completedAt)).toList();
    stored.completed = completed;
    stored.completedAt = completed ? (wasCompleted ? previousAt : now) : null;
    for (var i = 0; i < stored.subtasks.length; i++) {
      final s = stored.subtasks[i];
      final (wasSub, subAt) = subWas[i];
      s.completed = completed;
      s.completedAt = completed ? (wasSub ? subAt : now) : null;
    }
    if (!identical(task, stored)) {
      task.completed = stored.completed;
      task.completedAt = stored.completedAt;
      for (
        var i = 0;
        i < task.subtasks.length && i < stored.subtasks.length;
        i++
      ) {
        task.subtasks[i].completed = stored.subtasks[i].completed;
        task.subtasks[i].completedAt = stored.subtasks[i].completedAt;
      }
    }
    updateTask(stored);
  }

  void setSubtaskCompleted(String taskId, String subtaskId, bool completed) {
    final i = tasks.indexWhere((t) => t.id == taskId);
    if (i == -1) return;
    final stored = tasks[i];
    final sub = stored.subtasks.where((s) => s.id == subtaskId).firstOrNull;
    if (sub == null) return;
    final wasCompleted = sub.completed;
    final previousAt = sub.completedAt;
    sub.completed = completed;
    if (completed) {
      sub.completedAt =
          wasCompleted ? previousAt : DateTime.now().millisecondsSinceEpoch;
    } else {
      sub.completedAt = null;
    }
    updateTask(stored);
  }

  /// Restores a completed task back to active state.
  /// Uses existing parent-child cascade rule ([setParentCompleted]) so all subtasks
  /// are reset to incomplete as well, preventing [autoCompleteParent] from immediately
  /// marking the parent task as completed again.
  void restoreTask(Task task) {
    setParentCompleted(task, false);
  }

  /// Restores a completed task by ID.
  void restoreTaskById(String id) {
    final task = tasks.where((t) => t.id == id).firstOrNull;
    if (task != null) {
      restoreTask(task);
    }
  }

  /// Deletes a task by ID and returns a [TaskUndoSnapshot] capturing its state
  /// for a 5-second undo window. Immediately persists deletion.
  TaskUndoSnapshot? deleteTaskWithUndo(String id) {
    final i = tasks.indexWhere((t) => t.id == id);
    if (i == -1) return null;
    final task = tasks[i];
    ReminderService.instance.cancelReminder(task.id);
    for (final s in task.subtasks) {
      ReminderService.instance.cancelReminder(task.id, subtaskId: s.id);
    }
    _touchTask(task.id);
    final snapshot = TaskUndoSnapshot.capture(
      actionType: TaskUndoType.delete,
      task: task,
      boardEpoch: boardEpoch(task.boardId),
      originalIndex: i,
      commandSeq: taskSeq(task.id),
    );
    tasks.removeAt(i);
    _saveTasks();
    notifyListeners();
    return snapshot;
  }

  /// Toggles task completion state (cascading to all subtasks via [setParentCompleted])
  /// and returns a [TaskUndoSnapshot] capturing the previous state for undo.
  TaskUndoSnapshot? toggleCompleteWithUndo(Task task) {
    final i = tasks.indexWhere((t) => t.id == task.id);
    if (i == -1) return null;
    final current = tasks[i];
    final nextState = !current.completed;
    final before = Task.fromJson(current.toJson());
    setParentCompleted(current, nextState);
    return TaskUndoSnapshot.capture(
      actionType: nextState ? TaskUndoType.complete : TaskUndoType.restore,
      task: before,
      boardEpoch: boardEpoch(before.boardId),
      originalIndex: i,
      commandSeq: taskSeq(before.id),
    );
  }

  /// Checks if [snapshot] is still valid according to the invalidation contract:
  /// 1. Target board must exist.
  /// 2. Board epoch must match snapshot.boardEpoch (invalidated if clearBoard, clearQuadrant,
  ///    or overwrite import occurred).
  /// 3. For complete/restore: task must still exist and must not have been modified
  ///    by subsequent commands (e.g. title or quadrant changed).
  /// 4. For delete: task must not already exist.
  bool canApplyUndo(TaskUndoSnapshot snapshot) {
    if (!boards.any((b) => b.id == snapshot.boardId)) {
      return false;
    }
    if (boardEpoch(snapshot.boardId) != snapshot.boardEpoch) {
      return false;
    }
    if (snapshot.commandSeq != 0 &&
        snapshot.commandSeq != taskSeq(snapshot.taskId)) {
      return false;
    }
    if (snapshot.actionType == TaskUndoType.complete ||
        snapshot.actionType == TaskUndoType.restore) {
      final current = tasks.where((t) => t.id == snapshot.taskId).firstOrNull;
      if (current == null) return false;
      if (current.title != snapshot.task.title ||
          current.quadrant != snapshot.task.quadrant) {
        return false;
      }
    } else if (snapshot.actionType == TaskUndoType.delete) {
      if (tasks.any((t) => t.id == snapshot.taskId)) {
        return false;
      }
    }
    return true;
  }

  /// Reverses the mutation represented by [snapshot] if valid.
  /// Returns true on success, or false if rejected due to conflict or epoch invalidation.
  bool applyUndo(TaskUndoSnapshot snapshot) {
    if (!canApplyUndo(snapshot)) {
      return false;
    }

    switch (snapshot.actionType) {
      case TaskUndoType.delete:
        final restored = Task.fromJson(snapshot.task.toJson());
        final insertIndex = snapshot.originalIndex.clamp(0, tasks.length);
        tasks.insert(insertIndex, restored);
        final now = DateTime.now().millisecondsSinceEpoch;
        if (!restored.completed &&
            restored.reminderAt != null &&
            restored.reminderAt! > now) {
          ReminderService.instance.scheduleReminder(
            boardId: restored.boardId,
            taskId: restored.id,
            title: restored.title,
            body: restored.notesMarkdown,
            triggerAtMs: restored.reminderAt!,
          );
        }
        for (final sub in restored.subtasks) {
          if (!sub.completed &&
              sub.reminderAt != null &&
              sub.reminderAt! > now) {
            ReminderService.instance.scheduleReminder(
              boardId: restored.boardId,
              taskId: restored.id,
              subtaskId: sub.id,
              title: sub.title,
              body: restored.title,
              triggerAtMs: sub.reminderAt!,
            );
          }
        }
        _applyDeadlinePromotion();
        _saveTasks();
        notifyListeners();
        return true;

      case TaskUndoType.complete:
      case TaskUndoType.restore:
        final i = tasks.indexWhere((t) => t.id == snapshot.taskId);
        if (i == -1) return false;
        final current = tasks[i];
        current.completed = snapshot.task.completed;
        current.completedAt = snapshot.task.completedAt;
        final subMap = {for (final s in snapshot.task.subtasks) s.id: s};
        for (final sub in current.subtasks) {
          if (subMap.containsKey(sub.id)) {
            final oldSub = subMap[sub.id]!;
            sub.completed = oldSub.completed;
            sub.completedAt = oldSub.completedAt;
          }
        }
        final now = DateTime.now().millisecondsSinceEpoch;
        if (current.completed) {
          ReminderService.instance.cancelReminder(current.id);
          for (final sub in current.subtasks) {
            ReminderService.instance.cancelReminder(
              current.id,
              subtaskId: sub.id,
            );
          }
        } else {
          if (current.reminderAt != null && current.reminderAt! > now) {
            ReminderService.instance.scheduleReminder(
              boardId: current.boardId,
              taskId: current.id,
              title: current.title,
              body: current.notesMarkdown,
              triggerAtMs: current.reminderAt!,
            );
          } else {
            ReminderService.instance.cancelReminder(current.id);
          }
          for (final sub in current.subtasks) {
            if (!sub.completed &&
                sub.reminderAt != null &&
                sub.reminderAt! > now) {
              ReminderService.instance.scheduleReminder(
                boardId: current.boardId,
                taskId: current.id,
                subtaskId: sub.id,
                title: sub.title,
                body: current.title,
                triggerAtMs: sub.reminderAt!,
              );
            } else {
              ReminderService.instance.cancelReminder(
                current.id,
                subtaskId: sub.id,
              );
            }
          }
        }
        _applyDeadlinePromotion();
        _saveTasks();
        notifyListeners();
        return true;
    }
  }

  Task groupTasks(Iterable<String> ids, String title) {
    _touchCommand();
    final selected =
        tasks
            .where((t) => ids.contains(t.id) && t.boardId == activeBoardId)
            .toList();
    if (selected.length < 2 || title.trim().isEmpty) {
      throw StateError('Select at least two tasks on the active board');
    }
    final selectedIds = selected.map((t) => t.id).toSet();
    final deadlines =
        selected.map((t) => t.deadline).whereType<int>().toList()..sort();
    final parent = Task(
      id: newId(),
      boardId: selected.first.boardId,
      title: title,
      quadrant: selected.first.quadrant,
      completed: selected.every((t) => t.completed),
      isLongTerm: selected.any((t) => t.isLongTerm),
      deadline: deadlines.firstOrNull,
      createdAt: _now(),
      urgencyMode:
          selected.any((t) => t.urgencyMode == UrgencyMode.manual)
              ? UrgencyMode.manual
              : UrgencyMode.auto,
      subtasks: [
        for (final t in selected) ...[
          SubTask(
            id: newId(),
            title: t.title,
            completed: t.completed,
            completedAt: t.completedAt,
            deadline: t.deadline,
            notesMarkdown: t.notesMarkdown,
            reminderAt: t.reminderAt,
          ),
          for (final child in t.subtasks)
            SubTask(
              id: newId(),
              title: '${t.title} / ${child.title}',
              completed: child.completed,
              completedAt: child.completedAt,
              deadline: child.deadline,
              notesMarkdown: child.notesMarkdown,
              reminderAt: child.reminderAt,
            ),
        ],
      ],
    );
    for (final t in selected) {
      ReminderService.instance.cancelReminder(t.id);
      for (final s in t.subtasks) {
        ReminderService.instance.cancelReminder(t.id, subtaskId: s.id);
      }
    }
    tasks.removeWhere((t) => selectedIds.contains(t.id));
    tasks.insert(0, parent);
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!parent.completed &&
        parent.reminderAt != null &&
        parent.reminderAt! > now) {
      ReminderService.instance.scheduleReminder(
        boardId: parent.boardId,
        taskId: parent.id,
        title: parent.title,
        body: parent.notesMarkdown,
        triggerAtMs: parent.reminderAt!,
      );
    }
    for (final s in parent.subtasks) {
      if (!s.completed && s.reminderAt != null && s.reminderAt! > now) {
        ReminderService.instance.scheduleReminder(
          boardId: parent.boardId,
          taskId: parent.id,
          subtaskId: s.id,
          title: s.title,
          body: s.notesMarkdown,
          triggerAtMs: s.reminderAt!,
        );
      }
    }
    _saveTasks();
    notifyListeners();
    return parent;
  }

  void createBoard(String name) {
    final board = Board(id: newId(), name: name, createdAt: _now());
    boards.add(board);
    activeBoardId = board.id;
    _saveBoardsMeta();
    notifyListeners();
  }

  void renameBoard(String id, String name) {
    final i = boards.indexWhere((b) => b.id == id);
    if (i != -1) boards[i].name = name;
    _saveBoardsMeta();
    notifyListeners();
  }

  void deleteBoard(String id) {
    if (boards.length <= 1) return;
    bumpBoardEpoch(id);
    final boardTasks = tasks.where((t) => t.boardId == id).toList();
    ReminderService.instance.cancelAllForBoard(id, boardTasks);
    boards.removeWhere((b) => b.id == id);
    tasks.removeWhere((t) => t.boardId == id);
    if (activeBoardId == id) activeBoardId = boards.first.id;
    _saveBoardsMeta();
    _saveTasks();
    notifyListeners();
  }

  void updateSettings(AppSettings Function(AppSettings) change) {
    settings = change(settings);
    settings.urgencyThresholdDays = settings.urgencyThresholdDays.clamp(1, 14);
    _applyDeadlinePromotion();
    _saveSettings();
    notifyListeners();
  }

  Future<bool> updateAIConfig(AIConfig config) async {
    if (_credentialMigrationPending) {
      aiConfig.apiKey = _legacyCredentialForMigration ?? aiConfig.apiKey;
      credentialError = t['credentialMigrationError'];
      if (!_disposed) notifyListeners();
      return false;
    }
    final requested = config.apiKey;
    aiConfig = _copyConfig(config);
    // Keep the editable value visible while the secure write is pending. No
    // ordinary snapshot includes it; failure restores the confirmed value.
    aiConfig.apiKey = requested;
    _saveConfig();
    notifyListeners();
    if (requested == _confirmedCredential) {
      _pendingCredentialValue = null;
      credentialError = null;
      return true;
    }
    _pendingCredentialValue = requested;
    final previous = _credentialWrites;
    final result = Completer<bool>();
    _credentialWrites = () async {
      await previous;
      try {
        if (requested.isEmpty) {
          await credentialStore.delete();
          if (await credentialStore.read() != null) {
            throw StateError('Credential delete failed');
          }
        } else {
          await credentialStore.write(requested);
          if (await credentialStore.read() != requested) {
            throw StateError('Credential verification failed');
          }
        }
        _confirmedCredential = requested;
        aiConfig.apiKey = requested;
        credentialError = null;
        if (_pendingCredentialValue == requested) {
          _pendingCredentialValue = null;
        }
        result.complete(true);
      } catch (_) {
        credentialError = t['credentialStoreError'];
        aiConfig.apiKey = _confirmedCredential;
        result.complete(false);
      }
      notifyListeners();
    }();
    return result.future;
  }

  Future<bool> retryCredentialMigration() async {
    final rollback = _pendingCredentialRollback;
    if (rollback != null) return _restoreCredential(rollback);
    final legacy = _legacyCredentialForMigration ?? aiConfig.apiKey;
    try {
      final secured = await credentialStore.read();
      if (secured != null) {
        _confirmedCredential = secured;
      } else if (legacy.isNotEmpty) {
        await credentialStore.write(legacy);
        if (await credentialStore.read() != legacy) {
          throw StateError('Credential verification failed');
        }
        _confirmedCredential = legacy;
      } else {
        _confirmedCredential = '';
      }
      if (!await _saveProtocol!.scrubCredentials()) {
        throw StateError('Legacy scrub failed');
      }
      aiConfig.apiKey = _confirmedCredential;
      credentialError = null;
      _credentialMigrationPending = false;
      _legacyCredentialForMigration = null;
      return true;
    } catch (_) {
      credentialError = t['credentialMigrationError'];
      _credentialMigrationPending = true;
      _legacyCredentialForMigration = legacy;
      return false;
    }
  }

  Future<bool> retryCredential() async {
    final rollback = _pendingCredentialRollback;
    if (rollback != null) {
      return _restoreCredential(rollback);
    }
    final pending = _pendingCredentialValue;
    if (pending != null) {
      final config = _copyConfig(aiConfig);
      config.apiKey = pending;
      return updateAIConfig(config);
    }
    final wasPending = _credentialMigrationPending;
    final success = await retryCredentialMigration();
    if (success && wasPending && ready && !_disposed) {
      _applyDeadlinePromotion();
      ReminderService.instance.rescheduleAllFuture(tasks);
      _deadlineTimer ??= Timer.periodic(
        const Duration(hours: 1),
        (_) => _applyDeadlinePromotion(),
      );
      WidgetsBinding.instance.addObserver(this);
      notifyListeners();
    }
    return success;
  }

  AIConfig _copyConfig(AIConfig source) => AIConfig(
    provider: source.provider,
    protocol: source.protocol,
    baseUrl: source.baseUrl,
    apiKey: source.apiKey,
    model: source.model,
    enableThinking: source.enableThinking,
  );

  Future<bool> _restoreCredential(String value) async {
    try {
      if (value.isEmpty) {
        await credentialStore.delete();
      } else {
        await credentialStore.write(value);
      }
      if (await credentialStore.read() != (value.isEmpty ? null : value)) {
        throw StateError('Credential rollback verification failed');
      }
      _pendingCredentialRollback = null;
      credentialError = null;
      if (!_disposed) notifyListeners();
      return true;
    } catch (_) {
      _pendingCredentialRollback = value;
      credentialError = t['credentialStoreError'];
      if (!_disposed) notifyListeners();
      return false;
    }
  }

  // --- import / export (ExportData v2 standard, v1 downgrade compatible) ---

  String exportJson({int version = ExportData.currentVersion}) => jsonEncode(
    ExportData(
      version: version,
      boards: boards,
      tasks: tasks,
      settings: settings,
      aiConfig: aiConfig,
    ).toJson(targetVersion: version),
  );

  Future<String> exportJsonWithCredential({
    int version = ExportData.currentVersion,
  }) async {
    await _credentialWrites;
    if (credentialError != null) throw StateError('Credential unavailable');
    final secured = await credentialStore.read();
    if (secured == null && _confirmedCredential.isNotEmpty) {
      throw StateError('Credential unavailable');
    }
    final config = _copyConfig(aiConfig);
    config.apiKey = secured ?? '';
    return jsonEncode(
      ExportData(
        version: version,
        boards: boards,
        tasks: tasks,
        settings: settings,
        aiConfig: config,
      ).toJson(targetVersion: version, includeCredential: true),
    );
  }

  /// Returns the number of tasks imported. [mode] is 'merge' or 'overwrite'.
  int importData(Map<String, dynamic> json, String mode) {
    final plan = previewImport(json, mode);
    if (plan.conflicts != 0) throw const FormatException('Conflicting IDs');
    _applyImportState(plan);
    _persistAll();
    return plan.addedTasks;
  }

  ImportPlan previewImport(Map<String, dynamic> json, String mode) =>
      ImportPreflight.inspect(
        json,
        mode,
        currentBoards: boards,
        currentTasks: tasks,
        revision: _dirtyRevision,
      );

  /// Persist the proposed complete state before changing live state.
  Future<SaveResult> applyImport(
    ImportPlan plan, {
    bool importCredential = false,
  }) async {
    await _credentialWrites;
    if (plan.conflicts != 0 || hasStartupRecovery || credentialError != null) {
      return const SaveResult(false, 0);
    }
    final preceding = await flush();
    if (!preceding.success ||
        plan.baseRevision != _dirtyRevision ||
        _disposed) {
      return const SaveResult(false, 0);
    }
    final nextSettings = plan.settings ?? settings;
    final nextConfig =
        plan.aiConfig == null ? aiConfig : _copyConfig(plan.aiConfig!);
    final oldCredential = _confirmedCredential;
    final newCredential =
        importCredential && plan.hasCredential
            ? plan.aiConfig!.apiKey
            : oldCredential;
    nextConfig.apiKey = newCredential;
    if (newCredential != oldCredential) {
      try {
        if (newCredential.isEmpty) {
          await credentialStore.delete();
        } else {
          await credentialStore.write(newCredential);
        }
        if ((await credentialStore.read()) !=
            (newCredential.isEmpty ? null : newCredential)) {
          throw StateError('Credential verification failed');
        }
      } catch (_) {
        await _restoreCredential(oldCredential);
        credentialError = t['credentialStoreError'];
        if (!_disposed) notifyListeners();
        return const SaveResult(false, 0);
      }
    }
    final active =
        plan.mode == 'overwrite' ? plan.boards.first.id : activeBoardId;
    final values = _snapshotValues(
      boardsValue: plan.boards,
      tasksValue: plan.tasks,
      settingsValue: nextSettings,
      configValue: nextConfig,
      activeValue: active,
    );
    final result = await _saveProtocol!.commit(values);
    lastSaveResult = result;
    if (!result.success) {
      if (newCredential != oldCredential) {
        await _restoreCredential(oldCredential);
      }
      persistenceError = t['storageWriteError'];
      if (!_disposed) notifyListeners();
      return result;
    }
    _savedValues = values;
    _confirmedCredential = newCredential;
    credentialError = null;
    _dirtyRevision++;
    _savedRevision = _dirtyRevision;
    persistenceError = null;
    if (_disposed) return result;
    _applyImportState(plan);
    notifyListeners();
    return result;
  }

  void _applyImportState(ImportPlan plan) {
    if (plan.mode == 'overwrite') {
      bumpAllBoardEpochs();
      for (final board in plan.boards) {
        bumpBoardEpoch(board.id);
      }
    }
    boards = plan.boards;
    tasks = plan.tasks;
    settings = plan.settings ?? settings;
    if (plan.aiConfig != null) {
      aiConfig = _copyConfig(plan.aiConfig!);
      aiConfig.apiKey = _confirmedCredential;
    }
    if (plan.mode == 'overwrite') activeBoardId = boards.first.id;
    try {
      if (plan.mode == 'overwrite') ReminderService.instance.cancelAll();
      ReminderService.instance.rescheduleAllFuture(tasks);
    } catch (_) {
      // Reminder delivery is tracked separately from library persistence.
    }
    notifyListeners();
  }

  // --- deadline auto-promotion ---

  /// Test hook: run one promotion pass immediately.
  @visibleForTesting
  void promoteDeadlinesNow({DateTime? now}) =>
      _applyDeadlinePromotion(now: now);

  void _applyDeadlinePromotion({DateTime? now}) {
    if (tasks.isEmpty) return;
    final threshold = settings.urgencyThresholdDays;
    final ref = now ?? DateTime.now();
    var changed = false;
    for (final task in tasks) {
      if (task.deadline == null || task.completed) continue;
      if (task.urgencyMode != UrgencyMode.auto) continue;
      if (isDeadlineUrgent(task.deadline, threshold, now: ref)) {
        final nextQ = promoteToUrgent(task.quadrant);
        if (nextQ != task.quadrant) {
          task.quadrant = nextQ;
          changed = true;
        }
      }
    }
    if (changed) {
      _saveTasks();
      notifyListeners();
    }
  }

  // --- persistence ---

  dynamic _loadJson(String key) {
    try {
      final raw = _savedValues?[key] ?? _prefs.getString(key);
      if (raw == null) return null;
      return jsonDecode(raw);
    } catch (_) {
      return '<<corrupt>>'; // non-null sentinel marks corruption
    }
  }

  void _persistAll() {
    _saveTasks();
    _saveBoardsMeta();
    _saveConfig();
    _saveSettings();
  }

  void _write(String key, String value) {
    if (!ready || _disposed || hasStartupRecovery || credentialError != null) {
      return;
    }
    _dirtyRevision++;
    if (!_saveScheduled) {
      _saveScheduled = true;
      _pendingWrites = _pendingWrites.then((_) async {
        // Coalesce every mutation in the current synchronous command.
        await Future<void>.value();
        while (_savedRevision < _dirtyRevision && !_disposed) {
          final target = _dirtyRevision;
          final values = _snapshotValues();
          final result = await _saveProtocol!.commit(values);
          lastSaveResult = result;
          if (!result.success) {
            persistenceError = t['storageWriteError'];
            if (!_disposed) notifyListeners();
            _saveScheduled = false;
            return;
          }
          _savedRevision = target;
          _savedValues = values;
          persistenceError = null;
          if (!_disposed) notifyListeners();
        }
        _saveScheduled = false;
      });
    }
  }

  Future<SaveResult> flush() async {
    await _pendingWrites;
    return lastSaveResult;
  }

  Future<SaveResult> retrySave() async {
    if (!ready || hasStartupRecovery) return const SaveResult(false, 0);
    _savedRevision = _dirtyRevision;
    _write(_kTasks, '');
    return flush();
  }

  Map<String, String> _snapshotValues({
    List<Board>? boardsValue,
    List<Task>? tasksValue,
    AIConfig? configValue,
    AppSettings? settingsValue,
    String? activeValue,
  }) => {
    _kTasks: jsonEncode(
      (tasksValue ?? tasks).map((task) => task.toJson()).toList(),
    ),
    _kBoards: jsonEncode(
      (boardsValue ?? boards).map((board) => board.toJson()).toList(),
    ),
    _kConfig: jsonEncode(
      (configValue ?? aiConfig).toJson(includeCredential: false),
    ),
    _kSettings: jsonEncode((settingsValue ?? settings).toJson()),
    _kActiveBoard: activeValue ?? activeBoardId,
    _kHasSeenOnboarding: hasSeenOnboarding.toString(),
  };

  void _saveTasks() =>
      _write(_kTasks, jsonEncode(tasks.map((t) => t.toJson()).toList()));
  void _saveBoardsMeta() {
    _write(_kBoards, jsonEncode(boards.map((b) => b.toJson()).toList()));
    _write(_kActiveBoard, activeBoardId);
  }

  void _saveConfig() =>
      _write(_kConfig, jsonEncode(aiConfig.toJson(includeCredential: false)));
  void _saveSettings() => _write(_kSettings, jsonEncode(settings.toJson()));

  List<Locale> _resolvePlatformLocales() {
    try {
      return WidgetsBinding.instance.platformDispatcher.locales;
    } catch (_) {
      return const [];
    }
  }
}

int _now() => DateTime.now().millisecondsSinceEpoch;
