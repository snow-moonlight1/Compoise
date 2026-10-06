/// Material 3 themes: light/dark × five accent seeds, tuned for the soft-UI
/// look of the web app (rounded cards, no hard elevation shadows).
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'models.dart';
import 'ui/font_policy.dart';

const themeSeedColors = <ThemeColor, Color>{
  ThemeColor.blue: Color(0xFF3B82F6),
  ThemeColor.purple: Color(0xFF8B5CF6),
  ThemeColor.green: Color(0xFF10B981),
  ThemeColor.orange: Color(0xFFF97316),
  ThemeColor.pink: Color(0xFFEC4899),
};

double fontScaleFactor(FontSizePref pref) {
  switch (pref) {
    case FontSizePref.small:
      return 0.88;
    case FontSizePref.standard:
      return 1.0;
    case FontSizePref.large:
      return 1.16;
  }
}

List<String>? fontFallbackFor(
  FontFamilyPref pref, {
  TargetPlatform? platform,
}) {
  return AppFontPolicy(
    platform: platform ?? defaultTargetPlatform,
  ).fallbackFor(pref);
}

String? fontFamilyFor(FontFamilyPref pref, {TargetPlatform? platform}) {
  return AppFontPolicy(
    platform: platform ?? defaultTargetPlatform,
  ).familyFor(pref);
}

/// Composes the system [TextScaler] with an application-level scale factor.
/// Preserves system accessibility text scaling while honoring user preference.
class CombinedTextScaler extends TextScaler {
  final TextScaler systemScaler;
  final double appScale;
  const CombinedTextScaler(this.systemScaler, this.appScale);

  @override
  double get textScaleFactor => scale(1.0);

  @override
  double scale(double fontSize) => systemScaler.scale(fontSize) * appScale;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CombinedTextScaler &&
          other.systemScaler == systemScaler &&
          other.appScale == appScale;

  @override
  int get hashCode => Object.hash(systemScaler, appScale);
}

ThemeData buildTheme(
  Brightness brightness,
  ThemeColor colorPref, {
  FontFamilyPref fontFamilyPref = FontFamilyPref.system,
  TargetPlatform? platform,
  bool comicOutline = false,
  bool neumorphic = false,
}) {
  final resolvedPlatform = platform ?? defaultTargetPlatform;
  final fonts = AppFontPolicy(platform: resolvedPlatform);
  final scheme = ColorScheme.fromSeed(
    seedColor: themeSeedColors[colorPref]!,
    brightness: brightness,
  );
  final isDark = brightness == Brightness.dark;
  final bg = isDark ? const Color(0xFF2D3748) : const Color(0xFFEFEEEE);
  final baseText = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: brightness,
  ).textTheme.apply(
    fontFamily: fonts.familyFor(fontFamilyPref),
    fontFamilyFallback: fonts.fallbackFor(fontFamilyPref),
  );
  final textTheme = baseText.copyWith(
    bodyLarge: baseText.bodyLarge?.copyWith(fontWeight: fonts.bodyWeight),
    bodyMedium: baseText.bodyMedium?.copyWith(fontWeight: fonts.bodyWeight),
    bodySmall: baseText.bodySmall?.copyWith(fontWeight: fonts.bodyWeight),
    titleLarge: baseText.titleLarge?.copyWith(fontWeight: fonts.titleWeight),
    titleMedium: baseText.titleMedium?.copyWith(fontWeight: fonts.titleWeight),
    titleSmall: baseText.titleSmall?.copyWith(fontWeight: fonts.titleWeight),
    headlineSmall: baseText.headlineSmall?.copyWith(
      fontWeight: fonts.titleWeight,
    ),
    labelLarge: baseText.labelLarge?.copyWith(fontWeight: fonts.labelWeight),
  );

  final theme = ThemeData(
    useMaterial3: true,
    platform: resolvedPlatform,
    colorScheme: scheme.copyWith(surface: bg),
    scaffoldBackgroundColor: bg,
    fontFamily: fonts.familyFor(fontFamilyPref),
    fontFamilyFallback: fonts.fallbackFor(fontFamilyPref),
    textTheme: textTheme,
    primaryTextTheme: textTheme,
    textSelectionTheme: TextSelectionThemeData(
      selectionColor: scheme.primary.withValues(alpha: 0.24),
      cursorColor: scheme.primary,
      selectionHandleColor: scheme.primary,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: isDark ? const Color(0xFF37475C) : Colors.white.withValues(alpha: 0.72),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: EdgeInsets.zero,
    ),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 0,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)))),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
    }),
  );
  // The two appearance skins are alternatives: the settings switches clear
  // each other, and an import that enables both resolves to the comic look.
  if (comicOutline) return applyComicOutline(theme);
  if (neumorphic) return applyNeumorphic(theme);
  return theme;
}

