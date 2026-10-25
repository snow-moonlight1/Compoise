import 'package:flutter/material.dart';

import 'accessible_tap_target.dart';

enum TaskHierarchyLevel { parent, child }

abstract final class TaskHierarchyStyle {
  static const double hitTargetSize = AccessibleTapTarget.minTouchTarget;

  /// Painted box, not the hit target. Tasks.org puts an 18dp glyph
  /// (the 24dp outline icon, inset to 18) beside a 16sp title. Parent
  /// titles here are 16 and children are 14, so the boxes are 18 and 16.
  static const double parentCheckboxVisualSize = 18;
  static const double childCheckboxVisualSize = 16;
  static const double parentTitleSize = 16;
  static const double childTitleSize = 14;

  static double checkboxVisualSize(TaskHierarchyLevel level) =>
      level == TaskHierarchyLevel.parent
          ? parentCheckboxVisualSize
          : childCheckboxVisualSize;

  static double titleSize(TaskHierarchyLevel level) =>
      level == TaskHierarchyLevel.parent ? parentTitleSize : childTitleSize;
}

/// Names the completion box by level and task, so a card with subtasks does not
/// announce every box as the same untitled "Mark task complete".
String taskCheckboxLabel({
  required Map<String, String> t,
  required TaskHierarchyLevel level,
  required bool value,
  required String title,
}) {
  final role = level == TaskHierarchyLevel.parent
      ? (t['a11yRoleParent'] ?? 'parent task')
      : (t['a11yRoleSubtask'] ?? 'subtask');
  final template = value
      ? (t['a11yMarkIncomplete'] ?? 'Mark {role} "{title}" incomplete')
      : (t['a11yMarkComplete'] ?? 'Mark {role} "{title}" complete');
  return template.replaceAll('{role}', role).replaceAll('{title}', title);
}

/// Stable label for the subtask toggle: `expanded` carries the state, so the
/// label names the section and its progress instead of repeating "expand".
String subtaskToggleLabel({
  required Map<String, String> t,
  required String title,
  required int done,
  required int total,
}) =>
    (t['a11ySubtaskToggle'] ?? 'Subtasks of "{title}", {done} of {total} done')
        .replaceAll('{title}', title)
        .replaceAll('{done}', '$done')
        .replaceAll('{total}', '$total');

/// Completion control with distinct parent/child paint sizes and a 48dp,
/// keyboard-operable hit box.
class TaskHierarchyCheckbox extends StatelessWidget {
  const TaskHierarchyCheckbox({
    super.key,
    required this.level,
    required this.value,
    required this.onChanged,
    this.semanticsLabel,
    this.hitTargetKey,
    this.visualKey,
  });

  final TaskHierarchyLevel level;
  final bool value;
  final ValueChanged<bool> onChanged;
  final String? semanticsLabel;
  final Key? hitTargetKey;
  final Key? visualKey;

  @override
  Widget build(BuildContext context) {
    final visualSize = TaskHierarchyStyle.checkboxVisualSize(level);
    final paintScale = visualSize / Checkbox.width;

    return AccessibleTapTarget(
      hitTargetKey: hitTargetKey,
      minSide: TaskHierarchyStyle.hitTargetSize,
      semanticsLabel: semanticsLabel,
      checked: value,
      onTap: () => onChanged(!value),
      child: Transform.scale(
        key: visualKey,
        scale: paintScale,
        child: SizedBox.square(
          dimension: Checkbox.width,
          child: ExcludeFocus(
            // The real Checkbox is paint only: left interactive it would add a
            // second Tab stop on top of the 48dp target that wraps it.
            child: IgnorePointer(
              child: Checkbox(
                value: value,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.standard,
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
  }
}
