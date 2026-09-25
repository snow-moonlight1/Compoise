import 'package:flutter/material.dart';

import '../models.dart';
import 'date_edit_fields.dart';
import 'task_edit_draft.dart';

/// Opens the subtask editor and returns the edited subtask, or null when the
/// user cancels. The dialog owns its text controllers and releases them when it
/// closes, so reopening it repeatedly does not accumulate them.
Future<SubTaskEditResult?> showSubtaskEditDialog(
  BuildContext context, {
  required Map<String, String> t,
  required SubTask subtask,
  DateTime? parentDeadline,
}) => showDialog<SubTaskEditResult>(
  context: context,
  builder:
      (dialogContext) => _SubtaskEditDialog(
        t: t,
        subtask: subtask,
        parentDeadline: parentDeadline,
      ),
);

/// What the user confirmed in [showSubtaskEditDialog].
class SubTaskEditResult {
  const SubTaskEditResult({
    required this.title,
    required this.notesMarkdown,
    required this.deadline,
    required this.reminderAt,
  });

  final String title;
  final String? notesMarkdown;
  final int? deadline;
  final int? reminderAt;
}

class _SubtaskEditDialog extends StatefulWidget {
  const _SubtaskEditDialog({
    required this.t,
    required this.subtask,
    this.parentDeadline,
  });

  final Map<String, String> t;
  final SubTask subtask;
  final DateTime? parentDeadline;

  @override
  State<_SubtaskEditDialog> createState() => _SubtaskEditDialogState();
}

class _SubtaskEditDialogState extends State<_SubtaskEditDialog> {
  late final TextEditingController _title;
  late final TextEditingController _notes;
  late DateTime? _deadline = _subtask.deadline == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(_subtask.deadline!);
  late int? _reminderAt = _subtask.reminderAt;

  SubTask get _subtask => widget.subtask;
  Map<String, String> get _t => widget.t;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: _subtask.title);
    _notes = TextEditingController(text: _subtask.notesMarkdown ?? '');
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _submit() {
    if (hasPendingImeComposition(_title)) return;
    final title = _title.text.trim();
    if (title.isEmpty) return;
    final notes = _notes.text.trim();
    Navigator.pop(
      context,
      SubTaskEditResult(
        title: title,
        notesMarkdown: notes.isEmpty ? null : _notes.text,
        deadline: endOfCivilDayMs(_deadline),
        reminderAt: _reminderAt,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isAfterParent = isAfterParentDay(_deadline, widget.parentDeadline);

    return AlertDialog(
      title: Text(_t['editSubtask'] ?? 'Edit Subtask'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const ValueKey('subtask-edit-title'),
              controller: _title,
              autofocus: true,
              decoration: InputDecoration(
                labelText: _t['subtasks'] ?? 'Subtask',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _t['deadline'] ?? 'Deadline',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            DeadlineDayChips(
              t: _t,
              keyPrefix: 'subtask-deadline',
              selected: _deadline,
              onChanged: (day) => setState(() => _deadline = day),
            ),
            if (isAfterParent)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _t['subtaskDeadlineAfterParent']!,
                  key: const ValueKey('subtask-after-parent-warning'),
                  style: TextStyle(color: Colors.amber.shade800, fontSize: 12),
                ),
              ),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('subtask-edit-notes'),
              controller: _notes,
              minLines: 2,
              maxLines: 4,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                labelText: _t['subtaskNotes'] ?? _t['notes'] ?? 'Notes',
                hintText: _t['notesHint'] ?? 'Add notes…',
                alignLabelWithHint: true,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _t['reminder'] ?? 'Reminder',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: const ValueKey('subtask-reminder-btn'),
                    icon: Icon(
                      _reminderAt == null
                          ? Icons.notifications_none
                          : Icons.notifications_active,
                      size: 16,
                    ),
                    label: Text(
                      _reminderAt == null
                          ? (_t['setReminder'] ?? 'Set Reminder')
                          : formatCivilDateTimeMs(_reminderAt!),
                      style: const TextStyle(fontSize: 12),
                    ),
                    onPressed:
                        () => pickReminderMoment(
                          context,
                          t: _t,
                          reminderAt: _reminderAt,
                          deadline: _deadline,
                          onPicked:
                              (moment) =>
                                  setState(() => _reminderAt = moment),
                        ),
                  ),
                ),
                if (_reminderAt != null)
                  IconButton(
                    key: const ValueKey('subtask-reminder-clear'),
                    tooltip: _t['clearReminder'] ?? 'Clear Reminder',
                    icon: const Icon(Icons.close, size: 18),
                    visualDensity: VisualDensity.compact,
                    onPressed:
                        () => setState(() => _reminderAt = null),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('subtask-cancel-btn'),
          onPressed: () => Navigator.pop(context),
          child: Text(_t['cancel']!),
        ),
        FilledButton(
          key: const ValueKey('subtask-save-btn'),
          onPressed: _submit,
          child: Text(_t['save'] ?? 'Save'),
        ),
      ],
    );
  }
}