/// Flat thick-outline skin taken from the appearance sample the phone showed.
/// Shadows stay off. This is the comic look, not neumorphism.
class ComicOutline extends ThemeExtension<ComicOutline> {
  const ComicOutline({
    required this.canvas,
    required this.ink,
    required this.field,
    required this.edge,
    required this.primary,
    required this.onPrimary,
    required this.danger,
    required this.onDanger,
    required this.pressedPrimary,
    required this.pressedField,
    required this.pressedDanger,
  });

  static const double radius = 12;

  final Color canvas;
  final Color ink;
  final Color field;
  final Color edge;
  final Color primary;
  final Color onPrimary;
  final Color danger;
  final Color onDanger;
  final Color pressedPrimary;
  final Color pressedField;
  final Color pressedDanger;

  static const light = ComicOutline(
    canvas: Color(0xFFE6E9EF),
    ink: Color(0xFF1A2332),
    field: Color(0xFFF4F6FA),
    edge: Color(0xFF243044),
    primary: Color(0xFF0F3D75),
    onPrimary: Color(0xFFFFFFFF),
    danger: Color(0xFF8C1D18),
    onDanger: Color(0xFFFFFFFF),
    pressedPrimary: Color(0xFF08284F),
    pressedField: Color(0xFFD5DBE6),
    pressedDanger: Color(0xFF5F100D),
  );

  static const dark = ComicOutline(
    canvas: Color(0xFF151A21),
    ink: Color(0xFFF3F6FB),
    field: Color(0xFF222833),
    edge: Color(0xFFE7ECF4),
    primary: Color(0xFF9CC4FF),
    onPrimary: Color(0xFF0A1A33),
    danger: Color(0xFFFFB4A9),
    onDanger: Color(0xFF3F0A07),
    pressedPrimary: Color(0xFFD6E6FF),
    pressedField: Color(0xFF12161C),
    pressedDanger: Color(0xFFFFD8D2),
  );

  static ComicOutline? maybeOf(BuildContext context) =>
      Theme.of(context).extension<ComicOutline>();

  @override
  ComicOutline copyWith({
    Color? canvas,
    Color? ink,
    Color? field,
    Color? edge,
    Color? primary,
    Color? onPrimary,
    Color? danger,
    Color? onDanger,
    Color? pressedPrimary,
    Color? pressedField,
    Color? pressedDanger,
  }) {
    return ComicOutline(
      canvas: canvas ?? this.canvas,
      ink: ink ?? this.ink,
      field: field ?? this.field,
      edge: edge ?? this.edge,
      primary: primary ?? this.primary,
      onPrimary: onPrimary ?? this.onPrimary,
      danger: danger ?? this.danger,
      onDanger: onDanger ?? this.onDanger,
      pressedPrimary: pressedPrimary ?? this.pressedPrimary,
      pressedField: pressedField ?? this.pressedField,
      pressedDanger: pressedDanger ?? this.pressedDanger,
    );
  }

