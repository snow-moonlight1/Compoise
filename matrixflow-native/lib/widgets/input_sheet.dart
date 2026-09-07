import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../storage.dart';

/// Input surface with the two modes (manual lines, AI dump). Used both as a
/// bottom sheet and embedded in the desktop side panel ([embedded] skips pops).
class InputSheet extends StatefulWidget {
  final InputModePref initialMode;
  final bool embedded;
  const InputSheet({super.key, required this.initialMode, this.embedded = false});

  @override
  State<InputSheet> createState() => _InputSheetState();
}

class _InputSheetState extends State<InputSheet> {
  late InputModePref _mode = widget.initialMode;
  final _controller = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<Store>();
    final t = store.t;
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.enter, control: true): _submit,
          const SingleActivator(LogicalKeyboardKey.enter, meta: true): _submit,
        },
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<InputModePref>(
                segments: [
                  ButtonSegment(value: InputModePref.single, label: Text(t['modeManual']!)),
                  ButtonSegment(value: InputModePref.brainDump, label: Text(t['modeAI']!)),
                ],
                selected: {_mode},
                onSelectionChanged: (s) => setState(() => _mode = s.first),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _controller,
                maxLines: 5,
                minLines: 3,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: _mode == InputModePref.brainDump ? t['inputPlaceholderAI'] : t['inputPlaceholderManual'],
                ),
              ),
              const SizedBox(height: 6),
              if (_mode == InputModePref.brainDump)
                Text(
                  t['aiNote']!,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                  textAlign: TextAlign.center,
                ),
              Text(
                t['shortcutHint']!,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                onPressed: _busy ? null : _submit,
                icon: _busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(_mode == InputModePref.brainDump ? Icons.auto_awesome : Icons.add),
                label: Text(_mode == InputModePref.brainDump ? t['analyzeBtn']! : t['addSingleBtn']!),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _busy) return;
    final store = context.read<Store>();
    final t = store.t;

    if (_mode == InputModePref.single) {
      final lines = text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
      store.addTasks([for (final line in lines) store.newTask(line)]);
      _controller.clear();
      if (!widget.embedded) Navigator.of(context).pop();
      return;
    }

    setState(() => _busy = true);
    try {
      final results = await store.ai.analyzeTasks(
        inputs: text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList(),
        config: store.aiConfig,
        language: store.settings.language,
        autoDecompose: store.settings.autoDecomposeAI,
      );
      if (!mounted) return;

      // Phase 2: grouping decision for grouped results (subtasked + flagged groupable)
      final groups = results.where((r) => r.subtasks.isNotEmpty && !store.settings.autoGroupAI).toList()
        ..removeWhere((r) => store.settings.suppressGroupPrompt);
      final accepted = <AIAnalysisResult>[];
      for (final group in groups) {
        final keep = await _askGroup(context, group);
        if (keep) {
          accepted.add(group);
        } else {
          // split into standalone tasks
          for (final sub in group.subtasks) {
            accepted.add(AIAnalysisResult(title: sub, quadrant: group.quadrant));
          }
        }
      }
      final nonGrouped = results.where((r) => !groups.contains(r));
      final finalResults = [...accepted, ...nonGrouped];

      // Phase 3: silent decompose correction when autoDecompose is on
      final tasks = [
        for (final r in finalResults)
          r.toTask(id: DateTime.now().microsecondsSinceEpoch.toString() + r.title.hashCode.toString(), boardId: store.activeBoardId, createdAt: DateTime.now().millisecondsSinceEpoch),
      ];
      store.addTasks(tasks);

      if (!store.settings.autoDecomposeAI && !store.settings.suppressLongTermPrompt) {
        final longTerm = tasks.where((t) => t.isLongTerm && !t.hasSubtasks).toList();
        if (longTerm.isNotEmpty && mounted) {
          if (!widget.embedded) Navigator.of(context).pop();
          await showBatchDecomposeSheet(context, longTerm);
          return;
        }
      }
      if (mounted) {
        _controller.clear();
        if (!widget.embedded) Navigator.of(context).pop();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${t['error']}: $e'), width: 460),
      );
    }
  }

  Future<bool> _askGroup(BuildContext context, AIAnalysisResult group) async {
    final store = context.read<Store>();
    final t = store.t;
    final keep = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => ScaleIn(
        child: AlertDialog(
          title: Text(t['suggestedGroup']!),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t['suggestedGroupPrompt']!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                      )),
              const SizedBox(height: 10),
              Text(group.title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w800,
                      )),
              const SizedBox(height: 8),
              Text(t['groupContents']!,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                      )),
              const SizedBox(height: 4),
              ...group.subtasks.map((s) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Container(width: 4, height: 4, decoration: const BoxDecoration(color: Colors.grey, shape: BoxShape.circle)),
                        const SizedBox(width: 8),
                        Expanded(child: Text(s, style: Theme.of(context).textTheme.bodySmall)),
                      ],
                    ),
                  )),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(t['skipGroup']!)),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(t['confirmGroupBtn']!)),
          ],
        ),
      ),
    );
    return keep ?? false;
  }
}

