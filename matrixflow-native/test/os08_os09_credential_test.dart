import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _sentinel = 'SYNTHETIC_OS09_SENTINEL_INVALID';

class _MemoryCredential implements CredentialStore {
  String? value;
  bool failWrite = false;
  bool failRead = false;
  bool failDelete = false;
  @override
  Future<String?> read() async {
    if (failRead) throw StateError('synthetic read failure');
    return value;
  }

  @override
  Future<void> write(String value) async {
    if (failWrite) throw StateError('synthetic write failure');
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

  Future<Store> open(_MemoryCredential credential, {SaveWrite? writer}) async {
    final store = Store(credentialStore: credential, saveWriter: writer);
    await store.init();
    await store.flush();
    return store;
  }

  Map<String, dynamic> backup({int version = 2, bool withKey = true}) => {
    'version': version,
    'boards': [
      {'id': 'backup-board', 'name': 'Synthetic', 'createdAt': 1},
    ],
    'tasks': <Object>[],
    'aiConfig': {
      'providerId': 'custom',
      'protocol': 'openai',
      'customBaseUrl': 'https://example.invalid/v1',
      'customModel': 'synthetic-model',
      if (withKey) 'customApiKey': _sentinel,
    },
  };

  test(
    'default v2 and v1 exports omit credential; explicit export reads store',
    () async {
      SharedPreferences.setMockInitialValues({});
      final credential = _MemoryCredential();
      final store = await open(credential);
      expect(await store.updateAIConfig(AIConfig(apiKey: _sentinel)), isTrue);
      expect(store.exportJson(), isNot(contains('customApiKey')));
      expect(store.exportJson(version: 1), isNot(contains('customApiKey')));
      expect(
        (jsonDecode(await store.exportJsonWithCredential())
            as Map)['aiConfig']['customApiKey'],
        _sentinel,
      );
      credential.failRead = true;
      await expectLater(store.exportJsonWithCredential(), throwsStateError);
      expect(store.exportJson(), isNot(contains(_sentinel)));
      store.dispose();
    },
  );

  test(
    'first migration scrubs mirror and both slots; repeat startup keeps secure key',
    () async {
      SharedPreferences.setMockInitialValues({
        'matrixflow-config': jsonEncode(AIConfig(apiKey: _sentinel).toJson()),
      });
      final credential = _MemoryCredential();
      final first = await open(credential);
      expect(first.credentialError, isNull);
      expect(credential.value, _sentinel);
      final prefs = await SharedPreferences.getInstance();
      for (final key in [
        'matrixflow-config',
        'matrixflow-save-a',
        'matrixflow-save-b',
      ]) {
        expect(prefs.getString(key) ?? '', isNot(contains(_sentinel)));
      }
      await first.flush();
      first.dispose();
      final second = await open(credential);
      expect(second.aiConfig.apiKey, _sentinel);
      expect(second.credentialError, isNull);
      second.dispose();
    },
  );

  test(
    'migration removes a credential from each pre-existing OS06 slot',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final legacyConfig = jsonEncode(AIConfig(apiKey: _sentinel).toJson());
      final values = <String, String>{
        'matrixflow-tasks': '[]',
        'matrixflow-boards': '[]',
        'matrixflow-config': legacyConfig,
        'matrixflow-settings': '{}',
        'matrixflow-active-board': '',
        'matrixflow-has-seen-onboarding': 'false',
      };
      final protocol = SaveProtocol(prefs);
      expect((await protocol.commit(values)).success, isTrue);
      expect((await protocol.commit(values)).success, isTrue);
      expect(prefs.getString('matrixflow-save-a'), contains(_sentinel));
      expect(prefs.getString('matrixflow-save-b'), contains(_sentinel));
      final credential = _MemoryCredential();
      final store = await open(credential);
      expect(store.credentialError, isNull);
      for (final key in [
        'matrixflow-save-a',
        'matrixflow-save-b',
        'matrixflow-config',
      ]) {
        expect(prefs.getString(key), isNot(contains(_sentinel)));
      }
      expect(SaveProtocol(prefs).load(), isNotNull);
      store.dispose();
    },
  );

