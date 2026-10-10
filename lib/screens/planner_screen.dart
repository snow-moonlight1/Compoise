import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n.dart';
import '../models.dart';
import '../planner/planner_block.dart';
import '../planner/planner_date_strip.dart';
import '../planner/planner_day_timeline.dart';
import '../planner/planner_labels.dart';
import '../planner/planner_pinch.dart';
import '../planner/planner_task_pool.dart';
import '../planner/planner_toolbar.dart';
import '../planner/planner_view.dart';
import '../planner/planner_week_view.dart';
import '../planner/schedule_drag.dart';
import '../planner/schedule_edit_session.dart';
import '../planner/schedule_editor.dart';
import '../platform/device_time_zone_controller.dart';
import '../platform/device_time_zone_picker.dart';
import '../schedule_item.dart';
import '../schedule_time.dart';
import '../storage.dart';
import '../ui/platform_ui_policy.dart';
import '../widgets/batch_decompose_sheet.dart';
import '../widgets/input_sheet.dart';
import '../widgets/schedule_layout.dart';
import '../widgets/task_detail_panel.dart';

export '../planner/planner_view.dart';

/// Independently mountable Planner/Schedule surface. Live Store data supports
/// C2 editing; detached snapshots keep C1's read-only behavior.
/// Pass a live Store (or provide one via Provider), or a detached StoreSnapshot.
/// The display zone comes from an injected [DeviceTimeZoneController] (device
/// discovery plus an explicit user choice) or from a fixed [displayTimeZoneId].
/// With neither, the page asks for a zone instead of assuming one. Stored item
/// zones never determine the viewport, and a zone change only re-renders.
/// Mutations use A2 Store commands after review.
class PlannerScreen extends StatefulWidget {
  const PlannerScreen({
    super.key,
    this.displayTimeZoneId,
    this.timeZoneController,
    this.store,
    this.snapshot,
    this.initialDate,
    this.initialView = PlannerView.day,
    this.initialBoardId,
    this.initialTaskId,
    this.startTimeBlock = false,
    this.now,
  }) : assert(store == null || snapshot == null);

  /// Fixed display zone, used when no controller is injected and this page is
  /// not expected to discover the device zone itself.
  final String? displayTimeZoneId;

  /// Device zone discovery and user choice; wins over [displayTimeZoneId].
  final DeviceTimeZoneController? timeZoneController;
  final Store? store;
  final StoreSnapshot? snapshot;
  final ScheduleCivilDate? initialDate;
  final PlannerView initialView;

  /// Null starts with all boards. This is a local view filter, not activeBoardId.
  final String? initialBoardId;

  /// Parent task a new time block is created for.
  final String? initialTaskId;

  /// Opens the editor for that task's new time block once the page can save.
  final bool startTimeBlock;
  final DateTime Function()? now;

  @override
  State<PlannerScreen> createState() => _PlannerScreenState();
}

