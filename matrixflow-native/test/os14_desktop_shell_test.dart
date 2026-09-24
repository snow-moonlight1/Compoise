import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/screens/settings_screen.dart';
import 'package:matrixflow_native/services/desktop_shell_host.dart';
import 'package:matrixflow_native/services/desktop_shell_service.dart';
import 'package:provider/provider.dart';

import 'helpers.dart';

void main() {
  tearDown(DesktopShellService.instance.resetForTest);

  group('OS14 desktop shell real-result coordination', () {
    test(
      'tray init failure disables close-to-tray and retry can recover',
      () async {
        final host = _FakeDesktopShellHost();
        host.startHandler = () async {
          if (host.startCalls == 1) {
            return const DesktopShellResult(DesktopShellResultKind.unavailable);
          }
          return const DesktopShellResult.success();
        };
        final service = DesktopShellService.forTest(host);

        final failed = await service.applySettings(
          closeToTray: true,
          globalShortcut: '',
        );
        expect(failed.tray.kind, DesktopShellResultKind.unavailable);
        expect(failed.closeToTrayEffective, isFalse);
        expect(service.effectiveCloseToTray, isFalse);
        expect(service.isWindowVisible, isTrue);

        var exited = false;
        service.onExit = () => exited = true;
        expect(service.handleWindowCloseRequest(), isTrue);
        expect(host.hideCalls, 0);
        expect(exited, isTrue);

        service.onExit = null;
        final recovered = await service.retrySettings();
        expect(recovered.tray.succeeded, isTrue);
        expect(recovered.closeToTrayEffective, isTrue);
        expect(host.startCalls, 2);
      },
    );

    test(
      'hotkey conflict is observable and retry reports real success',
      () async {
        final host = _FakeDesktopShellHost();
        host.registerHandler = (shortcut) async {
          if (host.registerCalls == 1) {
            return const DesktopShellResult(DesktopShellResultKind.conflict);
          }
          return const DesktopShellResult.success();
        };
        final service = DesktopShellService.forTest(host);

        final conflict = await service.applySettings(
          closeToTray: false,
          globalShortcut: 'Ctrl+Alt+M',
        );
        expect(conflict.hotkey.kind, DesktopShellResultKind.conflict);
        expect(service.hasHotkeyConflict, isTrue);
        expect(service.registeredGlobalShortcut, isNull);

        final retried = await service.retrySettings();
        expect(retried.hotkey.succeeded, isTrue);
        expect(service.hasHotkeyConflict, isFalse);
        expect(service.registeredGlobalShortcut, 'Ctrl+Alt+M');
        expect(host.registerCalls, 2);
      },
    );

    test(
      'late hotkey result is superseded by the latest settings generation',
      () async {
        final host = _FakeDesktopShellHost();
        final late = Completer<DesktopShellResult>();
        host.registerHandler = (shortcut) {
          if (shortcut == 'Ctrl+Alt+M') return late.future;
          return Future.value(const DesktopShellResult.success());
        };
        final service = DesktopShellService.forTest(host);

        final first = service.applySettings(
          closeToTray: false,
          globalShortcut: 'Ctrl+Alt+M',
        );
        await _waitUntil(() => host.registerCalls == 1);
        final second = service.applySettings(
          closeToTray: true,
          globalShortcut: 'Ctrl+Alt+N',
        );

        late.complete(const DesktopShellResult.success());
        final staleResult = await first;
        final latestResult = await second;

        expect(staleResult.superseded, isTrue);
        expect(latestResult.superseded, isFalse);
        expect(latestResult.requestedShortcut, 'Ctrl+Alt+N');
        expect(service.lastSettingsResult?.generation, latestResult.generation);
        expect(service.registeredGlobalShortcut, 'Ctrl+Alt+N');
        expect(service.effectiveCloseToTray, isTrue);
        expect(host.registeredShortcuts, ['Ctrl+Alt+M', 'Ctrl+Alt+N']);
      },
    );

    test('late tray result cannot enable an outdated close policy', () async {
      final host = _FakeDesktopShellHost();
      final late = Completer<DesktopShellResult>();
      host.startHandler =
          () =>
              host.startCalls == 1
                  ? late.future
                  : Future.value(const DesktopShellResult.success());
      final service = DesktopShellService.forTest(host);

      final first = service.applySettings(
        closeToTray: true,
        globalShortcut: '',
      );
      await _waitUntil(() => host.startCalls == 1);
      final second = service.applySettings(
        closeToTray: false,
        globalShortcut: '',
      );
      late.complete(const DesktopShellResult.success());

      expect((await first).superseded, isTrue);
      expect((await second).closeToTrayEffective, isFalse);
      expect(service.effectiveCloseToTray, isFalse);
      expect(host.startCalls, 2);
    });

    test('failed hide keeps the window visible', () async {
      final host = _FakeDesktopShellHost();
      host.hideResult = const DesktopShellResult(
        DesktopShellResultKind.unavailable,
      );
      final service = DesktopShellService.forTest(host);
      await service.applySettings(closeToTray: true, globalShortcut: '');

      final result = await service.hideWindowToTray();
      expect(result.kind, DesktopShellResultKind.unavailable);
      expect(service.isWindowVisible, isTrue);
      expect(host.hideCalls, 1);
    });

    test('disable enable and repeated apply are idempotent', () async {
      final host = _FakeDesktopShellHost();
      final service = DesktopShellService.forTest(host);

      final enabled = await service.applySettings(
        closeToTray: true,
        globalShortcut: 'Ctrl+Alt+M',
      );
      expect(enabled.closeToTrayEffective, isTrue);
      expect(host.startCalls, 1);
      expect(host.registerCalls, 1);

      final repeated = await service.applySettings(
        closeToTray: true,
        globalShortcut: 'Ctrl+Alt+M',
      );
      expect(repeated.closeToTrayEffective, isTrue);
      expect(host.startCalls, 1);
      expect(host.registerCalls, 1);

      final disabled = await service.applySettings(
        closeToTray: false,
        globalShortcut: '',
      );
      expect(disabled.closeToTrayEffective, isFalse);
      expect(disabled.hotkey.kind, DesktopShellResultKind.disabled);
      expect(host.unregisterCalls, 1);

      final enabledAgain = await service.applySettings(
        closeToTray: true,
        globalShortcut: 'Ctrl+Alt+M',
      );
      expect(enabledAgain.closeToTrayEffective, isTrue);
      expect(host.startCalls, 1);
      expect(host.registerCalls, 2);
    });

    test('failed hotkey release stays observable and can be retried', () async {
      final host = _FakeDesktopShellHost();
      final service = DesktopShellService.forTest(host);
      await service.applySettings(
        closeToTray: false,
        globalShortcut: 'Ctrl+Alt+M',
      );
      host.unregisterResult = const DesktopShellResult(
        DesktopShellResultKind.unavailable,
      );

      final failed = await service.applySettings(
        closeToTray: false,
        globalShortcut: '',
      );
      expect(failed.hotkey.kind, DesktopShellResultKind.unavailable);
      expect(failed.registeredShortcut, 'Ctrl+Alt+M');

      host.unregisterResult = const DesktopShellResult.success();
      final retried = await service.retrySettings();
      expect(retried.hotkey.kind, DesktopShellResultKind.disabled);
      expect(retried.registeredShortcut, isNull);
    });
  });

  testWidgets('editing the shortcut applies the saved setting at runtime', (
    tester,
  ) async {
    DesktopShellService.debugIsDesktopOverride = true;
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
    await tester.dragUntilVisible(
      find.byKey(const ValueKey('desktop-hotkey-change')),
      find.byKey(const ValueKey('settings-list')),
      const Offset(0, -240),
    );
    await tester.tap(find.byKey(const ValueKey('desktop-hotkey-change')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('desktop-hotkey-input')),
      'Ctrl+Alt+N',
    );
    await tester.tap(find.byKey(const ValueKey('desktop-hotkey-save')));
    await tester.pumpAndSettle();

    expect(store.settings.globalShortcut, 'Ctrl+Alt+N');
    expect(DesktopShellService.instance.registeredGlobalShortcut, 'Ctrl+Alt+N');

    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });
}