  test('OS05 recovery resolution migrates legacy credential before saving', () async {
    SharedPreferences.setMockInitialValues({
      'matrixflow-config': jsonEncode(AIConfig(apiKey: _sentinel).toJson()),
      'matrixflow-tasks': '{damaged',
    });
    final credential = _MemoryCredential();
    final store = Store(credentialStore: credential);
    await store.init();
    expect(store.hasStartupRecovery, isTrue);
    expect(credential.value, isNull);
    expect(await store.discardDamagedStartupData(), isTrue);
    expect(credential.value, _sentinel);
    final prefs = await SharedPreferences.getInstance();
    for (final key in ['matrixflow-config', 'matrixflow-save-a', 'matrixflow-save-b']) {
      expect(prefs.getString(key) ?? '', isNot(contains(_sentinel)));
    }
    store.dispose();
  });

  for (final failure in ['write', 'read', 'scrub']) {
    test(
      'migration $failure failure retains legacy and retry completes',
      () async {
        SharedPreferences.setMockInitialValues({
          'matrixflow-config': jsonEncode(AIConfig(apiKey: _sentinel).toJson()),
        });
        final credential =
            _MemoryCredential()
              ..failWrite = failure == 'write'
              ..failRead = failure == 'read';
        var blockScrub = failure == 'scrub';
        final store = await open(
          credential,
          writer: (key, value) async {
            if (blockScrub && key == 'matrixflow-config') return false;
            return (await SharedPreferences.getInstance()).setString(
              key,
              value,
            );
          },
        );
        expect(store.credentialError, isNotNull);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('matrixflow-config'), contains(_sentinel));
        final attempted = store.aiConfig..apiKey = 'SYNTHETIC_BLOCKED_INVALID';
        expect(await store.updateAIConfig(attempted), isFalse);
        expect(credential.value, isNot('SYNTHETIC_BLOCKED_INVALID'));
        credential.failWrite = false;
        credential.failRead = false;
        blockScrub = false;
        expect(await store.retryCredentialMigration(), isTrue);
        expect((await store.retrySave()).success, isTrue);
        expect(
          prefs.getString('matrixflow-config'),
          isNot(contains(_sentinel)),
        );
        expect(store.aiConfig.apiKey, _sentinel);
        store.dispose();
      },
    );
  }

  test('credential changes and deletion verify secure storage', () async {
    SharedPreferences.setMockInitialValues({});
    final credential = _MemoryCredential();
    final store = await open(credential);
    expect(await store.updateAIConfig(AIConfig(apiKey: _sentinel)), isTrue);
    expect(
      await store.updateAIConfig(
        AIConfig(apiKey: 'SYNTHETIC_REPLACEMENT_INVALID'),
      ),
      isTrue,
    );
    expect(credential.value, 'SYNTHETIC_REPLACEMENT_INVALID');
    credential.failDelete = true;
    expect(await store.updateAIConfig(AIConfig(apiKey: '')), isFalse);
    expect(store.credentialError, isNotNull);
    credential.failDelete = false;
    expect(await store.retryCredential(), isTrue);
    expect(credential.value, isNull);
    expect(store.aiConfig.apiKey, isEmpty);
    store.dispose();
  });

  test(
    'legacy v1/v2, cancel, no-key overwrite and explicit cross-device restore',
    () async {
      SharedPreferences.setMockInitialValues({});
      final credential = _MemoryCredential();
      final store = await open(credential);
      expect(
        await store.updateAIConfig(AIConfig(apiKey: 'SYNTHETIC_LOCAL_INVALID')),
        isTrue,
      );
      for (final version in [1, 2]) {
        final plan = store.previewImport(backup(version: version), 'overwrite');
        expect(plan.hasCredential, isTrue);
        // Cancel is represented by never applying a preview.
        expect(store.aiConfig.apiKey, 'SYNTHETIC_LOCAL_INVALID');
        expect(await store.applyImport(plan), isA<SaveResult>());
        expect(store.aiConfig.apiKey, 'SYNTHETIC_LOCAL_INVALID');
      }
      final noKey = store.previewImport(backup(withKey: false), 'overwrite');
      expect(noKey.hasCredential, isFalse);
      expect((await store.applyImport(noKey)).success, isTrue);
      expect(store.aiConfig.apiKey, 'SYNTHETIC_LOCAL_INVALID');
      store.dispose();

      SharedPreferences.setMockInitialValues({});
      final otherCredential = _MemoryCredential();
      final other = await open(otherCredential);
      final crossDevice = other.previewImport(backup(version: 1), 'overwrite');
      expect((await other.applyImport(crossDevice)).success, isTrue);
      expect(otherCredential.value, isNull);
      final explicit = other.previewImport(backup(version: 1), 'overwrite');
      expect(
        (await other.applyImport(explicit, importCredential: true)).success,
        isTrue,
      );
      expect(otherCredential.value, _sentinel);
      expect(other.exportJson(), isNot(contains(_sentinel)));
      other.dispose();
    },
  );

  test(
    'import write failure retains library and key, errors do not leak',
    () async {
      SharedPreferences.setMockInitialValues({});
      final credential = _MemoryCredential();
      final store = await open(credential);
      final originalBoard = store.boards.first.id;
      credential.failWrite = true;
      final plan = store.previewImport(backup(), 'overwrite');
      expect(
        (await store.applyImport(plan, importCredential: true)).success,
        isFalse,
      );
      expect(store.boards.first.id, originalBoard);
      expect(credential.value, isNull);
      expect(store.credentialError, isNot(contains(_sentinel)));
      credential.failWrite = false;
      expect(await store.retryCredential(), isTrue);
      expect(
        (await store.applyImport(plan, importCredential: true)).success,
        isTrue,
      );
      expect(credential.value, _sentinel);
      store.dispose();
    },
  );

  test('batch write failure rolls back explicit imported credential', () async {
    SharedPreferences.setMockInitialValues({});
    final credential = _MemoryCredential();
    var failBatch = false;
    final store = await open(
      credential,
      writer: (key, value) async {
        if (failBatch &&
            key.startsWith('matrixflow-save-') &&
            key != SaveProtocol.pointerKey) {
          return false;
        }
        return (await SharedPreferences.getInstance()).setString(key, value);
      },
    );
    expect(
      await store.updateAIConfig(AIConfig(apiKey: 'SYNTHETIC_LOCAL_INVALID')),
      isTrue,
    );
    expect((await store.flush()).success, isTrue);
    final originalBoard = store.boards.first.id;
    failBatch = true;
    final plan = store.previewImport(backup(), 'overwrite');
    expect(
      (await store.applyImport(plan, importCredential: true)).success,
      isFalse,
    );
    expect(store.boards.first.id, originalBoard);
    expect(credential.value, 'SYNTHETIC_LOCAL_INVALID');
    expect(store.credentialError, isNull);
    store.dispose();
  });

  test('failed rollback retains a retry that restores the old credential', () async {
    SharedPreferences.setMockInitialValues({});
    final credential = _MemoryCredential();
    var failBatch = false;
    final store = await open(
      credential,
      writer: (key, value) async {
        if (failBatch && key.startsWith('matrixflow-save-')) return false;
        return (await SharedPreferences.getInstance()).setString(key, value);
      },
    );
    final originalBoard = store.boards.first.id;
    final plan = store.previewImport(backup(), 'overwrite');
    failBatch = true;
    credential.failDelete = true;
    expect((await store.applyImport(plan, importCredential: true)).success, isFalse);
    expect(store.boards.first.id, originalBoard);
    expect(credential.value, _sentinel);
    expect(store.credentialError, isNotNull);
    credential.failDelete = false;
    expect(await store.retryCredential(), isTrue);
    expect(credential.value, isNull);
    expect(store.credentialError, isNull);
    store.dispose();
  });
}
