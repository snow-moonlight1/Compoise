import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'ocr_assets.dart';

/// One model file published under the `ocr-models-v1` tag of this repository.
class OcrModelFile {
  const OcrModelFile(this.name, this.bytes, this.sha256);
  final String name;
  final int bytes;
  final String sha256;
}

/// PP-OCRv5 mobile (Apache-2.0) converted to ncnn. The app ships the native
/// runtime only; these files are downloaded the first time screenshot import
/// is used and verified against the pinned SHA-256 before they are installed.
/// The same bytes are locked in native/ocr/tools/models.lock.json.
class OcrModels {
  static const version = 'v1';
  static const approxMegabytes = 11;

  static const files = <OcrModelFile>[
    OcrModelFile(
      'ppocrv5_dict.txt',
      74012,
      'd1979e9f794c464c0d2e0b70a7fe14dd978e9dc644c0e71f14158cdf8342af1b',
    ),
    OcrModelFile(
      'PP_OCRv5_mobile_det.ncnn.param',
      24256,
      '19359eea27e9f38b493a40ac11acbb95bbe6cbe174866e9e043cbe6a786f3ce6',
    ),
    OcrModelFile(
      'PP_OCRv5_mobile_det.ncnn.bin',
      2357216,
      '857a96bc963725105b78a178dfcc3c0c3db1a7b9eef32244367b2cb105ccf60b',
    ),
    OcrModelFile(
      'PP_OCRv5_mobile_rec.ncnn.param',
      19632,
      'dbd3a743febb5d08157059d4ae31f9372b413b9739ef9d5963da68c987a2481c',
    ),
    OcrModelFile(
      'PP_OCRv5_mobile_rec.ncnn.bin',
      8242276,
      '49d9907a55ba20fa6637f9f788f66ab00793bc8ce57a733a09dbe86b9a2e3db0',
    ),
  ];

  static int get totalBytes => files.fold(0, (sum, f) => sum + f.bytes);

  /// Mirrors of the same tagged files, tried in order. jsDelivr answers well
  /// from mainland China; the GitHub release and raw copies follow.
  static List<String> urlsFor(String name) => [
    'https://cdn.jsdelivr.net/gh/snow-moonlight1/Compoise@ocr-models-$version/ncnn/$name',
    'https://github.com/snow-moonlight1/Compoise/releases/download/ocr-models-$version/$name',
    'https://raw.githubusercontent.com/snow-moonlight1/Compoise/ocr-models-$version/ncnn/$name',
  ];

  /// Test seam. Production uses the application support folder.
  static Future<Directory> Function()? directoryOverride;

  /// Root passed to the native runtime; model files live in `<root>/ncnn`.
  static Future<String> root() async {
    final base = directoryOverride != null
        ? await directoryOverride!()
        : await getApplicationSupportDirectory();
    return '${base.path}/ocr-models/$version';
  }

  /// True when every file exists with the pinned size. Hashes are checked at
  /// download time; a size check keeps startup cheap.
  static Future<bool> isInstalled() async {
    try {
      final dir = await root();
      for (final f in files) {
        final file = File(ocrModelPath(dir, f.name));
        if (!file.existsSync() || file.lengthSync() != f.bytes) return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Downloads the missing files. [onProgress] gets 0..1 over all bytes.
  /// Each file is verified before it replaces anything; a failure leaves no
  /// partial file behind and throws [OcrModelDownloadException].
  static Future<void> download({
    http.Client? client,
    void Function(double progress)? onProgress,
  }) async {
    final ownClient = client == null;
    final httpClient = client ?? http.Client();
    try {
      final dir = Directory('${await root()}/ncnn');
      dir.createSync(recursive: true);
      var done = 0;
      final total = totalBytes;
      for (final f in files) {
        final dest = File(ocrModelPath(await root(), f.name));
        if (dest.existsSync() && dest.lengthSync() == f.bytes) {
          done += f.bytes;
          onProgress?.call(done / total);
          continue;
        }
        await _fetchOne(httpClient, f, dest, (received) {
          onProgress?.call((done + received) / total);
        });
        done += f.bytes;
        onProgress?.call(done / total);
      }
    } finally {
      if (ownClient) httpClient.close();
    }
  }

  static Future<void> _fetchOne(
    http.Client client,
    OcrModelFile f,
    File dest,
    void Function(int received) progress,
  ) async {
    Object? lastError;
    final part = File('${dest.path}.part');
    for (final url in urlsFor(f.name)) {
      try {
        if (part.existsSync()) part.deleteSync();
        final request = http.Request('GET', Uri.parse(url));
        request.headers['User-Agent'] = 'Compoise';
        final response = await client
            .send(request)
            .timeout(const Duration(seconds: 30));
        if (response.statusCode != 200) {
          lastError = 'HTTP ${response.statusCode}';
          await response.stream.drain<void>();
          continue;
        }
        final sink = part.openWrite();
        var received = 0;
        try {
          await for (final chunk in response.stream.timeout(
            const Duration(seconds: 60),
          )) {
            received += chunk.length;
            if (received > f.bytes) throw StateError('too large');
            sink.add(chunk);
            progress(received);
          }
        } finally {
          await sink.close();
        }
        final digest = sha256.convert(part.readAsBytesSync()).toString();
        if (received != f.bytes || digest != f.sha256) {
          lastError = 'checksum mismatch';
          part.deleteSync();
          continue;
        }
        if (dest.existsSync()) dest.deleteSync();
        part.renameSync(dest.path);
        return;
      } catch (error) {
        lastError = error;
        try {
          if (part.existsSync()) part.deleteSync();
        } catch (_) {}
      }
    }
    throw OcrModelDownloadException('${f.name}: $lastError');
  }
}

class OcrModelDownloadException implements Exception {
  OcrModelDownloadException(this.message);
  final String message;
  @override
  String toString() => message;
}
