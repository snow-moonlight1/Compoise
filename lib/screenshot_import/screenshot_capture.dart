import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, listEquals;

import '../import_preview/draft_model.dart';
import '../ocr/ocr_runtime.dart';
import 'gutter_scan.dart';
import 'screenshot_adapter.dart';

typedef ScreenshotPicker = Future<List<PlatformFile>?> Function();
typedef ScreenshotRecognizer =
    Future<OcrImageResult> Function(
      String path,
      OcrCancellationToken cancellation,
    );
typedef ScreenshotMarkDecoder =
    Future<List<GutterMark>> Function(Uint8List png, int width, int height);

/// Limits apply to each capture, including images whose OCR subsequently fails.
/// Native OCR and Dart bitmap allocations are serialized across capture objects.
final class ScreenshotLimits {
  const ScreenshotLimits();
  static const maxImages = 10;
  static const maxFileBytes = 16 * 1024 * 1024;
  static const maxBatchBytes = 48 * 1024 * 1024;
  static const maxWidth = 4096;
  static const maxHeight = 8192;
  static const maxPixels = 12 * 1024 * 1024;
  static const maxBatchPixels = 24 * 1024 * 1024;
}

final class ScreenshotCaptureResult {
  const ScreenshotCaptureResult({
    this.batch,
    this.error,
    this.cancelled = false,
  });

  /// Editable I2 review state. No source paths, bitmap bytes or raw OCR retained.
  final DraftBatch? batch;

  /// Selection-level errors (oversized batch, picker unavailable, empty result).
  final String? error;
  final bool cancelled;
}

/// Standalone I3a entry point. I3b supplies navigation/boards and mounts
/// DraftPreview with [ScreenshotCaptureResult.batch]; this module never saves.
/// Desktop originals are read in place. I3b Android supplies bounded private
/// staging files and releases each one immediately after adaptation.
/// Cancel/dispose while the picker or native call is pending suppresses its
/// result. An active native call finishes before its memory can be reclaimed.
final class ScreenshotCapture {
  ScreenshotCapture({required OcrRuntime runtime, ScreenshotPicker? picker})
    : this.withRecognizer(
        recognize: (path, token) async =>
            (await runtime.recognizeFiles([path], cancellation: token)).single,
        picker: picker,
        modelAvailability: () => _checkModels(runtime.assetsRoot),
      );

  /// Injection seam: deterministic tests exercise the same capture and adapter.
  ScreenshotCapture.withRecognizer({
    required ScreenshotRecognizer recognize,
    ScreenshotPicker? picker,
    ScreenshotMarkDecoder? decodeMarks,
    Future<String?> Function()? modelAvailability,
  }) : _recognize = recognize,
       _picker = picker ?? pickScreenshotPngFiles,
       _decodeMarks = decodeMarks ?? _decodePngMarks,
       _modelAvailability = modelAvailability;

  final ScreenshotRecognizer _recognize;
  final ScreenshotPicker _picker;
  final ScreenshotMarkDecoder _decodeMarks;
  final Future<String?> Function()? _modelAvailability;
  OcrCancellationToken? _active;
  bool _busy = false;
  bool _disposed = false;
  int _generation = 0;
  static Future<void> _tail = Future<void>.value();

  void cancel() {
    _generation++;
    _active?.cancel();
  }

  void dispose() {
    _disposed = true;
    cancel();
  }

  Future<ScreenshotCaptureResult> pickAndCapture({
    void Function(int done, int total)? onProgress,
  }) => _start(null, null, null, null, onProgress);

  Future<ScreenshotCaptureResult> captureFiles(
    List<PlatformFile> files, {
    OcrCancellationToken? cancellation,
  }) => _start(List<PlatformFile>.of(files), cancellation);

