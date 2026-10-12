import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'screens/matrix_screen.dart';
import 'screens/startup_recovery_screen.dart';
import 'models.dart';
import 'services/desktop_shell_service.dart';
import 'services/desktop_shell_windows.dart';
import 'services/single_instance.dart';
import 'services/window_geometry.dart';
import 'storage.dart';
import 'theme.dart';
import 'ui/songti_font.dart';

Future<void> main([List<String> args = const <String>[]]) async {
  WidgetsFlutterBinding.ensureInitialized();
  await ensureWindowsWindowManager();
  await WindowGeometry.instance.start();
  final reminders = ReminderService.instance;
  const persistence = SharedPreferencesStorePersistence();
  await SingleInstanceController.install(
    initialArguments: args,
    onActivated: (incoming) {
      dispatchSingleInstanceActivation(
        incoming,
        restoreWindow: DesktopShellService.instance.restoreWindow,
        deliverPayload: reminders.acceptExternalActivation,
      );
    },
  );
  await reminders.init();
  runApp(CompoiseApp(reminders: reminders, persistence: persistence));
}

class CompoiseApp extends StatelessWidget {
  final List<Locale>? deviceLocales;
  final ReminderService? reminders;
  final StorePersistence? persistence;
  final SaveWrite? saveWriter;
  const CompoiseApp({
    super.key,
    this.deviceLocales,
    this.reminders,
    this.persistence,
    this.saveWriter,
  });

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) {
        final store = Store(
          deviceLocales: deviceLocales,
          reminders: reminders,
          persistence: persistence,
          saveWriter: saveWriter,
        );
        store.init();
        return store;
      },
      child: Consumer<Store>(
        builder: (context, store, _) {
          if (!store.ready) {
            return MaterialApp(
              debugShowCheckedModeBanner: false,
              home: Scaffold(
                body: Center(
                  child: store.startupError == null
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
          if (store.hasStartupRecovery) {
            return MaterialApp(
              debugShowCheckedModeBanner: false,
              home: const StartupRecoveryScreen(),
            );
          }
          return SongtiWarmup(
            load: store.settings.fontFamily == FontFamilyPref.serif,
            builder: (context) => MaterialApp(
              title: store.t['appTitle']!,
              debugShowCheckedModeBanner: false,
              theme: buildTheme(
                Brightness.light,
                store.settings.themeColor,
                fontFamilyPref: store.settings.fontFamily,
                comicOutline: store.settings.comicOutline,
                neumorphic: store.settings.neumorphic,
              ),
              darkTheme: buildTheme(
                Brightness.dark,
                store.settings.themeColor,
                fontFamilyPref: store.settings.fontFamily,
                comicOutline: store.settings.comicOutline,
                neumorphic: store.settings.neumorphic,
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
              supportedLocales: const [
                Locale('en'),
                Locale('zh'),
                Locale('ja'),
              ],
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
            ),
          );
        },
      ),
    );
  }
}
