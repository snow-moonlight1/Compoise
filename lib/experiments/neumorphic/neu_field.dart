import 'package:flutter/material.dart';

import 'neu_palette.dart';

/// Text input whose state is a border and, for error or disabled, an icon.
/// The outer shadow is omitted for high contrast and reduced motion.
class NeuField extends StatelessWidget {
  const NeuField({
    super.key,
    required this.label,
    this.controller,
    this.focusNode,
    this.errorText,
    this.enabled = true,
    this.maxLines = 1,
    this.minLines,
    this.onChanged,
    this.onSubmitted,
    this.textInputAction,
  });

  static const surfaceKey = Key('uiexp1-neu-field-surface');

  final String label;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? errorText;
  final bool enabled;
  final int? maxLines;
  final int? minLines;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputAction? textInputAction;

  @override
  Widget build(BuildContext context) {
    final spec = NeuSpec.of(context);
    final idle = spec.styleFor(NeuRole.secondary);
    final disabled = spec.styleFor(NeuRole.secondary, disabled: true);
    final palette = enabled ? idle : disabled;
    final multiline = maxLines == null || maxLines! > 1;
    final hasError = errorText != null && errorText!.isNotEmpty;
    final prefix = !enabled
        ? Icons.block
        : hasError
        ? Icons.error_outline
        : null;

    return DecoratedBox(
      key: surfaceKey,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(spec.radius),
        boxShadow: spec.shadows(pressed: false),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: NeuSpec.minTouchTarget),
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          enabled: enabled,
          maxLines: maxLines,
          minLines: minLines,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          keyboardType: multiline
              ? TextInputType.multiline
              : TextInputType.text,
          textInputAction:
              textInputAction ??
              (multiline ? TextInputAction.newline : TextInputAction.done),
          style: TextStyle(
            color: palette.foreground,
            fontSize: 14,
            height: 1.3,
          ),
          decoration: InputDecoration(
            labelText: label,
            errorText: hasError ? errorText : null,
            prefixIcon: prefix == null
                ? null
                : Icon(
                    prefix,
                    color: hasError ? spec.error : palette.foreground,
                  ),
            filled: true,
            fillColor: palette.fill,
            alignLabelWithHint: multiline,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 14,
            ),
            enabledBorder: _outline(palette.border, palette.borderWidth, spec),
            focusedBorder: _outline(spec.focusRing, spec.focusWidth, spec),
            errorBorder: _outline(spec.error, spec.focusWidth, spec),
            focusedErrorBorder: _outline(spec.error, spec.focusWidth, spec),
            disabledBorder: _outline(
              disabled.border,
              disabled.borderWidth,
              spec,
            ),
          ),
        ),
      ),
    );
  }

  OutlineInputBorder _outline(Color color, double width, NeuSpec spec) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(spec.radius),
        borderSide: BorderSide(color: color, width: width),
      );
}
