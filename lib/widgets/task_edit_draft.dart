import 'dart:convert';

import 'package:flutter/material.dart';

import '../models.dart';
import '../task_tags.dart';
import 'date_edit_fields.dart';

/// True while an IME composition is still open: the visible text is not yet the
/// text the user intends, so every commit path waits for it to close. Chinese,
/// Japanese and other composing input arrive through this state.
///
/// Only a range that exists *and* holds text is an open composition. Once a
/// candidate is chosen the platform leaves a valid but collapsed caret, and an
/// input that never composed anything reports [TextRange.empty]; neither may
/// hold up a commit, or finished Chinese and Japanese text could never be saved.
bool hasPendingImeComposition(TextEditingController controller) {
  final composing = controller.value.composing;
  return composing.isValid && !composing.isCollapsed;
}

/// One task's unsaved edit: the field controllers, the snapshot taken when the
/// editor opened, and the rules that decide what counts as a change and what a
/// save writes back. It never touches the Store, and the widget that owns a
/// draft disposes it.
///
/// The subtask composer belongs to the draft even before its row exists:
/// * Text there that was never added counts as an unsaved change, so closing
///   and switching task have to pass the discard prompt instead of losing it.
/// * A save turns it into a real subtask row, so saving never drops it.
/// * A discard drops it together with the rest of the draft.
/// * Pointing the draft at another task clears it, so it can never be added to
///   a different task.
class TaskEditDraft {
  /// [onChanged] fires for user edits only, never while [load] fills the
  /// fields, so a host can refresh and re-read dirtiness from one callback.
  TaskEditDraft(Task task, {required this.onChanged}) {
    titleController.addListener(_handleTextChanged);
    notesController.addListener(_handleTextChanged);
    newSubtaskController.addListener(_handleTextChanged);
    load(task);
  }

  final VoidCallback onChanged;
  final TextEditingController titleController = TextEditingController();
  final TextEditingController notesController = TextEditingController();
  final TextEditingController newSubtaskController = TextEditingController();

  int quadrant = 0;
  DateTime? deadline;
  int? reminderAt;
  bool isLongTerm = false;
  UrgencyMode urgencyMode = UrgencyMode.auto;
  List<SubTask> subtasks = [];
  List<String> tags = [];

  String _initialTitle = '';
  String _initialNotes = '';
  int _initialQuadrant = 0;
  int? _initialDeadlineMs;
  int? _initialReminderAt;
  bool _initialIsLongTerm = false;
  UrgencyMode _initialUrgencyMode = UrgencyMode.auto;
  String _initialSubtasksJson = '[]';
  List<SubTask> _openedSubtasks = [];
  List<String> _initialTags = [];
  bool _discarding = false;
  bool _loading = false;

  String get title => titleController.text.trim();

  bool get hasTitle => title.isNotEmpty;

  String? get notes {
    final text = notesController.text.trim();
    return text.isEmpty ? null : notesController.text;
  }

  /// A deadline is a civil day, stored as the end of that day.
  int? get deadlineMs => endOfCivilDayMs(deadline);

  /// Text in the composer row that has not become a subtask yet.
  String get pendingSubtaskTitle => newSubtaskController.text.trim();

  /// A composer row holding only whitespace is nothing the user meant to keep.
  bool get hasPendingSubtask => pendingSubtaskTitle.isNotEmpty;

  /// A close already decided by a save, delete or discard does not ask again.
  bool get isDiscarding => _discarding;

  void markDiscarding() => _discarding = true;

  bool get isDirty {
    if (_discarding) return false;
    if (title != _initialTitle.trim()) return true;
    if ((notes ?? '').trim() != _initialNotes.trim()) return true;
    if (quadrant != _initialQuadrant) return true;
    if (!_sameDayMs(deadlineMs, _initialDeadlineMs)) return true;
    if (reminderAt != _initialReminderAt) return true;
    if (isLongTerm != _initialIsLongTerm) return true;
    if (urgencyMode != _initialUrgencyMode) return true;
    if (_subtasksJson(subtasks) != _initialSubtasksJson) return true;
    if (!sameTagList(tags, _initialTags)) return true;
    if (hasPendingSubtask) return true;
    return false;
  }

  /// Takes [task]'s values as the new baseline. Used when the panel is kept
  /// alive and pointed at another task.
  void load(Task task) {
    _loading = true;
    titleController.text = task.title;
    notesController.text = task.notesMarkdown ?? '';
    // A half-written subtask belongs to the task that is being left, never to
    // [task]: clearing here is what keeps it from landing on the wrong parent.
    newSubtaskController.clear();
    quadrant = task.quadrant;
    deadline = task.deadline == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(task.deadline!);
    reminderAt = task.reminderAt;
    isLongTerm = task.isLongTerm;
    urgencyMode = task.urgencyMode;
    subtasks = _copy(task.subtasks);
    tags = normalizeTags(task.tags);
    _openedSubtasks = _copy(task.subtasks);
    _initialTitle = task.title;
    _initialNotes = task.notesMarkdown ?? '';
    _initialQuadrant = task.quadrant;
    _initialDeadlineMs = task.deadline;
    _initialReminderAt = task.reminderAt;
    _initialIsLongTerm = task.isLongTerm;
    _initialUrgencyMode = task.urgencyMode;
    _initialSubtasksJson = _subtasksJson(task.subtasks);
    _initialTags = normalizeTags(task.tags);
    _discarding = false;
    _loading = false;
  }