class _PlannerScreenState extends State<PlannerScreen>
    with SingleTickerProviderStateMixin {
  late ScheduleCivilDate _date;
  late PlannerView _view;
  String? _boardId;
  final _horizontal = ScrollController();
  final _vertical = ScrollController();
  final _pool = DraggableScrollableController();
  final _hover = ValueNotifier<PlannerHover?>(null);
  final _addFocus = FocusNode();
  final _stackKey = GlobalKey();
  final _viewportKey = GlobalKey();
  final _dropKeys = <String, GlobalKey>{};
  bool _editorOpen = false;
  bool _retryingStore = false;
  String? _adjustingId;
  String _dropHint = 'Release to place at {time}.';
  double _poolMin = 0.12;
  Offset? _poolPointer;
  ScheduleDayLayout? _paintedDay;
  List<ScheduleDayLayout> _weekLayouts = const [];
  late final AnimationController _motion;
  double _slideX = 0;
  String? _highlightTaskId;
  int _highlightToken = 0;

  /// Created only when the caller injects no controller, and disposed here.
  DeviceTimeZoneController? _ownedZone;

  /// Effective display zone. Null until the device reports one or the user
  /// picks one, because there is no silent fallback zone.
  String? _zone;
  bool _startedPreselectedBlock = false;

  DeviceTimeZoneController? get _zoneController =>
      widget.timeZoneController ?? _ownedZone;

  bool get _canPrevious =>
      !(_date.year <= 1 && _date.month == 1 && _date.day <= 7);

  bool get _canNext =>
      !(_date.year >= 9999 && _date.month == 12 && _date.day >= 24);

  void _readZone() {
    _zone = _zoneController?.displayIanaId ?? widget.displayTimeZoneId;
  }

  void _onZoneChanged() {
    if (!mounted) return;
    setState(_readZone);
    _armPreselectedBlock();
  }

  /// The task entry may arrive before device discovery finishes, so opening its
  /// editor is re-armed whenever a usable zone appears.
  void _armPreselectedBlock() {
    if (_startedPreselectedBlock ||
        !widget.startTimeBlock ||
        widget.initialTaskId == null ||
        _zone == null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _startPreselectedBlock(),
    );
  }

  ScheduleCivilDate _today() {
    final now = widget.now?.call() ?? DateTime.now();
    if (_zone == null) {
      // Host calendar date, used only as the starting cursor while the user is
      // still choosing a zone. It is never labelled a device zone.
      return ScheduleCivilDate(now.year, now.month, now.day);
    }
    final local = scheduleLocalTime(now.millisecondsSinceEpoch, _zone!);
    return ScheduleCivilDate(local.year, local.month, local.day);
  }

  @override
  void initState() {
    super.initState();
    _motion = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
      value: 1,
    );
    if (widget.timeZoneController == null && widget.displayTimeZoneId == null) {
      // No injected controller and no fixed zone: this page owns device
      // discovery, the change listener and the user choice.
      _ownedZone = DeviceTimeZoneController();
    }
    // Entering the page re-reads the device zone; the cached value renders
    // first and the page rebuilds only if the answer differs.
    _zoneController?.addListener(_onZoneChanged);
    _zoneController?.refresh();
    _readZone();
    _date = widget.initialDate ?? _today();
    _view = widget.initialView;
    _boardId = widget.initialBoardId;
    _armPreselectedBlock();
  }

  @override
  void didUpdateWidget(PlannerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.timeZoneController != widget.timeZoneController) {
      (oldWidget.timeZoneController ?? _ownedZone)?.removeListener(
        _onZoneChanged,
      );
      _zoneController?.addListener(_onZoneChanged);
    }
    // A new controller or a new fixed zone both re-project the same records.
    if (oldWidget.timeZoneController != widget.timeZoneController ||
        oldWidget.displayTimeZoneId != widget.displayTimeZoneId) {
      _readZone();
    }
  }

  @override
  void dispose() {
    _zoneController?.removeListener(_onZoneChanged);
    _ownedZone?.dispose();
    _ownedZone = null;
    _motion.dispose();
    _horizontal.dispose();
    _vertical.dispose();
    _pool.dispose();
    _hover.dispose();
    _addFocus.dispose();
    super.dispose();
  }

  /// The task entry asks for a new block of a named parent task. It waits for a
  /// zone and a writable library, and reports a task that vanished instead of
  /// opening an editor that could not save it.
  Future<void> _startPreselectedBlock() async {
    final taskId = widget.initialTaskId;
    if (taskId == null || _startedPreselectedBlock || !mounted) return;
    final store = widget.store ?? context.read<Store>();
    if (!store.ready || store.hasStartupRecovery || _editorOpen) return;
    if (_zone == null) return;
    _startedPreselectedBlock = true;
    if (!store.tasks.any((task) => task.id == taskId)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(store.t['scheduleTaskMissing']!)));
      return;
    }
    await _revealTask(store, taskId);
  }

  bool _isAfter(ScheduleCivilDate next, ScheduleCivilDate current) =>
      next.year > current.year ||
      (next.year == current.year &&
          (next.month > current.month ||
              (next.month == current.month && next.day > current.day)));

  bool _sameDate(ScheduleCivilDate a, ScheduleCivilDate b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  void _present({PlannerView? view, ScheduleCivilDate? date, double x = 0}) {
    _slideX = x;
    setState(() {
      if (view != null) _view = view;
      if (date != null) _date = date;
    });
    _resetScroll();
    _motion.forward(from: 0);
  }

  void _shift(int days) {
    if (days == 0) return;
    if (days < 0 && !_canPrevious) return;
    if (days > 0 && !_canNext) return;
    _present(date: _date.addDays(days), x: days > 0 ? 0.28 : -0.28);
  }

  void _navigate(int direction) =>
      _shift(direction * (_view == PlannerView.day ? 1 : 7));

  void _setView(PlannerView view) {
    if (_view == view) return;
    _present(view: view, x: view == PlannerView.day ? 0.16 : -0.16);
  }

  /// Pulls the pool up and marks [taskId], or jumps to a block that already
  /// exists. Does not open the schedule form.
  Future<void> _revealTask(Store store, String taskId) async {
    if (!mounted) return;
    ScheduleItem? placed;
    for (final item in store.scheduleItems) {
      if (item.taskId == taskId) {
        placed = item;
        break;
      }
    }
    if (placed != null && _zone != null) {
      final local = scheduleLocalTime(placed.startAt, _zone!);
      _present(
        view: PlannerView.day,
        date: ScheduleCivilDate(local.year, local.month, local.day),
        x: 0.16,
      );
      return;
    }
    setState(() {
      _highlightTaskId = taskId;
      _highlightToken += 1;
    });
  }

  void _resetScroll() {
    if (_vertical.positions.length == 1) _vertical.jumpTo(0);
    if (_horizontal.positions.length == 1) _horizontal.jumpTo(0);
  }

  Future<void> _addPoolTask(Store store, int quadrant) async {
    if (_editorOpen || store.hasStartupRecovery || !store.ready) return;
    setState(() => _editorOpen = true);
    List<Task>? longTerm;
    try {
      final filter = _boardId;
      final boardId =
          filter != null && store.boards.any((board) => board.id == filter)
          ? filter
          : null;
      final sheet = ChangeNotifierProvider<Store>.value(
        value: store,
        child: InputSheet(
          initialMode: store.settings.defaultInputMode,
          quadrant: quadrant,
          boardId: boardId,
        ),
      );
      if (PlatformUiPolicy.of(context).isTouchLayout) {
        longTerm = await showModalBottomSheet<List<Task>>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (_) => sheet,
        );
      } else {
        longTerm = await showDialog<List<Task>>(
          context: context,
          builder: (_) => Dialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 24,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520, maxHeight: 640),
              child: sheet,
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _editorOpen = false);
    }
    if (!mounted || longTerm == null || longTerm.isEmpty) return;
    await showBatchDecomposeSheet(context, longTerm);
  }

  Future<void> _create(Store store, ScheduleCivilDate date) async {
    if (_editorOpen || store.hasStartupRecovery || !store.ready) return;
    setState(() => _editorOpen = true);
    try {
      final session = ScheduleEditSession.create(
        store,
        ScheduleItemKind.event,
        _zone!,
        date,
      );
      final filter = _boardId;
      session.boardId =
          filter != null && store.boards.any((board) => board.id == filter)
          ? filter
          : store.activeBoardId;
      final saved = await showScheduleEditor(context, session);
      if (saved == true && mounted) _savedMessage(store);
    } finally {
      if (mounted) setState(() => _editorOpen = false);
    }
  }

  void _savedMessage(Store store, [String? message]) {
    final height = MediaQuery.sizeOf(context).height;
    final sheet = _pool.isAttached ? _pool.pixels : _poolMin * height;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.fromLTRB(16, 0, 16, sheet + 16),
        content: Text(message ?? store.t['scheduleEditorSaved']!),
      ),
    );
  }

  Future<void> _edit(
    Store store,
    ScheduleItem item,
    ScheduleEditMode mode, {
    int? revision,
    ScheduleWallTime? target,
    bool delete = false,
  }) async {
    if (_editorOpen || store.hasStartupRecovery || !store.ready) return;
    setState(() => _editorOpen = true);
    try {
      final session = ScheduleEditSession.edit(
        store,
        item,
        mode: mode,
        displayZone: _zone!,
        target: target,
        revision: revision,
      );
      final modal = delete
          ? showScheduleDelete(context, session)
          : showScheduleEditor(context, session);
      final saved = await modal;
      if (saved == true && mounted) _savedMessage(store);
    } finally {
      if (mounted) setState(() => _editorOpen = false);
    }
  }

  ScheduleWallTime _wallAt(ScheduleDayLayout day, double y) {
    final local = scheduleLocalTime(_snappedInstant(day, y), _zone!);
    return ScheduleWallTime(
      ScheduleCivilDate(local.year, local.month, local.day),
      hour: local.hour,
      minute: local.minute,
    );
  }

  int _snappedInstant(ScheduleDayLayout day, double y) {
    final elapsed = (y / day.pixelsPerHour * Duration.millisecondsPerHour)
        .floor();
    final quarter = Duration.millisecondsPerMinute * 15;
    return day.window.startAt + (elapsed ~/ quarter) * quarter;
  }

  Widget _drag(
    Store store,
    ScheduleItem item,
    ScheduleEditMode mode,
    Widget child, {
    Key? key,
  }) => LongPressDraggable<ScheduleDragPayload>(
    key: key,
    data: ScheduleDragPayload(item, store.scheduleRevision(item.id), mode),
    maxSimultaneousDrags: _editorOpen ? 0 : 1,
    dragAnchorStrategy: pointerDragAnchorStrategy,
    feedback: Material(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Text(
          store.t[mode == ScheduleEditMode.move
              ? 'scheduleEditorMove'
              : mode == ScheduleEditMode.resizeStart
              ? 'scheduleEditorResizeStart'
              : 'scheduleEditorResizeEnd']!,
        ),
      ),
    ),
    child: child,
  );

  Future<void> _pickDate(Map<String, String> t) async {
    final picked = await showDatePicker(
      context: context,
      helpText: t['scheduleChooseDate'],
      initialDate: DateTime(_date.year, _date.month, _date.day),
      firstDate: DateTime(1),
      lastDate: DateTime(9999, 12, 31),
      builder: (context, child) {
        final scaler = MediaQuery.textScalerOf(
          context,
        ).clamp(maxScaleFactor: 1.1);
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: scaler),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
    if (picked != null && mounted) {
      final next = ScheduleCivilDate(picked.year, picked.month, picked.day);
      if (_sameDate(next, _date)) return;
      _present(date: next, x: _isAfter(next, _date) ? 0.22 : -0.22);
    }
  }

  Future<void> _pickBoard(StoreSnapshot data, Map<String, String> t) async {
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t['scheduleBoardFilter']!),
        scrollable: true,
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final choice in [
                ('', t['allBoards']!),
                for (final board in data.boards) (board.id, board.name),
              ])
                RadioListTile<String>(
                  key: ValueKey('schedule-board-${choice.$1}'),
                  value: choice.$1,
                  groupValue: _boardId ?? '',
                  title: Text(choice.$2),
                  onChanged: (value) => Navigator.pop(context, value),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t['close']!),
          ),
        ],
      ),
    );
    if (selected != null && mounted) {
      setState(() => _boardId = selected.isEmpty ? null : selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.snapshot != null) return _buildData(widget.snapshot!);
    final store = widget.store ?? context.watch<Store>();
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final t = store.t;
        if (!store.ready) {
          return Scaffold(body: Center(child: Text(t['scheduleLoading']!)));
        }
        if (store.hasStartupRecovery) {
          return Scaffold(body: Center(child: Text(t['scheduleRecovery']!)));
        }
        return _buildData(store.captureSnapshot(), liveStore: store);
      },
    );
  }

  Widget _buildData(StoreSnapshot data, {Store? liveStore}) {
    final t = dictOf(data.settings.language);
    _dropHint = t['scheduleDropHint']!;
    final zone = _zone;
    // Without a usable device zone and without a user choice, the page states
    // the problem instead of drawing a grid in an assumed zone.
    if (zone == null) return _zoneRequiredScaffold(t);
    final scale = math.max(
      1.0,
      MediaQuery.textScalerOf(context).scale(14) / 14,
    );
    final boardId = data.boards.any((board) => board.id == _boardId)
        ? _boardId
        : null;
    final boardName = boardId == null
        ? null
        : data.boards.firstWhere((board) => board.id == boardId).name;
    final filterName = boardName ?? t['allBoards']!;
    final entries = scheduleEntries(
      items: data.scheduleItems,
      tasks: data.tasks,
      boards: data.boards,
      boardId: boardId,
    );
    final monday = _date.addDays(
      1 - DateTime.utc(_date.year, _date.month, _date.day).weekday,
    );
    final week = [for (var day = 0; day < 7; day++) monday.addDays(day)];
    final selected = scheduleDateLabel(_date);
    final layouts = [
      for (final date in week)
        ScheduleDayLayout(
          date: date,
          timeZoneId: zone,
          entries: entries,
          pixelsPerHour: 96 * scale,
          minimumItemHeight:
              (_adjustingId != null && scheduleDateLabel(date) == selected
                  ? 150
                  : 60) *
              scale,
        ),
    ];
    _weekLayouts = layouts;
    _paintedDay = layouts.firstWhere(
      (day) => scheduleDateLabel(day.date) == selected,
    );
    final zoneLabel =
        '${_zoneController?.followsDeviceZone ?? false ? t['scheduleZoneDevice'] : t['scheduleDisplayZone']}: $zone';
    final linked = {
      for (final item in data.scheduleItems)
        if (item.taskId != null) item.taskId!,
    };
    final tasks = [
      for (final task in data.tasks)
        if (!task.completed &&
            !linked.contains(task.id) &&
            (boardId == null || task.boardId == boardId))
          task,
    ]..sort((a, b) => a.title.compareTo(b.title));

    Widget blockFor(ScheduleDayLayout day, SchedulePlacement placement) {
      return PlannerBlock(
        placement: placement,
        dateLabel: scheduleDateLabel(day.date),
        zone: zone,
        t: t,
        liveStore: liveStore,
        compact: _view == PlannerView.week,
        adjusting: _adjustingId == placement.entry.item.id,
        onOpen: () => _openDetail(placement.entry.item.id, data, t, liveStore),
        onHandle: (mode) {
          final store = liveStore;
          if (store == null) return;
          _edit(store, placement.entry.item, mode);
        },
        drag: (mode, child, {key}) {
          final store = liveStore;
          if (store == null) return child;
          return _drag(store, placement.entry.item, mode, child, key: key);
        },
      );
    }

    return Scaffold(
      body: SafeArea(
        child: FocusTraversalGroup(
          policy: ReadingOrderTraversalPolicy(),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final poolMin = (72 / math.max(constraints.maxHeight, 1))
                  .clamp(0.08, 0.2)
                  .toDouble();
              _poolMin = poolMin;
              return Stack(
                key: _stackKey,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      PlannerToolbar(
                        t: t,
                        dateLabel: _view == PlannerView.day
                            ? plannerDayTitle(
                                _date,
                                data.settings.language,
                                t,
                              )
                            : plannerWeekTitle(
                                week.first,
                                week.last,
                                data.settings.language,
                              ),
                        view: _view,
                        canPrevious: _canPrevious,
                        canNext: _canNext,
                        zoneLabel: zoneLabel,
                        filterLabel: '${t['scheduleBoardFilter']}: $filterName',
                        onPrevious: () => _navigate(-1),
                        onNext: () => _navigate(1),
                        onPickDate: () => _pickDate(t),
                        onToday: () {
                          final today = _today();
                          if (_sameDate(today, _date)) return;
                          _present(
                            date: today,
                            x: _isAfter(today, _date) ? 0.22 : -0.22,
                          );
                        },
                        onView: _setView,
                        onFilter: () => _pickBoard(data, t),
                        onZone: _zoneController == null
                            ? null
                            : () => _chooseZone(_zoneController!, t),
                      ),
                      if (liveStore == null)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            t['scheduleReadOnly']!,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      if (liveStore?.persistenceError != null)
                        Semantics(
                          liveRegion: true,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Text(t['scheduleUnsaved']!),
                          ),
                        ),
                      if (liveStore?.persistenceError != null)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            key: const ValueKey('schedule-persistence-retry'),
                            onPressed: _retryingStore
                                ? null
                                : () async {
                                    setState(() => _retryingStore = true);
                                    try {
                                      await liveStore!.retrySave(
                                        waitForReminders: false,
                                      );
                                    } finally {
                                      if (mounted) {
                                        setState(() => _retryingStore = false);
                                      }
                                    }
                                  },
                            child: Text(t['scheduleEditorRetry']!),
                          ),
                        ),
                      if (_adjustingId != null && liveStore != null)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            key: const ValueKey('schedule-hide-handles'),
                            onPressed: () =>
                                setState(() => _adjustingId = null),
                            child: Text(t['scheduleEditorHideHandles']!),
                          ),
                        ),
                      Expanded(
                        child: ClipRect(
                          child: AnimatedBuilder(
                            animation: _motion,
                            builder: (context, child) {
                              final turned = Curves.easeOutCubic.transform(
                                _motion.value,
                              );
                              return FractionalTranslation(
                                key: const ValueKey('schedule-motion'),
                                translation: Offset(
                                  _slideX * (1 - turned),
                                  0,
                                ),
                                child: Opacity(
                                  opacity: (0.45 + 0.55 * turned).clamp(0, 1),
                                  child: child,
                                ),
                              );
                            },
                            child: Column(
                              children: [
                                if (_view == PlannerView.day)
                                  PlannerDateStrip(
                                    monday: monday,
                                    selected: _date,
                                    marked: {
                                      for (final day in layouts)
                                        if (day.placements.isNotEmpty)
                                          scheduleDateLabel(day.date),
                                    },
                                    t: t,
                                    language: data.settings.language,
                                    onSelect: (date) {
                                      if (_sameDate(date, _date)) return;
                                      _present(
                                        date: date,
                                        x: _isAfter(date, _date)
                                            ? 0.22
                                            : -0.22,
                                      );
                                    },
                                    onWeek: (direction) =>
                                        _shift(direction * 7),
                                  ),
                                Expanded(
                                  child: KeyedSubtree(
                                    key: _viewportKey,
                                    child: PlannerPinch(
                            onPinchIn: _view == PlannerView.day
                                ? () => _setView(PlannerView.week)
                                : null,
                            onPinchOut: _view == PlannerView.week
                                ? () => _setView(PlannerView.day)
                                : null,
                            child: _view == PlannerView.day
                                ? PlannerDayTimeline(
                                    day: _paintedDay!,
                                    scale: scale,
                                    vertical: _vertical,
                                    horizontal: _horizontal,
                                    moreTemplate: t['scheduleMoreCount']!,
                                    nowLabel: t['scheduleNow']!,
                                    hover: _hover,
                                    now: widget.now?.call() ?? DateTime.now(),
                                    onScheduleDrop: liveStore == null
                                        ? null
                                        : (payload, dy) => _edit(
                                            liveStore,
                                            payload.item,
                                            payload.mode,
                                            revision: payload.revision,
                                            target: _wallAt(_paintedDay!, dy),
                                          ),
                                    onPoolMove: _setHoverFromContent,
                                    onPoolAccept: liveStore == null
                                        ? null
                                        : (taskId, dy) {
                                            final day = _paintedDay;
                                            if (day == null) return;
                                            _hover.value = null;
                                            _placeTask(
                                              liveStore,
                                              taskId,
                                              _wallAt(day, dy),
                                            );
                                          },
                                    block: (placement) =>
                                        blockFor(_paintedDay!, placement),
                                  )
                                : PlannerWeekView(
                                    days: layouts,
                                    today: _today(),
                                    scale: scale,
                                    vertical: _vertical,
                                    t: t,
                                    onOpenDay: (date) => _present(
                                      view: PlannerView.day,
                                      date: date,
                                      x: 0.16,
                                    ),
                                    onWeek: (direction) =>
                                        _shift(direction * 7),
                                    bottomInset:
                                        poolMin * constraints.maxHeight,
                                    dropKey: _dropKey,
                                    onScheduleDrop: liveStore == null
                                        ? null
                                        : (payload, date) => _dropOnWeekDay(
                                            liveStore,
                                            payload,
                                            date,
                                          ),
                                    block: blockFor,
                                  ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  PlannerTaskPool(
                    controller: _pool,
                    minSize: poolMin,
                    tasks: tasks,
                    t: t,
                    zone: zone,
                    writable: liveStore != null,
                    addFocus: _addFocus,
                    addEnabled: !_editorOpen,
                    boardLabel:
                        '${t['scheduleBoardShort']}: $filterName',
                    onBoard: () => _pickBoard(data, t),
                    onAddToQuadrant: liveStore == null
                        ? null
                        : (quadrant) => _addPoolTask(liveStore, quadrant),
                    highlightTaskId: _highlightTaskId,
                    highlightToken: _highlightToken,
                    onOpenTask: liveStore == null
                        ? null
                        : (task) => showTaskEditSheet(
                            context,
                            task,
                            onScheduleTime: (taskId) =>
                                _revealTask(liveStore, taskId),
                          ),
                    onAdd: liveStore == null
                        ? () {}
                        : () => _create(liveStore, _date),
                    onDragStarted: (_) {
                      if (_pool.isAttached) {
                        _pool.animateTo(
                          _poolMin,
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOut,
                        );
                      }
                    },
                    onDragUpdate: (_, global) {
                      _poolPointer = global;
                      _autoScrollFromGlobal(global);
                    },
                    onDragEnd: (task, details) {
                      final store = liveStore;
                      final point = _poolPointer ?? details.offset;
                      final hover = _hover.value;
                      _poolPointer = null;
                      _hover.value = null;
                      if (store == null || details.wasAccepted) return;
                      if (_overSheet(point)) return;
                      if (_view == PlannerView.day && hover != null) {
                        final day = _paintedDay;
                        if (day == null) return;
                        _placeTask(store, task.id, _wallAt(day, hover.top + 1));
                        return;
                      }
                      _finishPoolDrop(store, task, point, hover);
                    },
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  GlobalKey _dropKey(String label) =>
      _dropKeys.putIfAbsent(label, GlobalKey.new);

  bool _overSheet(Offset global) {
    final box = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached || !box.hasSize) return false;
    final local = box.globalToLocal(global);
    final sheet = _pool.isAttached ? _pool.pixels : _poolMin * box.size.height;
    return local.dy >= box.size.height - sheet &&
        local.dy <= box.size.height &&
        local.dx >= 0 &&
        local.dx <= box.size.width;
  }

  void _autoScroll(double localY, double height) {
    if (!_vertical.hasClients) return;
    final sheet = _pool.isAttached ? _pool.pixels : 0.0;
    final bottom = height - math.min(sheet, height * 0.45);
    final delta = localY < 36
        ? -24.0
        : localY > bottom - 36
        ? 24.0
        : 0.0;
    if (delta == 0) return;
    final next = (_vertical.offset + delta).clamp(
      0.0,
      _vertical.position.maxScrollExtent,
    );
    if (next != _vertical.offset) _vertical.jumpTo(next);
  }

  Future<void> _finishPoolDrop(
    Store store,
    Task task,
    Offset global,
    PlannerHover? hover,
  ) async {
    if (_overSheet(global)) return;
    if (_view == PlannerView.week) {
      final date = _dateUnder(global);
      if (date == null) return;
      ScheduleDayLayout? layout;
      for (final day in _weekLayouts) {
        if (scheduleDateLabel(day.date) == scheduleDateLabel(date)) {
          layout = day;
        }
      }
      if (layout == null || _editorOpen) return;
      final suggested = _freeStart(layout);
      setState(() => _editorOpen = true);
      final picked = await showTimePicker(
        context: context,
        initialTime: TimeOfDay(
          hour: suggested.hour,
          minute: suggested.minute,
        ),
      );
      if (mounted) setState(() => _editorOpen = false);
      if (picked == null || !mounted) return;
      var minute = ((picked.minute + 7) ~/ 15) * 15;
      var hour = picked.hour;
      if (minute >= 60) {
        minute = 0;
        hour = (hour + 1) % 24;
      }
      await _placeTask(
        store,
        task.id,
        ScheduleWallTime(date, hour: hour, minute: minute),
      );
      return;
    }
    final day = _paintedDay;
    if (day == null) return;
    final box = _viewportKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached || !box.hasSize) return;
    final local = box.globalToLocal(global);
    final y = (_vertical.hasClients ? _vertical.offset : 0) + local.dy;
    final slot = (y < 0 || y >= day.axisHeight)
        ? (hover == null ? null : hover.top + 1)
        : (hover == null ? y : hover.top + 1);
    if (slot == null) return;
    _placeTask(store, task.id, _wallAt(day, slot));
  }

  void _autoScrollFromGlobal(Offset global) {
    final box = _viewportKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached || !box.hasSize) return;
    final local = box.globalToLocal(global);
    if (local.dy < 0 || local.dy > box.size.height) return;
    _autoScroll(local.dy, box.size.height);
  }

  void _setHoverFromContent(double y) {
    final day = _paintedDay;
    if (_view != PlannerView.day || day == null || _zone == null) {
      _hover.value = null;
      return;
    }
    if (y < 0 || y >= day.axisHeight) {
      _hover.value = null;
      return;
    }
    final snapped = _snappedInstant(day, y);
    if (snapped < day.window.startAt || snapped >= day.window.endAt) {
      _hover.value = null;
      return;
    }
    final end = snapped + const Duration(hours: 1).inMilliseconds;
    final startLabel = scheduleAxisLabel(snapped, _zone!);
    _hover.value = PlannerHover(
      top:
          (snapped - day.window.startAt) /
          Duration.millisecondsPerHour *
          day.pixelsPerHour,
      height: day.pixelsPerHour,
      label: '$startLabel – ${scheduleAxisLabel(end, _zone!)}',
      hint: plannerFilled(_dropHint, {'time': startLabel}),
    );
  }

  ScheduleCivilDate? _dateUnder(Offset global) {
    for (final entry in _dropKeys.entries) {
      final box =
          entry.value.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.attached || !box.hasSize) continue;
      final local = box.globalToLocal(global);
      if (local.dx < 0 ||
          local.dy < 0 ||
          local.dx > box.size.width ||
          local.dy > box.size.height) {
        continue;
      }
      final parts = entry.key.split('-');
      if (parts.length != 3) continue;
      return ScheduleCivilDate(
        int.parse(parts[0]),
        int.parse(parts[1]),
        int.parse(parts[2]),
      );
    }
    return null;
  }

  ScheduleWallTime _freeStart(ScheduleDayLayout day) {
    const length = Duration(hours: 1);
    final lengthMs = length.inMilliseconds;
    final quarter = const Duration(minutes: 15).inMilliseconds;
    bool free(int start) {
      final end = start + lengthMs;
      if (end > day.window.endAt) return false;
      for (final placement in day.placements) {
        if (start < placement.slice.endAt && end > placement.slice.startAt) {
          return false;
        }
      }
      return true;
    }

    var cursor = day.window.startAt;
    final nine = wallTimeCandidates(
      ScheduleWallTime(day.date, hour: 9, minute: 0),
      _zone!,
    );
    if (nine.isNotEmpty &&
        nine.first.instantMs >= day.window.startAt &&
        nine.first.instantMs + lengthMs <= day.window.endAt) {
      cursor = nine.first.instantMs;
    }
    for (
      var instant = cursor;
      instant + lengthMs <= day.window.endAt;
      instant += quarter
    ) {
      if (free(instant)) return _wallFromInstant(instant);
    }
    for (var instant = day.window.startAt; instant < cursor; instant += quarter) {
      if (free(instant)) return _wallFromInstant(instant);
    }
    return _wallFromInstant(cursor);
  }

  ScheduleWallTime _wallFromInstant(int instant) {
    final local = scheduleLocalTime(instant, _zone!);
    return ScheduleWallTime(
      ScheduleCivilDate(local.year, local.month, local.day),
      hour: local.hour,
      minute: local.minute,
    );
  }

  /// A pool drop keeps the existing review path. An empty overlap list is saved
  /// immediately; anything ambiguous opens the editor instead of writing blind.
  Future<void> _placeTask(
    Store store,
    String taskId,
    ScheduleWallTime start,
  ) async {
    if (_editorOpen || store.hasStartupRecovery || !store.ready || !mounted) {
      return;
    }
    if (!store.tasks.any((task) => task.id == taskId)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(store.t['scheduleTaskMissing']!)));
      return;
    }
    setState(() => _editorOpen = true);
    try {
      final session = ScheduleEditSession.create(
        store,
        ScheduleItemKind.timeBlock,
        _zone!,
        start.date,
        suggestedStart: start,
      );
      session.taskId = taskId;
      var openEditor = false;
      try {
        final endMs =
            resolveWallTime(start, _zone!) +
            const Duration(hours: 1).inMilliseconds;
        final end = _wallFromInstant(endMs);
        session.end.date = scheduleDateLabel(end.date);
        session.end.time =
            '${end.hour.toString().padLeft(2, '0')}:'
            '${end.minute.toString().padLeft(2, '0')}';
        session.end.offset = null;
        final review = session.review();
        if (review.overlaps.isEmpty) {
          final result = await session.submit(review);
          if (!mounted) return;
          if (result == ScheduleSubmitResult.saved) {
            _savedMessage(store);
            return;
          }
          if (result == ScheduleSubmitResult.unsaved) {
            if (mounted) _savedMessage(store, store.t['scheduleEditorUnsaved']);
            return;
          }
        }
        openEditor = true;
      } on ScheduleTimeException {
        openEditor = true;
      } on FormatException {
        if (mounted) _savedMessage(store, store.t['scheduleEditorInvalid']);
        return;
      }
      if (!openEditor || !mounted) return;
      final saved = await showScheduleEditor(context, session);
      if (saved == true && mounted) _savedMessage(store);
    } finally {
      if (mounted) setState(() => _editorOpen = false);
    }
  }

  void _dropOnWeekDay(
    Store store,
    ScheduleDragPayload payload,
    ScheduleCivilDate date,
  ) {
    final instant = payload.mode == ScheduleEditMode.resizeEnd
        ? payload.item.endAt
        : payload.item.startAt;
    final local = scheduleLocalTime(instant, _zone!);
    _edit(
      store,
      payload.item,
      payload.mode,
      revision: payload.revision,
      target: ScheduleWallTime(
        date,
        hour: local.hour,
        minute: local.minute,
        second: local.second,
        millisecond: local.millisecond,
      ),
    );
  }

  /// Shown while no zone can be used. It names the reason the device identity
  /// failed and offers the IANA picker; nothing is displayed in a made-up zone.
  Widget _zoneRequiredScaffold(Map<String, String> t) {
    final controller = _zoneController;
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    t['scheduleTitle']!,
                    style: theme.textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    scheduleZoneProblemText(
                      t,
                      problem: controller?.problem,
                      identity: controller?.deviceIdentity,
                    ),
                    key: const ValueKey('schedule-zone-required'),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    t['scheduleZoneHint']!,
                    style: theme.textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    key: const ValueKey('schedule-zone-choose'),
                    onPressed: controller == null
                        ? null
                        : () => _chooseZone(controller, t),
                    icon: const Icon(Icons.public),
                    label: Text(t['scheduleZoneChoose']!),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Records a user-chosen display zone on the controller. The choice is a view
  /// setting only: it never touches a stored record.
  Future<void> _chooseZone(
    DeviceTimeZoneController controller,
    Map<String, String> t,
  ) async {
    final chosen = await showScheduleZonePicker(
      context,
      t: t,
      current: controller.displayIanaId,
      deviceIanaId: controller.deviceIanaId,
      deviceIdentity: controller.deviceIdentity,
      problem: controller.problem,
    );
    if (chosen == null || !mounted) return;
    controller.chooseIana(chosen);
    if (!mounted) return;
    _armPreselectedBlock();
  }

  Future<void> _openDetail(
    String id,
    StoreSnapshot snapshot,
    Map<String, String> t,
    Store? liveStore,
  ) async {
    // Keep the actual grid focus across the detail -> editor/delete route chain.
    // The intermediate detail button is disposed before the editor closes.
    final origin = FocusManager.instance.primaryFocus;
    ScheduleItem? chosenItem;
    int? chosenRevision;
    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        Widget detail() {
          final current = liveStore?.captureSnapshot() ?? snapshot;
          final entry = scheduleEntries(
            items: current.scheduleItems,
            tasks: current.tasks,
            boards: current.boards,
          ).where((entry) => entry.item.id == id).firstOrNull;
          final theme = Theme.of(context);
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.85,
              ),
              child: SingleChildScrollView(
                key: const ValueKey('schedule-detail'),
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: entry == null
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t['scheduleUnavailable']!),
                          Text(t['scheduleUnavailable']!),
                          const SizedBox(height: 12),
                          TextButton(
                            key: const ValueKey('schedule-detail-close'),
                            onPressed: () => Navigator.pop(context),
                            child: Text(t['close']!),
                          ),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.title,
                            style: theme.textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          Text(plannerEntryLabel(entry, t)),
                          Text('${t['scheduleDisplayZone']}: ${_zone!}'),
                          Text(
                            '${t['scheduleStart']}: ${scheduleInstantLabel(entry.item.startAt, _zone!)}',
                          ),
                          Text(
                            '${t['scheduleEnd']}: ${scheduleInstantLabel(entry.item.endAt, _zone!)}',
                          ),
                          Text(
                            '${t['scheduleRecordedZone']}: ${entry.item.timeZoneId}',
                          ),
                          Text(
                            '${t['scheduleStart']}: ${scheduleInstantLabel(entry.item.startAt, entry.item.timeZoneId)}',
                          ),
                          Text(
                            '${t['scheduleEnd']}: ${scheduleInstantLabel(entry.item.endAt, entry.item.timeZoneId)}',
                          ),
                          Text(
                            '${t['scheduleElapsed']}: '
                            '${Duration(milliseconds: entry.item.endAt - entry.item.startAt)}',
                          ),
                          if (liveStore == null) Text(t['scheduleReadOnly']!),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            children: [
                              if (liveStore != null &&
                                  !liveStore.hasStartupRecovery) ...[
                                TextButton(
                                  key: const ValueKey('schedule-detail-edit'),
                                  onPressed: () {
                                    chosenItem = entry.item;
                                    chosenRevision = current
                                        .scheduleRevisionFor(id);
                                    Navigator.pop(context, 'edit');
                                  },
                                  child: Text(t['scheduleEditorEdit']!),
                                ),
                                PopupMenuButton<String>(
                                  key: const ValueKey('schedule-detail-actions'),
                                  tooltip: t['scheduleEditorMore'],
                                  itemBuilder: (_) => [
                                    for (final choice in [
                                      ('move', 'scheduleEditorMove'),
                                      (
                                        'resizeStart',
                                        'scheduleEditorResizeStart',
                                      ),
                                      ('resizeEnd', 'scheduleEditorResizeEnd'),
                                      ('handles', 'scheduleEditorHandles'),
                                      ('delete', 'scheduleEditorDelete'),
                                    ])
                                      PopupMenuItem(
                                        value: choice.$1,
                                        child: Text(t[choice.$2]!),
                                      ),
                                  ],
                                  onSelected: (action) {
                                    chosenItem = entry.item;
                                    chosenRevision = current
                                        .scheduleRevisionFor(id);
                                    Navigator.pop(context, action);
                                  },
                                  icon: const Icon(Icons.more_horiz),
                                ),
                              ],
                              TextButton(
                                key: const ValueKey('schedule-detail-close'),
                                onPressed: () => Navigator.pop(context),
                                child: Text(t['close']!),
                              ),
                            ],
                          ),
                        ],
                      ),
              ),
            ),
          );
        }

        return liveStore == null
            ? detail()
            : ListenableBuilder(
                listenable: liveStore,
                builder: (_, _) => detail(),
              );
      },
    );
    if (!mounted) return;
    if (action == 'handles') {
      setState(() => _adjustingId = id);
    } else if (action != null && liveStore != null && chosenItem != null) {
      await _edit(
        liveStore,
        chosenItem!,
        switch (action) {
          'move' => ScheduleEditMode.move,
          'resizeStart' => ScheduleEditMode.resizeStart,
          'resizeEnd' => ScheduleEditMode.resizeEnd,
          _ => ScheduleEditMode.edit,
        },
        revision: chosenRevision,
        delete: action == 'delete',
      );
    }
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final removed =
          liveStore != null &&
          !liveStore.scheduleItems.any((item) => item.id == id);
      if (!removed && origin?.context != null && origin!.canRequestFocus) {
        origin.requestFocus();
      } else if (liveStore != null) {
        _addFocus.requestFocus();
        final addContext = _addFocus.context;
        if (addContext != null) {
          Scrollable.ensureVisible(
            addContext,
            duration: const Duration(milliseconds: 150),
          );
        }
      }
    });
    // A read-only dialog may close without another frame being scheduled.
    WidgetsBinding.instance.scheduleFrame();
  }
}

/// Opens the schedule for the live library. Every entry point uses this so the
/// zone handling and the C2 review/save commands stay the only paths in.
Future<void> openPlannerScreen(
  BuildContext context, {
  Store? store,
  String? taskId,
  bool startTimeBlock = false,
}) => Navigator.of(context, rootNavigator: true).push(
  MaterialPageRoute<void>(
    builder: (_) => PlannerScreen(
      store: store,
      initialTaskId: taskId,
      startTimeBlock: startTimeBlock,
    ),
  ),
);
