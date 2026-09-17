import '../widgets/reminder_failure_banner.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../storage.dart';
import '../shortcuts.dart';
import '../ui/platform_ui_policy.dart';
import '../widgets/board_picker.dart';
import '../widgets/home_actions.dart';
import '../widgets/input_sheet.dart';
import '../widgets/quadrant_focus_view.dart';
import '../widgets/quadrant_pane.dart';
import '../widgets/task_detail_panel.dart';
import '../widgets/task_list_view.dart';
import '../widgets/text_prompt.dart';
import 'completed_screen.dart';
import 'onboarding_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';
import '../services/desktop_shell_service.dart';

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
  String? _highlightSubtaskId;
  bool _detailDirty = false;
  bool _composerOpen = false;
  final _detailKey = GlobalKey();

  Future<bool> _protectDetailDraft() async {
    if (!_detailDirty) return true;
    final discard = await confirmDiscardDraft(context);
    if (discard) _detailDirty = false;
    return discard;
  }

  Future<void> _closeDetail() async {
    if (!await _protectDetailDraft()) return;
    if (!mounted) return;
    setState(() {
      _activeDetailTaskId = null;
      _detailDirty = false;
    });
  }

  Future<void> _openTaskDetail(
    BuildContext context,
    Task task, {
    required bool isWide,
    String? subtaskId,
  }) async {
    if (isWide) {
      if (_activeDetailTaskId != null &&
          _activeDetailTaskId != task.id &&
          !await _protectDetailDraft()) {
        return;
      }
      if (!mounted) return;
      setState(() {
        _activeDetailTaskId = task.id;
        _highlightSubtaskId = subtaskId;
      });
    } else {
      await showTaskDetailSheet(context, task, highlightSubtaskId: subtaskId);
    }
  }

  bool _isTextEditingFocused() {
    final focus = FocusManager.instance.primaryFocus;
    if (focus == null) return false;
    final widget = focus.context?.widget;
    return widget is EditableText;
  }

  void _handleNotificationPayload(ReminderPayload payload) async {
    if (!await _protectDetailDraft() || !mounted) return;
    if (!mounted) return;
    final store = context.read<Store>();
    if (payload.boardId.isNotEmpty &&
        payload.boardId != store.activeBoardId &&
        store.boards.any((b) => b.id == payload.boardId)) {
      store.setActiveBoard(payload.boardId);
    }
    final task = store.tasks.where((t) => t.id == payload.taskId).firstOrNull;
    if (task != null) {
      if (payload.subtaskId != null) {
        _ensureExpanded(store, task.id);
      }
      final useSide = PlatformUiPolicy.of(context).canShowSideDetail(
        MediaQuery.sizeOf(context).width,
      );
      _openTaskDetail(
        context,
        task,
        isWide: useSide,
        subtaskId: payload.subtaskId,
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            store.t['taskNotFound'] ??
                'Task no longer exists or has been deleted',
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ReminderService.instance.onNotificationSelected =
            _handleNotificationPayload;
      }
    });
    DesktopShellService.instance.onShowWindow = () {
      if (mounted) setState(() {});
    };
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final store = context.read<Store>();
      DesktopShellService.instance.init(
        closeToTray: store.settings.closeToTray,
        globalShortcut: store.settings.globalShortcut,
        onQuickAddTask: _openInput,
        onSearch: () {
          if (!mounted) return;
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => SearchScreen(initialBoardId: store.activeBoardId),
            ),
          );
        },
      );
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final store = context.read<Store>();
      if (store.corruptNotice != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(store.corruptNotice!)));
        store.corruptNotice = null;
      }
      if (!store.hasSeenOnboarding) {
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const OnboardingScreen()));
      }
    });
  }

  @override
  void dispose() {
    if (ReminderService.instance.onNotificationSelected ==
        _handleNotificationPayload) {
      ReminderService.instance.onNotificationSelected = null;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<Store>();
    final t = store.t;
    final theme = Theme.of(context);
    final board = store.activeBoard;
    _selectedIds.retainAll(store.visibleTasks.map((task) => task.id));
    _expandedKeys.retainAll(store.tasks.map(_expandKey));

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
      child: Shortcuts.manager(
        manager: EditingAwareShortcutManager(),
        child: Actions(
          actions: {
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
                          (_) =>
                              SearchScreen(initialBoardId: store.activeBoardId),
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
                if (PlatformUiPolicy.of(context).showDesktopShortcuts) {
                  showShortcutsHelpDialog(context, t);
                }
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
                  _closeDetail();
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
                    final policy = PlatformUiPolicy.of(context);
                    final useSideDetail = policy.canShowSideDetail(
                      constraints.maxWidth,
                    );
                    final wide = useSideDetail;
                    final detailTask =
                        _activeDetailTaskId == null
                            ? null
                            : store.tasks
                                .where((t) => t.id == _activeDetailTaskId)
                                .firstOrNull;

                    final activeCenter =
                        _focusedQuadrant != null
                            ? _focusView(
                              wide: wide,
                              focusedQ: _focusedQuadrant!,
                            )
                            : store.settings.viewMode == ViewMode.grid
                            ? _grid(wide: wide)
                            : TaskListView(
                              selecting: _selecting,
                              selectedIds: _selectedIds,
                              expandedIds: _expandedIdsFor(store),
                              onSelect:
                                  (id) => setState(() {
                                    if (!_selectedIds.add(id)) {
                                      _selectedIds.remove(id);
                                    }
                                  }),
                              onToggleExpand: (id) => _toggleExpand(store, id),
                              onEnsureExpanded:
                                  (id) => _ensureExpanded(store, id),
                              onQuadrantTap:
                                  (q) => setState(() => _focusedQuadrant = q),
                              onEdit:
                                  (task) => _openTaskDetail(
                                    context,
                                    task,
                                    isWide: wide,
                                  ),
                            );

                    Widget mainContent;
                    final showSidebar = detailTask != null;
                    final panel =
                        detailTask == null
                            ? null
                            : TaskDetailPanel(
                              key: _detailKey,
                              task: detailTask,
                              highlightSubtaskId: _highlightSubtaskId,
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
                    if (!useSideDetail && panel != null) {
                      mainContent = panel;
                    } else if (showSidebar) {
                      mainContent = Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: activeCenter),
                          const SizedBox(width: PlatformUiPolicy.sideDetailGap),
                          SizedBox(
                            width: PlatformUiPolicy.sideDetailWidth,
                            child: panel,
                          ),
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
                          policy,
                          constraints.maxWidth,
                        ),
                        const ReminderFailureBanner(),
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
                        _bottomBar(context, store, t, theme, wide, policy),
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
    PlatformUiPolicy policy,
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
                child: Text('${t['groupSelected']} (${_selectedIds.length})'),
              ),
            const SizedBox(width: 4),
            if (policy.isTouchLayout)
              IconButton(
                key: const ValueKey('more-btn'),
                tooltip: t['more'] ?? 'More',
                icon: const Icon(Icons.more_horiz),
                onPressed: _openMore,
              ),
            IconButton(
              key: const ValueKey('exit-selection-btn'),
              tooltip: t['cancelSelection'],
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

    if (policy.isTouchLayout) {
      return HomeBottomActions(
        onSearch: _openSearch,
        onAdd: _openInput,
        onMore: _openMore,
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
    PlatformUiPolicy policy,
    double availableWidth,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 8, 4),
      child: Row(
        children: [
          if (_focusedQuadrant != null) ...[
            IconButton(
              key: const ValueKey('focus-back-btn'),
              tooltip: t['back'] ?? 'Back',
              icon: const Icon(Icons.arrow_back),
              style: IconButton.styleFrom(
                minimumSize: const Size(
                  PlatformUiPolicy.minActionSize,
                  PlatformUiPolicy.minActionSize,
                ),
              ),
              onPressed: () => setState(() => _focusedQuadrant = null),
            ),
            const SizedBox(width: 4),
          ],
          Expanded(
            child: InkWell(
              key: const ValueKey('board-picker-btn'),
              onTap: _openBoardPicker,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
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
          ),
          if (!policy.isTouchLayout)
            HomeHeaderActions(
              compact: policy.compactHeaderActions(availableWidth),
              onSearch: _openSearch,
              onAdd: _openInput,
              onMore: _openMore,
            ),
        ],
      ),
    );
  }

  void _openSearch() {
    final store = context.read<Store>();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SearchScreen(initialBoardId: store.activeBoardId),
      ),
    );
  }

  void _openCompleted() {
    final store = context.read<Store>();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CompletedScreen(initialBoardId: store.activeBoardId),
      ),
    );
  }

  void _openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
  }

  void _clearTransientUi() {
    setState(() {
      _selecting = false;
      _selectedIds.clear();
      _activeDetailTaskId = null;
      _detailDirty = false;
      _focusedQuadrant = null;
    });
  }

  Future<void> _openBoardPicker() {
    final store = context.read<Store>();
    return showBoardPicker(
      context: context,
      protectDraft: _protectDetailDraft,
      onBoardWillChange: _clearTransientUi,
      onCreate: () => _createBoard(context, store),
      onRename: () => _renameBoard(context, store),
      onClear: () => _clearBoard(context, store),
      onDelete: () => _deleteBoard(context, store),
    );
  }

  Future<void> _openMore() async {
    final action = await showHomeMore(context);
    if (!mounted || action == null) return;
    switch (action) {
      case HomeMoreAction.switchBoard:
        await _openBoardPicker();
      case HomeMoreAction.completed:
        _openCompleted();
      case HomeMoreAction.select:
        setState(() {
          _selecting = true;
          _selectedIds.clear();
        });
      case HomeMoreAction.settings:
        _openSettings();
    }
  }

  Future<void> _openInput() async {
    if (_composerOpen) return;
    if (!await _protectDetailDraft()) return;
    if (!mounted) return;
    if (_activeDetailTaskId != null) {
      setState(() {
        _activeDetailTaskId = null;
        _detailDirty = false;
      });
    }
    final store = context.read<Store>();
    final policy = PlatformUiPolicy.of(context);
    _composerOpen = true;
    List<Task>? longTerm;
    try {
      if (policy.isTouchLayout) {
        longTerm = await showModalBottomSheet<List<Task>>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          builder:
              (_) => InputSheet(initialMode: store.settings.defaultInputMode),
        );
      } else {
        longTerm = await showDialog<List<Task>>(
          context: context,
          barrierDismissible: true,
          builder:
              (ctx) => Dialog(
                insetPadding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 24,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 520,
                    maxHeight: 640,
                  ),
                  child: InputSheet(
                    initialMode: store.settings.defaultInputMode,
                  ),
                ),
              ),
        );
      }
    } finally {
      _composerOpen = false;
    }
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
        _detailDirty = false;
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
