import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../storage.dart';
import 'anim.dart';

class TaskCard extends StatelessWidget {
  final Task task;
  final int entranceIndex;
  final VoidCallback onChanged;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onDecompose;
  final VoidCallback onDecomposeStart; // signals busy state externally

  const TaskCard({
    super.key,
    required this.task,
    required this.entranceIndex,
    required this.onChanged,
    required this.onEdit,
    required this.onDelete,
    required this.onDecompose,
    required this.onDecomposeStart,
  });

  @override
  Widget build(BuildContext context) {
    final store = context.read<Store>();
    final t = store.t;
    final theme = Theme.of(context);
    final daysLeft = task.deadline == null
        ? null
        : ((task.deadline! - DateTime.now().millisecondsSinceEpoch) / 86400000).ceil();

    return StaggerIn(
      key: ValueKey('stagger-${task.id}'),
      index: entranceIndex,
      child: Card(
        margin: const EdgeInsets.only(bottom: 10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {},
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Checkbox(
                      value: task.completed,
                      onChanged: (_) {
                        store.setParentCompleted(task, !task.completed);
                        onChanged();
                      },
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          StrikeThrough(
                            crossed: task.completed,
                            child: Text(
                              task.title,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: task.completed
                                    ? theme.colorScheme.onSurface.withValues(alpha: 0.38)
                                    : null,
                              ),
                            ),
                          ),
                          if (task.reasoning != null && task.reasoning!.isNotEmpty && !task.completed)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                task.reasoning!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontStyle: FontStyle.italic,
                                  color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
                                ),
                              ),
                            ),
                          _DeadlineChip(daysLeft: daysLeft, done: task.completed, t: t),
                        ],
                      ),
                    ),
                  ],
                ),
                // Action row sits under the title so half-width quadrants never overflow.
                Align(
                  alignment: Alignment.centerRight,
                  child: _ActionRow(task: task, onEdit: onEdit, onDelete: onDelete, onDecompose: onDecompose, onDecomposeStart: onDecomposeStart),
                ),
                ..._subtasks(context, t, theme),
                if (!task.completed) _addSubtaskField(context, t, theme),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _subtasks(BuildContext context, Map<String, String> t, ThemeData theme) {
    if (task.subtasks.isEmpty) return [];
    return [
      const SizedBox(height: 6),
      Container(
        margin: const EdgeInsets.only(left: 8),
        padding: const EdgeInsets.only(left: 10),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(width: 2, color: theme.colorScheme.onSurface.withValues(alpha: 0.15)),
          ),
        ),
        child: Column(
          children: [
            for (final sub in task.subtasks)
              Row(
                children: [
                  SizedBox(
                    width: 30,
                    height: 30,
                    child: Checkbox(
                      value: sub.completed,
                      onChanged: (_) {
                        sub.completed = !sub.completed;
                        context.read<Store>().updateTask(task);
                        onChanged();
                      },
                    ),
                  ),
                  Expanded(
                    child: StrikeThrough(
                      crossed: sub.completed,
                      child: Text(
                        sub.title,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: sub.completed
                              ? theme.colorScheme.onSurface.withValues(alpha: 0.38)
                              : null,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.edit_outlined, size: 15),
                    onPressed: () => _editSubtask(context, sub),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Icons.close, size: 15, color: theme.colorScheme.error.withValues(alpha: 0.7)),
                    onPressed: () {
                      task.subtasks.remove(sub);
                      context.read<Store>().updateTask(task);
                      onChanged();
                    },
                  ),
                ],
              ),
          ],
        ),
      ),
    ];
  }

  Widget _addSubtaskField(BuildContext context, Map<String, String> t, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, top: 4),
      child: _AddSubtaskField(
        hintText: t['addSubtask']!,
        onSubmit: (text) {
          context.read<Store>().appendSubtasks(task.id, [
            SubTask(id: DateTime.now().microsecondsSinceEpoch.toString(), title: text),
          ]);
          onChanged();
        },
      ),
    );
  }

  Future<void> _editSubtask(BuildContext context, SubTask sub) async {
    final store = context.read<Store>();
    final controller = TextEditingController(text: sub.title);
    final newName = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(store.t['editTask']!),
        content: TextField(controller: controller, autofocus: true, onSubmitted: (v) => Navigator.pop(dialogContext, v)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(store.t['cancel']!)),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text), child: Text(store.t['confirm']!)),
        ],
      ),
    );
    if (newName != null && newName.trim().isNotEmpty) {
      sub.title = newName.trim();
      store.updateTask(task);
      onChanged();
    }
  }
}

class _DeadlineChip extends StatelessWidget {
  final int? daysLeft;
  final bool done;
  final Map<String, String> t;
  const _DeadlineChip({required this.daysLeft, required this.done, required this.t});

  @override
  Widget build(BuildContext context) {
    if (daysLeft == null || done) return const SizedBox.shrink();
    final overdue = daysLeft! < 0;
    final today = daysLeft == 0;
    final urgent = daysLeft! <= 2;
    final color = overdue || today
        ? Theme.of(context).colorScheme.error
        : urgent
            ? Colors.orange
            : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4);
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.calendar_month, size: 11, color: color),
          const SizedBox(width: 3),
          Text(
            overdue ? t['overdue']! : today ? t['today']! : '$daysLeft${t['daysLeft']}',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final Task task;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onDecompose;
  final VoidCallback onDecomposeStart;
  const _ActionRow({
    required this.task,
    required this.onEdit,
    required this.onDelete,
    required this.onDecompose,
    required this.onDecomposeStart,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.read<Store>().t;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (task.isLongTerm && !task.hasSubtasks)
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: t['decomposingSingle'],
            icon: const Icon(Icons.call_split, size: 16, color: Color(0xFFF59E0B)),
            onPressed: () {
              onDecomposeStart();
              onDecompose();
            },
          ),
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: t['toggleLongTerm'],
          icon: Icon(
            Icons.flag_outlined,
            size: 16,
            color: task.isLongTerm ? const Color(0xFFF59E0B) : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
          ),
          onPressed: () {
            task.isLongTerm = !task.isLongTerm;
            context.read<Store>().updateTask(task);
          },
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: t['editTask'],
          icon: Icon(Icons.edit_outlined, size: 16, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55)),
          onPressed: onEdit,
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: t['delete'],
          icon: Icon(Icons.delete_outline, size: 16, color: Theme.of(context).colorScheme.error.withValues(alpha: 0.7)),
          onPressed: onDelete,
        ),
      ],
    );
  }
}

class _AddSubtaskField extends StatefulWidget {
  final String hintText;
  final ValueChanged<String> onSubmit;
  const _AddSubtaskField({required this.hintText, required this.onSubmit});

  @override
  State<_AddSubtaskField> createState() => _AddSubtaskFieldState();
}

class _AddSubtaskFieldState extends State<_AddSubtaskField> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      decoration: InputDecoration(
        hintText: widget.hintText,
        prefixIcon: const Icon(Icons.add, size: 16),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      style: Theme.of(context).textTheme.bodySmall,
      onSubmitted: (value) {
        final text = value.trim();
        if (text.isEmpty) return;
        widget.onSubmit(text);
        _controller.clear();
      },
    );
  }
}