Future<void> _waitUntil(bool Function() condition) async {
  for (var i = 0; i < 20 && !condition(); i++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(condition(), isTrue);
}

class _FakeDesktopShellHost implements DesktopShellHost {
  String? _registeredShortcut;
  @override
  String? get registeredShortcut => _registeredShortcut;

  Future<DesktopShellResult> Function()? startHandler;
  Future<DesktopShellResult> Function(String shortcut)? registerHandler;
  DesktopShellResult unregisterResult = const DesktopShellResult.success();
  DesktopShellResult hideResult = const DesktopShellResult.success();

  int startCalls = 0;
  int registerCalls = 0;
  int unregisterCalls = 0;
  int hideCalls = 0;
  int showCalls = 0;
  int destroyCalls = 0;
  final List<String> registeredShortcuts = [];
  DesktopShellHostCallbacks? callbacks;

  @override
  Future<DesktopShellResult> start(DesktopShellHostCallbacks callbacks) async {
    startCalls++;
    this.callbacks = callbacks;
    return startHandler?.call() ?? const DesktopShellResult.success();
  }

  @override
  Future<DesktopShellResult> registerHotkey(
    String shortcut,
    VoidCallback onTrigger,
  ) async {
    registerCalls++;
    registeredShortcuts.add(shortcut);
    _registeredShortcut = null;
    final result =
        await (registerHandler?.call(shortcut) ??
            Future.value(const DesktopShellResult.success()));
    if (result.succeeded) _registeredShortcut = shortcut;
    return result;
  }

  @override
  Future<DesktopShellResult> unregisterHotkey() async {
    unregisterCalls++;
    if (unregisterResult.succeeded) _registeredShortcut = null;
    return unregisterResult;
  }

  @override
  Future<DesktopShellResult> hide() async {
    hideCalls++;
    return hideResult;
  }

  @override
  Future<DesktopShellResult> show() async {
    showCalls++;
    return const DesktopShellResult.success();
  }

  @override
  Future<void> destroy() async {
    destroyCalls++;
  }
}
