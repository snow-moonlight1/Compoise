import '../widgets/reminder_failure_banner.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../storage.dart';
import '../task_query.dart';
import '../ui/motion_policy.dart';
import '../ui/platform_ui_policy.dart';
import '../widgets/animated_task_title.dart';
import '../widgets/task_detail_panel.dart';
import '../widgets/task_exit.dart';
import '../widgets/task_filter_panel.dart';
import '../widgets/task_hierarchy_checkbox.dart';

/// Screen for searching and multi-dimensional filtering across tasks and subtasks.
class SearchScreen extends StatefulWidget {
  final String? initialBoardId;

  const SearchScreen({super.key, this.initialBoardId});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  final ScrollController _listController = ScrollController();
  TaskFilterCriteria _applied = const TaskFilterCriteria();

  final _detailKey = GlobalKey();
  late final TaskDetailSession _detail = TaskDetailSession(
    onChanged: () {
      if (mounted) setState(() {});
    },
  );

  /// Lightweight exit cache so a row that stops matching the query (for
  /// example a task completed under an "incomplete" filter) still leaves with
  /// visible feedback instead of teleporting away.
  late final ExitRetention<TaskSearchResult> _exitRetention =
      ExitRetention<TaskSearchResult>(
        onChange: () {
          if (mounted) setState(() {});
        },
      );

  @override
  void dispose() {
    _exitRetention.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
    _listController.dispose();
    super.dispose();
  }

  String _boardName(Store store, String boardId) {
    return resolveBoardName(
      boards: store.boards,
      boardId: boardId,
      unknownLabel: store.t['unknownBoard'] ?? 'Unknown board',
    );
  }

  Future<void> _openFilter(BuildContext context) async {
    _searchFocus.unfocus();
    FocusManager.instance.primaryFocus?.unfocus();
    final store = context.read<Store>();
    final boardId = widget.initialBoardId ?? store.activeBoardId;
    final result = await showTaskFilterEditor(
      context: context,
      applied: _applied,
      currentBoardName: _boardName(store, boardId),
      kind: TaskFilterKind.search,
    );
    if (!mounted) return;
    _searchFocus.unfocus();
    FocusManager.instance.primaryFocus?.unfocus();
    if (result != null) {
      setState(() => _applied = result);
    }
  }

  void _clearFilters() {
    setState(() => _applied = const TaskFilterCriteria());
  }

  void _clearKeyword() {
    _searchController.clear();
    setState(() {});
  }

  Future<void> _openDetail(
    BuildContext context,
    Task task, {
    String? subtaskId,
    required bool isWide,
  }) => _detail.open(context, task, isWide: isWide, subtaskId: subtaskId);

