/// Shared deadline and reminder editing pieces: one civil-day rule set, one
/// picker flow and one day-chip row. Presentation stays with each surface so
/// the composer, the detail editor and the subtask dialog keep their own
/// affordance while agreeing on what a chosen day or moment means.
library;

import 'package:flutter/material.dart';

import '../calendar_dates.dart';
import 'reminder_access.dart';

class TaskTimeSelection {
  const TaskTimeSelection(this.deadline, this.reminderAt);
  final DateTime? deadline;
  final int? reminderAt;
}

/// Edits both time properties in isolation. Closing or cancelling the dialog
/// returns null, so the caller's larger task draft remains untouched.
Future<TaskTimeSelection?> showTaskTimeEditor(
  BuildContext context, {
  required Map<String, String> t,
  DateTime? deadline,
  int? reminderAt,
}) => showDialog<TaskTimeSelection>(
  context: context,
  builder: (_) =>
      _TaskTimeDialog(t: t, deadline: deadline, reminderAt: reminderAt),
);

class _TaskTimeDialog extends StatefulWidget {
  const _TaskTimeDialog({
    required this.t,
    required this.deadline,
    required this.reminderAt,
  });
  final Map<String, String> t;
  final DateTime? deadline;
  final int? reminderAt;

  @override
  State<_TaskTimeDialog> createState() => _TaskTimeDialogState();
}

class _TaskTimeDialogState extends State<_TaskTimeDialog> {
  late DateTime? _deadline = widget.deadline;
  late int? _reminderAt = widget.reminderAt;

  Future<void> _preset(DateTime moment) async {
    await applyPresetReminderMoment(
      context,
      t: widget.t,
      moment: moment,
      onPicked: (value) {
        if (mounted) setState(() => _reminderAt = value);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final now = DateTime.now();
    final tomorrow = addCivilDays(now, 1);
    return AlertDialog(
      title: Text(t['timePanel']!),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t['deadline']!,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              DeadlineDayChips(
                t: t,
                keyPrefix: 'deadline',
                selected: _deadline,
                onChanged: (value) => setState(() => _deadline = value),
              ),
              const SizedBox(height: 24),
              Text(
                t['reminder']!,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              if (_reminderAt != null) ...[
                const SizedBox(height: 8),
                Text(formatCivilDateTimeMs(_reminderAt!)),
              ],
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (_deadline != null)
                    ActionChip(
                      key: const ValueKey('reminder-quick-due-date'),
                      label: Text(t['reminderOnDueDate']!),
                      onPressed: () => _preset(
                        DateTime(
                          _deadline!.year,
                          _deadline!.month,
                          _deadline!.day,
                          9,
                        ),
                      ),
                    ),
                  ActionChip(
                    key: const ValueKey('reminder-quick-today-18'),
                    label: Text(t['reminderToday18']!),
                    onPressed: () =>
                        _preset(DateTime(now.year, now.month, now.day, 18)),
                  ),
                  ActionChip(
                    key: const ValueKey('reminder-quick-tomorrow-9'),
                    label: Text(t['reminderTomorrow9']!),
                    onPressed: () => _preset(
                      DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 9),
                    ),
                  ),
                  ActionChip(
                    key: const ValueKey('reminder-quick-custom'),
                    label: Text(t['customReminder']!),
                    onPressed: () => pickReminderMoment(
                      context,
                      t: t,
                      reminderAt: _reminderAt,
                      deadline: _deadline,
                      onPicked: (value) {
                        if (mounted) setState(() => _reminderAt = value);
                      },
                    ),
                  ),
                  if (_reminderAt != null)
                    ActionChip(
                      key: const ValueKey('clear-reminder-btn'),
                      label: Text(t['clearReminder']!),
                      onPressed: () => setState(() => _reminderAt = null),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t['cancel']!),
        ),
        FilledButton(
          key: const ValueKey('time-confirm'),
          onPressed: () =>
              Navigator.pop(context, TaskTimeSelection(_deadline, _reminderAt)),
          child: Text(t['confirm']!),
        ),
      ],
    );
  }
}