  /// Load Android SAF files one at a time, retaining only memory draft data.
  Future<ScreenshotCaptureResult> captureSources(
    int count, {
    required Future<PlatformFile> Function(int) load,
    required Future<void> Function(int) release,
    void Function(int done, int total)? onProgress,
  }) {
    if (count < 1 || count > ScreenshotLimits.maxImages) {
      return Future.value(
        const ScreenshotCaptureResult(
          error: 'Select at most 10 PNG screenshots.',
        ),
      );
    }
    return _start(
      List.generate(count, (_) => PlatformFile(name: 'pending.png', size: 0)),
      null,
      load,
      release,
      onProgress,
    );
  }

  Future<ScreenshotCaptureResult> _start(
    List<PlatformFile>? files,
    OcrCancellationToken? cancellation, [
    Future<PlatformFile> Function(int)? load,
    Future<void> Function(int)? release,
    void Function(int, int)? onProgress,
  ]) async {
    if (_disposed) return const ScreenshotCaptureResult(cancelled: true);
    if (_busy) {
      return const ScreenshotCaptureResult(
        error: 'Screenshot capture is already running.',
      );
    }
    _busy = true;
    final generation = _generation;
    final token = cancellation ?? OcrCancellationToken();
    _active = token;
    try {
      if (files == null) {
        try {
          files = await _picker();
        } on _CaptureFailure catch (e) {
          if (_stale(generation)) {
            return const ScreenshotCaptureResult(cancelled: true);
          }
          return ScreenshotCaptureResult(error: e.message);
        } catch (_) {
          if (_stale(generation)) {
            return const ScreenshotCaptureResult(cancelled: true);
          }
          return const ScreenshotCaptureResult(
            error: 'Screenshot file selection failed.',
          );
        }
      }
      if (_stale(generation) || files == null) {
        return const ScreenshotCaptureResult(cancelled: true);
      }
      if (files.isEmpty) {
        return const ScreenshotCaptureResult(error: 'No screenshots selected.');
      }
      if (files.length > ScreenshotLimits.maxImages) {
        return const ScreenshotCaptureResult(
          error: 'Select at most 10 PNG screenshots.',
        );
      }
      final selected = List<PlatformFile>.of(files);
      final scheduled = _tail.then(
        (_) => _capture(selected, token, generation, load, release, onProgress),
      );
      _tail = scheduled.then<void>(
        (_) {},
        onError: (Object _, StackTrace __) {},
      );
      return await scheduled;
    } finally {
      _active = null;
      _busy = false;
    }
  }

  bool _stale(int generation) => _disposed || generation != _generation;

