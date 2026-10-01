import 'package:flutter/material.dart';

import 'device_time_zone.dart';

/// Asks for the IANA zone the schedule should display in.
///
/// Used both when the device zone cannot be used and when the user wants to
/// look at another zone. Returns the chosen id, or null when cancelled.
Future<String?> showScheduleZonePicker(
  BuildContext context, {
  required Map<String, String> t,
  String? current,
  String? deviceIanaId,
  String? deviceIdentity,
  DeviceTimeZoneProblem? problem,
  int limit = 60,
}) => showDialog<String>(
  context: context,
  builder: (_) => _ScheduleZoneDialog(
    t: t,
    current: current,
    deviceIanaId: deviceIanaId,
    deviceIdentity: deviceIdentity,
    problem: problem,
    limit: limit,
  ),
);

/// The message that explains why the user has to choose at all.
String scheduleZoneProblemText(
  Map<String, String> t, {
  DeviceTimeZoneProblem? problem,
  String? identity,
}) {
  final reported = identity ?? '';
  return switch (problem) {
    DeviceTimeZoneProblem.unmapped =>
      (t['scheduleZoneUnmapped'] ?? '').replaceAll('{zone}', reported),
    DeviceTimeZoneProblem.invalid =>
      (t['scheduleZoneInvalid'] ?? '').replaceAll('{zone}', reported),
    DeviceTimeZoneProblem.unavailable => t['scheduleZoneUnavailable'] ?? '',
    null => t['scheduleZoneHint'] ?? '',
  };
}

class _ScheduleZoneDialog extends StatefulWidget {
  const _ScheduleZoneDialog({
    required this.t,
    required this.current,
    required this.deviceIanaId,
    required this.deviceIdentity,
    required this.problem,
    required this.limit,
  });

  final Map<String, String> t;
  final String? current;
  final String? deviceIanaId;
  final String? deviceIdentity;
  final DeviceTimeZoneProblem? problem;
  final int limit;

  @override
  State<_ScheduleZoneDialog> createState() => _ScheduleZoneDialogState();
}

class _ScheduleZoneDialogState extends State<_ScheduleZoneDialog> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final theme = Theme.of(context);
    final options = searchScheduleZoneIds(_query, limit: widget.limit);
    final typed = _query.trim();
    final typedIsValid =
        typed.isNotEmpty && isKnownIanaTimeZone(typed) && !options.contains(typed);
    return AlertDialog(
      title: Text(t['scheduleZoneChoose'] ?? 'Choose time zone'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              scheduleZoneProblemText(
                t,
                problem: widget.problem,
                identity: widget.deviceIdentity,
              ),
              key: const ValueKey('schedule-zone-problem'),
            ),
            if (widget.problem != null) ...[
              const SizedBox(height: 8),
              Text(
                t['scheduleZoneHint'] ?? '',
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (widget.deviceIanaId != null) ...[
              const SizedBox(height: 4),
              TextButton.icon(
                key: const ValueKey('schedule-zone-use-device'),
                onPressed: () => Navigator.pop(context, widget.deviceIanaId),
                icon: const Icon(Icons.phone_android),
                label: Text(
                  '${t['scheduleZoneUseDevice'] ?? ''}: ${widget.deviceIanaId}',
                ),
              ),
            ],
            TextField(
              key: const ValueKey('schedule-zone-search'),
              controller: _search,
              autofocus: false,
              decoration: InputDecoration(
                labelText: t['scheduleZoneSearch'] ?? 'Search IANA time zones',
                isDense: true,
                border: const OutlineInputBorder(),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
            if (typed.isNotEmpty && !typedIsValid && options.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  t['scheduleEditorZoneError'] ??
                      'Enter a recognized IANA time zone.',
                  key: const ValueKey('schedule-zone-error'),
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView(
                key: const ValueKey('schedule-zone-options'),
                shrinkWrap: true,
                children: [
                  if (typedIsValid)
                    ListTile(
                      key: const ValueKey('schedule-zone-typed'),
                      leading: const Icon(Icons.keyboard),
                      title: Text(typed),
                      onTap: () => Navigator.pop(context, typed),
                    ),
                  for (final id in options)
                    ListTile(
                      key: ValueKey('schedule-zone-option-$id'),
                      selected: id == widget.current,
                      title: Text(id),
                      onTap: () => Navigator.pop(context, id),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('schedule-zone-cancel'),
          onPressed: () => Navigator.pop(context),
          child: Text(t['cancel'] ?? 'Cancel'),
        ),
      ],
    );
  }
}