  @override
  ComicOutline lerp(ComicOutline? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return ComicOutline(
      canvas: mix(canvas, other.canvas),
      ink: mix(ink, other.ink),
      field: mix(field, other.field),
      edge: mix(edge, other.edge),
      primary: mix(primary, other.primary),
      onPrimary: mix(onPrimary, other.onPrimary),
      danger: mix(danger, other.danger),
      onDanger: mix(onDanger, other.onDanger),
      pressedPrimary: mix(pressedPrimary, other.pressedPrimary),
      pressedField: mix(pressedField, other.pressedField),
      pressedDanger: mix(pressedDanger, other.pressedDanger),
    );
  }
}

ThemeData applyComicOutline(ThemeData theme) {
  final accent = theme.colorScheme.primary;
  final comic = (theme.brightness == Brightness.dark
          ? ComicOutline.dark
          : ComicOutline.light)
      .copyWith(
        primary: accent,
        onPrimary: theme.colorScheme.onPrimary,
        pressedPrimary: Color.alphaBlend(
          theme.brightness == Brightness.dark
              ? const Color(0x33FFFFFF)
              : const Color(0x33000000),
          accent,
        ),
      );
  final scheme = ColorScheme.fromSeed(
    seedColor: accent,
    brightness: theme.brightness,
  ).copyWith(
    primary: comic.primary,
    onPrimary: comic.onPrimary,
    secondary: comic.edge,
    onSecondary: comic.ink,
    tertiary: comic.ink,
    onTertiary: comic.field,
    error: comic.danger,
    onError: comic.onDanger,
    surface: comic.canvas,
    onSurface: comic.ink,
    onSurfaceVariant: comic.ink,
    outline: comic.edge,
    outlineVariant: comic.edge,
    surfaceTint: const Color(0x00000000),
    surfaceContainerHighest: comic.field,
    surfaceContainerHigh: comic.field,
    surfaceContainer: comic.field,
    surfaceContainerLow: comic.canvas,
    surfaceContainerLowest: comic.field,
    primaryContainer: comic.primary,
    onPrimaryContainer: comic.onPrimary,
    secondaryContainer: comic.field,
    onSecondaryContainer: comic.ink,
    errorContainer: comic.danger,
    onErrorContainer: comic.onDanger,
    inverseSurface: comic.ink,
    onInverseSurface: comic.field,
    shadow: const Color(0x00000000),
  );
  const radius = BorderRadius.all(Radius.circular(ComicOutline.radius));
  final panel = RoundedRectangleBorder(
    borderRadius: radius,
    side: BorderSide(color: comic.edge, width: 2),
  );
  ButtonStyle button({
    required Color fill,
    required Color foreground,
    required Color border,
    required Color pressedFill,
  }) {
    return ButtonStyle(
      elevation: const WidgetStatePropertyAll(0),
      shadowColor: const WidgetStatePropertyAll(Color(0x00000000)),
      surfaceTintColor: const WidgetStatePropertyAll(Color(0x00000000)),
      minimumSize: const WidgetStatePropertyAll(Size(48, 40)),
      tapTargetSize: MaterialTapTargetSize.padded,
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      ),
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return comic.canvas;
        if (states.contains(WidgetState.pressed)) return pressedFill;
        return fill;
      }),
      foregroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return comic.edge;
        return foreground;
      }),
      iconColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return comic.edge;
        return foreground;
      }),
      overlayColor: const WidgetStatePropertyAll(Color(0x00000000)),
      side: WidgetStateProperty.resolveWith((states) {
        final width =
            states.contains(WidgetState.pressed) ||
                states.contains(WidgetState.focused)
            ? 3.0
            : 2.0;
        return BorderSide(
          color: states.contains(WidgetState.disabled) ? comic.edge : border,
          width: width,
        );
      }),
      shape: const WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: radius),
      ),
    );
  }

  final secondary = button(
    fill: comic.field,
    foreground: comic.ink,
    border: comic.edge,
    pressedFill: comic.pressedField,
  );
  final primary = button(
    fill: comic.primary,
    foreground: comic.onPrimary,
    border: comic.primary,
    pressedFill: comic.pressedPrimary,
  );
  return theme.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: comic.canvas,
    dividerColor: comic.edge,
    extensions: <ThemeExtension<dynamic>>[comic],
    appBarTheme: AppBarTheme(
      backgroundColor: comic.canvas,
      foregroundColor: comic.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: const Color(0x00000000),
      shape: Border(bottom: BorderSide(color: comic.edge, width: 2)),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: comic.field,
      margin: EdgeInsets.zero,
      shape: panel,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: comic.field,
      elevation: 0,
      shape: panel,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: comic.canvas,
      elevation: 0,
      modalElevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        side: BorderSide(color: comic.edge, width: 2),
      ),
    ),
    datePickerTheme: DatePickerThemeData(
      backgroundColor: comic.field,
      shape: panel,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: comic.field,
      elevation: 0,
      shape: panel,
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(comic.field),
        elevation: const WidgetStatePropertyAll(0),
        shape: WidgetStatePropertyAll(panel),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: comic.field,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      hintStyle: TextStyle(color: comic.ink.withValues(alpha: 0.55)),
      labelStyle: TextStyle(color: comic.ink),
      border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: comic.edge, width: 2)),
      enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: comic.edge, width: 2)),
      focusedBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: comic.edge, width: 3)),
      errorBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: comic.danger, width: 2)),
      focusedErrorBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: comic.danger, width: 3)),
      disabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: comic.edge, width: 2)),
    ),
    filledButtonTheme: FilledButtonThemeData(style: primary),
    elevatedButtonTheme: ElevatedButtonThemeData(style: primary),
    outlinedButtonTheme: OutlinedButtonThemeData(style: secondary),
    textButtonTheme: TextButtonThemeData(style: secondary),
    iconButtonTheme: IconButtonThemeData(
      style: secondary.copyWith(
        padding: const WidgetStatePropertyAll(EdgeInsets.all(8)),
        minimumSize: const WidgetStatePropertyAll(Size(40, 40)),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: comic.primary,
      foregroundColor: comic.onPrimary,
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      highlightElevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: comic.primary, width: 2),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        side: WidgetStatePropertyAll(BorderSide(color: comic.edge, width: 2)),
        shape: const WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: radius),
        ),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return comic.primary;
          return comic.field;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return comic.onPrimary;
          return comic.ink;
        }),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: comic.field,
      selectedColor: comic.primary,
      disabledColor: comic.canvas,
      labelStyle: TextStyle(color: comic.ink),
      secondaryLabelStyle: TextStyle(color: comic.onPrimary),
      side: BorderSide(color: comic.edge, width: 2),
      shape: const RoundedRectangleBorder(borderRadius: radius),
    ),
    checkboxTheme: CheckboxThemeData(
      side: BorderSide(color: comic.edge, width: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return comic.primary;
        return comic.field;
      }),
      checkColor: WidgetStatePropertyAll(comic.onPrimary),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return comic.onPrimary;
        return comic.field;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return comic.primary;
        return comic.canvas;
      }),
      trackOutlineColor: WidgetStatePropertyAll(comic.edge),
      trackOutlineWidth: const WidgetStatePropertyAll(2),
    ),
    dividerTheme: DividerThemeData(color: comic.edge, thickness: 1, space: 1),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: comic.ink,
      contentTextStyle: TextStyle(color: comic.field),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: comic.edge, width: 2),
      ),
    ),
    listTileTheme: ListTileThemeData(iconColor: comic.ink, textColor: comic.ink),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: comic.canvas,
      elevation: 0,
      indicatorColor: comic.field,
      indicatorShape: panel,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: comic.primary),
  );
}

