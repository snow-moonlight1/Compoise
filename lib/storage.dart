/// Central app store: all state, persistence (same localStorage keys as the web
/// app), CRUD operations and the deadline auto-promotion loop.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ai_service.dart';
import 'backup_export.dart';
import 'credential_store.dart';
import 'deadline_policy.dart';
import 'l10n.dart';
import 'import_preflight.dart';
import 'models.dart';
import 'planned_policy.dart';
import 'schedule_item.dart';
import 'save_protocol.dart';
import 'services/reminder_service.dart';
import 'task_commands.dart';
import 'today_celebration.dart';

export 'backup_export.dart';
export 'data_migrations.dart';
export 'credential_store.dart';
export 'deadline_policy.dart';
export 'import_preflight.dart';
export 'save_protocol.dart';
export 'services/reminder_service.dart';
export 'task_commands.dart';

enum StartupDataState { missing, valid, migrated, corrupt }

/// Opens the local preferences database used by the OS06 save protocol.
abstract class StorePersistence {
  const StorePersistence();

  Future<SharedPreferences> open();
}

class SharedPreferencesStorePersistence extends StorePersistence {
  const SharedPreferencesStorePersistence();

  @override
  Future<SharedPreferences> open() => SharedPreferences.getInstance();
}

/// Detached read of the library. Mutating a snapshot does not change the store.
class StoreSnapshot {
  final List<Board> boards;
  final List<Task> tasks;
  final List<ScheduleItem> scheduleItems;
  final AIConfig aiConfig;
  final AppSettings settings;
  final String activeBoardId;
  final Map<String, int> taskRevisions;
  final Map<String, int> scheduleRevisions;

  const StoreSnapshot({
    required this.boards,
    required this.tasks,
    required this.scheduleItems,
    required this.aiConfig,
    required this.settings,
    required this.activeBoardId,
    required this.taskRevisions,
    required this.scheduleRevisions,
  });

  int revisionFor(String taskId) => taskRevisions[taskId] ?? 0;
  int scheduleRevisionFor(String id) => scheduleRevisions[id] ?? 0;
}

class _CredentialImportReservation {
  final Future<void> prior;
  final Completer<void> gate = Completer<void>();

  _CredentialImportReservation(this.prior);
}

class Store extends ChangeNotifier with WidgetsBindingObserver {
  static const _kTasks = 'matrixflow-tasks';
  static const _kSchedule = SaveProtocol.scheduleKey;
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
  int _credentialIntent = 0;
  int _queuedCredentialWrites = 0;
  final List<_CredentialImportReservation> _credentialImports = [];
  String? credentialError;
  bool _credentialMigrationPending = false;
  late SharedPreferences _prefs;
  SaveProtocol? _saveProtocol;
  Map<String, String>? _savedValues;
  final SaveWrite? saveWriter;
  final ReminderService? reminders;
  final StorePersistence persistence;

  bool ready = false;
  bool _disposed = false;
  bool hasSeenOnboarding = false;
  String? startupError;
  String? persistenceError;

  /// The store's single serial commit owner.
  ///
  /// Ordinary task/board/settings commands, the import transaction and every
  /// disk commit are chained onto this one future, so their
  /// read/derive/commit sections can never interleave. [SaveProtocol] keeps its
  /// own slot queue for on-disk ordering; this chain decides *which* state is
  /// committed and in which order. Anything that changes persisted state and
  /// awaits must run through [_runTransaction].
  Future<void> _commitGate = Future.value();
  bool _saveScheduled = false;
  int _dirtyRevision = 0;
  int _savedRevision = 0;
  SaveResult lastSaveResult = const SaveResult(true, 0);
  List<Board> _boards = [];
  List<Task> _tasks = [];
  List<ScheduleItem> _scheduleItems = [];
  List<Board> get boards => List.unmodifiable(_boards);
  List<Task> get tasks => List.unmodifiable(_tasks);
  List<ScheduleItem> get scheduleItems => List.unmodifiable(_scheduleItems);
  final Map<String, int> _scheduleSeq = {};
  int scheduleRevision(String id) => _scheduleSeq[id] ?? 0;
  void _touchSchedule(String id) => _scheduleSeq[id] = scheduleRevision(id) + 1;

  /// Commands use a caller's observed revision; a stale detail pane cannot
  /// overwrite a newer edit, deletion, or re-parenting.
  bool addScheduleItem(ScheduleItem item) {
    if (hasStartupRecovery) throw StateError('Startup recovery pending');
    _validateSchedule([..._scheduleItems, item]);
    _scheduleItems.add(item);
    _touchSchedule(item.id);
    _markDirty();
    notifyListeners();
    return true;
  }

  bool updateScheduleItem(ScheduleItem item, {required int expectedRevision}) {
    if (hasStartupRecovery) throw StateError('Startup recovery pending');
    final index = _scheduleItems.indexWhere((entry) => entry.id == item.id);
    if (index < 0 || scheduleRevision(item.id) != expectedRevision) {
      return false;
    }
    if (jsonEncode(_scheduleItems[index].toJson()) ==
        jsonEncode(item.toJson())) {
      return true;
    }
    final next = List<ScheduleItem>.from(_scheduleItems)..[index] = item;
    _validateSchedule(next);
    _scheduleItems[index] = item;
    _touchSchedule(item.id);
    _markDirty();
    notifyListeners();
    return true;
  }

  bool deleteScheduleItem(String id, {required int expectedRevision}) {
    if (hasStartupRecovery) throw StateError('Startup recovery pending');
    final index = _scheduleItems.indexWhere((entry) => entry.id == id);
    if (index < 0 || scheduleRevision(id) != expectedRevision) return false;
    _scheduleItems.removeAt(index);
    _touchSchedule(id);
    _markDirty();
    notifyListeners();
    return true;
  }

  void _validateSchedule(Iterable<ScheduleItem> items) =>
      validateScheduleCollection(
        items,
        parentTaskIds: {for (final task in _tasks) task.id},
        boardIds: {for (final board in _boards) board.id},
      );

  bool _removeScheduleForTaskIds(Set<String> ids) {
    if (ids.isEmpty) return false;
    final removed = _scheduleItems
        .where((item) => ids.contains(item.taskId))
        .toList();
    if (removed.isEmpty) return false;
    _scheduleItems.removeWhere((item) => ids.contains(item.taskId));
    for (final item in removed) {
      _touchSchedule(item.id);
    }
    return true;
  }

  bool _removeOrphanScheduleItems() {
    final taskIds = {for (final task in _tasks) task.id};
    final boardIds = {for (final board in _boards) board.id};
    final removed = _scheduleItems
        .where(
          (item) =>
              item.taskId != null && !taskIds.contains(item.taskId) ||
              item.boardId != null && !boardIds.contains(item.boardId),
        )
        .toList();
    if (removed.isEmpty) return false;
    _scheduleItems.removeWhere((item) => removed.contains(item));
    for (final item in removed) {
      _touchSchedule(item.id);
    }
    return true;
  }

  String activeBoardId = '';
  AIConfig aiConfig = AIConfig();
  AppSettings settings = AppSettings();

