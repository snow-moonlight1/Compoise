import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models.dart';
import '../storage.dart';
import 'app_notice.dart';

String countProgressLabel(CountProgress progress, Map<String, String> t) =>
    progress.target == null
    ? t['countUnlimitedProgress']!.replaceAll('{n}', '${progress.value}')
    : '${progress.value}/${progress.target}';

/// Separate from the completion checkbox so recording a unit is unambiguous.
class TaskCountAction extends StatelessWidget {
  const TaskCountAction({
    super.key,
    required this.task,
    required this.store,
    required this.onChanged,
  });
  final Task task;
  final Store store;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final progress = task.countProgress;
    if (progress == null) return const SizedBox.shrink();
    final t = store.t;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      children: [
        Text(
          countProgressLabel(progress, t),
          key: ValueKey('count-progress-${task.id}'),
        ),
        if (!task.completed)
          TextButton.icon(
            key: ValueKey('count-add-${task.id}'),
            icon: const Icon(Icons.add, size: 16),
            label: Text(t['countRecord']!),
            onPressed: () {
              final messenger = ScaffoldMessenger.maybeOf(context);
              final undo = store.recordTaskCount(task.id);
              onChanged();
              if (undo != null && messenger != null) {
                showAppNoticeOn(
                  messenger,
                  t['countRecorded']!,
                  actionLabel: t['undo'],
                  onAction: () {
                    store.applyUndo(undo);
                    onChanged();
                  },
                );
              }
            },
          ),
      ],
    );
  }
}

class TaskCountEditor extends StatelessWidget {
  const TaskCountEditor({
    super.key,
    required this.progress,
    required this.t,
    required this.onChanged,
  });
  final CountProgress? progress;
  final Map<String, String> t;
  final ValueChanged<CountProgress?> onChanged;
  @override
  Widget build(BuildContext context) => ListTile(
    key: const ValueKey('edit-count-progress'),
    contentPadding: EdgeInsets.zero,
    leading: const Icon(Icons.exposure_plus_1),
    title: Text(t['countTitle']!),
    subtitle: Text(
      progress == null ? t['countOff']! : countProgressLabel(progress!, t),
    ),
    trailing: const Icon(Icons.chevron_right),
    onTap: () => showDialog<void>(
      context: context,
      builder: (_) =>
          _CountDialog(progress: progress, t: t, onChanged: onChanged),
    ),
  );
}

class _CountDialog extends StatefulWidget {
  const _CountDialog({
    required this.progress,
    required this.t,
    required this.onChanged,
  });
  final CountProgress? progress;
  final Map<String, String> t;
  final ValueChanged<CountProgress?> onChanged;
  @override
  State<_CountDialog> createState() => _CountDialogState();
}

class _CountDialogState extends State<_CountDialog> {
  late int _mode = widget.progress == null
      ? 0
      : widget.progress!.target == null
      ? 2
      : 1;
  late final _target = TextEditingController(
    text: '${widget.progress?.target ?? 50}',
  );
  String? _error;
  @override
  void dispose() {
    _target.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    return AlertDialog(
      title: Text(t['countTitle']!),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<int>(
              key: const ValueKey('count-mode'),
              value: _mode,
              isExpanded: true,
              items: [
                for (final entry in {
                  0: 'countOff',
                  1: 'countFinite',
                  2: 'countUnlimited',
                }.entries)
                  DropdownMenuItem(
                    value: entry.key,
                    child: Text(t[entry.value]!),
                  ),
              ],
              onChanged: (value) => setState(() {
                _mode = value!;
                _error = null;
              }),
            ),
            if (_mode == 1)
              TextField(
                key: const ValueKey('count-target'),
                controller: _target,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: t['countTarget'],
                  errorText: _error,
                ),
              ),
            const SizedBox(height: 12),
            Text(t['countHint']!),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t['cancel']!),
        ),
        FilledButton(
          key: const ValueKey('count-save'),
          onPressed: () {
            final n = int.tryParse(_target.text);
            if (_mode == 1 &&
                (n == null ||
                    n < 1 ||
                    n > CountProgress.maxValue ||
                    n < (widget.progress?.value ?? 0))) {
              setState(() => _error = t['countInvalid']);
              return;
            }
            widget.onChanged(
              _mode == 0
                  ? null
                  : CountProgress(
                      value: widget.progress?.value ?? 0,
                      target: _mode == 1 ? n : null,
                    ),
            );
            Navigator.pop(context);
          },
          child: Text(t['save']!),
        ),
      ],
    );
  }
}
