import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/services/desktop_exit_coordinator.dart';
import 'package:matrixflow_native/storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Keys implements CredentialStore {
  String? value;
  Completer<void>? hold;
  Completer<void>? entered;
  bool failWrite = false;
  String? failOn;
  bool failRead = false;
  bool failDelete = false;
  int writes = 0;

  @override
  Future<String?> read() async {
    if (failRead) throw StateError('synthetic read failure');
    return value;
  }

  @override
  Future<void> write(String value) async {
    writes++;
    final gate = hold;
    if (gate != null) {
      hold = null;
      entered?.complete();
      await gate.future;
    }
    if (failWrite || value == failOn) {
      throw StateError('synthetic write failure');
    }
    this.value = value;
  }

  @override
  Future<void> delete() async {
    if (failDelete) throw StateError('synthetic delete failure');
    value = null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<Store> open(_Keys keys, {SaveWrite? writer}) async {
    final store = Store(credentialStore: keys, saveWriter: writer);
    await store.init();
    expect((await store.flush()).success, isTrue);
    return store;
  }

  Future<void> restart(Store old, _Keys keys, String expected) async {
    old.dispose();
    final again = await open(keys);
    expect(again.aiConfig.apiKey, expected);
    expect(keys.value, expected.isEmpty ? isNull : expected);
    again.dispose();
  }

  test(
    'A to B to empty keeps latest choice through flush and restart',
    () async {
      SharedPreferences.setMockInitialValues({});
      final keys = _Keys();
      final store = await open(keys);
      expect(
        await store.updateAIConfig(AIConfig(apiKey: 'synthetic-A')),
        isTrue,
      );
      final gate = Completer<void>();
      keys.hold = gate;
      keys.entered = Completer<void>();
      final old = store.updateAIConfig(AIConfig(apiKey: 'synthetic-B'));
      await keys.entered!.future;
      final clear = store.updateAIConfig(AIConfig(apiKey: ''));
      var drained = false;
      final flush = store.flush().then((result) {
        drained = true;
        return result;
      });
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(drained, isFalse);
      gate.complete();
      await old;
      expect(await clear, isTrue);
      expect((await flush).success, isTrue);
      expect(store.aiConfig.apiKey, isEmpty);
      await restart(store, keys, '');
    },
  );

  test(
    'empty to A to empty and repeated values do not skip correction',
    () async {
      SharedPreferences.setMockInitialValues({});
      final keys = _Keys();
      final store = await open(keys);
      final gate = Completer<void>();
      keys.hold = gate;
      keys.entered = Completer<void>();
      final first = store.updateAIConfig(AIConfig(apiKey: 'synthetic-A'));
      await keys.entered!.future;
      expect(await store.updateAIConfig(AIConfig(apiKey: '')), isTrue);
      gate.complete();
      await first;
      expect((await store.flush()).success, isTrue);
      expect(keys.value, isNull);
      expect(
        await store.updateAIConfig(AIConfig(apiKey: 'synthetic-C')),
        isTrue,
      );
      final writes = keys.writes;
      expect(
        await store.updateAIConfig(AIConfig(apiKey: 'synthetic-C')),
        isTrue,
      );
      expect(keys.writes, writes);
      await restart(store, keys, 'synthetic-C');
    },
  );

  test('older failure cannot overwrite newer successful intent', () async {
    SharedPreferences.setMockInitialValues({});
    final keys = _Keys()..failOn = 'synthetic-old';
    final store = await open(keys);
    final gate = Completer<void>();
    keys.hold = gate;
    keys.entered = Completer<void>();
    final old = store.updateAIConfig(AIConfig(apiKey: 'synthetic-old'));
    await keys.entered!.future;
    final latest = store.updateAIConfig(AIConfig(apiKey: 'synthetic-new'));
    gate.complete();
    expect(await old, isFalse);
    expect(await latest, isTrue);
    expect((await store.flush()).success, isTrue);
    expect(store.credentialError, isNull);
    await restart(store, keys, 'synthetic-new');
  });

  test(
    'latest failure and readback failure remain visible until retry',
    () async {
      SharedPreferences.setMockInitialValues({});
      final keys = _Keys();
      final store = await open(keys);
      expect(
        await store.updateAIConfig(AIConfig(apiKey: 'synthetic-A')),
        isTrue,
      );
      keys.failWrite = true;
      expect(
        await store.updateAIConfig(AIConfig(apiKey: 'synthetic-B')),
        isFalse,
      );
      expect((await store.flush()).success, isFalse);
      expect(store.credentialError, isNotNull);
      expect(store.aiConfig.apiKey, 'synthetic-A');
      keys.failWrite = false;
      expect(await store.retryCredential(), isTrue);
      expect((await store.flush()).success, isTrue);
      keys.failRead = true;
      expect(
        await store.updateAIConfig(AIConfig(apiKey: 'synthetic-C')),
        isFalse,
      );
      expect((await store.flush()).success, isFalse);
      expect(store.aiConfig.apiKey, 'synthetic-B');
      keys.failRead = false;
      expect((await store.retrySave()).success, isTrue);
      await restart(store, keys, 'synthetic-C');
    },
  );

  test(
    'import and newer edit serialize secure writes and restart consistently',
    () async {
      SharedPreferences.setMockInitialValues({});
      final keys = _Keys();
      final store = await open(keys);
      final plan = store.previewImport({
        'version': 2,
        'boards': store.boards.map((b) => b.toJson()).toList(),
        'tasks': <Object>[],
        'aiConfig': AIConfig(apiKey: 'synthetic-import').toJson(),
      }, 'overwrite');
      final gate = Completer<void>();
      keys.hold = gate;
      keys.entered = Completer<void>();
      final importing = store.applyImport(plan, importCredential: true);
      await keys.entered!.future;
      final latest = store.updateAIConfig(AIConfig(apiKey: 'synthetic-edit'));
      var drained = false;
      final flush = store.flush().then((value) {
        drained = true;
        return value;
      });
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(drained, isFalse);
      gate.complete();
      expect((await importing).success, isTrue);
      expect(await latest, isTrue);
      expect((await flush).success, isTrue);
      await restart(store, keys, 'synthetic-edit');
    },
  );

  test('failed import rolls back before a newer credential edit', () async {
    SharedPreferences.setMockInitialValues({});
    final keys = _Keys();
    var rejectImport = false;
    final store = await open(
      keys,
      writer: (key, value) async {
        if (rejectImport && key == SaveProtocol.pointerKey) {
          rejectImport = false;
          return false;
        }
        return (await SharedPreferences.getInstance()).setString(key, value);
      },
    );
    expect(
      await store.updateAIConfig(AIConfig(apiKey: 'synthetic-local')),
      isTrue,
    );
    expect((await store.flush()).success, isTrue);
    final plan = store.previewImport({
      'version': 2,
      'boards': store.boards.map((b) => b.toJson()).toList(),
      'tasks': <Object>[],
      'aiConfig': AIConfig(apiKey: 'synthetic-import').toJson(),
    }, 'overwrite');
    final gate = Completer<void>();
    keys.hold = gate;
    keys.entered = Completer<void>();
    rejectImport = true;
    final importing = store.applyImport(plan, importCredential: true);
    await keys.entered!.future;
    final latest = store.updateAIConfig(AIConfig(apiKey: 'synthetic-latest'));
    gate.complete();
    expect((await importing).success, isFalse);
    expect(await latest, isTrue);
    expect((await store.flush()).success, isTrue);
    await restart(store, keys, 'synthetic-latest');
  });

  test('failed import does not deadlock a second queued import', () async {
    SharedPreferences.setMockInitialValues({});
    final keys = _Keys();
    var armed = false;
    final entered = Completer<void>();
    final gate = Completer<void>();
    final store = await open(
      keys,
      writer: (key, value) async {
        if (armed && key == SaveProtocol.pointerKey) {
          armed = false;
          entered.complete();
          await gate.future;
          return false;
        }
        return (await SharedPreferences.getInstance()).setString(key, value);
      },
    );
    Map<String, dynamic> payload(String key) => {
      'version': 2,
      'boards': store.boards.map((b) => b.toJson()).toList(),
      'tasks': <Object>[],
      'aiConfig': AIConfig(apiKey: key).toJson(),
    };
    final firstPlan = store.previewImport(
      payload('synthetic-first'),
      'overwrite',
    );
    final secondPlan = store.previewImport(
      payload('synthetic-second'),
      'overwrite',
    );
    armed = true;
    final first = store.applyImport(firstPlan, importCredential: true);
    await entered.future;
    final second = store.applyImport(secondPlan, importCredential: true);
    gate.complete();
    expect((await first).success, isFalse);
    expect((await second).success, isTrue);
    expect((await store.flush()).success, isTrue);
    await restart(store, keys, 'synthetic-second');
  });

  test(
    'credential edit after a queued import keeps its accepted order',
    () async {
      SharedPreferences.setMockInitialValues({});
      final keys = _Keys();
      var armed = false;
      final entered = Completer<void>();
      final gate = Completer<void>();
      final store = await open(
        keys,
        writer: (key, value) async {
          if (armed &&
              key.startsWith('matrixflow-save-') &&
              key != SaveProtocol.pointerKey) {
            armed = false;
            entered.complete();
            await gate.future;
          }
          return (await SharedPreferences.getInstance()).setString(key, value);
        },
      );
      armed = true;
      store.createBoard('Synthetic queued board');
      await entered.future;
      final plan = store.previewImport({
        'version': 2,
        'boards': store.boards.map((b) => b.toJson()).toList(),
        'tasks': <Object>[],
        'aiConfig': AIConfig(apiKey: 'synthetic-import').toJson(),
      }, 'overwrite');
      final importing = store.applyImport(plan, importCredential: true);
      final latest = store.updateAIConfig(AIConfig(apiKey: 'synthetic-latest'));
      gate.complete();
      expect((await importing).success, isTrue);
      expect(await latest, isTrue);
      expect((await store.flush()).success, isTrue);
      await restart(store, keys, 'synthetic-latest');
    },
  );

  test(
    'failed newer edit during failed import retains error and retry',
    () async {
      SharedPreferences.setMockInitialValues({});
      final keys = _Keys()..failOn = 'synthetic-latest';
      var armed = false;
      final entered = Completer<void>();
      final gate = Completer<void>();
      final store = await open(
        keys,
        writer: (key, value) async {
          if (armed && key == SaveProtocol.pointerKey) {
            armed = false;
            entered.complete();
            await gate.future;
            return false;
          }
          return (await SharedPreferences.getInstance()).setString(key, value);
        },
      );
      expect(
        await store.updateAIConfig(AIConfig(apiKey: 'synthetic-local')),
        isTrue,
      );
      expect((await store.flush()).success, isTrue);
      final plan = store.previewImport({
        'version': 2,
        'boards': store.boards.map((b) => b.toJson()).toList(),
        'tasks': <Object>[],
        'aiConfig': AIConfig(apiKey: 'synthetic-import').toJson(),
      }, 'overwrite');
      armed = true;
      final importing = store.applyImport(plan, importCredential: true);
      await entered.future;
      expect(
        await store.updateAIConfig(AIConfig(apiKey: 'synthetic-latest')),
        isFalse,
      );
      gate.complete();
      expect((await importing).success, isFalse);
      expect(store.credentialError, isNotNull);
      expect((await store.flush()).success, isFalse);
      expect(keys.value, 'synthetic-local');
      keys.failOn = null;
      expect((await store.retrySave()).success, isTrue);
      await restart(store, keys, 'synthetic-latest');
    },
  );

  test(
    'same key chosen during failing import remains the latest intent',
    () async {
      SharedPreferences.setMockInitialValues({});
      final keys = _Keys();
      var armed = false;
      final entered = Completer<void>();
      final gate = Completer<void>();
      final store = await open(
        keys,
        writer: (key, value) async {
          if (armed && key == SaveProtocol.pointerKey) {
            armed = false;
            entered.complete();
            await gate.future;
            return false;
          }
          return (await SharedPreferences.getInstance()).setString(key, value);
        },
      );
      final plan = store.previewImport({
        'version': 2,
        'boards': store.boards.map((b) => b.toJson()).toList(),
        'tasks': <Object>[],
        'aiConfig': AIConfig(apiKey: 'synthetic-import').toJson(),
      }, 'overwrite');
      armed = true;
      final importing = store.applyImport(plan, importCredential: true);
      await entered.future;
      expect(
        await store.updateAIConfig(AIConfig(apiKey: 'synthetic-import')),
        isTrue,
      );
      gate.complete();
      expect((await importing).success, isFalse);
      expect((await store.flush()).success, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('matrixflow-config'),
        isNot(contains('synthetic-import')),
      );
      await restart(store, keys, 'synthetic-import');
    },
  );

  test(
    'retry after failure persists the accompanying non-secret config',
    () async {
      SharedPreferences.setMockInitialValues({});
      final keys = _Keys();
      final store = await open(keys);
      keys.failWrite = true;
      expect(
        await store.updateAIConfig(AIConfig(apiKey: 'synthetic-retry')),
        isFalse,
      );
      keys.failWrite = false;
      final changed = store.copyAIConfig()
        ..apiKey = 'synthetic-retry'
        ..baseUrl = 'https://example.invalid/retry';
      expect(await store.updateAIConfig(changed), isTrue);
      expect((await store.flush()).success, isTrue);
      store.dispose();
      final again = await open(keys);
      expect(again.aiConfig.apiKey, 'synthetic-retry');
      expect(again.aiConfig.baseUrl, 'https://example.invalid/retry');
      again.dispose();
    },
  );

  test('late credential completion after dispose does not notify', () async {
    SharedPreferences.setMockInitialValues({});
    final keys = _Keys();
    final store = await open(keys);
    final gate = Completer<void>();
    keys.hold = gate;
    keys.entered = Completer<void>();
    final update = store.updateAIConfig(AIConfig(apiKey: 'synthetic-late'));
    await keys.entered!.future;
    store.dispose();
    gate.complete();
    expect(await update, isTrue);
    expect(keys.value, 'synthetic-late');
  });

  test(
    'exit waits, times out to cancel, and retries failed credentials',
    () async {
      SharedPreferences.setMockInitialValues({});
      final keys = _Keys();
      final store = await open(keys);
      final gate = Completer<void>();
      keys.hold = gate;
      keys.entered = Completer<void>();
      final update = store.updateAIConfig(AIConfig(apiKey: 'synthetic-exit'));
      await keys.entered!.future;
      final problems = <DesktopExitSaveProblem>[];
      final coordinator = DesktopExitSaveCoordinator(
        flush: store.flush,
        retrySave: store.retrySave,
        chooseAfterProblem: (problem) async {
          problems.add(problem);
          return DesktopExitSaveChoice.cancel;
        },
        timeout: const Duration(milliseconds: 10),
      );
      expect(await coordinator.prepareToExit(), isFalse);
      expect(problems, [DesktopExitSaveProblem.timedOut]);
      gate.complete();
      expect(await update, isTrue);
      expect((await store.flush()).success, isTrue);
      keys.failWrite = true;
      expect(
        await store.updateAIConfig(AIConfig(apiKey: 'synthetic-retry')),
        isFalse,
      );
      keys.failWrite = false;
      final retry = DesktopExitSaveCoordinator(
        flush: store.flush,
        retrySave: store.retrySave,
        chooseAfterProblem: (problem) async {
          problems.add(problem);
          return DesktopExitSaveChoice.retry;
        },
        timeout: const Duration(seconds: 1),
      );
      expect(await retry.prepareToExit(), isTrue);
      expect(problems.last, DesktopExitSaveProblem.failed);
      await restart(store, keys, 'synthetic-retry');
    },
  );
}
