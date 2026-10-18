import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class CaptureRequest {
  const CaptureRequest(this.action, {this.text = ''});
  final String action;
  final String text;
}

/// A native share is queued until the current draft and onboarding are settled.
class QuickCapture extends ChangeNotifier {
  static final instance = QuickCapture();
  static const channel = MethodChannel('compoise/quick_capture');
  final Queue<CaptureRequest> _pending = Queue();
  bool _installed = false;
  Future<void> _tail = Future.value();

  CaptureRequest? get next => _pending.firstOrNull;
  void acknowledge(CaptureRequest request) {
    if (identical(next, request)) _pending.removeFirst();
  }

  void enqueue(CaptureRequest request) {
    _pending.add(request);
    notifyListeners();
  }

  Future<void> install() async {
    if (_installed || defaultTargetPlatform != TargetPlatform.android) return;
    _installed = true;
    channel.setMethodCallHandler((call) async {
      if (call.method == 'pendingChanged') await _readNative();
    });
    await _readNative();
  }

  Future<void> _readNative() {
    final next = _tail.then((_) async {
      try {
        final entries = await channel.invokeListMethod<dynamic>('takePending');
        for (final raw in entries ?? const []) {
          if (raw is Map && ['add', 'today', 'share'].contains(raw['action'])) {
            enqueue(
              CaptureRequest(
                raw['action'] as String,
                text: raw['text'] is String ? raw['text'] as String : '',
              ),
            );
          }
        }
      } on MissingPluginException {
        /* Widget tests have no Android host. */
      }
    });
    _tail = next.catchError((Object _) {});
    return _tail;
  }
}
