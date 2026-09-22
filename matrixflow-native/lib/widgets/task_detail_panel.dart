import 'reminder_failure_banner.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../storage.dart';
import 'input_sheet.dart';
import 'task_hierarchy_checkbox.dart';

/// Confirms discarding an unsaved detail draft. Returns true when the user
/// chooses to discard, false when they keep editing or dismiss the dialog.
Future<bool> confirmDiscardDraft(BuildContext context) async {
  final t = context.read<Store>().t;
  final res = await showDialog<bool>(
    context: context,
    builder:
        (ctx) => AlertDialog(
          title: Text(t['discardChangesTitle'] ?? 'Discard changes?'),
          content: Text(
            t['discardChangesConfirm'] ??
                'You have unsaved changes. Discard them?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(t['keepEditing'] ?? 'Keep Editing'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(t['discard'] ?? 'Discard'),
            ),
          ],
        ),
  );
  return res ?? false;
}

Future<void> showReminderAccessFeedback(BuildContext context) async {
  final status = await requestReminderAccess();
  if (!context.mounted) return;
  final t = context.read<Store>().t;
  if (status == ReminderPermissionStatus.denied ||
      status == ReminderPermissionStatus.unsupported) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          t['notifPermissionDenied'] ??
              'Notification permission denied; reminder is saved but may not fire',
        ),
      ),
    );
  } else if (status == ReminderPermissionStatus.inexactOnly) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          t['exactAlarmRestricted'] ??
              'Exact alarms restricted; reminder may be delayed',
        ),
      ),
    );
  }
}

/// Shows the task detail as a modal bottom sheet on narrow screens.
Future<void> showTaskDetailSheet(
  BuildContext context,
  Task task, {
  String? highlightSubtaskId,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Theme.of(context).colorScheme.surface,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
  ),
  builder:
      (_) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder:
            (sheetContext, scrollController) => TaskDetailPanel(
              key: ValueKey('task-detail-${task.id}'),
              task: task,
              scrollController: scrollController,
              highlightSubtaskId: highlightSubtaskId,
            ),
      ),
);

/// Central task detail editor for parent and child tasks.
/// Can be rendered inside a bottom sheet or as a desktop side panel.
class TaskDetailPanel extends StatefulWidget {
  final Task task;
  final VoidCallback? onClose;
  final ValueChanged<bool>? onDirtyChanged;
  final bool isSidebar;
  final ScrollController? scrollController;
  final String? highlightSubtaskId;

  const TaskDetailPanel({
    super.key,
    required this.task,
    this.onClose,
    this.onDirtyChanged,
    this.isSidebar = false,
    this.scrollController,
    this.highlightSubtaskId,
  });

  @override
  State<TaskDetailPanel> createState() => _TaskDetailPanelState();
}

class _TaskDetailPanelState extends State<TaskDetailPanel> {
  late final TextEditingController _title;
  late final TextEditingController _notes;
  late int _quadrant;
  late DateTime? _deadline;
  late int? _reminderAt;
  late bool _isLongTerm;
  late UrgencyMode _urgencyMode;
  late List<SubTask> _subtasks;
  late List<SubTask> _openedSubtasks;

  final TextEditingController _newSubtaskController = TextEditingController();

  late String _initialTitle;
  late String _initialNotes;
  late int _initialQuadrant;
  late int? _initialDeadlineMs;
  late int? _initialReminderAt;
  late bool _initialIsLongTerm;
  late UrgencyMode _initialUrgencyMode;
  late String _initialSubtasksJson;

