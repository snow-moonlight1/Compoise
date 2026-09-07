import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../storage.dart';
import '../widgets/input_sheet.dart';
import '../widgets/quadrant_pane.dart';
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
      final store = context.read<Store>();
      if (store.corruptNotice != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(store.corruptNotice!), width: 420),
        );
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

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 900;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(context, store, t, theme, board?.name ?? t['defaultBoardName']!),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                    child: wide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SizedBox(
                                width: 320,
                                child: _InputPanel(
                                  initialMode: store.settings.defaultInputMode,
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
      floatingActionButton: MediaQuery.of(context).size.width < 900
          ? FloatingActionButton(
              onPressed: _openInput,
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  Widget _grid() {
    return Column(
      children: [
        Expanded(child: Row(children: [
          Expanded(child: QuadrantPane(quadrant: qDo)),
          const SizedBox(width: 10),
          Expanded(child: QuadrantPane(quadrant: qPlan)),
        ])),
        const SizedBox(height: 10),
        Expanded(child: Row(children: [
          Expanded(child: QuadrantPane(quadrant: qDelegate)),
          const SizedBox(width: 10),
          Expanded(child: QuadrantPane(quadrant: qEliminate)),
        ])),
      ],
    );
  }

  Widget _header(BuildContext context, Store store, Map<String, String> t,
      ThemeData theme, String boardName) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 4),
      child: Row(
        children: [
          // Board switcher
          PopupMenuButton<String>(
            tooltip: t['boards'],
            onSelected: (value) {
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
            itemBuilder: (context) => [
              for (final b in store.boards)
                PopupMenuItem(
                  value: b.id,
                  child: Row(
                    children: [
                      if (b.id == store.activeBoardId)
                        Icon(Icons.check, size: 16, color: theme.colorScheme.primary)
                      else
                        const SizedBox(width: 16),
                      Expanded(child: Text(b.name, overflow: TextOverflow.ellipsis)),
                    ],
                  ),
                ),
              const PopupMenuDivider(),
              PopupMenuItem(value: '__new', child: Row(children: [const Icon(Icons.add, size: 16), const SizedBox(width: 8), Text(t['createBoard']!)])),
              PopupMenuItem(value: '__rename', child: Row(children: [const Icon(Icons.edit_outlined, size: 16), const SizedBox(width: 8), Text(t['renameBoard']!)])),
              if (store.boards.length > 1)
                PopupMenuItem(
                  value: '__delete',
                  child: Row(children: [
                    Icon(Icons.delete_outline, size: 16, color: theme.colorScheme.error),
                    const SizedBox(width: 8),
                    Text(t['deleteBoard']!),
                  ]),
                ),
            ],
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(boardName,
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(width: 4),
                const Icon(Icons.keyboard_arrow_down),
              ],
            ),
          ),
          const Spacer(),
          if (_selecting && _selectedIds.length >= 2)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: FilledButton.tonal(
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                onPressed: () => _groupSelected(context, store),
                child: Text('${t['groupSelected']} (${_selectedIds.length})'),
              ),
            ),
          IconButton(
            tooltip: _selecting ? t['cancelSelection'] : t['selectionMode'],
            onPressed: () => setState(() {
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
            onPressed: () => store.updateSettings((s) => s..hideCompleted = !s.hideCompleted),
            icon: Icon(
              store.settings.hideCompleted ? Icons.visibility_off : Icons.visibility,
              color: store.settings.hideCompleted ? theme.colorScheme.primary : null,
            ),
          ),
          IconButton(
            tooltip: t['settings'],
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
    );
  }

  void _openInput() {
    final store = context.read<Store>();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: InputSheet(initialMode: store.settings.defaultInputMode),
      ),
    );
  }

  Future<void> _createBoard(BuildContext context, Store store) async {
    final name = await _askText(context, store.t['boardName']!, store.t['createBoard']!,
        initial: store.t['untitledBoard']!);
    if (name != null && name.trim().isNotEmpty) store.createBoard(name.trim());
  }

  Future<void> _renameBoard(BuildContext context, Store store) async {
    final board = store.activeBoard;
    if (board == null) return;
    final name = await _askText(context, store.t['boardName']!, store.t['renameBoard']!,
        initial: board.name);
    if (name != null && name.trim().isNotEmpty) store.renameBoard(board.id, name.trim());
  }

  Future<void> _deleteBoard(BuildContext context, Store store) async {
    final t = store.t;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(t['deleteBoard']!),
        content: Text(t['confirmDeleteBoard']!),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(t['cancel']!)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(t['confirm']!),
          ),
        ],
      ),
    );
    if (ok == true) store.deleteBoard(store.activeBoardId);
  }

  Future<void> _groupSelected(BuildContext context, Store store) async {
    final title = await _askText(context, store.t['groupTitlePlaceholder']!, store.t['confirmGroup']!);
    if (title != null && title.trim().isNotEmpty) {
      store.groupTasks(_selectedIds, title.trim());
    }
    setState(() {
      _selecting = false;
      _selectedIds.clear();
    });
  }

  Future<String?> _askText(BuildContext context, String label, String title, {String? initial}) async {
    final controller = TextEditingController(text: initial ?? '');
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: label),
          onSubmitted: (v) => Navigator.pop(dialogContext, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(context.read<Store>().t['cancel']!)),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: Text(context.read<Store>().t['confirm']!),
          ),
        ],
      ),
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
