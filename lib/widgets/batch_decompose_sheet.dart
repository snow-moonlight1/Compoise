import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../ai_service.dart';
import '../models.dart';
import '../storage.dart';

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