  bool _forceClose = false;
  bool _notifyingDirty = false;
  bool _loadingTask = false;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController();
    _notes = TextEditingController();
    _loadFromTask(widget.task);
    _title.addListener(_onDraftChanged);
    _notes.addListener(_onDraftChanged);
  }

  @override
  void didUpdateWidget(TaskDetailPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.task.id != widget.task.id) {
      _loadFromTask(widget.task);
    }
  }

  @override
  void dispose() {
    _title.removeListener(_onDraftChanged);
    _notes.removeListener(_onDraftChanged);
    _title.dispose();
    _notes.dispose();
    _newSubtaskController.dispose();
    super.dispose();
  }

  void _loadFromTask(Task task) {
    _loadingTask = true;
    _title.text = task.title;
    _notes.text = task.notesMarkdown ?? '';
    _quadrant = task.quadrant;
    _deadline =
        task.deadline == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(task.deadline!);
    _reminderAt = task.reminderAt;
    _isLongTerm = task.isLongTerm;
    _urgencyMode = task.urgencyMode;
    _subtasks = [for (final s in task.subtasks) SubTask.fromJson(s.toJson())];
    _openedSubtasks = [
      for (final s in task.subtasks) SubTask.fromJson(s.toJson()),
    ];
    _initialTitle = task.title;
    _initialNotes = task.notesMarkdown ?? '';
    _initialQuadrant = task.quadrant;
    _initialDeadlineMs = task.deadline;
    _initialReminderAt = task.reminderAt;
    _initialIsLongTerm = task.isLongTerm;
    _initialUrgencyMode = task.urgencyMode;
    _initialSubtasksJson = jsonEncode(
      task.subtasks.map((s) => s.toJson()).toList(),
    );
    _forceClose = false;
    _loadingTask = false;
    _emitDirty();
  }

  void _onDraftChanged() {
    if (!mounted || _loadingTask) return;
    setState(() {});
    _emitDirty();
  }

  void _emitDirty() {
    if (_notifyingDirty) return;
    _notifyingDirty = true;
    widget.onDirtyChanged?.call(_isDirty);
    _notifyingDirty = false;
  }

  bool _isSameDay(DateTime? a, DateTime? b) {
    if (a == null || b == null) return false;
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _formatDateTime(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  bool get _isDirty {
    if (_forceClose) return false;
    if (_title.text.trim() != _initialTitle.trim()) return true;
    if (_notes.text.trim() != _initialNotes.trim()) return true;
    if (_quadrant != _initialQuadrant) return true;
    final initialMs = _initialDeadlineMs;
    final initialDate =
        initialMs == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(initialMs);
    if (_deadline == null
        ? initialDate != null
        : !_isSameDay(_deadline, initialDate)) {
      return true;
    }
    if (_reminderAt != _initialReminderAt) return true;
    if (_isLongTerm != _initialIsLongTerm) return true;
    if (_urgencyMode != _initialUrgencyMode) return true;
    final currentSubtasksJson = jsonEncode(
      _subtasks.map((s) => s.toJson()).toList(),
    );
    if (currentSubtasksJson != _initialSubtasksJson) return true;
    return false;
  }

  Future<void> _notifyReminderAccess() => showReminderAccessFeedback(context);

  void _close() {
    if (widget.onClose != null) {
      widget.onClose!();
    } else if (Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }

  Future<bool> _confirmDiscard(BuildContext context) =>
      confirmDiscardDraft(context);

  Future<void> _attemptClose() async {
    if (!_isDirty) {
      _close();
      return;
    }
    final discard = await _confirmDiscard(context);
    if (discard && mounted) {
      _forceClose = true;
      widget.onDirtyChanged?.call(false);
      _close();
    }
  }

  int? _normalizedDeadline(DateTime? d) =>
      d == null
          ? null
          : DateTime(d.year, d.month, d.day, 23, 59, 59).millisecondsSinceEpoch;

  bool _sameDayMs(int? a, int? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    final da = DateTime.fromMillisecondsSinceEpoch(a);
    final db = DateTime.fromMillisecondsSinceEpoch(b);
    return _isSameDay(da, db);
  }

  String _subJson(SubTask s) => jsonEncode(s.toJson());

  List<SubTask> _mergedSubtasks(List<SubTask> current) {
    final draftJson = jsonEncode(_subtasks.map((s) => s.toJson()).toList());
    if (draftJson == _initialSubtasksJson) {
      return [for (final s in current) SubTask.fromJson(s.toJson())];
    }

    final openedById = {for (final s in _openedSubtasks) s.id: s};
    final currentById = {for (final s in current) s.id: s};
    final result = <SubTask>[];
    final seen = <String>{};

    for (final draft in _subtasks) {
      seen.add(draft.id);
      final initial = openedById[draft.id];
      final live = currentById[draft.id];
      if (initial == null) {
        result.add(SubTask.fromJson(draft.toJson()));
        continue;
      }
      if (live == null) continue;
      if (_subJson(draft) == _subJson(initial)) {
        result.add(SubTask.fromJson(live.toJson()));
        continue;
      }
      final merged = SubTask.fromJson(draft.toJson());
      if (draft.title == initial.title) merged.title = live.title;
      if ((draft.notesMarkdown ?? '') == (initial.notesMarkdown ?? '')) {
        merged.notesMarkdown = live.notesMarkdown;
      }
      if (draft.deadline == initial.deadline) merged.deadline = live.deadline;
      if (draft.reminderAt == initial.reminderAt) {
        merged.reminderAt = live.reminderAt;
      }
      if (draft.completed == initial.completed) {
        merged.completed = live.completed;
        merged.completedAt = live.completedAt;
      }
      result.add(merged);
    }

    for (final live in current) {
      if (!seen.contains(live.id) && !openedById.containsKey(live.id)) {
        result.add(SubTask.fromJson(live.toJson()));
      }
    }
    return result;
  }

  void _save() {
    final titleText = _title.text.trim();
    if (titleText.isEmpty) return;

    final store = context.read<Store>();
    final current =
        store.tasks.where((t) => t.id == widget.task.id).firstOrNull;
    if (current == null) {
      _forceClose = true;
      widget.onDirtyChanged?.call(false);
      _close();
      return;
    }

    final notesText = _notes.text.trim();
    final draftNotes = notesText.isEmpty ? null : _notes.text;
    final draftDeadline = _normalizedDeadline(_deadline);
    final titleChanged = titleText != _initialTitle.trim();
    final notesChanged = (draftNotes ?? '').trim() != _initialNotes.trim();
    final quadrantChanged = _quadrant != _initialQuadrant;
    final deadlineChanged = !_sameDayMs(draftDeadline, _initialDeadlineMs);
    final reminderChanged = _reminderAt != _initialReminderAt;
    final longTermChanged = _isLongTerm != _initialIsLongTerm;
    final urgencyChanged = _urgencyMode != _initialUrgencyMode;

    final updated =
        Task.fromJson(current.toJson())
          ..title = titleChanged ? titleText : current.title
          ..notesMarkdown = notesChanged ? draftNotes : current.notesMarkdown
          ..quadrant = quadrantChanged ? _quadrant : current.quadrant
          ..deadline = deadlineChanged ? draftDeadline : current.deadline
          ..reminderAt = reminderChanged ? _reminderAt : current.reminderAt
          ..isLongTerm = longTermChanged ? _isLongTerm : current.isLongTerm
          ..urgencyMode = urgencyChanged ? _urgencyMode : current.urgencyMode
          ..subtasks = _mergedSubtasks(current.subtasks);

    store.updateTask(updated);
    _forceClose = true;
    widget.onDirtyChanged?.call(false);
    _close();
  }

  Future<void> _confirmDeleteTask() async {
    final store = context.read<Store>();
    final t = store.t;
    final ok = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Text(t['deleteTaskTitle']!),
            content: Text(t['deleteTaskConfirm']!),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(t['cancel']!),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(t['confirm']!),
              ),
            ],
          ),
    );
    if (ok == true && mounted) {
      store.deleteTask(widget.task.id);
      _forceClose = true;
      _close();
    }
  }

  Future<void> _pickDate() async {
    final first = DateTime(1900);
    final last = DateTime(2200, 12, 31);
    final date = _deadline ?? DateTime.now();
    final initial =
        date.isBefore(first)
            ? first
            : date.isAfter(last)
            ? last
            : date;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
    );
    if (mounted && picked != null) setState(() => _deadline = picked);
  }

  Future<void> _pickReminderDateTime() async {
    final now = DateTime.now();
    final initialDate =
        _reminderAt != null
            ? DateTime.fromMillisecondsSinceEpoch(_reminderAt!)
            : (_deadline ?? now);
    final firstDate = DateTime(now.year, now.month, now.day);
    final lastDate = DateTime(now.year + 5);

    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initialDate.isBefore(firstDate) ? firstDate : initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
    );
    if (pickedDate == null || !mounted) return;

    final initialTime =
        _reminderAt != null
            ? TimeOfDay.fromDateTime(
              DateTime.fromMillisecondsSinceEpoch(_reminderAt!),
            )
            : const TimeOfDay(hour: 9, minute: 0);

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: initialTime,
    );
    if (pickedTime == null || !mounted) return;

    final combined = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );

    if (combined.isBefore(DateTime.now())) {
      final t = context.read<Store>().t;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              t['reminderPastError'] ?? 'Reminder time cannot be in the past',
            ),
          ),
        );
      }
      return;
    }

    setState(() {
      _reminderAt = combined.millisecondsSinceEpoch;
    });
    await _notifyReminderAccess();
  }

  void _addSubtask() {
    final text = _newSubtaskController.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _subtasks.add(SubTask(id: newId(), title: text));
      _newSubtaskController.clear();
    });
  }

  Future<void> _editSubtask(SubTask sub) async {
    final store = context.read<Store>();
    final t = store.t;
    final theme = Theme.of(context);
    final titleController = TextEditingController(text: sub.title);
    final notesController = TextEditingController(
      text: sub.notesMarkdown ?? '',
    );
    DateTime? subDeadline =
        sub.deadline == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(sub.deadline!);
    int? subReminder = sub.reminderAt;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final now = DateTime.now();
            final today = DateTime(now.year, now.month, now.day);
            final tomorrow = today.add(const Duration(days: 1));
            final isCustom =
                subDeadline != null &&
                !_isSameDay(subDeadline, today) &&
                !_isSameDay(subDeadline, tomorrow);

            final isAfterParent =
                _deadline != null &&
                subDeadline != null &&
                subDeadline!.isAfter(
                  DateTime(
                    _deadline!.year,
                    _deadline!.month,
                    _deadline!.day,
                    23,
                    59,
                    59,
                  ),
                );

            return AlertDialog(
              title: Text(t['editSubtask'] ?? 'Edit Subtask'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      key: const ValueKey('subtask-edit-title'),
                      controller: titleController,
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: t['subtasks'] ?? 'Subtask',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      t['deadline'] ?? 'Deadline',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        ChoiceChip(
                          key: const ValueKey('subtask-deadline-today'),
                          avatar: const Icon(Icons.today, size: 16),
                          label: Text(t['today']!),
                          selected: _isSameDay(subDeadline, today),
                          onSelected: (selected) {
                            setDialogState(() {
                              subDeadline = selected ? today : null;
                            });
                          },
                        ),
                        ChoiceChip(
                          key: const ValueKey('subtask-deadline-tomorrow'),
                          avatar: const Icon(Icons.event, size: 16),
                          label: Text(t['tomorrow']!),
                          selected: _isSameDay(subDeadline, tomorrow),
                          onSelected: (selected) {
                            setDialogState(() {
                              subDeadline = selected ? tomorrow : null;
                            });
                          },
                        ),
                        ChoiceChip(
                          key: const ValueKey('subtask-deadline-custom'),
                          avatar: const Icon(Icons.calendar_month, size: 16),
                          label: Text(
                            isCustom
                                ? _formatDate(subDeadline!)
                                : t['pickDate']!,
                          ),
                          selected: isCustom,
                          onSelected: (_) async {
                            final first = DateTime(1900);
                            final last = DateTime(2200, 12, 31);
                            final initial = subDeadline ?? today;
                            final picked = await showDatePicker(
                              context: context,
                              initialDate:
                                  initial.isBefore(first)
                                      ? first
                                      : initial.isAfter(last)
                                      ? last
                                      : initial,
                              firstDate: first,
                              lastDate: last,
                            );
                            if (picked != null) {
                              setDialogState(() {
                                subDeadline = DateTime(
                                  picked.year,
                                  picked.month,
                                  picked.day,
                                );
                              });
                            }
                          },
                        ),
                        if (subDeadline != null)
                          IconButton(
                            key: const ValueKey('subtask-deadline-clear'),
                            tooltip: t['clearDate']!,
                            icon: const Icon(Icons.close, size: 18),
                            visualDensity: VisualDensity.compact,
                            onPressed:
                                () => setDialogState(() => subDeadline = null),
                          ),
                      ],
                    ),
                    if (isAfterParent)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          t['subtaskDeadlineAfterParent']!,
                          key: const ValueKey('subtask-after-parent-warning'),
                          style: TextStyle(
                            color: Colors.amber.shade800,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                    TextField(
                      key: const ValueKey('subtask-edit-notes'),
                      controller: notesController,
                      minLines: 2,
                      maxLines: 4,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      decoration: InputDecoration(
                        labelText: t['subtaskNotes'] ?? t['notes'] ?? 'Notes',
                        hintText: t['notesHint'] ?? 'Add notes…',
                        alignLabelWithHint: true,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      t['reminder'] ?? 'Reminder',
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
                              subReminder == null
                                  ? Icons.notifications_none
                                  : Icons.notifications_active,
                              size: 16,
                            ),
                            label: Text(
                              subReminder == null
                                  ? (t['setReminder'] ?? 'Set Reminder')
                                  : _formatDateTime(
                                    DateTime.fromMillisecondsSinceEpoch(
                                      subReminder!,
                                    ),
                                  ),
                              style: const TextStyle(fontSize: 12),
                            ),
                            onPressed: () async {
                              final now = DateTime.now();
                              final initialDate =
                                  subReminder != null
                                      ? DateTime.fromMillisecondsSinceEpoch(
                                        subReminder!,
                                      )
                                      : (subDeadline ?? now);
                              final firstDate = DateTime(
                                now.year,
                                now.month,
                                now.day,
                              );
                              final lastDate = DateTime(now.year + 5);
                              final pickedDate = await showDatePicker(
                                context: context,
                                initialDate:
                                    initialDate.isBefore(firstDate)
                                        ? firstDate
                                        : initialDate,
                                firstDate: firstDate,
                                lastDate: lastDate,
                              );
                              if (pickedDate == null || !context.mounted) {
                                return;
                              }
                              final initialTime =
                                  subReminder != null
                                      ? TimeOfDay.fromDateTime(
                                        DateTime.fromMillisecondsSinceEpoch(
                                          subReminder!,
                                        ),
                                      )
                                      : const TimeOfDay(hour: 9, minute: 0);
                              final pickedTime = await showTimePicker(
                                context: context,
                                initialTime: initialTime,
                              );
                              if (pickedTime == null || !context.mounted) {
                                return;
                              }
                              final combined = DateTime(
                                pickedDate.year,
                                pickedDate.month,
                                pickedDate.day,
                                pickedTime.hour,
                                pickedTime.minute,
                              );
                              if (combined.isBefore(DateTime.now())) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      t['reminderPastError'] ??
                                          'Reminder time cannot be in the past',
                                    ),
                                  ),
                                );
                                return;
                              }
                              setDialogState(() {
                                subReminder = combined.millisecondsSinceEpoch;
                              });
                              await showReminderAccessFeedback(context);
                            },
                          ),
                        ),
                        if (subReminder != null)
                          IconButton(
                            key: const ValueKey('subtask-reminder-clear'),
                            tooltip: t['clearReminder'] ?? 'Clear Reminder',
                            icon: const Icon(Icons.close, size: 18),
                            visualDensity: VisualDensity.compact,
                            onPressed:
                                () => setDialogState(() => subReminder = null),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  key: const ValueKey('subtask-cancel-btn'),
                  onPressed: () => Navigator.pop(dialogCtx, false),
                  child: Text(t['cancel']!),
                ),
                FilledButton(
                  key: const ValueKey('subtask-save-btn'),
                  onPressed: () {
                    if (titleController.text.trim().isEmpty) return;
                    Navigator.pop(dialogCtx, true);
                  },
                  child: Text(t['save'] ?? 'Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (mounted && saved == true) {
      final newTitle = titleController.text.trim();
      final notesRaw = notesController.text.trim();
      final newNotes = notesRaw.isEmpty ? null : notesController.text;
      final newDeadline =
          subDeadline == null
              ? null
              : DateTime(
                subDeadline!.year,
                subDeadline!.month,
                subDeadline!.day,
                23,
                59,
                59,
              ).millisecondsSinceEpoch;
      setState(() {
        sub.title = newTitle;
        sub.notesMarkdown = newNotes;
        sub.deadline = newDeadline;
        sub.reminderAt = subReminder;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<Store>();
    final t = store.t;
    final theme = Theme.of(context);
    final d = _deadline;
    final dirty = _isDirty;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onDirtyChanged?.call(dirty);
    });

    return PopScope(
      canPop: !_isDirty || _forceClose,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final discard = await _confirmDiscard(context);
        if (discard && mounted) {
          _forceClose = true;
          _close();
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusScope.of(context).unfocus(),
        child: Container(
          decoration:
              widget.isSidebar
                  ? BoxDecoration(
                    color: theme.colorScheme.surface,
                    border: Border(
                      left: BorderSide(color: theme.dividerColor, width: 1),
                    ),
                  )
                  : null,
          child: SafeArea(
            top: false,
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.enter, control: true):
                    _save,
                const SingleActivator(LogicalKeyboardKey.enter, meta: true):
                    _save,
              },
              child: Column(
                children: [
                  const ReminderFailureBanner(),
                  // Top Header / Toolbar
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            t['editTask']!,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: t['deleteTaskTitle']!,
                          icon: Icon(
                            Icons.delete_outline,
                            color: theme.colorScheme.error,
                          ),
                          onPressed: _confirmDeleteTask,
                        ),
                        const SizedBox(width: 4),
                        FilledButton(
                          key: const ValueKey('save-task'),
                          style: FilledButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                          ),
                          onPressed: _save,
                          child: Text(t['save'] ?? t['confirm']!),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: t['close']!,
                          icon: const Icon(Icons.close),
                          onPressed: _attemptClose,
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  // Scrollable Body
                  Expanded(
                    child: SingleChildScrollView(
                      controller: widget.scrollController,
                      padding: EdgeInsets.fromLTRB(
                        16,
                        12,
                        16,
                        MediaQuery.viewInsetsOf(context).bottom + 20,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Task Title Field (multiline, Enter newline, Ctrl+Enter save)
                          TextField(
                            key: const ValueKey('edit-title'),
                            controller: _title,
                            autofocus: !widget.isSidebar,
                            minLines: 1,
                            maxLines: 5,
                            keyboardType: TextInputType.multiline,
                            textInputAction: TextInputAction.newline,
                            decoration: InputDecoration(
                              labelText: t['editTask']!,
                              alignLabelWithHint: true,
                              border: const OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Task Notes Field (multiline plain text editor)
                          TextField(
                            key: const ValueKey('edit-notes'),
                            controller: _notes,
                            minLines: 2,
                            maxLines: 6,
                            keyboardType: TextInputType.multiline,
                            textInputAction: TextInputAction.newline,
                            decoration: InputDecoration(
                              labelText: t['notes'] ?? 'Notes',
                              hintText: t['notesHint'] ?? 'Add notes…',
                              alignLabelWithHint: true,
                              border: const OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Deadline row
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  icon: const Icon(
                                    Icons.calendar_month,
                                    size: 18,
                                  ),
                                  label: Text(
                                    d == null
                                        ? t['setDeadline']!
                                        : '${d.year}-${d.month}-${d.day}',
                                  ),
                                  onPressed: _pickDate,
                                ),
                              ),
                              if (d != null)
                                IconButton(
                                  tooltip: t['cancel']!,
                                  onPressed:
                                      () => setState(() => _deadline = null),
                                  icon: const Icon(Icons.clear),
                                ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // Reminder row
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  key: const ValueKey('edit-reminder-btn'),
                                  icon: Icon(
                                    _reminderAt == null
                                        ? Icons.notifications_none
                                        : Icons.notifications_active,
                                    size: 18,
                                    color:
                                        _reminderAt == null
                                            ? null
                                            : theme.colorScheme.primary,
                                  ),
                                  label: Text(
                                    _reminderAt == null
                                        ? (t['setReminder'] ?? 'Set Reminder')
                                        : _formatDateTime(
                                          DateTime.fromMillisecondsSinceEpoch(
                                            _reminderAt!,
                                          ),
                                        ),
                                  ),
                                  onPressed: _pickReminderDateTime,
                                ),
                              ),
                              if (_reminderAt != null)
                                IconButton(
                                  key: const ValueKey('clear-reminder-btn'),
                                  tooltip:
                                      t['clearReminder'] ?? 'Clear Reminder',
                                  onPressed:
                                      () => setState(() => _reminderAt = null),
                                  icon: const Icon(Icons.clear),
                                ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          // Quick reminder chips
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              if (d != null) ...[
                                ActionChip(
                                  key: const ValueKey(
                                    'reminder-quick-due-date',
                                  ),
                                  label: Text(
                                    t['reminderOnDueDate'] ??
                                        'On due date 09:00',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                  onPressed: () {
                                    final due9 = DateTime(
                                      d.year,
                                      d.month,
                                      d.day,
                                      9,
                                      0,
                                    );
                                    if (due9.isAfter(DateTime.now())) {
                                      setState(
                                        () =>
                                            _reminderAt =
                                                due9.millisecondsSinceEpoch,
                                      );
                                      _notifyReminderAccess();
                                    } else {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            t['reminderPastError'] ??
                                                'Reminder time cannot be in the past',
                                          ),
                                        ),
                                      );
                                    }
                                  },
                                ),
                              ],
                              ActionChip(
                                key: const ValueKey('reminder-quick-today-18'),
                                label: Text(
                                  t['reminderToday18'] ?? 'Today 18:00',
                                  style: const TextStyle(fontSize: 11),
                                ),
                                onPressed: () {
                                  final now = DateTime.now();
                                  final today18 = DateTime(
                                    now.year,
                                    now.month,
                                    now.day,
                                    18,
                                    0,
                                  );
                                  if (today18.isAfter(now)) {
                                    setState(
                                      () =>
                                          _reminderAt =
                                              today18.millisecondsSinceEpoch,
                                    );
                                    _notifyReminderAccess();
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          t['reminderPastError'] ??
                                              'Reminder time cannot be in the past',
                                        ),
                                      ),
                                    );
                                  }
                                },
                              ),
                              ActionChip(
                                key: const ValueKey(
                                  'reminder-quick-tomorrow-9',
                                ),
                                label: Text(
                                  t['reminderTomorrow9'] ?? 'Tomorrow 09:00',
                                  style: const TextStyle(fontSize: 11),
                                ),
                                onPressed: () {
                                  final now = DateTime.now();
                                  final tom9 = DateTime(
                                    now.year,
                                    now.month,
                                    now.day + 1,
                                    9,
                                    0,
                                  );
                                  setState(
                                    () =>
                                        _reminderAt =
                                            tom9.millisecondsSinceEpoch,
                                  );
                                  _notifyReminderAccess();
                                },
                              ),
                              ActionChip(
                                key: const ValueKey('reminder-quick-custom'),
                                label: Text(
                                  t['customReminder'] ?? 'Custom',
                                  style: const TextStyle(fontSize: 11),
                                ),
                                onPressed: _pickReminderDateTime,
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // Quadrant selection chips
                          Text(
                            t['quadrant']!,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              for (final q in allQuadrants)
                                ChoiceChip(
                                  label: Text(t['q$q']!),
                                  selected: _quadrant == q,
                                  onSelected: (_) {
                                    setState(() {
                                      final oldQ = _quadrant;
                                      _quadrant = q;
                                      if (isUrgentQuadrant(oldQ) !=
                                          isUrgentQuadrant(q)) {
                                        _urgencyMode = UrgencyMode.manual;
                                      }
                                    });
                                  },
                                ),
                            ],
                          ),
                          if (_urgencyMode == UrgencyMode.manual) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surfaceContainerHighest
                                    .withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.tune,
                                    size: 16,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      t['urgencyManualNotice'] ??
                                          'Urgency manually set',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color:
                                                theme
                                                    .colorScheme
                                                    .onSurfaceVariant,
                                          ),
                                    ),
                                  ),
                                  TextButton(
                                    key: const ValueKey('reset-urgency-auto'),
                                    style: TextButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                      ),
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        _urgencyMode = UrgencyMode.auto;
                                        final store = context.read<Store>();
                                        final d = _deadline;
                                        if (d != null) {
                                          final dMs =
                                              DateTime(
                                                d.year,
                                                d.month,
                                                d.day,
                                                23,
                                                59,
                                                59,
                                              ).millisecondsSinceEpoch;
                                          if (isDeadlineUrgent(
                                            dMs,
                                            store.settings.urgencyThresholdDays,
                                          )) {
                                            _quadrant = promoteToUrgent(
                                              _quadrant,
                                            );
                                          }
                                        }
                                      });
                                    },
                                    child: Text(
                                      t['resetUrgencyAuto'] ?? 'Restore Auto',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),

                          // Long-Term switch & AI Decompose button
                          Row(
                            children: [
                              Expanded(
                                child: SwitchListTile(
                                  title: Text(
                                    t['longTermTask'] ?? 'Long-Term Task',
                                    style: theme.textTheme.bodyMedium,
                                  ),
                                  value: _isLongTerm,
                                  onChanged:
                                      (v) => setState(() => _isLongTerm = v),
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                ),
                              ),
                              OutlinedButton.icon(
                                icon: const Icon(Icons.auto_awesome, size: 16),
                                label: Text(t['decomposeTask'] ?? 'AI'),
                                onPressed: () {
                                  showBatchDecomposeSheet(context, [
                                    widget.task,
                                  ], autoStart: true);
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // Subtasks Section
                          Row(
                            children: [
                              Text(
                                '${t['subtasks'] ?? 'Subtasks'} (${_subtasks.where((s) => s.completed).length}/${_subtasks.length})',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),

                          // Subtasks list
                          for (final sub in _subtasks)
                            Container(
                              key: ValueKey('detail-subtask-${sub.id}'),
                              margin: const EdgeInsets.fromLTRB(16, 2, 0, 2),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              decoration:
                                  sub.id == widget.highlightSubtaskId
                                      ? BoxDecoration(
                                        color: theme
                                            .colorScheme
                                            .primaryContainer
                                            .withValues(alpha: 0.35),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: theme.colorScheme.primary
                                              .withValues(alpha: 0.5),
                                        ),
                                      )
                                      : null,
                              child: Row(
                                children: [
                                  TaskHierarchyCheckbox(
                                    hitTargetKey: ValueKey(
                                      'detail-subtask-check-${sub.id}',
                                    ),
                                    visualKey: ValueKey(
                                      'detail-subtask-check-${sub.id}-visual',
                                    ),
                                    level: TaskHierarchyLevel.child,
                                    value: sub.completed,
                                    semanticsLabel: t['markTaskComplete'],
                                    onChanged: (v) {
                                      setState(() => sub.completed = v);
                                    },
                                  ),
                                  Expanded(
                                    child: InkWell(
                                      key: ValueKey('subtask-item-${sub.id}'),
                                      borderRadius: BorderRadius.circular(4),
                                      onTap: () => _editSubtask(sub),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 6,
                                          horizontal: 4,
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              sub.title,
                                              style: TextStyle(
                                                fontSize:
                                                    TaskHierarchyStyle
                                                        .childTitleSize,
                                                decoration:
                                                    sub.completed
                                                        ? TextDecoration
                                                            .lineThrough
                                                        : null,
                                                color:
                                                    sub.completed
                                                        ? theme.disabledColor
                                                        : theme
                                                            .colorScheme
                                                            .onSurface,
                                              ),
                                            ),
                                            if (sub.notesMarkdown != null &&
                                                sub.notesMarkdown!
                                                    .trim()
                                                    .isNotEmpty) ...[
                                              const SizedBox(height: 2),
                                              Text(
                                                sub.notesMarkdown!,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: theme.textTheme.bodySmall
                                                    ?.copyWith(
                                                      color:
                                                          theme
                                                              .colorScheme
                                                              .onSurfaceVariant,
                                                      fontSize: 11,
                                                    ),
                                              ),
                                            ],
                                            if (sub.deadline != null) ...[
                                              const SizedBox(height: 2),
                                              Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    Icons.calendar_month,
                                                    size: 11,
                                                    color: theme
                                                        .colorScheme
                                                        .onSurface
                                                        .withValues(alpha: 0.5),
                                                  ),
                                                  const SizedBox(width: 3),
                                                  Text(
                                                    _formatDate(
                                                      DateTime.fromMillisecondsSinceEpoch(
                                                        sub.deadline!,
                                                      ),
                                                    ),
                                                    style: theme
                                                        .textTheme
                                                        .labelSmall
                                                        ?.copyWith(
                                                          color: theme
                                                              .colorScheme
                                                              .onSurface
                                                              .withValues(
                                                                alpha: 0.6,
                                                              ),
                                                          fontSize: 11,
                                                        ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                            if (sub.reminderAt != null) ...[
                                              const SizedBox(height: 2),
                                              Row(
                                                children: [
                                                  Icon(
                                                    Icons
                                                        .notifications_active_outlined,
                                                    size: 11,
                                                    color:
                                                        theme
                                                            .colorScheme
                                                            .primary,
                                                  ),
                                                  const SizedBox(width: 3),
                                                  Text(
                                                    _formatDateTime(
                                                      DateTime.fromMillisecondsSinceEpoch(
                                                        sub.reminderAt!,
                                                      ),
                                                    ),
                                                    style: theme
                                                        .textTheme
                                                        .labelSmall
                                                        ?.copyWith(
                                                          color:
                                                              theme
                                                                  .colorScheme
                                                                  .primary,
                                                          fontSize: 11,
                                                        ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.close, size: 16),
                                    onPressed: () {
                                      setState(() => _subtasks.remove(sub));
                                    },
                                    tooltip: t['delete'] ?? 'Delete',
                                  ),
                                ],
                              ),
                            ),

                          // Add Subtask Row
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _newSubtaskController,
                                  decoration: InputDecoration(
                                    hintText: t['addSubtask']!,
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    border: const OutlineInputBorder(),
                                  ),
                                  onSubmitted: (_) => _addSubtask(),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton.filledTonal(
                                icon: const Icon(Icons.add),
                                onPressed: _addSubtask,
                                tooltip: t['addSubtask']!,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
