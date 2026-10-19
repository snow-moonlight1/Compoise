/// Hybrid logical clock used to order field edits across devices.
///
/// A clock value packs wall-clock milliseconds and a logical counter into one
/// integer: `ms * 1024 + counter`. It stays below 2^53 until the year 2248, so
/// it survives a JSON round trip on every platform. Each device observes the
/// largest clock it has merged, so an edit made after seeing another device's
/// change always sorts after it, even when the two wall clocks disagree.
library;

const int clockCounterSpan = 1024;

/// Largest clock value the sync files accept (2^53 - 1).
const int maxSyncClock = 9007199254740991;

class HybridClock {
  HybridClock({int last = 0, int Function()? nowMs})
    : _last = last,
      _nowMs = nowMs ?? _wallMs;

  int _last;
  final int Function() _nowMs;

  static int _wallMs() => DateTime.now().millisecondsSinceEpoch;

  /// The largest clock this device has issued or observed.
  int get last => _last;

  /// Issues a clock that is larger than every clock seen so far.
  int tick() {
    final wall = _nowMs() * clockCounterSpan;
    _last = wall > _last ? wall : _last + 1;
    if (_last > maxSyncClock) {
      throw StateError('Sync clock overflow');
    }
    return _last;
  }

  /// Records a clock received from another device.
  void observe(int remote) {
    if (remote > _last && remote <= maxSyncClock) _last = remote;
  }

  /// Wall-clock milliseconds encoded in [clock].
  static int millisecondsOf(int clock) => clock ~/ clockCounterSpan;
}

/// True when [value] is a clock the sync files may contain.
bool isValidClock(Object? value) =>
    value is int && value >= 0 && value <= maxSyncClock;
