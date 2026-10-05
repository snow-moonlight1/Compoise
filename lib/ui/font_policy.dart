import 'package:flutter/material.dart';

import '../models.dart';
import 'songti_font.dart';

/// Platform-aware font family and CJK fallbacks.
/// Window width is irrelevant: Android never receives Windows face names.
class AppFontPolicy {
  final TargetPlatform platform;

  const AppFontPolicy({required this.platform});

  factory AppFontPolicy.of(BuildContext context) =>
      AppFontPolicy(platform: Theme.of(context).platform);

  bool get isWindows => platform == TargetPlatform.windows;

  /// Faces confirmed or commonly present on Windows. Later names are
  /// fallbacks, not a claim that every machine has them.
  static const windowsCjkSans = <String>[
    'Microsoft YaHei UI',
    'Microsoft YaHei',
    'Noto Sans SC',
  ];

  static const windowsLatinSans = <String>['Segoe UI', 'Tahoma', 'Arial'];
  static const windowsLatinMono = <String>['Consolas', 'Courier New'];

  static const androidSans = <String>['Roboto', 'sans-serif'];
  static const androidMono = <String>['monospace'];

  String? familyFor(FontFamilyPref pref) {
    switch (pref) {
      case FontFamilyPref.system:
        return null;
      case FontFamilyPref.sansSerif:
        return isWindows ? windowsCjkSans.first : androidSans.first;
      case FontFamilyPref.serif:
        return SongtiFonts.family;
      case FontFamilyPref.monospace:
        return isWindows ? windowsLatinMono.first : androidMono.first;
    }
  }

  List<String>? fallbackFor(FontFamilyPref pref) {
    final faces = <String>[];
    switch (pref) {
      case FontFamilyPref.system:
        if (isWindows) faces.addAll(windowsCjkSans);
        break;
      case FontFamilyPref.sansSerif:
        if (isWindows) {
          faces.addAll(windowsCjkSans.skip(1));
          faces.addAll(windowsLatinSans);
          faces.add('sans-serif');
        } else {
          faces.addAll(androidSans.skip(1));
        }
        break;
      case FontFamilyPref.serif:
        break;
      case FontFamilyPref.monospace:
        if (isWindows) {
          faces.addAll(windowsLatinMono.skip(1));
          faces.addAll(windowsCjkSans);
          faces.add('monospace');
        }
        break;
    }
    if (faces.isEmpty) return null;
    final unique = <String>[];
    for (final face in faces) {
      if (!unique.contains(face)) unique.add(face);
    }
    return unique;
  }

  FontWeight get bodyWeight => FontWeight.w400;
  FontWeight get labelWeight => FontWeight.w500;
  FontWeight get titleWeight => FontWeight.w600;
}
