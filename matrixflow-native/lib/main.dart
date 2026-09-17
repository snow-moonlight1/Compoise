import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'screens/matrix_screen.dart';
import 'models.dart';
import 'services/desktop_shell_service.dart';
import 'services/desktop_shell_windows.dart';
import 'storage.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ensureWindowsWindowManager();
  await DesktopShellService.instance.init();
  await ReminderService.instance.init();
  runApp(const MatrixFlowApp());
}

class MatrixFlowApp extends StatelessWidget {
  final List<Locale>? deviceLocales;
  const MatrixFlowApp({super.key, this.deviceLocales});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => Store(deviceLocales: deviceLocales)..init(),
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
            theme: buildTheme(
              Brightness.light,
              store.settings.themeColor,
              fontFamilyPref: store.settings.fontFamily,
            ),
            darkTheme: buildTheme(
              Brightness.dark,
              store.settings.themeColor,
              fontFamilyPref: store.settings.fontFamily,
            ),
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
            builder: (context, child) {
              final systemScaler = MediaQuery.textScalerOf(context);
              final appScale = fontScaleFactor(store.settings.fontSize);
              return MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: CombinedTextScaler(systemScaler, appScale),
                ),
                child: child!,
              );
            },
            home: const MatrixHome(),
          );
        },
      ),
    );
  }
}
