import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../storage.dart';
import '../shortcuts.dart';
import '../widgets/command_palette.dart';
import '../widgets/input_sheet.dart';
import '../widgets/quadrant_focus_view.dart';
import '../widgets/quadrant_pane.dart';
import '../widgets/task_detail_panel.dart';
import '../widgets/task_list_view.dart';
import '../widgets/task_stats_bar.dart';
import '../widgets/text_prompt.dart';
import 'completed_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';

class MatrixHome extends StatefulWidget {
  const MatrixHome({super.key});

  @override
  State<MatrixHome> createState() => _MatrixHomeState();
}

class _MatrixHomeState extends State<MatrixHome> {
  bool _selecting = false;
  final Set<String> _selectedIds = {};
  final Set<String> _expandedKeys = {};
  int? _focusedQuadrant;
  final Map<String, double> _focusScrollOffsets = {};

  final Map<String, int> _subtaskCounts = {};

  String _expandKey(Task task) => '${task.boardId}/${task.id}';

  Set<String> _expandedIdsFor(Store store) => {
    for (final task in store.visibleTasks)
      if (_expandedKeys.contains(_expandKey(task))) task.id,
  };

  void _toggleExpand(Store store, String id) {
    final task = store.tasks.where((item) => item.id == id).firstOrNull;
    if (task == null) return;
    setState(() {
      final key = _expandKey(task);
      if (!_expandedKeys.add(key)) _expandedKeys.remove(key);
    });
  }

  void _ensureExpanded(Store store, String id) {
    final task = store.tasks.where((item) => item.id == id).firstOrNull;
    if (task == null) return;
    setState(() => _expandedKeys.add(_expandKey(task)));
  }

  String? _activeDetailTaskId;