/// Neumorphism: the control and the slab are the same color. A light from the
/// top-left raises a control with a light shadow on the top-left and a dark
/// shadow on the bottom-right. A pressed control sinks, and that pair moves
/// inside. It is not a tinted background and not one Material drop shadow.
class NeumorphicSkin extends ThemeExtension<NeumorphicSkin> {
  const NeumorphicSkin({
    required this.canvas,
    required this.ink,
    required this.field,
    required this.danger,
    required this.onDanger,
    required this.lightShadow,
    required this.darkShadow,
  });

  static const double radius = 12;

  /// Clear space a raised control needs on every side. The pair fades out
  /// inside this margin, so a parent clip does not slice it.
  static const double shadowMargin = 16;

  final Color canvas;
  final Color ink;

  /// Same slab as [canvas]. A second fill color would stop being neumorphic.
  final Color field;
  final Color danger;
  final Color onDanger;

  /// Top-left highlight of the raised pair. Inside a pressed control it sits
  /// on the bottom-right lip.
  final Color lightShadow;

  /// Bottom-right shade of the raised pair. Inside a pressed control it sits
  /// on the top-left lip.
  final Color darkShadow;

  static const light = NeumorphicSkin(
    canvas: Color(0xFFE0DEDA),
    ink: Color(0xFF2B2926),
    field: Color(0xFFE0DEDA),
    danger: Color(0xFF8C1D18),
    onDanger: Color(0xFFFFFFFF),
    lightShadow: Color(0xFFFFFFFF),
    darkShadow: Color(0xFFA39B92),
  );

