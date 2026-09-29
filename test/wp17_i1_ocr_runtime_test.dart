import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/ocr/ocr_runtime.dart';

void main() {
  test('cancelled batch retains one result per input without opening native code', () async {
    final token = OcrCancellationToken()..cancel();
    final results = await OcrRuntime(assetsRoot: 'unused').recognizeFiles(
      ['a.png', 'b.png'],
      cancellation: token,
    );
    expect(results.map((result) => result.path), ['a.png', 'b.png']);
    expect(results.every((result) => result.error == 'cancelled'), isTrue);
  });

  test('rejects batch larger than the bounded decode queue', () async {
    final runtime = OcrRuntime(assetsRoot: 'unused');
    await expectLater(runtime.recognizeFiles(List.filled(21, 'a.png')), throwsArgumentError);
  });

  final libraryPath = Platform.environment['WP17_OCR_TEST_LIBRARY'];
  final assetsRoot = Platform.environment['WP17_OCR_TEST_ASSETS'];
  final enabled = libraryPath != null && assetsRoot != null;

  test('native library returns a per-image error for unreadable PNG', () async {
    final result = (await OcrRuntime(
      assetsRoot: assetsRoot!,
      libraryPath: libraryPath!,
    ).recognizeFiles(['missing-wp17-i1.png'])).single;
    expect(result.succeeded, isFalse);
    expect(result.lines, isEmpty);
    expect(result.error, contains('cannot open image'));
  }, skip: !enabled);

  test('native call reproduces R2 text and boxes on synthetic screenshots', () async {
    final root = Directory.current.path;
    final samples = '$root/docs/evidence/wp17r2/samples/images';
    final raw = jsonDecode(File(
      '$root/docs/evidence/wp17r2/results/win/raw/ncnn-cpu-t4/all.json',
    ).readAsStringSync()) as Map<String, dynamic>;
    final reference = {
      for (final image in raw['images'] as List<dynamic>)
        File((image as Map<String, dynamic>)['path'] as String).uri.pathSegments.last:
            image,
    };
    final paths = [
      for (final name in reference.keys) '$samples/$name',
    ];
    final results = await OcrRuntime(
      assetsRoot: assetsRoot!,
      libraryPath: libraryPath!,
    ).recognizeFiles(paths);
    expect(results.length, paths.length);
    for (final result in results) {
      expect(result.error, isNull, reason: result.path);
      final expected = reference[File(result.path).uri.pathSegments.last]
          as Map<String, dynamic>;
      final lines = expected['lines'] as List<dynamic>;
      expect(result.width, expected['width']);
      expect(result.height, expected['height']);
      expect(result.lines.length, lines.length);
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i] as Map<String, dynamic>;
        expect(result.lines[i].text, line['text']);
        final box = line['box'] as List<dynamic>;
        for (var j = 0; j < 4; j++) {
          expect(result.lines[i].box[j], closeTo((box[j] as num).toDouble(), 1));
        }
      }
    }
  }, skip: !enabled, timeout: const Timeout(Duration(minutes: 5)));

  test('native library reports model, decode, size and repeated-call results', () async {
    final runtime = OcrRuntime(assetsRoot: assetsRoot!, libraryPath: libraryPath!);
    final temp = await Directory.systemTemp.createTemp('wp17i1-');
    try {
      final missingModel = (await OcrRuntime(
        assetsRoot: temp.path,
        libraryPath: libraryPath,
      ).recognizeFiles([_touch(temp, 'missing.png', [1, 2, 3])])).single;
      expect(missingModel.error, contains('cannot read dict'));
      expect(missingModel.width, 0);
      expect(missingModel.lines, isEmpty);

      final corrupt = (await runtime.recognizeFiles([
        _touch(temp, 'corrupt.png', utf8.encode('not a png')),
      ])).single;
      expect(corrupt.error, 'PNG header decode failed');

      final empty = (await runtime.recognizeFiles([
        _touch(temp, 'empty.png', const []),
      ])).single;
      expect(empty.error, contains('16 MiB or is empty'));

      final wide = (await runtime.recognizeFiles([
        _touch(temp, 'wide.png', _png(4097, 8)),
      ])).single;
      expect(wide.error, 'image dimensions exceed OCR limit');
      expect(wide.width, 0);

      final sample = '${Directory.current.path}/docs/evidence/wp17r2/samples/images/zh_light_base.png';
      final first = (await runtime.recognizeFiles([sample])).single;
      final second = (await runtime.recognizeFiles([sample])).single;
      expect(first.error, isNull);
      expect(second.width, first.width);
      expect(second.height, first.height);
      expect(second.lines.map((line) => line.text), first.lines.map((line) => line.text));

      final token = OcrCancellationToken();
      final pending = runtime.recognizeFiles([
        sample,
        '${Directory.current.path}/docs/evidence/wp17r2/samples/images/en_light_base.png',
      ], cancellation: token);
      token.cancel();
      final cancelled = await pending;
      expect(cancelled, hasLength(2));
      expect(cancelled.last.error, 'cancelled');
    } finally {
      await temp.delete(recursive: true);
    }
  }, skip: !enabled, timeout: const Timeout(Duration(minutes: 3)));
}

String _touch(Directory dir, String name, List<int> bytes) {
  final file = File('${dir.path}${Platform.pathSeparator}$name');
  file.writeAsBytesSync(bytes, flush: true);
  return file.path;
}

Uint8List _png(int width, int height) {
  final raw = BytesBuilder(copy: false);
  for (var y = 0; y < height; y++) {
    raw.addByte(0);
    for (var x = 0; x < width; x++) {
      raw.add(const [255, 255, 255]);
    }
  }
  final compressed = zlib.encode(raw.takeBytes());
  final out = BytesBuilder(copy: false);
  out.add(const [137, 80, 78, 71, 13, 10, 26, 10]);
  out.add(_chunk('IHDR', _pngHeader(width, height)));
  out.add(_chunk('IDAT', compressed));
  out.add(_chunk('IEND', const []));
  return out.toBytes();
}

Uint8List _pngHeader(int width, int height) {
  final data = ByteData(13);
  data.setUint32(0, width);
  data.setUint32(4, height);
  data.setUint8(8, 8);
  data.setUint8(9, 2);
  return data.buffer.asUint8List();
}

Uint8List _chunk(String tag, List<int> data) {
  final tagBytes = ascii.encode(tag);
  final length = Uint8List(4);
  ByteData.sublistView(length).setUint32(0, data.length);
  final crcInput = Uint8List(tagBytes.length + data.length);
  crcInput.setRange(0, tagBytes.length, tagBytes);
  crcInput.setRange(tagBytes.length, crcInput.length, data);
  final crcBytes = Uint8List(4);
  ByteData.sublistView(crcBytes).setUint32(0, _crc32(crcInput));
  final out = BytesBuilder(copy: false);
  out.add(length);
  out.add(tagBytes);
  out.add(data);
  out.add(crcBytes);
  return out.toBytes();
}

int _crc32(List<int> data) {
  var crc = 0xFFFFFFFF;
  for (final byte in data) {
    crc ^= byte;
    for (var bit = 0; bit < 8; bit++) {
      final mask = -(crc & 1);
      crc = (crc >> 1) ^ (0xEDB88320 & mask);
    }
  }
  return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}
