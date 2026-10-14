import 'dart:ui' as ui;

import 'package:compoise/models.dart';
import 'package:compoise/screens/matrix_screen.dart';
import 'package:compoise/storage.dart';
import 'package:compoise/ui/motion_policy.dart';
import 'package:compoise/widgets/animated_task_title.dart';
import 'package:compoise/widgets/app_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'helpers.dart';

Widget _app(Store store, {bool accessibleNavigation = false}) {
  return ChangeNotifierProvider.value(
    value: store,
    child: MaterialApp(
      theme: ThemeData(useMaterial3: true, platform: TargetPlatform.android),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('en'), Locale('zh'), Locale('ja')],
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(accessibleNavigation: accessibleNavigation),
        child: child!,
      ),
      home: const MatrixHome(),
    ),
  );
}

void main() {
  testWidgets('a notice with an action still goes away on its own', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(accessibleNavigation: true),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showAppNotice(
                context,
                'Deleted',
                actionLabel: 'Undo',
                onAction: () {},
              ),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('Deleted'), findsOneWidget);
    await tester.pump(kNoticeDuration);
    await tester.pumpAndSettle();
    expect(find.text('Deleted'), findsNothing);
  });

  for (final a11y in [false, true]) {
    testWidgets('swipe: complete is silent, delete undo auto-hides '
        '(accessibleNavigation: $a11y)', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final (store, _) = await makeStore();
      store.addTasks([
        store.newTask('Swipe done', quadrant: qDo),
        store.newTask('Swipe gone', quadrant: qDo),
      ]);
      await tester.pumpWidget(_app(store, accessibleNavigation: a11y));
      await tester.pumpAndSettle();

      await tester.drag(find.text('Swipe done'), const Offset(300, 0));
      await tester.pumpAndSettle();
      expect(
        store.tasks.firstWhere((t) => t.title == 'Swipe done').completed,
        isTrue,
      );
      expect(find.byType(SnackBar), findsNothing);

      await tester.drag(find.text('Swipe gone'), const Offset(-300, 0));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('undo-action-btn')), findsOneWidget);

      await tester.pump(kNoticeDuration);
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);

      await tester.pumpWidget(const SizedBox());
      store.dispose();
    });
  }

  group('line-by-line strikethrough', () {
    const boxes = [
      ui.TextBox.fromLTRBD(0, 0, 100, 20, TextDirection.ltr),
      ui.TextBox.fromLTRBD(0, 20, 50, 40, TextDirection.ltr),
      ui.TextBox.fromLTRBD(0, 40, 100, 60, TextDirection.ltr),
    ];
    List<double> at(double p) =>
        StrikeThroughPainter(boxes: boxes, progress: p).segmentWidths;

    test('lines are struck top to bottom, each to its own width', () {
      expect(at(0), [0, 0, 0]);
      expect(at(0.2), [50, 0, 0]);
      expect(at(0.4), [100, 0, 0]);
      expect(at(0.5), [100, 25, 0]);
      expect(at(0.8), [100, 50, 50]);
      expect(at(1), [100, 50, 100]);
    });

    testWidgets('a long title finishes in the same fixed time', (tester) async {
      for (final text in ['Short', List.filled(12, 'long title').join(' ')]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: SizedBox(
                width: 160,
                child: AnimatedStrikeThroughText(
                  key: ValueKey(text),
                  text: text,
                  completed: false,
                  strikeKey: const ValueKey('s'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: SizedBox(
                width: 160,
                child: AnimatedStrikeThroughText(
                  key: ValueKey(text),
                  text: text,
                  completed: true,
                  strikeKey: const ValueKey('s'),
                ),
              ),
            ),
          ),
        );
        StrikeThroughPainter painter() =>
            tester
                    .widget<CustomPaint>(find.byKey(const ValueKey('s')))
                    .foregroundPainter!
                as StrikeThroughPainter;
        await tester.pump();
        await tester.pump(MotionPolicy.strikethrough ~/ 2);
        expect(painter().progress, inExclusiveRange(0, 1));
        await tester.pump(MotionPolicy.strikethrough ~/ 2);
        expect(painter().progress, 1.0);
        final full = painter().segmentWidths;
        for (var i = 0; i < full.length; i++) {
          expect(full[i], painter().boxes[i].right - painter().boxes[i].left);
        }
      }
    });
  });
}
