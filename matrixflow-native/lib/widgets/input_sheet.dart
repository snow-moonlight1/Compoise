import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../ai_service.dart';
import '../models.dart';
import '../storage.dart';
import '../ui/platform_ui_policy.dart';
import 'batch_decompose_sheet.dart';
import 'date_edit_fields.dart';
import 'task_edit_draft.dart';

// The list widgets reach these two routes through this library; retarget them
// to the owning modules and drop both lines.
export 'batch_decompose_sheet.dart' show showBatchDecomposeSheet;
export 'task_detail_panel.dart' show showTaskEditSheet;

class InputSheet extends StatefulWidget {
  final InputModePref initialMode;
  final bool embedded;
  final ValueChanged<bool>? onDirtyChanged;
  const InputSheet({
    super.key,
    required this.initialMode,
    this.embedded = false,
    this.onDirtyChanged,
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
  bool _reportedDirty = false;
  String? _error;
  DateTime? _selectedDeadline;
  int? _selectedReminderAt;

  bool get _isDirty =>
      _controller.text.isNotEmpty ||
      _mode != widget.initialMode ||
      _selectedDeadline != null ||
      _selectedReminderAt != null;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_reportDirty);
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.watch<Store>().t;
    final policy = PlatformUiPolicy.of(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _reportDirty();
    });
    final insets =
        widget.embedded ? 0.0 : MediaQuery.viewInsetsOf(context).bottom;
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
                selected: _mode == mode,
                onSelected: _busy ? null : (_) => setState(() => _mode = mode),
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
        if (policy.showShortcutHints)
          Text(
            t['shortcutHintWindows'] ?? t['shortcutHint']!,
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
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
    final submit = FilledButton.icon(
      key: const ValueKey('submit-tasks'),
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
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
        t[_mode == InputModePref.brainDump ? 'analyzeBtn' : 'addSingleBtn']!,
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
        child:
            widget.embedded
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
      child: Padding(padding: EdgeInsets.only(bottom: insets), child: body),
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

  Widget _buildDeadlineRow(BuildContext context, Map<String, String> t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        DeadlineDayChips(
          t: t,
          keyPrefix: 'deadline',
          selected: _selectedDeadline,
          enabled: !_busy,
          onChanged:
              (day) => setState(() {
                _selectedDeadline = day;
              }),
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

  Widget _buildReminderRow(BuildContext context, Map<String, String> t) {
    final hasReminder = _selectedReminderAt != null;
    final formattedTime =
        hasReminder ? formatCivilDateTimeMs(_selectedReminderAt!) : null;

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
                color:
                    hasReminder ? Theme.of(context).colorScheme.primary : null,
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
                    _busy
                        ? null
                        : () => setState(() => _selectedReminderAt = null),
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _pickReminderDateTime() async {
    await pickReminderMoment(
      context,
      t: context.read<Store>().t,
      reminderAt: _selectedReminderAt,
      deadline: _selectedDeadline,
      onPicked:
          (moment) => setState(() {
            _selectedReminderAt = moment;
          }),
    );
  }

  Future<void> _submit() async {
    if (hasPendingImeComposition(_controller)) return;
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

    final deadlineSnapshot = endOfCivilDayMs(_selectedDeadline);

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
