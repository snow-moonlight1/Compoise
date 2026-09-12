/// Central app store: all state, persistence (same localStorage keys as the web
/// app), CRUD operations and the deadline auto-promotion loop.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ai_service.dart';
import 'l10n.dart';
import 'models.dart';
import 'task_commands.dart';

export 'task_commands.dart';

class Store extends ChangeNotifier with WidgetsBindingObserver {
  static const _kTasks = 'matrixflow-tasks';
  static const _kBoards = 'matrixflow-boards';
  static const _kConfig = 'matrixflow-config';
  static const _kSettings = 'matrixflow-settings';
  static const _kActiveBoard = 'matrixflow-active-board';

  final AIService ai;
  late SharedPreferences _prefs;

  bool ready = false;
  bool _disposed = false;
  String? startupError;
  String? persistenceError;
  Future<void> _pendingWrites = Future.value();
  List<Board> boards = [];
  List<Task> tasks = [];
  String activeBoardId = '';
  AIConfig aiConfig = AIConfig();
  AppSettings settings = AppSettings();
  String? corruptNotice; // set when a persisted blob failed to parse

  Map<String, String> get t => dictOf(settings.language);

  Timer? _deadlineTimer;

  final List<Locale>? initialDeviceLocales;

  Store({AIService? aiService, List<Locale>? deviceLocales})
      : ai = aiService ?? AIService(),
        initialDeviceLocales = deviceLocales;

  Future<void> init({List<Locale>? deviceLocales}) async {
    startupError = null;
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
    var corrupted = 0;

    T read<T>(String key, T fallback, T Function(dynamic) parse) {
      final raw = _loadJson(key);
      if (raw == null) return fallback;
      try {
        return parse(raw);
      } catch (_) {
        corrupted++;
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
    );
    final rawSettings = _loadJson(_kSettings);
    if (rawSettings == null) {
      settings = AppSettings(language: resolvedDeviceLang);
    } else {
      try {
        final map = rawSettings as Map<String, dynamic>;
        settings = AppSettings.fromJson(
          map,
          defaultLanguage: resolvedDeviceLang,
        );
      } catch (_) {
        corrupted++;
        settings = AppSettings(language: resolvedDeviceLang);
      }
    }
    boards = read(
      _kBoards,
      <Board>[],
      (raw) => records(raw, Board.fromJson, (b) => b.id),
    );
    tasks = read(
      _kTasks,
      <Task>[],
      (raw) => records(raw, Task.fromJson, (task) => task.id),
    );

    if (boards.isEmpty) {
      boards = [
        Board(id: newId(), name: t['defaultBoardName']!, createdAt: _now()),
      ];
    }
    final validIds = boards.map((b) => b.id).toSet();
    for (final task in tasks) {
      if (!validIds.contains(task.boardId)) {
        if (task.boardId.isNotEmpty) corrupted++;
        task.boardId = boards.first.id;
      }
    }
    final savedActive = _prefs.get(_kActiveBoard);
    activeBoardId = savedActive is String ? savedActive : '';
    if (!boards.any((b) => b.id == activeBoardId)) {
      activeBoardId = boards.first.id;
    }
    if (corrupted > 0) corruptNotice = t['corruptData'];

    ready = true;
    _persistAll();
    _applyDeadlinePromotion();
    notifyListeners();

    _deadlineTimer = Timer.periodic(
      const Duration(hours: 1),
      (_) => _applyDeadlinePromotion(),
    );
    WidgetsBinding.instance.addObserver(this);
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
          .where((t) => t.completed && (boardId == null || t.boardId == boardId))
          .toList();

  /// Total number of completed tasks on [boardId] (or across all boards if null).
  int completedTaskCount({String? boardId}) =>
      tasks
          .where((t) => t.completed && (boardId == null || t.boardId == boardId))
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
      (s) => s
        ..fontSize = FontSizePref.standard
        ..fontFamily = FontFamilyPref.system
        ..viewMode = ViewMode.grid,
    );
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
    tasks.insertAll(
      0,
      newTasks.where(
        (task) => boardIds.contains(task.boardId) && seen.add(task.id),
      ),
    );
    _applyDeadlinePromotion();
    _saveTasks();
    notifyListeners();
  }

