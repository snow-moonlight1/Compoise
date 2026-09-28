import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/screens/matrix_screen.dart';
import 'package:matrixflow_native/services/desktop_exit_coordinator.dart';
import 'package:matrixflow_native/services/desktop_shell_host.dart';
import 'package:matrixflow_native/services/desktop_shell_service.dart';
import 'package:matrixflow_native/storage.dart';
import 'package:matrixflow_native/ui/desktop_exit_strings.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('OS15 desktop exit idempotency', () {
    test('window close and tray exit join one approved destroy', () async {
      final host = _FakeDesktopShellHost();
      final service = DesktopShellService.forTest(host);
      await service.applySettings(closeToTray: false, globalShortcut: '');
      final approval = Completer<bool>();
      var guardCalls = 0;
      service.onExit = () {
        guardCalls++;
        return approval.future;
      };

      host.callbacks!.onWindowCloseRequested();
      host.callbacks!.onWindowCloseRequested();
      host.callbacks!.onExitRequested!.call();
      final joined = service.exitApplication();

      expect(guardCalls, 1);
      expect(service.isExitInProgress, isTrue);
      expect(host.destroyCalls, 0);
      approval.complete(true);
      expect(await joined, DesktopExitResult.completed);
      expect(host.destroyCalls, 1);
      expect(service.isExitInProgress, isFalse);

      expect(await service.exitApplication(), DesktopExitResult.completed);
      expect(guardCalls, 1);
      expect(host.destroyCalls, 1);
    });

    test('cancel keeps the host alive and permits a later exit', () async {
      final host = _FakeDesktopShellHost();
      final service = DesktopShellService.forTest(host);
      await service.applySettings(closeToTray: false, globalShortcut: '');
      var approve = false;
      service.onExit = () => approve;

      expect(await service.exitApplication(), DesktopExitResult.cancelled);
      expect(host.destroyCalls, 0);
      expect(service.isExitInProgress, isFalse);

      approve = true;
      expect(await service.exitApplication(), DesktopExitResult.completed);
      expect(host.destroyCalls, 1);
    });

    test('close-to-tray hides without running true-exit guard', () async {
      final host = _FakeDesktopShellHost();
      final service = DesktopShellService.forTest(host);
      var guardCalls = 0;
      service.onExit = () {
        guardCalls++;
        return true;
      };
      await service.applySettings(closeToTray: true, globalShortcut: '');

      expect(service.handleWindowCloseRequest(), isFalse);
      await Future<void>.delayed(Duration.zero);

      expect(host.hideCalls, 1);
      expect(host.destroyCalls, 0);
      expect(guardCalls, 0);
      expect(service.isWindowVisible, isFalse);
    });
  });

  group('OS15 save coordination', () {
    test('successful flush exits without prompting', () async {
      var prompts = 0;
      final coordinator = DesktopExitSaveCoordinator(
        flush: () async => const SaveResult(true, 4, committed: true),
        retrySave: () async => const SaveResult(true, 5, committed: true),
        chooseAfterProblem: (_) async {
          prompts++;
          return DesktopExitSaveChoice.cancel;
        },
        timeout: const Duration(seconds: 1),
      );

      expect(await coordinator.prepareToExit(), isTrue);
      expect(prompts, 0);
    });

    test(
      'failed flush retries and only exits after confirmed success',
      () async {
        var retries = 0;
        final problems = <DesktopExitSaveProblem>[];
        final coordinator = DesktopExitSaveCoordinator(
          flush: () async => const SaveResult(false, 4),
          retrySave: () async {
            retries++;
            return const SaveResult(true, 5, committed: true);
          },
          chooseAfterProblem: (problem) async {
            problems.add(problem);
            return DesktopExitSaveChoice.retry;
          },
          timeout: const Duration(seconds: 1),
        );

        expect(await coordinator.prepareToExit(), isTrue);
        expect(retries, 1);
        expect(problems, [DesktopExitSaveProblem.failed]);
      },
    );

    test('timed-out flush can cancel exit without claiming success', () async {
      final blocked = Completer<SaveResult>();
      DesktopExitSaveProblem? observed;
      final coordinator = DesktopExitSaveCoordinator(
        flush: () => blocked.future,
        retrySave: () async => const SaveResult(true, 5, committed: true),
        chooseAfterProblem: (problem) async {
          observed = problem;
          return DesktopExitSaveChoice.cancel;
        },
        timeout: const Duration(milliseconds: 1),
      );

      expect(await coordinator.prepareToExit(), isFalse);
      expect(observed, DesktopExitSaveProblem.timedOut);
      blocked.complete(const SaveResult(true, 4, committed: true));
    });

    test('failed flush can explicitly continue without saving', () async {
      var retryCalls = 0;
      final coordinator = DesktopExitSaveCoordinator(
        flush: () async => const SaveResult(false, 4),
        retrySave: () async {
          retryCalls++;
          return const SaveResult(true, 5, committed: true);
        },
        chooseAfterProblem: (_) async =>
            DesktopExitSaveChoice.exitWithoutSaving,
        timeout: const Duration(seconds: 1),
      );

      expect(await coordinator.prepareToExit(), isTrue);
      expect(retryCalls, 0);
    });

    test('all three languages provide explicit exit choices', () {
      for (final language in Language.values) {
        final strings = DesktopExitStrings.forLanguage(language);
        expect(strings.retry, isNotEmpty);
        expect(strings.exitWithoutSaving, isNotEmpty);
        expect(strings.cancelExit, isNotEmpty);
        expect(strings.saveFailedMessage, contains(strings.retry));
      }
    });
  });

  group('OS15 MatrixHome exit UI', () {
    testWidgets('IME draft is preserved when exit is cancelled', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final (store, _) = await makeStore();
      final host = _FakeDesktopShellHost();
      final service = DesktopShellService.forTest(host);
      await tester.pumpWidget(_app(store, service));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('add-task-btn')));
      await tester.pumpAndSettle();
      final input = tester.widget<TextField>(
        find.byKey(const ValueKey('task-step-0')),
      );
      const draft = '输入中';
      await tester.showKeyboard(find.byKey(const ValueKey('task-step-0')));
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: draft,
          selection: TextSelection.collapsed(offset: draft.length),
          composing: TextRange(start: 0, end: draft.length),
        ),
      );
      expect(input.controller!.value.composing.isValid, isTrue);
      await tester.pump();

      final exit = service.exitApplication();
      await tester.pumpAndSettle();
      expect(find.text(store.t['discardChangesTitle']!), findsOneWidget);
      await tester.tap(find.text(store.t['keepEditing']!));
      await tester.pumpAndSettle();

      expect(await exit, DesktopExitResult.cancelled);
      expect(host.destroyCalls, 0);
      expect(input.controller!.text, draft);
      expect(store.tasks, isEmpty);

      await tester.pumpWidget(const SizedBox());
      store.dispose();
    });

    testWidgets('dirty modal detail is discarded before the final destroy', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final (store, _) = await makeStore();
      final task = store.newTask('Original');
      store.addTasks([task]);
      await store.flush();
      final host = _FakeDesktopShellHost();
      final service = DesktopShellService.forTest(host);
      await tester.pumpWidget(_app(store, service));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Original').first);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('edit-title')),
        'Unsaved detail',
      );
      await tester.pumpAndSettle();

      final exit = service.exitApplication();
      await tester.pumpAndSettle();
      await tester.tap(find.text(store.t['discard']!));
      await tester.pumpAndSettle();

      expect(await exit, DesktopExitResult.completed);
      expect(host.destroyCalls, 1);
      expect(find.byKey(const ValueKey('edit-title')), findsNothing);
      expect(store.tasks.single.title, 'Original');

      await tester.pumpWidget(const SizedBox());
      store.dispose();
    });

    testWidgets('final destroy waits for an in-progress Store flush', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      SharedPreferences.setMockInitialValues({
        'matrixflow-has-seen-onboarding': true,
      });
      final gate = Completer<void>();
      var armed = false;
      var blocked = false;
      final store = Store(
        saveWriter: (key, value) async {
          if (armed && !blocked) {
            blocked = true;
            await gate.future;
          }
          return (await SharedPreferences.getInstance()).setString(key, value);
        },
      );
      await store.init();
      await store.flush();
      final host = _FakeDesktopShellHost();
      final service = DesktopShellService.forTest(host);
      await tester.pumpWidget(_app(store, service));
      await tester.pumpAndSettle();

      armed = true;
      store.createBoard('Pending board');
      final exit = service.exitApplication();
      await tester.pump(const Duration(milliseconds: 5));
      expect(blocked, isTrue);
      expect(host.destroyCalls, 0);

      gate.complete();
      await tester.pumpAndSettle();
      expect(await exit, DesktopExitResult.completed);
      expect(host.destroyCalls, 1);

      await tester.pumpWidget(const SizedBox());
      store.dispose();
    });

    testWidgets(
      'save failure offers retry and exits only after retry succeeds',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1200, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        SharedPreferences.setMockInitialValues({
          'matrixflow-has-seen-onboarding': true,
        });
        var reject = false;
        final store = Store(
          saveWriter: (key, value) async {
            if (reject && key == SaveProtocol.pointerKey) return false;
            return (await SharedPreferences.getInstance()).setString(
              key,
              value,
            );
          },
        );
        await store.init();
        await store.flush();
        final host = _FakeDesktopShellHost();
        final service = DesktopShellService.forTest(host);
        await tester.pumpWidget(_app(store, service));
        await tester.pumpAndSettle();

        reject = true;
        store.createBoard('Pending board');
        final exit = service.exitApplication();
        await tester.pumpAndSettle();

        final strings = DesktopExitStrings.forLanguage(store.settings.language);
        expect(find.text(strings.saveFailedTitle), findsOneWidget);
        expect(find.byKey(const ValueKey('exit-save-cancel')), findsOneWidget);
        expect(find.byKey(const ValueKey('exit-save-retry')), findsOneWidget);
        expect(
          find.byKey(const ValueKey('exit-without-saving')),
          findsOneWidget,
        );
        expect(host.destroyCalls, 0);

        reject = false;
        await tester.tap(find.byKey(const ValueKey('exit-save-retry')));
        await tester.pumpAndSettle();

        expect(await exit, DesktopExitResult.completed);
        expect(host.destroyCalls, 1);
        expect(store.persistenceError, isNull);

        await tester.pumpWidget(const SizedBox());
        store.dispose();
      },
    );
  });
}