  static const dark = NeumorphicSkin(
    canvas: Color(0xFF2C2B2A),
    ink: Color(0xFFF2EFEA),
    field: Color(0xFF2C2B2A),
    danger: Color(0xFFFFB4A9),
    onDanger: Color(0xFF3F0A07),
    lightShadow: Color(0xFF4A4845),
    darkShadow: Color(0xFF121110),
  );

  List<BoxShadow> get raisedShadows => <BoxShadow>[
    BoxShadow(color: lightShadow, offset: const Offset(-4, -4), blurRadius: 6),
    BoxShadow(color: darkShadow, offset: const Offset(4, 4), blurRadius: 6),
  ];

  /// Darker slab used where a real inset blur cannot be painted, such as a
  /// chip. Still the same family as [canvas], not the accent.
  Color get groove => Color.alphaBlend(darkShadow.withValues(alpha: 0.55), canvas);

  static NeumorphicSkin? maybeOf(BuildContext context) =>
      Theme.of(context).extension<NeumorphicSkin>();

  @override
  NeumorphicSkin copyWith({
    Color? canvas,
    Color? ink,
    Color? field,
    Color? danger,
    Color? onDanger,
    Color? lightShadow,
    Color? darkShadow,
  }) {
    return NeumorphicSkin(
      canvas: canvas ?? this.canvas,
      ink: ink ?? this.ink,
      field: field ?? this.field,
      danger: danger ?? this.danger,
      onDanger: onDanger ?? this.onDanger,
      lightShadow: lightShadow ?? this.lightShadow,
      darkShadow: darkShadow ?? this.darkShadow,
    );
  }

  @override
  NeumorphicSkin lerp(NeumorphicSkin? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return NeumorphicSkin(
      canvas: mix(canvas, other.canvas),
      ink: mix(ink, other.ink),
      field: mix(field, other.field),
      danger: mix(danger, other.danger),
      onDanger: mix(onDanger, other.onDanger),
      lightShadow: mix(lightShadow, other.lightShadow),
      darkShadow: mix(darkShadow, other.darkShadow),
    );
  }
}

