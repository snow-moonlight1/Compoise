import 'dart:math' as math;

import 'package:flutter/material.dart';

/// WCAG relative luminance contrast for two opaque colors.
double neuContrast(Color a, Color b) {
  final lighter = math.max(neuLuminance(a), neuLuminance(b));
  final darker = math.min(neuLuminance(a), neuLuminance(b));
  return (lighter + 0.05) / (darker + 0.05);
}

double neuLuminance(Color color) =>
    0.2126 * _channel(color.r) +
    0.7152 * _channel(color.g) +
    0.0722 * _channel(color.b);

double _channel(double value) => value <= 0.04045
    ? value / 12.92
    : math.pow((value + 0.055) / 1.055, 2.4).toDouble();

enum NeuRole { primary, secondary, danger }

/// Gallery-only paint override. [live] follows the pointer and keyboard.
enum NeuPaint { live, pressed, focused, disabled, error }

/// Resolved colors for one button state. Shadows are not part of this style:
/// every state is distinguishable by fill, border, width, or marker icon.
class NeuRoleStyle {
  const NeuRoleStyle({
    required this.fill,
    required this.foreground,
    required this.border,
    required this.borderWidth,
    this.markers = const <IconData>[],
  });

  final Color fill;
  final Color foreground;
  final Color border;
  final double borderWidth;
  final List<IconData> markers;
}

/// Soft-UI palette that keeps a real border when shadows are removed.
class NeuSpec {
  const NeuSpec._({
    required this.brightness,
    required this.highContrast,
    required this.reduceMotion,
    required this.canvas,
    required this.focusRing,
    required this.focusWidth,
    required this.error,
    required this.radius,
    required Map<_StyleKey, NeuRoleStyle> styles,
    required List<BoxShadow> raisedShadows,
    required List<BoxShadow> pressedShadows,
  }) : _styles = styles,
       _raisedShadows = raisedShadows,
       _pressedShadows = pressedShadows;

  final Brightness brightness;
  final bool highContrast;
  final bool reduceMotion;
  final Color canvas;
  final Color focusRing;
  final double focusWidth;
  final Color error;
  final double radius;
  final Map<_StyleKey, NeuRoleStyle> _styles;
  final List<BoxShadow> _raisedShadows;
  final List<BoxShadow> _pressedShadows;

  static const double minTouchTarget = 48;

  factory NeuSpec.of(BuildContext context) {
    final media = MediaQuery.of(context);
    return NeuSpec.resolve(
      brightness: Theme.of(context).brightness,
      highContrast: media.highContrast,
      reduceMotion: media.disableAnimations,
    );
  }

  factory NeuSpec.resolve({
    required Brightness brightness,
    required bool highContrast,
    required bool reduceMotion,
  }) {
    if (highContrast) {
      return brightness == Brightness.dark
          ? _highDark(reduceMotion)
          : _highLight(reduceMotion);
    }
    return brightness == Brightness.dark
        ? _dark(reduceMotion)
        : _light(reduceMotion);
  }

  NeuRoleStyle styleFor(
    NeuRole role, {
    bool pressed = false,
    bool disabled = false,
    bool error = false,
    bool selected = false,
  }) {
    final style = _styles[_StyleKey(role, pressed, disabled, error)]!;
    if (!selected) return style;
    return NeuRoleStyle(
      fill: style.fill,
      foreground: style.foreground,
      border: style.border,
      borderWidth: style.borderWidth + 1,
      markers: style.markers,
    );
  }

  /// Decorative only. High contrast and reduced motion keep the border and
  /// drop the shadow so the control does not depend on blur.
  List<BoxShadow>? shadows({required bool pressed}) {
    if (highContrast || reduceMotion) return null;
    return pressed ? _pressedShadows : _raisedShadows;
  }

