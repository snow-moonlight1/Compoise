import 'package:flutter/material.dart';

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
  bool _taskAssociation = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _taskAssociation = s.kind == ScheduleItemKind.timeBlock || s.taskId != null;
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
  }

  Future<void> _chooseAssociation() async {
    final values = _taskAssociation
        ? [
            for (final task in s.store.tasks)
              (
                task.id,
                '${task.title} · ${s.store.boards.where((b) => b.id == task.boardId).firstOrNull?.name ?? t['unknownBoard']} · Q${task.quadrant}',
              ),
          ]
        : [for (final board in s.store.boards) (board.id, board.name)];
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          t[_taskAssociation ? 'scheduleEditorParent' : 'scheduleBoardFilter']!,
        ),
        scrollable: true,
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (values.isEmpty) Text(t['scheduleEditorNoAssociation']!),
              for (final value in values)
                ListTile(
                  key: ValueKey('schedule-editor-association-${value.$1}'),
                  title: Text(value.$2),
                  onTap: () => Navigator.pop(context, value.$1),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t['close']!),
          ),
        ],
      ),
    );
    if (selected == null || !mounted) return;
    _changed(() {
      s.taskId = _taskAssociation ? selected : null;
      s.boardId = _taskAssociation ? null : selected;
    });
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(header: true, child: Text(label)),
        TextFormField(
          key: ValueKey(
            'schedule-editor-$name-date${editable ? '' : '-fixed-${input.date}'}',
          ),
          initialValue: input.date,
          readOnly: !editable,
          enabled: !_busy && !s.accepted,
          decoration: InputDecoration(
            labelText: '$label · ${t['scheduleEditorDate']}',
            hintText: 'YYYY-MM-DD',
          ),
          onChanged: (value) => _changed(() {
            input.date = value;
            input.offset = null;
          }),
        ),
        TextFormField(
          key: ValueKey(
            'schedule-editor-$name-time${editable ? '' : '-fixed-${input.time}'}',
          ),
          initialValue: input.time,
          readOnly: !editable,
          enabled: !_busy && !s.accepted,
          decoration: InputDecoration(
            labelText: '$label · ${t['scheduleEditorTime']}',
            hintText: 'HH:mm[:ss.SSS]',
          ),
          onChanged: (value) => _changed(() {
            input.time = value;
            input.offset = null;
          }),
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
    final association = _taskAssociation
        ? s.store.tasks.where((task) => task.id == s.taskId).firstOrNull?.title
        : s.store.boards
              .where((board) => board.id == s.boardId)
              .firstOrNull
              ?.name;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t[s.kind == ScheduleItemKind.timeBlock
              ? 'scheduleTimeBlock'
              : 'scheduleEvent']!,
        ),
        if (s.kind == ScheduleItemKind.event && s.mode == ScheduleEditMode.edit)
          TextFormField(
            key: const ValueKey('schedule-editor-title'),
            initialValue: s.title,
            decoration: InputDecoration(labelText: t['scheduleEditorTitle']),
            onChanged: (value) => _changed(() => s.title = value),
          ),
        if (s.kind == ScheduleItemKind.event && s.mode == ScheduleEditMode.edit)
          Wrap(
            spacing: 8,
            children: [
              for (final task in [true, false])
                ChoiceChip(
                  key: ValueKey(
                    'schedule-editor-associate-${task ? 'task' : 'board'}',
                  ),
                  label: Text(
                    t[task ? 'scheduleEditorParent' : 'scheduleEditorBoard']!,
                  ),
                  selected: _taskAssociation == task,
                  onSelected: (_) => _changed(() {
                    _taskAssociation = task;
                    s.taskId = null;
                    s.boardId = null;
                  }),
                ),
            ],
          ),
        TextButton(
          key: const ValueKey('schedule-editor-choose-association'),
          onPressed: s.mode == ScheduleEditMode.edit
              ? _chooseAssociation
              : null,
          child: Text(
            '${t['scheduleEditorAssociation']}: ${association ?? t['scheduleEditorChoose']}',
          ),
        ),
        _references(s.taskId),
        TextFormField(
          key: const ValueKey('schedule-editor-zone'),
          initialValue: s.timeZoneId,
          readOnly: s.mode != ScheduleEditMode.edit,
          decoration: InputDecoration(labelText: t['scheduleEditorZone']),
          onChanged: (value) => _changed(() {
            s.timeZoneId = value;
            s.start.offset = null;
            s.end.offset = null;
          }),
        ),
        _endpoint('start', s.start, s.startEditable),
        _endpoint('end', end, s.endEditable),
        if (s.mode == ScheduleEditMode.move)
          Text(t['scheduleEditorKeepDuration']!),
      ],
    );
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
        canPop: !_busy,
        child: AlertDialog(
          key: const ValueKey('schedule-editor'),
          scrollable: true,
          title: Text(
            t[s.original == null
                ? 'scheduleEditorNew'
                : switch (s.mode) {
                    ScheduleEditMode.edit => 'scheduleEditorEdit',
                    ScheduleEditMode.move => 'scheduleEditorMove',
                    ScheduleEditMode.resizeStart => 'scheduleEditorResizeStart',
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
                  child: _review == null ? _form() : _summary(),
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
              onPressed: _busy ? null : () => Navigator.pop(context, false),
              child: Text(t[s.accepted ? 'close' : 'cancel']!),
            ),
            if (s.accepted)
              TextButton(
                key: const ValueKey('schedule-editor-retry'),
                onPressed: _busy || blocked ? null : () => _submit(retry: true),
                child: Text(t['scheduleEditorRetry']!),
              )
            else if (_review == null)
              FilledButton(
                key: const ValueKey('schedule-editor-review'),
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
                      }),
                child: Text(t['scheduleEditorModify']!),
              ),
              FilledButton(
                key: const ValueKey('schedule-editor-save'),
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
        );
      },
    );
  }
}