ThemeData applyNeumorphic(ThemeData theme) {
  final accent = theme.colorScheme.primary;
  final onAccent = theme.colorScheme.onPrimary;
  final neu = theme.brightness == Brightness.dark
      ? NeumorphicSkin.dark
      : NeumorphicSkin.light;
  final border = NeuInputBorder(skin: neu);
  // Every surface is the slab. Accent stays on icons, cursors, and progress.
  // Raised and pressed depth is painted by NeuRaised / NeuInset / NeuInputBorder,
  // because Material elevation is only one shadow.
  final scheme = theme.colorScheme.copyWith(
    primary: accent,
    onPrimary: onAccent,
    error: neu.danger,
    onError: neu.onDanger,
    surface: neu.canvas,
    onSurface: neu.ink,
    onSurfaceVariant: neu.ink.withValues(alpha: 0.72),
    outline: neu.darkShadow,
    outlineVariant: neu.darkShadow.withValues(alpha: 0.45),
    surfaceTint: const Color(0x00000000),
    surfaceContainerHighest: neu.canvas,
    surfaceContainerHigh: neu.canvas,
    surfaceContainer: neu.canvas,
    surfaceContainerLow: neu.canvas,
    surfaceContainerLowest: neu.canvas,
    primaryContainer: neu.canvas,
    onPrimaryContainer: accent,
    secondaryContainer: neu.canvas,
    onSecondaryContainer: neu.ink,
    errorContainer: neu.danger,
    onErrorContainer: neu.onDanger,
    inverseSurface: neu.ink,
    onInverseSurface: neu.canvas,
    shadow: neu.darkShadow,
  );
  const radius = BorderRadius.all(Radius.circular(NeumorphicSkin.radius));
  return theme.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: neu.canvas,
    dividerColor: scheme.outlineVariant,
    extensions: <ThemeExtension<dynamic>>[neu],
    appBarTheme: AppBarTheme(
      backgroundColor: neu.canvas,
      foregroundColor: neu.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: const Color(0x00000000),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      shadowColor: const Color(0x00000000),
      surfaceTintColor: const Color(0x00000000),
      color: neu.canvas,
      margin: EdgeInsets.zero,
      shape: const RoundedRectangleBorder(borderRadius: radius),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: neu.canvas,
      elevation: 0,
      shadowColor: const Color(0x00000000),
      surfaceTintColor: const Color(0x00000000),
      shape: const RoundedRectangleBorder(borderRadius: radius),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: neu.canvas,
      elevation: 0,
      shadowColor: const Color(0x00000000),
      modalElevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(NeumorphicSkin.radius),
        ),
      ),
    ),
    datePickerTheme: DatePickerThemeData(
      backgroundColor: neu.canvas,
      elevation: 0,
      shadowColor: const Color(0x00000000),
      shape: const RoundedRectangleBorder(borderRadius: radius),
    ),
    // A menu overlaps the page, so it cannot share the slab's extruded pair.
    // Material only draws one shadow; this just keeps the menu visible.
    popupMenuTheme: PopupMenuThemeData(
      color: neu.canvas,
      elevation: 8,
      shadowColor: neu.darkShadow,
      surfaceTintColor: const Color(0x00000000),
      shape: const RoundedRectangleBorder(borderRadius: radius),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(neu.canvas),
        elevation: const WidgetStatePropertyAll(8),
        shadowColor: WidgetStatePropertyAll(neu.darkShadow),
        surfaceTintColor: const WidgetStatePropertyAll(Color(0x00000000)),
        shape: const WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: radius),
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: neu.canvas,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      hintStyle: TextStyle(color: neu.ink.withValues(alpha: 0.5)),
      labelStyle: TextStyle(color: neu.ink.withValues(alpha: 0.8)),
      border: border,
      enabledBorder: border,
      focusedBorder: border,
      errorBorder: border,
      focusedErrorBorder: border,
      disabledBorder: border,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        elevation: const WidgetStatePropertyAll(0),
        shadowColor: const WidgetStatePropertyAll(Color(0x00000000)),
        surfaceTintColor: const WidgetStatePropertyAll(Color(0x00000000)),
        backgroundColor: WidgetStatePropertyAll(neu.canvas),
        foregroundColor: WidgetStatePropertyAll(neu.ink),
        iconColor: WidgetStatePropertyAll(accent),
        overlayColor: WidgetStatePropertyAll(accent.withValues(alpha: 0.08)),
        shape: const WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: radius),
        ),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ButtonStyle(
        elevation: const WidgetStatePropertyAll(0),
        shadowColor: const WidgetStatePropertyAll(Color(0x00000000)),
        surfaceTintColor: const WidgetStatePropertyAll(Color(0x00000000)),
        backgroundColor: WidgetStatePropertyAll(neu.canvas),
        foregroundColor: WidgetStatePropertyAll(neu.ink),
        iconColor: WidgetStatePropertyAll(accent),
        overlayColor: WidgetStatePropertyAll(accent.withValues(alpha: 0.08)),
        shape: const WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: radius),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        elevation: const WidgetStatePropertyAll(0),
        shadowColor: const WidgetStatePropertyAll(Color(0x00000000)),
        backgroundColor: WidgetStatePropertyAll(neu.canvas),
        foregroundColor: WidgetStatePropertyAll(neu.ink),
        side: const WidgetStatePropertyAll(BorderSide.none),
        shape: const WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: radius),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStatePropertyAll(neu.ink),
        iconColor: WidgetStatePropertyAll(neu.ink),
        overlayColor: WidgetStatePropertyAll(accent.withValues(alpha: 0.08)),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStatePropertyAll(neu.ink),
        overlayColor: WidgetStatePropertyAll(accent.withValues(alpha: 0.08)),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: neu.canvas,
      foregroundColor: accent,
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      highlightElevation: 0,
      shape: const RoundedRectangleBorder(borderRadius: radius),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        side: const WidgetStatePropertyAll(BorderSide.none),
        elevation: const WidgetStatePropertyAll(0),
        backgroundColor: WidgetStatePropertyAll(neu.canvas),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return accent;
          return neu.ink;
        }),
        backgroundBuilder: (context, states, child) {
          if (!states.contains(WidgetState.selected)) return child!;
          return CustomPaint(
            painter: NeuInsetPainter(skin: neu, radius: NeumorphicSkin.radius),
            child: child,
          );
        },
        shape: const WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: radius),
        ),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: neu.canvas,
      selectedColor: neu.groove,
      disabledColor: neu.canvas,
      labelStyle: TextStyle(color: neu.ink),
      secondaryLabelStyle: TextStyle(
        color: accent,
        fontWeight: FontWeight.w700,
      ),
      side: BorderSide.none,
      elevation: 0,
      pressElevation: 0,
      shape: const RoundedRectangleBorder(borderRadius: radius),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStatePropertyAll(neu.lightShadow),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return neu.groove;
        return Color.alphaBlend(neu.darkShadow.withValues(alpha: 0.28), neu.canvas);
      }),
      trackOutlineColor: const WidgetStatePropertyAll(Color(0x00000000)),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return accent;
        return neu.canvas;
      }),
      checkColor: WidgetStatePropertyAll(onAccent),
      side: BorderSide(color: neu.darkShadow, width: 1.5),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: neu.ink,
      contentTextStyle: TextStyle(color: neu.canvas),
      elevation: 0,
      shape: const RoundedRectangleBorder(borderRadius: radius),
    ),
    listTileTheme: ListTileThemeData(iconColor: neu.ink, textColor: neu.ink),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: neu.canvas,
      elevation: 0,
      indicatorColor: neu.groove,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: accent),
  );
}

