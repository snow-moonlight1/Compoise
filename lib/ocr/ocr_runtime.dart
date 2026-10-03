import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

/// A raw OCR line. [box] is x, y, width, height in source image pixels.
final class OcrLine {
  const OcrLine({required this.text, required this.box, required this.score});

  final String text;
  final List<double> box;
  final double score;

  factory OcrLine.fromJson(Map<String, dynamic> json) => OcrLine(
    text: json['text'] as String,
    box: (json['box'] as List<dynamic>)
        .map((value) => (value as num).toDouble())
        .toList(growable: false),
    score: (json['score'] as num).toDouble(),
  );
}

/// One image's raw result. No task parsing or database write occurs here.
final class OcrImageResult {
  const OcrImageResult({
    required this.path,
    required this.width,
    required this.height,
    required this.lines,
    this.error,
  });

  final String path;
  final int width;
  final int height;
  final List<OcrLine> lines;
  final String? error;

  bool get succeeded => error == null;

  factory OcrImageResult.fromJson(String path, Map<String, dynamic> json) {
    final rawError = json['error'] as String?;
    return OcrImageResult(
      path: path,
      width: json['width'] as int,
      height: json['height'] as int,
      lines: (json['lines'] as List<dynamic>)
          .map((line) => OcrLine.fromJson(line as Map<String, dynamic>))
          .toList(growable: false),
      error: rawError == null || rawError.isEmpty ? null : rawError,
    );
  }
}

/// Cancellation takes effect before the next image. An active native call is
/// allowed to finish so the ncnn extractor and decoded bitmap are released.
final class OcrCancellationToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

typedef _CreateNative = Pointer<Void> Function(Pointer<Utf8>, Int32);
typedef _CreateDart = Pointer<Void> Function(Pointer<Utf8>, int);
typedef _RunNative = Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>);
typedef _RunDart = Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>);
typedef _DestroyNative = Void Function(Pointer<Void>);
typedef _DestroyDart = void Function(Pointer<Void>);
typedef _FreeNative = Void Function(Pointer<Utf8>);
typedef _FreeDart = void Function(Pointer<Utf8>);

/// Offline ncnn CPU bridge. The caller supplies verified model files in
/// [assetsRoot]/ncnn. Optional builds can stage the reviewed official weights;
/// the default build still has no OCR models or native component.
///
/// Every image executes in a background isolate. Calls across all instances
/// are serialized to avoid overlapping 400+ MiB model/bitmap allocations.
final class OcrRuntime {
  OcrRuntime({required this.assetsRoot, this.libraryPath, this.threads = 4}) {
    if (threads < 1 || threads > 4) {
      throw ArgumentError.value(threads, 'threads', 'must be in 1..4');
    }
  }

  final String assetsRoot;
  final String? libraryPath;
  final int threads;

  static Future<void> _tail = Future<void>.value();

  static Future<T> _oneAtATime<T>(Future<T> Function() work) {
    final scheduled = _tail.then((_) => work());
    _tail = scheduled.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return scheduled;
  }

  /// At most 20 PNG paths are accepted in one batch. Each path gets a result,
  /// including failures and images skipped after cancellation, in input order.
  Future<List<OcrImageResult>> recognizeFiles(
    List<String> imagePaths, {
    OcrCancellationToken? cancellation,
  }) async {
    if (imagePaths.length > 20) {
      throw ArgumentError.value(imagePaths.length, 'imagePaths', 'maximum 20');
    }
    final results = <OcrImageResult>[];
    for (final path in imagePaths) {
      if (cancellation?.isCancelled ?? false) {
        results.add(_failure(path, 'cancelled'));
        continue;
      }
      final result = await _oneAtATime(() async {
        if (cancellation?.isCancelled ?? false) {
          return _failure(path, 'cancelled');
        }
        try {
          return await Isolate.run(
            () => _recognizeOne(path, assetsRoot, libraryPath, threads),
          );
        } catch (error) {
          return _failure(path, 'native OCR unavailable: $error');
        }
      });
      results.add(result);
    }
    return List<OcrImageResult>.unmodifiable(results);
  }
}

OcrImageResult _failure(String path, String error) => OcrImageResult(
  path: path,
  width: 0,
  height: 0,
  lines: const [],
  error: error,
);

/// Library location for the current platform. Windows and Linux load the copy
/// installed next to the executable (Linux from the bundle's [lib] directory),
/// Android resolves the packaged shared object by name.
String resolveOcrLibraryPath() {
  if (Platform.isAndroid) return 'libmatrixflow_ocr.so';
  final executable = File(Platform.resolvedExecutable).parent.path;
  if (Platform.isWindows) return '$executable\\matrixflow_ocr.dll';
  if (Platform.isLinux) return '$executable/lib/libmatrixflow_ocr.so';
  throw UnsupportedError('OCR is available only on Android, Windows and Linux');
}

OcrImageResult _recognizeOne(
  String path,
  String assetsRoot,
  String? libraryPath,
  int threads,
) {
  final library = DynamicLibrary.open(libraryPath ?? resolveOcrLibraryPath());
  final create = library.lookupFunction<_CreateNative, _CreateDart>(
    'mf_ocr_create',
  );
  final run = library.lookupFunction<_RunNative, _RunDart>('mf_ocr_run_file');
  final destroy = library.lookupFunction<_DestroyNative, _DestroyDart>(
    'mf_ocr_destroy',
  );
  final free = library.lookupFunction<_FreeNative, _FreeDart>('mf_ocr_free');
  final assetPtr = assetsRoot.toNativeUtf8();
  final pathPtr = path.toNativeUtf8();
  Pointer<Void> session = nullptr;
  try {
    session = create(assetPtr, threads);
    final output = run(session, pathPtr);
    if (output == nullptr) {
      return _failure(path, 'native result allocation failed');
    }
    try {
      return OcrImageResult.fromJson(
        path,
        jsonDecode(output.toDartString()) as Map<String, dynamic>,
      );
    } finally {
      free(output);
    }
  } finally {
    if (session != nullptr) destroy(session);
    calloc.free(assetPtr);
    calloc.free(pathPtr);
  }
}
