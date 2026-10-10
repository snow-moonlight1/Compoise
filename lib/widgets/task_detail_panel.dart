import 'reminder_failure_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../screens/planner_screen.dart';
import '../storage.dart';
import '../ui/platform_ui_policy.dart';
import 'batch_decompose_sheet.dart';
import 'date_edit_fields.dart';
import 'subtask_edit_dialog.dart';
import 'task_edit_draft.dart';
import 'task_hierarchy_checkbox.dart';
import 'task_tags_editor.dart';

/// Confirms discarding an unsaved detail draft. Returns true when the user
/// chooses to discard, false when they keep editing or dismiss the dialog.
Future<bool> confirmDiscardDraft(BuildContext context) async {
  final t = context.read<Store>().t;
  final res = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(t['discardChangesTitle'] ?? 'Discard changes?'),
      content: Text(
        t['discardChangesConfirm'] ?? 'You have unsaved changes. Discard them?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(t['keepEditing'] ?? 'Keep Editing'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(ctx).colorScheme.error,
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(t['discard'] ?? 'Discard'),
        ),
      ],
    ),
  );
  return res ?? false;
}

/// Shows the task detail as a modal bottom sheet on narrow screens.
///
/// [onScheduleTime] replaces the default schedule entry, which saves a pending
/// draft and then opens the Planner for that task.
Future<void> showTaskDetailSheet(
  BuildContext context,
  Task task, {
  String? highlightSubtaskId,
  ValueChanged<bool>? onDirtyChanged,
  Future<void> Function(String taskId)? onScheduleTime,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Theme.of(context).colorScheme.surface,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
  ),
  builder: (_) => DraggableScrollableSheet(
    initialChildSize: 0.75,
    minChildSize: 0.4,
    maxChildSize: 0.95,
    expand: false,
    builder: (sheetContext, scrollController) => TaskDetailPanel(
      key: ValueKey('task-detail-${task.id}'),
      task: task,
      scrollController: scrollController,
      highlightSubtaskId: highlightSubtaskId,
      onDirtyChanged: onDirtyChanged,
      onScheduleTime: onScheduleTime,
    ),
  ),
);

/// Opens the editor for an existing task from a list row without a host panel.
Future<void> showTaskEditSheet(
  BuildContext context,
  Task task, {
  Future<void> Function(String taskId)? onScheduleTime,
}) => showTaskDetailSheet(
  context,
  task,
  onScheduleTime: onScheduleTime,
);

/// Which task a page shows in its detail editor, whether that editor holds an
/// unsaved draft, and what it takes to switch away or leave. Pages keep their
/// own layout and Store commands so the rules live in one place instead of
/// being retyped per surface.
class TaskDetailSession {
  /// [onChanged] fires when the opened task changes; the host rebuilds on it.
  /// A draft coming and going deliberately does not rebuild: it is read when
  /// the page needs to decide something.
  TaskDetailSession({required this.onChanged});

  final VoidCallback onChanged;

  String? _taskId;
  String? _highlightSubtaskId;
  bool _dirty = false;
  bool _modalOpen = false;

  String? get taskId => _taskId;

  String? get highlightSubtaskId => _highlightSubtaskId;

  bool get hasDraft => _dirty;

  bool get isModalOpen => _modalOpen;

  /// The hosted editor reports its own draft state; the page never has to poll
  /// it and nothing rebuilds because of it.
  void reportDraft(bool dirty) => _dirty = dirty;

  Task? taskIn(Store store) => _taskId == null
      ? null
      : store.tasks.where((task) => task.id == _taskId).firstOrNull;

  /// Opens [task]. On a wide layout the hosted panel switches, asking first
  /// when another task still holds a draft; on a narrow layout the modal editor
  /// runs and its draft is forgotten once it closes.
  Future<void> open(
    BuildContext context,
    Task task, {
    required bool isWide,
    String? subtaskId,
  }) async {
    if (isWide) {
      if (_taskId != null && _taskId != task.id) {
        if (!await confirmLeave(context)) return;
      }
      _taskId = task.id;
      _highlightSubtaskId = subtaskId;
      onChanged();
      return;
    }
    _modalOpen = true;
    _dirty = false;
    try {
      await showTaskDetailSheet(
        context,
        task,
        highlightSubtaskId: subtaskId,
        onDirtyChanged: (dirty) => _dirty = dirty,
      );
    } finally {
      _modalOpen = false;
      _dirty = false;
    }
  }

