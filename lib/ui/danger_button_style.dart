import 'package:flutter/material.dart';

import '../theme.dart';

/// Style for a destructive confirm button (delete, discard, clear).
///
/// Default and comic themes fill the button with the error color. The
/// neumorphic theme paints its own raised face on a transparent Material, so
/// a background color there shows up as a red plate behind the face; it keeps
/// the neumorphic face and uses red for the label instead.
ButtonStyle dangerButtonStyle(BuildContext context) {
  final theme = Theme.of(context);
  final error = theme.colorScheme.error;
  if (theme.extension<NeumorphicSkin>() != null) {
    return ButtonStyle(
      foregroundColor: WidgetStatePropertyAll(error),
      iconColor: WidgetStatePropertyAll(error),
    );
  }
  return FilledButton.styleFrom(backgroundColor: error);
}
