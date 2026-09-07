/// Central app store: all state, persistence (same localStorage keys as the web
/// app), CRUD operations and the deadline auto-promotion loop.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ai_service.dart';
import 'l10n.dart';
import 'models.dart';

class Store extends ChangeNotifier {
  static const _kTasks = 'matrixflow-tasks';
  static const _kBoards = 'matrixflow-boards';
  static const _kConfig = 'matrixflow-config';
  static const _kSettings = 'matrixflow-settings';

  final AIService ai;
  late SharedPreferences _prefs;

  bool ready = false;
  List<Board> boards = [];
  List<Task> tasks = [];
  String activeBoardId = '';
  AIConfig aiConfig = AIConfig();
  AppSettings settings = AppSettings();
  String? corruptNotice; // set when a persisted blob failed to parse

  Map<String, String> get t => dictOf(settings.language);

  Timer? _deadlineTimer;

  Store({AIService? aiService}) : ai = aiService ?? AIService();

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    var corrupted = 0;

    final cfg = _loadJson(_kConfig);
    if (cfg is Map<String, dynamic>) {
      aiConfig = AIConfig.fromJson(cfg);
    } else if (cfg != null) {
      corrupted++;
    }

    final st = _loadJson(_kSettings);
    if (st is Map<String, dynamic>) {
      settings = AppSettings.fromJson(st);
    } else if (st != null) {
      corrupted++;
    }

    final boardsRaw = _loadJson(_kBoards);
    if (boardsRaw is List) {
      boards = boardsRaw
          .whereType<Map<String, dynamic>>()
          .map(Board.fromJson)
          .toList();
    } else if (boardsRaw != null) {
      corrupted++;
    }

    final tasksRaw = _loadJson(_kTasks);
    if (tasksRaw is List) {
      var loaded = tasksRaw
          .whereType<Map<String, dynamic>>()
          .map(Task.fromJson)
          .toList();
      if (loaded.isNotEmpty && loaded.first.boardId.isEmpty) {
        // Pre-boards export: fold every task into the first board.
        if (boards.isEmpty) {
          boards = [Board(id: _uuid(), name: t['defaultBoardName']!, createdAt: _now())];
        }
        final target = boards.first.id;
        loaded = [
          for (final task in loaded) task..boardId = task.boardId.isEmpty ? target : task.boardId
        ];
      }
      tasks = loaded;
    } else if (tasksRaw != null) {
      corrupted++;
    }

    if (boards.isEmpty) {
      boards = [Board(id: _uuid(), name: t['defaultBoardName']!, createdAt: _now())];
    }
    if (!boards.any((b) => b.id == activeBoardId)) {
      activeBoardId = boards.first.id;
    }
    if (corrupted > 0) corruptNotice = t['corruptData'];

    ready = true;
    _persistAll();
    _applyDeadlinePromotion();
    notifyListeners();

