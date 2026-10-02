import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/main.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/screens/startup_recovery_screen.dart';
import 'package:matrixflow_native/screens/windows_upgrade_screen.dart';
import 'package:matrixflow_native/services/windows_data_upgrade.dart';
import 'package:matrixflow_native/storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';

import 'wp28_u1_support.dart';

const requiredKey = SaveProtocol.windowsCredentialsRequiredKey;
const readKey = SaveProtocol.windowsCredentialNoticeReadKey;
const syntheticKey = 'SYNTHETIC_U2_RECONFIGURED_INVALID';

class Credentials implements CredentialStore {
  String? value;
  bool failWrite = false;
  bool failRead = false;
  bool failDelete = false;
  bool mismatch = false;
  int writes = 0;
  Completer<void>? writeGate;
  @override
  Future<String?> read() async {
    if (failRead) throw StateError('Synthetic read failure');
    return mismatch ? null : value;
  }

  @override
  Future<void> write(String value) async {
    writes++;
    await writeGate?.future;
    if (failWrite) throw StateError('Synthetic write failure');
    this.value = value;
  }

  @override
  Future<void> delete() async {
    if (failDelete) throw StateError('Synthetic delete failure');
    value = null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Credentials credentials;
  setUp(() {
    credentials = Credentials();
    SharedPreferences.setMockInitialValues({
      for (final entry in syntheticSnapshot().entries)
        entry.key: entry.key == 'matrixflow-has-seen-onboarding'
            ? entry.value == 'true'
            : entry.value,
      requiredKey: true,
    });
  });

  Future<Store> open({SaveWrite? writer, bool seed = false}) async {
    final store = Store(
      credentialStore: credentials,
      reminders: NoopReminderService(),
      saveWriter: writer,
      windowsCredentialsRequiredOnOpen: seed,
    );
    await store.init();
    await store.flush();
    addTearDown(store.dispose);
    return store;
  }

  for (final key in [requiredKey, readKey]) {
    testWidgets('invalid upgrade mirror $key renders recovery without writes', (
      tester,
    ) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, 'damaged-upgrade-state');
      final store = await open();
      expect(store.hasStartupRecovery, isTrue);
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: store,
          child: const MaterialApp(home: StartupRecoveryScreen()),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(
        find.text(store.t['recoveryCredentialUpgradeState']!),
        findsOneWidget,
      );
      expect(prefs.getString(key), 'damaged-upgrade-state');
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  test(
    'acknowledgement persists, leaves setup required, reopens without gate',
    () async {
      final store = await open();
      expect(await store.acknowledgeWindowsCredentialNotice(), isTrue);
      expect(store.windowsCredentialsNeedSetup, isTrue);
      expect(credentials.writes, 0);
      final again = await open();
      expect(again.windowsCredentialNoticeRead, isTrue);
      expect(again.windowsCredentialsNeedSetup, isTrue);
      final prefs = await SharedPreferences.getInstance();
      final batch = SaveProtocol(prefs).load()!;
      expect(batch.values[requiredKey], 'true');
      expect(batch.values[readKey], 'true');
      expect(jsonEncode(batch.values), isNot(contains(syntheticKey)));
    },
  );

  test('failed acknowledgement rolls back; explicit retry commits', () async {
    var fail = false;
    final store = await open(
      writer: (key, value) async {
        if (fail && key.startsWith('matrixflow-save-')) return false;
        return (await SharedPreferences.getInstance()).setString(key, value);
      },
    );
    fail = true;
    expect(await store.acknowledgeWindowsCredentialNotice(), isFalse);
    expect(store.windowsCredentialNoticeRead, isFalse);
    expect((await open()).windowsCredentialNoticeRead, isFalse);
    fail = false;
    expect(await store.acknowledgeWindowsCredentialNotice(), isTrue);
    expect((await open()).windowsCredentialNoticeRead, isTrue);
  });

  for (final failure in ['write', 'readback']) {
    test(
      '$failure failure never clears setup; credential retry verifies and saves',
      () async {
        final store = await open();
        await store.acknowledgeWindowsCredentialNotice();
        credentials.failWrite = failure == 'write';
        credentials.mismatch = failure == 'readback';
        expect(
          await store.updateAIConfig(AIConfig(apiKey: syntheticKey)),
          isFalse,
        );
        expect(store.windowsCredentialsNeedSetup, isTrue);
        credentials.failWrite = false;
        credentials.mismatch = false;
        expect(await store.retryCredential(), isTrue);
        expect((await store.flush()).success, isTrue);
        expect((await open()).windowsCredentialsNeedSetup, isFalse);
      },
    );
  }

  test(
    'reading a pre-existing secure key alone does not certify a new write',
    () async {
      credentials.value = syntheticKey;
      final store = await open();
      expect(store.windowsCredentialsNeedSetup, isTrue);
      expect(credentials.writes, 0);
      expect(
        await store.updateAIConfig(AIConfig(apiKey: syntheticKey)),
        isTrue,
      );
      expect(credentials.writes, 1);
      expect((await store.flush()).success, isTrue);
      expect((await open()).windowsCredentialsNeedSetup, isFalse);
    },
  );

  test(
    'delete failure preserves configured state; verified deletion restores setting notice',
    () async {
      final store = await open();
      await store.acknowledgeWindowsCredentialNotice();
      await store.updateAIConfig(AIConfig(apiKey: syntheticKey));
      await store.flush();
      credentials.failDelete = true;
      expect(await store.updateAIConfig(AIConfig()), isFalse);
      expect(store.windowsCredentialsNeedSetup, isFalse);
      credentials.failDelete = false;
      expect(await store.retryCredential(), isTrue);
      await store.flush();
      final again = await open();
      expect(again.windowsCredentialsNeedSetup, isTrue);
      expect(again.windowsCredentialNoticeRead, isTrue);
    },
  );

  test(
    'latest queued deletion wins over a blocked older configuration',
    () async {
      final store = await open();
      credentials.writeGate = Completer<void>();
      final first = store.updateAIConfig(AIConfig(apiKey: syntheticKey));
      await Future<void>.delayed(Duration.zero);
      final second = store.updateAIConfig(
        AIConfig(apiKey: 'SYNTHETIC_U2_OLDER_INVALID'),
      );
      final third = store.updateAIConfig(AIConfig());
      credentials.writeGate!.complete();
      await Future.wait([first, second, third]);
      expect((await store.flush()).success, isTrue);
      expect(credentials.value, isNull);
      expect((await open()).windowsCredentialsNeedSetup, isTrue);
    },
  );

  test(
    'secure success plus slot failure stays pending and retrySave persists state',
    () async {
      var fail = false;
      final store = await open(
        writer: (key, value) async {
          if (fail && key.startsWith('matrixflow-save-')) return false;
          return (await SharedPreferences.getInstance()).setString(key, value);
        },
      );
      fail = true;
      expect(
        await store.updateAIConfig(AIConfig(apiKey: syntheticKey)),
        isTrue,
      );
      expect((await store.flush()).success, isFalse);
      expect(
        SaveProtocol(
          await SharedPreferences.getInstance(),
        ).load()!.values[requiredKey],
        'true',
      );
      fail = false;
      expect((await store.retrySave()).success, isTrue);
      expect((await open()).windowsCredentialsNeedSetup, isFalse);
    },
  );

  test('recovery lock blocks acknowledgement and secure writes', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('matrixflow-tasks', '[broken');
    final before = Map<String, Object?>.from({
      for (final key in prefs.getKeys()) key: prefs.get(key),
    });
    final store = await open();
    expect(store.hasStartupRecovery, isTrue);
    expect(await store.acknowledgeWindowsCredentialNotice(), isFalse);
    expect(await store.updateAIConfig(AIConfig(apiKey: syntheticKey)), isFalse);
    expect({for (final key in prefs.getKeys()) key: prefs.get(key)}, before);
    expect(credentials.writes, 0);
  });

  test(
    'encrypted source without preferences seeds persistent state on valid open',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = await open(seed: true);
      expect(store.windowsCredentialsNeedSetup, isTrue);
      expect(await store.acknowledgeWindowsCredentialNotice(), isTrue);
      expect((await open()).windowsCredentialNoticeRead, isTrue);
    },
  );

