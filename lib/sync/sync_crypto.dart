/// Envelope format for files the sync engine writes to a remote folder.
///
/// ```
/// "CPS1" | version (1 byte) | mode (1 byte) | nonce (12 bytes, mode 1 only) | body
/// ```
///
/// Mode 0 is gzip only. Mode 1 is AES-256-GCM over the gzip bytes; the body
/// ends with the 16-byte tag, and the header plus the file name are the
/// associated data, so a file cannot be renamed or have its header edited
/// without failing authentication. Keys come from the sync password through
/// Argon2id with parameters stored in the vault file. Nothing here touches
/// the network or the disk; v1.5.0 encrypted backups reuse it.
library;

import 'dart:convert';
import 'dart:io' show GZipCodec;
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

const List<int> envelopeMagic = [0x43, 0x50, 0x53, 0x31]; // "CPS1"
const int envelopeVersion = 1;
const int envelopeModePlain = 0;
const int envelopeModeEncrypted = 1;

const int _nonceLength = 12;
const int _tagLength = 16;
const int keyLength = 32;

/// Upper bound for one decompressed file. Far above the 20k-task benchmark;
/// it only exists so a hostile file cannot inflate without limit.
const int maxEnvelopeContentBytes = 256 * 1024 * 1024;

enum SyncCryptoError {
  /// The file is encrypted and no key was given.
  needsKey,

  /// Authentication failed: wrong key, or the bytes were changed.
  wrongKeyOrTampered,

  /// Not an envelope, truncated, or the content does not decompress.
  corrupt,

  /// Written by a newer format version.
  unsupported,

  /// A plain file where the vault requires encryption.
  notEncrypted,
}

class SyncCryptoException implements Exception {
  const SyncCryptoException(this.kind, [this.message = '']);

  final SyncCryptoError kind;
  final String message;

  @override
  String toString() => 'SyncCryptoException(${kind.name}): $message';
}

/// Argon2id parameters stored next to the data they protect.
class KdfParams {
  const KdfParams({
    required this.salt,
    this.memoryKiB = defaultMemoryKiB,
    this.iterations = defaultIterations,
    this.parallelism = 1,
  });

  /// OWASP's minimum Argon2id profile (19 MiB, 2 passes, 1 lane).
  static const int defaultMemoryKiB = 19456;
  static const int defaultIterations = 2;

  final List<int> salt;
  final int memoryKiB;
  final int iterations;
  final int parallelism;

  factory KdfParams.random({Random? random}) {
    final source = random ?? Random.secure();
    return KdfParams(salt: List<int>.generate(16, (_) => source.nextInt(256)));
  }

  Map<String, dynamic> toJson() => {
    'name': 'argon2id',
    'memoryKiB': memoryKiB,
    'iterations': iterations,
    'parallelism': parallelism,
    'salt': base64Encode(salt),
  };

  /// Rejects parameters that are unusable or would let a hostile vault file
  /// stall the device; both bounds sit far from the defaults.
  static KdfParams fromJson(Object? json) {
    if (json is! Map || json['name'] != 'argon2id') {
      throw const SyncCryptoException(
        SyncCryptoError.unsupported,
        'Unknown key derivation',
      );
    }
    final memory = json['memoryKiB'];
    final iterations = json['iterations'];
    final parallelism = json['parallelism'];
    final salt = json['salt'];
    if (memory is! int ||
        iterations is! int ||
        parallelism is! int ||
        salt is! String ||
        memory < 8 * 1024 ||
        memory > 1024 * 1024 ||
        iterations < 1 ||
        iterations > 16 ||
        parallelism < 1 ||
        parallelism > 8) {
      throw const SyncCryptoException(
        SyncCryptoError.corrupt,
        'Invalid key derivation parameters',
      );
    }
    final List<int> saltBytes;
    try {
      saltBytes = base64Decode(salt);
    } on FormatException {
      throw const SyncCryptoException(SyncCryptoError.corrupt, 'Invalid salt');
    }
    if (saltBytes.length < 16 || saltBytes.length > 64) {
      throw const SyncCryptoException(SyncCryptoError.corrupt, 'Invalid salt');
    }
    return KdfParams(
      salt: saltBytes,
      memoryKiB: memory,
      iterations: iterations,
      parallelism: parallelism,
    );
  }
}

