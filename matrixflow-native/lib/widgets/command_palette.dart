import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../screens/completed_screen.dart';
import '../screens/search_screen.dart';
import '../screens/settings_screen.dart';
import '../shortcuts.dart';
import '../storage.dart';
import '../task_query.dart';
import 'task_detail_panel.dart';

/// Represents an executable command in the command palette.
class PaletteCommand {
  final String id;
  final String title;
  final String? subtitle;
  final IconData icon;
  final VoidCallback onExecute;

  const PaletteCommand({
    required this.id,
    required this.title,
    this.subtitle,
    required this.icon,
    required this.onExecute,
  });
}

/// In-app Command Palette modal dialog.
class CommandPaletteDialog extends StatefulWidget {
  final VoidCallback? onOpenInput;
  final int? focusedQuadrant;
  final ValueChanged<int?>? onSetFocusedQuadrant;
  final VoidCallback? onClearBoard;

  const CommandPaletteDialog({
    super.key,
    this.onOpenInput,
    this.focusedQuadrant,
    this.onSetFocusedQuadrant,
    this.onClearBoard,
  });

  @override
  State<CommandPaletteDialog> createState() => _CommandPaletteDialogState();
}

class _CommandPaletteDialogState extends State<CommandPaletteDialog> {
  final TextEditingController _queryController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _queryController.addListener(_onQueryChanged);
  }

  @override
  void dispose() {
    _queryController.removeListener(_onQueryChanged);
    _queryController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onQueryChanged() {
    setState(() {
      _selectedIndex = 0;
    });
  }

  List<PaletteCommand> _buildCommands(Store store, Map<String, String> t) {
    final commands = <PaletteCommand>[
      PaletteCommand(
        id: 'new_task',
        title: t['commandNewTask'] ?? 'New Task',
        subtitle: 'Ctrl+N',
        icon: Icons.add_task,
        onExecute: () {
          Navigator.of(context).pop();
          widget.onOpenInput?.call();
        },
      ),
      PaletteCommand(
        id: 'search',
        title: t['commandSearch'] ?? 'Search Tasks',
        subtitle: 'Ctrl+F',
        icon: Icons.search,
        onExecute: () {
          Navigator.of(context).pop();
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => SearchScreen(initialBoardId: store.activeBoardId),
            ),
          );
        },
      ),
      PaletteCommand(
        id: 'completed',
        title: t['commandCompleted'] ?? 'Completed Tasks',
        subtitle: 'Ctrl+H',
        icon: Icons.task_alt,
        onExecute: () {
          Navigator.of(context).pop();
          Navigator.of(context).push(
            MaterialPageRoute(
              builder:
                  (_) => CompletedScreen(initialBoardId: store.activeBoardId),
            ),
          );
        },
      ),
      PaletteCommand(
        id: 'toggle_view',
        title:
            store.settings.viewMode == ViewMode.grid
                ? (t['viewModeList'] ?? 'Switch to List View')
                : (t['viewModeGrid'] ?? 'Switch to Grid View'),
        subtitle: 'Ctrl+Shift+V',
        icon:
            store.settings.viewMode == ViewMode.grid
                ? Icons.view_agenda_outlined
                : Icons.grid_view,
        onExecute: () {
          Navigator.of(context).pop();
          store.toggleViewMode();
        },
      ),
      PaletteCommand(
        id: 'toggle_hide_completed',
        title:
            store.settings.hideCompleted
                ? (t['showCompleted'] ?? 'Show Completed')
                : (t['hideCompleted'] ?? 'Hide Completed'),
        icon:
            store.settings.hideCompleted
                ? Icons.visibility
                : Icons.visibility_off,
        onExecute: () {
          Navigator.of(context).pop();
          store.updateSettings((s) => s..hideCompleted = !s.hideCompleted);
        },
      ),
      // Board switching
      for (final board in store.boards)
        if (board.id != store.activeBoardId)
          PaletteCommand(
            id: 'board_${board.id}',
            title: '${t['commandSwitchBoard'] ?? 'Switch Board'}: ${board.name}',
            subtitle: '${store.boardTaskCount(board.id)} ${t['tasks'] ?? 'tasks'}',
            icon: Icons.dashboard_outlined,
            onExecute: () {
              Navigator.of(context).pop();
              store.setActiveBoard(board.id);
            },
          ),
      // Quadrant focus commands
      PaletteCommand(
        id: 'focus_q1',
        title: t['commandFocusQ1'] ?? 'Focus Q1 (Urgent & Important)',
        icon: Icons.filter_1,
        onExecute: () {
          Navigator.of(context).pop();
          widget.onSetFocusedQuadrant?.call(qDo);
        },
      ),
      PaletteCommand(
        id: 'focus_q2',
        title: t['commandFocusQ2'] ?? 'Focus Q2 (Not Urgent & Important)',
        icon: Icons.filter_2,
        onExecute: () {
          Navigator.of(context).pop();
          widget.onSetFocusedQuadrant?.call(qPlan);
        },
      ),
      PaletteCommand(
        id: 'focus_q3',
        title: t['commandFocusQ3'] ?? 'Focus Q3 (Urgent & Not Important)',
        icon: Icons.filter_3,
        onExecute: () {
          Navigator.of(context).pop();
          widget.onSetFocusedQuadrant?.call(qDelegate);
        },
      ),
      PaletteCommand(
        id: 'focus_q4',
        title: t['commandFocusQ4'] ?? 'Focus Q4 (Not Urgent & Not Important)',
        icon: Icons.filter_4,
        onExecute: () {
          Navigator.of(context).pop();
          widget.onSetFocusedQuadrant?.call(qEliminate);
        },
      ),
      if (widget.focusedQuadrant != null)
        PaletteCommand(
          id: 'exit_focus',
          title: t['commandExitFocus'] ?? 'Exit Focus (Return to Matrix)',
          subtitle: 'Esc',
          icon: Icons.fullscreen_exit,
          onExecute: () {
            Navigator.of(context).pop();
            widget.onSetFocusedQuadrant?.call(null);
          },
        ),
      PaletteCommand(
        id: 'settings',
        title: t['commandSettings'] ?? 'Open Settings',
        subtitle: 'Ctrl+,',
        icon: Icons.settings_outlined,
        onExecute: () {
          Navigator.of(context).pop();
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const SettingsScreen()),
          );
        },
      ),
      PaletteCommand(
        id: 'shortcuts_help',
        title: t['shortcutsHelp'] ?? 'Keyboard Shortcuts Help',
        subtitle: 'Ctrl+/',
        icon: Icons.keyboard_outlined,
        onExecute: () {
          Navigator.of(context).pop();
          showShortcutsHelpDialog(context, t);
        },
      ),
      if (store.boardTaskCount(store.activeBoardId) > 0 &&
          widget.onClearBoard != null)
        PaletteCommand(
          id: 'clear_board',
          title: t['clearBoard'] ?? 'Clear This Board',
          icon: Icons.delete_sweep_outlined,
          onExecute: () {
            Navigator.of(context).pop();
            widget.onClearBoard?.call();
          },
        ),
    ];

    final query = _queryController.text.trim().toLowerCase();
    if (query.isEmpty) return commands;

    return commands
        .where(
          (c) =>
              c.title.toLowerCase().contains(query) ||
              (c.subtitle != null && c.subtitle!.toLowerCase().contains(query)),
        )
        .toList();
  }

  List<TaskSearchResult> _searchTasks(Store store) {
    final query = _queryController.text.trim();
    if (query.isEmpty) return const [];

    return queryTasks(
      tasks: store.tasks,
      boards: store.boards,
      activeBoardId: store.activeBoardId,
      query: query,
      scope: TaskScopeFilter.allBoards,
    );
  }

  void _onKey(KeyEvent event, int totalItems, VoidCallback onConfirm) {
    if (event is! KeyDownEvent) return;

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (totalItems > 0) {
        setState(() {
          _selectedIndex = (_selectedIndex + 1) % totalItems;
        });
      }
    } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (totalItems > 0) {
        setState(() {
          _selectedIndex = (_selectedIndex - 1 + totalItems) % totalItems;
        });
      }
    } else if (event.logicalKey == LogicalKeyboardKey.enter) {
      onConfirm();
    } else if (event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<Store>();
    final t = store.t;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final matchingCommands = _buildCommands(store, t);
    final matchingTasks = _searchTasks(store);
    final totalItems = matchingCommands.length + matchingTasks.length;

    // Safety clamp
    if (_selectedIndex >= totalItems && totalItems > 0) {
      _selectedIndex = totalItems - 1;
    }

    void confirmSelection() {
      if (totalItems == 0) return;
      if (_selectedIndex < matchingCommands.length) {
        matchingCommands[_selectedIndex].onExecute();
      } else {
        final taskIdx = _selectedIndex - matchingCommands.length;
        final res = matchingTasks[taskIdx];
        Navigator.of(context).pop();
        if (res.board.id != store.activeBoardId) {
          store.setActiveBoard(res.board.id);
        }
        showTaskDetailSheet(
          context,
          res.task,
          highlightSubtaskId: res.matchedSubtask?.id,
        );
      }
    }

    return KeyboardListener(
      focusNode: _focusNode,
      onKeyEvent: (event) => _onKey(event, totalItems, confirmSelection),
      child: Dialog(
        alignment: Alignment.topCenter,
        insetPadding: const EdgeInsets.fromLTRB(16, 60, 16, 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 580,
            maxHeight: 520,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Search text field
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color:
                          isDark
                              ? theme.colorScheme.outlineVariant
                              : const Color(0xFFE2E8F0),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.terminal_outlined,
                      color: theme.colorScheme.primary,
                      size: 22,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        key: const ValueKey('command-palette-input'),
                        controller: _queryController,
                        autofocus: true,
                        decoration: InputDecoration(
                          hintText:
                              t['commandPaletteHint'] ??
                              'Type a command or search tasks...',
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        style: theme.textTheme.bodyLarge,
                      ),
                    ),
                    if (_queryController.text.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () => _queryController.clear(),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ),
              // Results list
              Expanded(
                child:
                    totalItems == 0
                        ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24.0),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.search_off,
                                  size: 40,
                                  color: theme.disabledColor,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  t['noMatchingCommandsOrTasks'] ??
                                      'No matching commands or tasks',
                                  style: TextStyle(color: theme.disabledColor),
                                ),
                              ],
                            ),
                          ),
                        )
                        : ListView.builder(
                          itemCount:
                              (matchingCommands.isNotEmpty ? 1 : 0) +
                              matchingCommands.length +
                              (matchingTasks.isNotEmpty ? 1 : 0) +
                              matchingTasks.length,
                          itemBuilder: (context, index) {
                            var cursor = 0;

                            // Commands header
                            if (matchingCommands.isNotEmpty) {
                              if (index == cursor) {
                                return _buildSectionHeader(
                                  t['commandsCategory'] ?? 'Commands',
                                  theme,
                                );
                              }
                              cursor++;
                              if (index < cursor + matchingCommands.length) {
                                final cmdIdx = index - cursor;
                                final cmd = matchingCommands[cmdIdx];
                                final isSelected = _selectedIndex == cmdIdx;
                                return _buildCommandTile(
                                  cmd,
                                  isSelected,
                                  theme,
                                  isDark,
                                  () {
                                    setState(() => _selectedIndex = cmdIdx);
                                    cmd.onExecute();
                                  },
                                );
                              }
                              cursor += matchingCommands.length;
                            }

                            // Tasks header
                            if (matchingTasks.isNotEmpty) {
                              if (index == cursor) {
                                return _buildSectionHeader(
                                  t['tasksCategory'] ?? 'Tasks',
                                  theme,
                                );
                              }
                              cursor++;
                              final taskIdx = index - cursor;
                              final taskRes = matchingTasks[taskIdx];
                              final overallIdx =
                                  matchingCommands.length + taskIdx;
                              final isSelected = _selectedIndex == overallIdx;
                              return _buildTaskTile(
                                taskRes,
                                isSelected,
                                theme,
                                isDark,
                                t,
                                () {
                                  setState(() => _selectedIndex = overallIdx);
                                  confirmSelection();
                                },
                              );
                            }

                            return const SizedBox.shrink();
                          },
                        ),
              ),
              // Footer with keyboard tips
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color:
                      isDark
                          ? theme.colorScheme.surfaceContainerHighest.withValues(
                            alpha: 0.4,
                          )
                          : const Color(0xFFF8FAFC),
                  border: Border(
                    top: BorderSide(
                      color:
                          isDark
                              ? theme.colorScheme.outlineVariant
                              : const Color(0xFFE2E8F0),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    _keyBadge('↑↓', t['shortcutNavigate'] ?? 'Navigate', theme),
                    const SizedBox(width: 14),
                    _keyBadge('Enter', t['shortcutSelect'] ?? 'Select', theme),
                    const SizedBox(width: 14),
                    _keyBadge('Esc', t['shortcutClose'] ?? 'Close', theme),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        title.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _buildCommandTile(
    PaletteCommand cmd,
    bool isSelected,
    ThemeData theme,
    bool isDark,
    VoidCallback onTap,
  ) {
    final bg =
        isSelected
            ? theme.colorScheme.primary.withValues(alpha: isDark ? 0.25 : 0.12)
            : Colors.transparent;

    return InkWell(
      onTap: onTap,
      child: Container(
        color: bg,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(
              cmd.icon,
              size: 20,
              color:
                  isSelected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                cmd.title,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
            if (cmd.subtitle != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color:
                      isDark
                          ? theme.colorScheme.surfaceContainerHighest
                          : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  cmd.subtitle!,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontFamily: 'monospace',
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTaskTile(
    TaskSearchResult res,
    bool isSelected,
    ThemeData theme,
    bool isDark,
    Map<String, String> t,
    VoidCallback onTap,
  ) {
    final bg =
        isSelected
            ? theme.colorScheme.primary.withValues(alpha: isDark ? 0.25 : 0.12)
            : Colors.transparent;

    final qColor = switch (res.task.quadrant) {
      1 => const Color(0xFFEF4444),
      2 => const Color(0xFF3B82F6),
      3 => const Color(0xFFF59E0B),
      _ => const Color(0xFF10B981),
    };

    return InkWell(
      onTap: onTap,
      child: Container(
        color: bg,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: qColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      if (res.isCompleted)
                        const Padding(
                          padding: EdgeInsets.only(right: 6),
                          child: Icon(
                            Icons.check_circle,
                            size: 14,
                            color: Colors.green,
                          ),
                        ),
                      Expanded(
                        child: Text(
                          res.displayTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight:
                                isSelected ? FontWeight.w600 : FontWeight.normal,
                            decoration:
                                res.isCompleted
                                    ? TextDecoration.lineThrough
                                    : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    res.pathDisplay,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: qColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'Q${res.task.quadrant}',
                style: TextStyle(
                  color: qColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _keyBadge(String keyText, String label, ThemeData theme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            keyText,
            style: theme.textTheme.labelSmall?.copyWith(
              fontFamily: 'monospace',
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// Helper function to display the in-app command palette modal dialog.
Future<void> showCommandPalette(
  BuildContext context, {
  VoidCallback? onOpenInput,
  int? focusedQuadrant,
  ValueChanged<int?>? onSetFocusedQuadrant,
  VoidCallback? onClearBoard,
}) {
  return showDialog<void>(
    context: context,
    builder:
        (_) => CommandPaletteDialog(
          onOpenInput: onOpenInput,
          focusedQuadrant: focusedQuadrant,
          onSetFocusedQuadrant: onSetFocusedQuadrant,
          onClearBoard: onClearBoard,
        ),
  );
}
