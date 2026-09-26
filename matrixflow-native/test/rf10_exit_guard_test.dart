import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/services/desktop_shell_host.dart';
import 'package:matrixflow_native/services/desktop_shell_service.dart';

void main() {
  group('RF10 exit guard: applySettings/exit interleavings', () {
    test(
      'baseline: a finished apply followed by exit never touches the host after destroy',
      () async {
        final rig = _FactoryRig.create();
        final service = rig.service;
        final first = await service.applySettings(
          closeToTray: true,
          globalShortcut: 'Ctrl+Alt+M',
        );
        expect(first.hasFailure, isFalse);
        final h1 = rig.hosts.single;
        expect(h1.startCalls, 1);
        expect(h1.registerCalls, 1);
        expect(service.isApplyingSettings, isFalse);

        service.onExit = () => true;
        expect(
          await service.exitApplication(),
          DesktopExitResult.completed,
        );

        expect(h1.destroyCalls, 1);
        expect(rig.eventsAfter('H1:destroy-end'), isEmpty);
        expect(service.isTrayInitialized, isFalse);
        expect(service.registeredGlobalShortcut, isNull);
        expect(service.isApplyingSettings, isFalse);
      },
    );

    test(
      'race: an apply suspended in start() across destroy must not register or publish after exit',
      () async {
        final host = _ScriptedHost(1);
        final service = DesktopShellService.forTest(host);
        await service.applySettings(
          closeToTray: true,
          globalShortcut: 'Ctrl+Alt+M',
        );

        final startGate = Completer<DesktopShellResult>();
        host.startGate = startGate;
        final destroyGate = Completer<void>();
        host.destroyGate = destroyGate;

        final guard = Completer<bool>();
        var guardCalls = 0;
        service.onExit = () {
          guardCalls++;
          return guard.future;
        };

        // Second generation: a language change forces a tray start that we suspend.
        final secondApply = service.applySettings(
          closeToTray: true,
          globalShortcut: 'Ctrl+Alt+M',
          language: Language.zh,
        );
        await _waitUntil(() => host.startCalls == 2);

        final exitFuture = service.exitApplication();
        await _waitUntil(() => guardCalls == 1);
        guard.complete(true);
        await _waitUntil(() => host.destroyCalls == 1);
        expect(host.events, contains('H1:destroy-begin'));

        // Release the suspended tray start while destroy is still in flight.
        startGate.complete(const DesktopShellResult.success());
        await _pump(times: 4);

        // The apply must have joined the exit instead of issuing a hotkey call.
        final between = host.eventsBetween(
          'H1:destroy-begin',
          'H1:destroy-end',
        );
        expect(between.where((e) => e.contains('start-begin')), isEmpty);
        expect(between.where((e) => e.contains('register-begin')), isEmpty);

        destroyGate.complete();
        expect(await exitFuture, DesktopExitResult.completed);
        final secondResult = await secondApply;
        expect(secondResult.aborted, isTrue);
        expect(secondResult.hasFailure, isFalse);

        expect(host.registerCalls, 1); // only the first apply registered
        expect(host.eventsAfter('H1:destroy-end'), isEmpty);
        expect(service.isTrayInitialized, isFalse);
        expect(service.registeredGlobalShortcut, isNull);
        expect(service.isApplyingSettings, isFalse);
      },
    );

    test(
      'race2: an apply requested while destroy is running never creates a new host',
      () async {
        final rig = _FactoryRig.create();
        final service = rig.service;
        await service.applySettings(
          closeToTray: true,
          globalShortcut: 'Ctrl+Alt+M',
        );
        final h1 = rig.hosts.single;

        final guard = Completer<bool>();
        service.onExit = () => guard.future;
        final destroyGate = Completer<void>();
        h1.destroyGate = destroyGate;

        final exitFuture = service.exitApplication();
        guard.complete(true);
        await _waitUntil(() => h1.destroyCalls == 1);

        // Exit is mid-destroy; a settings change arrives.
        final lateApply = service.applySettings(
          closeToTray: false,
          globalShortcut: 'Ctrl+Alt+N',
        );
        await _pump(times: 4);
        expect(rig.hosts, hasLength(1)); // no factory call after host was nulled

        destroyGate.complete();
        expect(await exitFuture, DesktopExitResult.completed);
        final lateResult = await lateApply;
        expect(lateResult.aborted, isTrue);
        expect(rig.hosts, hasLength(1));
        expect(rig.eventsAfter('H1:destroy-end'), isEmpty);
        expect(service.isTrayInitialized, isFalse);
        expect(service.isApplyingSettings, isFalse);

        // A retry after a completed exit also stays inert.
        final retry = await service.retrySettings();
        expect(retry.aborted, isTrue);
        expect(retry.hasFailure, isFalse);
        expect(rig.hosts, hasLength(1));
        expect(service.isApplyingSettings, isFalse);
      },
    );
  });

  group('RF10 exit guard: exit outcomes and retry state', () {
    test(
      'completed exit settles isApplyingSettings and keeps later retries inert',
      () async {
        final host = _ScriptedHost(1);
        final service = DesktopShellService.forTest(host);
        await service.applySettings(
          closeToTray: true,
          globalShortcut: 'Ctrl+Alt+M',
        );

        final registerGate = Completer<DesktopShellResult>();
        host.registerGate = registerGate;
        final guard = Completer<bool>();
        service.onExit = () => guard.future;

        final secondApply = service.applySettings(
          closeToTray: true,
          globalShortcut: 'Ctrl+Alt+N',
        );
        await _waitUntil(() => host.registerCalls == 2);

        final exitFuture = service.exitApplication();
        guard.complete(true);
        expect(await exitFuture, DesktopExitResult.completed);

        // The suspended register result returns only after exit has completed.
        registerGate.complete(const DesktopShellResult.success());
        final secondResult = await secondApply;
        expect(secondResult.aborted, isTrue);
        expect(service.isApplyingSettings, isFalse);
        expect(service.isTrayInitialized, isFalse);
        expect(service.registeredGlobalShortcut, isNull);
        expect(host.registerCalls, 2); // the late result triggers no further ops

        // Post-exit retries complete as aborted without touching the host.
        final startSnapshot = host.startCalls;
        final registerSnapshot = host.registerCalls;
        final retry = await service.retrySettings();
        expect(retry.aborted, isTrue);
        expect(retry.hasFailure, isFalse);
        expect(host.startCalls, startSnapshot);
        expect(host.registerCalls, registerSnapshot);
        expect(service.isApplyingSettings, isFalse);
      },
    );

    test(
      'cancelled exit leaves the shell alive and the suspended apply finishes',
      () async {
        final host = _ScriptedHost(1);
        final service = DesktopShellService.forTest(host);
        await service.applySettings(
          closeToTray: true,
          globalShortcut: 'Ctrl+Alt+M',
        );

        final startGate = Completer<DesktopShellResult>();
        host.startGate = startGate;
        service.onExit = () => false;

        final secondApply = service.applySettings(
          closeToTray: true,
          globalShortcut: 'Ctrl+Alt+M',
          language: Language.zh,
        );
        await _waitUntil(() => host.startCalls == 2);

        expect(
          await service.exitApplication(),
          DesktopExitResult.cancelled,
        );
        expect(host.destroyCalls, 0);
        expect(service.isExitInProgress, isFalse);

        startGate.complete(const DesktopShellResult.success());
        final result = await secondApply;
        expect(result.superseded, isFalse);
        expect(result.aborted, isFalse);
        expect(result.tray.succeeded, isTrue);
        expect(host.callbacks?.language, Language.zh);
        expect(service.isApplyingSettings, isFalse);
        expect(service.isTrayInitialized, isTrue);

        // A later, approved exit still runs exactly one destroy.
        service.onExit = () => true;
        expect(
          await service.exitApplication(),
          DesktopExitResult.completed,
        );
        expect(host.destroyCalls, 1);
        expect(service.isApplyingSettings, isFalse);
      },
    );

    test(
      'applies queued while the exit guard is pending proceed after cancellation',
      () async {
        final host = _ScriptedHost(1);
        final service = DesktopShellService.forTest(host);
        await service.applySettings(
          closeToTray: true,
          globalShortcut: 'Ctrl+Alt+M',
        );

        final startGate = Completer<DesktopShellResult>();
        host.startGate = startGate;
        final guard = Completer<bool>();
        service.onExit = () => guard.future;

        final secondApply = service.applySettings(
          closeToTray: true,
          globalShortcut: 'Ctrl+Alt+M',
          language: Language.zh,
        );
        await _waitUntil(() => host.startCalls == 2);

        final exitFuture = service.exitApplication();
        // A third generation arrives while the guard decision is still pending.
        final thirdApply = service.applySettings(
          closeToTray: false,
          globalShortcut: '',
          language: Language.zh,
        );
        await _pump(times: 3);
        expect(service.isExitInProgress, isTrue);

        guard.complete(false);
        expect(await exitFuture, DesktopExitResult.cancelled);
        startGate.complete(const DesktopShellResult.success());

        final secondResult = await secondApply;
        final thirdResult = await thirdApply;
        expect(secondResult.superseded, isTrue);
        expect(thirdResult.superseded, isFalse);
        expect(thirdResult.aborted, isFalse);
        expect(thirdResult.closeToTrayEffective, isFalse);
        expect(host.destroyCalls, 0);
        expect(service.isApplyingSettings, isFalse);
      },
    );

    test(
      'failed destroy restores the host and the waiting apply re-establishes tray and hotkey',
      () async {
        final host = _ScriptedHost(1)..destroyThrows = true;
        final service = DesktopShellService.forTest(host);
        await service.applySettings(
          closeToTray: true,
          globalShortcut: 'Ctrl+Alt+M',
        );

        final registerGate = Completer<DesktopShellResult>();
        host.registerGate = registerGate;
        final destroyGate = Completer<void>();
        host.destroyGate = destroyGate;
        final guard = Completer<bool>();
        service.onExit = () => guard.future;

        final secondApply = service.applySettings(
          closeToTray: true,
          globalShortcut: 'Ctrl+Alt+N',
        );
        await _waitUntil(() => host.registerCalls == 2);

        final exitFuture = service.exitApplication();
        guard.complete(true);
        await _waitUntil(() => host.destroyCalls == 1);

        // The register result returns while destroy is in flight: the apply
        // must not publish it or start any new operation.
        registerGate.complete(const DesktopShellResult.success());
        await _pump(times: 4);
        final between = host.eventsBetween(
          'H1:destroy-begin',
          'H1:destroy-throw',
        );
        expect(between.where((e) => e.contains('register-begin')), isEmpty);
        expect(between.where((e) => e.contains('start-begin')), isEmpty);

        destroyGate.complete();
        expect(await exitFuture, DesktopExitResult.failed);
        expect(service.isExitInProgress, isFalse);

        // The waiting apply now retries tray + hotkey against the restored host.
        final result = await secondApply;
        expect(result.aborted, isFalse);
        expect(result.superseded, isFalse);
        expect(result.tray.succeeded, isTrue);
        expect(result.hotkey.succeeded, isTrue);
        expect(result.registeredShortcut, 'Ctrl+Alt+N');
        expect(host.startCalls, 2);
        // M; the in-flight N discarded at failure; then N again on retry.
        expect(host.registerCalls, 3);
        expect(service.isTrayInitialized, isTrue);
        expect(service.registeredGlobalShortcut, 'Ctrl+Alt+N');
        expect(service.isApplyingSettings, isFalse);

        // A subsequent approved exit with a healthy destroy completes.
        host.destroyThrows = false;
        host.destroyGate = null;
        host.registerGate = null;
        expect(
          await service.exitApplication(),
          DesktopExitResult.completed,
        );
        expect(host.destroyCalls, 2);
        expect(service.isApplyingSettings, isFalse);
      },
    );

    test(
      'concurrent exit requests and a late apply still run the guard and destroy once',
      () async {
        final host = _ScriptedHost(1);
        final service = DesktopShellService.forTest(host);
        await service.applySettings(
          closeToTray: true,
          globalShortcut: 'Ctrl+Alt+M',
        );

        final guard = Completer<bool>();
        var guardCalls = 0;
        service.onExit = () {
          guardCalls++;
          return guard.future;
        };
        final destroyGate = Completer<void>();
        host.destroyGate = destroyGate;

        final e1 = service.exitApplication();
        host.callbacks!.onWindowCloseRequested();
        host.callbacks!.onExitRequested!.call();
        final e2 = service.exitApplication();
        expect(identical(e1, e2), isTrue);
        await _waitUntil(() => guardCalls == 1);

        final lateApply = service.applySettings(
          closeToTray: false,
          globalShortcut: 'Ctrl+Alt+N',
        );
        await _pump(times: 3);

        guard.complete(true);
        await _waitUntil(() => host.destroyCalls == 1);
        expect(
          host
              .eventsAfter('H1:destroy-begin')
              .where((e) => e.contains('start-begin') || e.contains('register-begin')),
          isEmpty,
        );

        destroyGate.complete();
        expect(await e1, DesktopExitResult.completed);
        expect(await e2, DesktopExitResult.completed);
        expect((await lateApply).aborted, isTrue);
        expect(guardCalls, 1);
        expect(host.destroyCalls, 1);
        expect(service.isApplyingSettings, isFalse);

        // Calls after a completed exit are inert.
        expect(
          await service.exitApplication(),
          DesktopExitResult.completed,
        );
        expect(host.destroyCalls, 1);
      },
    );
  });

  group('RF10 exit guard: direct hotkey APIs', () {
    test(
      'direct calls wait for an in-flight exit and stay disabled after completion',
      () async {
        final rig = _FactoryRig.create();
        final service = rig.service;
        await service.applySettings(
          closeToTray: true,
          globalShortcut: 'Ctrl+Alt+M',
        );
        final h1 = rig.hosts.single;

        final guard = Completer<bool>();
        service.onExit = () => guard.future;
        final destroyGate = Completer<void>();
        h1.destroyGate = destroyGate;

        final exitFuture = service.exitApplication();
        await _waitUntil(() => service.isExitInProgress);

        // Direct calls while exit is pending must wait instead of touching the host.
        final directRegister = service.registerGlobalHotkey(
          'Ctrl+Alt+P',
          () {},
        );
        final directUnregister = service.unregisterGlobalHotkey();
        await _pump(times: 3);
        expect(rig.hosts, hasLength(1));

        guard.complete(true);
        await _waitUntil(() => h1.destroyCalls == 1);
        expect(
          rig
              .eventsAfter('H1:destroy-begin')
              .where((e) => e.contains('start') || e.contains('register')),
          isEmpty,
        );
        destroyGate.complete();

        expect(await exitFuture, DesktopExitResult.completed);
        expect(
          (await directRegister).kind,
          DesktopShellResultKind.disabled,
        );
        expect(
          (await directUnregister).kind,
          DesktopShellResultKind.disabled,
        );
        expect(rig.hosts, hasLength(1));

        // Calls after a completed exit stay inert without a factory call.
        expect(
          (await service.registerGlobalHotkey('Ctrl+Alt+Q', () {})).kind,
          DesktopShellResultKind.disabled,
        );
        expect(
          (await service.unregisterGlobalHotkey()).kind,
          DesktopShellResultKind.disabled,
        );
        expect(rig.hosts, hasLength(1));
      },
    );
  });
}

