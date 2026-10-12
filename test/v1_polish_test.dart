import 'dart:ui' show Rect;

import 'package:compoise/l10n.dart';
import 'package:compoise/models.dart';
import 'package:compoise/services/window_geometry.dart';
import 'package:compoise/storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _CountingCredential implements CredentialStore {
  String? value = 'k-synthetic';
  int reads = 0;
  @override
  Future<String?> read() async {
    reads++;
    return value;
  }

  @override
  Future<void> write(String value) async => this.value = value;
  @override
  Future<void> delete() async => value = null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => Store.deferCredentialLoad = false);

  group('keyring at startup', () {
    test('deferred: startup does not touch the keyring', () async {
      Store.deferCredentialLoad = true;
      final cred = _CountingCredential();
      final store = Store(credentialStore: cred);
      await store.init();
      expect(cred.reads, 0);
      expect(store.ready, isTrue);
      expect(store.credentialLoaded, isFalse);
      expect(store.aiConfig.apiKey, '');
      await Future.wait([
        store.ensureCredentialLoaded(),
        store.ensureCredentialLoaded(),
      ]);
      expect(cred.reads, 1);
      expect(store.credentialLoaded, isTrue);
      expect(store.aiConfig.apiKey, 'k-synthetic');
      await store.ensureCredentialLoaded();
      expect(cred.reads, 1);
    });

    test('deferred: a failing keyring degrades to unavailable', () async {
      Store.deferCredentialLoad = true;
      final store = Store(credentialStore: _ThrowingCredential());
      await store.init();
      await store.ensureCredentialLoaded();
      expect(store.credentialUnavailable, isTrue);
      expect(store.ready, isTrue);
    });

    test('not deferred (other platforms): read during startup', () async {
      Store.deferCredentialLoad = false;
      final cred = _CountingCredential();
      final store = Store(credentialStore: cred);
      await store.init();
      expect(cred.reads, 1);
      expect(store.credentialLoaded, isTrue);
      expect(store.aiConfig.apiKey, 'k-synthetic');
    });
  });

  group('window bounds', () {
    const screen = Rect.fromLTWH(0, 0, 1920, 1080);
    test('round trip and rejects junk', () {
      const r = Rect.fromLTWH(10, 20, 1200, 800);
      expect(decodeWindowBounds(encodeWindowBounds(r)), r);
      expect(decodeWindowBounds('nope'), isNull);
      expect(decodeWindowBounds(null), isNull);
      expect(
        decodeWindowBounds(
          encodeWindowBounds(const Rect.fromLTWH(0, 0, 10, 10)),
        ),
        isNull,
      );
    });
    test('on-screen position is kept', () {
      final r = resolveWindowBounds(const Rect.fromLTWH(100, 100, 1200, 800), [
        screen,
      ]);
      expect(r.bounds, const Rect.fromLTWH(100, 100, 1200, 800));
    });
    test('off-screen (unplugged monitor) falls back to centered size', () {
      final r = resolveWindowBounds(const Rect.fromLTWH(2500, 100, 1200, 800), [
        screen,
      ]);
      expect(r.bounds, isNull);
      expect(r.width, 1200);
      expect(r.height, 800);
    });
    test('second monitor position is kept', () {
      final r = resolveWindowBounds(const Rect.fromLTWH(2500, 100, 1200, 800), [
        screen,
        const Rect.fromLTWH(1920, 0, 2560, 1440),
      ]);
      expect(r.bounds, isNotNull);
    });
    test('oversized window is clamped to the screen', () {
      final r = resolveWindowBounds(const Rect.fromLTWH(0, 0, 4000, 3000), [
        screen,
      ]);
      expect(r.width, 1920);
      expect(r.height, 1080);
    });
  });

  group('default board name follows language', () {
    test('default board relabels, renamed board keeps its name', () async {
      SharedPreferences.setMockInitialValues({
        'compoise-settings': '{"language":"en"}',
      });
      final store = Store(credentialStore: _CountingCredential());
      await store.init();
      expect(store.boards.single.name, dictOf(Language.en)['defaultBoardName']);
      store.updateSettings((s) => s..language = Language.zh);
      expect(store.boards.single.name, dictOf(Language.zh)['defaultBoardName']);
      store.updateSettings((s) => s..language = Language.ja);
      expect(store.boards.single.name, dictOf(Language.ja)['defaultBoardName']);

      store.boards.single.name = 'Work';
      store.updateSettings((s) => s..language = Language.en);
      expect(store.boards.single.name, 'Work');
    });
  });

  test('screenshot hint uses plain words in every language', () {
    for (final lang in Language.values) {
      final d = dictOf(lang);
      for (final key in [
        'screenshotImportHint',
        'ocrModelDownloadPrompt',
        'screenshotImportNativeMissing',
        'screenshotImportModelsMissing',
        'screenshotImportCleanupFailed',
      ]) {
        final text = d[key]!;
        for (final word in [
          'Experimental',
          'OCR',
          'MiB',
          '实验',
          '実験',
          '临时副本',
          '待完成',
          '未完了',
          'pending',
        ]) {
          expect(text.contains(word), isFalse, reason: '$lang $key: $word');
        }
      }
    }
  });
}

class _ThrowingCredential implements CredentialStore {
  @override
  Future<String?> read() async => throw StateError('locked');
  @override
  Future<void> write(String value) async => throw StateError('locked');
  @override
  Future<void> delete() async => throw StateError('locked');
}
