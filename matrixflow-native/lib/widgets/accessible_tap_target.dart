import 'package:flutter/material.dart';

import '../ui/platform_ui_policy.dart';

/// Shape of the keyboard focus ring drawn around an [AccessibleTapTarget].
enum AccessibleTapTargetRing { roundedRect, circle }

/// Gives a compact control a 48dp touch target, a visible keyboard focus ring
/// and `Enter`/`Space` activation without enlarging what it paints: only the hit
/// box grows, [child] keeps its own visual size.
///
/// The state lives in exactly one semantic node. [checked] and [selected] carry
/// it while [semanticsLabel] names the target, and descendants are excluded so
/// the widget being painted cannot contribute a second announcement.
class AccessibleTapTarget extends StatefulWidget {
  const AccessibleTapTarget({
    super.key,
    required this.onTap,
    required this.child,
    this.minSide = minTouchTarget,
    this.hitTargetKey,
    this.semanticsLabel,
    this.checked,
    this.selected,
    this.inMutuallyExclusiveGroup = false,
    this.ring = AccessibleTapTargetRing.roundedRect,
    this.ringInset = 2,
  });

  static const double minTouchTarget = PlatformUiPolicy.minActionSize;

  final VoidCallback onTap;
  final Widget child;
  final double minSide;
  final Key? hitTargetKey;
  final String? semanticsLabel;
  final bool? checked;
  final bool? selected;
  final bool inMutuallyExclusiveGroup;
  final AccessibleTapTargetRing ring;
  final double ringInset;

  @override
  State<AccessibleTapTarget> createState() => _AccessibleTapTargetState();
}

class _AccessibleTapTargetState extends State<AccessibleTapTarget> {
  static const double _ringStroke = 2.5;

  bool _showFocusRing = false;
  bool _hasFocus = false;

  void _invoke() => widget.onTap();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FocusableActionDetector(
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            _invoke();
            return null;
          },
        ),
        ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(
          onInvoke: (_) {
            _invoke();
            return null;
          },
        ),
      },
      onShowFocusHighlight: (show) {
        if (_showFocusRing != show) setState(() => _showFocusRing = show);
      },
      onFocusChange: (hasFocus) {
        if (_hasFocus != hasFocus) setState(() => _hasFocus = hasFocus);
      },
      mouseCursor: SystemMouseCursors.click,
      child: Semantics(
        container: true,
        button: true,
        checked: widget.checked,
        selected: widget.selected,
        inMutuallyExclusiveGroup: widget.inMutuallyExclusiveGroup,
        focusable: true,
        focused: _hasFocus,
        label: widget.semanticsLabel,
        excludeSemantics: true,
        onTap: _invoke,
        child: GestureDetector(
          key: widget.hitTargetKey,
          behavior: HitTestBehavior.opaque,
          onTap: _invoke,
          child: CustomPaint(
            foregroundPainter: _showFocusRing
                ? _FocusRingPainter(
                    color: theme.colorScheme.onSurface,
                    inset: widget.ringInset,
                    circle: widget.ring == AccessibleTapTargetRing.circle,
                    strokeWidth: _ringStroke,
                  )
                : null,
            child: SizedBox.square(
              dimension: widget.minSide,
              child: Center(child: widget.child),
            ),
          ),
        ),
      ),
    );
  }
}

class _FocusRingPainter extends CustomPainter {
  const _FocusRingPainter({
    required this.color,
    required this.inset,
    required this.circle,
    required this.strokeWidth,
  });

  final Color color;
  final double inset;
  final bool circle;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final outset = inset + strokeWidth / 2;
    final rect = Rect.fromLTRB(
      outset,
      outset,
      size.width - outset,
      size.height - outset,
    );
    if (rect.width <= 0 || rect.height <= 0) return;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = color;
    if (circle) {
      canvas.drawOval(rect, paint);
    } else {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(8)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_FocusRingPainter old) =>
      old.color != color ||
      old.inset != inset ||
      old.circle != circle ||
      old.strokeWidth != strokeWidth;
}
