import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/screens/settings_screen.dart';
import 'package:matrixflow_native/services/desktop_shell_service.dart';
import 'package:provider/provider.dart';

import 'helpers.dart';

void main() {
  tearDown(() {
    DesktopShellService.instance.resetForTest();
  });

  group('WP26-B-N-Windows: DesktopShellService', () {
    test('non-desktop platforms safely no-op without crashes or exceptions', () async {
      DesktopShellService.debugIsDesktopOverride = false;
      final service = DesktopShellService.instance;

      expect(service.isDesktopSupported, isFalse);
      await service.init();
      expect(service.isTrayInitialized, isFalse);

      final closeResult = service.handleWindowCloseRequest(closeToTray: true);
      expect(closeResult, isTrue); // Not on desktop; returns true for normal exit

      final hotkeyResult = service.registerGlobalHotkey('Ctrl+Alt+M', () {});
      expect(hotkeyResult, isFalse);
      expect(service.hasHotkeyConflict, isFalse);
    });

    test('desktop platform initializes tray, hides to tray, restores, and manages hotkeys', () async {
      DesktopShellService.debugIsDesktopOverride = true;
      final service = DesktopShellService.instance;

      var windowShown = false;
      var appExited = false;

      await service.init(
        onShowWindow: () => windowShown = true,
        onExit: () => appExited = true,
      );

      expect(service.isDesktopSupported, isTrue);
      expect(service.isTrayInitialized, isTrue);
      expect(service.isWindowVisible, isTrue);

      // Test closeToTray = true intercepts window close
      final intercepted = service.handleWindowCloseRequest(closeToTray: true);
      expect(intercepted, isFalse);
      expect(service.isWindowVisible, isFalse);

      // Test restoreWindow
      service.restoreWindow();
      expect(service.isWindowVisible, isTrue);
      expect(windowShown, isTrue);

      // Test valid hotkey registration
      final hotkeyOk = service.registerGlobalHotkey('Ctrl+Alt+M', () {});
      expect(hotkeyOk, isTrue);
      expect(service.registeredGlobalShortcut, 'Ctrl+Alt+M');
      expect(service.hasHotkeyConflict, isFalse);

      // Test conflict hotkey handling (safe failure, no throw)
      final conflictOk = service.registerGlobalHotkey('Ctrl+Alt+Del', () {});
      expect(conflictOk, isFalse);
      expect(service.hasHotkeyConflict, isTrue);

      // Test closeToTray = false exits application
      final exitHandled = service.handleWindowCloseRequest(closeToTray: false);
      expect(exitHandled, isTrue);
      expect(appExited, isTrue);
      expect(service.isTrayInitialized, isFalse);
    });
  });

  group('WP26-B-N-Windows: Settings serialization & UI', () {
    test('AppSettings serializes and deserializes closeToTray and globalShortcut', () {
      final defaultSettings = AppSettings();
      expect(defaultSettings.closeToTray, isFalse);
      expect(defaultSettings.globalShortcut, 'Ctrl+Alt+M');

      final json = defaultSettings.toJson();
      expect(json['closeToTray'], isFalse);
      expect(json['globalShortcut'], 'Ctrl+Alt+M');

      final customized = AppSettings(
        closeToTray: true,
        globalShortcut: 'Ctrl+Shift+F12',
      );
      final customJson = customized.toJson();
      final roundtrip = AppSettings.fromJson(customJson);

      expect(roundtrip.closeToTray, isTrue);
      expect(roundtrip.globalShortcut, 'Ctrl+Shift+F12');
    });

    testWidgets('SettingsScreen displays Desktop & System section and toggles closeToTray', (tester) async {
      final (store, _) = await makeStore();

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: store,
          child: MaterialApp(
            theme: ThemeData(
              useMaterial3: true,
              platform: TargetPlatform.windows,
            ),
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            supportedLocales: const [Locale('en'), Locale('zh'), Locale('ja')],
            home: const SettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Scroll to Desktop & System section
      await tester.dragUntilVisible(
        find.text(store.t['desktopSection']!),
        find.descendant(
          of: find.byKey(const ValueKey('settings-list')),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.down,
          ),
        ),
        const Offset(0, -240),
      );
      await tester.pumpAndSettle();

      expect(find.text(store.t['desktopSection']!), findsOneWidget);
      expect(find.text(store.t['closeToTray']!), findsOneWidget);
      expect(find.text(store.t['globalHotkey']!), findsOneWidget);
      expect(find.text('Ctrl+Alt+M'), findsOneWidget);

      // Toggle closeToTray switch
      expect(store.settings.closeToTray, isFalse);
      await tester.tap(find.text(store.t['closeToTray']!));
      await tester.pumpAndSettle();

      expect(store.settings.closeToTray, isTrue);
      expect(find.text(store.t['closeToTrayNotice']!), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      store.dispose();
    });
  });
}
