import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/experiments/neumorphic/neumorphic.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/theme.dart';

/// Evidence and caches for this package stay outside the git worktree.
Directory uiexp1PrivateRoot() {
  final override = Platform.environment['UIEXP1_PRIVATE_ROOT'];
  final path = (override != null && override.isNotEmpty)
      ? override
      : Platform.isWindows
      ? r'D:\Dev_project\martix-uiexp-1-private'
      : '${Directory.systemTemp.path}${Platform.pathSeparator}uiexp1-private';
  final dir = Directory(path);
  dir.createSync(recursive: true);
  return dir;
}

Future<void> pumpUiexp(
  WidgetTester tester, {
  required Widget home,
  Size size = const Size(390, 900),
  double textScale = 1,
  bool highContrast = false,
  bool reduceMotion = false,
  Brightness brightness = Brightness.light,
  Locale locale = const Locale('zh'),
  EdgeInsets viewInsets = EdgeInsets.zero,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: locale,
      supportedLocales: const [Locale('zh'), Locale('en'), Locale('ja')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: buildTheme(brightness, ThemeColor.blue),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          highContrast: highContrast,
          disableAnimations: reduceMotion,
          viewInsets: viewInsets,
        ),
        child: child!,
      ),
      home: home,
    ),
  );
}

BoxDecoration neuSurface(WidgetTester tester, Key buttonKey) {
  final box = tester.widget<DecoratedBox>(
    find.descendant(
      of: find.byKey(buttonKey),
      matching: find.byKey(NeuButton.surfaceKey),
    ),
  );
  return box.decoration as BoxDecoration;
}

BoxDecoration neuRing(WidgetTester tester, Key buttonKey) {
  final box = tester.widget<DecoratedBox>(
    find.descendant(
      of: find.byKey(buttonKey),
      matching: find.byKey(NeuButton.ringKey),
    ),
  );
  return box.decoration as BoxDecoration;
}
