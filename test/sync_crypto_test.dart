import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:typed_data';

import 'package:compoise/sync/sync_crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

List<int> _hex(String hex) => [
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
];

String _toHex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Matcher _fails(SyncCryptoError kind) =>
    throwsA(isA<SyncCryptoException>().having((e) => e.kind, 'kind', kind));

void main() {
  final key = Uint8List.fromList(List<int>.generate(32, (i) => i));
  final otherKey = Uint8List.fromList(List<int>.generate(32, (i) => 255 - i));
  final content = utf8.encode('{"task":"买牛奶 — buy milk"}');

  group('known answers', () {
    // Reference values from libargon2 (argon2-cffi hash_secret_raw, type ID).
    test('Argon2id with the default profile', () async {
      final params = KdfParams(salt: List<int>.generate(16, (i) => i));
      final derived = await deriveVaultKey(
        'correct horse battery staple',
        params,
        inline: true,
      );
      expect(
        _toHex(derived),
        '818259b6310026a8e0dbac5d2e6927abcfdb07b32258fac4f61b18b80f929085',
      );
    });

    test('Argon2id runs on a background isolate', () async {
      // The smallest memory the vault format accepts is 8 MiB; the reference
      // value below uses 64 KiB, so call the algorithm directly for it.
      final algorithm = Argon2id(
        parallelism: 1,
        memory: 64,
        iterations: 2,
        hashLength: 32,
      );
      final secret = await algorithm.deriveKeyFromPassword(
        password: 'password',
        nonce: utf8.encode('somesalt'),
      );
      expect(
        _toHex(await secret.extractBytes()),
        '16a1a498734609dd01456da406de9f3d9da93e6c86c300a12fc1465214ce4922',
      );
      final params = KdfParams(salt: List<int>.filled(16, 7));
      final onIsolate = await deriveVaultKey('pw', params);
      final inline = await deriveVaultKey('pw', params, inline: true);
      expect(onIsolate, inline);
    });

    test('AES-256-GCM (GCM spec test case 16)', () async {
      final box = await AesGcm.with256bits().encrypt(
        _hex(
          'd9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a72'
          '1c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b39',
        ),
        secretKey: SecretKey(
          _hex(
            'feffe9928665731c6d6a8f9467308308feffe9928665731c6d6a8f9467308308',
          ),
        ),
        nonce: _hex('cafebabefacedbaddecaf888'),
        aad: _hex('feedfacedeadbeeffeedfacedeadbeefabaddad2'),
      );
      expect(
        _toHex(box.cipherText),
        '522dc1f099567d07f47f37a32a84427d643a8cdcbfe5c0c97598a2bd2555d1aa'
        '8cb08e48590dbb3da7b08b1056828838c5f61e6393ba7a0abcc9f662',
      );
      expect(_toHex(box.mac.bytes), '76fc6ece0f4e1768cddf8853bb2d551b');
    });
  });

  group('envelope', () {
    test('round-trips plain and encrypted', () async {
      final plain = await sealEnvelope(content, name: 'dev-a.cps');
      expect(isEncryptedEnvelope(plain), isFalse);
      expect(await openEnvelope(plain, name: 'dev-a.cps'), content);

      final sealed = await sealEnvelope(content, name: 'dev-a.cps', key: key);
      expect(isEncryptedEnvelope(sealed), isTrue);
      expect(await openEnvelope(sealed, name: 'dev-a.cps', key: key), content);
      expect(
        utf8.decode(sealed, allowMalformed: true),
        isNot(contains('milk')),
      );
    });

    test('nonces are fresh for every file', () async {
      final a = await sealEnvelope(content, name: 'n', key: key);
      final b = await sealEnvelope(content, name: 'n', key: key);
      expect(a.sublist(6, 18), isNot(b.sublist(6, 18)));
    });

    test(
      'tells a missing key, a wrong key and tampering apart from damage',
      () async {
        final sealed = await sealEnvelope(content, name: 'f', key: key);
        await expectLater(
          openEnvelope(sealed, name: 'f'),
          _fails(SyncCryptoError.needsKey),
        );
        await expectLater(
          openEnvelope(sealed, name: 'f', key: otherKey),
          _fails(SyncCryptoError.wrongKeyOrTampered),
        );
        final flipped = Uint8List.fromList(sealed)..[sealed.length - 20] ^= 1;
        await expectLater(
          openEnvelope(flipped, name: 'f', key: key),
          _fails(SyncCryptoError.wrongKeyOrTampered),
        );
        final header = Uint8List.fromList(sealed)..[8] ^= 1;
        await expectLater(
          openEnvelope(header, name: 'f', key: key),
          _fails(SyncCryptoError.wrongKeyOrTampered),
        );
        await expectLater(
          openEnvelope(sealed, name: 'renamed', key: key),
          _fails(SyncCryptoError.wrongKeyOrTampered),
          reason: 'the file name is authenticated',
        );
        await expectLater(
          openEnvelope(sealed.sublist(0, 20), name: 'f', key: key),
          _fails(SyncCryptoError.corrupt),
        );
        await expectLater(
          openEnvelope(utf8.encode('{"not":"envelope"}'), name: 'f', key: key),
          _fails(SyncCryptoError.corrupt),
        );
        final plain = await sealEnvelope(content, name: 'f');
        for (final cut in [1, 4, 8, 12]) {
          await expectLater(
            openEnvelope(plain.sublist(0, plain.length - cut), name: 'f'),
            _fails(SyncCryptoError.corrupt),
            reason: 'cut $cut bytes',
          );
        }
        final bitRot = Uint8List.fromList(plain)..[plain.length - 12] ^= 0x01;
        await expectLater(
          openEnvelope(bitRot, name: 'f'),
          _fails(SyncCryptoError.corrupt),
        );
      },
    );

    test('crc32 matches the gzip reference value', () {
      expect(crc32(utf8.encode('123456789')), 0xcbf43926);
    });

    test('an encrypted vault refuses plain files', () async {
      final plain = await sealEnvelope(content, name: 'f');
      await expectLater(
        openEnvelope(plain, name: 'f', key: key, requireEncryption: true),
        _fails(SyncCryptoError.notEncrypted),
      );
    });

    test('newer versions and modes are reported as unsupported', () async {
      final sealed = await sealEnvelope(content, name: 'f');
      final newer = Uint8List.fromList(sealed)..[4] = 2;
      await expectLater(
        openEnvelope(newer, name: 'f'),
        _fails(SyncCryptoError.unsupported),
      );
      final mode = Uint8List.fromList(sealed)..[5] = 9;
      await expectLater(
        openEnvelope(mode, name: 'f'),
        _fails(SyncCryptoError.unsupported),
      );
    });

    test('decompression is bounded', () {
      final bomb = gzip.encode(Uint8List(4 * 1024 * 1024));
      expect(
        () => inflateLimited(bomb, 1024 * 1024),
        _fails(SyncCryptoError.corrupt),
      );
      expect(inflateLimited(bomb, 8 * 1024 * 1024).length, 4 * 1024 * 1024);
    });
  });

  group('key check and parameters', () {
    test('verifies the password before any data file is read', () async {
      final check = await sealKeyCheck(key, 'vault123');
      expect(await verifyKeyCheck(key, 'vault123', check), isTrue);
      expect(await verifyKeyCheck(otherKey, 'vault123', check), isFalse);
      expect(await verifyKeyCheck(key, 'vault999', check), isFalse);
      await expectLater(
        verifyKeyCheck(key, 'vault123', 'not base64!'),
        _fails(SyncCryptoError.corrupt),
      );
    });

    test('rejects parameters that are unknown or out of bounds', () {
      final ok = KdfParams.random();
      expect(ok.salt, hasLength(16));
      final json = ok.toJson();
      expect(KdfParams.fromJson(json).memoryKiB, KdfParams.defaultMemoryKiB);
      expect(
        () => KdfParams.fromJson({...json, 'name': 'scrypt'}),
        _fails(SyncCryptoError.unsupported),
      );
      expect(
        () => KdfParams.fromJson({...json, 'memoryKiB': 1 << 30}),
        _fails(SyncCryptoError.corrupt),
      );
      expect(
        () => KdfParams.fromJson({...json, 'iterations': 0}),
        _fails(SyncCryptoError.corrupt),
      );
      expect(
        () => KdfParams.fromJson({
          ...json,
          'salt': base64Encode([1, 2]),
        }),
        _fails(SyncCryptoError.corrupt),
      );
    });
  });
}
