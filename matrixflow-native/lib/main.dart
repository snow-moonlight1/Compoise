import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'screens/matrix_screen.dart';
import 'models.dart';
import 'storage.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MatrixFlowApp());
}

class MatrixFlowApp extends StatelessWidget {
  const MatrixFlowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => Store()..init(),
      child: Consumer<Store>(
        builder: (context, store, _) {
          if (!store.ready) {
            return MaterialApp(
              debugShowCheckedModeBanner: false,
              home: Scaffold(
                body: Center(
                  child:
                      store.startupError == null
                          ? const CircularProgressIndicator()
                          : Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(store.startupError!),
                              TextButton(
                                onPressed: store.init,
                                child: Text(store.t['retry']!),
                              ),
                            ],
                          ),
                ),
              ),
            );
          }
          return MaterialApp(
            title: 'MatrixFlow AI',
            debugShowCheckedModeBanner: false,
            theme: buildTheme(Brightness.light, store.settings.themeColor),
            darkTheme: buildTheme(Brightness.dark, store.settings.themeColor),
            themeMode: switch (store.settings.theme) {
              ThemeModePref.light => ThemeMode.light,
              ThemeModePref.dark => ThemeMode.dark,
              ThemeModePref.system => ThemeMode.system,
            },
            locale: switch (store.settings.language) {
              Language.zh => const Locale('zh'),
              Language.ja => const Locale('ja'),
              Language.en => const Locale('en'),
            },
            supportedLocales: const [Locale('en'), Locale('zh'), Locale('ja')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: const MatrixHome(),
          );
        },
      ),
    );
  }
}
