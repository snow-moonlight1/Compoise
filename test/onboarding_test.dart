import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/screens/matrix_screen.dart';
import 'package:matrixflow_native/screens/onboarding_screen.dart';
import 'package:matrixflow_native/screens/settings_screen.dart';
import 'package:matrixflow_native/storage.dart';
import 'package:provider/provider.dart';

import 'helpers.dart';

Widget wrapApp(Store store, Widget home) {
  return ChangeNotifierProvider.value(
    value: store,
    child: MaterialApp(
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('en'), Locale('zh'), Locale('ja')],
      home: home,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WP09-N: Onboarding & Tutorial Help Panel', () {
    testWidgets('fresh launch automatically presents OnboardingScreen and can be completed', (tester) async {
      final (store, _) = await makeStore(hasSeenOnboarding: false);
      expect(store.hasSeenOnboarding, isFalse);

      await tester.pumpWidget(wrapApp(store, const MatrixHome()));
      await tester.pumpAndSettle();

      // Onboarding screen automatically popped up
      expect(find.byType(OnboardingScreen), findsOneWidget);
      expect(find.text(store.t['onboardingStep1Title']!), findsOneWidget);

      // Slide 1: Next button visible, Previous not visible
      expect(find.byKey(const ValueKey('onboarding-next-btn')), findsOneWidget);
      expect(find.byKey(const ValueKey('onboarding-prev-btn')), findsNothing);

      // Navigate to Slide 2
      await tester.tap(find.byKey(const ValueKey('onboarding-next-btn')));
      await tester.pumpAndSettle();
      expect(find.text(store.t['onboardingStep2Title']!), findsOneWidget);
      expect(find.byKey(const ValueKey('onboarding-prev-btn')), findsOneWidget);

      // Navigate back to Slide 1
      await tester.tap(find.byKey(const ValueKey('onboarding-prev-btn')));
      await tester.pumpAndSettle();
      expect(find.text(store.t['onboardingStep1Title']!), findsOneWidget);

      // Navigate all the way to Slide 5
      for (int i = 0; i < 4; i++) {
        await tester.tap(find.byKey(const ValueKey('onboarding-next-btn')));
        await tester.pumpAndSettle();
      }
      expect(find.text(store.t['onboardingStep5Title']!), findsOneWidget);
      expect(find.text(store.t['onboardingStart']!), findsOneWidget);

      // Tap "Get Started"
      await tester.tap(find.byKey(const ValueKey('onboarding-next-btn')));
      await tester.pumpAndSettle();

      // Onboarding dismissed, store marked as seen
      expect(find.byType(OnboardingScreen), findsNothing);
      expect(store.hasSeenOnboarding, isTrue);

      await tester.pumpWidget(const SizedBox());
      store.dispose();
    });

    testWidgets('skip button marks onboarding as complete and does not reopen on next launch', (tester) async {
      final (store, _) = await makeStore(hasSeenOnboarding: false);
      expect(store.hasSeenOnboarding, isFalse);

      await tester.pumpWidget(wrapApp(store, const MatrixHome()));
      await tester.pumpAndSettle();

      expect(find.byType(OnboardingScreen), findsOneWidget);

      // Tap "Skip"
      await tester.tap(find.byKey(const ValueKey('onboarding-skip-btn')));
      await tester.pumpAndSettle();

      expect(find.byType(OnboardingScreen), findsNothing);
      expect(store.hasSeenOnboarding, isTrue);

      // Simulate next launch / reboot with store where hasSeenOnboarding is true
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(wrapApp(store, const MatrixHome()));
      await tester.pumpAndSettle();

      // Does NOT pop up onboarding screen
      expect(find.byType(OnboardingScreen), findsNothing);
      expect(find.byType(MatrixHome), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      store.dispose();
    });

    testWidgets('SettingsScreen provides entry to reopen tutorial in review mode', (tester) async {
      final (store, _) = await makeStore();
      store.completeOnboarding();
      expect(store.hasSeenOnboarding, isTrue);

      await tester.pumpWidget(wrapApp(store, const SettingsScreen()));
      await tester.pumpAndSettle();

      // Scroll into view to build lazily in ListView
      final reopenTile = find.byKey(const ValueKey('reopen-onboarding-btn'));
      await tester.scrollUntilVisible(
        reopenTile,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(reopenTile, findsOneWidget);

      await tester.tap(reopenTile);
      await tester.pumpAndSettle();

      // Opens in review mode
      expect(find.byType(OnboardingScreen), findsOneWidget);
      expect(find.text(store.t['onboarding']!), findsOneWidget);
      expect(find.text(store.t['onboardingClose']!), findsOneWidget);

      // Close button exits review mode without corrupting store state
      await tester.tap(find.byKey(const ValueKey('onboarding-skip-btn')));
      await tester.pumpAndSettle();

      expect(find.byType(OnboardingScreen), findsNothing);
      expect(store.hasSeenOnboarding, isTrue);

      await tester.pumpWidget(const SizedBox());
      store.dispose();
    });

    testWidgets('Onboarding renders localized strings for Chinese and Japanese', (tester) async {
      // Chinese
      final (storeZh, _) = await makeStore(
        settings: AppSettings(language: Language.zh),
      );
      await tester.pumpWidget(wrapApp(storeZh, const OnboardingScreen(isReviewMode: true)));
      await tester.pumpAndSettle();

      expect(find.text(storeZh.t['onboardingStep1Title']!), findsOneWidget);
      expect(find.text('四象限矩阵与快速添加'), findsOneWidget);
      expect(find.text('下一步'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      storeZh.dispose();

      // Japanese
      final (storeJa, _) = await makeStore(
        settings: AppSettings(language: Language.ja),
      );
      await tester.pumpWidget(wrapApp(storeJa, const OnboardingScreen(isReviewMode: true)));
      await tester.pumpAndSettle();

      expect(find.text(storeJa.t['onboardingStep1Title']!), findsOneWidget);
      expect(find.text('アイゼンハワーマトリクスと高速追加'), findsOneWidget);
      expect(find.text('次へ'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      storeJa.dispose();
    });

    testWidgets('Escape shortcut finishes onboarding', (tester) async {
      final (store, _) = await makeStore();

      await tester.pumpWidget(wrapApp(store, const OnboardingScreen()));
      await tester.pumpAndSettle();

      expect(find.byType(OnboardingScreen), findsOneWidget);

      // Simulate Escape key
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.byType(OnboardingScreen), findsNothing);
      expect(store.hasSeenOnboarding, isTrue);

      await tester.pumpWidget(const SizedBox());
      store.dispose();
    });
  });
}
