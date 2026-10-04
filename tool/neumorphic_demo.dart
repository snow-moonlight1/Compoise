import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:matrixflow_native/experiments/neumorphic/neumorphic.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/theme.dart';

/// Headless-safe entry for the experiment gallery. It is not the production
/// app: `flutter run` without `-t` still starts `lib/main.dart`.
void main() {
  runApp(const NeuDemoApp());
}

class NeuDemoApp extends StatelessWidget {
  const NeuDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: NeuCopy.zh.galleryTitle,
      theme: buildTheme(Brightness.light, ThemeColor.blue),
      darkTheme: buildTheme(Brightness.dark, ThemeColor.blue),
      locale: const Locale('zh'),
      supportedLocales: const [Locale('zh'), Locale('en'), Locale('ja')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const RepaintBoundary(key: Key('uiexp1-shot'), child: NeuGallery()),
    );
  }
}
