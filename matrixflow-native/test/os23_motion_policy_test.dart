import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/screens/onboarding_screen.dart';
import 'package:matrixflow_native/storage.dart';
import 'package:matrixflow_native/ui/motion_policy.dart';
import 'package:provider/provider.dart';

import 'helpers.dart';

Widget wrapOnboarding(Store store) {
  return ChangeNotifierProvider.value(
    value: store,
    child: const MaterialApp(home: OnboardingScreen()),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('OS23: transition durations have a single source in MotionPolicy', () {
    // Values intentionally preserved from the pre-OS23 hardcoded call sites;
    // this test locks them so a future edit cannot silently change the feel.
    expect(MotionPolicy.strikethrough, const Duration(milliseconds: 220));
    expect(MotionPolicy.exitHold, const Duration(milliseconds: 220));
    expect(MotionPolicy.exitCollapse, const Duration(milliseconds: 120));
    expect(MotionPolicy.entranceStep, const Duration(milliseconds: 45));
    expect(MotionPolicy.entranceFade, const Duration(milliseconds: 260));
    expect(MotionPolicy.geometryEnter, const Duration(milliseconds: 320));
    expect(MotionPolicy.geometrySwitch, const Duration(milliseconds: 300));
    expect(MotionPolicy.geometryExit, const Duration(milliseconds: 280));
    expect(MotionPolicy.listFade, const Duration(milliseconds: 220));
    expect(MotionPolicy.scrollToTop, const Duration(milliseconds: 250));
    expect(MotionPolicy.pageTurn, const Duration(milliseconds: 300));
    expect(MotionPolicy.dismissible, const Duration(milliseconds: 200));
    expect(MotionPolicy.hoverHighlight, const Duration(milliseconds: 180));
  });

  testWidgets(
    'OS23: onboarding flips to the next slide immediately under reduce motion',
    (tester) async {
      final (store, _) = await makeStore(
        settings: AppSettings()..reduceMotion = true,
      );

      await tester.pumpWidget(wrapOnboarding(store));
      await tester.pump();

      // Slide 0: Previous button is not built yet.
      expect(find.byKey(const ValueKey('onboarding-prev-btn')), findsNothing);
      expect(
        find.byKey(const ValueKey('onboarding-next-btn')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('onboarding-next-btn')));
      // One frame only: the old 300ms slide would still be mid-flight. Under
      // reduce motion the page must already be on slide 1.
      await tester.pump();

      expect(
        find.byKey(const ValueKey('onboarding-prev-btn')),
        findsOneWidget,
      );
      expect(find.text(store.t['onboardingStep2Title']!), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      store.dispose();
    },
  );

  testWidgets(
    'OS23: onboarding still slides across multiple frames with reduce motion off',
    (tester) async {
      final (store, _) = await makeStore(
        settings: AppSettings()..reduceMotion = false,
      );

      await tester.pumpWidget(wrapOnboarding(store));
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('onboarding-next-btn')));
      // 50ms into a 300ms easeInOut slide: current page has not advanced yet.
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byKey(const ValueKey('onboarding-prev-btn')), findsNothing);

      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('onboarding-prev-btn')),
        findsOneWidget,
      );
      expect(find.text(store.t['onboardingStep2Title']!), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      store.dispose();
    },
  );
}
