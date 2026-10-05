// OS18 — 单次字号缩放与文本测量。全部为合成数据与 mock 持久化，不接触真实任务库、
// 设备无障碍设置或 AI 凭据；双端人工验收需单独进行。
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
import 'package:matrixflow_native/widgets/task_card.dart';
import 'package:provider/provider.dart';

import 'helpers.dart';
import 'support/settings_panels.dart';

/// Non-linear scaling of the shape platforms use: identical at 1 dp, a separate
/// step for real glyph sizes. Two instances are indistinguishable through the
/// value the pre-OS18 measurement cache keyed on.
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

/// The shell shape from `main.dart`: [MaterialApp] rebuilds from the Store and
/// contributes exactly one [CombinedTextScaler].
Widget _app(
  Store store,
  Widget home, {
  TextScaler systemScaler = TextScaler.noScaling,
}) => ChangeNotifierProvider.value(
  value: store,
  child: Consumer<Store>(
    builder: (context, store, _) => MaterialApp(
      theme: buildTheme(
        Brightness.light,
        store.settings.themeColor,
        fontFamilyPref: store.settings.fontFamily,
      ),
      locale: const Locale('en'),
      supportedLocales: const [Locale('en'), Locale('zh'), Locale('ja')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) => MediaQuery(
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
    (tester.widget<CustomPaint>(find.byKey(strikeKey))).foregroundPainter
        as StrikeThroughPainter;

/// Line fragments reported by the rendered [Text] itself — a measurement path
/// independent of the widget's private [TextPainter].
List<ui.TextBox> _renderedBoxes(WidgetTester tester, Key textKey, int length) =>
    (tester.renderObject(find.byKey(textKey)) as RenderParagraph)
        .getBoxesForSelection(
          TextSelection(baseOffset: 0, extentOffset: length),
        );

bool _boxesMatch(List<ui.TextBox> a, List<ui.TextBox> b) {
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

Widget _title(
  String text, {
  Key textKey = const ValueKey('t-text'),
  Key strikeKey = const ValueKey('t-strike'),
  double width = 600,
  int? maxLines,
}) => Scaffold(
  body: SizedBox(
    width: width,
    child: AnimatedStrikeThroughText(
      text: text,
      completed: true,
      textKey: textKey,
      strikeKey: strikeKey,
      maxLines: maxLines,
      overflow: maxLines == null ? TextOverflow.visible : TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 16),
    ),
  ),
);

const _en =
    'Ship release notes for the matrix app and verify every acceptance item';
const _zh = '紧急且重要：完成四象限待办的发版说明，并逐条核对验收清单与回归结果';
const _ja = '緊急かつ重要：リリースノートを執筆し、受入基準をすべて確認する作業を行う';
const _mixed = '方寸 待办：ship OS18 notes 日本語テスト and re-measure twice';

const _texts = [_en, _zh, _ja, _mixed];

/// Font preview and theme color each live on their own settings page.
/// [toPreview] opens the font page. Motion tests open the color page themselves.
Future<Store> _pumpSettings(
  WidgetTester tester, {
  AppSettings? settings,
  TextScaler systemScaler = TextScaler.noScaling,
  bool toPreview = true,
}) async {
  final (store, _) = await makeStore(settings: settings);
  await tester.pumpWidget(
    _app(store, const SettingsScreen(), systemScaler: systemScaler),
  );
  await tester.pumpAndSettle();
  if (toPreview) {
    await openSettingsPanel(tester, 'settings-font-row');
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('font-preview-card')),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }
  return store;
}

Size _dotSize(WidgetTester tester, ThemeColor color) => tester.getSize(
  find.descendant(
    of: find.byKey(ValueKey('theme-color-hit-${color.name}')),
    matching: find.byType(AnimatedContainer),
  ),
);

AnimatedContainer _dot(WidgetTester tester, ThemeColor color) =>
    tester.widget<AnimatedContainer>(
      find.descendant(
        of: find.byKey(ValueKey('theme-color-hit-${color.name}')),
        matching: find.byType(AnimatedContainer),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('OS18 settings font preview', () {
    // Wide enough that no preview line wraps at the sizes under test, so its
    // box is proportional to the effective font size.
    testWidgets(
      'system and app scale each apply exactly once, in combination',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1700, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final base = await _pumpSettings(tester);
        final reference = tester
            .getSize(find.byKey(const ValueKey('font-preview-title')))
            .width;
        base.dispose();
        expect(reference, greaterThan(0));

        const appScales = {
          FontSizePref.small: 0.88,
          FontSizePref.standard: 1.0,
          FontSizePref.large: 1.16,
        };
        for (final entry in appScales.entries) {
          for (final system in const [1.0, 1.25, 2.0]) {
            final store = await _pumpSettings(
              tester,
              settings: AppSettings()..fontSize = entry.key,
              systemScaler: TextScaler.linear(system),
            );

            final title = tester
                .getSize(find.byKey(const ValueKey('font-preview-title')))
                .width;
            expect(
              title / reference,
              closeTo(system * entry.value, 0.03),
              reason: '${entry.key.name} on system scale $system',
            );
            store.dispose();
          }
        }
      },
    );

    testWidgets('the preview grows like an ordinary 16 dp body Text', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1700, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final (store, _) = await makeStore(
        settings: AppSettings()..fontSize = FontSizePref.large,
      );
      await tester.pumpWidget(
        _app(
          store,
          Column(
            children: const [
              Expanded(child: SettingsScreen()),
              Text(
                'Ship notes',
                key: ValueKey('reference-title'),
                style: TextStyle(fontSize: 16, height: 1.35),
              ),
            ],
          ),
          systemScaler: const TextScaler.linear(1.25),
        ),
      );
      await tester.pumpAndSettle();
      // The font page is its own route, so the reference line on the page
      // underneath is covered once that route is open. Measure it first.
      final referenceHeight = tester
          .getSize(find.byKey(const ValueKey('reference-title')))
          .height;
      await openSettingsPanel(tester, 'settings-font-row');
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('font-preview-card')),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      // Both lines carry an explicit height: 1.35, so their box heights are a
      // direct read-out of the effective font size the scaler produced.
      expect(
        tester.getSize(find.byKey(const ValueKey('font-preview-title'))).height,
        closeTo(referenceHeight, 0.5),
        reason: 'the preview scaled a 16 dp line differently from the app body',
      );
      store.dispose();
    });

    testWidgets('title and sample keep their 16:14 ratio at every scale', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1700, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      for (final pref in FontSizePref.values) {
        final store = await _pumpSettings(
          tester,
          settings: AppSettings()..fontSize = pref,
          systemScaler: const TextScaler.linear(1.25),
        );

        // Both lines declare an explicit height, so their boxes are a direct
        // read-out of the effective font size: 16 x 1.35 against 14 x 1.4.
        final title = tester
            .getSize(find.byKey(const ValueKey('font-preview-title')))
            .height;
        final body = tester
            .getSize(find.byKey(const ValueKey('font-preview-body')))
            .height;
        expect(
          title / body,
          closeTo((16 * 1.35) / (14 * 1.4), 0.05),
          reason: '${pref.name} must not scale only one preview line',
        );
        store.dispose();
      }
    });
  });

  group('OS18 strikethrough measurement', () {
    testWidgets('lines track the rendered text across width and scale', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(900, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final (store, _) = await makeStore();

      for (final text in _texts) {
        for (final width in [240.0, 360.0, 720.0]) {
          for (final scaler in [
            TextScaler.noScaling,
            const TextScaler.linear(1.25),
            const TextScaler.linear(2.0),
            const _SteppedTextScaler(1.4),
          ]) {
            await tester.pumpWidget(
              _app(store, _title(text, width: width), systemScaler: scaler),
            );
            await tester.pumpAndSettle();

            final boxes = _painter(tester, const ValueKey('t-strike')).boxes;
            if (width == 240.0) {
              expect(
                boxes.length,
                greaterThan(1),
                reason: 'a 240 dp column should wrap this title',
              );
            }
            expect(
              _boxesMatch(
                boxes,
                _renderedBoxes(tester, const ValueKey('t-text'), text.length),
              ),
              isTrue,
              reason:
                  'strike offset for ${text.substring(0, 4)} at width $width '
                  'with $scaler',
            );
          }
        }
      }
      store.dispose();
    });

    testWidgets('an ellipsised title strikes only the visible lines', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(900, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final (store, _) = await makeStore();

      await tester.pumpWidget(
        _app(
          store,
          _title(_zh, width: 300, maxLines: 2),
          systemScaler: const TextScaler.linear(1.6),
        ),
      );
      await tester.pumpAndSettle();

      final boxes = _painter(tester, const ValueKey('t-strike')).boxes;
      expect(boxes.length, 2);
      expect(
        _boxesMatch(
          boxes,
          _renderedBoxes(tester, const ValueKey('t-text'), _zh.length),
        ),
        isTrue,
      );
      store.dispose();
    });

    testWidgets('a non-linear scaler change re-measures the lines', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(700, 400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final (store, _) = await makeStore();
      const text = 'Ship notes';

      Widget tree(double step) =>
          _app(store, _title(text), systemScaler: _SteppedTextScaler(step));

      await tester.pumpWidget(tree(1.0));
      await tester.pumpAndSettle();
      final before = _painter(tester, const ValueKey('t-strike')).boxes.single;

      await tester.pumpWidget(tree(1.4));
      await tester.pumpAndSettle();
      final after = _painter(tester, const ValueKey('t-strike')).boxes.single;

      // Glyph advances are rasterised per glyph, so growth is proportional
      // rather than exactly 1.4x; a stale cache would stay at 1.0x.
      expect(after.right, greaterThan(before.right * 1.2));
      expect(
        _boxesMatch(
          _painter(tester, const ValueKey('t-strike')).boxes,
          _renderedBoxes(tester, const ValueKey('t-text'), text.length),
        ),
        isTrue,
        reason: 'the strike kept the geometry of the previous scaler',
      );
      store.dispose();
    });

    testWidgets('unchanged layout reuses the cache, new width invalidates', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(700, 400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final (store, _) = await makeStore();

      await tester.pumpWidget(_app(store, _title(_en)));
      await tester.pumpAndSettle();
      final first = _painter(tester, const ValueKey('t-strike')).boxes;

      await tester.pumpWidget(_app(store, _title(_en)));
      await tester.pumpAndSettle();
      expect(
        identical(first, _painter(tester, const ValueKey('t-strike')).boxes),
        isTrue,
        reason: 'an unchanged layout re-measured the paragraph',
      );

      await tester.pumpWidget(_app(store, _title(_en, width: 300)));
      await tester.pumpAndSettle();
      final resized = _painter(tester, const ValueKey('t-strike')).boxes;
      expect(
        identical(first, resized),
        isFalse,
        reason: 'a narrower width must invalidate the cache',
      );
      expect(
        _boxesMatch(
          resized,
          _renderedBoxes(tester, const ValueKey('t-text'), _en.length),
        ),
        isTrue,
      );
      store.dispose();
    });
  });

  group('OS18 settings motion and OS02 hierarchy', () {
    testWidgets('the theme color dot still tweens while motion is allowed', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(420, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final store = await _pumpSettings(tester, toPreview: false);
      await openSettingsPanel(tester, 'settings-color-row');

      expect(
        _dot(tester, ThemeColor.purple).duration,
        const Duration(milliseconds: 200),
      );
      final unselected = _dotSize(tester, ThemeColor.purple).width;

      await tester.tap(find.byKey(const ValueKey('theme-color-hit-purple')));
      // The first pump starts the tween; only the next one samples it.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final mid = _dotSize(tester, ThemeColor.purple).width;
      expect(mid, greaterThan(unselected));
      expect(
        mid,
        lessThan(34),
        reason: 'halfway through the 200 ms tween the dot must not be settled',
      );
      await tester.pumpAndSettle();
      expect(_dotSize(tester, ThemeColor.purple).width, closeTo(34, 0.1));
      expect(store.settings.themeColor, ThemeColor.purple);
      store.dispose();
    });

    testWidgets('reduceMotion takes the dot straight to its final state', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(420, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final store = await _pumpSettings(
        tester,
        settings: AppSettings()..reduceMotion = true,
        toPreview: false,
      );
      await openSettingsPanel(tester, 'settings-color-row');

      expect(_dot(tester, ThemeColor.purple).duration, Duration.zero);
      final unselected = _dotSize(tester, ThemeColor.purple).width;
      expect(unselected, closeTo(28, 0.1));

      await tester.tap(find.byKey(const ValueKey('theme-color-hit-purple')));
      await tester.pump(const Duration(milliseconds: 1));
      expect(
        _dotSize(tester, ThemeColor.purple).width,
        closeTo(34, 0.1),
        reason: 'one frame must already show the settled selected size',
      );
      expect(store.settings.themeColor, ThemeColor.purple);

      // OS19 keeps a real 48 dp band around every dot, motion setting aside.
      for (final color in ThemeColor.values) {
        final band = tester.getSize(
          find.byKey(ValueKey('theme-color-hit-${color.name}')),
        );
        expect(band.width, greaterThanOrEqualTo(48));
        expect(band.height, greaterThanOrEqualTo(48));
      }
      store.dispose();
    });

    testWidgets(
      'parent and subtask strikes stay per row when text is enlarged',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(900, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final (store, _) = await makeStore(
          settings: AppSettings()..fontSize = FontSizePref.large,
        );
        final parent = store.newTask(_en, quadrant: qDo)
          ..completed = true
          ..subtasks = [
            SubTask(id: 'sub-a', title: _zh, completed: true),
            SubTask(id: 'sub-b', title: _ja, completed: true),
          ];
        store.addTasks([parent]);

        await tester.pumpWidget(
          _app(
            store,
            Scaffold(
              body: SizedBox(
                width: 420,
                child: TaskCard(
                  task: parent,
                  entranceIndex: 0,
                  onChanged: () {},
                  onEdit: () {},
                  onDelete: () {},
                  onDecompose: () {},
                  onDecomposeStart: () {},
                  expanded: true,
                  onToggleExpand: () {},
                ),
              ),
            ),
            systemScaler: const TextScaler.linear(1.25),
          ),
        );
        await tester.pumpAndSettle();

        final parentKey = ValueKey('task-strike-${parent.id}');
        final parentBoxes = _painter(tester, parentKey).boxes;
        expect(parentBoxes.length, greaterThan(1));
        expect(
          _boxesMatch(
            parentBoxes,
            _renderedBoxes(
              tester,
              ValueKey('task-title-${parent.id}'),
              _en.length,
            ),
          ),
          isTrue,
          reason: 'the parent row struck the wrong lines',
        );

        for (final sub in parent.subtasks) {
          final titleKey = ValueKey('subtask-title-text-${sub.id}');
          expect(
            _boxesMatch(
              _painter(tester, ValueKey('subtask-strike-${sub.id}')).boxes,
              _renderedBoxes(tester, titleKey, sub.title.length),
            ),
            isTrue,
            reason: 'subtask ${sub.id} struck the wrong lines',
          );
        }
        store.dispose();
      },
    );
  });
}