  /// The editor asked to close and has already settled its own draft.
  void handleClose() {
    _taskId = null;
    _highlightSubtaskId = null;
    _dirty = false;
    onChanged();
  }

  /// A close invoked from outside the editor, such as Escape: settles the draft
  /// first and stays put when the user keeps editing.
  Future<void> requestClose(BuildContext context) async {
    if (!await confirmLeave(context)) return;
    handleClose();
  }

  /// Asks whether an unsaved draft may be thrown away before navigating away,
  /// switching board, or opening another editor over the current one.
  Future<bool> confirmLeave(BuildContext context) async {
    if (!_dirty) return true;
    final discard = await confirmDiscardDraft(context);
    if (discard) _dirty = false;
    return discard;
  }

  /// Forgets the hosted editor without a prompt, for the moments the page is
  /// already dropping it: a board change or a clear.
  void drop() {
    _taskId = null;
    _highlightSubtaskId = null;
    _dirty = false;
  }
}

/// The detail editor next to a page's own content. The width and the gap come
/// from [PlatformUiPolicy] so every page agrees; the separator stays with the
/// surface that shows it.
class DetailSideBySide extends StatelessWidget {
  const DetailSideBySide({
    super.key,
    required this.main,
    required this.detail,
    this.separator,
    this.crossAxisAlignment = CrossAxisAlignment.stretch,
  });

  final Widget main;
  final Widget detail;
  final Widget? separator;
  final CrossAxisAlignment crossAxisAlignment;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: crossAxisAlignment,
      children: [
        Expanded(child: main),
        separator ?? const SizedBox(width: PlatformUiPolicy.sideDetailGap),
        SizedBox(width: PlatformUiPolicy.sideDetailWidth, child: detail),
      ],
    );
  }
}

/// Central task detail editor for parent and child tasks.
/// Can be rendered inside a bottom sheet or as a desktop side panel.
///
/// The schedule entry is offered for parent tasks only. Child tasks keep their
/// own editor without a schedule link, and the home input stays uncluttered.
class TaskDetailPanel extends StatefulWidget {
  final Task task;
  final VoidCallback? onClose;
  final ValueChanged<bool>? onDirtyChanged;
  final bool isSidebar;
  final ScrollController? scrollController;
  final String? highlightSubtaskId;

  /// Opens the schedule for this task. Defaults to saving the draft in place
  /// and pushing the Planner with this task preselected for a new time block.
  final Future<void> Function(String taskId)? onScheduleTime;

  const TaskDetailPanel({
    super.key,
    required this.task,
    this.onClose,
    this.onDirtyChanged,
    this.isSidebar = false,
    this.scrollController,
    this.highlightSubtaskId,
    this.onScheduleTime,
  });

  @override
  State<TaskDetailPanel> createState() => _TaskDetailPanelState();
}

