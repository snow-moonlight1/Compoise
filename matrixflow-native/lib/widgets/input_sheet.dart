import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../ai_service.dart';
import '../models.dart';
import '../storage.dart';
import 'task_detail_panel.dart';

class InputSheet extends StatefulWidget {
  final InputModePref initialMode;
  final bool embedded;
  const InputSheet({
    super.key,
    required this.initialMode,
    this.embedded = false,
  });
  @override
  State<InputSheet> createState() => _InputSheetState();
}

class _InputSheetState extends State<InputSheet> {
  late InputModePref _mode = widget.initialMode;
  final _controller = TextEditingController();
  AICancellation? _request;
  bool _busy = false;
  bool _closed = false;
  String? _error;
  DateTime? _selectedDeadline;
  int? _selectedReminderAt;

  @override
  void dispose() {
    _request?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.watch<Store>().t;
    final content = SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          12,
          16,
          (widget.embedded ? 0 : MediaQuery.viewInsetsOf(context).bottom) + 16,
        ),
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.enter, control: true):
                _submit,
            const SingleActivator(LogicalKeyboardKey.enter, meta: true):
                _submit,
          },
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 8,
                  children: [
                    for (final mode in InputModePref.values)
                      ChoiceChip(
                        label: Text(
                          t[mode == InputModePref.single
                              ? 'modeManual'
                              : 'modeAI']!,
                        ),
                        selected: _mode == mode,
                        onSelected:
                            _busy ? null : (_) => setState(() => _mode = mode),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('task-input'),
                  controller: _controller,
                  readOnly: _busy,
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
                const SizedBox(height: 6),
                if (_mode == InputModePref.brainDump)
                  Text(
                    t['aiNote']!,
                    style: Theme.of(context).textTheme.labelSmall,
                    textAlign: TextAlign.center,
                  ),
                if (widget.embedded)
                  Text(
                    t['shortcutHint']!,
                    style: Theme.of(context).textTheme.labelSmall,
                    textAlign: TextAlign.center,
                  ),
                const SizedBox(height: 8),
                _buildDeadlineRow(context, t),
                const SizedBox(height: 6),
                _buildReminderRow(context, t),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  key: const ValueKey('submit-tasks'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: _busy ? null : _submit,
                  icon:
                      _busy
                          ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                          : Icon(
                            _mode == InputModePref.brainDump
                                ? Icons.auto_awesome
                                : Icons.add,
                          ),
                  label: Text(
                    t[_mode == InputModePref.brainDump
                        ? 'analyzeBtn'
                        : 'addSingleBtn']!,
                  ),
                ),
              ],
            ),
          ),
        ),
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

  bool _isSameDay(DateTime? a, DateTime? b) {
    if (a == null || b == null) return false;
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  Widget _buildDeadlineRow(BuildContext context, Map<String, String> t) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final isCustom =
        _selectedDeadline != null &&
        !_isSameDay(_selectedDeadline, today) &&
        !_isSameDay(_selectedDeadline, tomorrow);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 4,
          children: [
            ChoiceChip(
              key: const ValueKey('deadline-today'),
              avatar: const Icon(Icons.today, size: 16),
              label: Text(t['today']!),
              selected: _isSameDay(_selectedDeadline, today),
              onSelected:
                  _busy
                      ? null
                      : (selected) {
                        setState(() {
                          _selectedDeadline = selected ? today : null;
                        });
                      },
            ),
            ChoiceChip(
              key: const ValueKey('deadline-tomorrow'),
              avatar: const Icon(Icons.event, size: 16),
              label: Text(t['tomorrow']!),
              selected: _isSameDay(_selectedDeadline, tomorrow),
              onSelected:
                  _busy
                      ? null
                      : (selected) {
                        setState(() {
                          _selectedDeadline = selected ? tomorrow : null;
                        });
                      },
            ),
            ChoiceChip(
              key: const ValueKey('deadline-custom'),
              avatar: const Icon(Icons.calendar_month, size: 16),
              label: Text(
                isCustom
                    ? '${_selectedDeadline!.year}-${_selectedDeadline!.month.toString().padLeft(2, '0')}-${_selectedDeadline!.day.toString().padLeft(2, '0')}'
                    : t['pickDate']!,
              ),
              selected: isCustom,
              onSelected: _busy ? null : (_) => _pickCustomDate(today),
            ),
            if (_selectedDeadline != null)
              IconButton(
                key: const ValueKey('deadline-clear'),
                tooltip: t['clearDate']!,
                icon: const Icon(Icons.close, size: 18),
                visualDensity: VisualDensity.compact,
                onPressed:
                    _busy
                        ? null
                        : () => setState(() => _selectedDeadline = null),
              ),
          ],
        ),
        if (_selectedDeadline != null)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 4),
            child: Text(
              t['deadlineBatchScope']!,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _pickCustomDate(DateTime today) async {
    final first = DateTime(1900);
    final last = DateTime(2200, 12, 31);
    final initial = _selectedDeadline ?? today;
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
    if (mounted && picked != null) {
      setState(() {
        _selectedDeadline = DateTime(picked.year, picked.month, picked.day);
      });
    }
  }

  Widget _buildReminderRow(BuildContext context, Map<String, String> t) {
    final hasReminder = _selectedReminderAt != null;
    final formattedTime = hasReminder
        ? () {
            final dt = DateTime.fromMillisecondsSinceEpoch(_selectedReminderAt!);
            return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
          }()
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 4,
          children: [
            ActionChip(
              key: const ValueKey('input-reminder-btn'),
              avatar: Icon(
                hasReminder
                    ? Icons.notifications_active
                    : Icons.notifications_none,
                size: 16,
                color: hasReminder ? Theme.of(context).colorScheme.primary : null,
              ),
              label: Text(
                hasReminder
                    ? formattedTime!
                    : (t['setReminder'] ?? 'Set Reminder'),
              ),
              onPressed: _busy ? null : _pickReminderDateTime,
            ),
            if (hasReminder)
              IconButton(
                key: const ValueKey('input-reminder-clear'),
                tooltip: t['clearReminder'] ?? 'Clear Reminder',
                icon: const Icon(Icons.close, size: 18),
                visualDensity: VisualDensity.compact,
                onPressed:
                    _busy ? null : () => setState(() => _selectedReminderAt = null),
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _pickReminderDateTime() async {
    final now = DateTime.now();
    final initialDate = _selectedReminderAt != null
        ? DateTime.fromMillisecondsSinceEpoch(_selectedReminderAt!)
        : (_selectedDeadline ?? now);
    final firstDate = DateTime(now.year, now.month, now.day);
    final lastDate = DateTime(now.year + 5);

    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initialDate.isBefore(firstDate) ? firstDate : initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
    );
    if (pickedDate == null || !mounted) return;

    final initialTime = _selectedReminderAt != null
        ? TimeOfDay.fromDateTime(
            DateTime.fromMillisecondsSinceEpoch(_selectedReminderAt!),
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
      _selectedReminderAt = combined.millisecondsSinceEpoch;
    });
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _busy || _closed) return;
    final store = context.read<Store>();
    final boardId = store.activeBoardId;
    final config = AIConfig.fromJson(store.aiConfig.toJson());
    final settings = AppSettings.fromJson(store.settings.toJson());
    final inputs =
        text
            .split('\n')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();

    final deadlineSnapshot =
        _selectedDeadline == null
            ? null
            : DateTime(
              _selectedDeadline!.year,
              _selectedDeadline!.month,
              _selectedDeadline!.day,
              23,
              59,
              59,
            ).millisecondsSinceEpoch;

    if (_mode == InputModePref.single) {
      store.addTasks([
        for (final line in inputs)
          store.newTask(line, deadline: deadlineSnapshot)
            ..reminderAt = _selectedReminderAt,
      ]);
      _controller.clear();
      setState(() {
        _selectedDeadline = null;
        _selectedReminderAt = null;
      });
      if (!widget.embedded) Navigator.pop(context);
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
          r.toTask(
            id: newId(),
            boardId: boardId,
            createdAt: DateTime.now().millisecondsSinceEpoch,
            deadline: deadlineSnapshot,
            reminderAt: _selectedReminderAt,
          ),
      ];
      store.addTasks(tasks);
      _controller.clear();
      setState(() {
        _selectedDeadline = null;
        _selectedReminderAt = null;
      });
      final longTerm =
          !settings.autoDecomposeAI && !settings.suppressLongTermPrompt
              ? tasks
                  .where((task) => task.isLongTerm && !task.hasSubtasks)
                  .toList()
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

  Future<bool?> _askGroup(AIAnalysisResult group) {
    final t = context.read<Store>().t;
    return showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            scrollable: true,
            title: Text(t['suggestedGroup']!),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t['suggestedGroupPrompt']!),
                const SizedBox(height: 8),
                Text(
                  group.title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
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

Future<void> showBatchDecomposeSheet(
  BuildContext context,
  List<Task> tasks, {
  bool autoStart = false,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => _DecomposeSheet(tasks: tasks, autoStart: autoStart),
);

class _DecomposeSheet extends StatefulWidget {
  final List<Task> tasks;
  final bool autoStart;
  const _DecomposeSheet({required this.tasks, required this.autoStart});
  @override
  State<_DecomposeSheet> createState() => _DecomposeSheetState();
}

class _DecomposeSheetState extends State<_DecomposeSheet> {
  late final _selected = widget.tasks.map((task) => task.id).toSet();
  final _request = AICancellation();
  bool _busy = false;
  bool _closed = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_closed) _run();
      });
    }
  }

  @override
  void dispose() {
    _request.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.watch<Store>().t;
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          _closed = true;
          _request.cancel();
        }
      },
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            MediaQuery.viewInsetsOf(context).bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                t['batchReviewTitle']!,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(t['batchReviewDesc']!),
              for (final task in widget.tasks)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _selected.contains(task.id),
                  title: Text(task.title),
                  onChanged:
                      _busy
                          ? null
                          : (v) => setState(() {
                            v == true
                                ? _selected.add(task.id)
                                : _selected.remove(task.id);
                          }),
                ),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              FilledButton.icon(
                key: const ValueKey('decompose-submit'),
                onPressed: _busy || _selected.isEmpty ? null : _run,
                icon:
                    _busy
                        ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                        : const Icon(Icons.auto_awesome),
                label: Text(
                  _busy
                      ? t['processingBatch']!
                      : '${t['processBatch']} (${_selected.length})',
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(t[_busy ? 'cancel' : 'skipBatch']!),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _run() async {
    if (_busy || _closed) return;
    final store = context.read<Store>();
    final picked =
        store.tasks
            .where(
              (task) =>
                  _selected.contains(task.id) &&
                  !task.hasSubtasks &&
                  !task.completed,
            )
            .map((task) => Task.fromJson(task.toJson()))
            .toList();
    if (picked.isEmpty) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final results = await store.ai.decomposeBatch(
        taskTitles: picked.map((task) => task.title).toSet().toList(),
        config: AIConfig.fromJson(store.aiConfig.toJson()),
        language: store.settings.language,
        cancellation: _request,
      );
      if (!mounted || _closed) return;
      for (final task in picked) {
        if (!results.any(
          (r) => r.originalTitle == task.title && r.subtasks.isNotEmpty,
        )) {
          throw const AIException('aiInvalidResponse');
        }
      }
      for (final task in picked) {
        final current = store.tasks.where((t) => t.id == task.id).firstOrNull;
        if (current == null ||
            current.title != task.title ||
            current.hasSubtasks ||
            current.completed) {
          continue;
        }
        final match = results.firstWhere((r) => r.originalTitle == task.title);
        store.appendSubtasks(
          task.id,
          match.subtasks.map((s) => SubTask(id: newId(), title: s)).toList(),
        );
      }
      Navigator.pop(context);
    } catch (error) {
      if (mounted && !_closed) {
        setState(() => _error = aiErrorMessage(error, store.t));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

Future<void> showTaskEditSheet(BuildContext context, Task task) =>
    showTaskDetailSheet(context, task);
