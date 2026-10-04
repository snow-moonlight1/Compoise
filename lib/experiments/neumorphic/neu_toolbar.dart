import 'package:flutter/material.dart';

import 'neu_button.dart';
import 'neu_palette.dart';

class NeuToolbarAction {
  const NeuToolbarAction({
    required this.label,
    required this.icon,
    this.onPressed,
    this.selected = false,
    this.buttonKey,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool selected;
  final Key? buttonKey;
}

/// Title plus actions. Narrow width and large text stack the actions under
/// the title so a 320dp row does not overflow.
class NeuToolbar extends StatelessWidget {
  const NeuToolbar({super.key, required this.title, this.actions = const []});

  final String title;
  final List<NeuToolbarAction> actions;

  @override
  Widget build(BuildContext context) {
    final spec = NeuSpec.of(context);
    final titleStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w700,
      color: spec.styleFor(NeuRole.secondary).foreground,
    );
    final titleWidget = Semantics(
      header: true,
      child: Text(title, softWrap: true, style: titleStyle),
    );
    final actionWidgets = [
      for (final action in actions)
        NeuButton(
          key: action.buttonKey,
          label: action.label,
          role: NeuRole.secondary,
          icon: action.icon,
          selected: action.selected,
          onPressed: action.onPressed,
        ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        final stacked = constraints.maxWidth < 480 || scale >= 2;
        if (stacked || actions.isEmpty) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              titleWidget,
              if (actionWidgets.isNotEmpty) const SizedBox(height: 8),
              ...[
                for (final action in actionWidgets) ...[
                  action,
                  const SizedBox(height: 8),
                ],
              ],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: titleWidget),
            const SizedBox(width: 12),
            SizedBox(
              width: 280,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: actionWidgets,
              ),
            ),
          ],
        );
      },
    );
  }
}
