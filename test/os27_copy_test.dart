import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/l10n.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/screens/onboarding_screen.dart';
import 'package:matrixflow_native/storage.dart';
import 'package:provider/provider.dart';

import 'helpers.dart';

/// OS27 copy package: the three dictionaries stay aligned, and the wording a
/// first-run user reads describes what the app actually does with task text.
Widget _wrap(Store store, Widget home) => ChangeNotifierProvider.value(
  value: store,
  child: MaterialApp(
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    supportedLocales: const [Locale('en'), Locale('zh'), Locale('ja')],
    home: home,
  ),
);

void main() {
  String text(String path) =>
      File(path).readAsStringSync().replaceAll('\r\n', '\n');

  const languages = [Language.en, Language.zh, Language.ja];

  Set<String> placeholders(String value) =>
      RegExp(r'\{([A-Za-z0-9_]+)\}').allMatches(value).map((m) => m.group(1)!).toSet();

  group('OS27 dictionary shape', () {
    test('every language defines exactly the same keys', () {
      final reference = dictOf(Language.en).keys.toSet();
      for (final lang in languages) {
        final keys = dictOf(lang).keys.toSet();
        expect(
          keys.difference(reference),
          isEmpty,
          reason: '$lang defines keys the other dictionaries do not',
        );
        expect(
          reference.difference(keys),
          isEmpty,
          reason: '$lang is missing keys',
        );
      }
    });

    test('every key interpolates the same placeholders in every language', () {
      for (final key in dictOf(Language.en).keys) {
        final expected = placeholders(dictOf(Language.en)[key]!);
        for (final lang in languages.skip(1)) {
          expect(
            placeholders(dictOf(lang)[key]!),
            expected,
            reason: '$key placeholder mismatch in $lang',
          );
        }
      }
    });

    test('no entry promises blanket privacy or losslessness', () {
      final banned = RegExp(
        '100%|绝对|絶対|无损失|不丢失数据|No data lost|never miss|不错过任何|見逃さない',
      );
      for (final lang in languages) {
        for (final entry in dictOf(lang).entries) {
          expect(
            banned.hasMatch(entry.value),
            isFalse,
            reason: '${lang.name}.${entry.key} over-promises',
          );
        }
      }
    });

    test('AI copy names the endpoint the task text is sent to', () {
      const marker = {
        Language.en: 'endpoint',
        Language.zh: '端点',
        Language.ja: 'エンドポイント',
      };
      for (final lang in languages) {
        final dict = dictOf(lang);
        for (final key in ['onboardingStep5Desc', 'aiNote']) {
          expect(
            dict[key]!,
            contains(marker[lang]),
            reason: '$lang.$key does not state where AI text goes',
          );
        }
      }
    });
  });

  group('OS27 onboarding and tray wording', () {
    test('the tutorial takes its wording from the dictionary', () {
      final source = text('lib/screens/onboarding_screen.dart');
      expect(source.contains('100%'), isFalse);
      expect(source, isNot(contains("?? '")));
    });

    test('the Windows tray reads its labels from the dictionary', () {
      final source = text('lib/services/desktop_shell_windows.dart');
      for (final key in [
        'trayShowWindow',
        'trayQuickAdd',
        'traySearch',
        'trayExit',
      ]) {
        expect(source, contains(key));
      }
      expect(source, isNot(contains("label: '")));
    });

    const untranslated = {'DeepSeek', 'Qwen', 'Doubao', 'OpenAI'};
    final latinOnly = RegExp(r'[A-Za-z]{2,}');
    final cjk = RegExp(
      r'[\p{Script=Han}\p{Script=Hiragana}\p{Script=Katakana}]',
      unicode: true,
    );

    for (final lang in [Language.zh, Language.ja]) {
      for (var slide = 1; slide <= 5; slide++) {
        testWidgets(
          '${lang.name} onboarding slide $slide has no English leftovers',
          (tester) async {
            final (store, _) = await makeStore(
              settings: AppSettings(language: lang),
            );
            await tester.pumpWidget(
              _wrap(store, const OnboardingScreen(isReviewMode: true)),
            );
            await tester.pumpAndSettle();
            for (var i = 1; i < slide; i++) {
              await tester.tap(
                find.byKey(const ValueKey('onboarding-next-btn')),
              );
              await tester.pumpAndSettle();
            }

            final visible =
                tester
                    .widgetList<Text>(find.byType(Text))
                    .map((widget) => widget.data ?? '')
                    .where((value) => value.isNotEmpty)
                    .toList();
            expect(visible, isNotEmpty);
            for (final value in visible) {
              if (!latinOnly.hasMatch(value)) continue;
              expect(
                cjk.hasMatch(value) || untranslated.contains(value),
                isTrue,
                reason: '"$value" left untranslated in ${lang.name}',
              );
            }

            store.dispose();
          },
        );
      }
    }

    testWidgets('the drag slide shows its own hint, not the submit hint', (
      tester,
    ) async {
      final (store, _) = await makeStore();
      await tester.pumpWidget(
        _wrap(store, const OnboardingScreen(isReviewMode: true)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('onboarding-next-btn')));
      await tester.pumpAndSettle();

      final dict = dictOf(Language.en);
      expect(find.text(dict['onboardingDragHint']!), findsOneWidget);
      expect(find.text(dict['shortcutHint']!), findsNothing);
      store.dispose();
    });
  });
}
