/// Material 3 themes: light/dark × five accent seeds, tuned for the soft-UI
/// look of the web app (rounded cards, no hard elevation shadows).
library;

import 'package:flutter/material.dart';

import 'models.dart';

const themeSeedColors = <ThemeColor, Color>{
  ThemeColor.blue: Color(0xFF3B82F6),
  ThemeColor.purple: Color(0xFF8B5CF6),
  ThemeColor.green: Color(0xFF10B981),
  ThemeColor.orange: Color(0xFFF97316),
  ThemeColor.pink: Color(0xFFEC4899),
};

ThemeData buildTheme(Brightness brightness, ThemeColor colorPref) {
  final scheme = ColorScheme.fromSeed(
    seedColor: themeSeedColors[colorPref]!,
    brightness: brightness,
  );
  final isDark = brightness == Brightness.dark;
  final bg = isDark ? const Color(0xFF2D3748) : const Color(0xFFEFEEEE);

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme.copyWith(surface: bg),
    scaffoldBackgroundColor: bg,
    fontFamily: null, // platform default; Nunito is bundled optionally
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
