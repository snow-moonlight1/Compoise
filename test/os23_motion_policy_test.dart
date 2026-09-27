import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/screens/matrix_screen.dart';
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

Widget wrapMatrix(Store store) {
  return ChangeNotifierProvider.value(
    value: store,
    child: const MaterialApp(home: MatrixHome()),
  );
}

void setViewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Seeds 15 tasks into Q1 (enough to scroll) and one task into Q2 (the item we
/// drag into Q1). Tasks are created then added in one batch.
Future<void> seedMatrix(Store store) async {
  final q1Tasks = [
    for (var i = 0; i < 15; i++) store.newTask('Do $i', quadrant: qDo),
  ];
  final moving = store.newTask('Moving Task', quadrant: qPlan);
  store.addTasks([...q1Tasks.reversed, moving]);
}

Future<void> dropMovingTaskOntoQ1(WidgetTester tester) async {
  final gesture = await tester.startGesture(
    tester.getCenter(find.text('Moving Task')),
  );
  await tester.pump(const Duration(milliseconds: 600));
  await gesture.moveTo(
    tester.getCenter(find.byKey(ValueKey('quadrant-header-$qDo'))),
  );
  await tester.pump();
  await gesture.up();
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

  testWidgets(
    'OS23: toggling reduce motion mid-page-turn jumps to the target slide',
    (tester) async {
      final (store, _) = await makeStore(
        settings: AppSettings()..reduceMotion = false,
      );

      await tester.pumpWidget(wrapOnboarding(store));
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('onboarding-next-btn')));
      // 120ms into the 300ms slide: still on slide 0.
      await tester.pump(const Duration(milliseconds: 120));
      expect(find.byKey(const ValueKey('onboarding-prev-btn')), findsNothing);

      // Flip reduce motion on while the turn is sliding.
      store.updateSettings((s) => s..reduceMotion = true);
      await tester.pump(); // didChangeDependencies schedules the jump
      await tester.pump(); // post-frame jump lands; page change settles
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
    'OS23: page turn still snaps after the destination crosses center',
    (tester) async {
      final (store, _) = await makeStore(
        settings: AppSettings()..reduceMotion = false,
      );
      await tester.pumpWidget(wrapOnboarding(store));
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('onboarding-next-btn')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 190));
      final pageView = tester.widget<PageView>(find.byType(PageView));
      expect(pageView.controller!.page, greaterThan(0.5));
      expect(pageView.controller!.page, lessThan(1));

      store.updateSettings((s) => s..reduceMotion = true);
      await tester.pump();
      await tester.pump();
      expect(pageView.controller!.page, 1);

      await tester.pumpWidget(const SizedBox());
      store.dispose();
    },
  );

  testWidgets(
    'OS23: dropped task jumps a scrolled pane to top at once under reduce motion',
    (tester) async {
      setViewport(tester, const Size(600, 700));
      final (store, _) = await makeStore(
        settings: AppSettings()..reduceMotion = true,
      );
      await seedMatrix(store);

      await tester.pumpWidget(wrapMatrix(store));
      await tester.pumpAndSettle();

      final q1List = find.byKey(
        PageStorageKey('${store.activeBoardId}-$qDo'),
      );
      await tester.drag(q1List, const Offset(0, -300));
      await tester.pumpAndSettle();
      final scrollable = tester.state<ScrollableState>(
        find.descendant(of: q1List, matching: find.byType(Scrollable)),
      );
      expect(scrollable.position.pixels, greaterThan(100));

      await dropMovingTaskOntoQ1(tester);
      // Only two frames: the post-drop callback must jump, not tween 250ms.
      await tester.pump();
      await tester.pump();

      expect(store.tasksIn(qDo).first.title, 'Moving Task');
      expect(scrollable.position.pixels, 0.0);

      await tester.pumpWidget(const SizedBox());
      store.dispose();
    },
  );

  testWidgets(
    'OS23: toggling reduce motion during scroll-to-top finishes at top immediately',
    (tester) async {
      setViewport(tester, const Size(600, 700));
      final (store, _) = await makeStore(
        settings: AppSettings()..reduceMotion = false,
      );
      await seedMatrix(store);

      await tester.pumpWidget(wrapMatrix(store));
      await tester.pumpAndSettle();

      final q1List = find.byKey(
        PageStorageKey('${store.activeBoardId}-$qDo'),
      );
      await tester.drag(q1List, const Offset(0, -300));
      await tester.pumpAndSettle();
      final scrollable = tester.state<ScrollableState>(
        find.descendant(of: q1List, matching: find.byType(Scrollable)),
      );
      final scrolledOffset = scrollable.position.pixels;
      expect(scrolledOffset, greaterThan(100));

      await dropMovingTaskOntoQ1(tester);
      await tester.pump(); // onAccept postframe creates the DrivenScrollActivity
      await tester.pump(); // first tick anchors the ticker start at this frame
      await tester.pump(const Duration(milliseconds: 100)); // 100ms elapsed
      expect(scrollable.position.pixels, lessThan(scrolledOffset));
      expect(scrollable.position.pixels, greaterThan(0));

      // Flip reduce motion on while the scroll is still running.
      store.updateSettings((s) => s..reduceMotion = true);
      await tester.pump(); // didChangeDependencies schedules the jump
      await tester.pump(); // post-frame jump lands at the top

      expect(scrollable.position.pixels, 0.0);

      // Drain timers scheduled before the toggle: Q2's retention snapshot of
      // the moved task (440ms hold+collapse) and the move SnackBar (~1.8s).
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      await tester.pumpWidget(const SizedBox());
      store.dispose();
    },
  );

  testWidgets(
    'OS23: reduce motion preserves a manually scrolled pane',
    (tester) async {
      setViewport(tester, const Size(600, 700));
      final (store, _) = await makeStore(
        settings: AppSettings()..reduceMotion = false,
      );
      await seedMatrix(store);
      await tester.pumpWidget(wrapMatrix(store));
      await tester.pumpAndSettle();

      final q1List = find.byKey(PageStorageKey('${store.activeBoardId}-$qDo'));
      await tester.drag(q1List, const Offset(0, -300));
      await tester.pumpAndSettle();
      final scrollable = tester.state<ScrollableState>(
        find.descendant(of: q1List, matching: find.byType(Scrollable)),
      );
      final offset = scrollable.position.pixels;
      expect(offset, greaterThan(100));

      store.updateSettings((s) => s..reduceMotion = true);
      await tester.pump();
      await tester.pump();
      expect(scrollable.position.pixels, offset);

      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    },
  );
}
