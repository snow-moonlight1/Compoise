// Fixes found by running the Linux desktop build by hand.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:compoise/l10n.dart';
import 'package:compoise/models.dart';
import 'package:compoise/planner/planner_guide.dart';
import 'package:compoise/screens/settings_screen.dart';
import 'package:compoise/services/desktop_shell_service.dart';
import 'package:compoise/services/reminder_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'foundation_regression_test.dart' as fixture;
import 'helpers.dart';
import 'wp15_c2_test_support.dart';

void main() {
  testWidgets('Esc closes the schedule guide like Skip', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                showPlannerGuide(context, dictOf(Language.en), markSeen: false),
            child: const Text('go'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('side pool: quadrant dots never run into their labels', (
    tester,
  ) async {
    final store = await c2Store();
    await c2Pump(
      tester,
      store,
      size: const Size(1400, 900),
      platform: TargetPlatform.linux,
    );
    for (final q in allQuadrants) {
      final label = find.descendant(
        of: c2Key('schedule-pool-tab-$q'),
        matching: find.byType(Text),
      );
      final box = tester.getRect(label.first);
      final dot = tester.getRect(c2Key('schedule-pool-dot-$q'));
      expect(dot.right, lessThanOrEqualTo(box.left + 1));
    }
    await c2Finish(tester, store);
  });

  testWidgets('Linux settings: no Android keep-alive guide, plain wording', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    DesktopShellService.debugIsDesktopOverride = true;
    try {
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      ReminderService.instance = InMemoryReminderService(
        permission: ReminderPermissionStatus.unknown,
      );
      final (store, _) = await makeStore(
        boards: [Board(id: 'b1', name: 'Board', createdAt: 1)],
      );
      await tester.pumpWidget(fixture.app(store, const SettingsScreen()));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('reminder-guide-tile')), findsNothing);
      final button = find.byKey(const ValueKey('test-android-notif-btn'));
      await tester.scrollUntilVisible(
        button,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.textContaining('Windows'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    } finally {
      debugDefaultTargetPlatformOverride = null;
      DesktopShellService.debugIsDesktopOverride = null;
    }
  });
}