/// Paints the concave pair: dark lip on the top-left, light lip on the
/// bottom-right. The caller has already filled [rect] with the slab color.
void paintNeuInset(Canvas canvas, Rect rect, NeumorphicSkin skin, double radius) {
  final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));
  canvas.save();
  canvas.clipRRect(rrect);

  void lobe(Color color, Offset shift) {
    final paint = Paint()
      ..color = color
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    final hole = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(rect.inflate(radius + 20))
      ..addRRect(rrect.shift(shift));
    canvas.drawPath(hole, paint);
  }

  lobe(skin.darkShadow, const Offset(4, 4));
  lobe(skin.lightShadow, const Offset(-4, -4));
  canvas.restore();
}

class NeuInsetPainter extends CustomPainter {
  const NeuInsetPainter({required this.skin, required this.radius});

  final NeumorphicSkin skin;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(radius)),
      Paint()..color = skin.canvas,
    );
    paintNeuInset(canvas, rect, skin, radius);
  }

  @override
  bool shouldRepaint(NeuInsetPainter oldDelegate) =>
      oldDelegate.skin != skin || oldDelegate.radius != radius;
}

/// Rounded field whose border is the inset pair, painted over a same-color fill.
class NeuInputBorder extends InputBorder {
  const NeuInputBorder({required this.skin, this.radius = NeumorphicSkin.radius})
    : super(borderSide: BorderSide.none);