  void _openTaskDetail(
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

  bool _isTextEditingFocused() {
    final focus = FocusManager.instance.primaryFocus;
    if (focus == null) return false;
    final widget = focus.context?.widget;
    return widget is EditableText;
  }

  void _openCommandPalette() {
    final store = context.read<Store>();
    showCommandPalette(
      context,
      onOpenInput: _openInput,
      focusedQuadrant: _focusedQuadrant,
      onSetFocusedQuadrant: (q) => setState(() => _focusedQuadrant = q),
      onClearBoard: () => _clearBoard(context, store),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final store = context.read<Store>();
      if (store.corruptNotice != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(store.corruptNotice!)));
        store.corruptNotice = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<Store>();
    final t = store.t;
    final theme = Theme.of(context);
    final board = store.activeBoard;
    _selectedIds.retainAll(store.visibleTasks.map((task) => task.id));
    _expandedKeys.retainAll(
      store.tasks.map(_expandKey),
    );

    for (final task in store.visibleTasks) {
      final prev = _subtaskCounts[task.id];
      if (prev != null && task.subtasks.length > prev) {
        _expandedKeys.add(_expandKey(task));
      }
      _subtaskCounts[task.id] = task.subtasks.length;
    }

    return PopScope(
      canPop: !_selecting && _focusedQuadrant == null,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_selecting) {
          setState(() {
            _selecting = false;
            _selectedIds.clear();
          });
          return;
        }
        if (_focusedQuadrant != null) {
          setState(() {
            _focusedQuadrant = null;
          });
          return;
        }
      },
      child: Shortcuts(
        shortcuts: matrixShortcuts,
        child: Actions(
          actions: {
            OpenCommandPaletteIntent: CallbackAction<OpenCommandPaletteIntent>(
              onInvoke: (_) {
                _openCommandPalette();
                return null;
              },
            ),
            NewTaskIntent: CallbackAction<NewTaskIntent>(
              onInvoke: (_) {
                if (!_isTextEditingFocused()) {
                  _openInput();
                }
                return null;
              },
            ),
            SearchTasksIntent: CallbackAction<SearchTasksIntent>(
              onInvoke: (_) {
                if (!_isTextEditingFocused()) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder:
                          (_) => SearchScreen(initialBoardId: store.activeBoardId),
                    ),
                  );
                }
                return null;
              },
            ),
            OpenCompletedIntent: CallbackAction<OpenCompletedIntent>(
              onInvoke: (_) {
                if (!_isTextEditingFocused()) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder:
                          (_) => CompletedScreen(
                            initialBoardId: store.activeBoardId,
                          ),
                    ),
                  );
                }
                return null;
              },
            ),
            ToggleViewModeIntent: CallbackAction<ToggleViewModeIntent>(
              onInvoke: (_) {
                if (!_isTextEditingFocused()) {
                  store.toggleViewMode();
                }
                return null;
              },
            ),
            OpenSettingsIntent: CallbackAction<OpenSettingsIntent>(
              onInvoke: (_) {
                if (!_isTextEditingFocused()) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  );
                }
                return null;
              },
            ),
            ShortcutsHelpIntent: CallbackAction<ShortcutsHelpIntent>(
              onInvoke: (_) {
                showShortcutsHelpDialog(context, t);
                return null;
              },
            ),
            EscapeIntent: CallbackAction<EscapeIntent>(
              onInvoke: (_) {
                final focus = FocusManager.instance.primaryFocus;
                if (focus != null && focus.context?.widget is EditableText) {
                  focus.unfocus();
                  return null;
                }
                if (_selecting) {
                  setState(() {
                    _selecting = false;
                    _selectedIds.clear();
                  });
                } else if (_focusedQuadrant != null) {
                  setState(() => _focusedQuadrant = null);
                } else if (_activeDetailTaskId != null) {
                  setState(() => _activeDetailTaskId = null);
                }
                return null;
              },
            ),
          },
          child: Focus(
            autofocus: true,
            child: Scaffold(
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 900;
              final detailTask =
                  _activeDetailTaskId == null
                      ? null
                      : store.tasks
                          .where((t) => t.id == _activeDetailTaskId)
                          .firstOrNull;

              if (!wide && _activeDetailTaskId != null) {
                _activeDetailTaskId = null;
                if (detailTask != null) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) showTaskDetailSheet(context, detailTask);
                  });
                }
              }

              final activeCenter =
                  _focusedQuadrant != null
                      ? _focusView(wide: wide, focusedQ: _focusedQuadrant!)
                      : store.settings.viewMode == ViewMode.grid
                          ? _grid(wide: wide)
                          : TaskListView(
                              selecting: _selecting,
                              selectedIds: _selectedIds,
                              expandedIds: _expandedIdsFor(store),
                              onSelect: (id) => setState(() {
                                if (!_selectedIds.add(id)) _selectedIds.remove(id);
                              }),
                              onToggleExpand: (id) => _toggleExpand(store, id),
                              onEnsureExpanded: (id) => _ensureExpanded(store, id),
                              onQuadrantTap: (q) => setState(() => _focusedQuadrant = q),
                              onEdit: (task) => _openTaskDetail(context, task, isWide: wide),
                            );

              Widget mainContent;
              if (wide) {
                final showSidebar = detailTask != null;
                final showLeftInput =
                    constraints.maxWidth >= 1220 || !showSidebar;
                mainContent = Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (showLeftInput) ...[
                      SizedBox(
                        width: 320,
                        child: _InputPanel(
                          initialMode: store.settings.defaultInputMode,
                        ),
                      ),
                      const SizedBox(width: 14),
                    ],
                    Expanded(child: activeCenter),
                    if (showSidebar) ...[
                      const SizedBox(width: 14),
                      SizedBox(
                        width: 340,
                        child: TaskDetailPanel(
                          task: detailTask,
                          isSidebar: true,
                          onClose:
                              () => setState(() => _activeDetailTaskId = null),
                        ),
                      ),
                    ],
                  ],
                );
              } else {
                mainContent = activeCenter;
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _header(
                    context,
                    store,
                    t,
                    theme,
                    board?.name ?? t['defaultBoardName']!,
                  ),
                  const TaskStatsBar(),
                  if (store.persistenceError != null)
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        store.persistenceError!,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(4, 2, 4, 2),
                      child: mainContent,
                    ),
                  ),
                  _bottomBar(context, store, t, theme, wide),
                ],
              );
            },
          ),
            ),
          ),
        ),
      ),
    ),
  );
}

  Widget _bottomBar(
    BuildContext context,
    Store store,
    Map<String, String> t,
    ThemeData theme,
    bool wide,
  ) {
    if (_selecting) {
      return Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(
            top: BorderSide(
              color:
                  theme.brightness == Brightness.light
                      ? const Color(0xFFD5DAE1)
                      : theme.colorScheme.outlineVariant,
            ),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                t['multiSelectStatus']!.replaceAll(
                  '{n}',
                  '${_selectedIds.length}',
                ),
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (_selectedIds.length == 1)
              TextButton.icon(
                onPressed: () {
                  final task =
                      store.tasks
                          .where((item) => item.id == _selectedIds.single)
                          .firstOrNull;
                  if (task != null) {
                    _openTaskDetail(context, task, isWide: wide);
                  }
                },
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: Text(t['editTask']!),
              ),
            if (_selectedIds.length >= 2)
              FilledButton.tonal(
                onPressed: () => _groupSelected(context, store),
                child: Text(
                  '${t['groupSelected']} (${_selectedIds.length})',
                ),
              ),
            const SizedBox(width: 4),
            IconButton(
              key: const ValueKey('exit-selection-btn'),
              icon: const Icon(Icons.close),
              onPressed:
                  () => setState(() {
                    _selecting = false;
                    _selectedIds.clear();
                  }),
            ),
          ],
        ),
      );
    }

    if (!wide) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
        child: Row(
          children: [
            FloatingActionButton.extended(
              tooltip: t['addBtn'],
              onPressed: _openInput,
              icon: const Icon(Icons.add),
              label: Text(t['addBtn']!),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _focusView({required bool wide, required int focusedQ}) {
    final store = context.read<Store>();
    return QuadrantFocusView(
      focusedQuadrant: focusedQ,
      selecting: _selecting,
      selectedIds: _selectedIds,
      expandedIds: _expandedIdsFor(store),
      onSelect:
          (id) => setState(() {
            if (!_selectedIds.add(id)) _selectedIds.remove(id);
          }),
      onToggleExpand: (id) => _toggleExpand(store, id),
      onEnsureExpanded: (id) => _ensureExpanded(store, id),
      onSwitchQuadrant: (newQ) => setState(() => _focusedQuadrant = newQ),
      onExitFocus: () => setState(() => _focusedQuadrant = null),
      onEdit: (task) => _openTaskDetail(context, task, isWide: wide),
    );
  }

  Widget _grid({required bool wide}) {
    final theme = Theme.of(context);
    final dividerColor =
        theme.brightness == Brightness.light
            ? const Color(0xFFD5DAE1)
            : theme.colorScheme.outlineVariant;

    Widget pane(int q) => QuadrantPane(
      quadrant: q,
      selecting: _selecting,
      selectedIds: _selectedIds,
      expandedIds: _expandedIdsFor(context.read<Store>()),
      onSelect:
          (id) => setState(() {
            if (!_selectedIds.add(id)) _selectedIds.remove(id);
          }),
      onToggleExpand: (id) => _toggleExpand(context.read<Store>(), id),
      onEnsureExpanded: (id) => _ensureExpanded(context.read<Store>(), id),
      onQuadrantTap: () => setState(() => _focusedQuadrant = q),
      onEdit: (task) => _openTaskDetail(context, task, isWide: wide),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final grid = SizedBox(
          height: constraints.maxHeight < 440 ? 440 : constraints.maxHeight,
          child: Column(
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: pane(qDo)),
                    VerticalDivider(
                      width: 1,
                      thickness: 1,
                      color: dividerColor,
                    ),
                    Expanded(child: pane(qPlan)),
                  ],
                ),
              ),
              Divider(height: 1, thickness: 1, color: dividerColor),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: pane(qDelegate)),
                    VerticalDivider(
                      width: 1,
                      thickness: 1,
                      color: dividerColor,
                    ),
                    Expanded(child: pane(qEliminate)),
                  ],
                ),
              ),
            ],
          ),
        );
        return constraints.maxHeight < 440
            ? SingleChildScrollView(child: grid)
            : grid;
      },
    );
  }

  Widget _header(
    BuildContext context,
    Store store,
    Map<String, String> t,
    ThemeData theme,
    String boardName,
  ) {
    return IconButtonTheme(
      data: IconButtonThemeData(
        style: IconButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.all(4),
          minimumSize: const Size(34, 34),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 8, 4),
        child: Row(
          children: [
          if (_focusedQuadrant != null) ...[
            IconButton(
              key: const ValueKey('focus-back-btn'),
              tooltip: t['back'] ?? 'Back',
              icon: const Icon(Icons.arrow_back),
              onPressed: () => setState(() => _focusedQuadrant = null),
            ),
            const SizedBox(width: 4),
          ],
          // Board switcher
          Expanded(
            child: PopupMenuButton<String>(
              tooltip: t['boards'],
              onSelected: (value) {
                setState(() {
                  _selecting = false;
                  _selectedIds.clear();
                  _activeDetailTaskId = null;
                  _focusedQuadrant = null;
                });
                if (value == '__new') {
                  _createBoard(context, store);
                } else if (value == '__rename') {
                  _renameBoard(context, store);
                } else if (value == '__clear') {
                  _clearBoard(context, store);
                } else if (value == '__delete') {
                  _deleteBoard(context, store);
                } else {
                  store.setActiveBoard(value);
                }
              },
              itemBuilder:
                  (context) => [
                    for (final b in store.boards)
                      PopupMenuItem(
                        value: b.id,
                        child: Row(
                          children: [
                            if (b.id == store.activeBoardId)
                              Icon(
                                Icons.check,
                                size: 16,
                                color: theme.colorScheme.primary,
                              )
                            else
                              const SizedBox(width: 16),
                            Expanded(
                              child: Text(
                                b.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    const PopupMenuDivider(),
                    PopupMenuItem(
                      value: '__new',
                      child: Row(
                        children: [
                          const Icon(Icons.add, size: 16),
                          const SizedBox(width: 8),
                          Text(t['createBoard']!),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: '__rename',
                      child: Row(
                        children: [
                          const Icon(Icons.edit_outlined, size: 16),
                          const SizedBox(width: 8),
                          Text(t['renameBoard']!),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      key: const ValueKey('clear-board-menu-item'),
                      value: '__clear',
                      enabled: store.boardTaskCount(store.activeBoardId) > 0,
                      child: Row(
                        children: [
                          Icon(
                            Icons.delete_sweep_outlined,
                            size: 16,
                            color:
                                store.boardTaskCount(store.activeBoardId) > 0
                                    ? theme.colorScheme.error
                                    : theme.disabledColor,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            t['clearBoard']!,
                            style: TextStyle(
                              color:
                                  store.boardTaskCount(store.activeBoardId) > 0
                                      ? theme.colorScheme.error
                                      : theme.disabledColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (store.boards.length > 1)
                      PopupMenuItem(
                        value: '__delete',
                        child: Row(
                          children: [
                            Icon(
                              Icons.delete_outline,
                              size: 16,
                              color: theme.colorScheme.error,
                            ),
                            const SizedBox(width: 8),
                            Text(t['deleteBoard']!),
                          ],
                        ),
                      ),
                  ],
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      boardName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.keyboard_arrow_down),
                ],
              ),
            ),
          ),
          IconButton(
            key: const ValueKey('command-palette-btn'),
            tooltip: '${t['commandPalette'] ?? 'Command Palette'} (Ctrl+K)',
            onPressed: _openCommandPalette,
            icon: const Icon(Icons.terminal_outlined),
          ),
          IconButton(
            key: const ValueKey('search-btn'),
            tooltip: t['search'] ?? 'Search',
            onPressed:
                () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder:
                        (_) => SearchScreen(initialBoardId: store.activeBoardId),
                  ),
                ),
            icon: const Icon(Icons.search),
          ),
          IconButton(
            key: const ValueKey('completed-btn'),
            tooltip: t['completedTasks'] ?? 'Completed Tasks',
            onPressed:
                () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder:
                        (_) => CompletedScreen(
                          initialBoardId: store.activeBoardId,
                        ),
                  ),
                ),
            icon: const Icon(Icons.task_alt),
          ),
          IconButton(
            tooltip: _selecting ? t['cancelSelection'] : t['selectionMode'],
            onPressed:
                () => setState(() {
                  _selecting = !_selecting;
                  _selectedIds.clear();
                }),
            icon: Icon(
              Icons.layers,
              color: _selecting ? theme.colorScheme.primary : null,
            ),
          ),
          IconButton(
            tooltip: t['hideCompleted'],
            onPressed:
                () => store.updateSettings(
                  (s) => s..hideCompleted = !s.hideCompleted,
                ),
            icon: Icon(
              store.settings.hideCompleted
                  ? Icons.visibility_off
                  : Icons.visibility,
              color:
                  store.settings.hideCompleted
                      ? theme.colorScheme.primary
                      : null,
            ),
          ),
          IconButton(
            key: const ValueKey('view-mode-toggle-btn'),
            tooltip:
                store.settings.viewMode == ViewMode.grid
                    ? (t['viewModeList'] ?? 'List View')
                    : (t['viewModeGrid'] ?? 'Grid View'),
            onPressed: () => store.toggleViewMode(),
            icon: Icon(
              store.settings.viewMode == ViewMode.grid
                  ? Icons.view_agenda_outlined
                  : Icons.grid_view,
            ),
          ),
          IconButton(
            tooltip: t['settings'],
            onPressed:
                () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                ),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
    ),
  );
}

  Future<void> _openInput() async {
    final store = context.read<Store>();
    final longTerm = await showModalBottomSheet<List<Task>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => InputSheet(initialMode: store.settings.defaultInputMode),
    );
    if (!mounted || longTerm == null || longTerm.isEmpty) return;
    await showBatchDecomposeSheet(context, longTerm);
  }

  Future<void> _createBoard(BuildContext context, Store store) async {
    final name = await _askText(
      context,
      store.t['boardName']!,
      store.t['createBoard']!,
      initial: store.t['untitledBoard']!,
    );
    if (context.mounted && name != null && name.trim().isNotEmpty) {
      store.createBoard(name.trim());
    }
  }

  Future<void> _renameBoard(BuildContext context, Store store) async {
    final board = store.activeBoard;
    if (board == null) return;
    final name = await _askText(
      context,
      store.t['boardName']!,
      store.t['renameBoard']!,
      initial: board.name,
    );
    if (context.mounted && name != null && name.trim().isNotEmpty) {
      store.renameBoard(board.id, name.trim());
    }
  }

  Future<void> _deleteBoard(BuildContext context, Store store) async {
    final t = store.t;
    final boardId = store.activeBoardId;
    final ok = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: Text(t['deleteBoard']!),
            content: Text(t['confirmDeleteBoard']!),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(t['cancel']!),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                ),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(t['confirm']!),
              ),
            ],
          ),
    );
    if (ok == true && context.mounted) {
      store.deleteBoard(boardId);
      _focusScrollOffsets.removeWhere((k, _) => k.startsWith('$boardId-'));
      setState(() => _focusedQuadrant = null);
    }
  }

  Future<void> _clearBoard(BuildContext context, Store store) async {
    final t = store.t;
    final boardId = store.activeBoardId;
    final board = store.boards.firstWhere(
      (b) => b.id == boardId,
      orElse: () => store.boards.first,
    );
    final count = store.boardTaskCount(boardId);
    if (count == 0) return;

    final ok = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            key: const ValueKey('clear-board-dialog'),
            title: Text(t['clearBoardTitle']!),
            content: Text(
              t['clearBoardConfirm']!
                  .replaceAll('{board}', board.name)
                  .replaceAll('{n}', '$count'),
            ),
            actions: [
              TextButton(
                key: const ValueKey('clear-board-cancel-btn'),
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(t['cancel']!),
              ),
              FilledButton(
                key: const ValueKey('clear-board-confirm-btn'),
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                ),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(t['clear']!),
              ),
            ],
          ),
    );
    if (ok == true && context.mounted) {
      setState(() {
        _selecting = false;
        _selectedIds.clear();
        _activeDetailTaskId = null;
        _focusedQuadrant = null;
      });
      store.clearBoard(boardId);
      _focusScrollOffsets.removeWhere((k, _) => k.startsWith('$boardId-'));
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(t['boardCleared']!)));
    }
  }

  Future<void> _groupSelected(BuildContext context, Store store) async {
    final ids = Set<String>.of(_selectedIds);
    final boardId = store.activeBoardId;
    final title = await _askText(
      context,
      store.t['groupTitlePlaceholder']!,
      store.t['confirmGroup']!,
    );
    if (!mounted) return;
    if (title != null &&
        title.trim().isNotEmpty &&
        boardId == store.activeBoardId &&
        store.tasks.where((t) => ids.contains(t.id)).length >= 2) {
      store.groupTasks(ids, title.trim());
    }
    setState(() {
      _selecting = false;
      _selectedIds.clear();
    });
  }

  Future<String?> _askText(
    BuildContext context,
    String label,
    String title, {
    String? initial,
  }) async {
    final t = context.read<Store>().t;
    return askText(
      context,
      title: title,
      label: label,
      initial: initial ?? '',
      cancel: t['cancel']!,
      confirm: t['confirm']!,
    );
  }
}

/// Desktop-side input panel (same InputSheet content, embedded).
class _InputPanel extends StatelessWidget {
  final InputModePref initialMode;
  const _InputPanel({required this.initialMode});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: SingleChildScrollView(
          child: InputSheet(initialMode: initialMode, embedded: true),
        ),
      ),
    );
  }
}