  /// Session latch for the Today completion celebration. Not written to the
  /// snapshot: it is not a user setting, and a new process starts clear.
  final TodayCelebrationMemory todayCelebration = TodayCelebrationMemory();
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
    this.reminders,
    StorePersistence? persistence,
  }) : ai = aiService ?? AIService(),
       credentialStore =
           credentialStore ??
           testCredentialStore ??
           const SystemCredentialStore(),
       persistence = persistence ?? const SharedPreferencesStorePersistence(),
       initialDeviceLocales = deviceLocales;

  /// Reminder port for commands. Falls back to the process service when the
  /// composition root does not pass one, so existing tests keep working.
  ReminderService get reminderService => reminders ?? ReminderService.instance;

  /// Re-arms a reminder whose scheduling failed, or cancels it when the task no
  /// longer asks for one. The returned result is the platform's real answer.
  Future<ReminderScheduleResult?> retryReminder(ReminderPayload payload) async {
    final service = reminderService;
    await service.init();
    if (_disposed) return null;
    final task = tasks.where((t) => t.id == payload.taskId).firstOrNull;
    final sub = task?.subtasks
        .where((s) => s.id == payload.subtaskId)
        .firstOrNull;
    final when = payload.subtaskId == null ? task?.reminderAt : sub?.reminderAt;
    if (task == null ||
        task.completed ||
        (payload.subtaskId != null && (sub == null || sub.completed)) ||
        when == null) {
      await service.cancelReminder(
        payload.taskId,
        subtaskId: payload.subtaskId,
        userInitiated: true,
      );
      return null;
    }
    return service.scheduleReminder(
      boardId: task.boardId,
      taskId: task.id,
      subtaskId: payload.subtaskId,
      title: sub?.title ?? task.title,
      body: sub?.notesMarkdown ?? task.notesMarkdown,
      triggerAtMs: when,
      // The user asked for this retry, so it opens a new retry generation
      // instead of spending the budget the automatic retries already used.
      userInitiated: true,
    );
  }

  /// Re-issues a cancellation the platform never confirmed.
  Future<ReminderCancelResult?> retryReminderCancellation(
    ReminderPayload payload,
  ) async {
    final service = reminderService;
    await service.init();
    if (_disposed) return null;
    return service.cancelReminder(
      payload.taskId,
      subtaskId: payload.subtaskId,
      userInitiated: true,
    );
  }

  /// Outcome of the most recent startup reminder pass, kept so a failure or a
  /// spent retry budget is never reported as a silent success.
  ReminderReconcileReport? lastReminderReport;

  /// Rebuilds the OS schedule from task data, then finishes reminder work a
  /// previous run could not. Ordering matters: the stored ledger is read first
  /// so a startup pass continues the retry budget the previous run already
  /// spent instead of starting a new generation, and reconciliation must not
  /// re-arm a reminder the fresh pass has already attempted.
  Future<ReminderReconcileReport> reconcileReminders() async {
    final service = reminderService;
    var report = const ReminderReconcileReport();
    try {
      await service.loadPendingJobs();
      if (_disposed) return report;
      await service.rescheduleAllFuture(tasks);
      if (_disposed) return report;
      report = await service.reconcilePending(tasks);
      // The ledger is the only memory a restart can use, so this pass is not
      // finished until its records have been through a completed write.
      await service.flushPendingLedger();
    } catch (_) {
      // Reminder delivery is tracked separately from library persistence; the
      // failure stays visible through scheduleFailures/cancelFailures and the
      // ledger issue notifier.
    }
    lastReminderReport = report;
    return report;
  }

  /// Clears every notification before a full library replace, then rebuilds.
  Future<void> resetAllReminders() async {
    try {
      await reminderService.cancelAll();
    } catch (_) {
      // The rebuild below records per-notification retries for anything left.
    }
    await reconcileReminders();
  }

  /// Generation of the library the platform schedule is allowed to mirror.
  ///
  /// An import publishes reminders only after its batch commits. A newer edit,
  /// a second import, or a rollback bumps this so a cancel/schedule that
  /// started for the previous library cannot land on top of the current one.
  int _reminderEpoch = 0;
  Future<void> _reminderSync = Future.value();
  int _reminderSyncDepth = 0;

  void _onLiveReminderChange() {
    _reminderEpoch++;
    if (_reminderSyncDepth > 0) _enqueueReminderRepair();
  }

  void _enqueueReminderRepair() {
    final epoch = _reminderEpoch;
    _reminderSync = _reminderSync.then(
      (_) => _runReminderSync(epoch, replaceAll: false),
    );
  }

  void _enqueueImportReminderSync({required bool replaceAll}) {
    final epoch = ++_reminderEpoch;
    _reminderSync = _reminderSync.then(
      (_) => _runReminderSync(epoch, replaceAll: replaceAll),
    );
  }

  /// Publishes [epoch]'s task list to the platform. [replaceAll] is the
  /// successful overwrite: it clears the previous library's notifications
  /// first. A repair only cancels reminders the current tasks no longer ask
  /// for, so a spent retry budget is not opened again by cancel-all.
  Future<void> _runReminderSync(int epoch, {required bool replaceAll}) async {
    if (_disposed || epoch != _reminderEpoch) return;
    _reminderSyncDepth++;
    try {
      if (replaceAll) {
        if (epoch != _reminderEpoch) return;
        await reminderService.cancelAll();
      }
      if (_disposed || epoch != _reminderEpoch) return;
      final snapshot = [
        for (final task in _tasks) Task.fromJson(task.toJson()),
      ];
      if (_disposed || epoch != _reminderEpoch) return;
      if (replaceAll) {
        await reminderService.rescheduleAllFuture(snapshot);
      } else {
        await reminderService.alignToTasks(snapshot);
      }
      if (_disposed || epoch != _reminderEpoch) return;
      lastReminderReport = await reminderService.reconcilePending(snapshot);
      if (_disposed || epoch != _reminderEpoch) return;
      await reminderService.flushPendingLedger();
    } catch (_) {
      // Delivery stays visible through scheduleFailures, cancelFailures and
      // the ledger issue. It does not roll the task library back.
    } finally {
      _reminderSyncDepth--;
    }
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
      _prefs = await persistence.open();
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
    _boards = read(
      _kBoards,
      <Board>[],
      (raw) => records(raw, Board.fromJson, (b) => b.id),
      (value) => value.map((b) => b.toJson()).toList(),
    );
    _tasks = read(
      _kTasks,
      <Task>[],
      (raw) => records(raw, Task.fromJson, (task) => task.id),
      (value) => value.map((task) => task.toJson()).toList(),
    );

    if (boards.isEmpty) {
      if (startupDataStates[_kBoards] == StartupDataState.valid) {
        startupDataStates[_kBoards] = StartupDataState.migrated;
      }
      _boards = [
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
    _scheduleItems = read(
      _kSchedule,
      <ScheduleItem>[],
      (raw) {
        if (raw is! List) throw const FormatException('Invalid schedule list');
        final parsed = [
          for (final item in raw)
            ScheduleItem.fromJson(item as Map<String, dynamic>),
        ];
        validateScheduleCollection(
          parsed,
          parentTaskIds: {for (final task in tasks) task.id},
          boardIds: {for (final board in boards) board.id},
        );
        return parsed;
      },
      (value) => value.map((item) => item.toJson()).toList(),
    );
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
    final onboarding = onboardingRaw == null
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
    unawaited(reconcileReminders());
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
          _kSchedule,
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
    _removeOrphanScheduleItems();
    if (!await retryCredentialMigration()) {
      notifyListeners();
      return false;
    }
    _persistAll();
    _applyDeadlinePromotion();
    unawaited(reconcileReminders());
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
    final list = tasks
        .where((task) => task.boardId == activeBoardId)
        .where((task) => !settings.hideCompleted || !task.completed)
        .toList();
    return list;
  }

  List<Task> tasksIn(int quadrant) =>
      visibleTasks.where((task) => task.quadrant == quadrant).toList();

  List<Task> longTermPending() => visibleTasks
      .where((task) => task.isLongTerm && !task.hasSubtasks && !task.completed)
      .toList();

  /// Direct query for completed tasks without copying or synthetic timestamps.
  /// If [boardId] is specified, returns completed tasks on that board;
  /// otherwise returns completed tasks across all boards.
  /// Unaffected by [settings.hideCompleted].
  List<Task> completedTasks({String? boardId}) => tasks
      .where((t) => t.completed && (boardId == null || t.boardId == boardId))
      .toList();

  /// Total number of completed tasks on [boardId] (or across all boards if null).
  int completedTaskCount({String? boardId}) => tasks
      .where((t) => t.completed && (boardId == null || t.boardId == boardId))
      .length;

  // --- today list ---

  /// The Today list: tasks bucketed by planned day and deadline across every
  /// quadrant, on the active board or, with [allBoards], across all of them.
  /// [settings.hideCompleted] does not apply — a completed task never enters a
  /// bucket — and reading this list never changes a quadrant.
  List<TodayGroup> todayGroups({bool allBoards = false, DateTime? now}) =>
      groupForToday(
        tasks.where((task) => allBoards || task.boardId == activeBoardId),
        now: now,
      );

  /// Tasks completed today, under the same board scope as [todayGroups].
  int completedTodayCount({bool allBoards = false}) => tasks
      .where(
        (task) =>
            completedOnDay(task) &&
            (allBoards || task.boardId == activeBoardId),
      )
      .length;

  // --- mutations ---

  void setViewMode(ViewMode mode) {
    if (settings.viewMode == mode) return;
    updateSettings((s) => s..viewMode = mode);
  }

  void toggleViewMode() {
    final next = settings.viewMode == ViewMode.grid
        ? ViewMode.list
        : ViewMode.grid;
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

  void completeOnboarding() {
    hasSeenOnboarding = true;
    _markDirty();
    notifyListeners();
  }

  void resetOnboardingForTest() {
    hasSeenOnboarding = false;
    _markDirty();
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
    final added = newTasks
        .where((task) => boardIds.contains(task.boardId) && seen.add(task.id))
        .toList();
    _tasks.insertAll(0, added);
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final task in added) {
      if (!task.completed &&
          task.reminderAt != null &&
          task.reminderAt! > now) {
        reminderService.scheduleReminder(
          boardId: task.boardId,
          taskId: task.id,
          title: task.title,
          body: task.notesMarkdown,
          triggerAtMs: task.reminderAt!,
        );
      }
      for (final sub in task.subtasks) {
        if (!sub.completed && sub.reminderAt != null && sub.reminderAt! > now) {
          reminderService.scheduleReminder(
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
    int? plannedDate,
  }) => Task(
    id: newId(),
    boardId: activeBoardId,
    title: title,
    quadrant: quadrant,
    isLongTerm: isLongTerm,
    createdAt: _now(),
    deadline: deadline,
    plannedDate: plannedDate,
  );

  void _insertAtFrontOfQuadrant(Task task) {
    final firstTargetIndex = tasks.indexWhere(
      (t) => t.boardId == task.boardId && t.quadrant == task.quadrant,
    );
    if (firstTargetIndex != -1) {
      _tasks.insert(firstTargetIndex, task);
    } else {
      final firstBoardIndex = tasks.indexWhere(
        (t) => t.boardId == task.boardId,
      );
      if (firstBoardIndex != -1) {
        _tasks.insert(firstBoardIndex, task);
      } else {
        _tasks.insert(0, task);
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
    to.plannedDate = from.plannedDate;
    to.subtasks = from.subtasks;
    to.reasoning = from.reasoning;
    to.urgencyMode = from.urgencyMode;
    to.notesMarkdown = from.notesMarkdown;
    to.reminderAt = from.reminderAt;
    to.reminderTimezone = from.reminderTimezone;
    to.completedAt = from.completedAt;
    // Copied, unlike the fields above: a caller's draft list must not stay
    // wired to the stored task after the update returns.
    to.tags = List<String>.from(from.tags);
    to.recoveryPending = from.recoveryPending;
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
      _tasks.removeAt(i);
      _insertAtFrontOfQuadrant(updated);
    } else {
      _tasks[i] = updated;
    }

    final oldSubIds = {for (final s in oldTask.subtasks) s.id};
    final newSubIds = {for (final s in updated.subtasks) s.id};
    for (final removedId in oldSubIds.difference(newSubIds)) {
      reminderService.cancelReminder(updated.id, subtaskId: removedId);
    }

    if (updated.completed) {
      reminderService.cancelReminder(updated.id);
      for (final sub in updated.subtasks) {
        reminderService.cancelReminder(updated.id, subtaskId: sub.id);
      }
    } else {
      if (updated.reminderAt != null && updated.reminderAt! > now) {
        reminderService.scheduleReminder(
          boardId: updated.boardId,
          taskId: updated.id,
          title: updated.title,
          body: updated.notesMarkdown,
          triggerAtMs: updated.reminderAt!,
          // Only a real reminder change is a user request; an unrelated edit
          // must keep spending the budget this reminder already used.
          userInitiated: updated.reminderAt != oldTask.reminderAt,
        );
      } else {
        reminderService.cancelReminder(updated.id);
      }
      for (final sub in updated.subtasks) {
        if (!sub.completed && sub.reminderAt != null && sub.reminderAt! > now) {
          reminderService.scheduleReminder(
            boardId: updated.boardId,
            taskId: updated.id,
            subtaskId: sub.id,
            title: sub.title,
            body: updated.title,
            triggerAtMs: sub.reminderAt!,
            userInitiated: oldSubMap[sub.id]?.reminderAt != sub.reminderAt,
          );
        } else {
          reminderService.cancelReminder(updated.id, subtaskId: sub.id);
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
      reminderService.cancelReminder(existing.id);
      for (final s in existing.subtasks) {
        reminderService.cancelReminder(existing.id, subtaskId: s.id);
      }
    }
    _tasks.removeWhere((t) => t.id == id);
    _removeScheduleForTaskIds({id});
    _saveTasks();
    notifyListeners();
  }

  void moveTask(String id, int quadrant) {
    final i = tasks.indexWhere((t) => t.id == id);
    if (i == -1) return;
    if (tasks[i].quadrant == quadrant) {
      // Same quadrant: do not reorder or invalidate undo.
      return;
    }
    _touchTask(id);
    final oldQuadrant = tasks[i].quadrant;
    final task = Task.fromJson(tasks[i].toJson())..quadrant = quadrant;
    if (isUrgentQuadrant(oldQuadrant) != isUrgentQuadrant(quadrant)) {
      task.urgencyMode = UrgencyMode.manual;
    }
    _tasks.removeAt(i);
    _insertAtFrontOfQuadrant(task);
    _saveTasks();
    notifyListeners();
  }

  /// Moves selected tasks on the active board as one library mutation and one
  /// persisted commit. Tasks already in the target quadrant keep their place.
  int moveTasks(Iterable<String> ids, int quadrant) {
    if (!allQuadrants.contains(quadrant)) {
      throw ArgumentError.value(quadrant, 'quadrant');
    }
    final selectedIds = ids.toSet();
    final moving = _tasks
        .where(
          (task) =>
              selectedIds.contains(task.id) &&
              task.boardId == activeBoardId &&
              task.quadrant != quadrant,
        )
        .toList();
    if (moving.isEmpty) return 0;

    final moved = [
      for (final task in moving)
        Task.fromJson(task.toJson())
          ..quadrant = quadrant
          ..urgencyMode =
              isUrgentQuadrant(task.quadrant) != isUrgentQuadrant(quadrant)
              ? UrgencyMode.manual
              : task.urgencyMode,
    ];
    final movingIds = moving.map((task) => task.id).toSet();
    _tasks.removeWhere((task) => movingIds.contains(task.id));
    for (final task in moved.reversed) {
      _touchTask(task.id);
      _insertAtFrontOfQuadrant(task);
    }
    _saveTasks();
    notifyListeners();
    return moved.length;
  }

  void resetTaskUrgencyMode(String taskId) {
    final i = tasks.indexWhere((t) => t.id == taskId);
    if (i == -1) return;
    final beforeMode = tasks[i].urgencyMode;
    final beforeQuadrant = tasks[i].quadrant;
    tasks[i].urgencyMode = UrgencyMode.auto;
    _applyDeadlinePromotion();
    final current = tasks[i];
    final modeChanged = current.urgencyMode != beforeMode;
    final quadrantChanged = current.quadrant != beforeQuadrant;
    // Promotion already bumps a task whose quadrant changed. A mode-only
    // reset still has to invalidate undo, or moving the mode back to auto
    // would leave the previous snapshot applicable.
    if (modeChanged && !quadrantChanged) _touchTask(taskId);
    _saveTasks();
    notifyListeners();
  }

  /// Plans [taskId] on the civil day of [day], or clears the plan when null.
  /// Nothing else moves: the quadrant, the deadline and the urgency mode keep
  /// their values, because a plan is not a commitment date.
  void setPlannedDay(String taskId, DateTime? day) {
    final i = tasks.indexWhere((t) => t.id == taskId);
    if (i == -1) return;
    final stored = tasks[i];
    final next = plannedDayMs(day);
    if (stored.plannedDate == next) return;
    updateTask(Task.fromJson(stored.toJson())..plannedDate = next);
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

  /// Deep copy of the current library. Callers can edit the copy and pass it
  /// back through a command; the store's tasks, boards, and config stay put.
  StoreSnapshot captureSnapshot() => StoreSnapshot(
    boards: List.unmodifiable([
      for (final board in boards) Board.fromJson(board.toJson()),
    ]),
    tasks: List.unmodifiable([
      for (final task in tasks) Task.fromJson(task.toJson()),
    ]),
    scheduleItems: List.unmodifiable(_scheduleItems),
    aiConfig: _copyConfig(aiConfig),
    settings: AppSettings.fromJson(settings.toJson()),
    activeBoardId: activeBoardId,
    taskRevisions: Map.unmodifiable(Map<String, int>.from(_taskSeq)),
    scheduleRevisions: Map.unmodifiable(Map<String, int>.from(_scheduleSeq)),
  );

  /// Detached config draft for settings edits without mutating live state.
  AIConfig copyAIConfig() => _copyConfig(aiConfig);

  /// Test setup that must not schedule reminders or bump revisions.
  @visibleForTesting
  void debugReplaceTasks(List<Task> next) {
    _tasks
      ..clear()
      ..addAll(next);
  }

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
    reminderService.cancelAllForBoard(boardId, boardTasks);
    final before = tasks.length;
    _tasks.removeWhere((t) => t.boardId == boardId);
    final removedSchedule = _removeScheduleForTaskIds({
      for (final task in boardTasks) task.id,
    });
    final removed = before - tasks.length;
    if (removed > 0 || removedSchedule) {
      _saveTasks();
      notifyListeners();
    }
    return removed;
  }

  void clearQuadrant(int quadrant, {String? boardId}) {
    final bId = boardId ?? activeBoardId;
    bumpBoardEpoch(bId);
    final quadTasks = tasks
        .where((t) => t.boardId == bId && t.quadrant == quadrant)
        .toList();
    reminderService.cancelAllForBoard(bId, quadTasks);
    _tasks.removeWhere((t) => t.boardId == bId && t.quadrant == quadrant);
    _removeScheduleForTaskIds({for (final task in quadTasks) task.id});
    _saveTasks();
    notifyListeners();
  }

  /// Parent checkbox cascade: set self + every subtask to [completed].
  /// Edits a copy so [updateTask] can still see the previous values.
  void setParentCompleted(Task task, bool completed) {
    final i = tasks.indexWhere((t) => t.id == task.id);
    if (i == -1) return;
    final stored = tasks[i];
    final now = DateTime.now().millisecondsSinceEpoch;
    final updated = Task.fromJson(stored.toJson());
    updated.completed = completed;
    updated.completedAt = completed
        ? (stored.completed ? stored.completedAt : now)
        : null;
    for (final sub in updated.subtasks) {
      final wasSub = sub.completed;
      final subAt = sub.completedAt;
      sub.completed = completed;
      sub.completedAt = completed ? (wasSub ? subAt : now) : null;
    }
    updateTask(updated);
  }

  /// Sets one parent's completed flag without cascading to its children.
  /// Search uses this; the matrix card uses [setParentCompleted].
  void setTaskCompleted(String taskId, bool completed) {
    final i = tasks.indexWhere((t) => t.id == taskId);
    if (i == -1) return;
    final stored = tasks[i];
    final updated = Task.fromJson(stored.toJson());
    updated.completed = completed;
    if (!completed) {
      updated.completedAt = null;
    } else if (!stored.completed) {
      updated.completedAt = null;
    }
    updateTask(updated);
  }

  void setSubtaskCompleted(String taskId, String subtaskId, bool completed) {
    final i = tasks.indexWhere((t) => t.id == taskId);
    if (i == -1) return;
    final stored = tasks[i];
    final subIndex = stored.subtasks.indexWhere((s) => s.id == subtaskId);
    if (subIndex == -1) return;
    final updated = Task.fromJson(stored.toJson());
    final sub = updated.subtasks[subIndex];
    final wasCompleted = stored.subtasks[subIndex].completed;
    final previousAt = stored.subtasks[subIndex].completedAt;
    sub.completed = completed;
    if (completed) {
      sub.completedAt = wasCompleted
          ? previousAt
          : DateTime.now().millisecondsSinceEpoch;
    } else {
      sub.completedAt = null;
    }
    updateTask(updated);
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
    reminderService.cancelReminder(task.id);
    for (final s in task.subtasks) {
      reminderService.cancelReminder(task.id, subtaskId: s.id);
    }
    _touchTask(task.id);
    final snapshot = TaskUndoSnapshot.capture(
      actionType: TaskUndoType.delete,
      task: task,
      boardEpoch: boardEpoch(task.boardId),
      originalIndex: i,
      commandSeq: taskSeq(task.id),
      linkedScheduleItems: [
        for (final item in _scheduleItems)
          if (item.taskId == task.id) item,
      ],
    );
    _tasks.removeAt(i);
    _removeScheduleForTaskIds({task.id});
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
  /// 3. A non-zero commandSeq must still match the task revision. Every command
  ///    that changes the task bumps that revision: parent or child edits,
  ///    completion, deletion, a quadrant move (including a move back to the
  ///    original quadrant), an urgency reset that changes mode, and deadline
  ///    promotion that changes quadrant. The whole snapshot is rejected, so an
  ///    old undo cannot overwrite the newer task. A zero seq is a legacy
  ///    snapshot that did not record a revision.
  /// 4. For complete/restore: task must still exist, and its title and quadrant
  ///    must still match the snapshot.
  /// 5. For delete: task must not already exist.
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
      final liveIds = {for (final item in _scheduleItems) item.id};
      if (snapshot.linkedScheduleItems.any(
        (item) => liveIds.contains(item.id),
      )) {
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
        _tasks.insert(insertIndex, restored);
        _scheduleItems.addAll(snapshot.linkedScheduleItems);
        for (final item in snapshot.linkedScheduleItems) {
          _touchSchedule(item.id);
        }
        final now = DateTime.now().millisecondsSinceEpoch;
        if (!restored.completed &&
            restored.reminderAt != null &&
            restored.reminderAt! > now) {
          reminderService.scheduleReminder(
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
            reminderService.scheduleReminder(
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
          reminderService.cancelReminder(current.id);
          for (final sub in current.subtasks) {
            reminderService.cancelReminder(current.id, subtaskId: sub.id);
          }
        } else {
          if (current.reminderAt != null && current.reminderAt! > now) {
            reminderService.scheduleReminder(
              boardId: current.boardId,
              taskId: current.id,
              title: current.title,
              body: current.notesMarkdown,
              triggerAtMs: current.reminderAt!,
            );
          } else {
            reminderService.cancelReminder(current.id);
          }
          for (final sub in current.subtasks) {
            if (!sub.completed &&
                sub.reminderAt != null &&
                sub.reminderAt! > now) {
              reminderService.scheduleReminder(
                boardId: current.boardId,
                taskId: current.id,
                subtaskId: sub.id,
                title: sub.title,
                body: current.title,
                triggerAtMs: sub.reminderAt!,
              );
            } else {
              reminderService.cancelReminder(current.id, subtaskId: sub.id);
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
    final selected = tasks
        .where((t) => ids.contains(t.id) && t.boardId == activeBoardId)
        .toList();
    if (selected.length < 2 || title.trim().isEmpty) {
      throw StateError('Select at least two tasks on the active board');
    }
    final selectedIds = selected.map((t) => t.id).toSet();
    final deadlines = selected.map((t) => t.deadline).whereType<int>().toList()
      ..sort();
    final parent = Task(
      id: newId(),
      boardId: selected.first.boardId,
      title: title,
      quadrant: selected.first.quadrant,
      completed: selected.every((t) => t.completed),
      isLongTerm: selected.any((t) => t.isLongTerm),
      deadline: deadlines.firstOrNull,
      createdAt: _now(),
      urgencyMode: selected.any((t) => t.urgencyMode == UrgencyMode.manual)
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
      reminderService.cancelReminder(t.id);
      for (final s in t.subtasks) {
        reminderService.cancelReminder(t.id, subtaskId: s.id);
      }
    }
    _tasks.removeWhere((t) => selectedIds.contains(t.id));
    _tasks.insert(0, parent);
    for (var i = 0; i < _scheduleItems.length; i++) {
      final item = _scheduleItems[i];
      if (!selectedIds.contains(item.taskId)) continue;
      _scheduleItems[i] = ScheduleItem.fromJson({
        ...item.toJson(),
        'taskId': parent.id,
      });
      _touchSchedule(item.id);
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!parent.completed &&
        parent.reminderAt != null &&
        parent.reminderAt! > now) {
      reminderService.scheduleReminder(
        boardId: parent.boardId,
        taskId: parent.id,
        title: parent.title,
        body: parent.notesMarkdown,
        triggerAtMs: parent.reminderAt!,
      );
    }
    for (final s in parent.subtasks) {
      if (!s.completed && s.reminderAt != null && s.reminderAt! > now) {
        reminderService.scheduleReminder(
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
    _boards.add(board);
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
    reminderService.cancelAllForBoard(id, boardTasks);
    _boards.removeWhere((b) => b.id == id);
    _tasks.removeWhere((t) => t.boardId == id);
    _removeScheduleForTaskIds({for (final task in boardTasks) task.id});
    final independent = _scheduleItems
        .where((item) => item.boardId == id)
        .toList();
    _scheduleItems.removeWhere((item) => item.boardId == id);
    for (final item in independent) {
      _touchSchedule(item.id);
    }
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
    final hadCredentialError = credentialError != null;
    if (_pendingCredentialRollback != null) {
      credentialError = t['credentialStoreError'];
      if (!_disposed) notifyListeners();
      return false;
    }
    aiConfig = _copyConfig(config);
    // Keep the editable value visible while the secure write is pending. No
    // ordinary snapshot includes it; failure restores the confirmed value.
    aiConfig.apiKey = requested;
    _saveConfig();
    if (!_disposed) notifyListeners();
    if (requested == _confirmedCredential &&
        _queuedCredentialWrites == 0 &&
        _credentialImports.isEmpty &&
        credentialError == null) {
      _pendingCredentialValue = null;
      return true;
    }
    _pendingCredentialValue = requested;
    final intent = ++_credentialIntent;
    final wasQueued = _queuedCredentialWrites > 0;
    _queuedCredentialWrites++;
    // Secure writes have their own ordered queue. They may complete while an
    // import's ordinary slot commit is blocked; the import reserves this queue
    // only for its secure write and any necessary rollback.
    final previous = _credentialWrites;
    final result = () async {
      await previous;
      try {
        if (intent != _credentialIntent) return false;
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
        if (intent == _credentialIntent) {
          aiConfig.apiKey = requested;
          credentialError = null;
          _pendingCredentialValue = null;
          // A failed earlier write blocked the ordinary config save. Persist
          // the latest non-secret fields now that the credential is verified.
          if (hadCredentialError) _saveConfig();
        }
        return true;
      } catch (_) {
        if (intent == _credentialIntent) {
          credentialError = t['credentialStoreError'];
          aiConfig.apiKey = _confirmedCredential;
        }
        return false;
      } finally {
        _queuedCredentialWrites--;
        if (!_disposed) notifyListeners();
      }
    }();
    _credentialWrites = result.then((_) {});
    // Restoring the confirmed value while an older write is blocked is an
    // accepted correction. Its durable result is reported by flush().
    if (wasQueued && requested == _confirmedCredential) return true;
    return result;
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
      return _runTransaction(() => _restoreCredential(rollback));
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
      reminderService.rescheduleAllFuture(tasks);
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
      _confirmedCredential = value;
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
    await _drainCommits();
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

  /// Builds the backup file or files for the live library.
  ///
  /// Every file this returns is checked against the same preflight a restore
  /// runs, so a success here is a backup that can actually be read back. When
  /// the library is too large for one file it is split, and when not even a
  /// split can carry it the bundle reports that instead of writing a file the
  /// import gate would later refuse.
  Future<BackupBundle> exportBackup({bool includeCredential = false}) async {
    final document = includeCredential
        ? await exportJsonWithCredential()
        : exportJson();
    return buildBackupBundle(document);
  }

  /// Returns the number of tasks imported. [mode] is 'merge' or 'overwrite'.
  ///
  /// Test-compatibility entry only. The product file import is [applyImport],
  /// which runs the whole transaction on the serial commit owner. This
  /// synchronous helper cannot await, so it preflights, changes memory and
  /// queues its save on that same owner. It never touches the credential
  /// store: an imported key is not adopted here, unlike [applyImport] with
  /// `importCredential`.
  int importData(Map<String, dynamic> json, String mode) {
    final plan = previewImport(json, mode);
    if (plan.conflicts != 0) throw const FormatException('Conflicting IDs');
    _applyImportState(plan);
    _persistAll();
    _enqueueImportReminderSync(replaceAll: plan.mode == 'overwrite');
    return plan.addedTasks;
  }

  ImportPlan previewImport(
    Map<String, dynamic> json,
    String mode, {
    String? targetBoardId,
  }) => ImportPreflight.inspect(
    json,
    mode,
    targetBoardId: targetBoardId,
    currentBoards: boards,
    currentTasks: tasks,
    revision: _dirtyRevision,
  );

  /// Commits one import as the store's only multi-step transaction.
  ///
  /// It runs inside the serial commit owner, so no ordinary command can land
  /// a disk commit in the middle of it. The order inside the transaction is
  /// fixed and is the contract every other commit path relies on:
  ///   1. drain earlier credential writes and reserve the credential queue,
  ///   2. write the credential choice this import carries,
  ///   3. re-derive the plan from its payload against the *live* library, so
  ///      commands accepted while steps 1-2 were running are part of the
  ///      result instead of being overwritten by the old preview,
  ///   4. apply that state to memory with no await in between,
  ///   5. commit exactly one batch built from the applied state, and roll the
  ///      memory back if the batch does not commit.
  ///
  /// Commands are never rejected while an import is in flight: they change
  /// memory immediately and their own commit is queued on the same owner, so
  /// input stays on screen and is saved either by this transaction (merge) or
  /// by the next queued commit.
  Future<SaveResult> applyImport(
    ImportPlan plan, {
    bool importCredential = false,
  }) {
    // Reserve the secure queue when the import is accepted, before any later
    // user edit can enqueue its credential operation.
    final intentAtAcceptance = _credentialIntent;
    final reservation = _CredentialImportReservation(_credentialWrites);
    _credentialWrites = () async {
      await reservation.prior;
      await reservation.gate.future;
    }();
    _credentialImports.add(reservation);
    return _runTransaction(
      () => _commitImportLocked(
        plan,
        importCredential: importCredential,
        intentAtStart: intentAtAcceptance,
        reservation: reservation,
      ),
    ).whenComplete(() => _credentialImports.remove(reservation));
  }

  Future<SaveResult> _commitImportLocked(
    ImportPlan plan, {
    required bool importCredential,
    required int intentAtStart,
    required _CredentialImportReservation reservation,
  }) async {
    late ImportPlan effective;
    var oldCredential = _confirmedCredential;
    var newCredential = oldCredential;
    try {
      await reservation.prior;
      if (_disposed ||
          plan.conflicts != 0 ||
          hasStartupRecovery ||
          credentialError != null) {
        return const SaveResult(false, 0);
      }
      final initial = _rebaseImport(plan);
      if (initial == null || initial.conflicts != 0) {
        return const SaveResult(false, 0);
      }
      oldCredential = _confirmedCredential;
      newCredential = importCredential && initial.hasCredential
          ? initial.aiConfig!.apiKey
          : oldCredential;
      if (newCredential != oldCredential) {
        if (newCredential.isEmpty) {
          await credentialStore.delete();
        } else {
          await credentialStore.write(newCredential);
        }
        if ((await credentialStore.read()) !=
            (newCredential.isEmpty ? null : newCredential)) {
          throw StateError('Credential verification failed');
        }
        _confirmedCredential = newCredential;
      }
      // Commands may have changed the live library while secure storage was
      // pending. The final plan must use that library, as RF02 requires.
      final rebased = _rebaseImport(plan);
      if (rebased == null || rebased.conflicts != 0) {
        if (newCredential != oldCredential &&
            await _restoreCredential(oldCredential)) {
          _confirmedCredential = oldCredential;
        }
        return const SaveResult(false, 0);
      }
      effective = rebased;
    } catch (_) {
      if (newCredential != oldCredential) {
        await _restoreCredential(oldCredential);
      }
      credentialError = t['credentialStoreError'];
      if (!_disposed) notifyListeners();
      return const SaveResult(false, 0);
    } finally {
      reservation.gate.complete();
    }
    final before = captureSnapshot();
    final newerConfig = intentAtStart != _credentialIntent
        ? _copyConfig(aiConfig)
        : null;
    _applyImportState(effective);
    if (newerConfig != null) aiConfig = newerConfig;
    final atCommit = _dirtyRevision;
    final values = _snapshotValues();
    final result = await _saveProtocol!.commit(values);
    lastSaveResult = result;
    if (!result.success) {
      _rollbackImport(before, values);
      if (newCredential != oldCredential) {
        final position = _credentialImports.indexOf(reservation);
        final nextImport =
            position >= 0 && position + 1 < _credentialImports.length
            ? _credentialImports[position + 1]
            : null;
        // The next import already gates subsequent edits. Wait only for edits
        // preceding it; waiting for its gate would deadlock the serial owner.
        final prior = nextImport?.prior ?? _credentialWrites;
        final rollbackGate = nextImport == null ? Completer<void>() : null;
        if (rollbackGate != null) {
          _credentialWrites = () async {
            await prior;
            await rollbackGate.future;
          }();
        }
        try {
          await prior;
          final newerSucceeded =
              intentAtStart != _credentialIntent &&
              _pendingCredentialValue == null &&
              credentialError == null;
          final newerFailed =
              intentAtStart != _credentialIntent && credentialError != null;
          if (!newerSucceeded && await _restoreCredential(oldCredential)) {
            _confirmedCredential = oldCredential;
            if (intentAtStart == _credentialIntent || newerFailed) {
              aiConfig.apiKey = oldCredential;
            }
            if (newerFailed) credentialError = t['credentialStoreError'];
          }
        } finally {
          rollbackGate?.complete();
        }
      }
      persistenceError = t['storageWriteError'];
      if (_dirtyRevision > _savedRevision) _scheduleCommit();
      if (!_disposed) notifyListeners();
      return result;
    }
    _savedValues = values;
    if (intentAtStart == _credentialIntent) {
      aiConfig.apiKey = newCredential;
      credentialError = null;
    }
    // Only the revisions up to the snapshot we just wrote are durable. A
    // command accepted while the batch was committing stays dirty and its
    // own commit is still queued on the owner.
    _savedRevision = atCommit;
    persistenceError = null;
    // The batch is the authority now. Reminders follow this library, not the
    // one that was visible while the slots were still in flight.
    _enqueueImportReminderSync(replaceAll: effective.mode == 'overwrite');
    if (_dirtyRevision > _savedRevision) _scheduleCommit();
    if (!_disposed) notifyListeners();
    return result;
  }

  /// Re-derives [plan] from the payload it was inspected from, against the
  /// live library. Returns null when the payload no longer yields a valid
  /// import for the current state.
  ImportPlan? _rebaseImport(ImportPlan plan) {
    final payload = plan.payload;
    if (payload == null) {
      // Hand-built plans cannot be re-derived. Accept them only when nothing
      // has been accepted since the preview.
      return plan.baseRevision == _dirtyRevision ? plan : null;
    }
    try {
      return ImportPreflight.inspect(
        payload,
        plan.mode,
        targetBoardId: plan.targetBoardId,
        currentBoards: boards,
        currentTasks: tasks,
        revision: _dirtyRevision,
      );
    } catch (_) {
      return null;
    }
  }

  /// Undoes exactly what the import changed after its batch failed to commit.
  ///
  /// The disk still holds [before], so the library must return there — except
  /// for records a command touched afterwards. [atCommit] was captured between
  /// applying the plan and writing the batch, so a record that now differs from
  /// it was changed by such a command and keeps its live form; everything else
  /// falls back to [before]. A command that writes the same bytes the snapshot
  /// already had does not anchor an imported record: there is nothing to tell
  /// it from a record the user never touched.
  ///
  /// Boards and tasks are merged separately, then closed: a kept task brings
  /// back the live board it was accepted onto. A board the user removed is not
  /// put back, and [activeBoardId] is moved onto a board that still exists
  /// when the selection named one this rollback dropped.
  void _rollbackImport(StoreSnapshot before, Map<String, String> atCommit) {
    final liveBoards = [
      for (final board in _boards) Board.fromJson(board.toJson()),
    ];
    final liveTasks = [for (final task in _tasks) Task.fromJson(task.toJson())];
    _boards = _carryPostCommitRecords(
      before: [for (final board in before.boards) board.toJson()],
      live: [for (final board in _boards) board.toJson()],
      committed: atCommit[_kBoards],
    ).map(Board.fromJson).toList();
    _tasks = _carryPostCommitRecords(
      before: [for (final task in before.tasks) task.toJson()],
      live: [for (final task in _tasks) task.toJson()],
      committed: atCommit[_kTasks],
    ).map(Task.fromJson).toList();
    _scheduleItems = _carryPostCommitRecords(
      before: [for (final item in before.scheduleItems) item.toJson()],
      live: [for (final item in _scheduleItems) item.toJson()],
      committed: atCommit[_kSchedule],
    ).map(ScheduleItem.fromJson).toList();
    if (jsonEncode(settings.toJson()) == atCommit[_kSettings]) {
      settings = AppSettings.fromJson(before.settings.toJson());
    }
    // The persisted config never carries the key, so the credential has to be
    // part of deciding whether anything touched the config after the commit.
    if (jsonEncode(aiConfig.toJson(includeCredential: false)) ==
            atCommit[_kConfig] &&
        aiConfig.apiKey == before.aiConfig.apiKey) {
      aiConfig = _copyConfig(before.aiConfig);
    }
    if (activeBoardId == atCommit[_kActiveBoard]) {
      activeBoardId = before.activeBoardId;
    }
    _retainDependenciesOfKeptSchedule(liveTasks, liveBoards);
    _retainDependenciesOfKeptTasks(liveBoards);
    _removeOrphanScheduleItems();
    if (!_boards.any((board) => board.id == activeBoardId)) {
      activeBoardId = _boards.any((board) => board.id == before.activeBoardId)
          ? before.activeBoardId
          : _boards.first.id;
    }
    // The uncommitted import never owned the platform schedule. Re-align to
    // the library that is actually still here, in case an older rebuild is
    // still in flight.
    _enqueueReminderRepair();
  }

  /// Keeps the board a surviving task was accepted onto.
  ///
  /// The copy comes from the live library the command saw. A board that is
  /// already gone from that library was deleted by the user and stays deleted.
  void _retainDependenciesOfKeptTasks(List<Board> liveBoards) {
    final present = {for (final board in _boards) board.id};
    final liveById = {for (final board in liveBoards) board.id: board};
    for (final task in _tasks) {
      if (present.contains(task.boardId)) continue;
      final dependency = liveById[task.boardId];
      if (dependency == null) continue;
      _boards.add(Board.fromJson(dependency.toJson()));
      present.add(dependency.id);
    }
  }

  void _retainDependenciesOfKeptSchedule(
    List<Task> liveTasks,
    List<Board> liveBoards,
  ) {
    final taskIds = {for (final task in _tasks) task.id};
    final liveTaskById = {for (final task in liveTasks) task.id: task};
    final boardIds = {for (final board in _boards) board.id};
    final liveBoardById = {for (final board in liveBoards) board.id: board};
    for (final item in _scheduleItems) {
      final taskId = item.taskId;
      if (taskId != null && !taskIds.contains(taskId)) {
        final task = liveTaskById[taskId];
        if (task != null) {
          _tasks.add(Task.fromJson(task.toJson()));
          taskIds.add(taskId);
        }
      }
      final boardId = item.boardId;
      if (boardId != null && !boardIds.contains(boardId)) {
        final board = liveBoardById[boardId];
        if (board != null) {
          _boards.add(Board.fromJson(board.toJson()));
          boardIds.add(boardId);
        }
      }
    }
  }

  /// Three-way merge over records keyed by id: [committed] is the base, the
  /// [live] records are the changes to keep, [before] is the state to fall back
  /// on for everything the commit itself introduced or rewrote.
  static Iterable<Map<String, dynamic>> _carryPostCommitRecords({
    required List<Map<String, dynamic>> before,
    required List<Map<String, dynamic>> live,
    required String? committed,
  }) {
    final beforeById = {for (final item in before) item['id'] as String: item};
    final liveById = {for (final item in live) item['id'] as String: item};
    final committedById = <String, String>{
      if (committed != null)
        for (final item
            in (jsonDecode(committed) as List).cast<Map<String, dynamic>>())
          item['id'] as String: jsonEncode(item),
    };
    Map<String, dynamic>? kept(String id) {
      final current = liveById[id];
      final unchanged = current == null
          ? !committedById.containsKey(id)
          : jsonEncode(current) == committedById[id];
      return unchanged ? beforeById[id] : current;
    }

    return [
      for (final id in {...beforeById.keys, ...liveById.keys})
        if (kept(id) != null) kept(id)!,
    ];
  }

  void _applyImportState(ImportPlan plan) {
    _dirtyRevision++;
    if (plan.mode == 'overwrite') {
      bumpAllBoardEpochs();
      for (final board in plan.boards) {
        bumpBoardEpoch(board.id);
      }
      for (final item in _scheduleItems) {
        _touchSchedule(item.id);
      }
      // Until v3 file import is implemented, legacy overwrite has no schedule.
      _scheduleItems = [];
    }
    _boards = plan.boards;
    _tasks = plan.tasks;
    settings = plan.settings ?? settings;
    if (plan.aiConfig != null) {
      aiConfig = _copyConfig(plan.aiConfig!);
      aiConfig.apiKey = _confirmedCredential;
    }
    if (plan.mode == 'overwrite') activeBoardId = boards.first.id;
    // This library is not durable yet. Bump the reminder generation so an
    // older rebuild cannot publish it, and do not cancel or schedule anything
    // until the batch commits.
    _reminderEpoch++;
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
          _touchTask(task.id);
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
      // A committed old slot without the optional schedule key is authoritative;
      // never borrow an uncommitted/stale compatibility mirror to fill it.
      final raw = _savedValues != null
          ? _savedValues![key]
          : _prefs.getString(key);
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

  /// Runs [body] as the next job of the serial commit owner. The chain never
  /// completes with an error, so one failed job cannot strand the queue; the
  /// caller still observes the error through the returned future.
  Future<T> _runTransaction<T>(Future<T> Function() body) {
    final previous = _commitGate;
    final response = Completer<T>();
    _commitGate = () async {
      await previous;
      try {
        response.complete(await body());
      } catch (error, stack) {
        response.completeError(error, stack);
      }
    }();
    return response.future;
  }

  /// Records that live state changed and queues a commit. It used to take the
  /// key and its encoded value, which nothing read: `_snapshotValues()` re-derives
  /// every persisted key when the queued commit runs, so encoding here only made
  /// the caller pay for a whole-library `jsonEncode` that was then discarded
  /// (RF09 C1, docs/RF09_SERIALIZATION_NOTES.md).
  void _markDirty() {
    if (!ready || _disposed || hasStartupRecovery || credentialError != null) {
      return;
    }
    _dirtyRevision++;
    _scheduleCommit();
  }

  /// Queues one commit job on the serial owner. The scheduler coalesces every
  /// mutation accepted before that job runs.
  void _scheduleCommit() {
    if (_saveScheduled) return;
    _saveScheduled = true;
    // The job is observed through [flush] and [lastSaveResult], not its own future.
    _runTransaction(() async {
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

  /// Waits until the accepted save, credential, import and reminder work is stable.
  ///
  /// A single await is not enough: a reminder edit accepted while an older
  /// alignment is still running replaces [_reminderSync]. The barrier samples
  /// the queue and the reminder generation together, and it only returns after
  /// a pass in which none of them changed. That pass is not a retry loop; the
  /// exit timeout still bounds the wait, and a failed ledger write is a failed
  /// flush rather than another silent attempt.
  ///
  /// [includeReminderLedger] adds the reminder retry ledger, which is the only
  /// memory a restart has for pending reminder work. The exit barrier uses it so
  /// a lost ledger cannot be reported as a clean shutdown; data flows such as a
  /// backup export keep the library-only contract. The ledger is awaited only
  /// when a write is actually outstanding.
  Future<SaveResult> flush({
    bool includeReminderLedger = false,
    bool waitForReminders = true,
  }) async {
    while (true) {
      final commitBarrier = _commitGate;
      final credentialBarrier = _credentialWrites;
      final reminderBarrier = _reminderSync;
      final reminderEpoch = _reminderEpoch;
      await Future.wait([
        commitBarrier,
        credentialBarrier,
        if (waitForReminders) reminderBarrier,
      ]);
      final ledger =
          waitForReminders &&
              includeReminderLedger &&
              reminderService.hasUnlandedLedgerWrites
          ? await reminderService.flushPendingLedger()
          : null;
      final stable =
          identical(commitBarrier, _commitGate) &&
          identical(credentialBarrier, _credentialWrites) &&
          (!waitForReminders ||
              (identical(reminderBarrier, _reminderSync) &&
                  reminderEpoch == _reminderEpoch));
      if (!stable) continue;
      if (credentialError != null ||
          _pendingCredentialRollback != null ||
          _pendingCredentialValue != null ||
          _credentialMigrationPending ||
          _savedRevision < _dirtyRevision ||
          (ledger?.failed ?? false)) {
        return SaveResult(false, lastSaveResult.revision);
      }
      return lastSaveResult;
    }
  }

  Future<SaveResult> retrySave({
    bool includeReminderLedger = false,
    bool waitForReminders = true,
  }) async {
    if (!ready || hasStartupRecovery) return const SaveResult(false, 0);
    await _drainCommits();
    if (includeReminderLedger && reminderService.hasUnlandedLedgerWrites) {
      final ledger = await reminderService.flushPendingLedger();
      if (ledger.failed && !await reminderService.retryPendingLedger()) {
        // Retrying did not land the ledger, so the barrier still owes the
        // caller a failed result instead of the library-only answer.
        return flush(
          includeReminderLedger: true,
          waitForReminders: waitForReminders,
        );
      }
    }
    if (credentialError != null ||
        _pendingCredentialValue != null ||
        _pendingCredentialRollback != null ||
        _credentialMigrationPending) {
      if (!await retryCredential()) {
        return flush(waitForReminders: waitForReminders);
      }
    }
    _savedRevision = _dirtyRevision;
    // Retry means "write the current state again", so it has to make the store
    // dirty even when no command changed anything since the last batch.
    _markDirty();
    // A credential retry can queue reminder work, so the ledger barrier is
    // re-checked here instead of trusting the pass above.
    return flush(
      includeReminderLedger: includeReminderLedger,
      waitForReminders: waitForReminders,
    );
  }

  Future<void> _drainCommits() async {
    // A completed credential operation may enqueue the config save it could
    // not schedule while secure storage was in an error state.
    while (true) {
      final commitBarrier = _commitGate;
      final credentialBarrier = _credentialWrites;
      await Future.wait([commitBarrier, credentialBarrier]);
      if (identical(commitBarrier, _commitGate) &&
          identical(credentialBarrier, _credentialWrites)) {
        return;
      }
    }
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
    _kSchedule: jsonEncode(scheduleItems.map((item) => item.toJson()).toList()),
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

  // Each of these marks one accepted mutation dirty. They keep their names
  // because callers read them as the per-domain save command, and one bump is
  // enough: the queued commit re-derives all six persisted keys together.
  void _saveTasks() {
    _markDirty();
    _onLiveReminderChange();
  }

  void _saveBoardsMeta() => _markDirty();

  void _saveConfig() => _markDirty();

  void _saveSettings() => _markDirty();

  List<Locale> _resolvePlatformLocales() {
    try {
      return WidgetsBinding.instance.platformDispatcher.locales;
    } catch (_) {
      return const [];
    }
  }
}

int _now() => DateTime.now().millisecondsSinceEpoch;
