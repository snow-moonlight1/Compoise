import 'dart:async';

import '../widgets/reminder_failure_banner.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../screenshot_import/screenshot_backend.dart';
import '../screenshot_import/screenshot_import_page.dart';
import '../storage.dart';
import '../theme.dart';
import '../shortcuts.dart';
import '../services/desktop_exit_coordinator.dart';
import '../services/desktop_shell_service.dart';
import '../ui/desktop_exit_strings.dart';
import '../ui/platform_ui_policy.dart';
import '../widgets/batch_decompose_sheet.dart';
import '../widgets/board_picker.dart';
import '../widgets/home_actions.dart';
import '../widgets/input_sheet.dart';
import '../widgets/quadrant_transition_layout.dart';
import '../widgets/task_detail_panel.dart';
import '../widgets/task_list_view.dart';
import '../widgets/text_prompt.dart';
import 'completed_screen.dart';
import 'onboarding_screen.dart';
import 'planner_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';
import 'today_screen.dart';

class MatrixHome extends StatefulWidget {
  final DesktopShellService? desktopShell;
  final ScreenshotBackend? screenshotBackend;
  final Duration exitSaveTimeout;

  const MatrixHome({
    super.key,
    this.desktopShell,
    this.screenshotBackend,
    this.exitSaveTimeout = const Duration(seconds: 8),
  });

  @override
  State<MatrixHome> createState() => _MatrixHomeState();
}

class _MatrixHomeState extends State<MatrixHome> {
  DesktopShellService get _desktopShell =>
      widget.desktopShell ?? DesktopShellService.instance;

  bool _selecting = false;
  final Set<String> _selectedIds = {};
  final Set<String> _expandedKeys = {};
  int? _focusedQuadrant;
  // List mode: while the focus overlay fades out the transition layout stays
  // mounted with the last focused quadrant, then the list view returns.
  bool _listExitFading = false;
  int? _listExitFrom;
  ViewMode? _lastViewMode;
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

  bool _composerOpen = false;
  bool _composerDirty = false;
  final _detailKey = GlobalKey();
  final _quadrantTransitionKey = GlobalKey();
  late final TaskDetailSession _detail = TaskDetailSession(
    onChanged: () {
      if (mounted) setState(() {});
    },
  );

  Future<bool> _protectDetailDraft() => _detail.confirmLeave(context);

  Future<bool> _prepareDraftForExit() async {
    if (!_detail.hasDraft && !_composerDirty) return true;
    if (!await confirmDiscardDraft(context) || !mounted) return false;

    final hadPanel = _detail.taskId != null;
    final hadModal = _detail.isModalOpen;
    _detail.drop();
    if (hadPanel) {
      setState(() {});
    } else if (hadModal || _composerOpen) {
      Navigator.of(context, rootNavigator: true).pop();
      await Future<void>.delayed(Duration.zero);
    }
    _composerDirty = false;
    return mounted;
  }

  Future<bool> _coordinateExit() async {
    if (!mounted || !await _prepareDraftForExit() || !mounted) return false;
    final store = context.read<Store>();
    return DesktopExitSaveCoordinator(
      // The exit barrier also waits for the reminder retry ledger, so pending
      // reminder work is never lost behind a reported clean shutdown.
      flush: () => store.flush(includeReminderLedger: true),
      retrySave: () => store.retrySave(includeReminderLedger: true),
      timeout: widget.exitSaveTimeout,
      chooseAfterProblem:
          (problem) => showDesktopExitSaveProblem(
            context,
            problem,
            store.settings.language,
          ),
    ).prepareToExit();
  }

  Future<void> _closeDetail() => _detail.requestClose(context);

  Future<void> _openTaskDetail(
    BuildContext context,
    Task task, {
    required bool isWide,
    String? subtaskId,
  }) => _detail.open(context, task, isWide: isWide, subtaskId: subtaskId);

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
      final useSide = PlatformUiPolicy.of(
        context,
      ).canShowSideDetail(MediaQuery.sizeOf(context).width);
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

