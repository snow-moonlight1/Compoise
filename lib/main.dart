import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'screens/matrix_screen.dart';
import 'screens/startup_recovery_screen.dart';
import 'screens/windows_upgrade_screen.dart';
import 'models.dart';
import 'services/desktop_shell_service.dart';
import 'services/desktop_shell_windows.dart';
import 'services/single_instance.dart';
import 'services/windows_data_upgrade.dart';
import 'services/windows_upgrade_validation.dart';
import 'storage.dart';
import 'theme.dart';
import 'ui/songti_font.dart';

Future<void> main([List<String> args = const <String>[]]) async {
  WidgetsFlutterBinding.ensureInitialized();
  final validation = const bool.fromEnvironment('WP28_U2_HARNESS')
      ? await WindowsUpgradeValidation.open()
      : null;
  await ensureWindowsWindowManager();
  final reminders = validation?.reminders ?? ReminderService.instance;
  final persistence = const SharedPreferencesStorePersistence();
  await SingleInstanceController.install(
    initialArguments: args,
    onActivated: (incoming) {
      validation?.onActivation(incoming);
      dispatchSingleInstanceActivation(
        incoming,
        restoreWindow: DesktopShellService.instance.restoreWindow,
        deliverPayload: reminders.acceptExternalActivation,
      );
    },
  );
  if (shouldUseRealWindowsShell()) {
    final upgrade = validation?.upgrade() ?? WindowsDataUpgrade();
    var noticeConfirmed = false;
    WindowsUpgradeResult? upgradeResult;
    final startup = WindowsUpgradeStartup(
      deviceLocales: validation == null ? null : const [Locale('en')],
      prepare: () async =>
          upgradeResult = await (validation?.prepare() ?? upgrade.prepare()),
      onCredentialNoticeConfirmed: () => noticeConfirmed = true,
      // No Store has opened, so there is no pending save to flush here.
      closeBeforeStore: windowManager.destroy,
      openApplication: () async {
        if (validation != null) {
          await validation.waitForStoreApproval();
        }
        await reminders.init();
        return MatrixFlowApp(
          reminders: reminders,
          persistence: persistence,
          saveWriter: validation?.write,
          acknowledgeWindowsCredentialNotice: noticeConfirmed,
          windowsCredentialsRequiredOnOpen:
              upgradeResult?.credentialsNeedSetup ?? false,
          onStoreReady: validation?.onStoreReady,
        );
      },
    );
    runApp(validation?.wrap(startup) ?? startup);
    return;
  }
  await reminders.init();
  runApp(MatrixFlowApp(reminders: reminders, persistence: persistence));
}

class MatrixFlowApp extends StatelessWidget {
  final List<Locale>? deviceLocales;
  final ReminderService? reminders;
  final StorePersistence? persistence;
  final SaveWrite? saveWriter;
  final bool acknowledgeWindowsCredentialNotice;
  final bool windowsCredentialsRequiredOnOpen;
  final Future<void> Function(Store)? onStoreReady;
  const MatrixFlowApp({
    super.key,
    this.deviceLocales,
    this.reminders,
    this.persistence,
    this.saveWriter,
    this.acknowledgeWindowsCredentialNotice = false,
    this.windowsCredentialsRequiredOnOpen = false,
    this.onStoreReady,
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
          windowsCredentialsRequiredOnOpen: windowsCredentialsRequiredOnOpen,
        );
        store.init().then((_) async {
          if (acknowledgeWindowsCredentialNotice) {
            await store.acknowledgeWindowsCredentialNotice();
          }
          await onStoreReady?.call(store);
        });
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
              ),
              darkTheme: buildTheme(
                Brightness.dark,
                store.settings.themeColor,
                fontFamilyPref: store.settings.fontFamily,
                comicOutline: store.settings.comicOutline,
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