  final NeumorphicSkin skin;
  final double radius;

  @override
  NeuInputBorder copyWith({BorderSide? borderSide, double? radius}) =>
      NeuInputBorder(skin: skin, radius: radius ?? this.radius);

  @override
  bool get isOutline => true;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  NeuInputBorder scale(double t) =>
      NeuInputBorder(skin: skin, radius: radius * t);

  RRect _rrect(Rect rect) =>
      RRect.fromRectAndRadius(rect, Radius.circular(radius));

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      Path()..addRRect(_rrect(rect));

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      getOuterPath(rect, textDirection: textDirection);

  @override
  void paint(
    Canvas canvas,
    Rect rect, {
    double? gapStart,
    double gapExtent = 0.0,
    double gapPercentage = 0.0,
    TextDirection? textDirection,
  }) {
    paintNeuInset(canvas, rect, skin, radius);
  }

  @override
  bool operator ==(Object other) =>
      other is NeuInputBorder && other.skin == skin && other.radius == radius;

  @override
  int get hashCode => Object.hash(skin, radius);
}

/// Convex control. Same color as the slab, light on the top-left, dark on
/// the bottom-right. Give it a margin so the pair is not covered by the next
/// sibling.
class NeuRaised extends StatelessWidget {
  const NeuRaised({
    super.key,
    required this.skin,
    required this.child,
    this.radius = NeumorphicSkin.radius,
  });

  final NeumorphicSkin skin;
  final Widget child;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: skin.canvas,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: skin.raisedShadows,
      ),
      child: child,
    );
  }
}

/// Concave control. Same color as the slab, with the shadow pair inside.
class NeuInset extends StatelessWidget {
  const NeuInset({
    super.key,
    required this.skin,
    required this.child,
    this.radius = NeumorphicSkin.radius,
  });

  final NeumorphicSkin skin;
  final Widget child;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: NeuInsetPainter(skin: skin, radius: radius),
      child: child,
    );
  }
}

/// Raised at rest, inset while a finger is down.
class NeuPressable extends StatefulWidget {
  const NeuPressable({
    super.key,
    required this.skin,
    required this.child,
    this.radius = 16,
  });

  final NeumorphicSkin skin;
  final Widget child;
  final double radius;

  @override
  State<NeuPressable> createState() => _NeuPressableState();
}

class _NeuPressableState extends State<NeuPressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    // One stable child. Swapping NeuRaised for NeuInset on pointer-down
    // threw away the button and cancelled its tap.
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => setState(() => _down = true),
      onPointerUp: (_) => setState(() => _down = false),
      onPointerCancel: (_) => setState(() => _down = false),
      child: _NeuPressFace(
        skin: widget.skin,
        radius: widget.radius,
        pressed: _down,
        child: widget.child,
      ),
    );
  }
}

class _NeuPressFace extends StatelessWidget {
  const _NeuPressFace({
    required this.skin,
    required this.radius,
    required this.pressed,
    required this.child,
  });

  final NeumorphicSkin skin;
  final double radius;
  final bool pressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: pressed
          ? NeuInsetPainter(skin: skin, radius: radius)
          : null,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: pressed ? const Color(0x00000000) : skin.canvas,
          borderRadius: BorderRadius.circular(radius),
          boxShadow: pressed ? null : skin.raisedShadows,
        ),
        child: child,
      ),
    );
  }
}
