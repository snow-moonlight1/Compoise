import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../planned_policy.dart';
import '../storage.dart';
import '../task_query.dart';
import '../ui/platform_ui_policy.dart';
import '../widgets/date_edit_fields.dart';
import '../widgets/reminder_failure_banner.dart';
import '../widgets/task_detail_panel.dart';
import '../widgets/task_filter_panel.dart';
import '../widgets/task_hierarchy_checkbox.dart';
import '../widgets/today_celebration_banner.dart';

/// The Today list: what is planned for today, what carried over, and what is
/// due without a plan — gathered from every quadrant and, on request, every
/// board.
///
/// Grouping is by day, never by quadrant: a row carries its own quadrant badge,
/// so nothing here can rewrite where a task lives on the matrix.
class TodayScreen extends StatefulWidget {
  final String? initialBoardId;

  const TodayScreen({super.key, this.initialBoardId});

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

/// One rendered line: a section heading, or a task under the heading above it.
class _TodayRow {
  const _TodayRow.header(this.section) : task = null;
  const _TodayRow.task(this.task) : section = null;

  final TodaySection? section;
  final Task? task;
}

class _TodayScreenState extends State<TodayScreen> {
  TaskFilterCriteria _applied = const TaskFilterCriteria();
  final _detailKey = GlobalKey();
  late final TaskDetailSession _detail = TaskDetailSession(
    onChanged: () {
      if (mounted) setState(() {});
    },
  );
  Store? _observedStore;
  _TodayScope? _todayScope;
  bool _showCelebration = false;

  bool get _allBoards => _applied.scope == TaskScopeFilter.allBoards;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final store = context.read<Store>();
    if (identical(_observedStore, store)) return;
    _observedStore?.removeListener(_onTodayStoreChanged);
    _observedStore = store;
    _todayScope = null;
    store.addListener(_onTodayStoreChanged);
  }

  @override
  void dispose() {
    _observedStore?.removeListener(_onTodayStoreChanged);
    super.dispose();
  }

  _TodayScope _capture(Store store) {
    final groups = store.todayGroups(allBoards: _allBoards);
    return _TodayScope(
      _allBoards ? 'all-boards' : 'board:${store.activeBoardId}',
      {
        for (final group in groups)
          for (final task in group.tasks) task.id,
      },
    );
  }

  bool _isCompleted(Store store, String id) {
    for (final task in store.tasks) {
      if (task.id == id) return task.completed;
    }
    return false;
  }

  /// Store notifications are the only path that can celebrate, and only when
  /// the open rows that disappeared are now completed. Board switches, plan
  /// clears, deletes, and the midnight refresh all notify too; they update the
  /// baseline and never consume the day's celebration.
  void _onTodayStoreChanged() {
    final store = _observedStore;
    if (store == null || !mounted) return;
    final next = _capture(store);
    final previous = _todayScope;
    if (previous == null) {
      _todayScope = next;
      return;
    }
    final removed = previous.openIds.difference(next.openIds);
    final celebrate = store.todayCelebration.consider(
      scopeUnchanged: previous.scopeKey == next.scopeKey,
      openBefore: previous.openIds.length,
      openAfter: next.openIds.length,
      removedIds: removed,
      isCompleted: (id) => _isCompleted(store, id),
    );
    final hide = previous.scopeKey != next.scopeKey || next.openIds.isNotEmpty;
    _todayScope = next;
    if (celebrate) {
      setState(() => _showCelebration = true);
    } else if (hide && _showCelebration) {
      setState(() => _showCelebration = false);
    }
  }

  void _dismissCelebration() {
    if (!mounted || !_showCelebration) return;
    setState(() => _showCelebration = false);
  }

  String _boardName(Store store, String boardId) => resolveBoardName(
    boards: store.boards,
    boardId: boardId,
    unknownLabel: store.t['unknownBoard'] ?? 'Unknown board',
  );

