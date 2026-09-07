import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../storage.dart';
import '../widgets/input_sheet.dart';
import '../widgets/quadrant_pane.dart';
import '../widgets/text_prompt.dart';
import 'settings_screen.dart';

class MatrixHome extends StatefulWidget {
  const MatrixHome({super.key});

  @override
  State<MatrixHome> createState() => _MatrixHomeState();
}

class _MatrixHomeState extends State<MatrixHome> {
  bool _selecting = false;
  final Set<String> _selectedIds = {};

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

    return PopScope(
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _selecting) {
          setState(() {
            _selecting = false;
            _selectedIds.clear();
          });
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 900;
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
                  if (store.persistenceError != null)
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        store.persistenceError!,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ),
                  if (_selecting && _selectedIds.length >= 2)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: FilledButton.tonal(
                        onPressed: () => _groupSelected(context, store),
                        child: Text(
                          '${t['groupSelected']} (${_selectedIds.length})',
                        ),
                      ),
                    ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                      child:
                          wide
                              ? Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  SizedBox(
                                    width: 320,
                                    child: _InputPanel(
                                      initialMode:
                                          store.settings.defaultInputMode,
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(child: _grid()),
                                ],
                              )
                              : _grid(),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        floatingActionButton:
            MediaQuery.of(context).size.width < 900
                ? FloatingActionButton(
                  tooltip: t['addBtn'],
                  onPressed: _openInput,
                  child: const Icon(Icons.add),
                )
                : null,
      ),
    );
  }

  Widget _grid() {
    Widget pane(int q) => QuadrantPane(
      quadrant: q,
      selecting: _selecting,
      selectedIds: _selectedIds,
      onSelect:
          (id) => setState(() {
            if (!_selectedIds.add(id)) _selectedIds.remove(id);
          }),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final grid = SizedBox(
          height: constraints.maxHeight < 440 ? 440 : constraints.maxHeight,
          child: Column(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Expanded(child: pane(qDo)),
                    const SizedBox(width: 10),
                    Expanded(child: pane(qPlan)),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: Row(
                  children: [
                    Expanded(child: pane(qDelegate)),
                    const SizedBox(width: 10),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 4),
      child: Row(
        children: [
          // Board switcher
          Expanded(
            child: PopupMenuButton<String>(
              tooltip: t['boards'],
              onSelected: (value) {
                setState(() {
                  _selecting = false;
                  _selectedIds.clear();
                });
                if (value == '__new') {
                  _createBoard(context, store);
                } else if (value == '__rename') {
                  _renameBoard(context, store);
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
    if (ok == true && context.mounted) store.deleteBoard(boardId);
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
