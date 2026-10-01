/// Device IANA time zone discovery for the schedule surfaces (WP15-D1).
///
/// The reported identity is never guessed from the current UTC offset or the
/// display language. Android and Linux already name an IANA zone; Windows
/// reports a Windows zone key that is translated through the fixed CLDR table
/// in `windows_time_zone_map.dart`; anything else is reported as a problem so
/// the user can pick a zone instead of being shown a silent UTC fallback.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../schedule_time.dart';
import 'windows_time_zone_map.dart';

/// Method channel implemented by the Android activity and the Windows runner.
/// It answers `systemZone` and pushes `onTimeZoneChanged` when the platform
/// reports a system zone change.
const String deviceTimeZoneChannelName = 'matrixflow/device_time_zone';

/// Which platform reported the identity, because it decides how the value is
/// interpreted: only Windows reports a key that needs translation.
enum DeviceTimeZonePlatform { android, windows, linux, unknown }

/// Why a device identity could not be turned into an IANA zone.
enum DeviceTimeZoneProblem {
  /// The platform could not be asked, or reported nothing usable.
  unavailable,

  /// The identity has no entry in the pinned Windows mapping.
  unmapped,

  /// The reported id is not in the bundled IANA database.
  invalid,
}

/// One raw platform answer, before any translation or validation.
class DeviceTimeZoneReading {
  const DeviceTimeZoneReading({required this.platform, this.identity})
    : unreadable = false;

  const DeviceTimeZoneReading.unreadable(this.platform)
    : identity = null,
      unreadable = true;

  final DeviceTimeZonePlatform platform;

  /// Windows zone key on Windows, IANA id on Android and Linux.
  final String? identity;

  /// True when the platform could not be asked at all.
  final bool unreadable;
}

/// The outcome shown to the user: either a usable IANA zone or a reason.
class DeviceTimeZoneStatus {
  const DeviceTimeZoneStatus._(this.ianaId, this.identity, this.problem);

  const DeviceTimeZoneStatus.resolved(String ianaId, {String? identity})
    : this._(ianaId, identity, null);

  const DeviceTimeZoneStatus.unresolved(
    DeviceTimeZoneProblem problem, {
    String? identity,
  }) : this._(null, identity, problem);

  final String? ianaId;

  /// Raw platform value, kept for the diagnostic message only.
  final String? identity;

  final DeviceTimeZoneProblem? problem;

  bool get resolved => ianaId != null;

  @override
  String toString() =>
      'DeviceTimeZoneStatus(${ianaId ?? problem?.name}, identity: $identity)';
}

/// True when the bundled database recognizes [id] as an IANA zone.
bool isKnownIanaTimeZone(String id) {
  if (id.isEmpty || id != id.trim()) return false;
  try {
    scheduleLocation(id);
    return true;
  } on ScheduleTimeException {
    return false;
  }
}

/// Every IANA id in the bundled database, sorted. Region ids first, since the
/// short aliases (`UTC`, `GMT`, `EST`) are not what a device reports.
List<String> scheduleZoneIds() {
  if (!tz.timeZoneDatabase.isInitialized) tz_data.initializeTimeZones();
  final ids = tz.timeZoneDatabase.locations.keys
      .where((id) => id.contains('/'))
      .toList();
  ids.sort();
  return List.unmodifiable(ids);
}

/// Region ids matching [query], capped so the picker stays a short list.
List<String> searchScheduleZoneIds(String query, {int limit = 60}) {
  final needle = query.trim().toLowerCase();
  final matches = <String>[];
  for (final id in scheduleZoneIds()) {
    if (needle.isEmpty || id.toLowerCase().contains(needle)) {
      matches.add(id);
      if (matches.length >= limit) break;
    }
  }
  return matches;
}

