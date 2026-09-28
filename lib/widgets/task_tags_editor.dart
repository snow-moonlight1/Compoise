import 'package:flutter/material.dart';

import '../task_tags.dart';

/// Tag editor for a task draft.
///
/// The widget holds no task data: it renders [value] and reports the next list
/// through [onChanged], so the caller keeps the draft, its dirty state, cancel
/// and save, and decides where the tags are written. [value] is never mutated.
///
/// Adding a tag the draft already carries — in any spelling — or a blank one
/// reports nothing, so a repeated entry does not make a draft look edited. Every
/// emitted list is normalised: trimmed, without blanks, and with the first
/// spelling kept for a case-equivalent duplicate.
class TaskTagsEditor extends StatefulWidget {
  final List<String> value;
  final ValueChanged<List<String>> onChanged;
  final Map<String, String> t;

  const TaskTagsEditor({
    super.key,
    required this.value,
    required this.onChanged,
    required this.t,
  });

  @override
  State<TaskTagsEditor> createState() => _TaskTagsEditorState();
}

class _TaskTagsEditorState extends State<TaskTagsEditor> {
  final TextEditingController _input = TextEditingController();
  final FocusNode _focus = FocusNode();

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _add(String raw) {
    final current = normalizeTags(widget.value);
    final next = normalizeTags([...current, raw]);
    _input.clear();
    if (!sameTagList(next, current)) widget.onChanged(next);
    if (mounted) _focus.requestFocus();
  }

  void _remove(String tag) {
    final key = tagKey(tag);
    widget.onChanged([
      for (final item in normalizeTags(widget.value))
        if (tagKey(item) != key) item,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final tags = normalizeTags(widget.value);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (tags.isNotEmpty)
          Wrap(
            key: const ValueKey('task-tags-list'),
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final tag in tags)
                Chip(
                  key: ValueKey('task-tag-$tag'),
                  label: Text(tag),
                  onDeleted: () => _remove(tag),
                  deleteIcon: Tooltip(
                    message: (t['tagRemove'] ?? 'Remove {tag}').replaceAll(
                      '{tag}',
                      tag,
                    ),
                    child: const Icon(Icons.close, size: 18),
                  ),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
            ],
          ),
        TextField(
          key: const ValueKey('task-tag-input'),
          controller: _input,
          focusNode: _focus,
          textInputAction: TextInputAction.done,
          onSubmitted: _add,
          decoration: InputDecoration(
            isDense: true,
            hintText: t['tagPlaceholder'] ?? 'Tag name',
            prefixIcon: const Icon(Icons.sell_outlined, size: 20),
            suffixIcon: IconButton(
              key: const ValueKey('task-tag-add'),
              tooltip: t['addTag'] ?? 'Add tag',
              onPressed: () => _add(_input.text),
              icon: const Icon(Icons.add),
            ),
          ),
        ),
      ],
    );
  }
}
