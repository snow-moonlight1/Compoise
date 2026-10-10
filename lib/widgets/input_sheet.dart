import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../ai_service.dart';
import '../models.dart';
import '../planned_policy.dart';
import '../storage.dart';
import '../ui/platform_ui_policy.dart';
import 'batch_decompose_sheet.dart';
import 'date_edit_fields.dart';
import 'task_edit_draft.dart';
import 'task_steps_composer.dart';

class InputSheet extends StatefulWidget {
  final InputModePref initialMode;
  final bool embedded;
  final ValueChanged<bool>? onDirtyChanged;

  /// Preset by the planner's quadrant add button. Home leaves both null.
  final int? quadrant;
  final String? boardId;
  const InputSheet({
    super.key,
    required this.initialMode,
    this.embedded = false,
    this.onDirtyChanged,
    this.quadrant,
    this.boardId,
  });
  @override
  State<InputSheet> createState() => _InputSheetState();
}

class _InputSheetState extends State<InputSheet> {
  late InputModePref _mode = widget.initialMode;
  final _controller = TextEditingController();
  final _parentTitle = TextEditingController();
  final _inputFocus = FocusNode();
  final _stepsKey = GlobalKey<TaskStepsComposerState>();
  bool _batch = false;
  bool _parentTitleExplicit = false;
  AICancellation? _request;
  bool _busy = false;
  bool _closed = false;
  bool _pendingManualSave = false;
  bool _reportedDirty = false;
  String? _error;
  DateTime? _selectedDeadline;
  DateTime? _selectedPlannedDate;
  int? _selectedReminderAt;

  Task _place(Task task) {
    final quadrant = widget.quadrant;
    if (quadrant != null) task.quadrant = quadrant;
    final board = widget.boardId;
    if (board != null && board.isNotEmpty) task.boardId = board;
    return task;
  }

