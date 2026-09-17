import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/screens/settings_screen.dart';
import 'package:matrixflow_native/theme.dart';
import 'package:matrixflow_native/ui/font_policy.dart';
import 'package:provider/provider.dart';

import 'helpers.dart';

void main() {
  test('UX04: Windows sans uses YaHei UI; Android does not', () {
    const windows = AppFontPolicy(platform: TargetPlatform.windows);
    const android = AppFontPolicy(platform: TargetPlatform.android);
    expect(windows.familyFor(FontFamilyPref.sansSerif), 'Microsoft YaHei UI');
    expect(
      windows.fallbackFor(FontFamilyPref.monospace),
      contains('Microsoft YaHei UI'),
    );
    expect(windows.familyFor(FontFamilyPref.monospace), 'Consolas');
    expect(windows.familyFor(FontFamilyPref.system), isNull);
    expect(
      windows.fallbackFor(FontFamilyPref.system),
      contains('Microsoft YaHei UI'),
    );
    expect(android.familyFor(FontFamilyPref.sansSerif), isNot('Microsoft YaHei UI'));
    expect(
      android.fallbackFor(FontFamilyPref.system) ?? const <String>[],
      isNot(contains('Microsoft YaHei UI')),
    );
    expect(windows.titleWeight, FontWeight.w600);
    expect(windows.bodyWeight, FontWeight.w400);
  });

  testWidgets('UX04: theme applies Consolas plus CJK fallback and title weight', (
    tester,
  ) async {
    final theme = buildTheme(
      Brightness.light,
      ThemeColor.blue,
      fontFamilyPref: FontFamilyPref.monospace,
      platform: TargetPlatform.windows,
    );
    expect(theme.textTheme.bodyMedium?.fontWeight, FontWeight.w400);
    expect(theme.textTheme.titleMedium?.fontWeight, FontWeight.w600);
    expect(theme.textSelectionTheme.selectionColor, isNotNull);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: const Scaffold(body: Text('sample')),
      ),
    );
    final style = DefaultTextStyle.of(tester.element(find.text('sample'))).style;
    expect(style.fontFamily, 'Consolas');
    expect(style.fontFamilyFallback, contains('Microsoft YaHei UI'));
  });

  testWidgets('UX04: preview shows CJK sample and keeps stored monospace', (
    tester,
  ) async {
    final (store, _) = await makeStore(
      settings: AppSettings(fontFamily: FontFamilyPref.monospace),
    );
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: store,
        child: MaterialApp(
          theme: buildTheme(
            Brightness.light,
            store.settings.themeColor,
            fontFamilyPref: store.settings.fontFamily,
            platform: TargetPlatform.windows,
          ),
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          supportedLocales: const [Locale('en'), Locale('zh'), Locale('ja')],
          home: const SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('font-preview-card')),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const ValueKey('font-preview-sample')), findsOneWidget);
    expect(find.textContaining('紧急且重要'), findsWidgets);
    expect(find.textContaining('123'), findsWidgets);
    expect(find.byKey(const ValueKey('font-monospace-hint')), findsOneWidget);
    expect(store.settings.fontFamily, FontFamilyPref.monospace);
    await tester.tap(find.byKey(const ValueKey('font-family-sansSerif')));
    await tester.pumpAndSettle();
    expect(store.settings.fontFamily, FontFamilyPref.sansSerif);
    expect(find.byKey(const ValueKey('font-monospace-hint')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });
}