  Task newTask(
    String title, {
    int quadrant = qDo,
    bool isLongTerm = false,
    int? deadline,
  }) =>
      Task(
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

  void updateTask(Task updated) {
    final i = tasks.indexWhere((t) => t.id == updated.id);
    if (i == -1) return;
    final oldQuadrant = tasks[i].quadrant;
    final quadrantChanged = oldQuadrant != updated.quadrant;

    if (settings.autoCompleteParent && updated.subtasks.isNotEmpty) {
      final allDone = updated.subtasks.every((s) => s.completed);
      if (allDone) updated.completed = true;
      if (updated.completed && updated.subtasks.any((s) => !s.completed)) {
        updated.completed = false;
      }
    }

    if (quadrantChanged) {
      tasks.removeAt(i);
      _insertAtFrontOfQuadrant(updated);
    } else {
      tasks[i] = updated;
    }

    _applyDeadlinePromotion();
    _saveTasks();
    notifyListeners();
  }

  void deleteTask(String id) {
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
    final task = Task.fromJson(tasks[i].toJson())..quadrant = quadrant;
    tasks.removeAt(i);
    _insertAtFrontOfQuadrant(task);
    _saveTasks();
    notifyListeners();
  }

  void appendSubtasks(String taskId, List<SubTask> subs) {
    final i = tasks.indexWhere((t) => t.id == taskId);
    if (i == -1) return;
    final updated = Task.fromJson(tasks[i].toJson())..subtasks.addAll(subs);
    updateTask(updated);
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
    tasks.removeWhere(
      (t) => t.boardId == bId && t.quadrant == quadrant,
    );
    _saveTasks();
    notifyListeners();
  }

  /// Parent checkbox cascade: set self + every subtask to [completed].
  void setParentCompleted(Task task, bool completed) {
    task.completed = completed;
    for (final s in task.subtasks) {
      s.completed = completed;
    }
    updateTask(task);
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
    final snapshot = TaskUndoSnapshot.capture(
      actionType: TaskUndoType.delete,
      task: task,
      boardEpoch: boardEpoch(task.boardId),
      originalIndex: i,
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
    final snapshot = TaskUndoSnapshot.capture(
      actionType: nextState ? TaskUndoType.complete : TaskUndoType.restore,
      task: current,
      boardEpoch: boardEpoch(current.boardId),
      originalIndex: i,
    );
    setParentCompleted(current, nextState);
    return snapshot;
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
        final subMap = {
          for (final s in snapshot.task.subtasks) s.id: s.completed,
        };
        for (final sub in current.subtasks) {
          if (subMap.containsKey(sub.id)) {
            sub.completed = subMap[sub.id]!;
          }
        }
        _applyDeadlinePromotion();
        _saveTasks();
        notifyListeners();
        return true;
    }
  }

  Task groupTasks(Iterable<String> ids, String title) {
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
      subtasks: [
        for (final t in selected) ...[
          SubTask(
            id: newId(),
            title: t.title,
            completed: t.completed,
            deadline: t.deadline,
          ),
          for (final child in t.subtasks)
            SubTask(
              id: newId(),
              title: '${t.title} / ${child.title}',
              completed: child.completed,
              deadline: child.deadline,
            ),
        ],
      ],
    );
    tasks.removeWhere((t) => selectedIds.contains(t.id));
    tasks.insert(0, parent);
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

  void updateAIConfig(AIConfig config) {
    aiConfig = config;
    _saveConfig();
    notifyListeners();
  }

  // --- import / export (web-compatible ExportData v1) ---

  String exportJson() => jsonEncode(
    ExportData(
      boards: boards,
      tasks: tasks,
      settings: settings,
      aiConfig: aiConfig,
    ).toJson(),
  );

  /// Returns the number of tasks imported. [mode] is 'merge' or 'overwrite'.
  int importData(Map<String, dynamic> json, String mode) {
    if (!['merge', 'overwrite'].contains(mode) ||
        (json.containsKey('version') &&
            json['version'] != ExportData.version) ||
        json['boards'] is! List ||
        json['tasks'] is! List) {
      throw const FormatException('bad export shape');
    }
    final incomingBoards =
        (json['boards'] as List)
            .cast<Map<String, dynamic>>()
            .map(Board.fromJson)
            .toList();
    final incomingTasks =
        (json['tasks'] as List)
            .cast<Map<String, dynamic>>()
            .map(Task.fromJson)
            .toList();
    // Parse every imported field before mutating live state.
    final incomingSettings =
        json['settings'] == null
            ? null
            : AppSettings.fromJson(json['settings'] as Map<String, dynamic>);
    final incomingConfig =
        json['aiConfig'] == null
            ? null
            : AIConfig.fromJson(json['aiConfig'] as Map<String, dynamic>);
    final seenBoards = <String>{};
    incomingBoards.removeWhere((b) => !seenBoards.add(b.id));
    final seenTasks = <String>{};
    incomingTasks.removeWhere((task) => !seenTasks.add(task.id));

    if (mode == 'overwrite') {
      bumpAllBoardEpochs();
      for (final b in incomingBoards) {
        bumpBoardEpoch(b.id);
      }
      if (incomingBoards.isEmpty) {
        incomingBoards.add(
          Board(id: newId(), name: t['defaultBoardName']!, createdAt: _now()),
        );
      }
      final validIds = incomingBoards.map((b) => b.id).toSet();
      for (final task in incomingTasks) {
        if (task.boardId.isEmpty) task.boardId = incomingBoards.first.id;
        if (!validIds.contains(task.boardId)) {
          throw const FormatException('Task references a missing board');
        }
      }
      boards = incomingBoards;
      tasks = incomingTasks;
      settings = incomingSettings ?? settings;
      aiConfig = incomingConfig ?? aiConfig;
      activeBoardId = boards.first.id;
      _applyDeadlinePromotion();
      _persistAll();
      notifyListeners();
      return incomingTasks.length;
    }

    // merge: dedupe boards & tasks by id, drop orphan tasks
    final existingBoardIds = boards.map((b) => b.id).toSet();
    final newBoards =
        incomingBoards.where((b) => !existingBoardIds.contains(b.id)).toList();
    boards.addAll(newBoards);

    final seenTaskIds = tasks.map((t) => t.id).toSet();
    final validBoardIds = {...existingBoardIds, ...newBoards.map((b) => b.id)};
    final incoming =
        incomingTasks
            .where(
              (task) =>
                  validBoardIds.contains(task.boardId) &&
                  seenTaskIds.add(task.id),
            )
            .toList();
    tasks.addAll(incoming);
    _applyDeadlinePromotion();
    _saveBoardsMeta();
    _saveTasks();
    notifyListeners();
    return incoming.length;
  }

  // --- deadline auto-promotion ---

  /// Test hook: run one promotion pass immediately.
  @visibleForTesting
  void promoteDeadlinesNow() => _applyDeadlinePromotion();

  void _applyDeadlinePromotion() {
    if (tasks.isEmpty) return;
    final threshold = settings.urgencyThresholdDays * 24 * 60 * 60 * 1000;
    final now = _now();
    var changed = false;
    for (final task in tasks) {
      if (task.deadline == null || task.completed) continue;
      final timeLeft = task.deadline! - now;
      if (task.quadrant == qPlan && timeLeft <= threshold) {
        task.quadrant = qDo;
        changed = true;
      } else if (task.quadrant == qEliminate && timeLeft <= threshold) {
        task.quadrant = qDelegate;
        changed = true;
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
      final raw = _prefs.getString(key);
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
    if (!ready || _disposed) return;
    _pendingWrites = _pendingWrites.then((_) async {
      try {
        if (!await _prefs.setString(key, value)) {
          throw StateError('Save failed');
        }
      } catch (_) {
        if (!_disposed) {
          persistenceError = t['storageWriteError'];
          notifyListeners();
        }
      }
    });
  }

  Future<void> flush() => _pendingWrites;

  void _saveTasks() =>
      _write(_kTasks, jsonEncode(tasks.map((t) => t.toJson()).toList()));
  void _saveBoardsMeta() {
    _write(_kBoards, jsonEncode(boards.map((b) => b.toJson()).toList()));
    _write(_kActiveBoard, activeBoardId);
  }

  void _saveConfig() => _write(_kConfig, jsonEncode(aiConfig.toJson()));
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
