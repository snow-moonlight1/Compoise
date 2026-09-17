import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../storage.dart';
import '../task_filter.dart';
import '../task_query.dart';
import '../ui/platform_ui_policy.dart';

export '../task_filter.dart';

String filterButtonLabel(Map<String, String> t, int count) {
  if (count <= 0) return t['filter'] ?? 'Filter';
  return (t['filterCount'] ?? 'Filter ({n})').replaceAll('{n}', '$count');
}

String currentBoardFilterLabel(Map<String, String> t, String boardName) {
  return (t['currentBoardNamed'] ?? 'Current: {name}').replaceAll(
    '{name}',
    boardName,
  );
}

String scopeSummaryLabel({
  required TaskFilterCriteria criteria,
  required Map<String, String> t,
  required String currentBoardName,
}) {
  if (criteria.scope == TaskScopeFilter.allBoards) {
    return t['allBoards'] ?? 'All Boards';
  }
  return currentBoardFilterLabel(t, currentBoardName);
}

List<String> appliedFilterSummaryLabels({
  required TaskFilterCriteria criteria,
  required TaskFilterKind kind,
  required Map<String, String> t,
  required String currentBoardName,
}) {
  final labels = <String>[scopeSummaryLabel(
    criteria: criteria,
    t: t,
    currentBoardName: currentBoardName,
  )];
  if (kind == TaskFilterKind.archive) return labels;
  if (criteria.quadrant != null) {
    labels.add(t['q${criteria.quadrant}'] ?? 'Q${criteria.quadrant}');
  }
  if (criteria.status == TaskStatusFilter.incomplete) {
    labels.add(t['incomplete'] ?? 'Incomplete');
  } else if (criteria.status == TaskStatusFilter.completed) {
    labels.add(t['completed'] ?? 'Completed');
  }
  if (criteria.date != TaskDateFilter.all) {
    labels.add(switch (criteria.date) {
      TaskDateFilter.today => t['today'] ?? 'Today',
      TaskDateFilter.thisWeek => t['thisWeek'] ?? 'This Week',
      TaskDateFilter.thisMonth => t['thisMonth'] ?? 'This Month',
      TaskDateFilter.overdue => t['overdue'] ?? 'Overdue',
      TaskDateFilter.noDate => t['noDate'] ?? 'No Date',
      TaskDateFilter.all => t['all'] ?? 'All',
    });
  }
  return labels;
}

class AppliedFilterSummary extends StatelessWidget {
  final TaskFilterCriteria criteria;
  final TaskFilterKind kind;
  final String currentBoardName;

  const AppliedFilterSummary({
    super.key,
    required this.criteria,
    required this.kind,
    required this.currentBoardName,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.watch<Store>().t;
    final theme = Theme.of(context);
    final labels = appliedFilterSummaryLabels(
      criteria: criteria,
      kind: kind,
      t: t,
      currentBoardName: currentBoardName,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          for (final label in labels)
            Chip(
              key: ValueKey('filter-summary-$label'),
              label: Text(label),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              labelStyle: theme.textTheme.labelMedium,
            ),
        ],
      ),
    );
  }
}

class FilterChromeBar extends StatelessWidget {
  final int activeCount;
  final bool canClear;
  final VoidCallback onOpen;
  final VoidCallback onClear;
  final bool expanded;
  final bool compact;

