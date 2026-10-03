import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../ocr/ocr_assets.dart';
import '../ocr/ocr_runtime.dart';
import 'screenshot_capture.dart';
import 'screenshot_saf.dart';

abstract interface class ScreenshotBackend {
  /// Returns a localized-key suffix; null permits selection.
  Future<String?> availability();
  Future<ScreenshotCaptureResult> capture(void Function(int, int) progress);
  void cancel();
  Future<void> dispose();
}

/// Read-only platform environment, injectable so the resolution order can be
/// asserted without a real process environment.
typedef OcrEnvironment = Map<String, String> Function();

/// Application support directory provider, injectable so the fallback entry of
/// the resolution order can be asserted without a platform channel.
typedef OcrSupportDirectory = Future<Directory> Function();
typedef OcrBundledDirectory = Future<String?> Function();

/// Asset root used when the caller supplies no [OcrRuntime].
///
/// Order: `WP17_OCR_ASSETS` environment variable (desktop development and
/// unmanaged deployments), then the compile-time `--dart-define`
/// `WP17_OCR_ASSETS`, then optional APK/bundle assets, then application support.
/// All entries are
/// local paths; nothing is downloaded and no path outside the requested root is
/// searched.
Future<String> resolveOcrAssetsRoot({
  OcrEnvironment environment = _platformEnvironment,
  OcrSupportDirectory? supportDirectory,
  OcrBundledDirectory bundledDirectory = bundledOcrAssetsRoot,
}) async {
  final fromEnvironment = environment()['WP17_OCR_ASSETS']?.trim();
  if (fromEnvironment != null && fromEnvironment.isNotEmpty) {
    return fromEnvironment;
  }
  const fromDefine = String.fromEnvironment('WP17_OCR_ASSETS');
  if (fromDefine.isNotEmpty) return fromDefine;
  final bundled = await bundledDirectory();
  if (bundled != null && bundled.isNotEmpty) return bundled;
  final support = await (supportDirectory ?? getApplicationSupportDirectory)();
  return '${support.path}/wp17r2-assets';
}

Map<String, String> _platformEnvironment() => Platform.environment;

final class LocalScreenshotBackend implements ScreenshotBackend {
  LocalScreenshotBackend({
    OcrRuntime? runtime,
    ScreenshotCapture? capture,
    ScreenshotSaf? saf,
    Future<String?> Function()? availability,
    bool? android,
    OcrEnvironment environment = _platformEnvironment,
  }) : _runtime = runtime,
       _capture = capture,
       _saf = saf,
       _availability = availability,
       _android = android ?? Platform.isAndroid,
       _environment = environment;

  OcrRuntime? _runtime;
  ScreenshotCapture? _capture;
  ScreenshotSaf? _saf;
  final Future<String?> Function()? _availability;
  final bool _android;
  final OcrEnvironment _environment;
  Future<ScreenshotCaptureResult>? _running;
  bool _disposed = false;
  int _generation = 0;

  @override
  Future<String?> availability() async {
    try {
      if (_android) {
        _saf ??= ScreenshotSaf();
        try {
          await _saf!.close();
          await _saf!.initialize();
        } catch (_) {
          return 'CleanupFailed';
        }
      }
      if (_availability != null) return await _availability();
      if (!_android && !Platform.isWindows && !Platform.isLinux) {
        return 'Unavailable';
      }
      _runtime ??= OcrRuntime(
        assetsRoot: await resolveOcrAssetsRoot(environment: _environment),
      );
      final missing = await missingOcrModelFiles(_runtime!.assetsRoot);
      if (missing.isNotEmpty) return 'ModelsMissing';
      try {
        final library = DynamicLibrary.open(
          _runtime!.libraryPath ?? resolveOcrLibraryPath(),
        );
        for (final name in [
          'mf_ocr_create',
          'mf_ocr_run_file',
          'mf_ocr_destroy',
          'mf_ocr_free',
        ]) {
          library.lookup<NativeFunction<Void Function()>>(name);
        }
      } catch (_) {
        return 'NativeMissing';
      }
      _capture ??= ScreenshotCapture(runtime: _runtime!);
      return null;
    } catch (_) {
      return 'Unavailable';
    }
  }

  @override
  Future<ScreenshotCaptureResult> capture(void Function(int, int) progress) {
    if (_disposed || _running != null) {
      return Future.value(const ScreenshotCaptureResult(cancelled: true));
    }
    final pending = _run(progress);
    _running = pending;
    return pending.whenComplete(() => _running = null);
  }

  Future<ScreenshotCaptureResult> _run(void Function(int, int) progress) async {
    final generation = _generation;
    // Repeat before picker: models may have disappeared since the page opened.
    final error = await availability();
    if (_disposed || generation != _generation) {
      return const ScreenshotCaptureResult(cancelled: true);
    }
    if (error != null) {
      return ScreenshotCaptureResult(error: 'screenshotImport$error');
    }
    try {
      if (!_android) {
        return await _capture!.pickAndCapture(onProgress: progress);
      }
      final count = await _saf!.pick();
      if (_disposed || generation != _generation || count == null) {
        return const ScreenshotCaptureResult(cancelled: true);
      }
      return await _capture!.captureSources(
        count,
        load: _saf!.load,
        release: _saf!.release,
        onProgress: progress,
      );
    } on ScreenshotInputFailure catch (e) {
      return ScreenshotCaptureResult(error: e.message);
    } catch (_) {
      return const ScreenshotCaptureResult(error: 'screenshotImportReadFailed');
    } finally {
      // Close happens after active native work completes, even after cancel.
      await _saf?.close();
    }
  }

  @override
  void cancel() {
    _generation++;
    _capture?.cancel();
    // Only dismiss selection here; deleting a path while OCR runs is avoided.
    unawaited(
      _saf?.cancelSelection().catchError((Object _) {}) ?? Future.value(),
    );
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    cancel();
    try {
      await _running;
    } catch (_) {
      /* caller reports cleanup failure */
    }
    await _saf?.close();
    _capture?.dispose();
  }
}
