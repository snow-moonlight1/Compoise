import 'dart:async';

import 'package:flutter/widgets.dart';

import 'device_time_zone.dart';

/// Holds the zone the schedule surfaces display in.
///
/// The device zone is re-read when the app resumes and when the platform
/// reports a change; the result only ever feeds the view, so refreshing can
/// never rewrite a stored record. A user choice made while the device zone is
/// unknown (or to look at another zone) stays until it is cleared.
class DeviceTimeZoneController extends ChangeNotifier
    with WidgetsBindingObserver {
  DeviceTimeZoneController({
    DeviceTimeZoneSource? source,
    Stream<void>? changeEvents,
    bool observeLifecycle = true,
    bool listenPlatformChanges = true,
  }) : _source = source ?? defaultDeviceTimeZoneSource(),
       _observeLifecycle = observeLifecycle {
    if (_observeLifecycle) WidgetsBinding.instance.addObserver(this);
    final events =
        changeEvents ??
        (listenPlatformChanges ? deviceTimeZoneChangeEvents() : null);
    _changeSubscription = events?.listen((_) => refresh());
  }

  final DeviceTimeZoneSource _source;
  final bool _observeLifecycle;
  StreamSubscription<void>? _changeSubscription;

  DeviceTimeZoneStatus _status = const DeviceTimeZoneStatus.unresolved(
    DeviceTimeZoneProblem.unavailable,
  );
  String? _selected;
  bool _refreshing = false;
  bool _refreshRequested = false;
  Future<void>? _refreshFuture;
  bool _disposed = false;

  /// What the device last reported, including why it could not be used.
  DeviceTimeZoneStatus get status => _status;

  /// The zone resolved from the device, or null when there is none.
  String? get deviceIanaId => _status.ianaId;

  /// An explicit user choice, which wins over the device zone until cleared.
  String? get selectedIanaId => _selected;

  /// The zone the UI should use, or null when the user still has to choose.
  String? get displayIanaId => _selected ?? _status.ianaId;

  /// True while a read is in flight.
  bool get refreshing => _refreshing;

  /// True when the display follows the device rather than a user choice.
  bool get followsDeviceZone => _selected == null && _status.resolved;

  /// Why the device zone is unusable, when it is.
  DeviceTimeZoneProblem? get problem => _status.problem;

  /// Raw platform identity behind [status], for the diagnostic message.
  String? get deviceIdentity => _status.identity;

  Future<void> refresh() {
    if (_disposed) return Future.value();
    _refreshRequested = true;
    return _refreshFuture ??= _readLatest().whenComplete(() {
      _refreshFuture = null;
    });
  }

  Future<void> _readLatest() async {
    _refreshing = true;
    try {
      do {
        _refreshRequested = false;
        await _readOnce();
      } while (_refreshRequested && !_disposed);
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _readOnce() async {
    DeviceTimeZoneStatus next;
    try {
      next = resolveDeviceTimeZone(await _source.read());
    } on Object {
      next = const DeviceTimeZoneStatus.unresolved(
        DeviceTimeZoneProblem.unavailable,
      );
    }
    if (_disposed) return;
    final changed =
        next.ianaId != _status.ianaId ||
        next.problem != _status.problem ||
        next.identity != _status.identity;
    _status = next;
    if (changed) notifyListeners();
  }

  /// Adopts a user-picked zone. Rejects anything the bundled database does not
  /// recognize, so an unusable value can never reach the grid.
  bool chooseIana(String id) {
    if (!isKnownIanaTimeZone(id)) return false;
    if (_selected == id) return true;
    _selected = id;
    notifyListeners();
    return true;
  }

  /// Goes back to the device zone, if the device has one.
  void useDeviceZone() {
    if (_selected == null) return;
    _selected = null;
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refresh();
  }

  @override
  void dispose() {
    _disposed = true;
    _changeSubscription?.cancel();
    if (_observeLifecycle) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
