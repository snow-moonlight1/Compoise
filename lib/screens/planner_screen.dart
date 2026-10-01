import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n.dart';
import '../planner/schedule_drag.dart';
import '../planner/schedule_edit_session.dart';
import '../planner/schedule_editor.dart';
import '../platform/device_time_zone_controller.dart';
import '../platform/device_time_zone_picker.dart';
import '../schedule_item.dart';
import '../schedule_time.dart';
import '../storage.dart';
import '../widgets/schedule_layout.dart';

enum PlannerView { day, week }

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

class _PlannerScreenState extends State<PlannerScreen> {
  late ScheduleCivilDate _date;
  late PlannerView _view;
  String? _boardId;
  final _horizontal = ScrollController();
  bool _editorOpen = false;
  bool _retryingStore = false;
  String? _adjustingId;

  /// Created only when the caller injects no controller, and disposed here.
  DeviceTimeZoneController? _ownedZone;

  /// Effective display zone. Null until the device reports one or the user
  /// picks one, because there is no silent fallback zone.
  String? _zone;
  bool _startedPreselectedBlock = false;

  DeviceTimeZoneController? get _zoneController =>
      widget.timeZoneController ?? _ownedZone;

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
    _horizontal.dispose();
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(store.t['scheduleTaskMissing']!)),
      );
      return;
    }
    await _create(
      store,
      _date,
      kind: ScheduleItemKind.timeBlock,
      taskId: taskId,
    );
  }

  void _navigate(int direction) => setState(() {
    _date = _date.addDays(direction * (_view == PlannerView.day ? 1 : 7));
  });

  Future<void> _create(
    Store store,
    ScheduleCivilDate date, {
    ScheduleWallTime? suggestedStart,
    ScheduleItemKind? kind,
    String? taskId,
  }) async {
    if (_editorOpen || store.hasStartupRecovery || !store.ready) return;
    setState(() => _editorOpen = true);
    try {
      // A task entry already knows the kind and its parent task; the grid asks.
      final chosen =
          kind ??
          await showDialog<ScheduleItemKind>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(store.t['scheduleEditorNew']!),
              scrollable: true,
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final option in ScheduleItemKind.values)
                    TextButton(
                      key: ValueKey('schedule-create-${option.name}'),
                      onPressed:
                          option == ScheduleItemKind.timeBlock &&
                              store.tasks.isEmpty
                          ? null
                          : () => Navigator.pop(context, option),
                      child: Text(
                        store.t[option == ScheduleItemKind.timeBlock
                            ? 'scheduleTimeBlock'
                            : 'scheduleEvent']!,
                      ),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(store.t['cancel']!),
                ),
              ],
            ),
          );
      if (chosen == null || !mounted) return;
      final session = ScheduleEditSession.create(
        store,
        chosen,
        _zone!,
        date,
        suggestedStart: suggestedStart,
      );
      if (taskId != null) session.taskId = taskId;
      final saved = await showScheduleEditor(context, session);
      if (saved == true && mounted) _savedMessage(store);
    } finally {
      if (mounted) setState(() => _editorOpen = false);
    }
  }

  void _savedMessage(Store store) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(store.t['scheduleEditorSaved']!)));

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
    final elapsed = (y / day.pixelsPerHour * Duration.millisecondsPerHour)
        .floor();
    final quarter = Duration.millisecondsPerMinute * 15;
    final instant = day.window.startAt + (elapsed ~/ quarter) * quarter;
    final local = scheduleLocalTime(instant, _zone!);
    return ScheduleWallTime(
      ScheduleCivilDate(local.year, local.month, local.day),
      hour: local.hour,
      minute: local.minute,
    );
  }

  Widget _interactiveGrid(
    ScheduleDayLayout day,
    Store? store,
    double axisWidth,
    Widget child,
  ) {
    if (store == null) return child;
    return Builder(
      builder: (context) => DragTarget<ScheduleDragPayload>(
        key: ValueKey('schedule-drop-${scheduleDateLabel(day.date)}'),
        onWillAcceptWithDetails: (_) =>
            !_editorOpen && !store.hasStartupRecovery,
        onAcceptWithDetails: (details) {
          final box = context.findRenderObject()! as RenderBox;
          final point = box.globalToLocal(details.offset);
          if (point.dy < 0 || point.dy >= day.axisHeight) return;
          final payload = details.data;
          _edit(
            store,
            payload.item,
            payload.mode,
            revision: payload.revision,
            target: _wallAt(day, point.dy),
          );
        },
        builder: (context, candidates, rejected) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) {
            if (details.localPosition.dx < axisWidth ||
                details.localPosition.dy >= day.axisHeight) {
              return;
            }
            _create(
              store,
              day.date,
              suggestedStart: _wallAt(day, details.localPosition.dy),
            );
          },
          child: child,
        ),
      ),
    );
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
    );
    if (picked != null && mounted) {
      setState(
        () => _date = ScheduleCivilDate(picked.year, picked.month, picked.day),
      );
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
    final zone = _zone;
    // Without a usable device zone and without a user choice, the page states
    // the problem instead of drawing a grid in an assumed zone.
    if (zone == null) return _zoneRequiredScaffold(t);
    final theme = Theme.of(context);
    final scale = math.max(
      1.0,
      MediaQuery.textScalerOf(context).scale(14) / 14,
    );
    final boardId = data.boards.any((board) => board.id == _boardId)
        ? _boardId
        : null;
    final boardName = boardId == null
        ? t['allBoards']!
        : data.boards.firstWhere((board) => board.id == boardId).name;
    final entries = scheduleEntries(
      items: data.scheduleItems,
      tasks: data.tasks,
      boards: data.boards,
      boardId: boardId,
    );
    final monday = _date.addDays(
      1 - DateTime.utc(_date.year, _date.month, _date.day).weekday,
    );
    final dates = _view == PlannerView.day
        ? [_date]
        : [for (var day = 0; day < 7; day++) monday.addDays(day)];
    final days = [
      for (final date in dates)
        ScheduleDayLayout(
          date: date,
          timeZoneId: zone,
          entries: entries,
          pixelsPerHour: 96 * scale,
          minimumItemHeight: (_adjustingId == null ? 60 : 150) * scale,
        ),
    ];
    final range = _view == PlannerView.day
        ? scheduleDateLabel(_date)
        : '${scheduleDateLabel(dates.first)} – ${scheduleDateLabel(dates.last)}';

    return Scaffold(
      body: SafeArea(
        child: FocusTraversalGroup(
          policy: ReadingOrderTraversalPolicy(),
          child: SingleChildScrollView(
            key: const ValueKey('schedule-scroll'),
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    t['scheduleTitle']!,
                    style: theme.textTheme.headlineSmall,
                  ),
                ),
                if (liveStore == null)
                  Text(t['scheduleReadOnly']!)
                else ...[
                  TextButton.icon(
                    key: const ValueKey('schedule-add'),
                    onPressed: _editorOpen
                        ? null
                        : () => _create(liveStore, _date),
                    icon: const Icon(Icons.add),
                    label: Text(t['scheduleEditorAdd']!),
                  ),
                  if (_adjustingId != null)
                    TextButton(
                      key: const ValueKey('schedule-hide-handles'),
                      onPressed: () => setState(() => _adjustingId = null),
                      child: Text(t['scheduleEditorHideHandles']!),
                    ),
                ],
                if (liveStore?.persistenceError != null)
                  Semantics(
                    liveRegion: true,
                    child: Text(t['scheduleUnsaved']!),
                  ),
                if (liveStore?.persistenceError != null)
                  TextButton(
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
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    IconButton(
                      key: const ValueKey('schedule-previous'),
                      tooltip:
                          t[_view == PlannerView.day
                              ? 'schedulePreviousDay'
                              : 'schedulePreviousWeek'],
                      onPressed:
                          _date.year <= 1 && _date.month == 1 && _date.day <= 7
                          ? null
                          : () => _navigate(-1),
                      icon: const Icon(Icons.chevron_left),
                    ),
                    TextButton(
                      key: const ValueKey('schedule-date'),
                      onPressed: () => _pickDate(t),
                      child: Text(range),
                    ),
                    IconButton(
                      key: const ValueKey('schedule-next'),
                      tooltip:
                          t[_view == PlannerView.day
                              ? 'scheduleNextDay'
                              : 'scheduleNextWeek'],
                      onPressed:
                          _date.year >= 9999 &&
                              _date.month == 12 &&
                              _date.day >= 24
                          ? null
                          : () => _navigate(1),
                      icon: const Icon(Icons.chevron_right),
                    ),
                    TextButton(
                      key: const ValueKey('schedule-today'),
                      onPressed: () => setState(() => _date = _today()),
                      child: Text(t['today']!),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final mode in PlannerView.values)
                      ChoiceChip(
                        key: ValueKey('schedule-mode-${mode.name}'),
                        label: Text(
                          t[mode == PlannerView.day
                              ? 'scheduleDay'
                              : 'scheduleWeek']!,
                        ),
                        selected: _view == mode,
                        onSelected: (_) => setState(() => _view = mode),
                      ),
                    TextButton.icon(
                      key: const ValueKey('schedule-filter'),
                      onPressed: () => _pickBoard(data, t),
                      icon: const Icon(Icons.filter_list),
                      label: Text('${t['scheduleBoardFilter']}: $boardName'),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      '${_zoneController?.followsDeviceZone ?? false ? t['scheduleZoneDevice'] : t['scheduleDisplayZone']}: $zone',
                    ),
                    if (_zoneController != null)
                      TextButton.icon(
                        key: const ValueKey('schedule-zone-switch'),
                        onPressed: () => _chooseZone(_zoneController!, t),
                        icon: const Icon(Icons.public),
                        label: Text(t['scheduleZoneSwitch']!),
                      ),
                  ],
                ),
                if (days.every((day) => day.placements.isEmpty))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(t['scheduleEmpty']!),
                  ),
                Text(
                  t['scheduleScrollHint']!,
                  style: theme.textTheme.bodySmall,
                ),
                if (liveStore != null) Text(t['scheduleEditorDragHint']!),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final laneWidth = 180.0 * scale;
                    final axisWidth = 150.0 * scale;
                    final dayHeight = days
                        .map((day) => day.height)
                        .reduce(math.max);
                    return Scrollbar(
                      controller: _horizontal,
                      thumbVisibility: true,
                      child: SingleChildScrollView(
                        key: const ValueKey('schedule-horizontal'),
                        controller: _horizontal,
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final day in days)
                              _dayColumn(
                                day,
                                t,
                                width: math.max(
                                  _view == PlannerView.day
                                      ? constraints.maxWidth
                                      : 0,
                                  axisWidth + day.laneCount * laneWidth,
                                ),
                                axisWidth: axisWidth,
                                gridHeight: dayHeight,
                                headerHeight: 90 * scale,
                                onOpen: (id) =>
                                    _openDetail(id, data, t, liveStore),
                                liveStore: liveStore,
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
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

  String _entryLabel(ScheduleEntry entry, Map<String, String> t) => [
    t[entry.item.kind.name == 'timeBlock'
        ? 'scheduleTimeBlock'
        : 'scheduleEvent']!,
    entry.title,
    entry.boardName ?? t['unknownBoard']!,
    if (entry.taskTitle != null) '${t['scheduleTask']}: ${entry.taskTitle}',
    if (entry.quadrant != null)
      'Q${entry.quadrant} · ${t['q${entry.quadrant}Short']}',
    if (entry.completed) t['completed']!,
  ].join(' · ');

  Widget _dayColumn(
    ScheduleDayLayout day,
    Map<String, String> t, {
    required double width,
    required double axisWidth,
    required double gridHeight,
    required double headerHeight,
    required ValueChanged<String> onOpen,
    Store? liveStore,
  }) {
    final theme = Theme.of(context);
    final dateLabel = scheduleDateLabel(day.date);
    final laneWidth = (width - axisWidth) / day.laneCount;
    return SizedBox(
      key: ValueKey('schedule-day-$dateLabel'),
      width: width,
      child: Column(
        children: [
          SizedBox(
            height: headerHeight,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Semantics(
                header: true,
                child: Text(
                  '$dateLabel · ${t['scheduleWeekday${DateTime.utc(day.date.year, day.date.month, day.date.day).weekday}']}\n'
                  '${(day.window.endAt - day.window.startAt) / Duration.millisecondsPerHour} ${t['scheduleHours']}',
                ),
              ),
            ),
          ),
          SizedBox(
            height: gridHeight,
            child: _interactiveGrid(
              day,
              liveStore,
              axisWidth,
              Stack(
                children: [
                  for (final tick in day.ticks)
                    Positioned(
                      top: tick.top,
                      left: 0,
                      right: 0,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: axisWidth,
                            child: Text(
                              tick.label,
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                          const Expanded(child: Divider(height: 1)),
                        ],
                      ),
                    ),
                  for (final placement in day.placements)
                    Positioned(
                      top: placement.top,
                      left: axisWidth + placement.lane * laneWidth + 2,
                      width: laneWidth - 4,
                      height: placement.height - 2,
                      child: _scheduleCard(
                        placement,
                        dateLabel,
                        t,
                        onOpen,
                        liveStore,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _scheduleCard(
    SchedulePlacement placement,
    String dateLabel,
    Map<String, String> t,
    ValueChanged<String> onOpen,
    Store? liveStore,
  ) {
    final entry = placement.entry;
    final slice = placement.slice;
    final theme = Theme.of(context);
    final isBlock = entry.item.kind.name == 'timeBlock';
    final continuation = [
      if (slice.continuesBefore) t['scheduleContinuesBefore']!,
      if (slice.continuesAfter) t['scheduleContinuesAfter']!,
    ].join(' · ');
    final time =
        '${scheduleClockLabel(slice.startAt, _zone!)} – '
        '${scheduleClockLabel(slice.endAt, _zone!)}';
    final label =
        '${_entryLabel(entry, t)} · $dateLabel · $time'
        '${continuation.isEmpty ? '' : ' · $continuation'}';
    final card = MergeSemantics(
      key: ValueKey('schedule-semantics-$dateLabel-${entry.item.id}'),
      child: Semantics(
        label: label,
        // Preserve the native button's tap action and keyboard focus semantics.
        // Only its painted text is excluded, since the label above is complete.
        child: Builder(
          builder: (context) => OutlinedButton(
            key: ValueKey('schedule-item-$dateLabel-${entry.item.id}'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.all(8),
              alignment: Alignment.topLeft,
              foregroundColor: entry.completed
                  ? theme.colorScheme.onSurfaceVariant
                  : theme.colorScheme.onSurface,
              backgroundColor: entry.completed
                  ? theme.colorScheme.surfaceContainerLow
                  : isBlock
                  ? theme.colorScheme.primaryContainer
                  : theme.colorScheme.secondaryContainer,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () => onOpen(entry.item.id),
            onFocusChange: (focused) {
              if (!focused) return;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (context.mounted) {
                  Scrollable.ensureVisible(
                    context,
                    alignment: 0.15,
                    duration: const Duration(milliseconds: 150),
                  );
                }
              });
            },
            // A short interval has a compact visible label; its full description
            // remains in semantics and the read-only detail. No fixed text scale.
            child: ExcludeSemantics(
              child: ClipRect(
                child: Text(
                  '${isBlock ? t['scheduleTimeBlock'] : t['scheduleEvent']} · ${entry.title}\n'
                  '${entry.boardName ?? t['unknownBoard']}'
                  '${entry.quadrant == null ? '' : ' · Q${entry.quadrant}'}'
                  '${entry.completed ? ' · ${t['completed']}' : ''}\n'
                  '${entry.taskTitle == null || isBlock ? '' : '${t['scheduleTask']}: ${entry.taskTitle}\n'}'
                  '$time${continuation.isEmpty ? '' : '\n$continuation'}',
                  overflow: TextOverflow.fade,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (liveStore == null) return card;
    final moving = _drag(
      liveStore,
      entry.item,
      ScheduleEditMode.move,
      card,
      key: ValueKey('schedule-drag-$dateLabel-${entry.item.id}'),
    );
    if (_adjustingId != entry.item.id) return moving;
    final handleHeight =
        48.0 * math.max(1.0, MediaQuery.textScalerOf(context).scale(14) / 14);
    return Stack(
      children: [
        Positioned(
          top: handleHeight,
          bottom: handleHeight,
          left: 0,
          right: 0,
          child: moving,
        ),
        for (final mode in [
          ScheduleEditMode.resizeStart,
          ScheduleEditMode.resizeEnd,
        ])
          Positioned(
            top: mode == ScheduleEditMode.resizeStart ? 0 : null,
            bottom: mode == ScheduleEditMode.resizeEnd ? 0 : null,
            left: 0,
            right: 0,
            height: handleHeight,
            child: _drag(
              liveStore,
              entry.item,
              mode,
              OutlinedButton(
                key: ValueKey(
                  'schedule-handle-$dateLabel-${entry.item.id}-${mode.name}',
                ),
                onPressed: () => _edit(liveStore, entry.item, mode),
                child: Text(
                  t[mode == ScheduleEditMode.resizeStart
                      ? 'scheduleEditorResizeStart'
                      : 'scheduleEditorResizeEnd']!,
                ),
              ),
              key: ValueKey(
                'schedule-handle-drag-$dateLabel-${entry.item.id}-${mode.name}',
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _openDetail(
    String id,
    StoreSnapshot snapshot,
    Map<String, String> t,
    Store? liveStore,
  ) => showDialog<void>(
    context: context,
    builder: (context) {
      Widget detail() {
        final current = liveStore?.captureSnapshot() ?? snapshot;
        final entry = scheduleEntries(
          items: current.scheduleItems,
          tasks: current.tasks,
          boards: current.boards,
        ).where((entry) => entry.item.id == id).firstOrNull;
        return AlertDialog(
          key: const ValueKey('schedule-detail'),
          title: Text(entry?.title ?? t['scheduleUnavailable']!),
          scrollable: true,
          content: SizedBox(
            width: 440,
            child: entry == null
                ? Text(t['scheduleUnavailable']!)
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_entryLabel(entry, t)),
                      Text(
                        '${t['scheduleDisplayZone']}: ${_zone!}',
                      ),
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
                    ],
                  ),
          ),
          actions: [
            if (liveStore != null &&
                entry != null &&
                !liveStore.hasStartupRecovery) ...[
              TextButton(
                key: const ValueKey('schedule-detail-edit'),
                onPressed: () {
                  Navigator.pop(context);
                  _edit(
                    liveStore,
                    entry.item,
                    ScheduleEditMode.edit,
                    revision: current.scheduleRevisionFor(id),
                  );
                },
                child: Text(t['scheduleEditorEdit']!),
              ),
              PopupMenuButton<String>(
                key: const ValueKey('schedule-detail-actions'),
                tooltip: t['scheduleEditorMore'],
                itemBuilder: (_) => [
                  for (final choice in [
                    ('move', 'scheduleEditorMove'),
                    ('resizeStart', 'scheduleEditorResizeStart'),
                    ('resizeEnd', 'scheduleEditorResizeEnd'),
                    ('handles', 'scheduleEditorHandles'),
                    ('delete', 'scheduleEditorDelete'),
                  ])
                    PopupMenuItem(value: choice.$1, child: Text(t[choice.$2]!)),
                ],
                onSelected: (action) {
                  Navigator.pop(context);
                  if (action == 'handles') {
                    setState(() => _adjustingId = id);
                    return;
                  }
                  _edit(
                    liveStore,
                    entry.item,
                    switch (action) {
                      'move' => ScheduleEditMode.move,
                      'resizeStart' => ScheduleEditMode.resizeStart,
                      'resizeEnd' => ScheduleEditMode.resizeEnd,
                      _ => ScheduleEditMode.edit,
                    },
                    revision: current.scheduleRevisionFor(id),
                    delete: action == 'delete',
                  );
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
