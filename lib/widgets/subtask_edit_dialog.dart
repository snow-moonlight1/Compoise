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
  builder: (dialogContext) => _SubtaskEditDialog(
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
    if (hasPendingImeComposition(_title) || hasPendingImeComposition(_notes)) {
      return;
    }
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

  Future<void> _editTime() async {
    final result = await showTaskTimeEditor(
      context,
      t: _t,
      deadline: _deadline,
      reminderAt: _reminderAt,
    );
    if (result == null || !mounted) return;
    setState(() {
      _deadline = result.deadline;
      _reminderAt = result.reminderAt;
    });
  }

  Future<void> _editNotes() async {
    final controller = TextEditingController(text: _notes.text);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_t['subtaskNotes']!),
        content: SizedBox(
          width: 420,
          child: TextField(
            key: const ValueKey('subtask-edit-notes'),
            controller: controller,
            autofocus: true,
            minLines: 4,
            maxLines: 12,
            keyboardType: TextInputType.multiline,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(_t['cancel']!),
          ),
          FilledButton(
            onPressed: () {
              if (!hasPendingImeComposition(controller)) {
                Navigator.pop(dialogContext, controller.text);
              }
            },
            child: Text(_t['confirm']!),
          ),
        ],
      ),
    );
    if (mounted && result != null) setState(() => _notes.text = result);
    Future<void>.delayed(const Duration(milliseconds: 350), controller.dispose);
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
            TextButton.icon(
              key: const ValueKey('subtask-notes-entry'),
              onPressed: _editNotes,
              icon: const Icon(Icons.notes_outlined),
              label: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _notes.text.trim().isEmpty ? _t['notesHint']! : _notes.text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const ValueKey('subtask-time-btn'),
              onPressed: _editTime,
              icon: const Icon(Icons.schedule),
              label: Text(_t['timePanel']!),
            ),
            if (_deadline != null || _reminderAt != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  [
                    if (_deadline != null)
                      '${_t['deadline']}: ${formatCivilDate(_deadline!)}',
                    if (_reminderAt != null)
                      '${_t['reminder']}: ${formatCivilDateTimeMs(_reminderAt!)}',
                  ].join(' · '),
                  style: theme.textTheme.bodySmall,
                ),
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
