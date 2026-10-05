import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/screens/settings_screen.dart';
import 'package:provider/provider.dart';

import 'helpers.dart';

void main() {
  testWidgets('settings opens the neumorphic comparison and can switch it', (
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

    final tile = find.byKey(const ValueKey('neumorphic-compare-tile'));
    await tester.dragUntilVisible(
      tile,
      find.byKey(const ValueKey('settings-list')),
      const Offset(0, -240),
    );
    await tester.pump();
    expect(find.text('实验性功能'), findsOneWidget);
    expect(find.text('轻拟态外观'), findsOneWidget);

    await tester.tap(tile);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const Key('uiexp1-scroll')), findsOneWidget);
    expect(find.byKey(const Key('uiexp1-skin-neu')), findsOneWidget);
    expect(find.byKey(const Key('uiexp1-skin-material')), findsNothing);

    await tester.tap(find.byKey(const Key('uiexp1-show-material')));
    await tester.pump();
    expect(find.byKey(const Key('uiexp1-skin-material')), findsOneWidget);
    expect(find.byKey(const Key('uiexp1-skin-neu')), findsNothing);

    await tester.tap(find.byType(BackButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('neumorphic-compare-tile')), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });
}
