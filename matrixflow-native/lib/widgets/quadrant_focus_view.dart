import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../storage.dart';
import 'quadrant_pane.dart';

/// Single quadrant focused view:
/// The focused quadrant occupies the main upper area with full width task rows,
/// while the remaining three quadrants are collapsed at the bottom into compact cards.
class QuadrantFocusView extends StatelessWidget {
  final int focusedQuadrant;
  final bool selecting;
  final Set<String> selectedIds;
  final Set<String> expandedIds;
  final ValueChanged<String>? onSelect;
  final ValueChanged<String>? onToggleExpand;
  final ValueChanged<String>? onEnsureExpanded;
  final ValueChanged<int> onSwitchQuadrant;
  final VoidCallback onExitFocus;
  final ValueChanged<Task>? onEdit;
  final ScrollController? scrollController;

  const QuadrantFocusView({
    super.key,
    required this.focusedQuadrant,
    this.selecting = false,
    this.selectedIds = const {},
    this.expandedIds = const {},
    this.onSelect,
    this.onToggleExpand,
    this.onEnsureExpanded,
    required this.onSwitchQuadrant,
    required this.onExitFocus,
    this.onEdit,
    this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    final store = context.watch<Store>();
    final t = store.t;
    final theme = Theme.of(context);

    final otherQuadrants = [qDo, qPlan, qDelegate, qEliminate]
        .where((q) => q != focusedQuadrant)
        .toList();

    final dividerColor =
        theme.brightness == Brightness.light
            ? const Color(0xFFD5DAE1)
            : theme.colorScheme.outlineVariant;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Main focused quadrant list
        Expanded(
          child: QuadrantPane(
            quadrant: focusedQuadrant,
            selecting: selecting,
            selectedIds: selectedIds,
            expandedIds: expandedIds,
            onSelect: onSelect,
            onToggleExpand: onToggleExpand,
            onEnsureExpanded: onEnsureExpanded,
            onQuadrantTap: onExitFocus,
            onEdit: onEdit,
            isFocused: true,
            scrollController: scrollController,
          ),
        ),

        Divider(height: 1, thickness: 1, color: dividerColor),
        const SizedBox(height: 6),

        // Three collapsed bottom cards in numerical order
        Container(
          constraints: const BoxConstraints(minHeight: 60),
          padding: const EdgeInsets.fromLTRB(6, 2, 6, 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final q in otherQuadrants) ...[
                Expanded(
                  child: _CollapsedQuadrantCard(
                    key: ValueKey('focus-card-$q'),
                    quadrant: q,
                    title: _titleFor(t, q),
                    count: store.tasksIn(q).length,
                    accent: Color(quadrantColors[q]!),
                    selecting: selecting,
                    onTap: () => onSwitchQuadrant(q),
                    onDropTask: (task) => store.moveTask(task.id, q),
                  ),
                ),
                if (q != otherQuadrants.last) const SizedBox(width: 6),
              ],
            ],
          ),
        ),
      ],
    );
  }

  String _titleFor(Map<String, String> t, int q) {
    return switch (q) {
      qDo => t['q1']!,
      qPlan => t['q2']!,
      qDelegate => t['q3']!,
      _ => t['q4']!,
    };
  }
}

class _CollapsedQuadrantCard extends StatefulWidget {
  final int quadrant;
  final String title;
  final int count;
  final Color accent;
  final bool selecting;
  final VoidCallback onTap;
  final ValueChanged<Task>? onDropTask;

  const _CollapsedQuadrantCard({
    super.key,
    required this.quadrant,
    required this.title,
    required this.count,
    required this.accent,
    required this.selecting,
    required this.onTap,
    this.onDropTask,
  });

  @override
  State<_CollapsedQuadrantCard> createState() => _CollapsedQuadrantCardState();
}

class _CollapsedQuadrantCardState extends State<_CollapsedQuadrantCard> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final store = context.read<Store>();

    return DragTarget<Task>(
      onWillAcceptWithDetails: (details) =>
          !widget.selecting && details.data.boardId == store.activeBoardId,
      onMove: (_) {
        if (!_hovering) setState(() => _hovering = true);
      },
      onLeave: (_) {
        if (_hovering) setState(() => _hovering = false);
      },
      onAcceptWithDetails: (details) {
        setState(() => _hovering = false);
        widget.onDropTask?.call(details.data);
      },
      builder: (context, candidate, _) {
        final isHovered = _hovering || candidate.isNotEmpty;
        final borderColor = isHovered
            ? widget.accent
            : (theme.brightness == Brightness.light
                ? const Color(0xFFD5DAE1)
                : theme.colorScheme.outlineVariant);
        final bgColor = isHovered
            ? widget.accent.withValues(alpha: 0.12)
            : theme.colorScheme.surface;

        return Material(
          color: bgColor,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: widget.onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: borderColor,
                  width: isHovered ? 1.5 : 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: widget.accent,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '${widget.count}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: widget.accent,
                        ),
                      ),
                      const Spacer(),
                      Icon(
                        Icons.chevron_right,
                        size: 14,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.35,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    widget.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      height: 1.15,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
