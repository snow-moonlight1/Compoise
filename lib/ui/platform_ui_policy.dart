import 'package:flutter/material.dart';

/// Platform chrome and input policy. Window width never implies device type:
/// Android stays a touch layout even when wide; Windows stays desktop even when
/// the window is narrow.
class PlatformUiPolicy {
  final TargetPlatform platform;

  const PlatformUiPolicy({required this.platform});

  factory PlatformUiPolicy.of(BuildContext context) =>
      PlatformUiPolicy(platform: Theme.of(context).platform);

  bool get isWindows => platform == TargetPlatform.windows;

  bool get isDesktop =>
      platform == TargetPlatform.windows ||
      platform == TargetPlatform.macOS ||
      platform == TargetPlatform.linux;

  bool get isTouchLayout => !isDesktop;

  bool get showDesktopShortcuts => isDesktop;

  bool get showShortcutHints => isDesktop;

  // The tray, global hotkey and close-to-tray controls have a Windows host.
  bool get showDesktopSettings => isWindows;

  static const double sideDetailWidth = 350;
  static const double sideDetailGap = 14;
  static const double minCenterWidth = 560;
  static const double compactHeaderBreakpoint = 720;
  static const double minActionSize = 48;

  bool canShowSideDetail(double availableWidth) =>
      availableWidth >= sideDetailWidth + sideDetailGap + minCenterWidth;

  bool compactHeaderActions(double availableWidth) =>
      availableWidth < compactHeaderBreakpoint;
}
