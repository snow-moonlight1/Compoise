import 'package:flutter/material.dart';

import '../schedule_item.dart';
import '../schedule_time.dart';
import '../theme.dart';
import '../ui/platform_ui_policy.dart';
import 'planner_labels.dart';
import 'schedule_edit_session.dart';

/// Opens the plain edit form: title, date, start and end. No review step and
/// no overlap confirmation; overlapping items simply sit side by side.
Future<bool?> showScheduleEditor(
  BuildContext context,
  ScheduleEditSession session,
) {
  // One centered dialog for new and edit, on phones and desktop alike.
  final width = MediaQuery.sizeOf(context).width;
  return showDialog<bool>(
    context: context,
    builder: (_) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: (width - 48).clamp(0.0, 420.0).toDouble(),
        ),
        child: ScheduleEditor(session: session),
      ),
    ),
  );
}

/// One centered confirmation (cancel / delete). Returns true to delete.
Future<bool?> showScheduleDeleteConfirm(
  BuildContext context,
  Map<String, String> t,
) => showDialog<bool>(
  context: context,
  builder: (context) => AlertDialog(
    key: const ValueKey('schedule-delete-confirm'),
    content: Text(t['scheduleDeleteConfirm']!),
    actions: [
      TextButton(
        key: const ValueKey('schedule-delete-cancel'),
        autofocus: true,
        onPressed: () => Navigator.pop(context, false),
        child: Text(t['cancel']!),
      ),
      FilledButton(
        key: const ValueKey('schedule-delete-submit'),
        onPressed: () => Navigator.pop(context, true),
        child: Text(t['delete']!),
      ),
    ],
  ),
);

class ScheduleEditor extends StatefulWidget {
  const ScheduleEditor({super.key, required this.session});
  final ScheduleEditSession session;
  @override
  State<ScheduleEditor> createState() => _ScheduleEditorState();
}

class _ScheduleEditorState extends State<ScheduleEditor> {
  ScheduleEditSession get s => widget.session;
  Map<String, String> get t => s.store.t;
  bool _busy = false;
  String? _error;

  String _two(int v) => v.toString().padLeft(2, '0');

  DateTime? _parsedDate(String value) {
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
    if (m == null) return null;
    return DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
  }

  TimeOfDay _parsedTime(String value) {
    final m = RegExp(r'^(\d{2}):(\d{2})').firstMatch(value);
    if (m == null) return const TimeOfDay(hour: 9, minute: 0);
    return TimeOfDay(hour: int.parse(m[1]!), minute: int.parse(m[2]!));
  }

  Widget _frame(BuildContext context, Widget? child) {
    final scaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.1);
    return Localizations.override(
      context: context,
      locale: Locale(s.store.settings.language.name),
      child: MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(alwaysUse24HourFormat: true, textScaler: scaler),
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }

  void _touch(VoidCallback update) => setState(() {
    update();
    _error = null;
  });