/// Derives the 32-byte vault key from [password]. Runs Argon2id on a
/// background isolate unless [inline] is set, because it takes a few hundred
/// milliseconds by design.
Future<Uint8List> deriveVaultKey(
  String password,
  KdfParams params, {
  bool inline = false,
}) {
  final salt = List<int>.of(params.salt);
  final memory = params.memoryKiB;
  final iterations = params.iterations;
  final parallelism = params.parallelism;
  Future<Uint8List> run() => _argon2id(
    password,
    salt,
    memory: memory,
    iterations: iterations,
    parallelism: parallelism,
  );
  return inline ? run() : Isolate.run(run);
}

Future<Uint8List> _argon2id(
  String password,
  List<int> salt, {
  required int memory,
  required int iterations,
  required int parallelism,
}) async {
  final algorithm = Argon2id(
    parallelism: parallelism,
    memory: memory,
    iterations: iterations,
    hashLength: keyLength,
  );
  final key = await algorithm.deriveKeyFromPassword(
    password: password,
    nonce: salt,
  );
  return Uint8List.fromList(await key.extractBytes());
}

final AesGcm _aes = AesGcm.with256bits();
final GZipCodec _gzip = GZipCodec(level: 6);

List<int> _aad(List<int> header, String name) => [
  ...header,
  ...utf8.encode(name),
];

/// Compresses [content] and, when [key] is given, encrypts it for the file
/// called [name].
Future<Uint8List> sealEnvelope(
  List<int> content, {
  required String name,
  List<int>? key,
  List<int>? nonce,
}) async {
  final compressed = _gzip.encode(content);
  if (key == null) {
    return Uint8List.fromList([
      ...envelopeMagic,
      envelopeVersion,
      envelopeModePlain,
      ...compressed,
    ]);
  }
  _checkKey(key);
  final iv = nonce ?? _aes.newNonce();
  if (iv.length != _nonceLength) throw ArgumentError('nonce');
  final header = [
    ...envelopeMagic,
    envelopeVersion,
    envelopeModeEncrypted,
    ...iv,
  ];
  final box = await _aes.encrypt(
    compressed,
    secretKey: SecretKey(List<int>.of(key)),
    nonce: iv,
    aad: _aad(header, name),
  );
  final out = BytesBuilder(copy: false)
    ..add(header)
    ..add(box.cipherText)
    ..add(box.mac.bytes);
  return out.takeBytes();
}

/// True when [bytes] start like an envelope of any mode.
bool looksLikeEnvelope(List<int> bytes) {
  if (bytes.length < envelopeMagic.length + 2) return false;
  for (var i = 0; i < envelopeMagic.length; i++) {
    if (bytes[i] != envelopeMagic[i]) return false;
  }
  return true;
}

bool isEncryptedEnvelope(List<int> bytes) =>
    looksLikeEnvelope(bytes) && bytes[5] == envelopeModeEncrypted;

/// Reverses [sealEnvelope]. With [requireEncryption], a plain file is refused
/// even though it could be read, so nobody with write access to the folder
/// can slip unencrypted content into an encrypted vault.
Future<Uint8List> openEnvelope(
  List<int> bytes, {
  required String name,
  List<int>? key,
  bool requireEncryption = false,
}) async {
  if (!looksLikeEnvelope(bytes)) {
    throw const SyncCryptoException(SyncCryptoError.corrupt, 'Not a sync file');
  }
  final version = bytes[4];
  final mode = bytes[5];
  if (version != envelopeVersion) {
    throw SyncCryptoException(
      version > envelopeVersion
          ? SyncCryptoError.unsupported
          : SyncCryptoError.corrupt,
      'Envelope version $version',
    );
  }
  final List<int> compressed;
  if (mode == envelopeModePlain) {
    if (requireEncryption) {
      throw const SyncCryptoException(SyncCryptoError.notEncrypted);
    }
    compressed = bytes.sublist(6);
  } else if (mode == envelopeModeEncrypted) {
    if (key == null) throw const SyncCryptoException(SyncCryptoError.needsKey);
    _checkKey(key);
    const headerLength = 6 + _nonceLength;
    if (bytes.length < headerLength + _tagLength) {
      throw const SyncCryptoException(SyncCryptoError.corrupt, 'Truncated');
    }
    final header = bytes.sublist(0, headerLength);
    final box = SecretBox(
      bytes.sublist(headerLength, bytes.length - _tagLength),
      nonce: bytes.sublist(6, headerLength),
      mac: Mac(bytes.sublist(bytes.length - _tagLength)),
    );
    try {
      compressed = await _aes.decrypt(
        box,
        secretKey: SecretKey(List<int>.of(key)),
        aad: _aad(header, name),
      );
    } on SecretBoxAuthenticationError {
      throw const SyncCryptoException(SyncCryptoError.wrongKeyOrTampered);
    }
  } else if (mode > envelopeModeEncrypted) {
    throw SyncCryptoException(SyncCryptoError.unsupported, 'Mode $mode');
  } else {
    throw SyncCryptoException(SyncCryptoError.corrupt, 'Mode $mode');
  }
  return inflateLimited(compressed, maxEnvelopeContentBytes);
}