  ReminderService? _boundReminders;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _boundReminders = context.read<Store>().reminderService;
      _boundReminders!.onNotificationSelected = _handleNotificationPayload;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final store = context.read<Store>();
      final shell = _desktopShell;
      shell.configureCallbacks(
        onShowWindow: () {
          if (mounted) setState(() {});
        },
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
        onExit: _coordinateExit,
      );
      unawaited(() async {
        final result = await shell.applySettings(
          closeToTray: store.settings.closeToTray,
          globalShortcut: store.settings.globalShortcut,
          language: store.settings.language,
        );
        if (!mounted || !shell.isDesktopSupported || !result.hasFailure) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              store.t['desktopShellApplyFailed'] ??
                  'Some Windows desktop features are unavailable. Open Settings to retry.',
            ),
          ),
        );
      }());
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
    if (_boundReminders?.onNotificationSelected == _handleNotificationPayload) {
      _boundReminders!.onNotificationSelected = null;
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
      canPop: !_selecting && _focusedQuadrant == null && !_listExitFading,
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
          _requestExitFocus();
          return;
        }
        _finishListExitNow();
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
                  _requestExitFocus();
                } else if (_listExitFading) {
                  _finishListExitNow();
                } else if (_detail.taskId != null) {
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
                    final detailTask = _detail.taskIn(store);

                    final viewMode = store.settings.viewMode;
                    // Switching matrix/list is a hard session end: drop both
                    // an active focus and an in-flight list fade so the new
                    // mode cannot keep a dangling _listExitFading flag.
                    if (_lastViewMode != viewMode &&
                        (_focusedQuadrant != null || _listExitFading)) {
                      _focusedQuadrant = null;
                      _listExitFading = false;
                      _listExitFrom = null;
                    }
                    _lastViewMode = viewMode;

                    final showListView =
                        viewMode == ViewMode.list &&
                        _focusedQuadrant == null &&
                        !_listExitFading;
                    final activeCenter =
                        showListView
                            ? TaskListView(
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
                              onQuadrantTap: _requestFocusQuadrant,
                              onEdit:
                                  (task) => _openTaskDetail(
                                    context,
                                    task,
                                    isWide: wide,
                                  ),
                              onEditSubtask:
                                  (task, subtaskId) => _openTaskDetail(
                                    context,
                                    task,
                                    isWide: wide,
                                    subtaskId: subtaskId,
                                  ),
                            )
                            : QuadrantTransitionLayout(
                              key: _quadrantTransitionKey,
                              focusedQuadrant:
                                  _focusedQuadrant ?? _listExitFrom,
                              viewMode: viewMode,
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
                              onFocusQuadrant: _requestFocusQuadrant,
                              onExitFocus: _requestExitFocus,
                              onEdit:
                                  (task) => _openTaskDetail(
                                    context,
                                    task,
                                    isWide: wide,
                                  ),
                              onEditSubtask:
                                  (task, subtaskId) => _openTaskDetail(
                                    context,
                                    task,
                                    isWide: wide,
                                    subtaskId: subtaskId,
                                  ),
                              fadeOutOnly:
                                  _listExitFading && _focusedQuadrant == null,
                              onFadeOutDone: () {
                                if (!mounted || !_listExitFading) return;
                                setState(() {
                                  _listExitFading = false;
                                  _listExitFrom = null;
                                });
                              },
                            );

                    Widget mainContent;
                    final showSidebar = detailTask != null;
                    final panel =
                        detailTask == null
                            ? null
                            : TaskDetailPanel(
                              key: _detailKey,
                              task: detailTask,
                              highlightSubtaskId: _detail.highlightSubtaskId,
                              isSidebar: true,
                              onDirtyChanged: _detail.reportDraft,
                              onClose: _detail.handleClose,
                            );
                    if (!useSideDetail && panel != null) {
                      mainContent = panel;
                    } else if (showSidebar) {
                      mainContent = DetailSideBySide(
                        main: activeCenter,
                        detail: panel!,
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
                        if (store.credentialError != null)
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    store.credentialError!,
                                    style: TextStyle(
                                      color: theme.colorScheme.error,
                                    ),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () async {
                                    if (await store.retryCredential()) {
                                      await store.retrySave();
                                    }
                                  },
                                  child: Text(t['retrySave']!),
                                ),
                              ],
                            ),
                          ),
                        if (store.persistenceError != null)
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    store.persistenceError!,
                                    style: TextStyle(
                                      color: theme.colorScheme.error,
                                    ),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () => store.retrySave(),
                                  child: Text(t['retrySave']!),
                                ),
                              ],
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
      final compact = MediaQuery.sizeOf(context).width < 360;
      void editSelected() {
        final task =
            store.tasks
                .where((item) => item.id == _selectedIds.single)
                .firstOrNull;
        if (task != null) {
          _openTaskDetail(context, task, isWide: wide);
        }
      }

      final neu = theme.extension<NeumorphicSkin>();
      return Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
        decoration: neu == null
            ? BoxDecoration(
                color: theme.colorScheme.surface,
                border: Border(
                  top: BorderSide(
                    color: theme.brightness == Brightness.light
                        ? const Color(0xFFD5DAE1)
                        : theme.colorScheme.outlineVariant,
                  ),
                ),
              )
            : BoxDecoration(
                color: neu.canvas,
                boxShadow: neu.raisedShadows,
              ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                compact
                    ? '${_selectedIds.length} ${t['selectedMark']}'
                    : t['multiSelectStatus']!.replaceAll(
                      '{n}',
                      '${_selectedIds.length}',
                    ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (_selectedIds.length == 1 && compact)
              IconButton(
                tooltip: t['editTask'],
                icon: const Icon(Icons.edit_outlined),
                onPressed: editSelected,
              ),
            if (_selectedIds.length == 1 && !compact)
              TextButton.icon(
                onPressed: editSelected,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: Text(t['editTask']!),
              ),
            if (_selectedIds.length >= 2 && compact)
              IconButton(
                tooltip: t['groupSelected'],
                icon: const Icon(Icons.group_work_outlined),
                onPressed: () => _groupSelected(context, store),
              ),
            if (_selectedIds.length >= 2 && !compact)
              FilledButton.tonal(
                onPressed: () => _groupSelected(context, store),
                child: Text('${t['groupSelected']} (${_selectedIds.length})'),
              ),
            if (_selectedIds.isNotEmpty)
              IconButton(
                key: const ValueKey('batch-move-btn'),
                tooltip: t['moveSelected'],
                icon: const Icon(Icons.drive_file_move_outline),
                onPressed: () => _moveSelected(context, store),
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

  void _finishListExitNow() {
    if (!_listExitFading) return;
    setState(() {
      _listExitFading = false;
      _listExitFrom = null;
    });
  }

  void _requestFocusQuadrant(int q) {
    setState(() {
      _listExitFading = false;
      _listExitFrom = null;
      _focusedQuadrant = q;
    });
  }

  void _requestExitFocus() {
    if (_focusedQuadrant == null) return;
    final store = context.read<Store>();
    setState(() {
      if (store.settings.viewMode == ViewMode.list) {
        // Keep the focus overlay alive for its fade-out; the list view comes
        // back when the transition layout reports completion.
        _listExitFrom = _focusedQuadrant;
        _listExitFading = true;
      }
      _focusedQuadrant = null;
    });
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
    final header = Padding(
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
              onPressed: _requestExitFocus,
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
                          fontWeight: FontWeight.w600,
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
    return header;
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

  void _openToday() {
    final store = context.read<Store>();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TodayScreen(initialBoardId: store.activeBoardId),
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
      _detail.drop();
      _focusedQuadrant = null;
      _listExitFading = false;
      _listExitFrom = null;
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
    final policy = PlatformUiPolicy.of(context);
    Widget panel(BuildContext ctx) => ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(ctx).height,
        maxWidth: 400,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            key: const ValueKey('more-schedule'),
            leading: const Icon(Icons.calendar_month_outlined),
            title: Text(ctx.read<Store>().t['scheduleOpen']!),
            onTap: () => Navigator.of(ctx).pop('schedule'),
          ),
          ListTile(
            key: const ValueKey('more-screenshot-import'),
            leading: const Icon(Icons.image_outlined),
            title: Text(ctx.read<Store>().t['screenshotImportTitle']!),
            onTap: () => Navigator.of(ctx).pop('screenshot-import'),
          ),
          const Flexible(child: HomeMorePanel()),
        ],
      ),
    );
    final Object? action;
    if (policy.isTouchLayout) {
      action = await showModalBottomSheet<Object>(
        context: context, isScrollControlled: true, useSafeArea: true,
        builder: panel,
      );
    } else {
      action = await showDialog<Object>(
        context: context,
        builder: (ctx) => Dialog(
          alignment: Alignment.topRight,
          insetPadding: const EdgeInsets.fromLTRB(24, 72, 24, 24),
          child: panel(ctx),
        ),
      );
    }
    if (action == 'screenshot-import') {
      if (!mounted || !await _protectDetailDraft() || !mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              ScreenshotImportPage(backend: widget.screenshotBackend),
        ),
      );
      return;
    }
    if (action == 'schedule') {
      // Leaving an unsaved detail draft for the schedule keeps the same guard
      // as every other navigation away from the page.
      if (!mounted || !await _protectDetailDraft() || !mounted) return;
      await openPlannerScreen(context, store: context.read<Store>());
      return;
    }
    if (!mounted || action == null) return;
    switch (action) {
      case HomeMoreAction.switchBoard:
        await _openBoardPicker();
      case HomeMoreAction.today:
        _openToday();
      case HomeMoreAction.completed:
        _openCompleted();
      case HomeMoreAction.select:
        setState(() {
          _selecting = true;
          _selectedIds.clear();
        });
      case HomeMoreAction.settings:
        _openSettings();
      default:
        break;
    }
  }

  Future<void> _openInput() async {
    if (_composerOpen) return;
    if (!await _protectDetailDraft()) return;
    if (!mounted) return;
    if (_detail.taskId != null) setState(_detail.drop);
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
              (_) => InputSheet(
                initialMode: store.settings.defaultInputMode,
                onDirtyChanged: (dirty) => _composerDirty = dirty,
              ),
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
                    onDirtyChanged: (dirty) => _composerDirty = dirty,
                  ),
                ),
              ),
        );
      }
    } finally {
      _composerOpen = false;
      _composerDirty = false;
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
      setState(() {
        _focusedQuadrant = null;
        _listExitFading = false;
        _listExitFrom = null;
      });
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
        _detail.drop();
        _focusedQuadrant = null;
        _listExitFading = false;
        _listExitFrom = null;
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

  Future<void> _moveSelected(BuildContext context, Store store) async {
    final ids = Set<String>.of(_selectedIds);
    final boardId = store.activeBoardId;
    final t = store.t;
    final quadrant = await showDialog<int>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: Text(t['moveSelected']!),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final q in allQuadrants)
                  ListTile(
                    key: ValueKey('batch-move-q$q'),
                    title: Text(t['q$q']!),
                    onTap: () => Navigator.pop(dialogContext, q),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(t['cancel']!),
              ),
            ],
          ),
    );
    if (!context.mounted || quadrant == null || boardId != store.activeBoardId) {
      return;
    }
    final currentIds = store.visibleTasks
        .where((task) => ids.contains(task.id) && _selectedIds.contains(task.id))
        .map((task) => task.id);
    final count = store.moveTasks(currentIds, quadrant);
    if (count == 0) return;
    setState(() {
      _selecting = false;
      _selectedIds.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          t['tasksMoved']!
              .replaceAll('{n}', '$count')
              .replaceAll('{quadrant}', t['q$quadrant']!),
        ),
      ),
    );
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
