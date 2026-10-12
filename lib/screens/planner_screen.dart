import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../l10n.dart';
import '../models.dart';
import '../planner/planner_block.dart';
import '../planner/planner_date_strip.dart';
import '../planner/planner_detail_card.dart';
import '../planner/planner_drag_feedback.dart';
import '../planner/planner_guide.dart';
import '../planner/planner_guide_flag.dart';
import '../planner/planner_day_swipe.dart';
import '../planner/planner_day_timeline.dart';
import '../planner/planner_labels.dart';
import '../planner/planner_pinch.dart';
import '../planner/planner_skin.dart';
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
    this.autoGuide = false,
    this.embedded = false,
    this.active = true,
    this.focusToken = 0,
    this.onLeave,
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

  /// Shows the first-visit guide once. Off for embedded and test mounts.
  final bool autoGuide;

  /// A main tab of the home page: a peer of the task board, so no back arrow.
  final bool embedded;

  /// False while the page is mounted but hidden (another home tab is shown);
  /// the back key then belongs to that tab.
  final bool active;

  /// Bumped by the host to focus [initialTaskId] again on a mounted page.
  final int focusToken;

  /// Embedded page: back with nothing left to close asks the host to leave.
  final VoidCallback? onLeave;
  final DateTime Function()? now;

  @override
  State<PlannerScreen> createState() => _PlannerScreenState();
}