  const FilterChromeBar({
    super.key,
    required this.activeCount,
    required this.canClear,
    required this.onOpen,
    required this.onClear,
    this.expanded = false,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.watch<Store>().t;
    final label = filterButtonLabel(t, activeCount);
    final open =
        compact
            ? IconButton(
              key: const ValueKey('filter-open-btn'),
              tooltip: label,
              onPressed: onOpen,
              icon: Badge(
                isLabelVisible: activeCount > 0,
                label: Text('$activeCount'),
                child: const Icon(Icons.filter_list),
              ),
              style: IconButton.styleFrom(
                minimumSize: const Size(
                  PlatformUiPolicy.minActionSize,
                  PlatformUiPolicy.minActionSize,
                ),
                tapTargetSize: MaterialTapTargetSize.padded,
              ),
            )
            : TextButton.icon(
              key: const ValueKey('filter-open-btn'),
              onPressed: onOpen,
              icon: const Icon(Icons.filter_list, size: 20),
              label: Text(label),
              style: TextButton.styleFrom(
                minimumSize: const Size(
                  PlatformUiPolicy.minActionSize,
                  PlatformUiPolicy.minActionSize,
                ),
                tapTargetSize: MaterialTapTargetSize.padded,
              ),
            );
    final clear =
        compact
            ? IconButton(
              key: const ValueKey('clear-filters-btn'),
              tooltip: t['clearFilters'] ?? 'Clear filters',
              onPressed: canClear ? onClear : null,
              icon: const Icon(Icons.filter_alt_off_outlined),
              style: IconButton.styleFrom(
                minimumSize: const Size(
                  PlatformUiPolicy.minActionSize,
                  PlatformUiPolicy.minActionSize,
                ),
                tapTargetSize: MaterialTapTargetSize.padded,
              ),
            )
            : TextButton(
              key: const ValueKey('clear-filters-btn'),
              onPressed: canClear ? onClear : null,
              style: TextButton.styleFrom(
                minimumSize: const Size(
                  PlatformUiPolicy.minActionSize,
                  PlatformUiPolicy.minActionSize,
                ),
                tapTargetSize: MaterialTapTargetSize.padded,
              ),
              child: Text(t['clearFilters'] ?? 'Clear filters'),
            );
    if (!expanded) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          open,
          if (canClear) clear,
        ],
      );
    }
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
        child: Row(
          children: [
            Expanded(child: open),
            Expanded(child: clear),
          ],
        ),
      ),
    );
  }
}

Future<TaskFilterCriteria?> showTaskFilterEditor({
  required BuildContext context,
  required TaskFilterCriteria applied,
  required String currentBoardName,
  required TaskFilterKind kind,
}) {
  final policy = PlatformUiPolicy.of(context);
  final width = MediaQuery.sizeOf(context).width;

  if (policy.isTouchLayout) {
    return showModalBottomSheet<TaskFilterCriteria>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) {
        final height = MediaQuery.sizeOf(ctx).height * 0.7;
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
          child: SizedBox(
            height: height,
            child: TaskFilterPanel(
              initial: applied,
              currentBoardName: currentBoardName,
              kind: kind,
              showCancel: false,
              onApply: (value) => Navigator.pop(ctx, value),
              onCancel: () => Navigator.pop(ctx),
            ),
          ),
        );
      },
    );
  }

  TaskFilterPanel buildPanel(BuildContext ctx) {
    return TaskFilterPanel(
      initial: applied,
      currentBoardName: currentBoardName,
      kind: kind,
      showCancel: true,
      onApply: (value) => Navigator.pop(ctx, value),
      onCancel: () => Navigator.pop(ctx),
    );
  }

  Widget wrapDesktopPanel(BuildContext ctx, {required double maxHeight}) {
    final size = MediaQuery.sizeOf(ctx);
    final height = maxHeight.clamp(320.0, 560.0);
    final width = (size.width - 48).clamp(280.0, 420.0);
    return SizedBox(
      width: width,
      height: height,
      child: buildPanel(ctx),
    );
  }

  if (width < PlatformUiPolicy.compactHeaderBreakpoint) {
    return showDialog<TaskFilterCriteria>(
      context: context,
      builder: (ctx) {
        final maxHeight = MediaQuery.sizeOf(ctx).height * 0.8;
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: wrapDesktopPanel(ctx, maxHeight: maxHeight),
        );
      },
    );
  }

  return showGeneralDialog<TaskFilterCriteria>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black26,
    pageBuilder: (ctx, animation, secondary) {
      final maxHeight = MediaQuery.sizeOf(ctx).height - 96;
      return SafeArea(
        child: Align(
          alignment: Alignment.topRight,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 72, 16, 16),
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(12),
              clipBehavior: Clip.antiAlias,
              child: wrapDesktopPanel(ctx, maxHeight: maxHeight),
            ),
          ),
        ),
      );
    },
  );
}

class TaskFilterPanel extends StatefulWidget {
  final TaskFilterCriteria initial;
  final String currentBoardName;
  final TaskFilterKind kind;
  final ScrollController? scrollController;
  final bool showCancel;
  final ValueChanged<TaskFilterCriteria> onApply;
  final VoidCallback onCancel;

  const TaskFilterPanel({
    super.key,
    required this.initial,
    required this.currentBoardName,
    required this.kind,
    this.scrollController,
    this.showCancel = false,
    required this.onApply,
    required this.onCancel,
  });