/// The Windows key to IANA translation, case-insensitive as a courtesy to
/// callers that normalize the key name themselves.
String? ianaForWindowsIdentity(String identity) {
  final trimmed = identity.trim();
  if (trimmed.isEmpty) return null;
  final exact = windowsTimeZoneToIana[trimmed];
  if (exact != null) return exact;
  final lowered = trimmed.toLowerCase();
  for (final entry in windowsTimeZoneToIana.entries) {
    if (entry.key.toLowerCase() == lowered) return entry.value;
  }
  return null;
}

/// Turns one raw platform answer into the status the UI acts on.
DeviceTimeZoneStatus resolveDeviceTimeZone(DeviceTimeZoneReading reading) {
  final identity = reading.identity?.trim();
  if (reading.unreadable || identity == null || identity.isEmpty) {
    return DeviceTimeZoneStatus.unresolved(
      DeviceTimeZoneProblem.unavailable,
      identity: identity,
    );
  }
  if (reading.platform == DeviceTimeZonePlatform.windows) {
    final iana = ianaForWindowsIdentity(identity);
    if (iana == null) {
      return DeviceTimeZoneStatus.unresolved(
        DeviceTimeZoneProblem.unmapped,
        identity: identity,
      );
    }
    return _validated(iana, identity);
  }
  return _validated(identity, identity);
}

DeviceTimeZoneStatus _validated(String ianaId, String identity) =>
    isKnownIanaTimeZone(ianaId)
    ? DeviceTimeZoneStatus.resolved(ianaId, identity: identity)
    : DeviceTimeZoneStatus.unresolved(
        DeviceTimeZoneProblem.invalid,
        identity: identity,
      );

/// Anything that can answer "which zone is this device in".
abstract class DeviceTimeZoneSource {
  Future<DeviceTimeZoneReading> read();
}

/// The source a real app uses: the platform channel everywhere except Linux,
/// where the system configuration is read directly from Dart.
DeviceTimeZoneSource defaultDeviceTimeZoneSource() =>
    defaultTargetPlatform == TargetPlatform.linux
    ? LinuxDeviceTimeZoneSource()
    : ChannelDeviceTimeZoneSource();