  static NeuSpec _light(bool reduceMotion) {
    const canvas = Color(0xFFE6E9EF);
    const ink = Color(0xFF1A2332);
    const primary = Color(0xFF0F3D75);
    const primaryPressed = Color(0xFF08284F);
    const danger = Color(0xFF8C1D18);
    const dangerPressed = Color(0xFF5F100D);
    const field = Color(0xFFF4F6FA);
    const edge = Color(0xFF243044);
    return NeuSpec._(
      brightness: Brightness.light,
      highContrast: false,
      reduceMotion: reduceMotion,
      canvas: canvas,
      focusRing: const Color(0xFF0B3A82),
      focusWidth: 3,
      error: danger,
      radius: 12,
      raisedShadows: const <BoxShadow>[
        BoxShadow(
          color: Color(0xFFFFFFFF),
          offset: Offset(-4, -4),
          blurRadius: 8,
        ),
        BoxShadow(
          color: Color(0x80919AAB),
          offset: Offset(4, 4),
          blurRadius: 8,
        ),
      ],
      pressedShadows: const <BoxShadow>[
        BoxShadow(
          color: Color(0x66919AAB),
          offset: Offset(1, 1),
          blurRadius: 2,
        ),
      ],
      styles: _table(
        primary: _pair(primary, const Color(0xFFFFFFFF), primary, 2),
        primaryPressed: _pair(
          primaryPressed,
          const Color(0xFFFFFFFF),
          primaryPressed,
          3,
        ),
        secondary: _pair(field, ink, edge, 2),
        secondaryPressed: _pair(const Color(0xFFD5DBE6), ink, edge, 3),
        danger: _pair(
          danger,
          const Color(0xFFFFFFFF),
          danger,
          2,
          const <IconData>[Icons.warning_amber_outlined],
        ),
        dangerPressed: _pair(
          dangerPressed,
          const Color(0xFFFFFFFF),
          dangerPressed,
          3,
          const <IconData>[Icons.warning_amber_outlined],
        ),
        disabledFill: canvas,
        disabledInk: edge,
        disabledBorder: edge,
        errorBorder: ink,
      ),
    );
  }

  static NeuSpec _dark(bool reduceMotion) {
    const canvas = Color(0xFF151A21);
    const ink = Color(0xFFF3F6FB);
    const primary = Color(0xFF9CC4FF);
    const primaryInk = Color(0xFF0A1A33);
    const primaryPressed = Color(0xFFD6E6FF);
    const danger = Color(0xFFFFB4A9);
    const dangerInk = Color(0xFF3F0A07);
    const dangerPressed = Color(0xFFFFD8D2);
    const field = Color(0xFF222833);
    const edge = Color(0xFFE7ECF4);
    return NeuSpec._(
      brightness: Brightness.dark,
      highContrast: false,
      reduceMotion: reduceMotion,
      canvas: canvas,
      focusRing: const Color(0xFFFFE082),
      focusWidth: 3,
      error: const Color(0xFFFFB4A9),
      radius: 12,
      raisedShadows: const <BoxShadow>[
        BoxShadow(
          color: Color(0x66000000),
          offset: Offset(4, 4),
          blurRadius: 8,
        ),
        BoxShadow(
          color: Color(0x1FFFFFFF),
          offset: Offset(-3, -3),
          blurRadius: 6,
        ),
      ],
      pressedShadows: const <BoxShadow>[
        BoxShadow(
          color: Color(0x66000000),
          offset: Offset(1, 1),
          blurRadius: 2,
        ),
      ],
      styles: _table(
        primary: _pair(primary, primaryInk, primary, 2),
        primaryPressed: _pair(primaryPressed, primaryInk, primaryPressed, 3),
        secondary: _pair(field, ink, edge, 2),
        secondaryPressed: _pair(const Color(0xFF12161C), ink, edge, 3),
        danger: _pair(danger, dangerInk, danger, 2, const <IconData>[
          Icons.warning_amber_outlined,
        ]),
        dangerPressed: _pair(
          dangerPressed,
          dangerInk,
          dangerPressed,
          3,
          const <IconData>[Icons.warning_amber_outlined],
        ),
        disabledFill: canvas,
        disabledInk: ink,
        disabledBorder: edge,
        errorBorder: const Color(0xFFFFE082),
      ),
    );
  }

  static NeuSpec _highLight(bool reduceMotion) {
    const black = Color(0xFF000000);
    const white = Color(0xFFFFFFFF);
    return NeuSpec._(
      brightness: Brightness.light,
      highContrast: true,
      reduceMotion: reduceMotion,
      canvas: white,
      focusRing: black,
      focusWidth: 3,
      error: black,
      radius: 12,
      raisedShadows: const <BoxShadow>[],
      pressedShadows: const <BoxShadow>[],
      styles: _table(
        primary: _pair(black, white, black, 3),
        primaryPressed: _pair(black, white, black, 6),
        secondary: _pair(white, black, black, 3),
        secondaryPressed: _pair(white, black, black, 6),
        danger: _pair(white, black, black, 4, const <IconData>[
          Icons.warning_amber_outlined,
        ]),
        dangerPressed: _pair(white, black, black, 6, const <IconData>[
          Icons.warning_amber_outlined,
        ]),
        disabledFill: white,
        disabledInk: black,
        disabledBorder: black,
        errorBorder: black,
      ),
    );
  }

