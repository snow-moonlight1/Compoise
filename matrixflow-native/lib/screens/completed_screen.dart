import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../storage.dart';
import '../task_stats.dart';
import '../widgets/anim.dart';
import '../widgets/task_detail_panel.dart';

enum CompletedScope {
  currentBoard,
  allBoards,
}

class CompletedScreen extends StatefulWidget {
  final String? initialBoardId;

  const CompletedScreen({super.key, this.initialBoardId});

  @override
  State<CompletedScreen> createState() => _CompletedScreenState();
}

class _CompletedScreenState extends State<CompletedScreen> {
  CompletedScope _scope = CompletedScope.currentBoard;
  final Set<String> _expandedIds = {};
  String? _activeDetailTaskId;

  void _toggleExpand(String id) {
    setState(() {
      if (!_expandedIds.add(id)) {
        _expandedIds.remove(id);
      }
    });
  }

  void _openDetail(
    BuildContext context,
    Task task, {
    required bool isWide,
  }) {
    if (isWide) {
      setState(() => _activeDetailTaskId = task.id);
    } else {
      showTaskDetailSheet(context, task);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<Store>();
    final t = store.t;
    final theme = Theme.of(context);
    final activeBoardId = widget.initialBoardId ?? store.activeBoardId;

    final completedTasks = store.completedTasks(
      boardId: _scope == CompletedScope.currentBoard ? activeBoardId : null,
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
                    showTaskDetailSheet(context, detailTask);
                  }
                });
              }
            }

            final mainContent = Column(
              children: [
                _buildHeader(
                  context,
                  store,
                  t,
                  theme,
                  completedTasks.length,
                  activeBoardId,
                ),
                _buildScopeChips(context, t, theme),
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

            if (isWide && detailTask != null) {
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
                  SizedBox(
                    width: 350,
                    child: TaskDetailPanel(
                      task: detailTask,
                      isSidebar: true,
                      onClose: () {
                        setState(() => _activeDetailTaskId = null);
                      },
                    ),
                  ),
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
    Store store,
    Map<String, String> t,
    ThemeData theme,
    int count,
    String activeBoardId,
  ) {
    final countText = (t['completedCount'] ?? '{n} completed').replaceAll(
      '{n}',
      '$count',
    );
    final stats = computeTaskStats(
      tasks: store.tasks,
      boardId: _scope == CompletedScope.currentBoard ? activeBoardId : null,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 4),
      child: Row(
        children: [
          IconButton(
            key: const ValueKey('completed-back-btn'),
            tooltip: t['back'] ?? 'Back',
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
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
                Row(
                  children: [
                    Text(
                      countText,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1.5,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${t['statsCompletionRate'] ?? 'Completion'}: ${stats.percentageText}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScopeChips(
    BuildContext context,
    Map<String, String> t,
    ThemeData theme,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          ChoiceChip(
            key: const ValueKey('completed-scope-current'),
            label: Text(t['currentBoard'] ?? 'Current Board'),
            selected: _scope == CompletedScope.currentBoard,
            onSelected: (selected) {
              if (selected) {
                setState(() => _scope = CompletedScope.currentBoard);
              }
            },
          ),
          const SizedBox(width: 8),
          ChoiceChip(
            key: const ValueKey('completed-scope-all'),
            label: Text(t['allBoards'] ?? 'All Boards'),
            selected: _scope == CompletedScope.allBoards,
            onSelected: (selected) {
              if (selected) {
                setState(() => _scope = CompletedScope.allBoards);
              }
            },
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
            _scope == CompletedScope.allBoards || task.boardId != activeBoardId;

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
                                color: theme
                                    .colorScheme
                                    .surfaceContainerHighest
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
                                          color: theme
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
