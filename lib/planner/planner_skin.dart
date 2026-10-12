import 'package:flutter/material.dart';

import '../theme.dart';

/// The planner's own surfaces (blocks, bars, buttons, circles) follow the
/// active skin through the same theme extensions the home page reads:
/// [ComicOutline] (flat, 2dp ink outline, no shadow) and [NeumorphicSkin]
/// (slab colour, light/dark shadow pair). With neither, every method returns
/// its input unchanged, so the default look is untouched.
class PlannerSkin {
  const PlannerSkin._(this.comic, this.neu);

  final ComicOutline? comic;
  final NeumorphicSkin? neu;

  static PlannerSkin of(BuildContext context) => PlannerSkin._(
    ComicOutline.maybeOf(context),
    NeumorphicSkin.maybeOf(context),
  );

  bool get plain => comic == null && neu == null;

  /// Smaller pair than a home-page button: planner pieces sit close together.
  List<BoxShadow> get _raised => [
    BoxShadow(
      color: neu!.lightShadow,
      offset: const Offset(-2, -2),
      blurRadius: 4,
    ),
    BoxShadow(
      color: neu!.darkShadow,
      offset: const Offset(2, 2),
      blurRadius: 4,
    ),
  ];

  /// Restyles [base]. [raised] false means sunk (neumorphic groove) or flat;
  /// [selected] thickens the comic outline and keeps a neumorphic accent edge.
  BoxDecoration surface(
    BoxDecoration base, {
    bool raised = true,
    bool selected = false,
  }) {
    if (comic != null) {
      return base.copyWith(
        color: base.color ?? comic!.field,
        border: Border.all(color: comic!.edge, width: selected ? 3 : 2),
        boxShadow: const <BoxShadow>[],
      );
    }
    if (neu != null) {
      // copyWith cannot clear a border, so build the decoration afresh.
      return BoxDecoration(
        color: raised ? (base.color ?? neu!.canvas) : neu!.groove,
        border: selected ? base.border : null,
        borderRadius: base.borderRadius,
        shape: base.shape,
        boxShadow: raised ? _raised : const <BoxShadow>[],
      );
    }
    return base;
  }

  /// Thin grid / axis lines: comic's edge colour is ink, far too heavy for a
  /// hairline, so it is softened there.
  Color hairline(ThemeData theme) => comic != null
      ? comic!.edge.withValues(alpha: 0.35)
      : theme.colorScheme.outlineVariant;

  /// Text colour that stays readable on a tinted block in any skin.
  Color? ink(ThemeData theme) => comic?.ink ?? neu?.ink;
}
