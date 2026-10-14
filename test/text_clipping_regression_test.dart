// Text clipping regressions found in the neumorphic sweep: the selection
// toolbar, the API key hint, the tip width, the quadrant titles and the
// onboarding drag sample. Plus the one-line connection test result.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:compoise/ai_presets.dart';
import 'package:compoise/ai_service.dart';
import 'package:compoise/l10n.dart';
import 'package:compoise/models.dart';
import 'package:compoise/screens/matrix_screen.dart';
import 'package:compoise/screens/onboarding_screen.dart';
import 'package:compoise/screens/settings_model_request.dart';
import 'package:compoise/screens/settings_screen.dart';
import 'package:compoise/storage.dart';
import 'package:compoise/theme.dart';
import 'package:provider/provider.dart';

import 'helpers.dart';
import 'support/settings_panels.dart';
import 'support/text_clip_probe.dart';
import 'support/field_center_probe.dart';

enum _Skin { plain, comic, neu }

Widget _app(
  Store store,
  _Skin skin,
  Widget home, {
  double scale = 1,
  Language lang = Language.zh,
}) => ChangeNotifierProvider.value(
  value: store,
  child: MaterialApp(
    theme: buildTheme(
      Brightness.light,
      ThemeColor.purple,
      comicOutline: skin == _Skin.comic,
      neumorphic: skin == _Skin.neu,
    ),
    locale: Locale(lang.name),
    supportedLocales: const [Locale('en'), Locale('zh'), Locale('ja')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: home,
  ),
);

Future<Store> _store(_Skin skin, {Language lang = Language.zh}) async {
  final (store, _) = await makeStore(
    settings: AppSettings(
      language: lang,
      neumorphic: skin == _Skin.neu,
      comicOutline: skin == _Skin.comic,
      themeColor: ThemeColor.purple,
    ),
  );
  return store;
}

void main() {
  for (final skin in _Skin.values) {
    testWidgets('${skin.name}: selection toolbar labels are not cut', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(411, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final store = await _store(skin);
      await tester.pumpWidget(_app(store, skin, const SettingsScreen()));
      await tester.pumpAndSettle();
      await openSettingsPanel(tester, 'settings-assistant-row');
      final field = find.byType(TextField).at(1);
      await tester.enterText(field, 'deepseek-flash');
      await tester.longPress(
        find.descendant(of: field, matching: find.byType(EditableText)),
      );
      await tester.pumpAndSettle();

      final buttons = find.byType(TextSelectionToolbarTextButton);
      expect(buttons, findsWidgets);
      for (final button in buttons.evaluate()) {
        final label = find.descendant(
          of: find.byWidget(button.widget),
          matching: find.byType(RichText),
        );
        // 14px label in the 44px strip: the full glyph height must fit.
        expect(tester.getSize(label.first).height, greaterThanOrEqualTo(14));
      }
      expect(findTextClips(tester), isEmpty);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    });
  }

  testWidgets('neumorphic: API key hint sits in the middle of the well', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(411, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = await _store(_Skin.neu);
    await tester.pumpWidget(_app(store, _Skin.neu, const SettingsScreen()));
    await tester.pumpAndSettle();
    await openSettingsPanel(tester, 'settings-assistant-row');

    final field = tester.getRect(find.byKey(const ValueKey('api-key-input')));
    expect(offCenterFields(tester), isEmpty);

    // The tip under the fields lines up with them.
    final preset = getAIProviderPreset(store.aiConfig.provider);
    final tip = find.ancestor(
      of: find.text(
        store.t['aiRecommendTip']!
            .replaceAll('{provider}', preset.name(store.t))
            .replaceAll('{model}', preset.defaultModel),
      ),
      matching: find.byType(CustomPaint),
    );
    final tipBox = tester.getRect(tip.first);
    expect((tipBox.left - field.left).abs(), lessThanOrEqualTo(1));
    expect((tipBox.right - field.right).abs(), lessThanOrEqualTo(1));
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('quadrant titles get a third line instead of spilling', (
    tester,
  ) async {
    final store = await _store(_Skin.plain, lang: Language.en);
    store.addTasks([store.newTask('Buy milk', quadrant: qPlan)]);
    await tester.pumpWidget(_app(store, _Skin.plain, const MatrixHome()));
    await tester.pumpAndSettle();
    final title = tester.widget<Text>(find.text(store.t['q4']!).first);
    expect(title.maxLines, 3);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('onboarding drag sample fits 360dp with 1.3x text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = await _store(_Skin.plain, lang: Language.en);
    await tester.pumpWidget(
      _app(
        store,
        _Skin.plain,
        const OnboardingScreen(isReviewMode: true),
        scale: 1.3,
        lang: Language.en,
      ),
    );
    await tester.pumpAndSettle();
    // The test font is far wider than real fonts, so other rows may report
    // overflow here; only the drag sample row is checked.
    var checked = false;
    for (var i = 0; i < 5; i++) {
      tester.takeException();
      final sample = find.text(store.t['onboardingSampleDragTask']!);
      if (sample.hitTestable().evaluate().isNotEmpty) {
        final row = find.ancestor(of: sample, matching: find.byType(Row)).at(1);
        final flex = tester.renderObject<RenderFlex>(row);
        expect(flex.toStringShort(), isNot(contains('OVERFLOWING')));
        checked = true;
      }
      final next = find.byKey(const ValueKey('onboarding-next-btn'));
      await tester.tap(next);
      await tester.pumpAndSettle();
    }
    tester.takeException();
    expect(checked, isTrue);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  group('connection test result is one plain sentence', () {
    final t = dictOf(Language.zh);
    AiProbeStep step(String code, {bool ok = false, int? status}) =>
        AiProbeStep(
          kind: AiProbeKind.modelGeneration,
          attempted: true,
          ok: ok,
          code: code,
          status: status,
        );

    test('success and reasoning-only both read as connected', () {
      expect(connectionResultText(step('aiGenerationOk', ok: true), t), '连接成功');
      expect(connectionResultText(step('aiGenerationThinkingOnly'), t), '连接成功');
    });

    test('failures name the cause without status codes', () {
      final cases = {
        step('aiUnauthorized', status: 401): t['aiUnauthorized'],
        step('aiNetworkError'): t['connFailNetwork'],
        step('requestTimeout'): t['connFailNetwork'],
        step('aiHttpError', status: 402): t['connFailQuota'],
        step('aiHttpError', status: 429): t['connFailQuota'],
        step('aiHttpError', status: 404): t['connFailModel'],
        step('aiHttpError', status: 503): t['connFailServer'],
        step('aiMissingModel'): t['connFailNoModel'],
        step('aiMissingConfig'): t['connFailNoConfig'],
      };
      cases.forEach((s, expected) {
        final text = connectionResultText(s, t);
        expect(text, expected);
        expect(text, isNot(matches(RegExp(r'\d{3}'))));
      });
    });
  });
}
