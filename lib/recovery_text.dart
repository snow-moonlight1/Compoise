import 'dart:typed_data';

/// SHA-256 of [bytes], lowercase hex. Recovery chunks use this for the archive
/// id and for the prefix that must already be present before a chunk is applied.
String recoverySha256Hex(List<int> bytes) {
  final digest = _sha256(bytes);
  final out = StringBuffer();
  for (final byte in digest) {
    out.write(byte.toRadixString(16).padLeft(2, '0'));
  }
  return out.toString();
}

/// UTF-8 length of [text] after JSON string escaping, without the surrounding
/// quotes. This is the size a backup file actually pays for the field.
int jsonStringUtf8Length(String text) {
  final units = text.codeUnits;
  var bytes = 0;
  for (var i = 0; i < units.length; i++) {
    bytes += _escapedBytes(units, i);
    i += _unitWidth(units, i) - 1;
  }
  return bytes;
}

/// Splits [text] so each piece's JSON-escaped UTF-8 size is at most [budget].
/// Pieces join back to [text] and never cut a surrogate pair.
List<String> sliceJsonText(String text, int budget) {
  if (budget < 6) {
    throw ArgumentError.value(budget, 'budget');
  }
  final units = text.codeUnits;
  final parts = <String>[];
  var start = 0;
  var bytes = 0;
  for (var i = 0; i < units.length; i++) {
    final size = _escapedBytes(units, i);
    final width = _unitWidth(units, i);
    if (bytes > 0 && bytes + size > budget) {
      parts.add(String.fromCharCodes(units.sublist(start, i)));
      start = i;
      bytes = 0;
    }
    bytes += size;
    i += width - 1;
  }
  if (start < units.length) {
    parts.add(String.fromCharCodes(units.sublist(start)));
  }
  return parts;
}

int _unitWidth(List<int> units, int index) {
  final unit = units[index];
  if (unit >= 0xD800 && unit <= 0xDBFF && index + 1 < units.length) {
    final next = units[index + 1];
    if (next >= 0xDC00 && next <= 0xDFFF) return 2;
  }
  return 1;
}

int _escapedBytes(List<int> units, int index) {
  if (_unitWidth(units, index) == 2) return 4;
  final unit = units[index];
  if (unit < 0x20) {
    if (unit == 0x08 ||
        unit == 0x09 ||
        unit == 0x0A ||
        unit == 0x0C ||
        unit == 0x0D) {
      return 2;
    }
    return 6;
  }
  if (unit == 0x22 || unit == 0x5C) return 2;
  if (unit < 0x80) return 1;
  if (unit < 0x800) return 2;
  return 3;
}

int _rotr(int value, int bits) {
  final x = value & 0xffffffff;
  return ((x >> bits) | (x << (32 - bits))) & 0xffffffff;
}

int _shr(int value, int bits) => (value & 0xffffffff) >> bits;

