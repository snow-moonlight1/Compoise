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

  return ThemeData(
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
}