/// Two instants on the same local year/month/day. A reminder keeps its exact
/// moment; a deadline is a civil day, so this is the comparison that counts.
bool isSameCivilDay(DateTime? a, DateTime? b) {
  if (a == null || b == null) return false;
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

/// Today's local calendar day at midnight.
DateTime civilToday() => civilDate(DateTime.now());

/// Deadline instant for a chosen day: end of that civil day.
int? endOfCivilDayMs(DateTime? day) => day == null
    ? null
    : DateTime(day.year, day.month, day.day, 23, 59, 59).millisecondsSinceEpoch;

/// Whether [candidate] is later than the end of the parent's [parentDeadline]
/// day. Shared by every editor that shows the after-parent warning.
bool isAfterParentDay(DateTime? candidate, DateTime? parentDeadline) =>
    parentDeadline != null &&
    candidate != null &&
    candidate.isAfter(
      DateTime(
        parentDeadline.year,
        parentDeadline.month,
        parentDeadline.day,
        23,
        59,
        59,
      ),
    );

String formatCivilDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String formatCivilDateTime(DateTime d) =>
    '${formatCivilDate(d)} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

String formatCivilDateMs(int ms) =>
    formatCivilDate(DateTime.fromMillisecondsSinceEpoch(ms));

String formatCivilDateTimeMs(int ms) =>
    formatCivilDateTime(DateTime.fromMillisecondsSinceEpoch(ms));

/// Opens the deadline dialog inside [deadlinePickerWindow]. Returns the chosen
/// civil day, or null when the user cancelled; a cancelled dialog never
/// rewrites a stored deadline, however far out of range it is.
Future<DateTime?> pickDeadlineDay(
  BuildContext context, {
  DateTime? selected,
}) async {
  final window = deadlinePickerWindow(
    now: DateTime.now(),
    selected: selected ?? civilToday(),
  );
  final picked = await showDatePicker(
    context: context,
    initialDate: window.initial,
    firstDate: window.first,
    lastDate: window.last,
  );
  if (picked == null || !context.mounted) return null;
  return civilDate(picked);
}

/// Runs the reminder date and time dialogs inside [reminderPickerWindow] and
/// applies the result through [onPicked] before reporting the permission
/// outcome. A past moment or a cancelled dialog leaves the stored reminder
/// untouched.
Future<void> pickReminderMoment(
  BuildContext context, {
  required Map<String, String> t,
  required ValueChanged<int> onPicked,
  int? reminderAt,
  DateTime? deadline,
}) async {
  final window = reminderPickerWindow(
    now: DateTime.now(),
    reminderAt: reminderAt,
    deadline: deadline,
  );
  final pickedDate = await showDatePicker(
    context: context,
    initialDate: window.initial,
    firstDate: window.first,
    lastDate: window.last,
  );
  if (pickedDate == null || !context.mounted) return;

  final pickedTime = await showTimePicker(
    context: context,
    initialTime: reminderAt == null
        ? const TimeOfDay(hour: 9, minute: 0)
        : TimeOfDay.fromDateTime(
            DateTime.fromMillisecondsSinceEpoch(reminderAt),
          ),
  );
  if (pickedTime == null || !context.mounted) return;

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
          t['reminderPastError'] ?? 'Reminder time cannot be in the past',
        ),
      ),
    );
    return;
  }

  onPicked(combined.millisecondsSinceEpoch);
  await showReminderAccessFeedback(context);
}

/// Preset reminders (due date 09:00, today 18:00, tomorrow 09:00) follow the
/// same past-moment rule and permission feedback as the picker.
Future<void> applyPresetReminderMoment(
  BuildContext context, {
  required Map<String, String> t,
  required ValueChanged<int> onPicked,
  required DateTime moment,
}) async {
  if (!moment.isAfter(DateTime.now())) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          t['reminderPastError'] ?? 'Reminder time cannot be in the past',
        ),
      ),
    );
    return;
  }
  onPicked(moment.millisecondsSinceEpoch);
  await showReminderAccessFeedback(context);
}

/// Today / tomorrow / custom / clear chips for a deadline day. [keyPrefix]
/// keeps each surface's existing test keys; [note] stays with the caller
/// because the hints differ per editor.
class DeadlineDayChips extends StatelessWidget {
  const DeadlineDayChips({
    super.key,
    required this.t,
    required this.selected,
    required this.onChanged,
    required this.keyPrefix,
    this.enabled = true,
  });

  final Map<String, String> t;
  final DateTime? selected;
  final ValueChanged<DateTime?> onChanged;
  final String keyPrefix;
  final bool enabled;

  Key _key(String suffix) => ValueKey('$keyPrefix-$suffix');

  @override
  Widget build(BuildContext context) {
    final today = civilToday();
    final tomorrow = addCivilDays(today, 1);
    final isCustom =
        selected != null &&
        !isSameCivilDay(selected, today) &&
        !isSameCivilDay(selected, tomorrow);

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 4,
      children: [
        ChoiceChip(
          key: _key('today'),
          avatar: const Icon(Icons.today, size: 16),
          label: Text(t['today']!),
          selected: isSameCivilDay(selected, today),
          onSelected: enabled
              ? (value) => onChanged(value ? today : null)
              : null,
        ),
        ChoiceChip(
          key: _key('tomorrow'),
          avatar: const Icon(Icons.event, size: 16),
          label: Text(t['tomorrow']!),
          selected: isSameCivilDay(selected, tomorrow),
          onSelected: enabled
              ? (value) => onChanged(value ? tomorrow : null)
              : null,
        ),
        ChoiceChip(
          key: _key('custom'),
          avatar: const Icon(Icons.calendar_month, size: 16),
          label: Text(isCustom ? formatCivilDate(selected!) : t['pickDate']!),
          selected: isCustom,
          onSelected: enabled
              ? (_) async {
                  final picked = await pickDeadlineDay(
                    context,
                    selected: selected ?? today,
                  );
                  if (picked != null) onChanged(picked);
                }
              : null,
        ),
        if (selected != null)
          IconButton(
            key: _key('clear'),
            tooltip: t['clearDate']!,
            icon: const Icon(Icons.close, size: 18),
            visualDensity: VisualDensity.compact,
            onPressed: enabled ? () => onChanged(null) : null,
          ),
      ],
    );
  }
}
