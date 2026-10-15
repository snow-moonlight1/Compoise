/// Shared deadline and reminder editing. Cancelling either picker keeps the draft.
library;

import 'package:flutter/material.dart';
import '../calendar_dates.dart';
import 'app_notice.dart';
import 'reminder_access.dart';

class TaskTimeSelection {
  const TaskTimeSelection({this.deadline, this.reminderAt});
  final DateTime? deadline;
  final int? reminderAt;
}

Future<TaskTimeSelection?> showTaskTimeEditor(
  BuildContext context, {
  required Map<String, String> t,
  DateTime? deadline,
  int? reminderAt,
}) {
  final editor = _TaskTimeEditor(
    t: t,
    deadline: deadline,
    reminderAt: reminderAt,
  );
  return showDialog<TaskTimeSelection>(
    context: context,
    builder: (_) => editor,
  );
}

class _TaskTimeEditor extends StatefulWidget {
  const _TaskTimeEditor({
    required this.t,
    required this.deadline,
    required this.reminderAt,
  });
  final Map<String, String> t;
  final DateTime? deadline;
  final int? reminderAt;
  @override
  State<_TaskTimeEditor> createState() => _TaskTimeEditorState();
}

class _TaskTimeEditorState extends State<_TaskTimeEditor> {
  late DateTime? _deadline = widget.deadline;
  late int? _reminderAt = widget.reminderAt;

  Widget _field(
    String label,
    String key,
    String? value,
    VoidCallback pick,
    VoidCallback clear,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(label, style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              key: ValueKey(key),
              onPressed: pick,
              icon: const Icon(Icons.event_outlined, size: 18),
              label: Text(value ?? widget.t['pickDateTime']!),
            ),
          ),
          if (value != null)
            IconButton(
              key: ValueKey(
                key == 'deadline-custom'
                    ? 'deadline-clear'
                    : 'clear-reminder-btn',
              ),
              tooltip: widget.t['clearDate'],
              icon: const Icon(Icons.close),
              onPressed: clear,
            ),
        ],
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _field(
          t['deadline']!,
          'deadline-custom',
          _deadline == null ? null : formatCivilDateTime(_deadline!),
          () async {
            final value = await pickDeadlineMoment(
              context,
              selected: _deadline,
            );
            if (mounted && value != null) setState(() => _deadline = value);
          },
          () => setState(() => _deadline = null),
        ),
        const SizedBox(height: 24),
        _field(
          t['reminder']!,
          'reminder-quick-custom',
          _reminderAt == null ? null : formatCivilDateTimeMs(_reminderAt!),
          () async {
            await pickReminderMoment(
              context,
              t: t,
              reminderAt: _reminderAt,
              deadline: _deadline,
              onPicked: (value) {
                if (mounted) setState(() => _reminderAt = value);
              },
            );
          },
          () => setState(() => _reminderAt = null),
        ),
      ],
    );
    void confirm() => Navigator.pop(
      context,
      TaskTimeSelection(deadline: _deadline, reminderAt: _reminderAt),
    );
    final save = FilledButton(
      key: const ValueKey('time-confirm'),
      onPressed: confirm,
      child: Text(t['confirm']!),
    );
    return AlertDialog(
      title: Text(t['timePanel']!),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(child: content),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t['cancel']!),
        ),
        save,
      ],
    );
  }
}

DateTime civilToday() => civilDate(DateTime.now());

// An imported/AI date without a clock time can use day end. Interactive editors
// instead retain the chosen instant, including unchanged imported seconds.
int? endOfCivilDayMs(DateTime? day) => day == null
    ? null
    : DateTime(day.year, day.month, day.day, 23, 59, 59).millisecondsSinceEpoch;

bool isAfterParentDay(DateTime? candidate, DateTime? parentDeadline) =>
    parentDeadline != null &&
    candidate != null &&
    candidate.isAfter(parentDeadline);

String formatCivilDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
String formatCivilDateTime(DateTime d) =>
    '${formatCivilDate(d)} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
String formatCivilDateMs(int ms) =>
    formatCivilDate(DateTime.fromMillisecondsSinceEpoch(ms));
String formatCivilDateTimeMs(int ms) =>
    formatCivilDateTime(DateTime.fromMillisecondsSinceEpoch(ms));

Future<DateTime?> _pickMoment(
  BuildContext context,
  DatePickerWindow window,
  DateTime initial,
) async {
  final day = await showDatePicker(
    context: context,
    initialDate: window.initial,
    firstDate: window.first,
    lastDate: window.last,
  );
  if (day == null || !context.mounted) return null;
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(initial),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
      child: child!,
    ),
  );
  if (time == null || !context.mounted) return null;
  return DateTime(day.year, day.month, day.day, time.hour, time.minute);
}

Future<DateTime?> pickDeadlineMoment(
  BuildContext context, {
  DateTime? selected,
}) {
  final now = DateTime.now();
  return _pickMoment(
    context,
    deadlinePickerWindow(now: now, selected: selected),
    selected ?? now,
  );
}

Future<void> pickReminderMoment(
  BuildContext context, {
  required Map<String, String> t,
  required ValueChanged<int> onPicked,
  int? reminderAt,
  DateTime? deadline,
}) async {
  final now = DateTime.now();
  final selected = reminderAt == null
      ? now
      : DateTime.fromMillisecondsSinceEpoch(reminderAt);
  final picked = await _pickMoment(
    context,
    reminderPickerWindow(now: now, reminderAt: reminderAt, deadline: deadline),
    selected,
  );
  if (picked == null || !context.mounted) return;
  if (!picked.isAfter(DateTime.now())) {
    showAppNotice(context, t['reminderPastError']!);
    return;
  }
  onPicked(picked.millisecondsSinceEpoch);
  await showReminderAccessFeedback(context);
}
