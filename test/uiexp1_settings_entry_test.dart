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

  testWidgets('settings switch turns the neumorphic skin on, exclusive with comic', (
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

    final neuTile = find.byKey(const ValueKey('neumorphic-switch'));
    await tester.dragUntilVisible(
      neuTile,
      find.byKey(const ValueKey('settings-list')),
      const Offset(0, -240),
    );
    await tester.pump();
    expect(find.text('拟态'), findsOneWidget);
    expect(store.settings.neumorphic, isFalse);

    await tester.tap(neuTile);
    await tester.pump();
    expect(store.settings.neumorphic, isTrue);

    // Enabling the comic look clears the neumorphic one and vice versa.
    final comicTile = find.byKey(const ValueKey('comic-outline-switch'));
    await tester.dragUntilVisible(
      comicTile,
      find.byKey(const ValueKey('settings-list')),
      const Offset(0, 240),
    );
    await tester.pump();
    await tester.tap(comicTile);
    await tester.pump();
    expect(store.settings.comicOutline, isTrue);
    expect(store.settings.neumorphic, isFalse);
    await tester.dragUntilVisible(
      neuTile,
      find.byKey(const ValueKey('settings-list')),
      const Offset(0, -240),
    );
    await tester.pump();
    await tester.tap(neuTile);
    await tester.pump();
    expect(store.settings.neumorphic, isTrue);
    expect(store.settings.comicOutline, isFalse);

    final neu = buildTheme(
      Brightness.light,
      ThemeColor.blue,
      neumorphic: true,
    );
    final skin = neu.extension<NeumorphicSkin>();
    expect(skin, isNotNull);
    expect(neu.scaffoldBackgroundColor, const Color(0xFFE0DEDA));
    expect(skin!.field, skin.canvas);
    expect(skin.raisedShadows, hasLength(2));
    expect(skin.raisedShadows.first.offset.dx, lessThan(0));
    expect(skin.raisedShadows.last.offset.dx, greaterThan(0));
    expect(neu.cardTheme.elevation, 0);
    expect(neu.inputDecorationTheme.enabledBorder, isA<NeuInputBorder>());

    final plain = buildTheme(Brightness.light, ThemeColor.blue);
    expect(plain.extension<NeumorphicSkin>(), isNull);
    expect(neu.colorScheme.primary, plain.colorScheme.primary);

    final dark = buildTheme(
      Brightness.dark,
      ThemeColor.blue,
      neumorphic: true,
    );
    expect(dark.scaffoldBackgroundColor, const Color(0xFF2C2B2A));
    expect(dark.extension<NeumorphicSkin>()!.field, const Color(0xFF2C2B2A));

    // Comic wins when a backup enables both.
    final both = buildTheme(
      Brightness.light,
      ThemeColor.blue,
      comicOutline: true,
      neumorphic: true,
    );
    expect(both.extension<ComicOutline>(), isNotNull);
    expect(both.extension<NeumorphicSkin>(), isNull);

    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });
}
