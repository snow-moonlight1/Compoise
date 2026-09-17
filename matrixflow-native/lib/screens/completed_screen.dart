import '../widgets/reminder_failure_banner.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../storage.dart';
import '../task_query.dart';
import '../task_stats.dart';
import '../ui/platform_ui_policy.dart';
import '../widgets/anim.dart';
import '../widgets/task_detail_panel.dart';
import '../widgets/task_filter_panel.dart';

class CompletedScreen extends StatefulWidget {
  final String? initialBoardId;

  const CompletedScreen({super.key, this.initialBoardId});

  @override
  State<CompletedScreen> createState() => _CompletedScreenState();
}

class _CompletedScreenState extends State<CompletedScreen> {
  TaskFilterCriteria _applied = const TaskFilterCriteria();
  final Set<String> _expandedIds = {};
  String? _activeDetailTaskId;
  bool _detailDirty = false;
  final _detailKey = GlobalKey();

  String _boardName(Store store, String boardId) {
    return resolveBoardName(
      boards: store.boards,
      boardId: boardId,
      unknownLabel: store.t['unknownBoard'] ?? 'Unknown board',
    );
  }

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
      setState(
        () => _applied = TaskFilterCriteria(scope: result.scope),
      );
    }
  }

  void _clearFilters() {
    setState(() => _applied = const TaskFilterCriteria());
  }

  void _toggleExpand(String id) {
    setState(() {
      if (!_expandedIds.add(id)) {
        _expandedIds.remove(id);
      }
    });
  }

  Future<bool> _protectDetailDraft() async {
    if (!_detailDirty) return true;
    final discard = await confirmDiscardDraft(context);
    if (discard) _detailDirty = false;
    return discard;
  }

  Future<void> _openDetail(
    BuildContext context,
    Task task, {
    required bool isWide,
  }) async {
    if (isWide) {
      if (_activeDetailTaskId != null &&
          _activeDetailTaskId != task.id &&
          !await _protectDetailDraft()) {
        return;
      }
      if (!mounted) return;
      setState(() => _activeDetailTaskId = task.id);
    } else {
      await showTaskDetailSheet(context, task);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<Store>();
    final t = store.t;
    final theme = Theme.of(context);
    final activeBoardId = widget.initialBoardId ?? store.activeBoardId;

    final rawCompletedTasks = store.completedTasks(
      boardId:
          _applied.scope == TaskScopeFilter.currentBoard
              ? activeBoardId
              : null,
    );
    final completedTasks = sortCompletedTasks(rawCompletedTasks);
    final policy = PlatformUiPolicy.of(context);
    final boardName = _boardName(store, activeBoardId);
    final activeCount = _applied.dimensionCount(TaskFilterKind.archive);

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
            final isWide = constraints.maxWidth >= 900;
            final detailTask =
                _activeDetailTaskId == null
                    ? null
                    : store.tasks
                        .where((item) => item.id == _activeDetailTaskId)
                        .firstOrNull;

            final mainContent = Column(
              children: [
                _buildHeader(
                  context,
                  t,
                  theme,
                  completedTasks.length,
                  policy,
                  activeCount,
                  constraints.maxWidth,
                ),
                const ReminderFailureBanner(),
                AppliedFilterSummary(
                  criteria: _applied,
                  kind: TaskFilterKind.archive,
                  currentBoardName: boardName,
                ),
                Expanded(
                  child:
                      completedTasks.isEmpty
                          ? _buildEmptyState(context, t, theme)
                          : _buildList(
                            context,
                            store,
                            t,
                            theme,
                            completedTasks,
                            activeBoardId,
                            isWide,
                          ),
                ),
              ],
            );

            if (detailTask != null) {
              final panel = TaskDetailPanel(
                key: _detailKey,
                task: detailTask,
                isSidebar: true,
                onDirtyChanged: (dirty) {
                  if (_detailDirty == dirty) return;
                  _detailDirty = dirty;
                },
                onClose: () {
                  setState(() {
                    _activeDetailTaskId = null;
                    _detailDirty = false;
                  });
                },
              );
              if (!isWide) return panel;
              return Row(
                children: [
                  Expanded(child: mainContent),
                  VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color:
                        theme.brightness == Brightness.light
                            ? const Color(0xFFD5DAE1)
                            : theme.colorScheme.outlineVariant,
                  ),
                  SizedBox(width: 350, child: panel),
                ],
              );
            }

            return mainContent;
          },
        ),
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    Map<String, String> t,
    ThemeData theme,
    int count,
    PlatformUiPolicy policy,
    int activeCount,
    double maxWidth,
  ) {
    final countText = (t['completedCount'] ?? '{n} items in list').replaceAll(
      '{n}',
      '$count',
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 4),
      child: Row(
        children: [
          IconButton(
            key: const ValueKey('completed-back-btn'),
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
                  t['completedTasks'] ?? 'Completed Tasks',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  countText,
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
              compact: policy.compactHeaderActions(maxWidth),
            ),
        ],
      ),
    );
  }

  String _formatCompletionTime(int ms, Map<String, String> t) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    final now = DateTime.now();
    final isToday =
        dt.year == now.year && dt.month == now.month && dt.day == now.day;
    final yesterday = now.subtract(const Duration(days: 1));
    final isYesterday =
        dt.year == yesterday.year &&
        dt.month == yesterday.month &&
        dt.day == yesterday.day;
    final timeStr =
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    if (isToday) {
      return '${t['today'] ?? 'Today'} $timeStr';
    } else if (isYesterday) {
      return '${t['yesterday'] ?? 'Yesterday'} $timeStr';
    } else {
      final dateStr =
          '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
      return '$dateStr $timeStr';
    }
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
            Icons.check_circle_outline,
            size: 56,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(height: 12),
          Text(
            t['noCompletedTasks'] ?? 'No completed tasks',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(
    BuildContext context,
    Store store,
    Map<String, String> t,
    ThemeData theme,
    List<Task> tasks,
    String activeBoardId,
    bool isWide,
  ) {
    final boardMap = {for (final b in store.boards) b.id: b.name};

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      itemCount: tasks.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final task = tasks[index];
        final isExpanded = _expandedIds.contains(task.id);
        final q = task.quadrant;
        final qColor = Color(quadrantColors[q] ?? 0xFF888888);
        final qName = t['q$q'] ?? 'Q$q';
        final boardName = boardMap[task.boardId] ?? task.boardId;
        final showBoardBadge =
            _applied.scope == TaskScopeFilter.allBoards ||
            task.boardId != activeBoardId;

        return InkWell(
          key: ValueKey('completed-item-${task.id}'),
          borderRadius: BorderRadius.circular(8),
          onTap: () => _openDetail(context, task, isWide: isWide),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Completed Checkbox: tapping it restores task
                Semantics(
                  label: t['restoreTask'] ?? 'Restore',
                  button: true,
                  child: SizedBox(
                    width: 36,
                    height: 36,
                    child: Center(
                      child: Checkbox(
                        key: ValueKey('completed-check-${task.id}'),
                        value: true,
                        onChanged: (_) {
                          store.restoreTask(task);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                t['taskRestored'] ?? 'Task restored',
                              ),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Board and Quadrant Badges
                      Row(
                        children: [
                          if (showBoardBadge) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surfaceContainerHighest
                                    .withValues(alpha: 0.6),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                boardName,
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
                              qName,
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

                      // Title with strike-through
                      StrikeThrough(
                        crossed: true,
                        child: Text(
                          task.title,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontSize: 15,
                            height: 1.35,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.5,
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              task.completedAt != null
                                  ? Icons.event_available
                                  : Icons.help_outline,
                              size: 13,
                              color: theme.colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.7),
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                task.completedAt != null
                                    ? (t['completedAtTime'] ??
                                            'Completed: {time}')
                                        .replaceAll(
                                          '{time}',
                                          _formatCompletionTime(
                                            task.completedAt!,
                                            t,
                                          ),
                                        )
                                    : (t['timeUnknown'] ?? 'Time unknown'),
                                key: ValueKey('completed-time-${task.id}'),
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant
                                      .withValues(alpha: 0.8),
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Subtasks toggle & progress
                      if (task.subtasks.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        InkWell(
                          key: ValueKey('completed-expand-${task.id}'),
                          borderRadius: BorderRadius.circular(4),
                          onTap: () => _toggleExpand(task.id),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isExpanded
                                      ? Icons.keyboard_arrow_down
                                      : Icons.keyboard_arrow_right,
                                  size: 16,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  (t['subtaskProgress'] ??
                                          'Subtasks {done}/{total}')
                                      .replaceAll(
                                        '{done}',
                                        '${task.subtasks.where((s) => s.completed).length}',
                                      )
                                      .replaceAll(
                                        '{total}',
                                        '${task.subtasks.length}',
                                      ),
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (isExpanded)
                          Padding(
                            padding: const EdgeInsets.only(left: 12, top: 4),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                for (final s in task.subtasks)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 2,
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          s.completed
                                              ? Icons.check_circle_outline
                                              : Icons.radio_button_unchecked,
                                          size: 14,
                                          color:
                                              theme
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            s.title,
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                                  decoration:
                                                      s.completed
                                                          ? TextDecoration
                                                              .lineThrough
                                                          : null,
                                                  color: theme
                                                      .colorScheme
                                                      .onSurface
                                                      .withValues(alpha: 0.5),
                                                ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ],
                  ),
                ),

                // Restore button
                IconButton(
                  key: ValueKey('completed-restore-${task.id}'),
                  tooltip: t['restoreTask'] ?? 'Restore',
                  icon: const Icon(Icons.restore, size: 20),
                  onPressed: () {
                    store.restoreTask(task);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(t['taskRestored'] ?? 'Task restored'),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                ),

                // Delete permanently button (strictly scoped to this task)
                IconButton(
                  key: ValueKey('completed-delete-${task.id}'),
                  tooltip: t['deleteCompletedTask'] ?? 'Delete',
                  icon: Icon(
                    Icons.delete_outline,
                    size: 20,
                    color: theme.colorScheme.error.withValues(alpha: 0.7),
                  ),
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder:
                          (ctx) => AlertDialog(
                            title: Text(t['deleteCompletedTask'] ?? 'Delete'),
                            content: Text(
                              t['confirmDeleteCompletedTask'] ??
                                  'Delete this completed task permanently?',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: Text(t['cancelSelection'] ?? 'Cancel'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: Text(
                                  t['delete'] ?? 'Delete',
                                  style: TextStyle(
                                    color: theme.colorScheme.error,
                                  ),
                                ),
                              ),
                            ],
                          ),
                    );
                    if (confirmed == true) {
                      store.deleteTask(task.id);
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
