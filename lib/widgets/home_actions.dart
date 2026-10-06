import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../storage.dart';
import '../task_stats.dart';
import '../theme.dart';
import '../ui/platform_ui_policy.dart';

enum HomeMoreAction { switchBoard, today, completed, select, settings }

class HomeActionButton extends StatelessWidget {
  final Key? buttonKey;
  final IconData icon;
  final String label;
  final String? tooltip;
  final VoidCallback onPressed;
  final bool compact;
  final bool expanded;

  /// Accent-colored icon on the neumorphic slab. The slab itself stays the
  /// background color.
  final bool accentIcon;

  const HomeActionButton({
    super.key,
    this.buttonKey,
    required this.icon,
    required this.label,
    this.tooltip,
    required this.onPressed,
    this.compact = false,
    this.expanded = false,
    this.accentIcon = false,
  });

  @override
  Widget build(BuildContext context) {
    final skin = NeumorphicSkin.maybeOf(context);
    final accent = Theme.of(context).colorScheme.primary;
    final iconColor = skin != null && accentIcon ? accent : null;
    Widget child =
        compact
            ? IconButton(
              key: buttonKey,
              tooltip: tooltip ?? label,
              onPressed: onPressed,
              icon: Icon(icon, color: iconColor),
              style: IconButton.styleFrom(
                foregroundColor: skin?.ink,
                backgroundColor: skin == null ? null : const Color(0x00000000),
                minimumSize: const Size(
                  PlatformUiPolicy.minActionSize,
                  PlatformUiPolicy.minActionSize,
                ),
                tapTargetSize: MaterialTapTargetSize.padded,
              ),
            )
            : TextButton.icon(
              key: buttonKey,
              onPressed: onPressed,
              icon: Icon(icon, size: 20, color: iconColor),
              label: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              style: TextButton.styleFrom(
                foregroundColor: skin?.ink,
                backgroundColor: skin == null ? null : const Color(0x00000000),
                minimumSize: Size(
                  expanded ? double.infinity : PlatformUiPolicy.minActionSize,
                  PlatformUiPolicy.minActionSize,
                ),
                tapTargetSize: MaterialTapTargetSize.padded,
              ),
            );
    if (skin != null) {
      child = Padding(
        padding: EdgeInsets.symmetric(
          horizontal: expanded ? 8 : 4,
          vertical: expanded ? 10 : 4,
        ),
        child: NeuPressable(skin: skin, radius: compact ? 14 : 16, child: child),
      );
    }
    if (!expanded) return child;
    return Expanded(child: child);
  }
}

class HomeBottomActions extends StatelessWidget {
  final VoidCallback onSearch;
  final VoidCallback onAdd;
  final VoidCallback onMore;

  const HomeBottomActions({
    super.key,
    required this.onSearch,
    required this.onAdd,
    required this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.watch<Store>().t;
    final theme = Theme.of(context);
    final neu = theme.extension<NeumorphicSkin>();
    return Material(
      color: theme.colorScheme.surface,
      child: Padding(
        padding: neu == null
            ? const EdgeInsets.fromLTRB(8, 4, 8, 4)
            : const EdgeInsets.fromLTRB(8, 6, 8, 8),
        child: Row(
          children: [
            HomeActionButton(
              buttonKey: const ValueKey('search-btn'),
              icon: Icons.search,
              label: t['search'] ?? 'Search',
              onPressed: onSearch,
              expanded: true,
            ),
            HomeActionButton(
              buttonKey: const ValueKey('add-task-btn'),
              icon: Icons.add,
              label: t['addBtn'] ?? 'Add Task',
              onPressed: onAdd,
              expanded: true,
              accentIcon: true,
            ),
            HomeActionButton(
              buttonKey: const ValueKey('more-btn'),
              icon: Icons.more_horiz,
              label: t['more'] ?? 'More',
              onPressed: onMore,
              expanded: true,
            ),
          ],
        ),
      ),
    );
  }
}

class HomeHeaderActions extends StatelessWidget {
  final bool compact;
  final VoidCallback onSearch;
  final VoidCallback onAdd;
  final VoidCallback onMore;

  const HomeHeaderActions({
    super.key,
    required this.compact,
    required this.onSearch,
    required this.onAdd,
    required this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.watch<Store>().t;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        HomeActionButton(
          buttonKey: const ValueKey('search-btn'),
          icon: Icons.search,
          label: t['search'] ?? 'Search',
          compact: compact,
          onPressed: onSearch,
        ),
        HomeActionButton(
          buttonKey: const ValueKey('add-task-btn'),
          icon: Icons.add,
          label: t['addBtn'] ?? 'Add Task',
          compact: compact,
          onPressed: onAdd,
          accentIcon: true,
        ),
        HomeActionButton(
          buttonKey: const ValueKey('more-btn'),
          icon: Icons.more_horiz,
          label: t['more'] ?? 'More',
          compact: compact,
          onPressed: onMore,
        ),
      ],
    );
  }
}