    _deadlineTimer = Timer.periodic(const Duration(hours: 1), (_) => _applyDeadlinePromotion());
  }

  @override
  void dispose() {
    _deadlineTimer?.cancel();
    super.dispose();
  }

  // --- derived ---

  Board? get activeBoard =>
      boards.where((b) => b.id == activeBoardId).firstOrNull;

  List<Task> get visibleTasks {
    final list = tasks
        .where((task) => task.boardId == activeBoardId)
        .where((task) => !settings.hideCompleted || !task.completed)
        .toList();
    return list;
  }

  List<Task> tasksIn(int quadrant) =>
      visibleTasks.where((task) => task.quadrant == quadrant).toList();

  List<Task> longTermPending() =>
      visibleTasks.where((task) => task.isLongTerm && !task.hasSubtasks && !task.completed).toList();

  // --- mutations ---

  void setActiveBoard(String id) {
    activeBoardId = id;
    _saveBoardsMeta();
    notifyListeners();
  }

  void addTasks(List<Task> newTasks) {
    tasks.insertAll(0, newTasks);
    _saveTasks();
    notifyListeners();
  }

  Task newTask(String title, {int quadrant = qDo, bool isLongTerm = false}) => Task(
        id: _uuid(),
        boardId: activeBoardId,
        title: title,
        quadrant: quadrant,
        isLongTerm: isLongTerm,
        createdAt: _now(),
      );

  void updateTask(Task updated) {
    if (settings.autoCompleteParent &&
        updated.subtasks.isNotEmpty) {
      final allDone = updated.subtasks.every((s) => s.completed);
      if (allDone) updated.completed = true;
      if (updated.completed && updated.subtasks.any((s) => !s.completed)) {
        updated.completed = false;
      }
    }
    final i = tasks.indexWhere((t) => t.id == updated.id);
    if (i != -1) tasks[i] = updated;
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
    tasks[i] = Task.fromJson(tasks[i].toJson())..quadrant = quadrant;
    _saveTasks();
    notifyListeners();
  }

  void appendSubtasks(String taskId, List<SubTask> subs) {
    final i = tasks.indexWhere((t) => t.id == taskId);
    if (i == -1) return;
    tasks[i].subtasks = [...tasks[i].subtasks, ...subs];
    _saveTasks();
    notifyListeners();
  }

  void clearQuadrant(int quadrant) {
    tasks.removeWhere((t) => t.boardId == activeBoardId && t.quadrant == quadrant);
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

  Task groupTasks(Iterable<String> ids, String title) {
    final selected = tasks.where((t) => ids.contains(t.id)).toList();
    if (selected.isEmpty) throw StateError('no tasks selected');
    final parent = Task(
      id: _uuid(),
      boardId: selected.first.boardId,
      title: title,
      quadrant: selected.first.quadrant,
      createdAt: _now(),
      subtasks: [
        for (final t in selected)
          SubTask(
            id: _uuid(),
            title: t.title,
            completed: t.completed,
            deadline: t.deadline,
          ),
      ],
    );
    tasks.removeWhere((t) => ids.contains(t.id));
    tasks.insert(0, parent);
    _saveTasks();
    notifyListeners();
    return parent;
  }

  void createBoard(String name) {
    final board = Board(id: _uuid(), name: name, createdAt: _now());
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
    boards.removeWhere((b) => b.id == id);
    tasks.removeWhere((t) => t.boardId == id);
    if (activeBoardId == id) activeBoardId = boards.first.id;
    _saveBoardsMeta();
    _saveTasks();
    notifyListeners();
  }

  void updateSettings(AppSettings Function(AppSettings) change) {
    settings = change(settings);
    _saveSettings();
    notifyListeners();
  }

  void updateAIConfig(AIConfig config) {
    aiConfig = config;
    _saveConfig();
    notifyListeners();
  }

  // --- import / export (web-compatible ExportData v1) ---

  String exportJson() => jsonEncode(ExportData(
        boards: boards,
        tasks: tasks,
        settings: settings,
        aiConfig: aiConfig,
      ).toJson());

  /// Returns the number of tasks imported. [mode] is 'merge' or 'overwrite'.
  int importData(Map<String, dynamic> json, String mode) {
    if (json['boards'] is! List || json['tasks'] is! List) {
      throw const FormatException('bad export shape');
    }
    final incomingBoards = (json['boards'] as List)
        .whereType<Map<String, dynamic>>()
        .map(Board.fromJson)
        .toList();
    final incomingTasks = (json['tasks'] as List)
        .whereType<Map<String, dynamic>>()
        .map(Task.fromJson)
        .toList();

    if (mode == 'overwrite') {
      boards = incomingBoards;
      tasks = incomingTasks;
      if (json['settings'] is Map<String, dynamic>) {
        settings = AppSettings.fromJson(json['settings'] as Map<String, dynamic>);
      }
      if (json['aiConfig'] is Map<String, dynamic>) {
        aiConfig = AIConfig.fromJson(json['aiConfig'] as Map<String, dynamic>);
      }
      if (boards.isEmpty) {
        boards = [Board(id: _uuid(), name: t['defaultBoardName']!, createdAt: _now())];
      }
      activeBoardId = boards.first.id;
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
    final incoming = incomingTasks
        .where((task) => !seenTaskIds.contains(task.id) && validBoardIds.contains(task.boardId))
        .toList();
    tasks.addAll(incoming);
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
    final raw = _prefs.getString(key);
    if (raw == null) return null;
    try {
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

  void _saveTasks() =>
      _prefs.setString(_kTasks, jsonEncode(tasks.map((t) => t.toJson()).toList()));
  void _saveBoardsMeta() =>
      _prefs.setString(_kBoards, jsonEncode(boards.map((b) => b.toJson()).toList()));
  void _saveConfig() => _prefs.setString(_kConfig, jsonEncode(aiConfig.toJson()));
  void _saveSettings() => _prefs.setString(_kSettings, jsonEncode(settings.toJson()));
}

int _now() => DateTime.now().millisecondsSinceEpoch;

String _uuid() {
  // crypto.randomUUID is available on all Flutter targets via Random.secure.
  final rnd = DateTime.now().microsecondsSinceEpoch;
  return 'mf-$rnd-${(rnd * 31) & 0x7fffffff}';
}
