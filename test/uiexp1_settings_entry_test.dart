import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/screens/settings_screen.dart';
import 'package:matrixflow_native/theme.dart';
import 'package:provider/provider.dart';

import 'helpers.dart';

void main() {
  testWidgets('settings switch turns the comic outline on for the whole app', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final (store, _) = await makeStore(
      settings: AppSettings(language: Language.zh),
    );
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: store,
        child: const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          supportedLocales: [Locale('zh'), Locale('en'), Locale('ja')],
          home: SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('外观'), findsOneWidget);
    final tile = find.byKey(const ValueKey('comic-outline-switch'));
    await tester.dragUntilVisible(
      tile,
      find.byKey(const ValueKey('settings-list')),
      const Offset(0, -240),
    );
    await tester.pump();
    expect(find.text('漫画描边'), findsOneWidget);
    expect(store.settings.comicOutline, isFalse);

    await tester.tap(tile);
    await tester.pump();
    expect(store.settings.comicOutline, isTrue);

    final comic = buildTheme(
      Brightness.light,
      ThemeColor.blue,
      comicOutline: true,
    );
    expect(comic.extension<ComicOutline>(), isNotNull);
    expect(comic.scaffoldBackgroundColor, const Color(0xFFE6E9EF));
    final side = comic.filledButtonTheme.style?.side?.resolve({});
    expect(side?.width, 2);

    final plain = buildTheme(Brightness.light, ThemeColor.blue);
    expect(plain.extension<ComicOutline>(), isNull);
    expect(comic.colorScheme.primary, plain.colorScheme.primary);
    expect(side?.color, plain.colorScheme.primary);

    final pink = buildTheme(
      Brightness.light,
      ThemeColor.pink,
      comicOutline: true,
    );
    expect(pink.colorScheme.primary, isNot(comic.colorScheme.primary));

    final dark = buildTheme(
      Brightness.dark,
      ThemeColor.blue,
      comicOutline: true,
    );
    final darkPlain = buildTheme(Brightness.dark, ThemeColor.blue);
    expect(dark.colorScheme.primary, darkPlain.colorScheme.primary);
    expect(dark.scaffoldBackgroundColor, const Color(0xFF151A21));

    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });
}
