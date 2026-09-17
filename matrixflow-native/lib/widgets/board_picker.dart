import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../storage.dart';
import '../ui/platform_ui_policy.dart';

Future<void> showBoardPicker({
  required BuildContext context,
  required Future<bool> Function() protectDraft,
  required VoidCallback onBoardWillChange,
  required Future<void> Function() onCreate,
  required Future<void> Function() onRename,
  required Future<void> Function() onClear,
  required Future<void> Function() onDelete,
}) {
  final policy = PlatformUiPolicy.of(context);
  final panel = BoardPickerPanel(
    protectDraft: protectDraft,
    onBoardWillChange: onBoardWillChange,
    onCreate: onCreate,
    onRename: onRename,
    onClear: onClear,
    onDelete: onDelete,
  );
  if (policy.isTouchLayout) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(ctx).bottom,
        ),
        child: panel,
      ),
    );
  }
  return showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 560),
        child: panel,
      ),
    ),
  );
}

class BoardPickerPanel extends StatelessWidget {
  final Future<bool> Function() protectDraft;
  final VoidCallback onBoardWillChange;
  final Future<void> Function() onCreate;
  final Future<void> Function() onRename;
  final Future<void> Function() onClear;
  final Future<void> Function() onDelete;

  const BoardPickerPanel({
    super.key,
    required this.protectDraft,
    required this.onBoardWillChange,
    required this.onCreate,
    required this.onRename,
    required this.onClear,
    required this.onDelete,
  });

  Future<void> _closeThen(BuildContext context, Future<void> Function() action) async {
    Navigator.of(context).pop();
    await action();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<Store>();
    final t = store.t;
    final theme = Theme.of(context);
    final canClear = store.boardTaskCount(store.activeBoardId) > 0;
    return Material(
      key: const ValueKey('board-picker-panel'),
      color: theme.colorScheme.surface,
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.7,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  t['boardPickerTitle'] ?? t['boards'] ?? 'Boards',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final board in store.boards)
                    ListTile(
                      key: ValueKey('board-picker-item-${board.id}'),
                      minVerticalPadding: 12,
                      leading: Icon(
                        board.id == store.activeBoardId
                            ? Icons.check
                            : Icons.dashboard_outlined,
                        color:
                            board.id == store.activeBoardId
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurfaceVariant,
                      ),
                      title: Text(board.name),
                      selected: board.id == store.activeBoardId,
                      onTap: () async {
                        if (board.id == store.activeBoardId) {
                          Navigator.of(context).pop();
                          return;
                        }
                        if (!await protectDraft()) return;
                        if (!context.mounted) return;
                        onBoardWillChange();
                        store.setActiveBoard(board.id);
                        Navigator.of(context).pop();
                      },
                    ),
                  const Divider(height: 24),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                    child: Text(
                      t['boardManage'] ?? 'Manage',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  ListTile(
                    key: const ValueKey('board-picker-create'),
                    minVerticalPadding: 12,
                    leading: const Icon(Icons.add),
                    title: Text(t['createBoard']!),
                    onTap: () => _closeThen(context, onCreate),
                  ),
                  ListTile(
                    key: const ValueKey('board-picker-rename'),
                    minVerticalPadding: 12,
                    leading: const Icon(Icons.edit_outlined),
                    title: Text(t['renameBoard']!),
                    onTap: () => _closeThen(context, onRename),
                  ),
                  ListTile(
                    key: const ValueKey('clear-board-menu-item'),
                    minVerticalPadding: 12,
                    enabled: canClear,
                    leading: Icon(
                      Icons.delete_sweep_outlined,
                      color:
                          canClear
                              ? theme.colorScheme.error
                              : theme.disabledColor,
                    ),
                    title: Text(
                      t['clearBoard']!,
                      style: TextStyle(
                        color:
                            canClear
                                ? theme.colorScheme.error
                                : theme.disabledColor,
                      ),
                    ),
                    onTap:
                        canClear ? () => _closeThen(context, onClear) : null,
                  ),
                  if (store.boards.length > 1)
                    ListTile(
                      key: const ValueKey('board-picker-delete'),
                      minVerticalPadding: 12,
                      leading: Icon(
                        Icons.delete_outline,
                        color: theme.colorScheme.error,
                      ),
                      title: Text(
                        t['deleteBoard']!,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                      onTap: () => _closeThen(context, onDelete),
                    ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }
}