  @override
  Widget build(BuildContext context) {
    final store = context.watch<Store>();
    final t = store.t;
    final theme = Theme.of(context);
    final activeBoardId = widget.initialBoardId ?? store.activeBoardId;

    final results = queryTasks(
      tasks: store.tasks,
      boards: store.boards,
      activeBoardId: activeBoardId,
      query: _searchController.text,
      scope: _applied.scope,
      quadrant: _applied.quadrant,
      status: _applied.status,
      dateFilter: _applied.date,
    );
    final policy = PlatformUiPolicy.of(context);
    final boardName = _boardName(store, activeBoardId);
    final activeCount = _applied.dimensionCount(TaskFilterKind.search);

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
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = policy.canShowSideDetail(constraints.maxWidth);
            // Exit cache is resolved before the empty/results branch, otherwise
            // the last leaving row would be replaced by the empty state.
            final entries = _exitRetention.sync(
              items: results,
              // Query and criteria are part of the epoch: rows that stop
              // matching because the user typed or re-filtered disappear at
              // once, while rows that vanish because their own state changed
              // keep the exit animation.
              epochKey:
                  'search-$activeBoardId#${store.boardEpoch(activeBoardId)}'
                  '#${_searchController.text}#${_applied.scope.name}'
                  '#${_applied.status.name}#${_applied.quadrant}'
                  '#${_applied.date.name}',
              idOf: (hit) => hit.resultKey,
              keepIfMissing:
                  (hit) => store.tasks.any((task) => task.id == hit.task.id),
              reduceMotion: MotionPolicy.reduceMotionOf(context),
            );
            final detailTask = _detail.taskIn(store);

            final mainSearchContent = Column(
              children: [
                _buildSearchBar(
                  context,
                  t,
                  theme,
                  policy,
                  activeCount,
                  constraints.maxWidth,
                ),
                const ReminderFailureBanner(),
                AppliedFilterSummary(
                  criteria: _applied,
                  kind: TaskFilterKind.search,
                  currentBoardName: boardName,
                ),
                _buildResultsSummary(context, t, theme, results.length),
                Expanded(
                  child:
                      entries.isEmpty
                          ? _buildEmptyState(
                            context,
                            t,
                            theme,
                            boardName,
                          )
                          : _buildResultsList(
                            context,
                            store,
                            t,
                            theme,
                            entries,
                            isWide,
                            policy,
                          ),
                ),
              ],
            );

            if (detailTask == null) return mainSearchContent;
            final panel = TaskDetailPanel(
              key: _detailKey,
              task: detailTask,
              isSidebar: true,
              highlightSubtaskId: _detail.highlightSubtaskId,
              onDirtyChanged: _detail.reportDraft,
              onClose: _detail.handleClose,
            );
            if (!isWide) return panel;
            return DetailSideBySide(
              main: mainSearchContent,
              detail: panel,
              separator: VerticalDivider(
                width: 1,
                thickness: 1,
                color:
                    theme.brightness == Brightness.light
                        ? const Color(0xFFD5DAE1)
                        : theme.colorScheme.outlineVariant,
              ),
              crossAxisAlignment: CrossAxisAlignment.center,
            );
          },
        ),
      ),
    );

  }

  Widget _buildSearchBar(
    BuildContext context,
    Map<String, String> t,
    ThemeData theme,
    PlatformUiPolicy policy,
    int activeCount,
    double maxWidth,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 4),
      child: Row(
        children: [
          IconButton(
            key: const ValueKey('search-back-btn'),
            tooltip: t['back'] ?? 'Back',
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.maybePop(context),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: TextField(
              key: const ValueKey('search-input'),
              controller: _searchController,
              focusNode: _searchFocus,
              autofocus: false,
              decoration: InputDecoration(
                hintText:
                    t['searchPlaceholder'] ?? 'Search tasks and subtasks…',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon:
                    _searchController.text.isNotEmpty
                        ? IconButton(
                          key: const ValueKey('clear-search-btn'),
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {});
                          },
                        )
                        : null,
                isDense: true,
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.5,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          if (!policy.isTouchLayout) ...[
            const SizedBox(width: 4),
            FilterChromeBar(
              activeCount: activeCount,
              canClear: !_applied.isDefault,
              onOpen: () => _openFilter(context),
              onClear: _clearFilters,
              compact: policy.compactHeaderActions(maxWidth),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildResultsSummary(
    BuildContext context,
    Map<String, String> t,
    ThemeData theme,
    int count,
  ) {
    final text = (t['resultsCount'] ?? '{n} results').replaceAll(
      '{n}',
      '$count',
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Text(
            text,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(
    BuildContext context,
    Map<String, String> t,
    ThemeData theme,
    String boardName,
  ) {
    final query = _searchController.text.trim();
    final scope = scopeSummaryLabel(
      criteria: _applied,
      t: t,
      currentBoardName: boardName,
    );
    final hint =
        query.isEmpty
            ? (t['emptyResultsScope'] ?? 'No matches in {scope}').replaceAll(
              '{scope}',
              scope,
            )
            : (t['emptyResultsQuery'] ??
                    'No matches for “{query}” in {scope}')
                .replaceAll('{query}', query)
                .replaceAll('{scope}', scope);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off_outlined,
              size: 48,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              t['noResults'] ?? 'No matching tasks',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              hint,
              key: const ValueKey('empty-results-hint'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                if (!_applied.isDefault)
                  TextButton(
                    key: const ValueKey('empty-clear-filters-btn'),
                    onPressed: _clearFilters,
                    child: Text(t['clearFilters'] ?? 'Clear filters'),
                  ),
                if (query.isNotEmpty)
                  TextButton(
                    key: const ValueKey('empty-clear-keyword-btn'),
                    onPressed: _clearKeyword,
                    child: Text(t['clearKeyword'] ?? 'Clear keyword'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultsList(
    BuildContext context,
    Store store,
    Map<String, String> t,
    ThemeData theme,
    List<ExitEntry<TaskSearchResult>> entries,
    bool isWide,
    PlatformUiPolicy policy,
  ) {
    final activeBoardId = widget.initialBoardId ?? store.activeBoardId;
    return ListView.separated(
      controller: _listController,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      itemCount: entries.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final entry = entries[index];
        final hit = entry.item;
        final task = hit.task;
        final subtask = hit.matchedSubtask;
        final isSubtask = hit.isSubtaskMatch;
        final level = isSubtask
            ? TaskHierarchyLevel.child
            : TaskHierarchyLevel.parent;
        final isCompleted = hit.isCompleted;
        final q = task.quadrant;
        final qColor = Color(quadrantColors[q]!);
        final isOtherBoard = hit.board.id != activeBoardId;

        final row = InkWell(
          key: ValueKey('search-item-${hit.resultKey}'),
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            _openDetail(context, task, subtaskId: subtask?.id, isWide: isWide);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TaskHierarchyCheckbox(
                  key: ValueKey('search-check-${hit.resultKey}'),
                  hitTargetKey: ValueKey('search-check-hit-${hit.resultKey}'),
                  visualKey: ValueKey('search-check-visual-${hit.resultKey}'),
                  level: level,
                  value: isCompleted,
                  semanticsLabel: taskCheckboxLabel(
                    t: t,
                    level: level,
                    value: isCompleted,
                    title:
                        isSubtask
                            ? (subtask?.title ?? task.title)
                            : task.title,
                  ),
                  onChanged: (val) {
                    if (isSubtask && subtask != null) {
                      store.setSubtaskCompleted(task.id, subtask.id, val);
                    } else {
                      store.setTaskCompleted(task.id, val);
                    }
                  },
                ),
                const SizedBox(width: 8),

                // Main body
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Breadcrumb path and quadrant badge
                      Row(
                        children: [
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
                              t['q$q'] ?? 'Q$q',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: qColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '·',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              hit.pathDisplay,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),

                      // Title
                      AnimatedStrikeThroughText(
                        key: ValueKey('search-title-anim-${hit.resultKey}'),
                        text: hit.displayTitle,
                        completed: isCompleted,
                        strikeKey: ValueKey('search-strike-${hit.resultKey}'),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontSize: TaskHierarchyStyle.titleSize(
                            isSubtask
                                ? TaskHierarchyLevel.child
                                : TaskHierarchyLevel.parent,
                          ),
                          color:
                              isCompleted
                                  ? theme.disabledColor
                                  : theme.colorScheme.onSurface,
                          fontWeight:
                              isSubtask ? FontWeight.normal : FontWeight.w600,
                        ),
                      ),

                      // Subtasks summary or deadline badge
                      if (!isSubtask && task.subtasks.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          '${t['subtasks'] ?? 'Subtasks'}: ${task.subtasks.where((s) => s.completed).length}/${task.subtasks.length}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // Deadline chip if deadline exists
                if (hit.deadline != null) ...[
                  const SizedBox(width: 8),
                  _buildDeadlineBadge(theme, t, hit.deadline!, isCompleted),
                ],

                // Action Menu: "Go to Board" when task belongs to other board
                if (isOtherBoard) ...[
                  const SizedBox(width: 4),
                  PopupMenuButton<String>(
                    tooltip: t['goToBoard'] ?? 'Go to Board',
                    icon: const Icon(Icons.more_vert, size: 18),
                    onSelected: (val) async {
                      if (val == 'goToBoard') {
                        if (!await _detail.confirmLeave(context)) return;
                        if (!context.mounted) return;
                        store.setActiveBoard(hit.board.id);
                        Navigator.pop(context);
                      }
                    },
                    itemBuilder:
                        (_) => [
                          PopupMenuItem(
                            key: ValueKey('go-to-board-btn-${hit.resultKey}'),
                            value: 'goToBoard',
                            child: Row(
                              children: [
                                const Icon(Icons.arrow_forward, size: 16),
                                const SizedBox(width: 8),
                                Text(t['goToBoard'] ?? 'Go to Board'),
                              ],
                            ),
                          ),
                        ],
                  ),
                ],
              ],
            ),
          ),
        );
        return ExitingRow(
          key: ValueKey('search-exit-${hit.resultKey}'),
          exiting: entry.exiting,
          child: row,
        );
      },
    );
  }

  Widget _buildDeadlineBadge(
    ThemeData theme,
    Map<String, String> t,
    int deadline,
    bool completed,
  ) {
    final days = calendarDaysLeft(deadline);
    final isOverdue = !completed && days < 0;
    final isToday = days == 0;

    final color =
        isOverdue
            ? theme.colorScheme.error
            : isToday
            ? Colors.orange
            : theme.colorScheme.outline;

    final text =
        isOverdue
            ? t['overdue'] ?? 'Overdue'
            : isToday
            ? t['today'] ?? 'Today'
            : '${days}d';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 0.8),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
