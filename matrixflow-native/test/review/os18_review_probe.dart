// Review counterexample for F15 / OS18, added 2026-09-25. Desired behaviour is
// asserted, so these deliberately fail on the reviewed baseline (main before
// OS18). Run explicitly:
//   flutter test --no-pub test/review/os18_review_probe.dart
// Named *_probe.dart so it stays out of the default suite, matching the other
// files in this directory. All data is synthetic; no real task store, device
// setting or API credential is touched.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/screens/settings_screen.dart';
import 'package:matrixflow_native/storage.dart';
import 'package:matrixflow_native/theme.dart';
import 'package:matrixflow_native/widgets/animated_task_title.dart';
import 'package:provider/provider.dart';

import '../helpers.dart';

/// Android-style bucketed (non-linear) text scaling. Both instances answer
/// `1.0` for [TextScaler.scale] at 1 dp — the only scaler value the baseline
/// measurement cache looked at — while real glyph sizes differ by [step].
final class _SteppedTextScaler extends TextScaler {
  const _SteppedTextScaler(this.step);

  final double step;

  @override
  double scale(double fontSize) => fontSize <= 1.0 ? fontSize : fontSize * step;

  @override
  double get textScaleFactor => scale(14) / 14;

  @override
  bool operator ==(Object other) =>
      other is _SteppedTextScaler && other.step == step;

  @override
  int get hashCode => step.hashCode;
}

/// Mirrors the production app shell in `main.dart`: the [MaterialApp] rebuilds
/// from the Store, and exactly one [CombinedTextScaler] is composed in
/// [MaterialApp.builder] — nothing else may multiply the app scale.
Widget _app(
  Store store,
  Widget home, {
  TextScaler systemScaler = TextScaler.noScaling,
}) => ChangeNotifierProvider.value(
  value: store,
  child: Consumer<Store>(
    builder:
        (context, store, _) => MaterialApp(
          theme: buildTheme(
            Brightness.light,
            store.settings.themeColor,
            fontFamilyPref: store.settings.fontFamily,
          ),
          locale: const Locale('en'),
          supportedLocales: const [Locale('en'), Locale('zh'), Locale('ja')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          builder:
              (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: CombinedTextScaler(
                    systemScaler,
                    fontScaleFactor(store.settings.fontSize),
                  ),
                ),
                child: child!,
              ),
          home: home,
        ),
  ),
);

StrikeThroughPainter _painter(WidgetTester tester, Key strikeKey) =>
    (tester.widget<CustomPaint>(
          find.byKey(strikeKey),
        )).foregroundPainter
        as StrikeThroughPainter;

/// The line fragments the [Text] itself laid out — an independent measurement
/// path from the widget's private [TextPainter].
List<ui.TextBox> _renderedBoxes(WidgetTester tester, Key textKey, int length) =>
    (tester.renderObject(find.byKey(textKey)) as RenderParagraph)
        .getBoxesForSelection(
          TextSelection(baseOffset: 0, extentOffset: length),
        );

bool _sameBoxes(List<ui.TextBox> a, List<ui.TextBox> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].left != b[i].left ||
        a[i].top != b[i].top ||
        a[i].right != b[i].right ||
        a[i].bottom != b[i].bottom) {
      return false;
    }
  }
  return true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'OS-R09a: the font preview applies the app font scale exactly once',
    (tester) async {
      // Wide enough that the preview title stays on a single line at every
      // scale under test, so its width is proportional to the font size.
      await tester.binding.setSurfaceSize(const Size(1600, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final (store, _) = await makeStore();
      await tester.pumpWidget(
        _app(store, const SettingsScreen(), systemScaler: const TextScaler.linear(1.25)),
      );
      await tester.pumpAndSettle();

      final title = find.byKey(const ValueKey('font-preview-title'));
      await tester.scrollUntilVisible(
        title,
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      final standardWidth = tester.getSize(title).width;
      expect(standardWidth, greaterThan(0));

      await tester.ensureVisible(find.byKey(const ValueKey('font-size-large')));
      await tester.tap(find.byKey(const ValueKey('font-size-large')));
      await tester.pumpAndSettle();
      expect(store.settings.fontSize, FontSizePref.large);

      // MediaQuery already multiplies by fontScaleFactor(large); the preview
      // must not multiply the same preference into fontSize a second time.
      expect(
        tester.getSize(title).width / standardWidth,
        closeTo(fontScaleFactor(FontSizePref.large), 0.01),
        reason: 'the app font scale reached the preview twice',
      );

      store.dispose();
    },
  );

  testWidgets(
    'OS-R09b: a non-linear scaler re-measures the strikethrough lines',
    (tester) async {
      const textKey = ValueKey('probe-title-text');
      const strikeKey = ValueKey('probe-title-strike');
      const text = 'Ship notes';

      await tester.binding.setSurfaceSize(const Size(700, 400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final (store, _) = await makeStore();

      await tester.pumpWidget(
        _app(
          store,
          Scaffold(
            body: SizedBox(
              width: 600,
              child: AnimatedStrikeThroughText(
                text: text,
                completed: true,
                textKey: textKey,
                strikeKey: strikeKey,
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ),
          systemScaler: const _SteppedTextScaler(1.0),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        _sameBoxes(
          _painter(tester, strikeKey).boxes,
          _renderedBoxes(tester, textKey, text.length),
        ),
        isTrue,
        reason: 'the strike must start on the rendered line fragments',
      );
      final before = _painter(tester, strikeKey).boxes.single.right;

      // Same widget, same TextStyle, same width, and the same scale(1.0): only
      // the effective glyph size changed.
      await tester.pumpWidget(
        _app(
          store,
          Scaffold(
            body: SizedBox(
              width: 600,
              child: AnimatedStrikeThroughText(
                text: text,
                completed: true,
                textKey: textKey,
                strikeKey: strikeKey,
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ),
          systemScaler: const _SteppedTextScaler(1.4),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        _sameBoxes(
          _painter(tester, strikeKey).boxes,
          _renderedBoxes(tester, textKey, text.length),
        ),
        isTrue,
        reason: 'the strike kept the geometry measured under the old scaler',
      );
      // Glyph advances are rasterised per glyph, so the growth is proportional
      // rather than exactly 1.4x; a stale cache stays at 1.0x.
      expect(
        _painter(tester, strikeKey).boxes.single.right,
        closeTo(before * 1.4, before * 0.02),
        reason: 'the strike did not re-measure after the scaler changed',
      );

      store.dispose();
    },
  );
}