  bool get _isDirty =>
      (_mode == InputModePref.single && !_batch
          ? (_stepsKey.currentState?.text.isNotEmpty ?? false)
          : _controller.text.isNotEmpty) ||
      _parentTitle.text.isNotEmpty ||
      _batch ||
      _mode != widget.initialMode ||
      _selectedDeadline != null ||
      _selectedPlannedDate != null ||
      _selectedReminderAt != null;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_reportDirty);
    _parentTitle.addListener(_reportDirty);
  }

  void _reportDirty() {
    final dirty = _isDirty;
    if (_reportedDirty == dirty) return;
    _reportedDirty = dirty;
    widget.onDirtyChanged?.call(dirty);
  }

  @override
  void dispose() {
    _request?.cancel();
    _controller.removeListener(_reportDirty);
    _controller.dispose();
    _parentTitle.removeListener(_reportDirty);
    _parentTitle.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.watch<Store>().t;
    final policy = PlatformUiPolicy.of(context);
    final steps = _stepsKey.currentState;
    final showParentTitle =
        _mode == InputModePref.single &&
        !_batch &&
        (steps?.hasMultipleRows == true || _parentTitleExplicit);
    final firstStep = steps?.nonEmptySteps.firstOrNull ?? '';
    final suggestedTitle = firstStep.length > 24
        ? '${firstStep.substring(0, 24)}…'
        : firstStep;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _reportDirty();
    });
    final insets = widget.embedded
        ? 0.0
        : MediaQuery.viewInsetsOf(context).bottom;
    final fields = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          children: [
            for (final mode in InputModePref.values)
              ChoiceChip(
                label: Text(
                  t[mode == InputModePref.single ? 'modeManual' : 'modeAI']!,
                ),
                selected: _mode == mode && !_batch,
                onSelected: _busy || _pendingManualSave
                    ? null
                    : (_) => _switchMode(mode, false),
              ),
            ChoiceChip(
              key: const ValueKey('batch-mode'),
              label: Text(t['batchIndependent']!),
              selected: _batch,
              onSelected: _busy || _pendingManualSave
                  ? null
                  : (_) => _switchMode(InputModePref.single, true),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_mode == InputModePref.single && !_batch) ...[
          if (showParentTitle) ...[
            TextField(
              key: const ValueKey('parent-title'),
              controller: _parentTitle,
              enabled: !_busy && !_pendingManualSave,
              decoration: InputDecoration(
                labelText: t['parentTitle']!,
                hintText: suggestedTitle,
                helperText: t['parentTitleSuggested']!,
              ),
              onChanged: (_) => setState(() => _parentTitleExplicit = true),
            ),
            const SizedBox(height: 8),
          ],
          Text(
            t['stepsOneTask']!,
            style: Theme.of(context).textTheme.labelMedium,
          ),
          TaskStepsComposer(
            key: _stepsKey,
            t: t,
            enabled: !_busy && !_pendingManualSave,
            onChanged: () {
              if (mounted) setState(() {});
              _reportDirty();
            },
          ),
        ] else ...[
          Text(
            t[_batch ? 'batchIndependentHint' : 'aiInputHint']!,
            style: Theme.of(context).textTheme.labelMedium,
          ),
          TextField(
            key: const ValueKey('task-input'),
            controller: _controller,
            focusNode: _inputFocus,
            onChanged: (_) => setState(() {}),
            readOnly: _busy || _pendingManualSave,
            maxLines: 5,
            minLines: 3,
            autofocus: !widget.embedded,
            decoration: InputDecoration(
              hintText:
                  t[_mode == InputModePref.brainDump
                      ? 'inputPlaceholderAI'
                      : 'inputPlaceholderManual'],
            ),
          ),
        ],
        if (_mode == InputModePref.single &&
            !_batch &&
            (steps?.nonEmptySteps.length ?? 0) > 1)
          Text(
            t['stepCountPreview']!.replaceFirst(
              '{count}',
              '${steps!.nonEmptySteps.length}',
            ),
          ),
        if (_batch && _controller.text.trim().isNotEmpty)
          Text(
            t['batchCountPreview']!.replaceFirst(
              '{count}',
              '${_controller.text.split('\n').where((line) => line.trim().isNotEmpty).length}',
            ),
          ),
        const SizedBox(height: 6),
        if (_mode == InputModePref.brainDump)
          Text(
            t['aiNote']!,
            style: Theme.of(context).textTheme.labelSmall,
            textAlign: TextAlign.center,
          ),
        if (policy.showShortcutHints)
          Text(
            t['shortcutHintWindows'] ?? t['shortcutHint']!,
            style: Theme.of(context).textTheme.labelSmall,
            textAlign: TextAlign.center,
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const ValueKey('input-time-btn'),
          onPressed: _busy || _pendingManualSave ? null : _editTime,
          icon: const Icon(Icons.schedule),
          label: Text(
            _selectedPlannedDate == null &&
                    _selectedDeadline == null &&
                    _selectedReminderAt == null
                ? t['timePanel']!
                : [
                    if (_selectedPlannedDate != null)
                      '${t['plannedDate']}: ${formatCivilDate(_selectedPlannedDate!)}',
                    if (_selectedDeadline != null)
                      '${t['deadline']}: ${formatCivilDate(_selectedDeadline!)}',
                    if (_selectedReminderAt != null)
                      '${t['reminder']}: ${formatCivilDateTimeMs(_selectedReminderAt!)}',
                  ].join(' · '),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
    final submit = FilledButton.icon(
      key: const ValueKey('submit-tasks'),
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
      onPressed: _busy ? null : _submit,
      icon: _busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(
              _mode == InputModePref.brainDump ? Icons.auto_awesome : Icons.add,
            ),
      label: Text(
        _pendingManualSave
            ? t['retrySave']!
            : t[_mode == InputModePref.brainDump
                  ? 'analyzeBtn'
                  : (_batch ? 'batchIndependent' : 'addSingleBtn')]!,
      ),
    );
    final maxHeight = MediaQuery.sizeOf(context).height - insets - 24;
    final body = Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.enter, control: true):
              _submit,
          const SingleActivator(LogicalKeyboardKey.enter, meta: true): _submit,
        },
        child: widget.embedded
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [fields, const SizedBox(height: 12), submit],
              )
            : ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: maxHeight > 200 ? maxHeight : 200,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Flexible(child: SingleChildScrollView(child: fields)),
                    const SizedBox(height: 12),
                    submit,
                  ],
                ),
              ),
      ),
    );
    final content = SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: insets),
        child: body,
      ),
    );
    if (widget.embedded) return content;
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          _closed = true;
          _request?.cancel();
        }
      },
      child: content,
    );
  }

  void _switchMode(InputModePref mode, bool batch) {
    final returningToSteps =
        (_mode != InputModePref.single || _batch) &&
        mode == InputModePref.single &&
        !batch;
    if (_mode == InputModePref.single && !_batch) {
      _controller.text = _stepsKey.currentState?.text ?? '';
    }
    setState(() {
      _mode = mode;
      _batch = batch;
    });
    if (returningToSteps) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _stepsKey.currentState?.setText(_controller.text);
      });
    }
    _reportDirty();
  }

  Future<void> _editTime() async {
    final result = await showTaskTimeEditor(
      context,
      t: context.read<Store>().t,
      deadline: _selectedDeadline,
      reminderAt: _selectedReminderAt,
      supportsPlannedDate: true,
      plannedDate: _selectedPlannedDate,
    );
    if (!mounted) return;
    if (_mode == InputModePref.single && !_batch) {
      _stepsKey.currentState?.restoreFocus();
    } else {
      _inputFocus.requestFocus();
    }
    if (result == null) return;
    setState(() {
      _selectedDeadline = result.deadline;
      _selectedReminderAt = result.reminderAt;
      _selectedPlannedDate = result.plannedDate;
    });
  }

  Future<void> _submit() async {
    if (_pendingManualSave) {
      if (_busy || _closed) return;
      final store = context.read<Store>();
      setState(() => _busy = true);
      final result = await store.retrySave(waitForReminders: false);
      if (!mounted || _closed) return;
      setState(() => _busy = false);
      if (!result.success) {
        setState(
          () => _error = store.persistenceError ?? store.t['storageWriteError'],
        );
        return;
      }
      _finishManualSave();
      return;
    }
    if (hasPendingImeComposition(_controller) ||
        hasPendingImeComposition(_parentTitle) ||
        (_stepsKey.currentState?.hasComposition ?? false)) {
      return;
    }
    final text = _mode == InputModePref.single && !_batch
        ? (_stepsKey.currentState?.text ?? '').trim()
        : _controller.text.trim();
    if (text.isEmpty || _busy || _closed) return;
    final store = context.read<Store>();
    final boardId = widget.boardId ?? store.activeBoardId;
    final config = AIConfig.fromJson(store.aiConfig.toJson());
    final settings = AppSettings.fromJson(store.settings.toJson());
    final inputs = (_mode == InputModePref.single && !_batch
        ? (_stepsKey.currentState?.nonEmptySteps ?? <String>[])
        : text
              .split('\n')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList());

    final deadlineSnapshot = endOfCivilDayMs(_selectedDeadline);
    final plannedSnapshot = plannedDayMs(_selectedPlannedDate);

    if (_mode == InputModePref.single) {
      setState(() {
        _busy = true;
        _error = null;
      });
      if (_batch) {
        store.addTasks([
          for (final line in inputs)
            _place(
              store.newTask(
                line,
                quadrant: widget.quadrant ?? qDo,
                deadline: deadlineSnapshot,
                plannedDate: plannedSnapshot,
              )..reminderAt = _selectedReminderAt,
            ),
        ]);
      } else if (inputs.length == 1 && !_parentTitleExplicit) {
        store.addTasks([
          _place(
            store.newTask(
              inputs.single,
              quadrant: widget.quadrant ?? qDo,
              deadline: deadlineSnapshot,
              plannedDate: plannedSnapshot,
            )..reminderAt = _selectedReminderAt,
          ),
        ]);
      } else {
        final title = _parentTitle.text.trim().isNotEmpty
            ? _parentTitle.text.trim()
            : (inputs.first.length > 24
                  ? '${inputs.first.substring(0, 24)}…'
                  : inputs.first);
        store.addTasks([
          _place(
            store.newTask(
              title,
              quadrant: widget.quadrant ?? qDo,
              deadline: deadlineSnapshot,
              plannedDate: plannedSnapshot,
            )
              ..reminderAt = _selectedReminderAt
              ..subtasks = [
                for (final line in inputs) SubTask(id: newId(), title: line),
              ],
          ),
        ]);
      }
      final result = await store.flush(waitForReminders: false);
      if (!mounted || _closed) return;
      setState(() => _busy = false);
      if (!result.success) {
        setState(() {
          _pendingManualSave = true;
          _error = store.persistenceError ?? store.t['storageWriteError'];
        });
        return;
      }
      _finishManualSave();
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final request = _request = AICancellation();
    final startEpoch = store.boardEpoch(boardId);
    try {
      final results = await store.ai.analyzeTasks(
        inputs: inputs,
        config: config,
        language: settings.language,
        autoDecompose: settings.autoDecomposeAI,
        cancellation: request,
      );
      if (!mounted || _closed) return;
      if (results.isEmpty) throw const AIException('aiInvalidResponse');
      final accepted = <AIAnalysisResult>[];
      for (final result in results) {
        if (result.isGrouped &&
            result.subtasks.isNotEmpty &&
            !settings.autoGroupAI &&
            !settings.suppressGroupPrompt) {
          final keep = await _askGroup(result);
          if (!mounted || _closed) return;
          if (keep == null) return;
          if (!keep) {
            accepted.addAll(
              result.subtasks.map(
                (s) => AIAnalysisResult(title: s, quadrant: result.quadrant),
              ),
            );
            continue;
          }
        }
        accepted.add(result);
      }
      if (!store.boards.any((b) => b.id == boardId) ||
          store.boardEpoch(boardId) != startEpoch) {
        throw const AIException('boardUnavailable');
      }
      final tasks = [
        for (final r in accepted)
          _place(
            r.toTask(
              id: newId(),
              boardId: boardId,
              createdAt: DateTime.now().millisecondsSinceEpoch,
              deadline: deadlineSnapshot,
              plannedDate: plannedSnapshot,
              reminderAt: _selectedReminderAt,
            ),
          ),
      ];
      store.addTasks(tasks);
      _controller.clear();
      setState(() {
        _selectedDeadline = null;
        _selectedPlannedDate = null;
        _selectedReminderAt = null;
      });
      final longTerm =
          !settings.autoDecomposeAI && !settings.suppressLongTermPrompt
          ? tasks.where((task) => task.isLongTerm && !task.hasSubtasks).toList()
          : <Task>[];
      if (!widget.embedded) {
        Navigator.pop(context, longTerm);
      } else if (longTerm.isNotEmpty) {
        await showBatchDecomposeSheet(context, longTerm);
      }
    } catch (error) {
      if (mounted && !_closed && !request.isCancelled) {
        setState(() => _error = aiErrorMessage(error, store.t));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
      if (identical(_request, request)) _request = null;
    }
  }

  void _finishManualSave() {
    _pendingManualSave = false;
    _controller.clear();
    _stepsKey.currentState?.clear();
    _parentTitle.clear();
    setState(() {
      _parentTitleExplicit = false;
      _selectedDeadline = null;
      _selectedPlannedDate = null;
      _selectedReminderAt = null;
      _error = null;
    });
    if (!widget.embedded) Navigator.pop(context);
  }

  Future<bool?> _askGroup(AIAnalysisResult group) {
    final t = context.read<Store>().t;
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        title: Text(t['suggestedGroup']!),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t['suggestedGroupPrompt']!),
            const SizedBox(height: 8),
            Text(group.title, style: Theme.of(context).textTheme.titleMedium),
            ...group.subtasks.map(
              (s) => Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('• $s'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(t['skipGroup']!),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(t['confirmGroupBtn']!),
          ),
        ],
      ),
    );
  }
}
