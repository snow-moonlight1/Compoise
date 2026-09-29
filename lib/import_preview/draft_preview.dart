import 'package:flutter/material.dart';

import '../l10n.dart';
import '../models.dart' show Language;
import 'draft_model.dart';

/// Caller owns [batch] and ephemeral thumbnails. The preview never saves them.
/// [onSubmit] receives a detached snapshot and is invoked at most once.
class DraftPreview extends StatefulWidget {
  final DraftBatch batch;
  final List<ImportBoardChoice> boards;
  final Map<String, ImageProvider> thumbnails;
  final Language language;
  final Future<void> Function(ImportSubmission submission) onSubmit;
  final VoidCallback onCancel;

  const DraftPreview({
    super.key,
    required this.batch,
    required this.boards,
    required this.onSubmit,
    required this.onCancel,
    this.thumbnails = const {},
    this.language = Language.zh,
  });

  @override
  State<DraftPreview> createState() => _DraftPreviewState();
}

class ImportBoardChoice {
  final String id;
  final String name;
  const ImportBoardChoice(this.id, this.name);
}

class _DraftPreviewState extends State<DraftPreview> {
  final Map<String, TextEditingController> _titleControllers = {};
  bool _submitting = false;
  bool _cancelled = false;
  bool _submitted = false;
  String? _error;

  String t(String key) => dictOf(widget.language)[key]!;