  static NeuSpec _highDark(bool reduceMotion) {
    const black = Color(0xFF000000);
    const white = Color(0xFFFFFFFF);
    return NeuSpec._(
      brightness: Brightness.dark,
      highContrast: true,
      reduceMotion: reduceMotion,
      canvas: black,
      focusRing: white,
      focusWidth: 3,
      error: white,
      radius: 12,
      raisedShadows: const <BoxShadow>[],
      pressedShadows: const <BoxShadow>[],
      styles: _table(
        primary: _pair(white, black, white, 3),
        primaryPressed: _pair(white, black, white, 6),
        secondary: _pair(black, white, white, 3),
        secondaryPressed: _pair(black, white, white, 6),
        danger: _pair(black, white, white, 4, const <IconData>[
          Icons.warning_amber_outlined,
        ]),
        dangerPressed: _pair(black, white, white, 6, const <IconData>[
          Icons.warning_amber_outlined,
        ]),
        disabledFill: black,
        disabledInk: white,
        disabledBorder: white,
        errorBorder: white,
      ),
    );
  }

  static Map<_StyleKey, NeuRoleStyle> _table({
    required NeuRoleStyle primary,
    required NeuRoleStyle primaryPressed,
    required NeuRoleStyle secondary,
    required NeuRoleStyle secondaryPressed,
    required NeuRoleStyle danger,
    required NeuRoleStyle dangerPressed,
    required Color disabledFill,
    required Color disabledInk,
    required Color disabledBorder,
    required Color errorBorder,
  }) {
    NeuRoleStyle disabled(List<IconData> markers) => NeuRoleStyle(
      fill: disabledFill,
      foreground: disabledInk,
      border: disabledBorder,
      borderWidth: 7,
      markers: <IconData>[Icons.block, ...markers],
    );
    NeuRoleStyle withError(NeuRoleStyle base) => NeuRoleStyle(
      fill: base.fill,
      foreground: base.foreground,
      border: errorBorder,
      borderWidth: math.max(base.borderWidth, 3) + 1,
      markers: <IconData>[...base.markers, Icons.error_outline],
    );

    final roles = <NeuRole, (NeuRoleStyle, NeuRoleStyle)>{
      NeuRole.primary: (primary, primaryPressed),
      NeuRole.secondary: (secondary, secondaryPressed),
      NeuRole.danger: (danger, dangerPressed),
    };
    final table = <_StyleKey, NeuRoleStyle>{};
    for (final entry in roles.entries) {
      final role = entry.key;
      final normal = entry.value.$1;
      final pressed = entry.value.$2;
      final markers = normal.markers;
      for (final isPressed in const <bool>[false, true]) {
        final base = isPressed ? pressed : normal;
        table[_StyleKey(role, isPressed, false, false)] = base;
        table[_StyleKey(role, isPressed, false, true)] = withError(base);
        table[_StyleKey(role, isPressed, true, false)] = disabled(markers);
        table[_StyleKey(role, isPressed, true, true)] = withError(
          disabled(markers),
        );
      }
    }
    return table;
  }

  static NeuRoleStyle _pair(
    Color fill,
    Color foreground,
    Color border,
    double width, [
    List<IconData> markers = const <IconData>[],
  ]) => NeuRoleStyle(
    fill: fill,
    foreground: foreground,
    border: border,
    borderWidth: width,
    markers: markers,
  );
}

class _StyleKey {
  const _StyleKey(this.role, this.pressed, this.disabled, this.error);

  final NeuRole role;
  final bool pressed;
  final bool disabled;
  final bool error;

  @override
  bool operator ==(Object other) =>
      other is _StyleKey &&
      other.role == role &&
      other.pressed == pressed &&
      other.disabled == disabled &&
      other.error == error;

  @override
  int get hashCode => Object.hash(role, pressed, disabled, error);
}