/// Decompresses gzip [bytes], refusing output larger than [limit].
///
/// The decoder tolerates a missing trailer, so the CRC-32 and length stored
/// there are checked here: a plain file cut short by an interrupted upload
/// must not read as a complete one.
Uint8List inflateLimited(List<int> bytes, int limit) {
  const corrupt = SyncCryptoException(
    SyncCryptoError.corrupt,
    'Content does not decompress',
  );
  if (bytes.length < 18) throw corrupt;
  final sink = _LimitedSink(limit);
  try {
    final input = _gzip.decoder.startChunkedConversion(sink);
    input.add(bytes);
    input.close();
  } on SyncCryptoException {
    rethrow;
  } catch (_) {
    throw corrupt;
  }
  final out = sink.builder.takeBytes();
  final n = bytes.length;
  int le32(int at) =>
      bytes[at] |
      bytes[at + 1] << 8 |
      bytes[at + 2] << 16 |
      bytes[at + 3] << 24;
  if (le32(n - 4) != out.length & 0xffffffff || le32(n - 8) != crc32(out)) {
    throw corrupt;
  }
  return out;
}

final Uint32List _crcTable = () {
  final table = Uint32List(256);
  for (var i = 0; i < 256; i++) {
    var c = i;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    }
    table[i] = c;
  }
  return table;
}();

/// CRC-32 as used by gzip.
int crc32(List<int> bytes) {
  var crc = 0xffffffff;
  for (final byte in bytes) {
    crc = _crcTable[(crc ^ byte) & 0xff] ^ (crc >>> 8);
  }
  return crc ^ 0xffffffff;
}

class _LimitedSink implements Sink<List<int>> {
  _LimitedSink(this.limit);

  final int limit;
  final BytesBuilder builder = BytesBuilder(copy: true);

  @override
  void add(List<int> data) {
    if (builder.length + data.length > limit) {
      throw const SyncCryptoException(SyncCryptoError.corrupt, 'Too large');
    }
    builder.add(data);
  }

  @override
  void close() {}
}

void _checkKey(List<int> key) {
  if (key.length != keyLength) throw ArgumentError('key length');
}

/// Encrypted marker stored in the vault file. Opening it proves the password
/// before any data file is touched, which is how a wrong password is told
/// apart from a damaged or edited data file.
Future<String> sealKeyCheck(List<int> key, String vaultId) async {
  final sealed = await sealEnvelope(
    utf8.encode('compoise-vault:$vaultId'),
    name: 'vault-check',
    key: key,
  );
  return base64Encode(sealed);
}

/// True when [key] opens [check] for [vaultId].
Future<bool> verifyKeyCheck(List<int> key, String vaultId, String check) async {
  final List<int> bytes;
  try {
    bytes = base64Decode(check);
  } on FormatException {
    throw const SyncCryptoException(SyncCryptoError.corrupt, 'Invalid check');
  }
  try {
    final content = await openEnvelope(
      bytes,
      name: 'vault-check',
      key: key,
      requireEncryption: true,
    );
    return utf8.decode(content, allowMalformed: true) ==
        'compoise-vault:$vaultId';
  } on SyncCryptoException catch (error) {
    if (error.kind == SyncCryptoError.wrongKeyOrTampered) return false;
    rethrow;
  }
}