/// Batch decompose: pick long-term tasks, run AI, append subtasks.
Future<void> showBatchDecomposeSheet(BuildContext context, List<Task> longTermTasks) async {
  final store = context.read<Store>();
  final t = store.t;
  final selected = {for (final task in longTermTasks) task.id};
  var busy = false;

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) {
      return StatefulBuilder(
        builder: (sheetContext, setSheetState) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(t['batchReviewTitle']!, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(t['batchReviewDesc']!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55),
                      )),
              const SizedBox(height: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final task in longTermTasks)
                      CheckboxListTile(
                        value: selected.contains(task.id),
                        onChanged: (v) => setSheetState(() =>
                            v == true ? selected.add(task.id) : selected.remove(task.id)),
                        title: Text(task.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                        secondary: const Icon(Icons.call_split, color: Color(0xFFF59E0B)),
                        dense: true,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: busy ? null : () => Navigator.pop(sheetContext),
                      child: Text(t['skipBatch']!),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: busy || selected.isEmpty
                          ? null
                          : () async {
                              setSheetState(() => busy = true);
                              try {
                                final picked = longTermTasks.where((task) => selected.contains(task.id)).toList();
                                final results = await store.ai.decomposeBatch(
                                  taskTitles: picked.map((task) => task.title).toList(),
                                  config: store.aiConfig,
                                  language: store.settings.language,
                                );
                                for (final task in picked) {
                                  final match = results.where((r) => r.originalTitle == task.title).firstOrNull;
                                  if (match != null && match.subtasks.isNotEmpty) {
                                    store.appendSubtasks(
                                      task.id,
                                      match.subtasks
                                          .map((s) => SubTask(
                                                id: '${task.id}-${s.hashCode}',
                                                title: s,
                                              ))
                                          .toList(),
                                    );
                                  }
                                }
                                if (sheetContext.mounted) Navigator.pop(sheetContext);
                              } catch (e) {
                                setSheetState(() => busy = false);
                                if (sheetContext.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('${t['error']}: $e'), width: 460),
                                  );
                                }
                              }
                            },
                      icon: busy
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.auto_awesome),
                      label: Text(busy ? t['processingBatch']! : '${t['processBatch']} (${selected.length})'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Task edit sheet: title, deadline, quadrant.
Future<void> showTaskEditSheet(BuildContext context, Task task) async {
  final store = context.read<Store>();
  final t = store.t;
  final titleController = TextEditingController(text: task.title);
  var quadrant = task.quadrant;
  DateTime? deadline =
      task.deadline == null ? null : DateTime.fromMillisecondsSinceEpoch(task.deadline!);

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (sheetContext, setSheetState) => Padding(
        padding: EdgeInsets.fromLTRB(
            16, 16, 16, MediaQuery.of(sheetContext).viewInsets.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t['editTask']!, style: Theme.of(sheetContext).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            TextField(
              controller: titleController,
              autofocus: true,
              maxLines: 2,
              decoration: InputDecoration(hintText: t['inputPlaceholderManual']),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_month, size: 18),
                    label: Text(() {
                      final d = deadline;
                      return d == null
                          ? t['setDeadline']!
                          : '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
                    }()),
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: sheetContext,
                        initialDate: deadline ?? DateTime.now(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) setSheetState(() => deadline = picked);
                    },
                  ),
                ),
                if (deadline != null)
                  IconButton(
                    tooltip: t['cancel'],
                    icon: const Icon(Icons.clear),
                    onPressed: () => setSheetState(() => deadline = null),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(t['quadrant']!, style: Theme.of(sheetContext).textTheme.labelMedium),
            const SizedBox(height: 6),
            SegmentedButton<int>(
              segments: [
                for (final q in allQuadrants)
                  ButtonSegment(
                    value: q,
                    label: Text(t['q${q}Short']!),
                  ),
              ],
              selected: {quadrant},
              onSelectionChanged: (s) => setSheetState(() => quadrant = s.first),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
              icon: const Icon(Icons.check),
              label: Text(t['confirm']!),
              onPressed: () {
                final title = titleController.text.trim();
                if (title.isEmpty) return;
                final d = deadline;
                task.title = title;
                task.quadrant = quadrant;
                task.deadline = d == null
                    ? null
                    : DateTime(d.year, d.month, d.day).millisecondsSinceEpoch;
                store.updateTask(task);
                Navigator.pop(sheetContext);
              },
            ),
          ],
        ),
      ),
    ),
  );
}

/// Fade+scale wrapper used by suggestion dialogs.
class ScaleIn extends StatelessWidget {
  final Widget child;
  const ScaleIn({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: 1),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutBack,
      builder: (context, v, child) => Transform.scale(
        scale: 0.92 + 0.08 * v,
        child: Opacity(opacity: v.clamp(0, 1), child: child),
      ),
      child: child,
    );
  }
}