  Future<void> _pickDate(ScheduleEndpointInput input) async {
    final initial = _parsedDate(input.date) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1),
      lastDate: DateTime(9999, 12, 31),
      builder: _frame,
    );
    if (picked == null) return;
    _touch(() {
      final shiftEnd = identical(input, s.start) && s.end.date == s.start.date;
      input.date =
          '${picked.year.toString().padLeft(4, '0')}-'
          '${_two(picked.month)}-${_two(picked.day)}';
      input.offset = null;
      if (shiftEnd) {
        s.end.date = input.date;
        s.end.offset = null;
      }
    });
  }

  Future<void> _pickTime(ScheduleEndpointInput input) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _parsedTime(input.time),
      builder: _frame,
    );
    if (picked == null) return;
    _touch(() {
      final oldStart = _parsedTime(s.start.time);
      final oldEnd = _parsedTime(s.end.time);
      final keep =
          oldEnd.hour * 60 +
          oldEnd.minute -
          (oldStart.hour * 60 + oldStart.minute);
      input.time = '${_two(picked.hour)}:${_two(picked.minute)}';
      input.offset = null;
      // Moving the start keeps the length, like a calendar app does.
      if (identical(input, s.start) && s.end.time.isNotEmpty && keep > 0) {
        final total = picked.hour * 60 + picked.minute + keep;
        if (total < 24 * 60 && s.start.date == s.end.date) {
          s.end.time = '${_two(total ~/ 60)}:${_two(total % 60)}';
          s.end.offset = null;
        }
      }
    });
  }

  Future<void> _save() async {
    if (_busy) return;
    if (s.kind == ScheduleItemKind.event && s.title.trim().isEmpty) {
      setState(() => _error = t['scheduleEditorTitleRequired']);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    String? failure;
    try {
      final start = s.resolvedStart;
      final end = s.resolvedEnd;
      if (end <= start) {
        failure = t['scheduleEditorEndBeforeStart'];
      } else {
        final result = s.accepted ? await s.retry() : await s.commit();
        if (!mounted) return;
        if (result == ScheduleSubmitResult.saved) {
          Navigator.pop(context, true);
          return;
        }
        failure =
            t[switch (result) {
              ScheduleSubmitResult.unsaved => 'scheduleEditorUnsaved',
              ScheduleSubmitResult.stale => 'scheduleEditorStale',
              ScheduleSubmitResult.recovery => 'scheduleRecovery',
              _ => 'scheduleEditorInvalid',
            }];
      }
    } on ScheduleTimeException catch (error) {
      failure =
          t[error.reason == ScheduleTimeError.gap
              ? 'scheduleEditorGap'
              : 'scheduleEditorInputError'];
    } on FormatException {
      failure = t['scheduleEditorInvalid'];
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = failure;
    });
  }

  String _dateText(ScheduleEndpointInput input) {
    final d = _parsedDate(input.date);
    if (d == null) return t['schedulePickDate']!;
    return plannerDayTitle(
      ScheduleCivilDate(d.year, d.month, d.day),
      s.store.settings.language,
      t,
    );
  }

  Widget _picker(Key key, String text, VoidCallback? onTap, {IconData? icon}) =>
      OutlinedButton.icon(
        key: key,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, PlatformUiPolicy.minActionSize),
        ),
        onPressed: _busy ? null : onTap,
        icon: Icon(icon ?? Icons.schedule, size: 18),
        label: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 260),
          child: FittedBox(fit: BoxFit.scaleDown, child: Text(text)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final neu = NeumorphicSkin.maybeOf(context) != null;
    final isEvent = s.kind == ScheduleItemKind.event;
    final taskTitle = s.store.tasks
        .where((task) => task.id == s.taskId)
        .map((task) => task.title)
        .firstOrNull;
    final sameDay = s.start.date == s.end.date;
    return SafeArea(
      child: SingleChildScrollView(
        key: const ValueKey('schedule-editor'),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t[s.original == null
                  ? 'scheduleEditorNew'
                  : 'scheduleEditorEdit']!,
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            if (isEvent)
              TextFormField(
                key: const ValueKey('schedule-editor-title'),
                initialValue: s.title,
                enabled: !_busy,
                textInputAction: TextInputAction.done,
                // Neumorphic reserves a label band above the text, which pushed
                // the placeholder up. Its title shows as a centred hint.
                textAlignVertical: neu ? TextAlignVertical.center : null,
                decoration: neu
                    ? InputDecoration(
                        hintText: t['scheduleEditorTitle'],
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 18,
                        ),
                      )
                    : InputDecoration(labelText: t['scheduleEditorTitle']),
                onChanged: (value) => _touch(() => s.title = value),
              )
            else if (taskTitle != null)
              Text(taskTitle, style: theme.textTheme.titleMedium),
            if (isEvent && taskTitle != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '${t['scheduleTask']}: $taskTitle',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 16),
            _picker(
              const ValueKey('schedule-editor-start-date'),
              _dateText(s.start),
              () => _pickDate(s.start),
              icon: Icons.event,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _picker(
                  const ValueKey('schedule-editor-start-time'),
                  s.start.time.isEmpty
                      ? t['schedulePickTime']!
                      : '${t['scheduleStart']} ${s.start.time.substring(0, 5)}',
                  () => _pickTime(s.start),
                ),
                _picker(
                  const ValueKey('schedule-editor-end-time'),
                  s.end.time.isEmpty
                      ? t['schedulePickTime']!
                      : '${t['scheduleEnd']} ${s.end.time.substring(0, 5)}',
                  () => _pickTime(s.end),
                ),
              ],
            ),
            if (!sameDay) ...[
              const SizedBox(height: 8),
              _picker(
                const ValueKey('schedule-editor-end-date'),
                '${t['scheduleEnd']} ${_dateText(s.end)}',
                () => _pickDate(s.end),
                icon: Icons.event,
              ),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    _error!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              ),
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton(
                  key: const ValueKey('schedule-editor-cancel'),
                  onPressed: _busy ? null : () => Navigator.pop(context, false),
                  child: Text(t['cancel']!),
                ),
                FilledButton(
                  key: const ValueKey('schedule-editor-save'),
                  onPressed: _busy ? null : _save,
                  child: Text(t['save']!),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