  Future<void> _openFilter(BuildContext context) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final store = context.read<Store>();
    final boardId = widget.initialBoardId ?? store.activeBoardId;
    final result = await showTaskFilterEditor(
      context: context,
      applied: _applied,
      currentBoardName: _boardName(store, boardId),
      kind: TaskFilterKind.archive,
    );
    if (!mounted) return;
    if (result != null) {
      setState(() => _applied = TaskFilterCriteria(scope: result.scope));
    }
  }

  void _clearFilters() => setState(() => _applied = const TaskFilterCriteria());

  Future<void> _openDetail(
    BuildContext context,
    Task task, {
    required bool isWide,
  }) => _detail.open(context, task, isWide: isWide);

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  void _planToday(Store store, Task task) {
    store.setPlannedDay(task.id, civilToday());
    _toast(store.t['taskPlannedToday']!);
  }

  void _clearPlan(Store store, Task task) {
    store.setPlannedDay(task.id, null);
    _toast(store.t['taskPlanCleared']!);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<Store>();
    final t = store.t;
    final theme = Theme.of(context);
    final policy = PlatformUiPolicy.of(context);
    final activeBoardId = widget.initialBoardId ?? store.activeBoardId;
    final isWide = policy.canShowSideDetail(MediaQuery.sizeOf(context).width);
    final groups = store.todayGroups(allBoards: _allBoards);
    final captured = _capture(store);
    if (_todayScope == null) {
      _todayScope = captured;
    } else if (_todayScope!.scopeKey != captured.scopeKey) {
      // Filter changes do not notify the store. They are not a completion.
      _todayScope = captured;
      _showCelebration = false;
    }
    final rows = [
      for (final group in groups) ...[
        _TodayRow.header(group.section),
        for (final task in group.tasks) _TodayRow.task(task),
      ],
    ];
    final activeCount = _applied.dimensionCount(TaskFilterKind.archive);
    final detailTask = _detail.taskIn(store);

    final mainContent = Column(
      children: [
        _buildHeader(context, t, theme, policy, store, groups, activeCount),
        if (_showCelebration)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TodayCelebrationBanner(
              key: const ValueKey('today-celebration'),
              title: t['todayCelebrationTitle']!,
              body: t['todayCelebrationBody']!,
              closeLabel: t['close']!,
              onClose: _dismissCelebration,
            ),
          ),
        const ReminderFailureBanner(),
        AppliedFilterSummary(
          criteria: _applied,
          kind: TaskFilterKind.archive,
          currentBoardName: _boardName(store, activeBoardId),
        ),
        Expanded(
          child:
              rows.isEmpty
                  ? _buildEmptyState(t, theme)
                  : ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    itemCount: rows.length,
                    itemBuilder:
                        (context, index) =>
                            rows[index].section != null
                                ? _buildSectionHeader(
                                  t,
                                  theme,
                                  rows[index].section!,
                                  groups,
                                )
                                : _buildRow(
                                  store,
                                  t,
                                  theme,
                                  rows[index].task!,
                                  activeBoardId,
                                  isWide,
                                ),
                  ),
        ),
      ],
    );

    return Scaffold(
      bottomNavigationBar:
          policy.isTouchLayout
              ? FilterChromeBar(
                activeCount: activeCount,
                canClear: !_applied.isDefault,
                onOpen: () => _openFilter(context),
                onClear: _clearFilters,
                expanded: true,
              )
              : null,
      body: SafeArea(
        bottom: !policy.isTouchLayout,
        child:
            detailTask == null
                ? mainContent
                : _buildWithDetail(mainContent, detailTask, theme, isWide),
      ),
    );
  }

  Widget _buildWithDetail(
    Widget mainContent,
    Task detailTask,
    ThemeData theme,
    bool isWide,
  ) {
    final panel = TaskDetailPanel(
      key: _detailKey,
      task: detailTask,
      isSidebar: true,
      onDirtyChanged: _detail.reportDraft,
      onClose: _detail.handleClose,
    );
    if (!isWide) return panel;
    return DetailSideBySide(
      main: mainContent,
      detail: panel,
      separator: VerticalDivider(
        width: 1,
        thickness: 1,
        color:
            theme.brightness == Brightness.light
                ? const Color(0xFFD5DAE1)
                : theme.colorScheme.outlineVariant,
      ),
      crossAxisAlignment: CrossAxisAlignment.start,
    );
  }

  Widget _buildHeader(
    BuildContext context,
    Map<String, String> t,
    ThemeData theme,
    PlatformUiPolicy policy,
    Store store,
    List<TodayGroup> groups,
    int activeCount,
  ) {
    final open = groups.fold<int>(0, (sum, group) => sum + group.tasks.length);
    final completedToday = store.completedTodayCount(allBoards: _allBoards);
    final countText =
        '${(t['completedCount'] ?? '{n} items in list').replaceAll('{n}', '$open')}'
        ' · '
        '${(t['todayCompletedCount'] ?? '{n} completed today').replaceAll('{n}', '$completedToday')}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 4),
      child: Row(
        children: [
          IconButton(
            key: const ValueKey('today-back-btn'),
            tooltip: t['back'] ?? 'Back',
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.maybePop(context),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  t['today']!,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  countText,
                  key: const ValueKey('today-summary'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (!policy.isTouchLayout)
            FilterChromeBar(
              activeCount: activeCount,
              canClear: !_applied.isDefault,
              onOpen: () => _openFilter(context),
              onClear: _clearFilters,
              compact: policy.compactHeaderActions(
                MediaQuery.sizeOf(context).width,
              ),
            ),
        ],
      ),
    );
  }

  String _sectionLabel(Map<String, String> t, TodaySection section) =>
      switch (section) {
        TodaySection.carriedOver => t['todaySectionCarriedOver']!,
        TodaySection.plannedToday => t['todaySectionPlanned']!,
        TodaySection.dueNow => t['todaySectionDueNow']!,
      };

  Widget _buildSectionHeader(
    Map<String, String> t,
    ThemeData theme,
    TodaySection section,
    List<TodayGroup> groups,
  ) {
    final count = groups
        .firstWhere((group) => group.section == section)
        .tasks.length;
    return Padding(
      key: ValueKey('today-section-${section.name}'),
      padding: const EdgeInsets.fromLTRB(8, 14, 8, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _sectionLabel(t, section),
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            '$count',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(Map<String, String> t, ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.today_outlined,
            size: 56,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(height: 12),
          Text(
            t['todayEmpty']!,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRow(
    Store store,
    Map<String, String> t,
    ThemeData theme,
    Task task,
    String activeBoardId,
    bool isWide,
  ) {
    final qColor = Color(quadrantColors[task.quadrant] ?? 0xFF888888);
    final showBoardBadge = _allBoards || task.boardId != activeBoardId;
    final stepsDone = task.subtasks.where((s) => s.completed).length;

    return InkWell(
      key: ValueKey('today-item-${task.id}'),
      borderRadius: BorderRadius.circular(8),
      onTap: () => _openDetail(context, task, isWide: isWide),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TaskHierarchyCheckbox(
              hitTargetKey: ValueKey('today-check-${task.id}'),
              visualKey: ValueKey('today-check-${task.id}-visual'),
              level: TaskHierarchyLevel.parent,
              value: false,
              semanticsLabel: taskCheckboxLabel(
                t: t,
                level: TaskHierarchyLevel.parent,
                value: false,
                title: task.title,
              ),
              onChanged: (value) => store.setParentCompleted(task, value),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (showBoardBadge) ...[
                        Flexible(
                          child: Text(
                            _boardName(store, task.boardId),
                            key: ValueKey('today-board-${task.id}'),
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: qColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          t['q${task.quadrant}'] ?? 'Q${task.quadrant}',
                          key: ValueKey('today-quadrant-${task.id}'),
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: qColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    task.title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: TaskHierarchyStyle.parentTitleSize,
                      height: 1.35,
                    ),
                  ),
                  if (task.plannedDate != null || task.deadline != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 2,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (task.plannedDate != null)
                            _DateLabel(
                              key: ValueKey('today-planned-${task.id}'),
                              icon: Icons.event_note,
                              text:
                                  '${t['plannedDate']}: ${formatCivilDateMs(task.plannedDate!)}',
                              color: theme.colorScheme.primary,
                            ),
                          if (task.deadline != null)
                            _DeadlineLabel(task: task, t: t, theme: theme),
                        ],
                      ),
                    ),
                  if (task.subtasks.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        (t['subtaskProgress'] ?? 'Subtasks {done}/{total}')
                            .replaceAll('{done}', '$stepsDone')
                            .replaceAll('{total}', '${task.subtasks.length}'),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            _planMenu(store, t, task),
          ],
        ),
      ),
    );
  }

  Widget _planMenu(Store store, Map<String, String> t, Task task) {
    return PopupMenuButton<String>(
      key: ValueKey('today-menu-${task.id}'),
      tooltip: t['moreProperties']!,
      icon: const Icon(Icons.more_horiz, size: 20),
      onSelected: (value) {
        if (value == 'plan-today') {
          _planToday(store, task);
        } else if (value == 'clear-plan') {
          _clearPlan(store, task);
        }
      },
      itemBuilder:
          (context) => [
            if (plannedDaysLeft(task.plannedDate) != 0)
              PopupMenuItem(
                value: 'plan-today',
                child: Text(t['planForToday']!),
              ),
            if (task.plannedDate != null)
              PopupMenuItem(value: 'clear-plan', child: Text(t['clearPlan']!)),
          ],
    );
  }
}

/// Open Today rows for one board scope. Compared by the screen so a filter
/// or board change is not mistaken for the list being cleared.
class _TodayScope {
  const _TodayScope(this.scopeKey, this.openIds);

  final String scopeKey;
  final Set<String> openIds;
}

/// One date on a Today row. The planned day carries [color] from the accent and
/// never the error colour, so a plan cannot be misread as a missed deadline.
class _DateLabel extends StatelessWidget {
  const _DateLabel({
    super.key,
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontSize: 11,
            ),
          ),
        ),
      ],
    );
  }
}

class _DeadlineLabel extends StatelessWidget {
  const _DeadlineLabel({
    required this.task,
    required this.t,
    required this.theme,
  });

  final Task task;
  final Map<String, String> t;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final days = calendarDaysLeft(task.deadline!);
    return _DateLabel(
      key: ValueKey('today-deadline-${task.id}'),
      icon: Icons.calendar_month,
      text: '${t['deadline']}: ${formatCivilDateMs(task.deadline!)}',
      color:
          days <= 0
              ? theme.colorScheme.error
              : theme.colorScheme.onSurfaceVariant,
    );
  }
}
