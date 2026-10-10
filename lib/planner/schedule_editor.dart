import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../schedule_item.dart';
import '../schedule_time.dart';
import '../widgets/schedule_layout.dart';
import 'schedule_edit_session.dart';

Future<bool?> showScheduleEditor(
  BuildContext context,
  ScheduleEditSession session,
) => showDialog<bool>(
  context: context,
  barrierDismissible: false,
  builder: (_) => ScheduleEditor(session: session),
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
  ScheduleReview? _review;
  bool _allowOverlap = false;
  bool _busy = false;
  String? _error;
  late final String _initialDraft;
  bool _initialProposal = false;
  bool _confirmingLeave = false;
  final _reviewFocus = FocusNode();
  final _saveFocus = FocusNode();
  final _overlapFocus = FocusNode();
  final _retryFocus = FocusNode();
  final _cancelFocus = FocusNode();

  String get _draft => jsonEncode([
    s.title,
    s.taskId,
    s.boardId,
    s.timeZoneId,
    s.start.date,
    s.start.time,
    s.start.offset?.inMinutes,
    s.end.date,
    s.end.time,
    s.end.offset?.inMinutes,
  ]);

  bool get _hasDraft =>
      !s.accepted && (_initialProposal || _draft != _initialDraft);

  @override
  void initState() {
    super.initState();
    _initialDraft = _draft;
    if (s.original != null && s.mode != ScheduleEditMode.edit) {
      try {
        _initialProposal =
            jsonEncode(s.review().item.toJson()) !=
            jsonEncode(s.original!.toJson());
      } on ScheduleTimeException {
        _initialProposal = true;
      } on FormatException {
        _initialProposal = true;
      }
    }
  }

  @override
  void dispose() {
    _reviewFocus.dispose();
    _saveFocus.dispose();
    _overlapFocus.dispose();
    _retryFocus.dispose();
    _cancelFocus.dispose();
    super.dispose();
  }

  void _focusAfterBuild(FocusNode node) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !node.canRequestFocus) return;
      node.requestFocus();
      final focusContext = node.context;
      if (focusContext != null) {
        Scrollable.ensureVisible(
          focusContext,
          alignment: 0.15,
          duration: const Duration(milliseconds: 150),
        );
      }
    });
  }

  Future<void> _confirmLeave() async {
    if (_busy || _confirmingLeave || !_hasDraft) return;
    _confirmingLeave = true;
    final discard = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              Navigator.pop(context, false),
        },
        child: AlertDialog(
          key: const ValueKey('schedule-editor-discard-confirm'),
          scrollable: true,
          title: Text(t['discardChangesTitle']!),
          content: Text(t['discardChangesConfirm']!),
          actions: [
            TextButton(
              key: const ValueKey('schedule-editor-keep-editing'),
              autofocus: true,
              onPressed: () => Navigator.pop(context, false),
              child: Text(t['scheduleEditorKeepEditing']!),
            ),
            TextButton(
              key: const ValueKey('schedule-editor-discard'),
              onPressed: () => Navigator.pop(context, true),
              child: Text(t['discard']!),
            ),
          ],
        ),
      ),
    );
    _confirmingLeave = false;
    if (discard == true && mounted && !_busy && !s.accepted) {
      Navigator.pop(context, false);
    }
  }

  void _changed(VoidCallback update) => setState(() {
    update();
    _review = null;
    _allowOverlap = false;
    _error = null;
  });

  String _timeError(ScheduleTimeException error) =>
      t[switch (error.reason) {
        ScheduleTimeError.gap => 'scheduleEditorGap',
        ScheduleTimeError.fold ||
        ScheduleTimeError.offset => 'scheduleEditorFold',
        ScheduleTimeError.unknownZone => 'scheduleEditorZoneError',
        _ => 'scheduleEditorInputError',
      }]!;

  void _prepare() {
    try {
      if (s.outdated) {
        setState(() => _error = t['scheduleEditorStale']);
        return;
      }
      setState(() {
        _review = s.review();
        _allowOverlap = false;
        _error = null;
      });
      _focusAfterBuild(_review!.overlaps.isEmpty ? _saveFocus : _overlapFocus);
    } on ScheduleTimeException catch (error) {
      setState(() => _error = _timeError(error));
    } on FormatException {
      setState(() => _error = t['scheduleEditorInvalid']);
    }
  }

  Future<void> _submit({bool retry = false}) async {
    if (_busy) return;
    setState(() => _busy = true);
    final result = retry
        ? await s.retry()
        : await s.submit(_review!, allowOverlap: _allowOverlap);
    if (!mounted) return;
    if (result == ScheduleSubmitResult.saved) {
      Navigator.pop(context, true);
      return;
    }
    setState(() {
      _busy = false;
      _error =
          t[switch (result) {
            ScheduleSubmitResult.unsaved => 'scheduleEditorUnsaved',
            ScheduleSubmitResult.stale => 'scheduleEditorStale',
            ScheduleSubmitResult.recovery => 'scheduleRecovery',
            ScheduleSubmitResult.reviewChanged => 'scheduleEditorReviewChanged',
            _ => 'scheduleEditorInvalid',
          }];
      if (result == ScheduleSubmitResult.reviewChanged) {
        _review = null;
        _allowOverlap = false;
      }
    });
    _focusAfterBuild(
      result == ScheduleSubmitResult.unsaved ? _retryFocus : _cancelFocus,
    );
  }

  String _associationLabel(ScheduleItem item) {
    final task = s.store.tasks
        .where((task) => task.id == item.taskId)
        .firstOrNull;
    final board = s.store.boards
        .where((board) => board.id == (task?.boardId ?? item.boardId))
        .firstOrNull;
    return [
      if (task != null)
        '${t['scheduleTask']}: ${task.title} · Q${task.quadrant}',
      board?.name ?? t['unknownBoard']!,
    ].join(' · ');
  }

  DateTime? _parsedDate(String value) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
    if (match == null) return null;
    final year = int.parse(match[1]!);
    final month = int.parse(match[2]!);
    final day = int.parse(match[3]!);
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    final date = DateTime(year, month, day);
    if (date.year != year || date.month != month || date.day != day) {
      return null;
    }
    return date;
  }

  TimeOfDay _parsedTime(String value) {
    final match = RegExp(r'^(\d{2}):(\d{2})').firstMatch(value);
    if (match == null) return const TimeOfDay(hour: 9, minute: 0);
    final hour = int.parse(match[1]!);
    final minute = int.parse(match[2]!);
    if (hour > 23 || minute > 59) return const TimeOfDay(hour: 9, minute: 0);
    return TimeOfDay(hour: hour, minute: minute);
  }

  String _two(int value) => value.toString().padLeft(2, '0');

  Widget _pickerFrame(BuildContext context, Widget? child) {
    // The Material picker sizes itself for a 1.1 text scale and then overflows
    // when the page scale is larger. Keep the page scale everywhere else.
    final scaler = MediaQuery.textScalerOf(
      context,
    ).clamp(maxScaleFactor: 1.1);
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

  Future<void> _pickDate(ScheduleEndpointInput input) async {
    final first = DateTime(1, 1, 1);
    final last = DateTime(9999, 12, 31);
    var initial = _parsedDate(input.date) ?? DateTime(2026, 1, 1);
    if (initial.isBefore(first)) initial = first;
    if (initial.isAfter(last)) initial = last;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
      builder: _pickerFrame,
    );
    if (picked == null) return;
    _changed(() {
      input.date =
          '${picked.year.toString().padLeft(4, '0')}-${_two(picked.month)}-${_two(picked.day)}';
      input.offset = null;
    });
  }

  Future<void> _pickTime(ScheduleEndpointInput input) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _parsedTime(input.time),
      builder: _pickerFrame,
    );
    if (picked == null) return;
    _changed(() {
      input.time = '${_two(picked.hour)}:${_two(picked.minute)}';
      input.offset = null;
    });
  }

  Widget _endpoint(String name, ScheduleEndpointInput input, bool editable) {
    final label = t[name == 'start' ? 'scheduleStart' : 'scheduleEnd']!;
    List<ScheduleWallCandidate> candidates = [];
    String? error;
    try {
      candidates = input.candidates(s.timeZoneId);
      if (candidates.isEmpty) error = t['scheduleEditorGap'];
    } on ScheduleTimeException {
      // Incomplete input is explained when the user asks to review.
    }
    final dateText = input.date.isEmpty ? t['schedulePickDate']! : input.date;
    final timeText = input.time.isEmpty ? t['schedulePickTime']! : input.time;
    final enabled = editable && !_busy && !s.accepted;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(header: true, child: Text(label)),
        const SizedBox(height: 12),
        Text(t['scheduleEditorDate']!),
        const SizedBox(height: 4),
        if (editable)
          OutlinedButton(
            key: ValueKey('schedule-editor-$name-date'),
            onPressed: enabled ? () => _pickDate(input) : null,
            child: Text(dateText),
          )
        else
          Text(
            key: ValueKey('schedule-editor-$name-date-fixed-${input.date}'),
            dateText,
          ),
        const SizedBox(height: 12),
        Text(t['scheduleEditorTime']!),
        const SizedBox(height: 4),
        if (editable)
          OutlinedButton(
            key: ValueKey('schedule-editor-$name-time'),
            onPressed: enabled ? () => _pickTime(input) : null,
            child: Text(timeText),
          )
        else
          Text(
            key: ValueKey('schedule-editor-$name-time-fixed-${input.time}'),
            timeText,
          ),
        if (error != null) Text(error),
        if (candidates.length > 1 && editable) ...[
          Text(t['scheduleEditorFold']!),
          for (final candidate in candidates)
            RadioListTile<Duration>(
              key: ValueKey(
                'schedule-editor-$name-offset-${candidate.offset.inMinutes}',
              ),
              title: Text(
                '${scheduleOffsetLabel(candidate.offset)} · ${candidate.abbreviation}',
              ),
              value: candidate.offset,
              groupValue: input.offset,
              onChanged: _busy || s.accepted
                  ? null
                  : (value) => _changed(() => input.offset = value),
            ),
        ],
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _references(String? taskId) {
    final task = s.store.tasks.where((task) => task.id == taskId).firstOrNull;
    if (task == null) return const SizedBox.shrink();
    String day(int ms) {
      final date = DateTime.fromMillisecondsSinceEpoch(ms);
      return scheduleDateLabel(
        ScheduleCivilDate(date.year, date.month, date.day),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(t['scheduleEditorReference']!),
        Text(
          '${t['plannedDate']}: ${task.plannedDate == null ? '—' : day(task.plannedDate!)}',
        ),
        Text(
          '${t['deadline']}: ${task.deadline == null ? '—' : day(task.deadline!)}',
        ),
      ],
    );
  }

  Widget _form() {
    var end = s.end;
    if (s.mode == ScheduleEditMode.move) {
      try {
        end = ScheduleEndpointInput.fromInstant(s.resolvedEnd, s.timeZoneId);
      } on ScheduleTimeException {
        end = ScheduleEndpointInput(date: '', time: '');
      }
    }
    final link = _linkLine();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (s.kind == ScheduleItemKind.event && s.mode == ScheduleEditMode.edit)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: TextFormField(
              key: const ValueKey('schedule-editor-title'),
              initialValue: s.title,
              decoration: InputDecoration(labelText: t['scheduleEditorTitle']),
              onChanged: (value) => _changed(() => s.title = value),
            ),
          ),
        if (link != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(link, style: Theme.of(context).textTheme.bodyMedium),
          ),
        if (s.taskId != null) _references(s.taskId),
        _endpoint('start', s.start, s.startEditable),
        _endpoint('end', end, s.endEditable),
        if (s.mode == ScheduleEditMode.move)
          Text(t['scheduleEditorKeepDuration']!),
      ],
    );
  }

  /// Existing records and a drop that already names a task show that link as
  /// text. A new event keeps its board on the session and does not ask again.
  String? _linkLine() {
    final taskId = s.taskId;
    if (taskId != null) {
      final task = s.store.tasks
          .where((task) => task.id == taskId)
          .firstOrNull;
      if (task == null) return null;
      return '${t['scheduleTask']}: ${task.title}';
    }
    if (s.original == null || s.boardId == null) return null;
    final board = s.store.boards
        .where((board) => board.id == s.boardId)
        .firstOrNull;
    return '${t['scheduleBoardShort']}: ${board?.name ?? t['unknownBoard']}';
  }

  Widget _summary() {
    final item = _review!.item;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(t['scheduleEditorReview']!),
        Text(
          item.title ??
              s.store.tasks
                  .where((task) => task.id == item.taskId)
                  .firstOrNull
                  ?.title ??
              '',
        ),
        Text(_associationLabel(item)),
        Text('${t['scheduleEditorZone']}: ${item.timeZoneId}'),
        Text(
          '${t['scheduleStart']}: ${scheduleInstantLabel(item.startAt, item.timeZoneId)}',
        ),
        Text(
          '${t['scheduleEnd']}: ${scheduleInstantLabel(item.endAt, item.timeZoneId)}',
        ),
        Text(
          '${t['scheduleElapsed']}: ${Duration(milliseconds: item.endAt - item.startAt)}',
        ),
        _references(item.taskId),
        if (_review!.overlaps.isNotEmpty) ...[
          Text(t['scheduleEditorOverlap']!),
          for (final overlap in _review!.overlaps)
            Text(
              '${overlap.title ?? s.store.tasks.where((task) => task.id == overlap.taskId).firstOrNull?.title} · '
              '${_associationLabel(overlap)} · '
              '${scheduleInstantLabel(overlap.startAt, s.timeZoneId)} – '
              '${scheduleInstantLabel(overlap.endAt, s.timeZoneId)}',
            ),
          CheckboxListTile(
            key: const ValueKey('schedule-editor-allow-overlap'),
            focusNode: _overlapFocus,
            value: _allowOverlap,
            title: Text(t['scheduleEditorAllowOverlap']!),
            onChanged: _busy || s.accepted
                ? null
                : (value) => setState(() => _allowOverlap = value!),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: s.store,
    builder: (context, _) {
      final blocked =
          s.outdated || s.store.hasStartupRecovery || !s.store.ready;
      final message = s.outdated
          ? t['scheduleEditorStale']
          : s.store.hasStartupRecovery
          ? t['scheduleRecovery']
          : _error;
      return PopScope(
        canPop: !_busy && !_hasDraft,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _confirmLeave();
        },
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () =>
                Navigator.maybePop(context),
          },
          child: AlertDialog(
            key: const ValueKey('schedule-editor'),
            scrollable: true,
            title: Text(
              t[s.original == null
                  ? 'scheduleEditorNew'
                  : switch (s.mode) {
                      ScheduleEditMode.edit => 'scheduleEditorEdit',
                      ScheduleEditMode.move => 'scheduleEditorMove',
                      ScheduleEditMode.resizeStart =>
                        'scheduleEditorResizeStart',
                      ScheduleEditMode.resizeEnd => 'scheduleEditorResizeEnd',
                    }]!,
            ),
            content: SizedBox(
              width: 480,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AbsorbPointer(
                    absorbing: _busy || s.accepted || blocked,
                    child: ExcludeFocus(
                      excluding: _busy || s.accepted || blocked,
                      child: _review == null ? _form() : _summary(),
                    ),
                  ),
                  if (message != null)
                    Semantics(liveRegion: true, child: Text(message)),
                  if (_busy) Text(t['scheduleEditorSaving']!),
                ],
              ),
            ),
            actions: [
              TextButton(
                key: const ValueKey('schedule-editor-cancel'),
                focusNode: _cancelFocus,
                onPressed: _busy ? null : () => Navigator.pop(context, false),
                child: Text(t[s.accepted ? 'close' : 'cancel']!),
              ),
              if (s.accepted)
                TextButton(
                  key: const ValueKey('schedule-editor-retry'),
                  focusNode: _retryFocus,
                  onPressed: _busy || blocked
                      ? null
                      : () => _submit(retry: true),
                  child: Text(t['scheduleEditorRetry']!),
                )
              else if (_review == null)
                FilledButton(
                  key: const ValueKey('schedule-editor-review'),
                  focusNode: _reviewFocus,
                  autofocus: true,
                  onPressed: _busy || blocked ? null : _prepare,
                  child: Text(t['scheduleEditorReview']!),
                )
              else ...[
                TextButton(
                  key: const ValueKey('schedule-editor-modify'),
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                          _review = null;
                          _allowOverlap = false;
                          _focusAfterBuild(_reviewFocus);
                        }),
                  child: Text(t['scheduleEditorModify']!),
                ),
                FilledButton(
                  key: const ValueKey('schedule-editor-save'),
                  focusNode: _saveFocus,
                  onPressed:
                      _busy ||
                          blocked ||
                          (_review!.overlaps.isNotEmpty && !_allowOverlap)
                      ? null
                      : () => _submit(),
                  child: Text(t['scheduleEditorSave']!),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}

Future<bool?> showScheduleDelete(
  BuildContext context,
  ScheduleEditSession session,
) => showDialog<bool>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _ScheduleDelete(session),
);

class _ScheduleDelete extends StatefulWidget {
  const _ScheduleDelete(this.session);
  final ScheduleEditSession session;
  @override
  State<_ScheduleDelete> createState() => _ScheduleDeleteState();
}

class _ScheduleDeleteState extends State<_ScheduleDelete> {
  bool _busy = false;
  String? _error;
  Future<void> _submit() async {
    if (_busy) return;
    setState(() => _busy = true);
    final s = widget.session;
    final result = s.accepted ? await s.retry() : await s.delete();
    if (!mounted) return;
    if (result == ScheduleSubmitResult.saved) {
      Navigator.pop(context, true);
      return;
    }
    setState(() {
      _busy = false;
      _error =
          s.store.t[result == ScheduleSubmitResult.unsaved
              ? 'scheduleEditorUnsaved'
              : result == ScheduleSubmitResult.recovery
              ? 'scheduleRecovery'
              : 'scheduleEditorStale'];
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    return ListenableBuilder(
      listenable: s.store,
      builder: (context, _) {
        final t = s.store.t;
        final blocked =
            s.outdated || s.store.hasStartupRecovery || !s.store.ready;
        return PopScope(
          canPop: !_busy,
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.escape): () =>
                  Navigator.maybePop(context),
            },
            child: AlertDialog(
              key: const ValueKey('schedule-delete-confirm'),
              scrollable: true,
              title: Text(t['scheduleEditorDelete']!),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t['scheduleEditorDeleteHint']!),
                  Text(
                    s.original!.title ??
                        s.store.tasks
                            .where((task) => task.id == s.original!.taskId)
                            .firstOrNull
                            ?.title ??
                        '',
                  ),
                  Text(
                    scheduleInstantLabel(
                      s.original!.startAt,
                      s.original!.timeZoneId,
                    ),
                  ),
                  Text(
                    scheduleInstantLabel(
                      s.original!.endAt,
                      s.original!.timeZoneId,
                    ),
                  ),
                  if (blocked || _error != null)
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        blocked
                            ? t[s.store.hasStartupRecovery
                                  ? 'scheduleRecovery'
                                  : 'scheduleEditorStale']!
                            : _error!,
                      ),
                    ),
                  if (_busy) Text(t['scheduleEditorSaving']!),
                ],
              ),
              actions: [
                TextButton(
                  key: const ValueKey('schedule-delete-cancel'),
                  autofocus: true,
                  onPressed: _busy ? null : () => Navigator.pop(context, false),
                  child: Text(t[s.accepted ? 'close' : 'cancel']!),
                ),
                FilledButton(
                  key: const ValueKey('schedule-delete-submit'),
                  onPressed: _busy || blocked ? null : _submit,
                  child: Text(
                    t[s.accepted
                        ? 'scheduleEditorRetry'
                        : 'scheduleEditorDelete']!,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