Widget _app(Store store, DesktopShellService service) =>
    ChangeNotifierProvider.value(
      value: store,
      child: MaterialApp(
        theme: ThemeData(useMaterial3: true, platform: TargetPlatform.windows),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('en'), Locale('zh'), Locale('ja')],
        home: MatrixHome(
          desktopShell: service,
          exitSaveTimeout: const Duration(milliseconds: 20),
        ),
      ),
    );

class _FakeDesktopShellHost implements DesktopShellHost {
  DesktopShellHostCallbacks? callbacks;
  String? _registeredShortcut;
  int hideCalls = 0;
  int destroyCalls = 0;

  @override
  String? get registeredShortcut => _registeredShortcut;

  @override
  Future<DesktopShellResult> start(DesktopShellHostCallbacks callbacks) async {
    this.callbacks = callbacks;
    return const DesktopShellResult.success();
  }

  @override
  Future<DesktopShellResult> registerHotkey(
    String shortcut,
    VoidCallback onTrigger,
  ) async {
    _registeredShortcut = shortcut;
    return const DesktopShellResult.success();
  }

  @override
  Future<DesktopShellResult> unregisterHotkey() async {
    _registeredShortcut = null;
    return const DesktopShellResult.success();
  }

  @override
  Future<DesktopShellResult> hide() async {
    hideCalls++;
    return const DesktopShellResult.success();
  }

  @override
  Future<DesktopShellResult> show() async => const DesktopShellResult.success();

  @override
  Future<void> destroy() async {
    destroyCalls++;
  }
}