  @override
  State<TaskFilterPanel> createState() => _TaskFilterPanelState();
}

class _TaskFilterPanelState extends State<TaskFilterPanel> {
  late TaskFilterCriteria _draft;
  ScrollController? _ownedController;

  ScrollController? get _listController =>
      widget.scrollController ?? _ownedController;

  @override
  void initState() {
    super.initState();
    _draft = widget.initial;
    if (widget.scrollController == null) {
      _ownedController = ScrollController();
    }
  }

  @override
  void dispose() {
    _ownedController?.dispose();
    super.dispose();
  }

  void _resetDraft() {
    setState(() => _draft = const TaskFilterCriteria());
  }

  Key _scopeKey(TaskScopeFilter scope) {
    if (widget.kind == TaskFilterKind.archive) {
      return ValueKey(
        scope == TaskScopeFilter.currentBoard
            ? 'completed-scope-current'
            : 'completed-scope-all',
      );
    }
    return ValueKey(
      scope == TaskScopeFilter.currentBoard
          ? 'filter-scope-current'
          : 'filter-scope-all',
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.watch<Store>().t;
    final theme = Theme.of(context);
    final policy = PlatformUiPolicy.of(context);
    return Material(
      key: const ValueKey('filter-panel'),
      color: theme.colorScheme.surface,
      child: Column(
        children: [
          if (policy.isTouchLayout)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    t['filter'] ?? 'Filter',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (widget.showCancel)
                  IconButton(
                    key: const ValueKey('filter-cancel-btn'),
                    tooltip: t['cancel'] ?? 'Cancel',
                    onPressed: widget.onCancel,
                    icon: const Icon(Icons.close),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Scrollbar(
              thumbVisibility: policy.isDesktop,
              controller: _listController,
              child: SingleChildScrollView(
                controller: _listController,
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                  _sectionTitle(theme, t['filterScope'] ?? t['boards'] ?? 'Board'),
                  _optionTile(
                    key: _scopeKey(TaskScopeFilter.currentBoard),
                    title: currentBoardFilterLabel(t, widget.currentBoardName),
                    selected: _draft.scope == TaskScopeFilter.currentBoard,
                    onTap: () => setState(
                      () => _draft = _draft.copyWith(
                        scope: TaskScopeFilter.currentBoard,
                      ),
                    ),
                  ),
                  _optionTile(
                    key: _scopeKey(TaskScopeFilter.allBoards),
                    title: t['allBoards'] ?? 'All Boards',
                    selected: _draft.scope == TaskScopeFilter.allBoards,
                    onTap: () => setState(
                      () => _draft = _draft.copyWith(
                        scope: TaskScopeFilter.allBoards,
                      ),
                    ),
                  ),
                  if (widget.kind == TaskFilterKind.search) ...[
                    _sectionTitle(theme, t['filterQuadrant'] ?? 'Quadrant'),
                    _optionTile(
                      key: const ValueKey('filter-q-all'),
                      title: t['all'] ?? 'All',
                      selected: _draft.quadrant == null,
                      onTap: () => setState(
                        () => _draft = _draft.copyWith(quadrant: () => null),
                      ),
                    ),
                    for (final q in allQuadrants)
                      _optionTile(
                        key: ValueKey('filter-q-$q'),
                        title: t['q$q'] ?? 'Q$q',
                        selected: _draft.quadrant == q,
                        leading: CircleAvatar(
                          radius: 6,
                          backgroundColor: Color(quadrantColors[q]!),
                        ),
                        onTap: () => setState(
                          () => _draft = _draft.copyWith(quadrant: () => q),
                        ),
                      ),
                    _sectionTitle(theme, t['filterStatus'] ?? 'Status'),
                    _optionTile(
                      key: const ValueKey('filter-status-all'),
                      title: t['all'] ?? 'All',
                      selected: _draft.status == TaskStatusFilter.all,
                      onTap: () => setState(
                        () => _draft = _draft.copyWith(
                          status: TaskStatusFilter.all,
                        ),
                      ),
                    ),
                    _optionTile(
                      key: const ValueKey('filter-status-incomplete'),
                      title: t['incomplete'] ?? 'Incomplete',
                      selected: _draft.status == TaskStatusFilter.incomplete,
                      onTap: () => setState(
                        () => _draft = _draft.copyWith(
                          status: TaskStatusFilter.incomplete,
                        ),
                      ),
                    ),
                    _optionTile(
                      key: const ValueKey('filter-status-completed'),
                      title: t['completed'] ?? 'Completed',
                      selected: _draft.status == TaskStatusFilter.completed,
                      onTap: () => setState(
                        () => _draft = _draft.copyWith(
                          status: TaskStatusFilter.completed,
                        ),
                      ),
                    ),
                    _sectionTitle(theme, t['filterDate'] ?? 'Date'),
                    _optionTile(
                      key: const ValueKey('filter-date-all'),
                      title: t['all'] ?? 'All',
                      selected: _draft.date == TaskDateFilter.all,
                      onTap: () => setState(
                        () => _draft = _draft.copyWith(
                          date: TaskDateFilter.all,
                        ),
                      ),
                    ),
                    _optionTile(
                      key: const ValueKey('filter-date-today'),
                      title: t['today'] ?? 'Today',
                      selected: _draft.date == TaskDateFilter.today,
                      onTap: () => setState(
                        () => _draft = _draft.copyWith(
                          date: TaskDateFilter.today,
                        ),
                      ),
                    ),
                    _optionTile(
                      key: const ValueKey('filter-date-week'),
                      title: t['thisWeek'] ?? 'This Week',
                      selected: _draft.date == TaskDateFilter.thisWeek,
                      onTap: () => setState(
                        () => _draft = _draft.copyWith(
                          date: TaskDateFilter.thisWeek,
                        ),
                      ),
                    ),
                    _optionTile(
                      key: const ValueKey('filter-date-month'),
                      title: t['thisMonth'] ?? 'This Month',
                      selected: _draft.date == TaskDateFilter.thisMonth,
                      onTap: () => setState(
                        () => _draft = _draft.copyWith(
                          date: TaskDateFilter.thisMonth,
                        ),
                      ),
                    ),
                    _optionTile(
                      key: const ValueKey('filter-date-overdue'),
                      title: t['overdue'] ?? 'Overdue',
                      selected: _draft.date == TaskDateFilter.overdue,
                      onTap: () => setState(
                        () => _draft = _draft.copyWith(
                          date: TaskDateFilter.overdue,
                        ),
                      ),
                    ),
                    _optionTile(
                      key: const ValueKey('filter-date-nodate'),
                      title: t['noDate'] ?? 'No Date',
                      selected: _draft.date == TaskDateFilter.noDate,
                      onTap: () => setState(
                        () => _draft = _draft.copyWith(
                          date: TaskDateFilter.noDate,
                        ),
                      ),
                    ),
                  ],
                ],
                ),
              ),
            ),
          ),
          const Divider(height: 1),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
              child: Row(
                children: [
                  TextButton(
                    key: const ValueKey('filter-reset-btn'),
                    onPressed: _resetDraft,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(
                        PlatformUiPolicy.minActionSize,
                        PlatformUiPolicy.minActionSize,
                      ),
                    ),
                    child: Text(t['resetFilters'] ?? 'Reset'),
                  ),
                  const Spacer(),
                  if (widget.showCancel)
                    TextButton(
                      onPressed: widget.onCancel,
                      style: TextButton.styleFrom(
                        minimumSize: const Size(
                          PlatformUiPolicy.minActionSize,
                          PlatformUiPolicy.minActionSize,
                        ),
                      ),
                      child: Text(t['cancel'] ?? 'Cancel'),
                    ),
                  FilledButton(
                    key: const ValueKey('filter-apply-btn'),
                    onPressed: () => widget.onApply(_draft),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(
                        PlatformUiPolicy.minActionSize,
                        PlatformUiPolicy.minActionSize,
                      ),
                    ),
                    child: Text(t['applyFilters'] ?? 'Apply'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(ThemeData theme, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _optionTile({
    required Key key,
    required String title,
    required bool selected,
    required VoidCallback onTap,
    Widget? leading,
  }) {
    return ListTile(
      key: key,
      minVerticalPadding: 12,
      leading:
          leading ??
          Icon(selected ? Icons.check_circle : Icons.circle_outlined),
      title: Text(title),
      selected: selected,
      trailing: selected && leading != null ? const Icon(Icons.check) : null,
      onTap: onTap,
    );
  }
}
