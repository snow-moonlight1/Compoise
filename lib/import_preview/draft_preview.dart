import 'package:flutter/material.dart';

import '../l10n.dart';
import '../models.dart' show Language;
import '../ui/platform_ui_policy.dart';
import '../widgets/app_notice.dart';
import 'draft_model.dart';

/// Only the final detached selection is submitted. Editing never writes data.
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
  final Map<String, TextEditingController> _titles = {};
  final Set<String> _expanded = {};
  bool _submitting = false, _cancelled = false, _submitted = false;
  String t(String key) => dictOf(widget.language)[key]!;
  @override
  void dispose() {
    for (final controller in _titles.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _cancel() {
    if (_submitting || _cancelled || _submitted) return;
    _cancelled = true;
    widget.onCancel();
  }

  bool get _hasBoard => widget.boards.any((b) => b.id == widget.batch.boardId);
  Future<void> _submit() async {
    if (_submitting ||
        _cancelled ||
        _submitted ||
        !_hasBoard ||
        !widget.batch.canSubmit) {
      return;
    }
    final submission = widget.batch.snapshot();
    setState(() => _submitting = true);
    try {
      await widget.onSubmit(submission);
      _submitted = true;
    } catch (_) {
      if (mounted && !_cancelled) {
        showAppNotice(context, t('importSubmitFailed'));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _bounded(Widget child) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 760),
      child: child,
    ),
  );
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_submitting,
    onPopInvokedWithResult: (didPop, _) {
      // The route is already gone. Only the explicit button requests a pop.
      if (didPop) _cancelled = true;
    },
    child: SafeArea(
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              key: const ValueKey('import-review-scroll'),
              padding: const EdgeInsets.all(16),
              child: _bounded(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        t('importReviewTitle'),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(t('importReviewHint')),
                    const SizedBox(height: 16),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        if (PlatformUiPolicy.of(context).isDesktop &&
                            constraints.maxWidth >= 600) {
                          return Row(
                            children: [
                              Expanded(child: _boardField()),
                              const SizedBox(width: 12),
                              Expanded(child: _quadrantField()),
                            ],
                          );
                        }
                        return Column(
                          children: [
                            _boardField(),
                            const SizedBox(height: 12),
                            _quadrantField(),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    for (var i = 0; i < widget.batch.images.length; i++) ...[
                      _imageCard(widget.batch.images[i], i),
                      const SizedBox(height: 12),
                    ],
                  ],
                ),
              ),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: _bounded(
              Row(
                children: [
                  OutlinedButton(
                    key: const ValueKey('import-cancel'),
                    onPressed: _submitting ? null : _cancel,
                    child: Text(t('cancel')),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      key: const ValueKey('import-submit'),
                      onPressed:
                          !_submitting &&
                              !_cancelled &&
                              !_submitted &&
                              _hasBoard &&
                              widget.batch.canSubmit
                          ? _submit
                          : null,
                      child: Text(
                        _submitting
                            ? t('processing')
                            : t('importSubmit').replaceAll(
                                '{count}',
                                '${widget.batch.activeTasks.length}',
                              ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
  Widget _boardField() => DropdownButtonFormField<String>(
    key: const ValueKey('import-board'),
    isExpanded: true,
    decoration: InputDecoration(labelText: t('importBoard')),
    value: _hasBoard ? widget.batch.boardId : null,
    items: [
      for (final board in widget.boards)
        DropdownMenuItem(
          value: board.id,
          child: Text(board.name, overflow: TextOverflow.ellipsis),
        ),
    ],
    onChanged: _submitting
        ? null
        : (value) => setState(() => widget.batch.boardId = value),
  );
  Widget _quadrantField() => DropdownButtonFormField<int>(
    key: const ValueKey('import-quadrant'),
    isExpanded: true,
    decoration: InputDecoration(labelText: t('importQuadrant')),
    value: widget.batch.quadrant,
    items: [
      for (var q = 1; q <= 4; q++)
        DropdownMenuItem(
          value: q,
          child: Text(t('q${q}Short'), overflow: TextOverflow.ellipsis),
        ),
    ],
    onChanged: _submitting
        ? null
        : (value) => setState(() => widget.batch.quadrant = value),
  );
  bool _isOther(DraftTask task) =>
      task.excluded &&
      task.reviewReasons.any((reason) => reason.startsWith('dropped '));
  bool _isDuplicate(DraftTask task) => widget.batch.duplicates.any(
    (hint) =>
        hint.imageIds.contains(task.imageId) &&
        widget.batch.images.any(
          (image) =>
              image.id != task.imageId &&
              hint.imageIds.contains(image.id) &&
              image.tasks.any(
                (other) => other.title.trim() == task.title.trim(),
              ),
        ),
  );
  Widget _imageCard(DraftImage image, int index) {
    final theme = Theme.of(context);
    final thumbnail = widget.thumbnails[image.id];
    final others = image.tasks.where(_isOther).toList();
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
                    padding: const EdgeInsets.only(right: 8),
                    child: Image(
                      image: thumbnail,
                      width: 36,
                      height: 48,
                      fit: BoxFit.cover,
                      semanticLabel: '${t('importImage')} ${index + 1}',
                    ),
                  ),
                Expanded(
                  child: Text(
                    '${t('importImage')} ${index + 1}',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  key: ValueKey('image-up-${image.id}'),
                  tooltip: t('importMoveEarlier'),
                  onPressed: _submitting || index == 0
                      ? null
                      : () => setState(
                          () => widget.batch.moveImage(index, index - 1),
                        ),
                  icon: const Icon(Icons.arrow_upward),
                ),
                IconButton(
                  key: ValueKey('image-down-${image.id}'),
                  tooltip: t('importMoveLater'),
                  onPressed:
                      _submitting || index == widget.batch.images.length - 1
                      ? null
                      : () => setState(
                          () => widget.batch.moveImage(index, index + 1),
                        ),
                  icon: const Icon(Icons.arrow_downward),
                ),
              ],
            ),
            if (image.failed)
              Text(
                image.error!,
                style: TextStyle(color: theme.colorScheme.error),
              )
            else ...[
              SwitchListTile(
                key: ValueKey('image-skip-${image.id}'),
                contentPadding: EdgeInsets.zero,
                title: Text(t('importSkipImage')),
                value: image.skipped,
                onChanged: _submitting
                    ? null
                    : (value) => setState(() => image.skipped = value),
              ),
              if (!image.skipped) ...[
                for (final task in image.tasks.where((task) => !_isOther(task)))
                  _taskCard(image, task),
                if (image.tasks.isEmpty) Text(t('importNoteNoRows')),
                if (others.isNotEmpty)
                  ExpansionTile(
                    key: ValueKey('import-other-${image.id}'),
                    tilePadding: EdgeInsets.zero,
                    title: Text(
                      t(
                        'importOtherText',
                      ).replaceAll('{count}', '${others.length}'),
                    ),
                    children: [
                      for (final task in others) _taskCard(image, task),
                    ],
                  ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _taskCard(DraftImage image, DraftTask task) {
    final preceding = image.tasks
        .take(image.tasks.indexOf(task))
        .where((candidate) => !candidate.excluded)
        .toList();
    final parents = preceding.where((candidate) => candidate.parentId == null);
    final expanded = _expanded.contains(task.id);
    return Padding(
      key: ValueKey('task-${task.id}'),
      padding: EdgeInsets.only(top: 8, left: task.parentId == null ? 0 : 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Checkbox(
                key: ValueKey('exclude-${task.id}'),
                semanticLabel: t(
                  'importSelectTask',
                ).replaceAll('{title}', task.title),
                value: !task.excluded,
                onChanged: _submitting
                    ? null
                    : (value) => setState(
                        () => widget.batch.setExcluded(task, value != true),
                      ),
              ),
              Expanded(
                child: TextFormField(
                  key: ValueKey('title-${task.id}'),
                  controller: _titles.putIfAbsent(
                    task.id,
                    () => TextEditingController(text: task.title),
                  ),
                  maxLines: null,
                  readOnly: _submitting,
                  decoration: InputDecoration(
                    hintText: t('importTaskTitle'),
                    errorText: !task.excluded && !task.hasValidTitle
                        ? t('importEmptyTitle')
                        : null,
                  ),
                  onChanged: (value) => setState(() => task.title = value),
                ),
              ),
              IconButton(
                key: ValueKey('options-${task.id}'),
                tooltip: t('importTaskOptions'),
                isSelected: expanded,
                onPressed: _submitting
                    ? null
                    : () => setState(() {
                        if (!_expanded.add(task.id)) _expanded.remove(task.id);
                      }),
                icon: const Icon(Icons.more_horiz),
              ),
            ],
          ),
          if (_isDuplicate(task) || task.checked)
            Padding(
              padding: const EdgeInsets.only(left: 48, top: 4),
              child: Text(
                [
                  if (_isDuplicate(task)) t('importDuplicate'),
                  if (task.checked) t('importCompleted'),
                ].join(' · '),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (expanded) ...[
            const SizedBox(height: 12),
            CheckboxListTile(
              key: ValueKey('checked-${task.id}'),
              contentPadding: EdgeInsets.zero,
              value: task.checked,
              title: Text(t('importCompleted')),
              onChanged: _submitting
                  ? null
                  : (value) => setState(() => task.checked = value ?? false),
            ),
            DropdownButtonFormField<String>(
              key: ValueKey('parent-${task.id}'),
              isExpanded: true,
              decoration: InputDecoration(labelText: t('importParent')),
              value: parents.any((candidate) => candidate.id == task.parentId)
                  ? task.parentId
                  : '',
              items: [
                DropdownMenuItem(value: '', child: Text(t('importNoParent'))),
                for (final candidate in parents)
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
              const SizedBox(height: 12),
              TextFormField(
                key: ValueKey('due-${task.id}'),
                initialValue: task.dueText,
                readOnly: _submitting,
                decoration: InputDecoration(labelText: t('importDateText')),
                onChanged: (value) => setState(() => task.dueText = value),
              ),
              CheckboxListTile(
                key: ValueKey('keep-due-${task.id}'),
                contentPadding: EdgeInsets.zero,
                title: Text(t('importKeepDateText')),
                value: task.keepDueText,
                onChanged: _submitting
                    ? null
                    : (value) =>
                          setState(() => task.keepDueText = value ?? false),
              ),
            ],
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
                            _titles[task.id]!.text = task.title;
                          }
                        }),
                  child: Text(t('importSplit')),
                ),
                TextButton(
                  key: ValueKey('merge-${task.id}'),
                  onPressed: _submitting || preceding.isEmpty
                      ? null
                      : () => setState(() {
                          FocusScope.of(context).unfocus();
                          final target = preceding.last;
                          if (widget.batch.mergeWithPrevious(task)) {
                            _titles[target.id]?.text = target.title;
                          }
                        }),
                  child: Text(t('importMergePrevious')),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