  Future<ScreenshotCaptureResult> _capture(
    List<PlatformFile> files,
    OcrCancellationToken token,
    int generation,
    Future<PlatformFile> Function(int)? load,
    Future<void> Function(int)? release,
    void Function(int, int)? onProgress,
  ) async {
    var bytesBudget = 0;
    var pixelsBudget = 0;
    final images = <Map<String, dynamic>>[];
    // Retention is capped by maxBatchBytes; exact equality gives hints only.
    // Both this list and all OCR/bitmap intermediates die with this invocation.
    final originalBytes = <String, Uint8List>{};
    for (final (index, selected) in files.indexed) {
      final id = 'image-${index + 1}';
      Map<String, dynamic> failure(String message) => {
        'id': id,
        'error': message,
      };
      if (_stale(generation)) {
        return const ScreenshotCaptureResult(cancelled: true);
      }
      if (token.isCancelled) {
        images.add(failure('Screenshot OCR cancelled.'));
        continue;
      }
      try {
        final input = load == null ? selected : await load(index);
        if (_stale(generation)) {
          return const ScreenshotCaptureResult(cancelled: true);
        }
        final path = input.path;
        if (!input.name.toLowerCase().endsWith('.png') ||
            (path != null && !path.toLowerCase().endsWith('.png'))) {
          images.add(
            failure(
              'Unsupported format: only PNG is accepted; no conversion is performed.',
            ),
          );
          continue;
        }
        if (path == null || path.isEmpty) {
          images.add(failure('Selected screenshot has no readable file path.'));
          continue;
        }
        try {
          final stat = await File(path).stat();
          if (stat.type != FileSystemEntityType.file) {
            throw const _CaptureFailure('Screenshot file is unavailable.');
          }
          if (stat.size <= 0 || stat.size > ScreenshotLimits.maxFileBytes) {
            throw const _CaptureFailure(
              'PNG must be nonempty and at most 16 MiB.',
            );
          }
          if (bytesBudget + stat.size > ScreenshotLimits.maxBatchBytes) {
            throw const _CaptureFailure(
              'Screenshot batch exceeds the 48 MiB file budget.',
            );
          }
          bytesBudget += stat.size;
          final handle = await File(path).open();
          late Uint8List png;
          late int width;
          late int height;
          try {
            final header = await handle.read(33);
            final size = _pngDimensions(header);
            width = size.$1;
            height = size.$2;
            if (pixelsBudget + width * height >
                ScreenshotLimits.maxBatchPixels) {
              throw const _CaptureFailure(
                'Screenshot batch exceeds the 24 Mi-pixel decode budget.',
              );
            }
            pixelsBudget += width * height;
            await handle.setPosition(0);
            // A growing or replaced source cannot trigger an unbounded read.
            png = await handle.read(stat.size + 1);
            if (png.length != stat.size) {
              throw const _CaptureFailure(
                'Screenshot changed while reading; select it again.',
              );
            }
            _validatePngChunks(png);
          } finally {
            await handle.close();
          }
          if (_stale(generation)) {
            return const ScreenshotCaptureResult(cancelled: true);
          }
          if (token.isCancelled) {
            images.add(failure('Screenshot OCR cancelled.'));
            continue;
          }
          final modelError = await _modelAvailability?.call();
          if (modelError != null) throw _CaptureFailure(modelError);
          if (_stale(generation)) {
            return const ScreenshotCaptureResult(cancelled: true);
          }
          if (token.isCancelled) {
            images.add(failure('Screenshot OCR cancelled.'));
            continue;
          }
          final marks = await _decodeMarks(png, width, height);
          if (_stale(generation)) {
            return const ScreenshotCaptureResult(cancelled: true);
          }
          if (token.isCancelled) {
            images.add(failure('Screenshot OCR cancelled.'));
            continue;
          }
          final raw = await _recognize(path, token);
          if (_stale(generation)) {
            return const ScreenshotCaptureResult(cancelled: true);
          }
          if (token.isCancelled) {
            images.add(failure('Screenshot OCR cancelled.'));
            continue;
          }
          if (raw.error != null) throw _CaptureFailure(_ocrFailure(raw.error!));
          final afterOcr = await File(path).stat();
          if (afterOcr.size != stat.size ||
              afterOcr.modified != stat.modified) {
            throw const _CaptureFailure(
              'Screenshot changed during OCR; select it again.',
            );
          }
          if (raw.width != width || raw.height != height) {
            throw const _CaptureFailure(
              'OCR dimensions differ from the selected PNG; select it again.',
            );
          }
          final wire = const ScreenshotDraftAdapter().adapt(
            id: id,
            result: raw,
            marks: marks,
          );
          images.add(wire);
          originalBytes[id] = png;
        } on _CaptureFailure catch (e) {
          images.add(failure(e.message));
        } on FileSystemException {
          images.add(failure('Screenshot file could not be read.'));
        } on FormatException {
          images.add(failure('Invalid PNG, image evidence or OCR result.'));
        } catch (_) {
          // Neither native errors nor exceptions containing paths/text reach logs.
          images.add(
            failure(
              'Screenshot decoding or OCR failed; no tasks were produced.',
            ),
          );
        }
      } on ScreenshotInputFailure catch (e) {
        images.add(failure(e.message));
      } catch (_) {
        images.add(failure('Screenshot file could not be read.'));
      } finally {
        // Propagate cleanup failure: a draft must not conceal retained sources.
        await release?.call(index);
        onProgress?.call(index + 1, files.length);
      }
    }
    if (_stale(generation)) {
      return const ScreenshotCaptureResult(cancelled: true);
    }
    final duplicates = _duplicates(images, originalBytes);
    return ScreenshotCaptureResult(
      batch: DraftBatch.fromJson({
        'schema': 'wp17r2-draft/1',
        'images': images,
        'duplicates': duplicates,
      }),
    );
  }
}

