import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../ai_service.dart';
import '../models.dart';
import '../storage.dart';

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
    if (_mode == InputModePref.single) {
      store.addTasks([for (final line in inputs) store.newTask(line)]);
      _controller.clear();
      if (!widget.embedded) Navigator.pop(context);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final request = _request = AICancellation();
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
      if (!store.boards.any((b) => b.id == boardId)) {
        throw const AIException('boardUnavailable');
      }
      final tasks = [
        for (final r in accepted)
          r.toTask(
            id: newId(),
            boardId: boardId,
            createdAt: DateTime.now().millisecondsSinceEpoch,
          ),
      ];
      store.addTasks(tasks);
      _controller.clear();
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
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _TaskEditSheet(task: task),
    );

class _TaskEditSheet extends StatefulWidget {
  final Task task;
  const _TaskEditSheet({required this.task});
  @override
  State<_TaskEditSheet> createState() => _TaskEditSheetState();
}

class _TaskEditSheetState extends State<_TaskEditSheet> {
  late final _title = TextEditingController(text: widget.task.title);
  late int _quadrant = widget.task.quadrant;
  late DateTime? _deadline =
      widget.task.deadline == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(widget.task.deadline!);
  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<Store>();
    final t = store.t;
    final d = _deadline;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                t['editTask']!,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('edit-title'),
                controller: _title,
                autofocus: true,
                minLines: 1,
                maxLines: 3,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.calendar_month, size: 18),
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
                      tooltip: t['cancel'],
                      onPressed: () => setState(() => _deadline = null),
                      icon: const Icon(Icons.clear),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(t['quadrant']!),
              Wrap(
                spacing: 8,
                children: [
                  for (final q in allQuadrants)
                    ChoiceChip(
                      label: Text(t['q${q}Short']!),
                      selected: _quadrant == q,
                      onSelected: (_) => setState(() => _quadrant = q),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                key: const ValueKey('save-task'),
                icon: const Icon(Icons.check),
                label: Text(t['confirm']!),
                onPressed: () {
                  if (_title.text.trim().isEmpty) return;
                  final current =
                      store.tasks
                          .where((task) => task.id == widget.task.id)
                          .firstOrNull;
                  if (current != null) {
                    final updated =
                        Task.fromJson(current.toJson())
                          ..title = _title.text.trim()
                          ..quadrant = _quadrant
                          ..deadline =
                              d == null
                                  ? null
                                  : DateTime(
                                    d.year,
                                    d.month,
                                    d.day,
                                  ).millisecondsSinceEpoch;
                    store.updateTask(updated);
                  }
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        ),
      ),
    );
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
}