Future<void> _pump({int times = 1}) async {
  for (var i = 0; i < times; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<void> _waitUntil(bool Function() condition) async {
  for (var i = 0; i < 100; i++) {
    if (condition()) return;
    await Future<void>.delayed(Duration.zero);
  }
  expect(condition(), isTrue);
}

class _FactoryRig {
  _FactoryRig._(this.service, this.events, this.hosts);

  final DesktopShellService service;
  final List<String> events;
  final List<_ScriptedHost> hosts;

  factory _FactoryRig.create({
    void Function(_ScriptedHost host)? configure,
  }) {
    final events = <String>[];
    final hosts = <_ScriptedHost>[];
    final config = configure ?? ((_) {});
    final service = DesktopShellService.forTestFactory(() {
      final host = _ScriptedHost(hosts.length + 1, events);
      hosts.add(host);
      config(host);
      return host;
    });
    return _FactoryRig._(service, events, hosts);
  }

  List<String> eventsAfter(String marker) {
    final index = events.lastIndexOf(marker);
    return index < 0 ? const <String>[] : events.sublist(index + 1);
  }
}

class _ScriptedHost implements DesktopShellHost {
  _ScriptedHost(this.serial, [List<String>? eventLog])
    : _events = eventLog ?? <String>[];

  final int serial;
  final List<String> _events;
  List<String> get events => _events;

  Completer<DesktopShellResult>? startGate;
  Completer<DesktopShellResult>? registerGate;
  Completer<DesktopShellResult>? unregisterGate;
  Completer<void>? destroyGate;
  bool destroyThrows = false;
  DesktopShellResult startResult = const DesktopShellResult.success();
  DesktopShellResult registerResult = const DesktopShellResult.success();
  DesktopShellResult unregisterResult = const DesktopShellResult.success();

  int startCalls = 0;
  int registerCalls = 0;
  int unregisterCalls = 0;
  int hideCalls = 0;
  int showCalls = 0;
  int destroyCalls = 0;
  DesktopShellHostCallbacks? callbacks;

  String? _registeredShortcut;
  @override
  String? get registeredShortcut => _registeredShortcut;

  void _log(String message) => _events.add('H$serial:$message');

  @override
  Future<DesktopShellResult> start(
    DesktopShellHostCallbacks callbacks,
  ) async {
    startCalls++;
    this.callbacks = callbacks;
    _log('start-begin');
    final gate = startGate;
    final result = gate == null ? startResult : await gate.future;
    _log('start-end:${result.kind.name}');
    return result;
  }

  @override
  Future<DesktopShellResult> registerHotkey(
    String shortcut,
    VoidCallback onTrigger,
  ) async {
    registerCalls++;
    _log('register-begin:$shortcut');
    final gate = registerGate;
    final result = gate == null ? registerResult : await gate.future;
    if (result.succeeded) _registeredShortcut = shortcut;
    _log('register-end:${result.kind.name}');
    return result;
  }

  @override
  Future<DesktopShellResult> unregisterHotkey() async {
    unregisterCalls++;
    _log('unregister-begin');
    final gate = unregisterGate;
    final result = gate == null ? unregisterResult : await gate.future;
    if (result.succeeded) _registeredShortcut = null;
    _log('unregister-end:${result.kind.name}');
    return result;
  }

  @override
  Future<DesktopShellResult> hide() async {
    hideCalls++;
    _log('hide');
    return const DesktopShellResult.success();
  }

  @override
  Future<DesktopShellResult> show() async {
    showCalls++;
    _log('show');
    return const DesktopShellResult.success();
  }

  @override
  Future<void> destroy() async {
    destroyCalls++;
    _log('destroy-begin');
    final gate = destroyGate;
    if (gate != null) await gate.future;
    if (destroyThrows) {
      _log('destroy-throw');
      throw StateError('synthetic destroy failure');
    }
    _log('destroy-end');
  }

  List<String> eventsAfter(String marker) {
    final index = _events.lastIndexOf(marker);
    return index < 0 ? const <String>[] : _events.sublist(index + 1);
  }

  List<String> eventsBetween(String beginMarker, String endMarker) {
    final begin = _events.lastIndexOf(beginMarker);
    final end = _events.lastIndexOf(endMarker);
    if (begin < 0 || end < 0 || end <= begin) return const <String>[];
    return _events.sublist(begin + 1, end);
  }
}
