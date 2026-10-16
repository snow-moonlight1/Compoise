import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../app_version.dart';
import '../diagnostics/app_log.dart';
import 'device_prefs.dart';

const latestReleaseApi =
    'https://api.github.com/repos/snow-moonlight1/Compoise/releases/latest';
const releasePagePrefix = 'https://github.com/snow-moonlight1/Compoise/';
const latestReleasePage = '${releasePagePrefix}releases/latest';

/// A release tag such as `v1.2.3`, `v1.2.3+4` or `v1.2.3-ci.5`.
class ReleaseVersion implements Comparable<ReleaseVersion> {
  const ReleaseVersion(
    this.major,
    this.minor,
    this.patch, {
    this.preRelease,
    this.build,
  });

  final int major;
  final int minor;
  final int patch;
  final String? preRelease;
  final int? build;

  static final _pattern = RegExp(
    r'^v?(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.\-]+))?(?:\+(\d+))?$',
  );

  static ReleaseVersion? parse(String raw) {
    final m = _pattern.firstMatch(raw.trim());
    if (m == null) return null;
    return ReleaseVersion(
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
      preRelease: m.group(4),
      build: m.group(5) == null ? null : int.parse(m.group(5)!),
    );
  }

  bool get isPreRelease => preRelease != null;

  /// What users see: `1.2.3`, without build metadata.
  String get label => '$major.$minor.$patch';

  @override
  int compareTo(ReleaseVersion other) {
    for (final (a, b) in [
      (major, other.major),
      (minor, other.minor),
      (patch, other.patch),
    ]) {
      if (a != b) return a.compareTo(b);
    }
    // A pre-release sorts before the release it leads up to.
    if (isPreRelease != other.isPreRelease) return isPreRelease ? -1 : 1;
    if (isPreRelease) {
      final order = preRelease!.compareTo(other.preRelease!);
      if (order != 0) return order;
    }
    return (build ?? 0).compareTo(other.build ?? 0);
  }

  bool operator >(ReleaseVersion other) => compareTo(other) > 0;
}

enum UpdateCheckStatus { available, upToDate, failed }

class UpdateCheckResult {
  const UpdateCheckResult(this.status, {this.latest, this.url});

  final UpdateCheckStatus status;

  /// For example `1.0.1`.
  final String? latest;

  /// The release page; always on github.com/snow-moonlight1/Compoise.
  final String? url;
}

/// Asks GitHub for the latest formal release and compares it with this build.
///
/// The request carries no user data: only the fixed URL, an `Accept` header
/// and a `User-Agent` naming the app version. Failures are quiet and logged.
class UpdateChecker {
  UpdateChecker({
    http.Client? client,
    DevicePrefs? prefs,
    String? currentVersion,
    DateTime Function()? now,
    this.timeout = const Duration(seconds: 10),
  }) : _client = client,
       _prefs = prefs ?? DevicePrefs.instance,
       _current = currentVersion ?? appVersionLabel,
       _now = now ?? DateTime.now;

  static const interval = Duration(hours: 24);

  final http.Client? _client;
  final DevicePrefs _prefs;
  final String _current;
  final DateTime Function() _now;
  final Duration timeout;

  Future<UpdateCheckResult> check() async {
    final client = _client ?? http.Client();
    try {
      final res = await client
          .get(
            Uri.parse(latestReleaseApi),
            headers: {
              'Accept': 'application/vnd.github+json',
              'User-Agent': 'Compoise/$appVersion',
            },
          )
          .timeout(timeout);
      if (res.statusCode != 200) {
        AppLog.warn('update', 'Update check HTTP ${res.statusCode}');
        return const UpdateCheckResult(UpdateCheckStatus.failed);
      }
      final json = jsonDecode(utf8.decode(res.bodyBytes));
      if (json is! Map) throw const FormatException('release is not an object');
      if (json['draft'] == true || json['prerelease'] == true) {
        return const UpdateCheckResult(UpdateCheckStatus.upToDate);
      }
      final tag = json['tag_name'];
      final latest = tag is String ? ReleaseVersion.parse(tag) : null;
      final current = ReleaseVersion.parse(_current);
      if (latest == null || current == null) {
        throw const FormatException('unreadable version');
      }
      if (latest.isPreRelease || !(latest > current)) {
        return UpdateCheckResult(
          UpdateCheckStatus.upToDate,
          latest: latest.label,
        );
      }
      final page = json['html_url'];
      return UpdateCheckResult(
        UpdateCheckStatus.available,
        latest: latest.label,
        url: page is String && page.startsWith(releasePagePrefix)
            ? page
            : latestReleasePage,
      );
    } catch (e) {
      AppLog.warn('update', 'Update check failed: ${e.runtimeType}');
      return const UpdateCheckResult(UpdateCheckStatus.failed);
    } finally {
      if (_client == null) client.close();
    }
  }

  /// The automatic check: only when the user turned it on and at most once a
  /// day. Returns a result only when a newer version exists.
  Future<UpdateCheckResult?> checkIfDue() async {
    if (!_prefs.updateCheckEnabled) return null;
    final now = _now();
    final last = _prefs.lastUpdateCheck;
    if (last != null && !last.isAfter(now) && now.difference(last) < interval) {
      return null;
    }
    await _prefs.setLastUpdateCheck(now);
    final result = await check();
    return result.status == UpdateCheckStatus.available ? result : null;
  }
}
