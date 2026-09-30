import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:matrixflow_native/ocr/ocr_runtime.dart';

OcrLine line(
  String text,
  double x,
  double y, {
  double width = 100,
  double score = .99,
}) => OcrLine(text: text, box: [x, y, width, 20], score: score);

OcrImageResult result(
  String path,
  List<OcrLine> lines, {
  int width = 400,
  int height = 400,
  String? error,
}) => OcrImageResult(
  path: path,
  width: width,
  height: height,
  lines: lines,
  error: error,
);

Uint8List bitmap({bool dark = false}) {
  final bytes = Uint8List(400 * 400 * 4);
  for (var p = 0; p < bytes.length; p += 4) {
    bytes[p] = bytes[p + 1] = bytes[p + 2] = dark ? 20 : 255;
    bytes[p + 3] = 255;
  }
  void box(int left, int top, bool filled) {
    for (var y = top; y < top + 16; y++) {
      for (var x = left; x < left + 16; x++) {
        if (!filled &&
            x >= left + 2 &&
            x < left + 14 &&
            y >= top + 2 &&
            y < top + 14) {
          continue;
        }
        final p = (y * 400 + x) * 4;
        bytes[p] = bytes[p + 1] = bytes[p + 2] = dark ? 245 : 0;
      }
    }
  }

  box(12, 140, false);
  box(40, 200, true);
  return bytes;
}

Uint8List png({
  int width = 400,
  int height = 400,
  Uint8List? rgba,
  bool headerOnly = false,
  int padding = 0,
}) {
  final header = ByteData(13)
    ..setUint32(0, width)
    ..setUint32(4, height)
    ..setUint8(8, 8)
    ..setUint8(9, 6);
  final scanlines = BytesBuilder(copy: false);
  if (!headerOnly) {
    final pixels = rgba ?? bitmap();
    for (var y = 0; y < height; y++) {
      scanlines.addByte(0);
      scanlines.add(pixels.sublist(y * width * 4, (y + 1) * width * 4));
    }
  }
  return (BytesBuilder(copy: false)
        ..add(const [137, 80, 78, 71, 13, 10, 26, 10])
        ..add(chunk('IHDR', header.buffer.asUint8List()))
        ..add(chunk('IDAT', zlib.encode(scanlines.takeBytes())))
        ..add(padding == 0 ? const [] : chunk('tEXt', Uint8List(padding)))
        ..add(chunk('IEND', const [])))
      .takeBytes();
}

Uint8List chunk(String tag, List<int> bytes) {
  final content = Uint8List.fromList([...ascii.encode(tag), ...bytes]);
  var crc = 0xffffffff;
  for (final byte in content) {
    crc ^= byte;
    for (var i = 0; i < 8; i++) {
      crc = (crc >> 1) ^ ((crc & 1) == 0 ? 0 : 0xedb88320);
    }
  }
  final size = ByteData(4)..setUint32(0, bytes.length);
  final checksum = ByteData(4)..setUint32(0, (crc ^ 0xffffffff) & 0xffffffff);
  return (BytesBuilder(copy: false)
        ..add(size.buffer.asUint8List())
        ..add(content)
        ..add(checksum.buffer.asUint8List()))
      .takeBytes();
}

PlatformFile picked(File file, {int? declaredSize}) => PlatformFile(
  name: file.uri.pathSegments.last,
  size: declaredSize ?? file.lengthSync(),
  path: file.path,
);
