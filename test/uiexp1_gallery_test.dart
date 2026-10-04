import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/experiments/neumorphic/neumorphic.dart';

import 'uiexp1_harness.dart';

void main() {
  for (final width in <double>[320, 390]) {
    for (final scale in <double>[1, 2, 3]) {
      for (final locale in const <Locale>[
        Locale('zh'),
        Locale('en'),
        Locale('ja'),
      ]) {
        testWidgets(
          'narrow ${width.toInt()} ${locale.languageCode} text x$scale',
          (tester) async {
            final copy = NeuCopy.of(locale);
            await pumpUiexp(
              tester,
              home: const NeuGallery(initialScene: NeuScene.note),
              size: Size(width, 980),
              textScale: scale,
              locale: locale,
            );
            expect(tester.takeException(), isNull);
            final save = tester.getRect(
              find.byKey(const Key('uiexp1-neu-save')),
            );
            expect(save.left, greaterThanOrEqualTo(-0.1));
            expect(save.right, lessThanOrEqualTo(width + 0.1));
            expect(save.height, greaterThanOrEqualTo(48));
            final note = tester.getRect(
              find.byKey(const Key('uiexp1-neu-note-body')),
            );
            expect(note.left, greaterThanOrEqualTo(-0.1));
            expect(note.right, lessThanOrEqualTo(width + 0.1));
            expect(find.text(copy.captionNote), findsOneWidget);
            expect(find.text(copy.recommendation), findsOneWidget);
          },
        );
      }
    }
  }

  testWidgets('wide layout shows Material and neumorphic together', (
    tester,
  ) async {
    await pumpUiexp(
      tester,
      home: const NeuGallery(initialScene: NeuScene.steps),
      size: const Size(800, 1100),
    );
    expect(find.byKey(const Key('uiexp1-skin-material')), findsOneWidget);
    expect(find.byKey(const Key('uiexp1-skin-neu')), findsOneWidget);
    expect(find.byKey(const Key('uiexp1-show-material')), findsNothing);
    expect(find.text(NeuCopy.zh.captionSteps), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow layout toggles skins and keeps the three scenes', (
    tester,
  ) async {
    await pumpUiexp(
      tester,
      home: const NeuGallery(),
      size: const Size(390, 900),
    );
    expect(find.byKey(const Key('uiexp1-skin-neu')), findsOneWidget);
    expect(find.byKey(const Key('uiexp1-skin-material')), findsNothing);
    expect(find.text(NeuCopy.zh.captionSingle), findsOneWidget);
    expect(find.text(NeuCopy.zh.parentTitle), findsNothing);
    expect(find.byType(Checkbox), findsNWidgets(1));

    await tester.tap(find.byKey(const Key('uiexp1-scene-steps')));
    await tester.pump();
    expect(find.text(NeuCopy.zh.captionSteps), findsOneWidget);
    expect(find.text(NeuCopy.zh.parentTitle), findsOneWidget);
    expect(find.byType(Checkbox), findsNWidgets(2));

    await tester.tap(find.byKey(const Key('uiexp1-scene-note')));
    await tester.pump();
    expect(find.text(NeuCopy.zh.noteBody), findsOneWidget);
    expect(find.text(NeuCopy.zh.propertySummary), findsOneWidget);

    await tester.enterText(find.byKey(const Key('uiexp1-neu-note')), '甲\n乙');
    await tester.pump();
    expect(find.byType(Checkbox), findsNWidgets(2));

    await tester.ensureVisible(find.byKey(const Key('uiexp1-show-material')));
    await tester.tap(find.byKey(const Key('uiexp1-show-material')));
    await tester.pump();
    expect(find.byKey(const Key('uiexp1-skin-material')), findsOneWidget);
    expect(find.byKey(const Key('uiexp1-skin-neu')), findsNothing);
    expect(find.byType(FilledButton), findsWidgets);
  });

  testWidgets('save, schedule, and delete stay inside the sample', (
    tester,
  ) async {
    await pumpUiexp(
      tester,
      home: const NeuGallery(),
      size: const Size(390, 900),
    );
    await tester.ensureVisible(find.byKey(const Key('uiexp1-neu-save')));
    await tester.tap(find.byKey(const Key('uiexp1-neu-save')));
    await tester.pump();
    expect(find.text(NeuCopy.zh.statusSaved), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('uiexp1-neu-schedule')));
    await tester.tap(find.byKey(const Key('uiexp1-neu-schedule')));
    await tester.pump();
    expect(find.text(NeuCopy.zh.statusScheduled), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('uiexp1-neu-delete')));
    await tester.tap(find.byKey(const Key('uiexp1-neu-delete')));
    await tester.pump();
    expect(find.text(NeuCopy.zh.deleteError), findsWidgets);
    expect(find.text(NeuCopy.zh.statusBlocked), findsOneWidget);
  });

  testWidgets('locale switch, contrast, motion, and keyboard inset', (
    tester,
  ) async {
    await pumpUiexp(
      tester,
      home: const NeuGallery(),
      size: const Size(390, 700),
      viewInsets: const EdgeInsets.only(bottom: 280),
    );
    await tester.tap(find.byKey(const Key('uiexp1-locale-en')));
    await tester.pump();
    expect(find.text(NeuCopy.en.save), findsWidgets);

    await tester.tap(find.byKey(const Key('uiexp1-toggle-contrast')));
    await tester.pump();
    expect(neuSurface(tester, const Key('uiexp1-neu-save')).boxShadow, isNull);

    await tester.tap(find.byKey(const Key('uiexp1-toggle-contrast')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('uiexp1-toggle-motion')));
    await tester.pump();
    expect(neuSurface(tester, const Key('uiexp1-neu-save')).boxShadow, isNull);
    expect(
      (neuSurface(tester, const Key('uiexp1-neu-save')).border! as Border)
          .top
          .width,
      greaterThanOrEqualTo(2),
    );

    await tester.ensureVisible(find.byKey(const Key('uiexp1-neu-save')));
    final save = tester.getRect(find.byKey(const Key('uiexp1-neu-save')));
    expect(save.top, lessThan(700 - 280));
    expect(save.bottom, greaterThan(0));
  });

  testWidgets('matrix samples expose pressed, focus, disabled, and error', (
    tester,
  ) async {
    await pumpUiexp(
      tester,
      home: const NeuGallery(),
      size: const Size(390, 900),
    );
    final pressed = neuSurface(
      tester,
      const Key('uiexp1-matrix-primary-pressed'),
    );
    final live = neuSurface(tester, const Key('uiexp1-neu-save'));
    expect(pressed.color, isNot(live.color));
    expect(
      (neuRing(tester, const Key('uiexp1-matrix-secondary-focused')).border!
              as Border)
          .top
          .color
          .a,
      greaterThan(0),
    );
    expect(
      tester.getSemantics(
        find.byKey(const Key('uiexp1-matrix-secondary-disabled')),
      ),
      containsSemantics(isButton: true, isEnabled: false),
    );
    expect(
      tester.getSemantics(find.byKey(const Key('uiexp1-matrix-danger-error'))),
      containsSemantics(isButton: true, hint: NeuCopy.zh.deleteError),
    );
    expect(find.text(NeuCopy.zh.deleteError), findsWidgets);
  });
}
