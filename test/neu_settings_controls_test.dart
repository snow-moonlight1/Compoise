import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/screens/settings_screen.dart';
import 'package:matrixflow_native/theme.dart';
import 'package:provider/provider.dart';

import 'helpers.dart';
import 'support/settings_panels.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('neumorphic choices sink in, and fields share one width', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final theme = buildTheme(
      Brightness.light,
      ThemeColor.purple,
      neumorphic: true,
    );
    final (store, _) = await makeStore(
      settings: AppSettings(
        language: Language.zh,
        neumorphic: true,
        themeColor: ThemeColor.purple,
      ),
    );
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: store,
        child: MaterialApp(
          theme: theme,
          locale: const Locale('zh'),
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          supportedLocales: const [Locale('zh'), Locale('en'), Locale('ja')],
          home: const SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await openSettingsPanel(tester, 'settings-language-row');
    expect(find.byType(SegmentedButton<Language>), findsNothing);

    final selected = find.byKey(const ValueKey('settings-language-zh'));
    final other = find.byKey(const ValueKey('settings-language-en'));
    expect(selected, findsOneWidget);
    expect(other, findsOneWidget);
    expect(_inset(tester, selected), isTrue);
    expect(_raised(tester, other), isTrue);
    expect(_inset(tester, other), isFalse);
    expect(
      tester.getSize(selected).height,
      closeTo(tester.getSize(other).height, 0.5),
    );
    expect(
      find.descendant(of: selected, matching: find.byIcon(Icons.check)),
      findsNothing,
    );

    await tester.tap(other);
    await tester.pumpAndSettle();
    expect(store.settings.language, Language.en);

    await openSettingsPanel(tester, 'settings-theme-row');
    final themeOn = find.widgetWithText(TextButton, store.t['themeSystem']!);
    final themeOff = find.widgetWithText(TextButton, store.t['themeLight']!);
    expect(_inset(tester, themeOn), isTrue);
    expect(_raised(tester, themeOff), isTrue);
    expect(
      tester.getSize(themeOn).height,
      closeTo(tester.getSize(themeOff).height, 0.5),
    );

    await openSettingsPanel(tester, 'settings-font-row');
    final sizeOn = find.byKey(const ValueKey('font-size-standard'));
    final sizeOff = find.byKey(const ValueKey('font-size-large'));
    expect(_inset(tester, sizeOn), isTrue);
    expect(_raised(tester, sizeOff), isTrue);
    expect(
      tester.getSize(sizeOn).height,
      closeTo(tester.getSize(sizeOff).height, 0.5),
    );

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await openSettingsPanel(tester, 'settings-assistant-row');

    final provider = find.byKey(const ValueKey('provider-selector'));
    final apiKey = find.byKey(const ValueKey('api-key-input'));
    expect(_raised(tester, provider), isTrue);
    expect(_inset(tester, provider), isFalse);

    final providerBox = tester.getRect(provider);
    final apiBox = tester.getRect(apiKey);
    expect((providerBox.width - apiBox.width).abs(), lessThan(2));

    final refresh = tester.getRect(
      find.byKey(const ValueKey('refresh-models-btn')),
    );
    expect(refresh.right, lessThanOrEqualTo(apiBox.right + 1));
    expect(refresh.left, greaterThan(apiBox.left));

    final field = tester.widget<TextField>(apiKey);
    expect(field.textAlignVertical, TextAlignVertical.top);
    final decorator = tester.widget<InputDecorator>(
      find.descendant(of: apiKey, matching: find.byType(InputDecorator)),
    );
    final resolved = decorator.decoration.applyDefaults(
      theme.inputDecorationTheme,
    );
    expect(resolved.enabledBorder, isA<NeuInputBorder>());
    expect(resolved.contentPadding!.resolve(TextDirection.ltr).top, 26);

    final label = tester.getRect(find.text(store.t['customApiKey']!));
    final hint = tester.getRect(find.text('sk-...'));
    expect(hint.top, greaterThan(label.bottom + 4));

    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });
}

bool _raised(WidgetTester tester, Finder chip) {
  return tester
      .widgetList<DecoratedBox>(
        find.ancestor(of: chip, matching: find.byType(DecoratedBox)),
      )
      .any((box) {
        final decoration = box.decoration;
        return decoration is BoxDecoration &&
            decoration.boxShadow != null &&
            decoration.boxShadow!.isNotEmpty;
      });
}

bool _inset(WidgetTester tester, Finder chip) {
  return tester
      .widgetList<CustomPaint>(
        find.ancestor(of: chip, matching: find.byType(CustomPaint)),
      )
      .any((paint) => paint.painter is NeuInsetPainter);
}