  /// Adds a subtask from the composer row, or null when there is nothing to add.
  SubTask? takeNewSubtask() {
    final text = pendingSubtaskTitle;
    if (text.isEmpty) return null;
    final subtask = SubTask(id: newId(), title: text);
    newSubtaskController.clear();
    subtasks.add(subtask);
    return subtask;
  }

  /// Writes the draft onto the [current] live task. Fields the draft did not
  /// change keep whatever the Store holds, so an edit that started before
  /// someone else saved cannot overwrite their newer values.
  Task applyTo(Task current) {
    final draftTitle = title;
    final draftNotes = notes;
    final titleChanged = draftTitle != _initialTitle.trim();
    final notesChanged = (draftNotes ?? '').trim() != _initialNotes.trim();
    return Task.fromJson(current.toJson())
      ..title = titleChanged ? draftTitle : current.title
      ..notesMarkdown = notesChanged ? draftNotes : current.notesMarkdown
      ..quadrant = quadrant != _initialQuadrant ? quadrant : current.quadrant
      ..deadline = !_sameDayMs(deadlineMs, _initialDeadlineMs)
          ? deadlineMs
          : current.deadline
      ..reminderAt = reminderAt != _initialReminderAt
          ? reminderAt
          : current.reminderAt
      ..isLongTerm = isLongTerm != _initialIsLongTerm
          ? isLongTerm
          : current.isLongTerm
      ..urgencyMode = urgencyMode != _initialUrgencyMode
          ? urgencyMode
          : current.urgencyMode
      ..subtasks = _mergedSubtasks(current.subtasks)
      ..tags = _mergedTags(current.tags);
  }

  /// Apply only tag additions and removals made in this draft. A tag added to
  /// the live task while this editor was open survives a save of other fields.
  List<String> _mergedTags(List<String> current) {
    if (sameTagList(tags, _initialTags)) return normalizeTags(current);
    final initialKeys = tagKeys(_initialTags);
    final draftKeys = tagKeys(tags);
    final removed = initialKeys.difference(draftKeys);
    final result = <String>[
      for (final tag in normalizeTags(current))
        if (!removed.contains(tagKey(tag))) tag,
    ];
    final resultKeys = tagKeys(result);
    for (final tag in normalizeTags(tags)) {
      final key = tagKey(tag);
      if (!initialKeys.contains(key) && resultKeys.add(key)) result.add(tag);
    }
    return result;
  }

  /// Untouched rows follow the live task; edited rows keep the edit and pick up
  /// only the fields nobody changed under it, such as a completion from a list.
  List<SubTask> _mergedSubtasks(List<SubTask> current) {
    final draftJson = _subtasksJson(subtasks);
    if (draftJson == _initialSubtasksJson) {
      return _copy(current);
    }

    final openedById = {for (final s in _openedSubtasks) s.id: s};
    final currentById = {for (final s in current) s.id: s};
    final result = <SubTask>[];
    final seen = <String>{};

    for (final draft in subtasks) {
      seen.add(draft.id);
      final initial = openedById[draft.id];
      final live = currentById[draft.id];
      if (initial == null) {
        result.add(SubTask.fromJson(draft.toJson()));
        continue;
      }
      if (live == null) continue;
      if (_subJson(draft) == _subJson(initial)) {
        result.add(SubTask.fromJson(live.toJson()));
        continue;
      }
      final merged = SubTask.fromJson(draft.toJson());
      if (draft.title == initial.title) merged.title = live.title;
      if ((draft.notesMarkdown ?? '') == (initial.notesMarkdown ?? '')) {
        merged.notesMarkdown = live.notesMarkdown;
      }
      if (draft.deadline == initial.deadline) merged.deadline = live.deadline;
      if (draft.reminderAt == initial.reminderAt) {
        merged.reminderAt = live.reminderAt;
      }
      if (draft.completed == initial.completed) {
        merged.completed = live.completed;
        merged.completedAt = live.completedAt;
      }
      result.add(merged);
    }

    for (final live in current) {
      if (!seen.contains(live.id) && !openedById.containsKey(live.id)) {
        result.add(SubTask.fromJson(live.toJson()));
      }
    }
    return result;
  }

  void _handleTextChanged() {
    if (_loading) return;
    onChanged();
  }

  void dispose() {
    titleController.removeListener(_handleTextChanged);
    notesController.removeListener(_handleTextChanged);
    newSubtaskController.removeListener(_handleTextChanged);
    titleController.dispose();
    notesController.dispose();
    newSubtaskController.dispose();
  }
}

bool _sameDayMs(int? a, int? b) {
  if (a == null && b == null) return true;
  if (a == null || b == null) return false;
  return isSameCivilDay(
    DateTime.fromMillisecondsSinceEpoch(a),
    DateTime.fromMillisecondsSinceEpoch(b),
  );
}

List<SubTask> _copy(List<SubTask> source) => [
  for (final subtask in source) SubTask.fromJson(subtask.toJson()),
];

String _subtasksJson(List<SubTask> subtasks) =>
    jsonEncode(subtasks.map((s) => s.toJson()).toList());

String _subJson(SubTask subtask) => jsonEncode(subtask.toJson());
