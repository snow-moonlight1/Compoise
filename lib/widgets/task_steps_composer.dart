import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'task_edit_draft.dart';

/// A plain-text checklist draft. Newlines split the edited row at the caret;
/// this also handles pasted blocks and selection replacement. Blank rows stay
/// visible while editing, but callers persist only [nonEmptySteps].
class TaskStepsComposer extends StatefulWidget {
  const TaskStepsComposer({
    super.key,
    required this.t,
    required this.onChanged,
    this.enabled = true,
  });

  final Map<String, String> t;
  final VoidCallback onChanged;
  final bool enabled;

  @override
  State<TaskStepsComposer> createState() => TaskStepsComposerState();
}

class _StepRow {
  _StepRow(String text)
    : controller = TextEditingController(text: text),
      focus = FocusNode();

  final TextEditingController controller;
  final FocusNode focus;
  bool wasComposing = false;
  bool ignoreSubmitOnce = false;

  void dispose() {
    controller.dispose();
    focus.dispose();
  }
}

class TaskStepsComposerState extends State<TaskStepsComposer> {
  final List<_StepRow> _rows = [_StepRow('')];
  bool _splitting = false;
  int _lastFocusedIndex = 0;

  List<String> get nonEmptySteps => [
    for (final row in _rows)
      if (row.controller.text.trim().isNotEmpty) row.controller.text.trim(),
  ];

  String get text => _rows.map((row) => row.controller.text).join('\n');
  bool get hasComposition =>
      _rows.any((row) => hasPendingImeComposition(row.controller));
  bool get hasMultipleRows => _rows.length > 1;

  void setText(String value) {
    final previous = List<_StepRow>.of(_rows);
    _rows
      ..clear()
      ..addAll(value.split('\n').map(_StepRow.new));
    if (_rows.isEmpty) _rows.add(_StepRow(''));
    setState(() {});
    widget.onChanged();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final row in previous) {
        row.dispose();
      }
    });
  }

  void clear() => setText('');

  void restoreFocus() {
    if (_rows.isEmpty) return;
    final index = _lastFocusedIndex.clamp(0, _rows.length - 1);
    _focusRow(index, _rows[index].controller.selection.extentOffset);
  }

  void _focusRow(int index, int offset) {
    _lastFocusedIndex = index;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || index >= _rows.length) return;
      final row = _rows[index];
      row.focus.requestFocus();
      row.controller.selection = TextSelection.collapsed(
        offset: offset.clamp(0, row.controller.text.length),
      );
    });
  }

  void _changed(_StepRow row) {
    if (_splitting) return;
    if (hasPendingImeComposition(row.controller)) {
      row.wasComposing = true;
      widget.onChanged();
      return;
    }
    if (row.wasComposing) {
      row.wasComposing = false;
      row.ignoreSubmitOnce = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        row.ignoreSubmitOnce = false;
      });
    }
    final index = _rows.indexOf(row);
    if (index < 0) return;
    final value = row.controller.value;
    if (!value.text.contains('\n')) {
      setState(() {});
      widget.onChanged();
      return;
    }
    final caret = value.selection.extentOffset.clamp(0, value.text.length);
    final beforeCaret = value.text.substring(0, caret);
    final target = '\n'.allMatches(beforeCaret).length;
    final column = beforeCaret.split('\n').last.length;
    final parts = value.text.split('\n');
    _splitting = true;
    row.controller.value = TextEditingValue(
      text: parts.first,
      selection: TextSelection.collapsed(offset: parts.first.length),
    );
    _rows.insertAll(index + 1, parts.skip(1).map(_StepRow.new));
    _splitting = false;
    setState(() {});
    widget.onChanged();
    _focusRow(index + target, column);
  }

  KeyEventResult _key(int index, KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.backspace ||
        index == 0 ||
        _rows[index].controller.text.isNotEmpty ||
        hasPendingImeComposition(_rows[index].controller)) {
      return KeyEventResult.ignored;
    }
    _removeBlank(index);
    return KeyEventResult.handled;
  }

  void _removeBlank(int index) {
    if (index == 0 || _rows[index].controller.text.isNotEmpty) return;
    final previousLength = _rows[index - 1].controller.text.length;
    final removed = _rows.removeAt(index);
    WidgetsBinding.instance.addPostFrameCallback((_) => removed.dispose());
    setState(() {});
    widget.onChanged();
    _focusRow(index - 1, previousLength);
  }

  void _submitRow(_StepRow row) {
    if (hasPendingImeComposition(row.controller) ||
        row.wasComposing ||
        row.ignoreSubmitOnce) {
      row.wasComposing = false;
      row.ignoreSubmitOnce = false;
      return;
    }
    final index = _rows.indexOf(row);
    if (index < 0) return;
    final value = row.controller.value;
    final selection = value.selection;
    final start = selection.isValid ? selection.start : value.text.length;
    final end = selection.isValid ? selection.end : value.text.length;
    final left = value.text.substring(0, start);
    final right = value.text.substring(end);
    row.controller.value = TextEditingValue(
      text: left,
      selection: TextSelection.collapsed(offset: left.length),
    );
    _rows.insert(index + 1, _StepRow(right));
    setState(() {});
    widget.onChanged();
    _focusRow(index + 1, 0);
  }

  @override
  void dispose() {
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var i = 0; i < _rows.length; i++)
        Builder(
          builder: (context) {
            final row = _rows[i];
            return Padding(
              key: ObjectKey(_rows[i]),
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  ExcludeSemantics(
                    child: Checkbox(value: false, onChanged: null),
                  ),
                  Expanded(
                    child: Focus(
                      onKeyEvent: (_, event) => _key(i, event),
                      child: TextField(
                        key: ValueKey('task-step-$i'),
                      onTap: () => _lastFocusedIndex = i,
                        controller: row.controller,
                        focusNode: row.focus,
                        enabled: widget.enabled,
                        autofocus: i == 0,
                        minLines: 1,
                        maxLines: null,
                        keyboardType: TextInputType.multiline,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          hintText: i == 0
                              ? widget.t['inputPlaceholderManual']
                              : widget.t['nextStepHint'],
                          isDense: true,
                          border: InputBorder.none,
                        ),
                        onChanged: (_) => _changed(row),
                        onSubmitted: widget.enabled
                            ? (_) => _submitRow(row)
                            : null,
                      ),
                    ),
                  ),
                  if (i > 0 && _rows[i].controller.text.isEmpty)
                    IconButton(
                      key: ValueKey('remove-empty-step-$i'),
                      tooltip: widget.t['removeEmptyStep'],
                      onPressed: widget.enabled ? () => _removeBlank(i) : null,
                      icon: const Icon(Icons.close, size: 18),
                    ),
                ],
              ),
            );
          },
        ),
    ],
  );
}
