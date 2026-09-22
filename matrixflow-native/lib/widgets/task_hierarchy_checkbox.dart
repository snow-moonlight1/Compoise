import 'package:flutter/material.dart';

enum TaskHierarchyLevel { parent, child }

abstract final class TaskHierarchyStyle {
  static const double hitTargetSize = 48;
  static const double parentCheckboxVisualSize = 22;
  static const double childCheckboxVisualSize = 18;
  static const double parentTitleSize = 16;
  static const double childTitleSize = 14;

  static double checkboxVisualSize(TaskHierarchyLevel level) =>
      level == TaskHierarchyLevel.parent
          ? parentCheckboxVisualSize
          : childCheckboxVisualSize;

  static double titleSize(TaskHierarchyLevel level) =>
      level == TaskHierarchyLevel.parent ? parentTitleSize : childTitleSize;
}

/// Completion control with distinct parent/child paint sizes and a 48dp hit box.
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

    return Semantics(
      label: semanticsLabel,
      checked: value,
      container: true,
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: TaskHierarchyStyle.hitTargetSize,
        child: GestureDetector(
          key: hitTargetKey,
          behavior: HitTestBehavior.opaque,
          onTap: () => onChanged(!value),
          child: Center(
            child: Transform.scale(
              key: visualKey,
              scale: paintScale,
              child: SizedBox.square(
                dimension: Checkbox.width,
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
        ),
      ),
    );
  }
}