final class ScreenshotInputFailure implements Exception {
  const ScreenshotInputFailure(this.message);
  final String message;
}

final class _CaptureFailure implements Exception {
  const _CaptureFailure(this.message);
  final String message;
}

/// The locked Android picker copies unbounded input to disk and logs URIs
/// before returning to Dart (even withData=false). Do not invoke it until that
/// privacy/resource gate is resolved. Other unvalidated mobile platforms also
/// fail explicitly. A future approved picker can use the injected seam.
Future<List<PlatformFile>?> pickScreenshotPngFiles({
  TargetPlatform? platform,
}) async {
  final target = platform ?? defaultTargetPlatform;
  if (target == TargetPlatform.android) {
    throw const _CaptureFailure(
      'Screenshot selection is unavailable on this platform: the current mobile picker caches originals and logs URIs. Privacy and resource gates remain open.',
    );
  }
  if (target != TargetPlatform.windows && target != TargetPlatform.linux) {
    throw const _CaptureFailure(
      'Screenshot OCR is unavailable or unverified on this platform.',
    );
  }
  return (await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['png'],
    allowMultiple: true,
    allowCompression: false,
    withData: false,
    withReadStream: false,
  ))?.files;
}

(int, int) _pngDimensions(Uint8List bytes) {
  const signature = [137, 80, 78, 71, 13, 10, 26, 10];
  if (bytes.length < 33 || !listEquals(bytes.sublist(0, 8), signature)) {
    throw const _CaptureFailure(
      'Invalid PNG signature/header; other formats are unsupported.',
    );
  }
  final data = ByteData.sublistView(bytes);
  if (data.getUint32(8) != 13 || data.getUint32(12) != 0x49484452) {
    throw const _CaptureFailure('Invalid PNG IHDR header.');
  }
  final w = data.getUint32(16);
  final h = data.getUint32(20);
  if (w <= 0 ||
      h <= 0 ||
      w > ScreenshotLimits.maxWidth ||
      h > ScreenshotLimits.maxHeight ||
      w * h > ScreenshotLimits.maxPixels) {
    throw const _CaptureFailure(
      'PNG dimensions exceed 4096×8192 or 12 Mi-pixels.',
    );
  }
  return (w, h);
}

void _validatePngChunks(Uint8List png) {
  final data = ByteData.sublistView(png);
  var offset = 8;
  var chunks = 0;
  var hasData = false;
  while (offset + 12 <= png.length && chunks++ < 10000) {
    final length = data.getUint32(offset);
    final tag = data.getUint32(offset + 4);
    if (offset + length + 12 > png.length) break;
    if (tag == 0x6163544c) {
      throw const _CaptureFailure(
        'Animated PNG is unsupported; select a static PNG.',
      );
    }
    if (tag == 0x49444154) hasData = true;
    offset += length + 12;
    if (tag == 0x49454e44 && length == 0 && hasData && offset == png.length) {
      return;
    }
  }
  throw const _CaptureFailure('Invalid or excessively fragmented PNG.');
}

