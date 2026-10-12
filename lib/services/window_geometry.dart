import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:ui' show Offset, Rect, Size;

import 'package:flutter/foundation.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

const windowBoundsKey = 'compoise-window-bounds';

/// Smallest window the restore will accept; anything smaller is ignored.
const double _minWidth = 360;
const double _minHeight = 480;

/// How much of the window's title strip must sit on a display for the saved
/// position to be reused. Otherwise the window is centered with its saved size.
const double _visibleTitle = 48;

String encodeWindowBounds(Rect r) =>
    jsonEncode({'x': r.left, 'y': r.top, 'w': r.width, 'h': r.height});

Rect? decodeWindowBounds(String? raw) {
  if (raw == null) return null;
  try {
    final m = jsonDecode(raw) as Map<String, dynamic>;
    final r = Rect.fromLTWH(
      (m['x'] as num).toDouble(),
      (m['y'] as num).toDouble(),
      (m['w'] as num).toDouble(),
      (m['h'] as num).toDouble(),
    );
    if (!r.isFinite || r.width < _minWidth || r.height < _minHeight) {
      return null;
    }
    return r;
  } catch (_) {
    return null;
  }
}

/// What to do with saved bounds given the current displays' visible areas.
/// Returns the saved rect when its title strip is reachable on some display,
/// a size-only result (position null) when it would be off screen, and the
/// size is clamped to the largest display so it never exceeds the screen.
({Rect? bounds, double width, double height}) resolveWindowBounds(
  Rect saved,
  List<Rect> displays,
) {
  if (displays.isEmpty) {
    return (bounds: null, width: saved.width, height: saved.height);
  }
  var maxW = 0.0, maxH = 0.0;
  for (final d in displays) {
    if (d.width > maxW) maxW = d.width;
    if (d.height > maxH) maxH = d.height;
  }
  final w = saved.width.clamp(_minWidth, maxW < _minWidth ? _minWidth : maxW);
  final h = saved.height.clamp(
    _minHeight,
    maxH < _minHeight ? _minHeight : maxH,
  );
  final title = Rect.fromLTWH(saved.left, saved.top, w, _visibleTitle);
  for (final d in displays) {
    final hit = d.intersect(title);
    if (hit.width >= 120 && hit.height >= _visibleTitle / 2) {
      return (
        bounds: Rect.fromLTWH(saved.left, saved.top, w, h),
        width: w,
        height: h,
      );
    }
  }
  return (bounds: null, width: w, height: h);
}

bool get _isDesktop =>
    !kIsWeb &&
    (Platform.isWindows || Platform.isLinux || Platform.isMacOS) &&
    !Platform.environment.containsKey('FLUTTER_TEST');

/// Restores the last window size and position, then keeps them saved.
class WindowGeometry with WindowListener {
  WindowGeometry._();
  static final instance = WindowGeometry._();

  Timer? _debounce;
  bool _started = false;

  Future<void> start() async {
    if (!_isDesktop || _started) return;
    _started = true;
    try {
      await windowManager.ensureInitialized();
      final prefs = await SharedPreferences.getInstance();
      final saved = decodeWindowBounds(prefs.getString(windowBoundsKey));
      if (saved != null) {
        final displays = await screenRetriever.getAllDisplays();
        final areas = [
          for (final d in displays)
            Rect.fromLTWH(
              (d.visiblePosition ?? Offset.zero).dx,
              (d.visiblePosition ?? Offset.zero).dy,
              (d.visibleSize ?? d.size).width,
              (d.visibleSize ?? d.size).height,
            ),
        ];
        final r = resolveWindowBounds(saved, areas);
        if (r.bounds != null) {
          await windowManager.setBounds(r.bounds!);
        } else {
          await windowManager.setSize(Size(r.width, r.height));
          await windowManager.center();
        }
      }
      windowManager.addListener(this);
    } catch (_) {
      // Geometry is a convenience; never block startup on it.
    }
  }

  void _scheduleSave() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), save);
  }

  Future<void> save() async {
    try {
      if (await windowManager.isMaximized() ||
          await windowManager.isMinimized() ||
          await windowManager.isFullScreen()) {
        return;
      }
      final b = await windowManager.getBounds();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(windowBoundsKey, encodeWindowBounds(b));
    } catch (_) {}
  }

  // Linux reports only the live resize/move events; Windows and macOS also
  // send the "-d" end events. Both are debounced into one save.
  @override
  void onWindowResize() => _scheduleSave();
  @override
  void onWindowMove() => _scheduleSave();
  @override
  void onWindowResized() => _scheduleSave();
  @override
  void onWindowMoved() => _scheduleSave();
  @override
  void onWindowClose() => save();
}
