import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';

import 'screenshot_capture.dart';

/// Android URIs never leave the native bridge. Only private staged paths are
/// passed to the existing path-based OCR runtime, and never to Store or logs.
final class ScreenshotSaf {
  ScreenshotSaf({MethodChannel? channel})
    : _channel =
          channel ?? const MethodChannel('com.matrixflow/screenshot_import');
  final MethodChannel _channel;
  String? _session;

  Future<void> initialize() => _channel.invokeMethod<void>('cleanup');
  Future<int?> pick() async {
    final reply = await _channel.invokeMapMethod<String, dynamic>('pick');
    if (reply == null) return null;
    if (reply['error'] != null) {
      throw ScreenshotInputFailure(reply['error'] as String);
    }
    _session = reply['session'] as String;
    return reply['count'] as int;
  }

  Future<PlatformFile> load(int index) async {
    final reply = await _channel.invokeMapMethod<String, dynamic>('stage', {
      'session': _session,
      'index': index,
    });
    if (reply == null || reply['error'] != null) {
      throw ScreenshotInputFailure(
        reply?['error'] as String? ?? 'screenshotImportSafRead',
      );
    }
    return PlatformFile(
      name: 'image-$index.png',
      size: reply['bytes'] as int,
      path: reply['path'] as String,
    );
  }

  Future<void> release(int index) => _channel.invokeMethod<void>('release', {
    'session': _session,
    'index': index,
  });

  Future<void> cancelSelection() => _channel.invokeMethod<void>('cancelPick');
  Future<void> close() async {
    final session = _session;
    if (session != null) {
      await _channel.invokeMethod<void>('close', {'session': session});
    }
    _session = null;
  }
}