class _PlannerScreenState extends State<PlannerScreen>
    with SingleTickerProviderStateMixin {
  late ScheduleCivilDate _date;
  late PlannerView _view;
  String? _boardId;
  final _vertical = ScrollController();
  final _pool = DraggableScrollableController();
  final _hover = ValueNotifier<PlannerHover?>(null);
  final _itemPointer = PlannerDragPointer();
  final _addFocus = FocusNode();
  final _stackKey = GlobalKey();
  final _viewportKey = GlobalKey();
  final _dropKeys = <String, GlobalKey>{};
  bool _editorOpen = false;
  bool _retryingStore = false;
  String? _selectedId;
  String _dropHint = 'Release to place at {time}.';
  double _poolMin = 0.12;
  Offset? _poolPointer;
  Offset? _tapDown;
  Duration _tapAt = Duration.zero;
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
    _pool.addListener(_poolMoved);
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollToDefault();
      _maybeGuide();
    });
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
    if (oldWidget.focusToken != widget.focusToken) {
      _startedPreselectedBlock = false;
      _armPreselectedBlock();
    }
  }

  @override
  void dispose() {
    _zoneController?.removeListener(_onZoneChanged);
    _ownedZone?.dispose();
    _ownedZone = null;
    _motion.dispose();
    _vertical.dispose();
    _pool.removeListener(_poolMoved);
    _pool.dispose();
    _hover.dispose();
    _itemPointer.dispose();
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
      _fail(store.t['scheduleTaskMissing']!);
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
    _selectedId = null;
    _resetScroll();
    if (MediaQuery.disableAnimationsOf(context)) {
      _motion.value = 1;
    } else {
      _motion.forward(from: 0);
    }
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scrollToDefault();
    });
  }

  /// A day opens near the morning (or an hour before now, for today) instead
  /// of at midnight, so the first screen already shows useful hours.
  void _scrollToDefault() {
    if (_vertical.positions.length != 1) return;
    if (_view == PlannerView.week) {
      _vertical.jumpTo(0);
      return;
    }
    final scale = math.max(
      1.0,
      MediaQuery.textScalerOf(context).scale(14) / 14,
    );
    var hour = 7;
    if (_sameDate(_date, _today())) {
      final now = widget.now?.call() ?? DateTime.now();
      final local = _zone == null
          ? now
          : scheduleLocalTime(now.millisecondsSinceEpoch, _zone!);
      hour = math.max(0, local.hour - 1);
    }
    var target = hour * 96.0 * scale;
    final placements = _paintedDay?.placements ?? const <SchedulePlacement>[];
    if (placements.isNotEmpty) {
      // Never hide the first item of the day above the fold.
      final first = placements.map((p) => p.top).reduce(math.min);
      target = math.min(target, math.max(0.0, first - 48 * scale));
    }
    _vertical.jumpTo(
      target.clamp(0.0, _vertical.position.maxScrollExtent).toDouble(),
    );
  }

  /// Failure message: one at a time, gone after ~4 s or on the close icon, no
  /// undo, floating above the pool bar and the selection bar. While a dialog is
  /// up its own inline text carries the error instead.
  void _fail(String message) {
    if (!mounted || _editorOpen) return;
    final height = MediaQuery.sizeOf(context).height;
    final sheet = _docked
        ? 0.0
        : _pool.isAttached
        ? _pool.pixels
        : _poolMin * height;
    final bar = _selectedId == null ? 0.0 : 64.0;
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        key: const ValueKey('schedule-error'),
        behavior: SnackBarBehavior.floating,
        showCloseIcon: true,
        duration: const Duration(seconds: 4),
        margin: EdgeInsets.fromLTRB(16, 0, 16, sheet + bar + 12),
        content: Text(message),
      ),
    );
  }

  bool _foldingPool = false;
  bool _poolOpen = false;

  /// Folds the pool to its bar: eased, quick, and instant under "reduce motion".
  Future<void> _foldPool() {
    if (MediaQuery.disableAnimationsOf(context)) {
      _pool.jumpTo(_poolMin);
      return Future<void>.value();
    }
    return _pool.animateTo(
      _poolMin,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  /// Expanding the pool drops the selection, so only one of them is ever up.
  void _poolMoved() {
    final open = _pool.isAttached && _pool.size > _poolMin + 0.02;
    if (open != _poolOpen && mounted && !_foldingPool) {
      setState(() => _poolOpen = open);
    }
    if (_foldingPool || _selectedId == null || !_pool.isAttached) return;
    if (_pool.size > _poolMin + 0.02) setState(() => _selectedId = null);
  }

  void _deselect() {
    if (_selectedId != null) setState(() => _selectedId = null);
  }

  /// Tap on a block: select it (round handles on both edges plus the detail
  /// panel). The pool folds down so the panel has room, and the block is kept
  /// clear of the panel.
  void _selectItem(String id) {
    setState(() => _selectedId = id);
    if (_pool.isAttached && _pool.size > _poolMin + 0.02) {
      _foldingPool = true;
      _foldPool().whenComplete(() => _foldingPool = false);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealSelected());
  }

  void _revealSelected() {
    final day = _paintedDay;
    final id = _selectedId;
    if (!mounted || day == null || id == null || _view != PlannerView.day) {
      return;
    }
    if (!_vertical.hasClients) return;
    final box = _viewportKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final placement = day.placements
        .where((p) => p.entry.item.id == id)
        .firstOrNull;
    if (placement == null) return;
    final viewport = box.size.height;
    // Space the detail panel and the folded pool take at the bottom.
    final covered = 72 + 64.0;
    final top = placement.top - plannerHandleReach - 8;
    final bottom = placement.top + placement.height + plannerHandleReach + 8;
    final offset = _vertical.offset;
    double? next;
    if (top < offset) {
      next = top;
    } else if (bottom > offset + viewport - covered) {
      next = math.min(bottom - (viewport - covered), top);
    }
    if (next == null) return;
    final clamped = next
        .clamp(0.0, _vertical.position.maxScrollExtent)
        .toDouble();
    if (MediaQuery.disableAnimationsOf(context)) {
      _vertical.jumpTo(clamped);
    } else {
      _vertical.animateTo(
        clamped,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _maybeGuide() async {
    if (!widget.autoGuide || widget.snapshot != null) return;
    if (await PlannerGuideFlags.seen(PlannerGuideFlags.guideKey)) return;
    if (!mounted) return;
    final t = dictOf((widget.store ?? context.read<Store>()).settings.language);
    await showPlannerGuide(context, t);
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

  ScheduleItem _withTimes(ScheduleItem item, int startAt, int endAt) =>
      item.kind == ScheduleItemKind.timeBlock
      ? ScheduleItem.timeBlock(
          id: item.id,
          taskId: item.taskId!,
          startAt: startAt,
          endAt: endAt,
          timeZoneId: item.timeZoneId,
        )
      : ScheduleItem.event(
          id: item.id,
          title: item.title!,
          taskId: item.taskId,
          boardId: item.boardId,
          startAt: startAt,
          endAt: endAt,
          timeZoneId: item.timeZoneId,
        );

  /// Applies a finished drag. [minutes] is already snapped to 15 minutes.
  Future<void> _applyChange(
    Store store,
    ScheduleItem item,
    ScheduleEditMode mode,
    int minutes,
  ) async {
    if (store.hasStartupRecovery || !store.ready) {
      _fail(store.t['scheduleRecovery']!);
      return;
    }
    final delta = minutes * Duration.millisecondsPerMinute;
    const min = 15 * Duration.millisecondsPerMinute;
    final start = switch (mode) {
      ScheduleEditMode.move => item.startAt + delta,
      ScheduleEditMode.resizeStart => math.min(
        item.startAt + delta,
        item.endAt - min,
      ),
      _ => item.startAt,
    };
    final end = switch (mode) {
      ScheduleEditMode.move => item.endAt + delta,
      ScheduleEditMode.resizeEnd => math.max(
        item.endAt + delta,
        item.startAt + min,
      ),
      _ => item.endAt,
    };
    await _replaceTimes(store, item, start, end);
  }

  Future<void> _replaceTimes(
    Store store,
    ScheduleItem item,
    int start,
    int end,
  ) async {
    final revision = store.scheduleRevision(item.id);
    final ScheduleItem updated;
    try {
      updated = _withTimes(item, start, end);
    } on FormatException {
      _fail(store.t['scheduleEditorInvalid']!);
      return;
    }
    bool changed;
    try {
      changed = store.updateScheduleItem(updated, expectedRevision: revision);
    } on StateError {
      _fail(store.t['scheduleEditorStale']!);
      return;
    } on FormatException {
      _fail(store.t['scheduleEditorInvalid']!);
      return;
    }
    if (!changed) {
      _fail(store.t['scheduleEditorStale']!);
      return;
    }
    final result = await store.flush(waitForReminders: false);
    if (!mounted) return;
    if (!result.success) {
      _fail(store.t['scheduleEditorUnsaved']!);
    }
  }

  /// Opens the plain edit form for [item].
  Future<void> _editItem(Store store, ScheduleItem item) async {
    if (_editorOpen || store.hasStartupRecovery || !store.ready) return;
    setState(() => _editorOpen = true);
    try {
      final session = ScheduleEditSession.edit(
        store,
        item,
        displayZone: _zone!,
        revision: store.scheduleRevision(item.id),
      );
      await showScheduleEditor(context, session);
    } finally {
      if (mounted) setState(() => _editorOpen = false);
    }
  }

  /// Deletes after one centered confirmation.
  Future<void> _deleteItem(Store store, ScheduleItem item) async {
    if (store.hasStartupRecovery || !store.ready) return;
    final revision = store.scheduleRevision(item.id);
    final ok = await showScheduleDeleteConfirm(context, store.t);
    if (ok != true || !mounted) return;
    if (!store.deleteScheduleItem(item.id, expectedRevision: revision)) {
      _fail(store.t['scheduleDeleteFailed']!);
      return;
    }
    setState(() => _selectedId = null);
    final result = await store.flush(waitForReminders: false);
    if (mounted && !result.success) _fail(store.t['scheduleDeleteFailed']!);
  }

  /// New event from the pool's "+": opens the plain form with a free hour.
  Future<void> _create(
    Store store,
    ScheduleCivilDate date, {
    ScheduleWallTime? at,
  }) async {
    if (_editorOpen || store.hasStartupRecovery || !store.ready) return;
    setState(() => _editorOpen = true);
    try {
      final day = _paintedDay;
      final start = at ?? (day == null ? null : _freeStart(day));
      final session = ScheduleEditSession.create(
        store,
        ScheduleItemKind.event,
        _zone!,
        date,
        suggestedStart: start,
      );
      if (start == null) {
        session.start.time = '09:00';
      }
      final endMs =
          resolveWallTime(
            ScheduleWallTime(
              date,
              hour: int.parse(session.start.time.substring(0, 2)),
              minute: int.parse(session.start.time.substring(3, 5)),
            ),
            _zone!,
          ) +
          const Duration(hours: 1).inMilliseconds;
      final end = _wallFromInstant(endMs);
      session.end.date = scheduleDateLabel(end.date);
      session.end.time =
          '${end.hour.toString().padLeft(2, '0')}:'
          '${end.minute.toString().padLeft(2, '0')}';
      final filter = _boardId;
      session.boardId =
          filter != null && store.boards.any((board) => board.id == filter)
          ? filter
          : store.activeBoardId;
      await showScheduleEditor(context, session);
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

  /// Week-list blocks are dragged to another day with the long-press draggable.
  Widget _drag(
    Store store,
    ScheduleItem item,
    String title,
    ScheduleEditMode mode,
    Widget child, {
    Key? key,
    Size? size,
  }) {
    final data = ScheduleDragPayload(
      item,
      store.scheduleRevision(item.id),
      mode,
    );
    // Same look and size as the label; the original stays behind, faded.
    final feedback = PlannerDragFeedback(
      pointer: _itemPointer,
      size: size ?? const Size(160, 40),
      child: Material(
        type: MaterialType.transparency,
        child: SizedBox(
          width: size?.width ?? 160,
          height: size?.height ?? 40,
          child: child,
        ),
      ),
    );
    final ghost = Opacity(opacity: 0.38, child: child);
    void moved(DragUpdateDetails details) =>
        _itemPointer.update(details.globalPosition);
    final desktop = PlatformUiPolicy.of(context).isDesktop;
    final touch = LongPressDraggable<ScheduleDragPayload>(
      key: desktop ? null : key,
      data: data,
      maxSimultaneousDrags: _editorOpen ? 0 : 1,
      dragAnchorStrategy: _itemPointer.anchor,
      onDragUpdate: moved,
      feedback: feedback,
      childWhenDragging: ghost,
      child: child,
    );
    if (!desktop) return touch;
    // Desktop mouse: press and drag right away.
    return PlannerMouseDraggable<ScheduleDragPayload>(
      key: key,
      data: data,
      maxSimultaneousDrags: _editorOpen ? 0 : 1,
      dragAnchorStrategy: _itemPointer.anchor,
      onDragUpdate: moved,
      feedback: feedback,
      childWhenDragging: ghost,
      child: touch,
    );
  }

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
    final inner = _buildBody(context);
    // Back closes the top-most thing first: selection, then the open pool,
    // then (embedded) returns to the task board, then leaves.
    return PopScope(
      canPop:
          !widget.active ||
          (!widget.embedded && _selectedId == null && !_poolOpen),
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_selectedId != null) {
          setState(() => _selectedId = null);
        } else if (_poolOpen && _pool.isAttached) {
          _foldPool();
        } else {
          widget.onLeave?.call();
        }
      },
      child: PlatformUiPolicy.of(context).isDesktop && widget.active
          ? _keys(inner)
          : inner,
    );
  }

  Store? get _liveStore =>
      widget.snapshot != null ? null : widget.store ?? context.read<Store>();

  /// Desktop keyboard: arrows move a day/week, T today, D/W switch view,
  /// Delete removes the selected item (after the usual confirmation), Esc
  /// clears the selection, Ctrl+N creates an item.
  Widget _keys(Widget child) {
    void delete() {
      final store = _liveStore;
      final id = _selectedId;
      if (store == null || id == null || _editorOpen) return;
      final item = store.scheduleItems.where((i) => i.id == id).firstOrNull;
      if (item != null) _deleteItem(store, item);
    }

    void create() {
      final store = _liveStore;
      if (store != null) _create(store, _date);
    }

    void guarded(VoidCallback action) {
      if (_editorOpen) return;
      action();
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
            guarded(() => _navigate(-1)),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
            guarded(() => _navigate(1)),
        const SingleActivator(LogicalKeyboardKey.keyT): () => guarded(_goToday),
        const SingleActivator(LogicalKeyboardKey.keyD): () =>
            guarded(() => _setView(PlannerView.day)),
        const SingleActivator(LogicalKeyboardKey.keyW): () =>
            guarded(() => _setView(PlannerView.week)),
        const SingleActivator(LogicalKeyboardKey.delete): delete,
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_selectedId != null) _deselect();
        },
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): create,
      },
      child: Focus(
        key: const ValueKey('schedule-keys'),
        autofocus: true,
        child: child,
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
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

  Offset? _lastClick;
  Duration _lastClickAt = Duration.zero;

  /// Desktop: a mouse double click on an empty part of the day timeline
  /// creates an item at that quarter hour. Touch never does this, and a plain
  /// listener keeps every other gesture as it was.
  Widget _doubleClickCreate(Store? store, double scale, Widget child) {
    if (store == null) return child;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (e) {
        if (e.kind != PointerDeviceKind.mouse ||
            e.buttons != kPrimaryMouseButton) {
          return;
        }
        final last = _lastClick;
        final quick =
            last != null &&
            e.timeStamp - _lastClickAt < const Duration(milliseconds: 400) &&
            (e.position - last).distance < 8;
        _lastClick = quick ? null : e.position;
        _lastClickAt = e.timeStamp;
        if (quick) _createAt(store, e.position, scale);
      },
      child: child,
    );
  }

  void _createAt(Store store, Offset global, double scale) {
    final day = _paintedDay;
    final box = _viewportKey.currentContext?.findRenderObject() as RenderBox?;
    if (day == null || box == null || !box.hasSize || _editorOpen) return;
    final local = box.globalToLocal(global);
    // Left of the hour labels is not the grid.
    if (local.dx < plannerPageMargin + 44 * scale) return;
    final y = (_vertical.hasClients ? _vertical.offset : 0) + local.dy;
    if (y < 0 || y >= day.axisHeight) return;
    final onBlock = day.placements.any(
      (p) => y >= p.top && y <= p.top + p.height,
    );
    if (onBlock) return;
    _create(store, _date, at: _wallAt(day, y));
  }

  /// Right click on a block: edit or delete.
  Future<void> _blockMenu(Store store, ScheduleItem item, Offset at) async {
    final t = store.t;
    _selectItem(item.id);
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        at & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          key: const ValueKey('schedule-menu-edit'),
          value: 'edit',
          child: Text(t['scheduleEditorEdit']!),
        ),
        PopupMenuItem(
          key: const ValueKey('schedule-menu-delete'),
          value: 'delete',
          child: Text(t['scheduleEditorDelete']!),
        ),
      ],
    );
    if (!mounted) return;
    if (choice == 'edit') _editItem(store, item);
    if (choice == 'delete') _deleteItem(store, item);
  }

  /// Day: jump to today; week: to this week. The view mode stays.
  void _goToday() {
    final today = _today();
    _present(date: today, x: _isAfter(today, _date) ? 0.22 : -0.22);
  }

  /// Whether the last layout put the pool in a side panel.
  bool _docked = false;

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
          minimumItemHeight: 48 * scale,
        ),
    ];
    _weekLayouts = layouts;
    _paintedDay = layouts.firstWhere(
      (day) => scheduleDateLabel(day.date) == selected,
    );
    final zoneLabel =
        '${_zoneController?.followsDeviceZone ?? false ? t['scheduleZoneDevice'] : t['scheduleDisplayZone']}: $zone';
    final scheduledIds = {
      for (final item in data.scheduleItems)
        if (item.taskId != null) item.taskId!,
    };
    final tasks = plannerPoolTasks(data.tasks, boardId: boardId);
    final desktop = PlatformUiPolicy.of(context).isDesktop;
    final todayFab = _view == PlannerView.day
        ? !_sameDate(_today(), _date)
        : !week.any((d) => _sameDate(d, _today()));
    final selectedEntry = _selectedId == null
        ? null
        : entries.where((e) => e.item.id == _selectedId).firstOrNull;
    if (_selectedId != null && selectedEntry == null) {
      // The item vanished (deleted, undone or edited elsewhere).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _selectedId != null) setState(() => _selectedId = null);
      });
    }

    Widget blockFor(ScheduleDayLayout day, SchedulePlacement placement) {
      final item = placement.entry.item;
      final concurrent = day.placements
          .where(
            (other) =>
                other.entry.item.id != item.id &&
                scheduleIntervalsOverlap(
                  other.slice.startAt,
                  other.slice.endAt,
                  placement.slice.startAt,
                  placement.slice.endAt,
                ),
          )
          .length;
      return PlannerBlock(
        placement: placement,
        dateLabel: scheduleDateLabel(day.date),
        zone: zone,
        t: t,
        writable: liveStore != null,
        selected: _selectedId == item.id,
        pixelsPerHour: day.pixelsPerHour,
        concurrent: concurrent,
        compact: _view == PlannerView.week,
        dayStart: day.window.startAt,
        dayEnd: day.window.endAt,
        onTap: () {
          final store = liveStore;
          if (_selectedId == item.id && store != null) {
            _editItem(store, item);
            return;
          }
          _selectItem(item.id);
        },
        onChange: (mode, minutes) {
          final store = liveStore;
          if (store == null) return;
          _applyChange(store, item, mode, minutes);
        },
        onContextMenu: liveStore == null
            ? null
            : (at) => _blockMenu(liveStore, item, at),
        scrollOffset: () => _vertical.hasClients ? _vertical.offset : 0.0,
        onDragGlobal: _autoScrollFromGlobal,
        drag: (mode, child, {key, size}) {
          final store = liveStore;
          if (store == null) return child;
          return _drag(
            store,
            item,
            placement.entry.title,
            mode,
            child,
            key: key,
            size: size,
          );
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
              final docked = desktop && constraints.maxWidth >= 900;
              _docked = docked;
              final bottomPad = docked ? 0.0 : poolMin * constraints.maxHeight;
              final Widget content =
                  // Taps on empty content fold an opened pool. A plain
                  // listener: it never joins the gesture arena, so blocks,
                  // handles, swipes and drags behave exactly as before.
                  Listener(
                    behavior: HitTestBehavior.translucent,
                    onPointerDown: (e) {
                      _tapDown = _poolOpen ? e.position : null;
                      _tapAt = e.timeStamp;
                    },
                    onPointerMove: (e) {
                      if (_tapDown != null &&
                          (e.position - _tapDown!).distance > 12) {
                        _tapDown = null;
                      }
                    },
                    onPointerUp: (e) {
                      final down = _tapDown;
                      _tapDown = null;
                      if (down == null || !_poolOpen || !_pool.isAttached) {
                        return;
                      }
                      if (e.timeStamp - _tapAt >
                          const Duration(milliseconds: 300)) {
                        return;
                      }
                      if (_highlightTaskId != null) {
                        setState(() => _highlightTaskId = null);
                      }
                      _foldPool();
                    },
                    child: Column(
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
                          filterLabel:
                              '${t['scheduleBoardFilter']}: $filterName',
                          onPrevious: () => _navigate(-1),
                          onNext: () => _navigate(1),
                          onPickDate: () => _pickDate(t),
                          onView: _setView,
                          onFilter: () => _pickBoard(data, t),
                          onZone: _zoneController == null
                              ? null
                              : () => _chooseZone(_zoneController!, t),
                          onBack: !widget.embedded && Navigator.canPop(context)
                              ? () => Navigator.maybePop(context)
                              : null,
                          onGuide: () =>
                              showPlannerGuide(context, t, markSeen: false),
                          onToday: desktop ? _goToday : null,
                          todayInView: !todayFab,
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
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
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
                                          setState(
                                            () => _retryingStore = false,
                                          );
                                        }
                                      }
                                    },
                              child: Text(t['scheduleEditorRetry']!),
                            ),
                          ),
                        // A short window (landscape phone) keeps the room for the
                        // grid; the date picker and swipes still move between days.
                        if (_view == PlannerView.day &&
                            MediaQuery.sizeOf(context).height >= 480)
                          PlannerDateStrip(
                            monday: monday,
                            selected: _date,
                            marked: _markedDays(entries, zone),
                            t: t,
                            language: data.settings.language,
                            onSelect: (date) {
                              if (_sameDate(date, _date)) return;
                              _present(
                                date: date,
                                x: _isAfter(date, _date) ? 0.22 : -0.22,
                              );
                            },
                            onWeek: (direction) => _shift(direction * 7),
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
                                            ? PlannerDaySwipe(
                                                onSwipe: _shift,
                                                child: _doubleClickCreate(
                                                  desktop ? liveStore : null,
                                                  scale,
                                                  PlannerDayTimeline(
                                                    day: _paintedDay!,
                                                    scale: scale,
                                                    vertical: _vertical,
                                                    nowLabel: t['scheduleNow']!,
                                                    hover: _hover,
                                                    now:
                                                        widget.now?.call() ??
                                                        DateTime.now(),
                                                    selectedId: _selectedId,
                                                    emptyLabel:
                                                        entries.isEmpty ||
                                                            _paintedDay!
                                                                .placements
                                                                .isEmpty
                                                        ? t['scheduleEmptyHint']
                                                        : null,
                                                    onGridTap: (_) =>
                                                        _deselect(),
                                                    onPoolMove:
                                                        _setHoverFromContent,
                                                    onPoolAccept:
                                                        liveStore == null
                                                        ? null
                                                        : (taskId, dy) {
                                                            final day =
                                                                _paintedDay;
                                                            if (day == null) {
                                                              return;
                                                            }
                                                            _hover.value = null;
                                                            _placeTask(
                                                              liveStore,
                                                              taskId,
                                                              _wallAt(day, dy),
                                                            );
                                                          },
                                                    block: (placement) =>
                                                        blockFor(
                                                          _paintedDay!,
                                                          placement,
                                                        ),
                                                  ),
                                                ),
                                              )
                                            : GestureDetector(
                                                behavior:
                                                    HitTestBehavior.translucent,
                                                onTap: _deselect,
                                                child: PlannerWeekView(
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
                                                  bottomInset: bottomPad,
                                                  dropKey: _dropKey,
                                                  onScheduleDrop:
                                                      liveStore == null
                                                      ? null
                                                      : (payload, date) =>
                                                            _dropOnWeekDay(
                                                              liveStore,
                                                              payload,
                                                              date,
                                                            ),
                                                  block: blockFor,
                                                ),
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
                  );
              final Widget pool = PlannerTaskPool(
                docked: docked,
                controller: _pool,
                minSize: poolMin,
                tasks: tasks,
                scheduledIds: scheduledIds,
                t: t,
                zone: zone,
                writable: liveStore != null,
                addFocus: _addFocus,
                addEnabled: !_editorOpen,
                boardLabel: boardId != null && data.boards.length > 1
                    ? filterName
                    : null,
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
                  if (_selectedId != null) {
                    setState(() => _selectedId = null);
                  }
                  if (_pool.isAttached) _foldPool();
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
              );
              return Stack(
                key: _stackKey,
                children: [
                  if (docked)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: content),
                        SizedBox(width: plannerDockWidth, child: pool),
                      ],
                    )
                  else ...[
                    content,
                    pool,
                  ],
                  if (selectedEntry != null && !_editorOpen)
                    Positioned(
                      left: 12,
                      right: docked ? plannerDockWidth + 12 : 12,
                      bottom: bottomPad + 8,
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 520),
                          child: PlannerDetailCard(
                            entry: selectedEntry,
                            zone: zone,
                            language: data.settings.language,
                            t: t,
                            writable: liveStore != null,
                            onEdit: () =>
                                _editItem(liveStore!, selectedEntry.item),
                            onDelete: () =>
                                _deleteItem(liveStore!, selectedEntry.item),
                          ),
                        ),
                      ),
                    ),
                  if (!desktop &&
                      todayFab &&
                      selectedEntry == null &&
                      !_poolOpen)
                    Positioned(
                      right: 22,
                      bottom: bottomPad + 22,
                      child: _TodayButton(
                        key: const ValueKey('schedule-today'),
                        label: t['scheduleTodayShort']!,
                        tooltip: t['scheduleBackToday']!,
                        onPressed: _goToday,
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// Every local day that has an item, for the dots under the date strip.
  Set<String> _markedDays(List<ScheduleEntry> entries, String zone) {
    final days = <String>{};
    for (final entry in entries) {
      final a = scheduleLocalTime(entry.item.startAt, zone);
      // An item ending exactly at midnight does not touch the next day.
      final b = scheduleLocalTime(entry.item.endAt - 1, zone);
      var day = ScheduleCivilDate(a.year, a.month, a.day);
      final last = scheduleDateLabel(ScheduleCivilDate(b.year, b.month, b.day));
      for (var i = 0; i < 62; i++) {
        final label = scheduleDateLabel(day);
        days.add(label);
        if (label == last) break;
        day = day.addDays(1);
      }
    }
    return days;
  }

  GlobalKey _dropKey(String label) =>
      _dropKeys.putIfAbsent(label, GlobalKey.new);

  bool _overSheet(Offset global) {
    final box = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached || !box.hasSize) return false;
    final local = box.globalToLocal(global);
    if (_docked) {
      return local.dx >= box.size.width - plannerDockWidth &&
          local.dx <= box.size.width &&
          local.dy >= 0 &&
          local.dy <= box.size.height;
    }
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
        initialTime: TimeOfDay(hour: suggested.hour, minute: suggested.minute),
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
      final box = entry.value.currentContext?.findRenderObject() as RenderBox?;
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
    for (
      var instant = day.window.startAt;
      instant < cursor;
      instant += quarter
    ) {
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

  /// A pool drop creates the schedule item straight away. Overlap is allowed:
  /// the new item sits beside the others and a soft message offers undo.
  Future<void> _placeTask(
    Store store,
    String taskId,
    ScheduleWallTime start,
  ) async {
    if (_editorOpen || store.hasStartupRecovery || !store.ready || !mounted) {
      return;
    }
    if (!store.tasks.any((task) => task.id == taskId)) {
      _fail(store.t['scheduleTaskMissing']!);
      return;
    }
    final ScheduleItem item;
    try {
      final startAt = resolveWallTime(start, _zone!);
      item = ScheduleItem.timeBlock(
        id: newId(),
        taskId: taskId,
        startAt: startAt,
        endAt: startAt + const Duration(hours: 1).inMilliseconds,
        timeZoneId: _zone!,
      );
    } on ScheduleTimeException {
      _fail(store.t['scheduleEditorGap']!);
      return;
    }
    try {
      store.addScheduleItem(item);
    } on FormatException {
      _fail(store.t['scheduleDropFailed']!);
      return;
    } on StateError {
      _fail(store.t['scheduleDropFailed']!);
      return;
    }
    final result = await store.flush(waitForReminders: false);
    if (!mounted) return;
    if (!result.success) {
      _fail(store.t['scheduleEditorUnsaved']!);
    }
  }

  /// Moves a week-list block to another day, keeping its clock time and length.
  void _dropOnWeekDay(
    Store store,
    ScheduleDragPayload payload,
    ScheduleCivilDate date,
  ) {
    final item = payload.item;
    final local = scheduleLocalTime(item.startAt, _zone!);
    try {
      final start = resolveWallTime(
        ScheduleWallTime(
          date,
          hour: local.hour,
          minute: local.minute,
          second: local.second,
          millisecond: local.millisecond,
        ),
        _zone!,
      );
      _replaceTimes(store, item, start, start + item.endAt - item.startAt);
    } on ScheduleTimeException {
      _fail(store.t['scheduleEditorGap']!);
    }
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
      // Same board as the task page, so both pages count the same tasks.
      initialBoardId: store?.activeBoardId,
      autoGuide: true,
    ),
  ),
);

/// Round "today" button, bottom right; grows in unless motion is reduced.
/// Width of the side task pool on a wide desktop window.
const double plannerDockWidth = 340;

class _TodayButton extends StatefulWidget {
  const _TodayButton({
    super.key,
    required this.label,
    required this.tooltip,
    required this.onPressed,
  });

  final String label;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  State<_TodayButton> createState() => _TodayButtonState();
}

class _TodayButtonState extends State<_TodayButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.value = 1;
    } else if (!_c.isAnimating && _c.value == 0) {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final curve = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: curve,
      child: ScaleTransition(
        scale: curve,
        child: Tooltip(
          message: widget.tooltip,
          child: Semantics(
            button: true,
            label: widget.tooltip,
            excludeSemantics: true,
            onTap: widget.onPressed,
            child: _face(theme),
          ),
        ),
      ),
    );
  }

  Widget _face(ThemeData theme) {
    final skin = PlannerSkin.of(context);
    final label = Text(
      widget.label,
      style: theme.textTheme.titleLarge?.copyWith(
        color: skin.neu != null
            ? theme.colorScheme.primary
            : theme.colorScheme.onPrimaryContainer,
        fontWeight: FontWeight.w700,
      ),
    );
    final face = SizedBox(width: 56, height: 56, child: Center(child: label));
    if (skin.plain) {
      return Material(
        color: theme.colorScheme.primaryContainer,
        elevation: 3,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: widget.onPressed,
          child: face,
        ),
      );
    }
    // Comic: filled, outlined disc. Neumorphic: raised disc, accent number.
    return DecoratedBox(
      decoration: skin.surface(
        BoxDecoration(
          color: skin.comic != null
              ? theme.colorScheme.primaryContainer
              : skin.neu!.canvas,
          shape: BoxShape.circle,
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: widget.onPressed,
          child: face,
        ),
      ),
    );
  }
}
