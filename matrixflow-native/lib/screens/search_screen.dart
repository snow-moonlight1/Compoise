import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../storage.dart';
import '../task_query.dart';
import '../widgets/task_detail_panel.dart';

/// Screen for searching and multi-dimensional filtering across tasks and subtasks.
class SearchScreen extends StatefulWidget {
  final String? initialBoardId;

  const SearchScreen({super.key, this.initialBoardId});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  TaskScopeFilter _scope = TaskScopeFilter.currentBoard;
  int? _selectedQuadrant; // null means All
  TaskStatusFilter _selectedStatus = TaskStatusFilter.all;
  TaskDateFilter _selectedDate = TaskDateFilter.all;

  String? _activeDetailTaskId;
  String? _highlightSubtaskId;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openDetail(
    BuildContext context,
    Task task, {
    String? subtaskId,
    required bool isWide,
  }) {
    if (isWide) {
      setState(() {
        _activeDetailTaskId = task.id;
        _highlightSubtaskId = subtaskId;
      });
    } else {
      showTaskDetailSheet(context, task, highlightSubtaskId: subtaskId);
    }
  }

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
      scope: _scope,
      quadrant: _selectedQuadrant,
      status: _selectedStatus,
      dateFilter: _selectedDate,
    );

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 900;
            final detailTask =
                _activeDetailTaskId == null
                    ? null
                    : store.tasks
                        .where((item) => item.id == _activeDetailTaskId)
                        .firstOrNull;

            if (!isWide && _activeDetailTaskId != null) {
              _activeDetailTaskId = null;
              if (detailTask != null) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    showTaskDetailSheet(
                      context,
                      detailTask,
                      highlightSubtaskId: _highlightSubtaskId,
                    );
                  }
                });
              }
            }

            final mainSearchContent = Column(
              children: [
                _buildSearchBar(context, t, theme),
                _buildFilterChips(context, t, theme, store),
                _buildResultsSummary(context, t, theme, results.length),
                Expanded(
                  child:
                      results.isEmpty
                          ? _buildEmptyState(context, t, theme)
                          : _buildResultsList(
                            context,
                            store,
                            t,
                            theme,
                            results,
                            isWide,
                          ),
                ),
              ],
            );

            if (isWide && detailTask != null) {
              return Row(
                children: [
                  Expanded(child: mainSearchContent),
                  VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color:
                        theme.brightness == Brightness.light
                            ? const Color(0xFFD5DAE1)
                            : theme.colorScheme.outlineVariant,
                  ),
                  SizedBox(
                    width: 350,
                    child: TaskDetailPanel(
                      task: detailTask,
                      isSidebar: true,
                      highlightSubtaskId: _highlightSubtaskId,
                      onClose: () {
                        setState(() {
                          _activeDetailTaskId = null;
                          _highlightSubtaskId = null;
                        });
                      },
                    ),
                  ),
                ],
              );
            }

            return mainSearchContent;
          },
        ),
      ),
    );
  }

  Widget _buildSearchBar(
    BuildContext context,
    Map<String, String> t,
    ThemeData theme,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 4),
      child: Row(
        children: [
          IconButton(
            key: const ValueKey('search-back-btn'),
            tooltip: t['back'] ?? 'Back',
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: TextField(
              key: const ValueKey('search-input'),
              controller: _searchController,
              autofocus: false,
              decoration: InputDecoration(
                hintText: t['searchPlaceholder'] ?? 'Search tasks and subtasks…',
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
        ],
      ),
    );
  }

  Widget _buildFilterChips(
    BuildContext context,
    Map<String, String> t,
    ThemeData theme,
    Store store,
  ) {
    return SizedBox(
      height: 48,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
          // Scope Filter
          ChoiceChip(
            key: const ValueKey('filter-scope-current'),
            label: Text(t['currentBoard'] ?? 'Current Board'),
            selected: _scope == TaskScopeFilter.currentBoard,
            onSelected:
                (selected) => setState(() {
                  _scope = TaskScopeFilter.currentBoard;
                }),
          ),
          const SizedBox(width: 6),
          ChoiceChip(
            key: const ValueKey('filter-scope-all'),
            label: Text(t['allBoards'] ?? 'All Boards'),
            selected: _scope == TaskScopeFilter.allBoards,
            onSelected:
                (selected) => setState(() {
                  _scope = TaskScopeFilter.allBoards;
                }),
          ),

          const SizedBox(width: 12),
          const VerticalDivider(width: 1, indent: 6, endIndent: 6),
          const SizedBox(width: 12),

          // Quadrant Filter
          ChoiceChip(
            key: const ValueKey('filter-q-all'),
            label: Text(t['all'] ?? 'All'),
            selected: _selectedQuadrant == null,
            onSelected: (_) => setState(() => _selectedQuadrant = null),
          ),
          const SizedBox(width: 6),
          for (final q in allQuadrants) ...[
            ChoiceChip(
              key: ValueKey('filter-q-$q'),
              label: Text(t['q$q'] ?? 'Q$q'),
              selected: _selectedQuadrant == q,
              avatar: CircleAvatar(
                radius: 4,
                backgroundColor: Color(quadrantColors[q]!),
              ),
              onSelected:
                  (selected) =>
                      setState(() => _selectedQuadrant = selected ? q : null),
            ),
            const SizedBox(width: 6),
          ],

          const SizedBox(width: 6),
          const VerticalDivider(width: 1, indent: 6, endIndent: 6),
          const SizedBox(width: 12),

          // Status Filter
          ChoiceChip(
            key: const ValueKey('filter-status-all'),
            label: Text('${t['filterStatus'] ?? 'Status'}: ${t['all'] ?? 'All'}'),
            selected: _selectedStatus == TaskStatusFilter.all,
            onSelected: (_) => setState(() => _selectedStatus = TaskStatusFilter.all),
          ),
          const SizedBox(width: 6),
          ChoiceChip(
            key: const ValueKey('filter-status-incomplete'),
            label: Text(t['incomplete'] ?? 'Incomplete'),
            selected: _selectedStatus == TaskStatusFilter.incomplete,
            onSelected:
                (_) =>
                    setState(() => _selectedStatus = TaskStatusFilter.incomplete),
          ),
          const SizedBox(width: 6),
          ChoiceChip(
            key: const ValueKey('filter-status-completed'),
            label: Text(t['completed'] ?? 'Completed'),
            selected: _selectedStatus == TaskStatusFilter.completed,
            onSelected:
                (_) =>
                    setState(() => _selectedStatus = TaskStatusFilter.completed),
          ),

          const SizedBox(width: 12),
          const VerticalDivider(width: 1, indent: 6, endIndent: 6),
          const SizedBox(width: 12),

          // Date Filter
          ChoiceChip(
            key: const ValueKey('filter-date-all'),
            label: Text('${t['filterDate'] ?? 'Date'}: ${t['all'] ?? 'All'}'),
            selected: _selectedDate == TaskDateFilter.all,
            onSelected: (_) => setState(() => _selectedDate = TaskDateFilter.all),
          ),
          const SizedBox(width: 6),
          ChoiceChip(
            key: const ValueKey('filter-date-today'),
            label: Text(t['today'] ?? 'Today'),
            selected: _selectedDate == TaskDateFilter.today,
            onSelected:
                (_) => setState(() => _selectedDate = TaskDateFilter.today),
          ),
          const SizedBox(width: 6),
          ChoiceChip(
            key: const ValueKey('filter-date-week'),
            label: Text(t['thisWeek'] ?? 'This Week'),
            selected: _selectedDate == TaskDateFilter.thisWeek,
            onSelected:
                (_) => setState(() => _selectedDate = TaskDateFilter.thisWeek),
          ),
          const SizedBox(width: 6),
          ChoiceChip(
            key: const ValueKey('filter-date-month'),
            label: Text(t['thisMonth'] ?? 'This Month'),
            selected: _selectedDate == TaskDateFilter.thisMonth,
            onSelected:
                (_) => setState(() => _selectedDate = TaskDateFilter.thisMonth),
          ),
          const SizedBox(width: 6),
          ChoiceChip(
            key: const ValueKey('filter-date-overdue'),
            label: Text(t['overdue'] ?? 'Overdue'),
            selected: _selectedDate == TaskDateFilter.overdue,
            onSelected:
                (_) => setState(() => _selectedDate = TaskDateFilter.overdue),
          ),
          const SizedBox(width: 6),
          ChoiceChip(
            key: const ValueKey('filter-date-nodate'),
            label: Text(t['noDate'] ?? 'No Date'),
            selected: _selectedDate == TaskDateFilter.noDate,
            onSelected:
                (_) => setState(() => _selectedDate = TaskDateFilter.noDate),
          ),
        ],
      ),
    ),
  );
}

  Widget _buildResultsSummary(
    BuildContext context,
    Map<String, String> t,
    ThemeData theme,
    int count,
  ) {
    final text = (t['resultsCount'] ?? '{n} results').replaceAll('{n}', '$count');
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
  ) {
    return Center(
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
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsList(
    BuildContext context,
    Store store,
    Map<String, String> t,
    ThemeData theme,
    List<TaskSearchResult> results,
    bool isWide,
  ) {
    final activeBoardId = widget.initialBoardId ?? store.activeBoardId;

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      itemCount: results.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final hit = results[index];
        final task = hit.task;
        final subtask = hit.matchedSubtask;
        final isSubtask = hit.isSubtaskMatch;
        final isCompleted = hit.isCompleted;
        final q = task.quadrant;
        final qColor = Color(quadrantColors[q]!);
        final isOtherBoard = hit.board.id != activeBoardId;

        return InkWell(
          key: ValueKey('search-item-${hit.resultKey}'),
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            _openDetail(
              context,
              task,
              subtaskId: subtask?.id,
              isWide: isWide,
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Completion Checkbox
                SizedBox(
                  width: 32,
                  height: 32,
                  child: Checkbox(
                    key: ValueKey('search-check-${hit.resultKey}'),
                    value: isCompleted,
                    onChanged: (v) {
                      final val = v ?? false;
                      if (isSubtask && subtask != null) {
                        subtask.completed = val;
                      } else {
                        task.completed = val;
                      }
                      store.updateTask(task);
                    },
                  ),
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
                      Text(
                        hit.displayTitle,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          decoration:
                              isCompleted ? TextDecoration.lineThrough : null,
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
                    onSelected: (val) {
                      if (val == 'goToBoard') {
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