Future<HomeMoreAction?> showHomeMore(BuildContext context) {
  final policy = PlatformUiPolicy.of(context);
  if (policy.isTouchLayout) {
    return showModalBottomSheet<HomeMoreAction>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => const HomeMorePanel(),
    );
  }
  return showDialog<HomeMoreAction>(
    context: context,
    builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.fromLTRB(24, 72, 24, 24),
      alignment: Alignment.topRight,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400, maxHeight: 560),
        child: const HomeMorePanel(),
      ),
    ),
  );
}

class HomeMorePanel extends StatelessWidget {
  const HomeMorePanel({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<Store>();
    final t = store.t;
    final theme = Theme.of(context);
    final stats = computeTaskStats(tasks: store.tasks);
    final canSelect = store.visibleTasks.isNotEmpty;
    String rateText;
    if (stats.totalTasks == 0) {
      rateText = t['completionRateEmpty'] ?? 'All boards: no tasks';
    } else {
      rateText = (t['completionRateSummary'] ??
              'All boards: {done}/{total} completed ({percent}%)')
          .replaceAll('{done}', '${stats.completedTasks}')
          .replaceAll('{total}', '${stats.totalTasks}')
          .replaceAll('{percent}', '${(stats.completionRate * 100).round()}');
    }

    return Material(
      key: const ValueKey('more-panel'),
      color: theme.colorScheme.surface,
      child: SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            ListTile(
              key: const ValueKey('more-switch-board'),
              minVerticalPadding: 12,
              leading: const Icon(Icons.dashboard_outlined),
              title: Text(t['switchBoard'] ?? 'Switch board'),
              onTap: () => Navigator.pop(context, HomeMoreAction.switchBoard),
            ),
            ListTile(
              key: const ValueKey('today-btn'),
              minVerticalPadding: 12,
              leading: const Icon(Icons.today),
              title: Text(t['today']!),
              onTap: () => Navigator.pop(context, HomeMoreAction.today),
            ),
            ListTile(
              key: const ValueKey('completed-btn'),
              minVerticalPadding: 12,
              leading: const Icon(Icons.task_alt),
              title: Text(t['completedTasks'] ?? 'Completed Tasks'),
              onTap: () => Navigator.pop(context, HomeMoreAction.completed),
            ),
            const Divider(height: 8),
            ListTile(
              key: const ValueKey('view-mode-toggle-btn'),
              minVerticalPadding: 12,
              leading: Icon(
                store.settings.viewMode == ViewMode.grid
                    ? Icons.grid_view
                    : Icons.view_agenda_outlined,
              ),
              title: Text(t['viewMode'] ?? 'View'),
              subtitle: Text(
                store.settings.viewMode == ViewMode.grid
                    ? (t['viewModeGrid'] ?? 'Grid View')
                    : (t['viewModeList'] ?? 'List View'),
              ),
              onTap: store.toggleViewMode,
            ),
            SwitchListTile(
              key: const ValueKey('show-completed-switch'),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              secondary: Icon(
                store.settings.hideCompleted
                    ? Icons.visibility_off
                    : Icons.visibility,
              ),
              title: Text(t['showCompletedTasks'] ?? 'Show completed tasks'),
              value: !store.settings.hideCompleted,
              onChanged:
                  (show) => store.updateSettings(
                    (s) => s..hideCompleted = !show,
                  ),
            ),
            ListTile(
              key: const ValueKey('select-tasks-btn'),
              minVerticalPadding: 12,
              enabled: canSelect,
              leading: const Icon(Icons.layers),
              title: Text(t['selectTasks'] ?? t['selectionMode'] ?? 'Select tasks'),
              onTap:
                  canSelect
                      ? () => Navigator.pop(context, HomeMoreAction.select)
                      : null,
            ),
            ListTile(
              key: const ValueKey('more-settings-btn'),
              minVerticalPadding: 12,
              leading: const Icon(Icons.settings_outlined),
              title: Text(t['settings']!),
              onTap: () => Navigator.pop(context, HomeMoreAction.settings),
            ),
            if (store.settings.showCompletionRate) ...[
              const Divider(height: 16),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Text(
                  rateText,
                  key: const ValueKey('completion-rate-text'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