Future<List<GutterMark>> _decodePngMarks(
  Uint8List png,
  int width,
  int height,
) async {
  final codec = await ui.instantiateImageCodec(png);
  try {
    if (codec.frameCount != 1) throw const FormatException('animated bitmap');
    final frame = await codec.getNextFrame();
    var disposed = false;
    try {
      if (frame.image.width != width || frame.image.height != height) {
        throw const FormatException('bitmap size mismatch');
      }
      final pixels = await frame.image.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      );
      if (pixels == null) throw const FormatException('bitmap unavailable');
      final transfer = TransferableTypedData.fromList([
        pixels.buffer.asUint8List(pixels.offsetInBytes, pixels.lengthInBytes),
      ]);
      // Dispose the original image before scanning; the codec is disposed
      // before returning, so native OCR never overlaps this decoded bitmap.
      frame.image.dispose();
      disposed = true;
      return await Isolate.run(
        () => scanGutter(transfer.materialize().asUint8List(), width, height),
      );
    } finally {
      if (!disposed) frame.image.dispose();
    }
  } finally {
    codec.dispose();
  }
}

const _missingModels =
    'OCR model files are missing or unreadable. Screenshot OCR is not formally available.';
Future<String?> _checkModels(String root) async {
  const names = [
    'ppocrv5_dict.txt',
    'PP_OCRv5_mobile_det.ncnn.param',
    'PP_OCRv5_mobile_det.ncnn.bin',
    'PP_OCRv5_mobile_rec.ncnn.param',
    'PP_OCRv5_mobile_rec.ncnn.bin',
  ];
  for (final name in names) {
    try {
      final file = File('$root/ncnn/$name');
      final handle = await file.open();
      try {
        if ((await handle.read(1)).isEmpty) return _missingModels;
      } finally {
        await handle.close();
      }
    } on FileSystemException {
      return _missingModels;
    }
  }
  return null;
}

String _ocrFailure(String error) {
  if (error.contains('cannot read dict') ||
      error.contains('dict too small') ||
      error.contains('cannot load det model') ||
      error.contains('cannot load rec model')) {
    return _missingModels;
  }
  if (error == 'cancelled') return 'Screenshot OCR cancelled.';
  if (error.contains('native OCR unavailable')) {
    return 'Native OCR runtime is unavailable. Screenshot OCR is not formally available.';
  }
  return 'OCR failed for this screenshot; no tasks were produced.';
}

List<Map<String, dynamic>> _duplicates(
  List<Map<String, dynamic>> images,
  Map<String, Uint8List> bytes,
) {
  final successful = images.where((image) => image['error'] == null).toList();
  final ignored = RegExp(
    r'[\s\x00-\x1f\x7f-\x9f\u200b-\u200f\u202a-\u202e\u2060-\u206f\ufeff]',
  );
  Set<int> titles(Map<String, dynamic> image) =>
      (image['tasks'] as List<Map<String, dynamic>>)
          .map((task) => task['title'] as String)
          .join()
          .toLowerCase()
          .replaceAll(ignored, '')
          .runes
          .map((r) => r >= 0xff01 && r <= 0xff5e ? r - 0xfee0 : r)
          .toSet();
  final titleSets = successful.map(titles).toList();
  final hints = <Map<String, dynamic>>[];
  for (var i = 0; i < successful.length; i++) {
    for (var j = i + 1; j < successful.length; j++) {
      final a = successful[i];
      final b = successful[j];
      String? reason;
      if (listEquals(bytes[a['id']], bytes[b['id']])) {
        reason = 'identical-bytes';
      } else {
        final sa = titleSets[i];
        final sb = titleSets[j];
        if (sa.isNotEmpty && sb.isNotEmpty) {
          final similarity = sa.intersection(sb).length / sa.union(sb).length;
          if (similarity >= .9) {
            reason = 'char-jaccard=${similarity.toStringAsFixed(3)}';
          }
        }
      }
      if (reason != null) {
        hints.add({
          'images': [a['id'], b['id']],
          'reason': reason,
          'hint_only': true,
        });
      }
    }
  }
  return hints;
}