  @override
  void dispose() {
    for (final controller in _titleControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _cancel() {
    if (_submitting || _cancelled || _submitted) return;
    _cancelled = true;
    widget.onCancel();
  }

  Future<void> _submit() async {
    if (_submitting || _cancelled || _submitted || !widget.batch.canSubmit) {
      return;
    }
    final submission = widget.batch.snapshot();
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.onSubmit(submission);
      _submitted = true;
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = t('importSubmitFailed');
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final batch = widget.batch;
    final theme = Theme.of(context);
    return PopScope(
      canPop: !_submitting,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _cancel();
      },
      child: SafeArea(
        child: SingleChildScrollView(
          key: const ValueKey('import-review-scroll'),
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            MediaQuery.viewInsetsOf(context).bottom + 24,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      t('importReviewTitle'),
                      style: theme.textTheme.headlineSmall,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(t('importReviewHint')),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    key: const ValueKey('import-board'),
                    isExpanded: true,
                    decoration: InputDecoration(labelText: t('importBoard')),
                    value:
                        widget.boards.any((board) => board.id == batch.boardId)
                        ? batch.boardId
                        : null,
                    items: [
                      for (final board in widget.boards)
                        DropdownMenuItem(
                          value: board.id,
                          child: Text(
                            board.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: _submitting
                        ? null
                        : (value) => setState(() => batch.boardId = value),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    key: const ValueKey('import-quadrant'),
                    isExpanded: true,
                    decoration: InputDecoration(labelText: t('importQuadrant')),
                    value: batch.quadrant,
                    items: [
                      for (var q = 1; q <= 4; q++)
                        DropdownMenuItem(
                          value: q,
                          child: Text(
                            '${t('importQuadrant')} $q · ${t('q${q}Short')}',
                          ),
                        ),
                    ],
                    onChanged: _submitting
                        ? null
                        : (value) => setState(() => batch.quadrant = value),
                  ),
                  const SizedBox(height: 16),
                  for (var i = 0; i < batch.images.length; i++) ...[
                    _imageCard(batch.images[i], i),
                    const SizedBox(height: 12),
                  ],
                  for (var i = 0; i < batch.duplicates.length; i++)
                    _duplicateTile(batch.duplicates[i], i),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        _error!,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ),
                  const SizedBox(height: 16),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton(
                        key: const ValueKey('import-cancel'),
                        onPressed: _submitting ? null : _cancel,
                        child: Text(t('cancel')),
                      ),
                      FilledButton(
                        key: const ValueKey('import-submit'),
                        onPressed:
                            !_submitting &&
                                !_cancelled &&
                                !_submitted &&
                                batch.canSubmit
                            ? _submit
                            : null,
                        child: Text(
                          _submitting ? t('processing') : t('importSubmit'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _imageCard(DraftImage image, int index) {
    final batch = widget.batch;
    final theme = Theme.of(context);
    final thumbnail = widget.thumbnails[image.id];
    return Card(
      key: ValueKey('image-${image.id}'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (thumbnail != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Image(
                        image: thumbnail,
                        width: 48,
                        height: 64,
                        fit: BoxFit.cover,
                        semanticLabel: '${t('importImage')} ${index + 1}',
                      ),
                    ),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${t('importImage')} ${index + 1}',
                        style: theme.textTheme.titleMedium,
                      ),
                      Text(
                        image.failed
                            ? t('importImageFailed')
                            : '${image.tasks.where((task) => !task.excluded).length} ${t('importTasks')}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  key: ValueKey('image-up-${image.id}'),
                  tooltip: t('importMoveEarlier'),
                  onPressed: _submitting || index == 0
                      ? null
                      : () => setState(() => batch.moveImage(index, index - 1)),
                  icon: const Icon(Icons.arrow_upward),
                ),
                IconButton(
                  key: ValueKey('image-down-${image.id}'),
                  tooltip: t('importMoveLater'),
                  onPressed: _submitting || index == batch.images.length - 1
                      ? null
                      : () => setState(() => batch.moveImage(index, index + 1)),
                  icon: const Icon(Icons.arrow_downward),
                ),
              ],
            ),
            if (image.failed) ...[
              const SizedBox(height: 8),
              Text(
                image.error!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ] else ...[
              SwitchListTile(
                key: ValueKey('image-skip-${image.id}'),
                contentPadding: EdgeInsets.zero,
                title: Text(t('importSkipImage')),
                value: image.skipped,
                onChanged: _submitting
                    ? null
                    : (value) => setState(() {
                        image.skipped = value;
                        if (!value) {
                          for (final task in image.tasks) {
                            task.confirmed = false;
                          }
                        }
                      }),
              ),
              if (!image.skipped) ...[
                for (final note in image.notes)
                  Text(note, style: theme.textTheme.bodySmall),
                for (final task in image.tasks) _taskCard(image, task),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _taskCard(DraftImage image, DraftTask task) {
    final theme = Theme.of(context);
    final previous = image.tasks
        .take(image.tasks.indexOf(task))
        .where((candidate) => !candidate.excluded)
        .toList();
    return Padding(
      key: ValueKey('task-${task.id}'),
      padding: const EdgeInsets.only(top: 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                key: ValueKey('title-${task.id}'),
                controller: _titleControllers.putIfAbsent(
                  task.id,
                  () => TextEditingController(text: task.title),
                ),
                maxLines: null,
                decoration: InputDecoration(
                  labelText: t('importTaskTitle'),
                  errorText: !task.excluded && !task.hasValidTitle
                      ? t('importEmptyTitle')
                      : null,
                ),
                onChanged: _submitting
                    ? null
                    : (value) => setState(() {
                        task.title = value;
                        task.confirmed = false;
                      }),
              ),
              CheckboxListTile(
                key: ValueKey('checked-${task.id}'),
                contentPadding: EdgeInsets.zero,
                value: task.checked,
                title: Text(t('importCompleted')),
                onChanged: _submitting
                    ? null
                    : (value) => setState(() {
                        task.checked = value ?? false;
                        task.confirmed = false;
                      }),
              ),
              DropdownButtonFormField<String>(
                key: ValueKey('parent-${task.id}'),
                isExpanded: true,
                decoration: InputDecoration(labelText: t('importParent')),
                value:
                    previous.any((candidate) => candidate.id == task.parentId)
                    ? task.parentId
                    : '',
                items: [
                  DropdownMenuItem(value: '', child: Text(t('importNoParent'))),
                  for (final candidate in previous)
                    DropdownMenuItem(
                      value: candidate.id,
                      child: Text(
                        candidate.title,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: _submitting
                    ? null
                    : (value) => setState(
                        () => widget.batch.setParent(
                          task,
                          value == '' ? null : value,
                        ),
                      ),
              ),
              if (task.dueText != null) ...[
                const SizedBox(height: 8),
                TextFormField(
                  key: ValueKey('due-${task.id}'),
                  initialValue: task.dueText,
                  decoration: InputDecoration(
                    labelText: t('importDateText'),
                    helperText: t('importDateHint'),
                  ),
                  onChanged: _submitting
                      ? null
                      : (value) => setState(() {
                          task.dueText = value;
                          task.confirmed = false;
                        }),
                ),
                CheckboxListTile(
                  key: ValueKey('keep-due-${task.id}'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(t('importKeepDateText')),
                  value: task.keepDueText,
                  onChanged: _submitting
                      ? null
                      : (value) => setState(() {
                          task.keepDueText = value ?? false;
                          task.confirmed = false;
                        }),
                ),
              ],
              for (final reason in task.reviewReasons)
                Text(
                  '${t('importNeedsReview')}: ${_reasonText(reason)}',
                  style: theme.textTheme.bodySmall,
                ),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  TextButton(
                    key: ValueKey('split-${task.id}'),
                    onPressed: _submitting
                        ? null
                        : () => setState(() {
                            if (widget.batch.splitAtNewline(task) != null) {
                              _titleControllers[task.id]!.text = task.title;
                            }
                          }),
                    child: Text(t('importSplit')),
                  ),
                  TextButton(
                    key: ValueKey('merge-${task.id}'),
                    onPressed: _submitting || previous.isEmpty
                        ? null
                        : () => setState(() {
                            FocusScope.of(context).unfocus();
                            final target = previous.last;
                            if (widget.batch.mergeWithPrevious(task)) {
                              _titleControllers[target.id]!.text = target.title;
                            }
                          }),
                    child: Text(t('importMergePrevious')),
                  ),
                ],
              ),
              SwitchListTile(
                key: ValueKey('exclude-${task.id}'),
                contentPadding: EdgeInsets.zero,
                title: Text(
                  task.excluded ? t('importRestore') : t('importExclude'),
                ),
                value: task.excluded,
                onChanged: _submitting
                    ? null
                    : (value) =>
                          setState(() => widget.batch.setExcluded(task, value)),
              ),
              if (!task.excluded)
                CheckboxListTile(
                  key: ValueKey('confirm-${task.id}'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(t('importConfirmTask')),
                  value: task.confirmed,
                  onChanged: _submitting || !task.hasValidTitle
                      ? null
                      : (value) =>
                            setState(() => task.confirmed = value ?? false),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _reasonText(String reason) {
    const keys = <String, String>{
      'date text needs review': 'importReasonDate',
      'indent/parent needs review': 'importReasonParent',
      'parent row is missing or out of order': 'importReasonParentOrder',
      'parent was excluded': 'importReasonParentExcluded',
      'split task needs review': 'importReasonSplit',
      'merged task needs review': 'importReasonMerged',
    };
    final key = keys[reason];
    if (key != null) return t(key);
    const dropped = 'dropped ';
    if (reason.startsWith(dropped)) {
      return '${t('importReasonDropped')}: ${reason.substring(dropped.length)}';
    }
    return reason;
  }

  Widget _duplicateTile(DuplicateHint hint, int index) {
    return CheckboxListTile(
      key: ValueKey('duplicate-$index'),
      title: Text('${t('importDuplicate')}: ${hint.imageIds.join(' / ')}'),
      subtitle: Text(t('importDuplicateHint')),
      value: hint.acknowledged,
      onChanged: _submitting
          ? null
          : (value) => setState(() => hint.acknowledged = value ?? false),
    );
  }
}