class _TaskDetailPanelState extends State<TaskDetailPanel> {
  late final TaskEditDraft _draft;
  bool _notifyingDirty = false;
  bool _showMore = false;
  bool _saving = false;
  bool _pendingSave = false;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    _draft = TaskEditDraft(widget.task, onChanged: _onDraftChanged);
    _emitDirty();
  }

  @override
  void didUpdateWidget(TaskDetailPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.task.id != widget.task.id) {
      _draft.load(widget.task);
      _showMore = false;
      _pendingSave = false;
      _saveError = null;
      _emitDirty();
    }
  }

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  void _onDraftChanged() {
    if (!mounted) return;
    setState(() {});
    _emitDirty();
  }

  void _emitDirty() {
    if (_notifyingDirty) return;
    _notifyingDirty = true;
    widget.onDirtyChanged?.call(_draft.isDirty);
    _notifyingDirty = false;
  }

  void _close() {
    if (widget.onClose != null) {
      widget.onClose!();
    } else if (Navigator.canPop(context)) {
      WidgetsBinding.instance.scheduleFrame();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && Navigator.canPop(context)) Navigator.pop(context);
      });
    }
  }

  Future<bool> _confirmDiscard(BuildContext context) =>
      confirmDiscardDraft(context);

  Future<void> _attemptClose() async {
    if (!_draft.isDirty) {
      _close();
      return;
    }
    final discard = await _confirmDiscard(context);
    if (discard && mounted) {
      _draft.markDiscarding();
      setState(() {});
      widget.onDirtyChanged?.call(false);
      _close();
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_pendingSave) {
      setState(() => _saving = true);
      final store = context.read<Store>();
      final current = store.tasks
          .where((t) => t.id == widget.task.id)
          .firstOrNull;
      if (current != null) store.updateTask(_draft.applyTo(current));
      final result = await store.retrySave(waitForReminders: false);
      if (!mounted) return;
      setState(() => _saving = false);
      if (!result.success) {
        setState(
          () => _saveError =
              store.persistenceError ?? store.t['storageWriteError'],
        );
        return;
      }
      _finishSave();
      return;
    }
    if (hasPendingImeComposition(_draft.titleController) ||
        hasPendingImeComposition(_draft.notesController) ||
        hasPendingImeComposition(_draft.newSubtaskController)) {
      return;
    }
    if (!_draft.hasTitle) return;

    final store = context.read<Store>();
    final current = store.tasks
        .where((t) => t.id == widget.task.id)
        .firstOrNull;
    if (current == null) {
      _draft.markDiscarding();
      setState(() {});
      widget.onDirtyChanged?.call(false);
      _close();
      return;
    }

    // A save is the user saying this draft is finished, so the composer row is
    // written as a subtask instead of quietly disappearing with the editor.
    _draft.takeNewSubtask();
    setState(() {
      _saving = true;
      _saveError = null;
    });
    store.updateTask(_draft.applyTo(current));
    final result = await store.flush(waitForReminders: false);
    if (!mounted) return;
    setState(() => _saving = false);
    if (!result.success) {
      setState(() {
        _pendingSave = true;
        _saveError = store.persistenceError ?? store.t['storageWriteError'];
      });
      return;
    }
    _finishSave();
  }

  void _finishSave() {
    _draft.markDiscarding();
    setState(() {});
    widget.onDirtyChanged?.call(false);
    _close();
  }

  /// Saves the draft in place for an action that needs a stored parent task but
  /// continues on the same page. Returns false while the draft cannot be
  /// written, leaving the existing unsaved state visible instead of navigating.
  Future<bool> _persistDraft() async {
    if (!_draft.isDirty) return true;
    if (!_draft.hasTitle) return false;
    final store = context.read<Store>();
    final current = store.tasks
        .where((t) => t.id == widget.task.id)
        .firstOrNull;
    if (current == null) return false;
    _draft.takeNewSubtask();
    setState(() {
      _saving = true;
      _saveError = null;
    });
    store.updateTask(_draft.applyTo(current));
    final result = await store.flush(waitForReminders: false);
    if (!mounted) return false;
    setState(() => _saving = false);
    if (!result.success) {
      setState(() {
        _pendingSave = true;
        _saveError = store.persistenceError ?? store.t['storageWriteError'];
      });
      return false;
    }
    _draft.markDiscarding();
    setState(() {});
    widget.onDirtyChanged?.call(false);
    return true;
  }

  /// Schedules time for this parent task. A time block references a stored
  /// task, so a pending draft is saved first; a save that fails keeps the
  /// editor and its error message where they are.
  Future<void> _scheduleTime() async {
    if (_saving) return;
    final store = context.read<Store>();
    final navigator = Navigator.of(context, rootNavigator: true);
    final handler = widget.onScheduleTime;
    if (!await _persistDraft() || !mounted) return;
    final taskId = widget.task.id;
    // The sheet has to be gone before the schedule route is pushed over it.
    if (!widget.isSidebar && navigator.canPop()) {
      navigator.pop();
      await Future<void>.delayed(Duration.zero);
    }
    if (handler != null) {
      await handler(taskId);
      return;
    }
    await navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => PlannerScreen(
          store: store,
          initialTaskId: taskId,
          startTimeBlock: true,
        ),
      ),
    );
  }

  Future<void> _confirmDeleteTask() async {
    final store = context.read<Store>();
    final t = store.t;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t['deleteTaskTitle']!),
        content: Text(t['deleteTaskConfirm']!),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t['cancel']!),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t['confirm']!),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      store.deleteTask(widget.task.id);
      _draft.markDiscarding();
      setState(() {});
      _close();
    }
  }

  Future<void> _editTime() async {
    final result = await showTaskTimeEditor(
      context,
      t: context.read<Store>().t,
      deadline: _draft.deadline,
      reminderAt: _draft.reminderAt,
      supportsPlannedDate: true,
      plannedDate: _draft.plannedDate,
    );
    if (result == null || !mounted) return;
    setState(() {
      _draft.deadline = result.deadline;
      _draft.reminderAt = result.reminderAt;
      _draft.plannedDate = result.plannedDate;
    });
  }

  Future<void> _editNotes() async {
    final controller = TextEditingController(text: _draft.notesController.text);
    final t = context.read<Store>().t;
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(t['editNotes']!),
        content: SizedBox(
          width: 420,
          child: TextField(
            key: const ValueKey('edit-notes'),
            controller: controller,
            autofocus: true,
            minLines: 4,
            maxLines: 12,
            keyboardType: TextInputType.multiline,
            decoration: InputDecoration(hintText: t['notesHint']),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(t['cancel']!),
          ),
          FilledButton(
            onPressed: () {
              if (hasPendingImeComposition(controller)) return;
              Navigator.pop(dialogContext, controller.text);
            },
            child: Text(t['confirm']!),
          ),
        ],
      ),
    );
    if (mounted && value != null) _draft.notesController.text = value;
    Future<void>.delayed(const Duration(milliseconds: 350), controller.dispose);
  }

  void _addSubtask() {
    if (hasPendingImeComposition(_draft.newSubtaskController)) return;
    if (_draft.takeNewSubtask() == null) return;
    setState(() {});
  }

  Future<void> _editSubtask(SubTask sub) async {
    final result = await showSubtaskEditDialog(
      context,
      t: context.read<Store>().t,
      subtask: sub,
      parentDeadline: _draft.deadline,
    );
    if (result == null || !mounted) return;
    setState(() {
      sub.title = result.title;
      sub.notesMarkdown = result.notesMarkdown;
      sub.deadline = result.deadline;
      sub.reminderAt = result.reminderAt;
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<Store>();
    final t = store.t;
    final theme = Theme.of(context);
    final d = _draft.deadline;
    final p = _draft.plannedDate;
    final dirty = _draft.isDirty;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onDirtyChanged?.call(dirty);
    });

    return PopScope(
      canPop: !_draft.isDirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final discard = await _confirmDiscard(context);
        if (discard && mounted) {
          _draft.markDiscarding();
          setState(() {});
          _close();
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusScope.of(context).unfocus(),
        child: Container(
          decoration: widget.isSidebar
              ? BoxDecoration(
                  color: theme.colorScheme.surface,
                  border: Border(
                    left: BorderSide(color: theme.dividerColor, width: 1),
                  ),
                )
              : null,
          child: SafeArea(
            top: false,
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.enter, control: true):
                    _save,
                const SingleActivator(LogicalKeyboardKey.enter, meta: true):
                    _save,
              },
              child: Column(
                children: [
                  const ReminderFailureBanner(),
                  // Top Header / Toolbar
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            t['editTask']!,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        FilledButton(
                          key: const ValueKey('save-task'),
                          style: FilledButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                          ),
                          onPressed: _saving ? null : _save,
                          child: Text(
                            _pendingSave
                                ? t['retrySave']!
                                : t['save'] ?? t['confirm']!,
                          ),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: t['close']!,
                          icon: const Icon(Icons.close),
                          onPressed: _attemptClose,
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  if (_saveError != null)
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        _saveError!,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ),
                  // Scrollable Body
                  Expanded(
                    child: SingleChildScrollView(
                      controller: widget.scrollController,
                      padding: EdgeInsets.fromLTRB(
                        16,
                        12,
                        16,
                        MediaQuery.viewInsetsOf(context).bottom + 20,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Task Title Field (multiline, Enter newline, Ctrl+Enter save)
                          TextField(
                            key: const ValueKey('edit-title'),
                            controller: _draft.titleController,
                            autofocus: !widget.isSidebar,
                            minLines: 1,
                            maxLines: 5,
                            keyboardType: TextInputType.multiline,
                            textInputAction: TextInputAction.newline,
                            decoration: InputDecoration(
                              labelText: t['editTask']!,
                              alignLabelWithHint: true,
                              border: const OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Subtasks Section
                          Text(
                            '${t['subtasks'] ?? 'Subtasks'} (${_draft.subtasks.where((s) => s.completed).length}/${_draft.subtasks.length})',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),

                          // Subtasks list
                          for (final sub in _draft.subtasks)
                            Container(
                              key: ValueKey('detail-subtask-${sub.id}'),
                              margin: const EdgeInsets.fromLTRB(16, 2, 0, 2),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              decoration: sub.id == widget.highlightSubtaskId
                                  ? BoxDecoration(
                                      color: theme.colorScheme.primaryContainer
                                          .withValues(alpha: 0.35),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: theme.colorScheme.primary
                                            .withValues(alpha: 0.5),
                                      ),
                                    )
                                  : null,
                              child: Row(
                                children: [
                                  TaskHierarchyCheckbox(
                                    hitTargetKey: ValueKey(
                                      'detail-subtask-check-${sub.id}',
                                    ),
                                    visualKey: ValueKey(
                                      'detail-subtask-check-${sub.id}-visual',
                                    ),
                                    level: TaskHierarchyLevel.child,
                                    value: sub.completed,
                                    semanticsLabel: taskCheckboxLabel(
                                      t: t,
                                      level: TaskHierarchyLevel.child,
                                      value: sub.completed,
                                      title: sub.title,
                                    ),
                                    onChanged: (v) {
                                      setState(() => sub.completed = v);
                                    },
                                  ),
                                  Expanded(
                                    child: InkWell(
                                      key: ValueKey('subtask-item-${sub.id}'),
                                      borderRadius: BorderRadius.circular(4),
                                      onTap: () => _editSubtask(sub),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 6,
                                          horizontal: 4,
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              sub.title,
                                              style: TextStyle(
                                                fontSize: TaskHierarchyStyle
                                                    .childTitleSize,
                                                decoration: sub.completed
                                                    ? TextDecoration.lineThrough
                                                    : null,
                                                color: sub.completed
                                                    ? theme.disabledColor
                                                    : theme
                                                          .colorScheme
                                                          .onSurface,
                                              ),
                                            ),
                                            if (sub.notesMarkdown != null &&
                                                sub.notesMarkdown!
                                                    .trim()
                                                    .isNotEmpty) ...[
                                              const SizedBox(height: 2),
                                              Text(
                                                sub.notesMarkdown!,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: theme.textTheme.bodySmall
                                                    ?.copyWith(
                                                      color: theme
                                                          .colorScheme
                                                          .onSurfaceVariant,
                                                      fontSize: 11,
                                                    ),
                                              ),
                                            ],
                                            if (sub.deadline != null) ...[
                                              const SizedBox(height: 2),
                                              Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    Icons.calendar_month,
                                                    size: 11,
                                                    color: theme
                                                        .colorScheme
                                                        .onSurface
                                                        .withValues(alpha: 0.5),
                                                  ),
                                                  const SizedBox(width: 3),
                                                  Text(
                                                    formatCivilDateMs(
                                                      sub.deadline!,
                                                    ),
                                                    style: theme
                                                        .textTheme
                                                        .labelSmall
                                                        ?.copyWith(
                                                          color: theme
                                                              .colorScheme
                                                              .onSurface
                                                              .withValues(
                                                                alpha: 0.6,
                                                              ),
                                                          fontSize: 11,
                                                        ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                            if (sub.reminderAt != null) ...[
                                              const SizedBox(height: 2),
                                              Row(
                                                children: [
                                                  Icon(
                                                    Icons
                                                        .notifications_active_outlined,
                                                    size: 11,
                                                    color: theme
                                                        .colorScheme
                                                        .primary,
                                                  ),
                                                  const SizedBox(width: 3),
                                                  Text(
                                                    formatCivilDateTimeMs(
                                                      sub.reminderAt!,
                                                    ),
                                                    style: theme
                                                        .textTheme
                                                        .labelSmall
                                                        ?.copyWith(
                                                          color: theme
                                                              .colorScheme
                                                              .primary,
                                                          fontSize: 11,
                                                        ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.close, size: 16),
                                    onPressed: () {
                                      setState(
                                        () => _draft.subtasks.remove(sub),
                                      );
                                    },
                                    tooltip: t['delete'] ?? 'Delete',
                                  ),
                                ],
                              ),
                            ),

                          // Add Subtask Row
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  key: const ValueKey('edit-new-subtask'),
                                  controller: _draft.newSubtaskController,
                                  decoration: InputDecoration(
                                    hintText: t['addSubtask']!,
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    border: const OutlineInputBorder(),
                                  ),
                                  onSubmitted: (_) => _addSubtask(),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton.filledTonal(
                                icon: const Icon(Icons.add),
                                onPressed: _addSubtask,
                                tooltip: t['addSubtask']!,
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          TextButton.icon(
                            key: const ValueKey('edit-notes-entry'),
                            onPressed: _editNotes,
                            icon: const Icon(Icons.notes_outlined),
                            label: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                _draft.notesController.text.trim().isEmpty
                                    ? t['notesHint']!
                                    : _draft.notesController.text,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            key: const ValueKey('edit-schedule-entry'),
                            onPressed: _saving ? null : _scheduleTime,
                            icon: const Icon(Icons.calendar_month_outlined),
                            label: Text(t['scheduleTimeEntry']!),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            key: const ValueKey('edit-time-btn'),
                            onPressed: _editTime,
                            icon: const Icon(Icons.schedule),
                            label: Text(t['timePanel']!),
                          ),
                          if (d != null ||
                              p != null ||
                              _draft.reminderAt != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Wrap(
                                spacing: 8,
                                children: [
                                  if (p != null)
                                    ActionChip(
                                      key: const ValueKey('edit-planned-btn'),
                                      label: Text(
                                        '${t['plannedDate']}: ${formatCivilDate(p)}',
                                      ),
                                      onPressed: _editTime,
                                    ),
                                  if (d != null)
                                    ActionChip(
                                      key: const ValueKey('edit-deadline-btn'),
                                      label: Text(
                                        '${t['deadline']}: ${formatCivilDate(d)}',
                                      ),
                                      onPressed: _editTime,
                                    ),
                                  if (_draft.reminderAt != null)
                                    ActionChip(
                                      key: const ValueKey('edit-reminder-btn'),
                                      label: Text(
                                        '${t['reminder']}: ${formatCivilDateTimeMs(_draft.reminderAt!)}',
                                      ),
                                      onPressed: _editTime,
                                    ),
                                ],
                              ),
                            ),
                          if (_draft.quadrant != qDo ||
                              _draft.isLongTerm ||
                              _draft.urgencyMode == UrgencyMode.manual)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Wrap(
                                spacing: 8,
                                children: [
                                  ActionChip(
                                    key: const ValueKey('quadrant-summary'),
                                    label: Text(t['q${_draft.quadrant}']!),
                                    onPressed: () =>
                                        setState(() => _showMore = true),
                                  ),
                                  if (_draft.isLongTerm)
                                    ActionChip(
                                      label: Text(t['longTermTask']!),
                                      onPressed: () =>
                                          setState(() => _showMore = true),
                                    ),
                                ],
                              ),
                            ),
                          if (_draft.tags.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Wrap(
                                key: const ValueKey('task-tags-summary'),
                                spacing: 6,
                                runSpacing: 4,
                                children: [
                                  for (final tag in _draft.tags)
                                    ActionChip(
                                      label: Text(tag),
                                      onPressed: () =>
                                          setState(() => _showMore = true),
                                    ),
                                ],
                              ),
                            ),
                          const SizedBox(height: 8),
                          TextButton.icon(
                            key: const ValueKey('more-properties-btn'),
                            onPressed: () =>
                                setState(() => _showMore = !_showMore),
                            icon: Icon(
                              _showMore ? Icons.expand_less : Icons.expand_more,
                            ),
                            label: Text(t['moreProperties']!),
                          ),
                          if (_showMore) ...[
                            Text(
                              t['filterTags']!,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 6),
                            TaskTagsEditor(
                              value: _draft.tags,
                              onChanged: (tags) =>
                                  setState(() => _draft.tags = tags),
                              t: t,
                            ),
                            const SizedBox(height: 16),
                            // Quadrant selection chips
                            Text(
                              t['quadrant']!,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                for (final q in allQuadrants)
                                  ChoiceChip(
                                    label: Text(t['q$q']!),
                                    selected: _draft.quadrant == q,
                                    onSelected: (_) {
                                      setState(() {
                                        final oldQ = _draft.quadrant;
                                        _draft.quadrant = q;
                                        if (isUrgentQuadrant(oldQ) !=
                                            isUrgentQuadrant(q)) {
                                          _draft.urgencyMode =
                                              UrgencyMode.manual;
                                        }
                                      });
                                    },
                                  ),
                              ],
                            ),
                            if (_draft.urgencyMode == UrgencyMode.manual) ...[
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: theme
                                      .colorScheme
                                      .surfaceContainerHighest
                                      .withValues(alpha: 0.5),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.tune,
                                      size: 16,
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        t['urgencyManualNotice'] ??
                                            'Urgency manually set',
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color: theme
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                            ),
                                      ),
                                    ),
                                    TextButton(
                                      key: const ValueKey('reset-urgency-auto'),
                                      style: TextButton.styleFrom(
                                        visualDensity: VisualDensity.compact,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                        ),
                                      ),
                                      onPressed: () {
                                        setState(() {
                                          _draft.urgencyMode = UrgencyMode.auto;
                                          final store = context.read<Store>();
                                          final d = _draft.deadline;
                                          if (d != null) {
                                            final dMs = DateTime(
                                              d.year,
                                              d.month,
                                              d.day,
                                              23,
                                              59,
                                              59,
                                            ).millisecondsSinceEpoch;
                                            if (isDeadlineUrgent(
                                              dMs,
                                              store
                                                  .settings
                                                  .urgencyThresholdDays,
                                            )) {
                                              _draft.quadrant = promoteToUrgent(
                                                _draft.quadrant,
                                              );
                                            }
                                          }
                                        });
                                      },
                                      child: Text(
                                        t['resetUrgencyAuto'] ?? 'Restore Auto',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(height: 16),

                            // Long-Term switch & AI Decompose button
                            Row(
                              children: [
                                Expanded(
                                  child: SwitchListTile(
                                    title: Text(
                                      t['longTermTask'] ?? 'Long-Term Task',
                                      style: theme.textTheme.bodyMedium,
                                    ),
                                    value: _draft.isLongTerm,
                                    onChanged: (v) =>
                                        setState(() => _draft.isLongTerm = v),
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                ),
                                OutlinedButton.icon(
                                  icon: const Icon(
                                    Icons.auto_awesome,
                                    size: 16,
                                  ),
                                  label: Text(t['decomposeTask'] ?? 'AI'),
                                  onPressed: () {
                                    showBatchDecomposeSheet(context, [
                                      widget.task,
                                    ], autoStart: true);
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),

                            TextButton.icon(
                              onPressed: _confirmDeleteTask,
                              icon: Icon(
                                Icons.delete_outline,
                                color: theme.colorScheme.error,
                              ),
                              label: Text(t['deleteTaskTitle']!),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
