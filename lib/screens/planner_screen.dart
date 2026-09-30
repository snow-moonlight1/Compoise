import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n.dart';
import '../schedule_time.dart';
import '../storage.dart';
import '../widgets/schedule_layout.dart';

enum PlannerView { day, week }

/// WP15-C1's independently mountable, read-only Planner/Schedule surface.
/// Pass a live Store (or provide one via Provider), or a detached StoreSnapshot.
/// The caller supplies the current device's IANA display zone; platform-to-IANA
/// mapping and the home entry point belong to integration. Stored item zones
/// never determine the viewport and viewing never changes Store state.
class PlannerScreen extends StatefulWidget {
  const PlannerScreen({
    super.key,
    required this.displayTimeZoneId,
    this.store,
    this.snapshot,
    this.initialDate,
    this.initialView = PlannerView.day,
    this.initialBoardId,
    this.now,
  }) : assert(store == null || snapshot == null);

  final String displayTimeZoneId;
  final Store? store;
  final StoreSnapshot? snapshot;
  final ScheduleCivilDate? initialDate;
  final PlannerView initialView;

  /// Null starts with all boards. This is a local view filter, not activeBoardId.
  final String? initialBoardId;
  final DateTime Function()? now;

  @override
  State<PlannerScreen> createState() => _PlannerScreenState();
}

class _PlannerScreenState extends State<PlannerScreen> {
  late ScheduleCivilDate _date;
  late PlannerView _view;
  String? _boardId;
  final _horizontal = ScrollController();

  ScheduleCivilDate _today() {
    final local = scheduleLocalTime(
      (widget.now?.call() ?? DateTime.now()).millisecondsSinceEpoch,
      widget.displayTimeZoneId,
    );
    return ScheduleCivilDate(local.year, local.month, local.day);
  }

  @override
  void initState() {
    super.initState();
    _date = widget.initialDate ?? _today();
    _view = widget.initialView;
    _boardId = widget.initialBoardId;
  }

  @override
  void dispose() {
    _horizontal.dispose();
    super.dispose();
  }

  void _navigate(int direction) => setState(() {
    _date = _date.addDays(direction * (_view == PlannerView.day ? 1 : 7));
  });

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
          timeZoneId: widget.displayTimeZoneId,
          entries: entries,
          pixelsPerHour: 96 * scale,
          minimumItemHeight: 60 * scale,
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
                Text(t['scheduleReadOnly']!),
                if (liveStore?.persistenceError != null)
                  Semantics(
                    liveRegion: true,
                    child: Text(t['scheduleUnsaved']!),
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
                Text(
                  '${t['scheduleDisplayZone']}: ${widget.displayTimeZoneId}',
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
            child: Stack(
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
                    child: _scheduleCard(placement, dateLabel, t, onOpen),
                  ),
              ],
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
        '${scheduleClockLabel(slice.startAt, widget.displayTimeZoneId)} – '
        '${scheduleClockLabel(slice.endAt, widget.displayTimeZoneId)}';
    final label =
        '${_entryLabel(entry, t)} · $dateLabel · $time'
        '${continuation.isEmpty ? '' : ' · $continuation'}';
    return MergeSemantics(
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
                        '${t['scheduleDisplayZone']}: ${widget.displayTimeZoneId}',
                      ),
                      Text(
                        '${t['scheduleStart']}: ${scheduleInstantLabel(entry.item.startAt, widget.displayTimeZoneId)}',
                      ),
                      Text(
                        '${t['scheduleEnd']}: ${scheduleInstantLabel(entry.item.endAt, widget.displayTimeZoneId)}',
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
                      Text(t['scheduleReadOnly']!),
                    ],
                  ),
          ),
          actions: [
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