/// Reads the identity over [deviceTimeZoneChannelName].
class ChannelDeviceTimeZoneSource implements DeviceTimeZoneSource {
  ChannelDeviceTimeZoneSource({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(deviceTimeZoneChannelName);

  final MethodChannel _channel;

  @override
  Future<DeviceTimeZoneReading> read() async {
    try {
      final reply = await _channel.invokeMapMethod<String, Object?>(
        'systemZone',
      );
      final platform =
          _platformFromName(reply?['platform'] as String?) ??
          _platformFromTarget(defaultTargetPlatform);
      final identity = (reply?['identity'] as String?)?.trim();
      if (identity == null || identity.isEmpty) {
        return DeviceTimeZoneReading.unreadable(platform);
      }
      return DeviceTimeZoneReading(platform: platform, identity: identity);
    } on MissingPluginException {
      return DeviceTimeZoneReading.unreadable(
        _platformFromTarget(defaultTargetPlatform),
      );
    } on PlatformException {
      return DeviceTimeZoneReading.unreadable(
        _platformFromTarget(defaultTargetPlatform),
      );
    }
  }
}

/// Reads `TZ` from the process, then the distribution's `/etc/timezone` file
/// and the `/etc/localtime` symlink. An explicit `TZ` that
/// cannot be named as an IANA zone is reported as a problem rather than
/// silently replaced by a lower-priority file.
class LinuxDeviceTimeZoneSource implements DeviceTimeZoneSource {
  LinuxDeviceTimeZoneSource({
    Map<String, String>? environment,
    Future<String?> Function(String path)? readFile,
    Future<String?> Function(String path)? readLink,
  }) : _environment = environment ?? Platform.environment,
       _readFile = readFile ?? _defaultReadFile,
       _readLink = readLink ?? _defaultReadLink;

  final Map<String, String> _environment;
  final Future<String?> Function(String path) _readFile;
  final Future<String?> Function(String path) _readLink;

  static Future<String?> _defaultReadFile(String path) async {
    final file = File(path);
    if (!await file.exists()) return null;
    return file.readAsString();
  }

  static Future<String?> _defaultReadLink(String path) async {
    final link = Link(path);
    if (!await link.exists()) return null;
    return link.target();
  }

  @override
  Future<DeviceTimeZoneReading> read() async {
    const platform = DeviceTimeZonePlatform.linux;
    final tzValue = _environment['TZ']?.trim();
    if (tzValue != null && tzValue.isNotEmpty) {
      final candidate = _zoneFromZoneInfoPath(
        tzValue.startsWith(':') ? tzValue.substring(1) : tzValue,
      );
      if (candidate != null) {
        return DeviceTimeZoneReading(platform: platform, identity: candidate);
      }
      // `:/etc/localtime` and its relatives point back at the files below.
      if (!tzValue.contains('/localtime')) {
        return DeviceTimeZoneReading(platform: platform, identity: tzValue);
      }
    }

    final etcTimezone = (await _readFile('/etc/timezone'))?.trim();
    if (etcTimezone != null && etcTimezone.isNotEmpty) {
      final first = etcTimezone
          .split(RegExp(r'[\r\n]+'))
          .firstWhere((line) => line.trim().isNotEmpty, orElse: () => '')
          .trim();
      if (first.isNotEmpty) {
        return DeviceTimeZoneReading(platform: platform, identity: first);
      }
    }

    final linkTarget = await _readLink('/etc/localtime');
    if (linkTarget != null && linkTarget.isNotEmpty) {
      final candidate = _zoneFromZoneInfoPath(linkTarget);
      if (candidate != null) {
        return DeviceTimeZoneReading(platform: platform, identity: candidate);
      }
      // A copied file carries no zone name; reading the offset would be a guess.
      return const DeviceTimeZoneReading.unreadable(platform);
    }
    return const DeviceTimeZoneReading.unreadable(platform);
  }

  /// Names the zone in a zoneinfo path. A bare `Asia/Shanghai` or a POSIX
  /// `TZ` rule both come back unchanged so that validation can reject them.
  static String? _zoneFromZoneInfoPath(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    const marker = 'zoneinfo/';
    final index = trimmed.indexOf(marker);
    if (index >= 0) {
      final tail = trimmed.substring(index + marker.length);
      return tail.isEmpty ? null : tail;
    }
    if (trimmed.endsWith('/localtime') || trimmed.endsWith('/timezone')) {
      return null;
    }
    return trimmed;
  }
}

/// Emits whenever a platform that can observe a zone change reports one. The
/// stream is broadcast; closing it releases the channel handler.
Stream<void> deviceTimeZoneChangeEvents({MethodChannel? channel}) {
  final events = StreamController<void>.broadcast();
  final methodChannel =
      channel ?? const MethodChannel(deviceTimeZoneChannelName);
  methodChannel.setMethodCallHandler((call) async {
    if (call.method == 'onTimeZoneChanged' && !events.isClosed) {
      events.add(null);
    }
  });
  events.onCancel = () => methodChannel.setMethodCallHandler(null);
  return events.stream;
}

DeviceTimeZonePlatform? _platformFromName(String? name) => switch (name) {
  'android' => DeviceTimeZonePlatform.android,
  'windows' => DeviceTimeZonePlatform.windows,
  'linux' => DeviceTimeZonePlatform.linux,
  _ => null,
};

DeviceTimeZonePlatform _platformFromTarget(TargetPlatform platform) =>
    switch (platform) {
      TargetPlatform.android => DeviceTimeZonePlatform.android,
      TargetPlatform.windows => DeviceTimeZonePlatform.windows,
      TargetPlatform.linux => DeviceTimeZonePlatform.linux,
      _ => DeviceTimeZonePlatform.unknown,
    };