Uint8List _sha256(List<int> message) {
  var h0 = 0x6a09e667;
  var h1 = 0xbb67ae85;
  var h2 = 0x3c6ef372;
  var h3 = 0xa54ff53a;
  var h4 = 0x510e527f;
  var h5 = 0x9b05688c;
  var h6 = 0x1f83d9ab;
  var h7 = 0x5be0cd19;

  final bitLength = message.length * 8;
  var paddedLength = message.length + 1 + 8;
  final remainder = paddedLength % 64;
  if (remainder != 0) paddedLength += 64 - remainder;
  final padded = Uint8List(paddedLength);
  padded.setRange(0, message.length, message);
  padded[message.length] = 0x80;
  var length = bitLength;
  for (var i = 0; i < 8; i++) {
    padded[paddedLength - 1 - i] = length & 0xff;
    length >>= 8;
  }

  final words = List<int>.filled(64, 0);
  for (var offset = 0; offset < padded.length; offset += 64) {
    for (var i = 0; i < 16; i++) {
      final at = offset + i * 4;
      words[i] =
          (padded[at] << 24) |
          (padded[at + 1] << 16) |
          (padded[at + 2] << 8) |
          padded[at + 3];
    }
    for (var i = 16; i < 64; i++) {
      final s0 =
          _rotr(words[i - 15], 7) ^
          _rotr(words[i - 15], 18) ^
          _shr(words[i - 15], 3);
      final s1 =
          _rotr(words[i - 2], 17) ^
          _rotr(words[i - 2], 19) ^
          _shr(words[i - 2], 10);
      words[i] = (words[i - 16] + s0 + words[i - 7] + s1) & 0xffffffff;
    }
    var a = h0;
    var b = h1;
    var c = h2;
    var d = h3;
    var e = h4;
    var f = h5;
    var g = h6;
    var h = h7;
    for (var i = 0; i < 64; i++) {
      final s1 = _rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25);
      final ch = (e & f) ^ (~e & 0xffffffff & g);
      final temp1 = (h + s1 + ch + _sha256K[i] + words[i]) & 0xffffffff;
      final s0 = _rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22);
      final maj = (a & b) ^ (a & c) ^ (b & c);
      final temp2 = (s0 + maj) & 0xffffffff;
      h = g;
      g = f;
      f = e;
      e = (d + temp1) & 0xffffffff;
      d = c;
      c = b;
      b = a;
      a = (temp1 + temp2) & 0xffffffff;
    }
    h0 = (h0 + a) & 0xffffffff;
    h1 = (h1 + b) & 0xffffffff;
    h2 = (h2 + c) & 0xffffffff;
    h3 = (h3 + d) & 0xffffffff;
    h4 = (h4 + e) & 0xffffffff;
    h5 = (h5 + f) & 0xffffffff;
    h6 = (h6 + g) & 0xffffffff;
    h7 = (h7 + h) & 0xffffffff;
  }

  final digest = Uint8List(32);
  final state = [h0, h1, h2, h3, h4, h5, h6, h7];
  for (var i = 0; i < state.length; i++) {
    digest[i * 4] = (state[i] >> 24) & 0xff;
    digest[i * 4 + 1] = (state[i] >> 16) & 0xff;
    digest[i * 4 + 2] = (state[i] >> 8) & 0xff;
    digest[i * 4 + 3] = state[i] & 0xff;
  }
  return digest;
}

const _sha256K = <int>[
  0x428a2f98,
  0x71374491,
  0xb5c0fbcf,
  0xe9b5dba5,
  0x3956c25b,
  0x59f111f1,
  0x923f82a4,
  0xab1c5ed5,
  0xd807aa98,
  0x12835b01,
  0x243185be,
  0x550c7dc3,
  0x72be5d74,
  0x80deb1fe,
  0x9bdc06a7,
  0xc19bf174,
  0xe49b69c1,
  0xefbe4786,
  0x0fc19dc6,
  0x240ca1cc,
  0x2de92c6f,
  0x4a7484aa,
  0x5cb0a9dc,
  0x76f988da,
  0x983e5152,
  0xa831c66d,
  0xb00327c8,
  0xbf597fc7,
  0xc6e00bf3,
  0xd5a79147,
  0x06ca6351,
  0x14292967,
  0x27b70a85,
  0x2e1b2138,
  0x4d2c6dfc,
  0x53380d13,
  0x650a7354,
  0x766a0abb,
  0x81c2c92e,
  0x92722c85,
  0xa2bfe8a1,
  0xa81a664b,
  0xc24b8b70,
  0xc76c51a3,
  0xd192e819,
  0xd6990624,
  0xf40e3585,
  0x106aa070,
  0x19a4c116,
  0x1e376c08,
  0x2748774c,
  0x34b0bcb5,
  0x391c0cb3,
  0x4ed8aa4a,
  0x5b9cca4f,
  0x682e6ff3,
  0x748f82ee,
  0x78a5636f,
  0x84c87814,
  0x8cc70208,
  0x90befffa,
  0xa4506ceb,
  0xbef9a3f7,
  0xc67178f2,
];
