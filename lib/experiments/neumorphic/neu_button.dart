import 'package:flutter/material.dart';

import 'neu_palette.dart';

/// Primary, secondary, and danger actions for the neumorphic experiment.
///
/// Soft shadows are decorative. Role and state stay visible through fill,
/// border width, marker icons, and the semantics node. High contrast and
/// reduced motion omit the shadow.
class NeuButton extends StatefulWidget {
  const NeuButton({
    super.key,
    required this.label,
    required this.role,
    this.onPressed,
    this.icon,
    this.paint = NeuPaint.live,
    this.selected = false,
    this.errorText,
    this.focusNode,
    this.semanticsLabel,
  });

  static const surfaceKey = Key('uiexp1-neu-surface');
  static const ringKey = Key('uiexp1-neu-ring');
  static const hatchKey = Key('uiexp1-neu-hatch');

  final String label;
  final NeuRole role;
  final VoidCallback? onPressed;
  final IconData? icon;
  final NeuPaint paint;
  final bool selected;
  final String? errorText;
  final FocusNode? focusNode;
  final String? semanticsLabel;

  @override
  State<NeuButton> createState() => _NeuButtonState();
}

class _NeuButtonState extends State<NeuButton> {
  bool _down = false;
  bool _hasFocus = false;

  bool get _disabled =>
      widget.onPressed == null || widget.paint == NeuPaint.disabled;

  void _invoke() {
    if (_disabled) return;
    widget.onPressed!.call();
  }

  @override
  Widget build(BuildContext context) {
    final spec = NeuSpec.of(context);
    final pressed =
        widget.paint == NeuPaint.pressed ||
        (widget.paint == NeuPaint.live && _down);
    final showFocus = widget.paint == NeuPaint.focused || _hasFocus;
    final showError =
        widget.paint == NeuPaint.error ||
        (widget.errorText != null && widget.errorText!.isNotEmpty);
    final style = spec.styleFor(
      widget.role,
      pressed: pressed,
      disabled: _disabled,
      error: showError,
      selected: widget.selected,
    );
    final markers = <IconData>[
      if (widget.icon != null) widget.icon!,
      ...style.markers,
    ];
    final radius = BorderRadius.circular(spec.radius);

    return Semantics(
      container: true,
      button: true,
      enabled: !_disabled,
      focusable: !_disabled,
      focused: _hasFocus || widget.paint == NeuPaint.focused,
      selected: widget.selected,
      label: widget.semanticsLabel ?? widget.label,
      hint: showError ? widget.errorText : null,
      onTap: _disabled ? null : _invoke,
      excludeSemantics: true,
      child: FocusableActionDetector(
        enabled: !_disabled,
        focusNode: widget.focusNode,
        includeFocusSemantics: false,
        mouseCursor: _disabled
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
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
        onFocusChange: (hasFocus) {
          if (_hasFocus != hasFocus) setState(() => _hasFocus = hasFocus);
        },
        child: Listener(
          onPointerDown: _disabled || widget.paint != NeuPaint.live
              ? null
              : (_) => setState(() => _down = true),
          onPointerUp: (_) {
            if (_down) setState(() => _down = false);
          },
          onPointerCancel: (_) {
            if (_down) setState(() => _down = false);
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _disabled ? null : _invoke,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minWidth: NeuSpec.minTouchTarget,
                minHeight: NeuSpec.minTouchTarget,
              ),
              child: DecoratedBox(
                key: NeuButton.ringKey,
                decoration: BoxDecoration(
                  borderRadius: radius,
                  border: Border.all(
                    color: showFocus ? spec.focusRing : Colors.transparent,
                    width: spec.focusWidth,
                  ),
                ),
                child: DecoratedBox(
                  key: NeuButton.surfaceKey,
                  decoration: BoxDecoration(
                    color: style.fill,
                    borderRadius: radius,
                    border: Border.all(
                      color: style.border,
                      width: style.borderWidth,
                    ),
                    boxShadow: spec.shadows(pressed: pressed),
                  ),
                  child: CustomPaint(
                    key: NeuButton.hatchKey,
                    foregroundPainter: _disabled
                        ? _HatchPainter(style.border)
                        : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              for (final icon in markers) ...[
                                Icon(icon, size: 20, color: style.foreground),
                                const SizedBox(width: 8),
                              ],
                              Expanded(
                                child: Text(
                                  widget.label,
                                  softWrap: true,
                                  style: TextStyle(
                                    color: style.foreground,
                                    fontSize: 14,
                                    height: 1.3,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (showError &&
                              widget.errorText != null &&
                              widget.errorText!.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                widget.errorText!,
                                softWrap: true,
                                style: TextStyle(
                                  color: style.foreground,
                                  fontSize: 12,
                                  height: 1.3,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
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

class _HatchPainter extends CustomPainter {
  const _HatchPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = color;
    canvas.drawLine(
      const Offset(10, 10),
      Offset(size.width - 10, size.height - 10),
      paint,
    );
  }

  @override
  bool shouldRepaint(_HatchPainter oldDelegate) => oldDelegate.color != color;
}