  test(
    'malformed state is protected rather than silently acknowledged',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(requiredKey, 'invalid');
      final store = await open();
      expect(store.hasStartupRecovery, isTrue);
      expect(await store.acknowledgeWindowsCredentialNotice(), isFalse);
      expect(prefs.getString(requiredKey), 'invalid');
    },
  );

  for (final failCommit in [false, true]) {
    test(
      'explicit credential import shares the state commit and rollback ($failCommit)',
      () async {
        var armed = false;
        final store = await open(
          writer: (key, value) async {
            if (armed && key.startsWith('matrixflow-save-')) return false;
            return (await SharedPreferences.getInstance()).setString(
              key,
              value,
            );
          },
        );
        await store.acknowledgeWindowsCredentialNotice();
        armed = failCommit;
        final plan = store.previewImport({
          'version': 2,
          'boards': [
            {
              'id': 'synthetic-import-board',
              'name': 'Synthetic import',
              'createdAt': 1,
            },
          ],
          'tasks': <Object>[],
          'aiConfig': {
            'providerId': 'custom',
            'protocol': 'openai',
            'customBaseUrl': 'https://example.invalid/v1',
            'customModel': 'synthetic-model',
            'customApiKey': syntheticKey,
          },
        }, 'overwrite');
        expect(
          (await store.applyImport(plan, importCredential: true)).success,
          !failCommit,
        );
        expect(store.windowsCredentialsNeedSetup, failCommit);
        expect(credentials.value, failCommit ? null : syntheticKey);
        final batch = SaveProtocol(
          await SharedPreferences.getInstance(),
        ).load()!;
        expect(batch.values[requiredKey], failCommit.toString());
        expect(batch.values[readKey], 'true');
      },
    );
  }

  test(
    'resolved recovery requires a fresh validated acknowledgement',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('matrixflow-tasks', '[broken');
      final store = await open();
      expect(await store.acknowledgeWindowsCredentialNotice(), isFalse);
      expect(await store.discardDamagedStartupData(), isTrue);
      expect(await store.acknowledgeWindowsCredentialNotice(), isTrue);
      expect((await open()).windowsCredentialNoticeRead, isTrue);
    },
  );

  test(
    'failed Store credential validation leaves confirmation pending',
    () async {
      credentials.failRead = true;
      final store = await open();
      expect(await store.acknowledgeWindowsCredentialNotice(), isFalse);
      expect((await SharedPreferences.getInstance()).getBool(readKey), isNull);
      credentials.failRead = false;
      expect(await store.retryCredential(), isTrue);
      expect(await store.acknowledgeWindowsCredentialNotice(), isTrue);
    },
  );

  test(
    'committed state overrides a stale bootstrap mirror in upgrade preparation',
    () async {
      final fixture = await UpgradeFixture.create();
      addTearDown(fixture.dispose);
      final store = await open();
      await store.acknowledgeWindowsCredentialNotice();
      await store.updateAIConfig(AIConfig(apiKey: syntheticKey));
      await store.flush();
      final prefs = await SharedPreferences.getInstance();
      final envelope = <String, Object>{
        for (final key in prefs.getKeys()) 'flutter.$key': prefs.get(key)!,
      };
      envelope['flutter.$requiredKey'] = true;
      envelope['flutter.$readKey'] = false;
      await fixture.writeTarget(jsonEncode(envelope));
      final prepared = await fixture.adapter().prepare();
      expect(prepared.credentialsNeedSetup, isFalse);
      expect(prepared.credentialNoticeRead, isTrue);
      expect(prepared.showCredentialNotice, isFalse);
    },
    skip: false,
  );

  testWidgets(
    'closing gate leaves acknowledgement untouched; continue confirms once',
    (tester) async {
      var confirmations = 0;
      var closes = 0;
      var opens = 0;
      await tester.pumpWidget(
        WindowsUpgradeStartup(
          deviceLocales: const [Locale('en')],
          prepare: () async => const WindowsUpgradeResult(
            WindowsUpgradeStatus.migrated,
            credentialsNeedSetup: true,
          ),
          onCredentialNoticeConfirmed: () => confirmations++,
          closeBeforeStore: () async {
            closes++;
          },
          openApplication: () async {
            opens++;
            return const MaterialApp(home: Text('opened'));
          },
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Close app'));
      await tester.tap(find.text('Close app'));
      expect(closes, 1);
      expect(confirmations, 0);
      expect(opens, 0);
      await tester.ensureVisible(find.text('Continue to app / recovery'));
      await tester.tap(find.text('Continue to app / recovery'));
      await tester.pumpAndSettle();
      expect(confirmations, 1);
      expect(opens, 1);
    },
  );

  testWidgets(
    'production app records explicit confirmation only after validated Store',
    (tester) async {
      Store.testCredentialStore = credentials;
      addTearDown(() => Store.testCredentialStore = null);
      await tester.pumpWidget(
        MatrixFlowApp(
          reminders: NoopReminderService(),
          acknowledgeWindowsCredentialNotice: true,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        SaveProtocol(
          await SharedPreferences.getInstance(),
        ).load()!.values[readKey],
        'true',
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}
