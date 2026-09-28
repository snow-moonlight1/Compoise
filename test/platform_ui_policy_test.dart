import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/ui/platform_ui_policy.dart';

void main() {
  test('Linux keeps desktop input without Windows shell settings', () {
    const linux = PlatformUiPolicy(platform: TargetPlatform.linux);
    const windows = PlatformUiPolicy(platform: TargetPlatform.windows);

    expect(linux.isDesktop, isTrue);
    expect(linux.showDesktopShortcuts, isTrue);
    expect(linux.showDesktopSettings, isFalse);
    expect(windows.showDesktopSettings, isTrue);
  });
}
