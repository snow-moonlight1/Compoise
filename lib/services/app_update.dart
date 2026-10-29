import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../app_version.dart';
import '../diagnostics/app_log.dart';
import 'update_check.dart';

/// Where the in-app update runs. Linux keeps opening the release page.
enum UpdateTarget { android, windows, none }

UpdateTarget get currentUpdateTarget {
  // Widget tests run on the host OS; they opt in by passing a target.
  if (Platform.environment['FLUTTER_TEST'] == 'true') return UpdateTarget.none;
  if (Platform.isAndroid) return UpdateTarget.android;
  if (Platform.isWindows) return UpdateTarget.windows;
  return UpdateTarget.none;
}

const _releaseDownloadPrefix =
    'https://github.com/snow-moonlight1/Compoise/releases/download/';
const checksumsFileName = 'SHA256SUMS.txt';

/// The release file for this device, by the names the release workflow uses:
/// `compoise-<label>-android-<abi>.apk` and
/// `compoise-<label>-windows-<arch>-setup.exe`.
///
/// Android tries the device ABIs in preference order (only the two phone
/// ABIs have split APKs), then the universal APK.
String? updateAssetName(
  UpdateTarget target,
  String label, {
  List<String> abis = const [],
  String windowsArch = 'x64',
}) {
  switch (target) {
    case UpdateTarget.android:
      for (final abi in abis) {
        if (abi == 'arm64-v8a' || abi == 'armeabi-v7a') {
          return 'compoise-$label-android-$abi.apk';
        }
      }
      return 'compoise-$label-android-universal.apk';
    case UpdateTarget.windows:
      final arch = windowsArch == 'arm64' ? 'arm64' : 'x64';
      return 'compoise-$label-windows-$arch-setup.exe';
    case UpdateTarget.none:
      return null;
  }
}

/// Picks [preferred] from the files a release actually has; falls back to the
/// universal APK or the x64 installer when the preferred one is missing.
String? pickAvailableAsset(String preferred, Iterable<String> available) {
  final names = available.toSet();
  if (names.contains(preferred)) return preferred;
  final fallback = preferred.contains('-android-')
      ? preferred.replaceFirst(
          RegExp(r'-android-.+\.apk$'),
          '-android-universal.apk',
        )
      : preferred.replaceFirst('-windows-arm64-', '-windows-x64-');
  return names.contains(fallback) ? fallback : null;
}

Uri releaseFileUri(String tag, String name) => Uri.parse(
  '$_releaseDownloadPrefix${Uri.encodeComponent(tag)}/'
  '${Uri.encodeComponent(name)}',
);

/// `sha256sum` output: `<hex>  <name>` or `<hex> *<name>` per line.
Map<String, String> parseSha256Sums(String text) {
  final sums = <String, String>{};
  final line = RegExp(r'^([0-9a-fA-F]{64})\s+\*?(.+?)\s*$');
  for (final raw in const LineSplitter().convert(text)) {
    final m = line.firstMatch(raw);
    if (m != null) sums[m.group(2)!] = m.group(1)!.toLowerCase();
  }
  return sums;
}

/// The one update package kept on the device.
class StoredPackage {
  const StoredPackage({
    required this.version,
    required this.fileName,
    required this.sha256,
    required this.complete,
  });

  /// Release version, for example `1.2.2` or `1.2.2+6`.
  final String version;
  final String fileName;
  final String sha256;

  /// Downloaded and verified against SHA256SUMS.txt.
  final bool complete;

  ReleaseVersion? get parsed => ReleaseVersion.parse(version);

  Map<String, Object?> toJson() => {
    'version': version,
    'fileName': fileName,
    'sha256': sha256,
    'complete': complete,
  };

  static StoredPackage? fromJson(Object? json) {
    if (json is! Map) return null;
    final version = json['version'];
    final fileName = json['fileName'];
    final sha = json['sha256'];
    if (version is! String || fileName is! String || sha is! String) {
      return null;
    }
    // Only a bare file name inside the update folder is trusted.
    if (fileName.contains('/') || fileName.contains('\\')) return null;
    return StoredPackage(
      version: version,
      fileName: fileName,
      sha256: sha,
      complete: json['complete'] == true,
    );
  }
}

/// [a] is a newer release than [b]. A missing build number on either side
/// only compares the version, since release tags usually carry none.
bool isNewerRelease(ReleaseVersion a, ReleaseVersion b) {
  if (a.build == null || b.build == null) {
    return ReleaseVersion(a.major, a.minor, a.patch, preRelease: a.preRelease) >
        ReleaseVersion(b.major, b.minor, b.patch, preRelease: b.preRelease);
  }
  return a > b;
}

bool isSameRelease(ReleaseVersion a, ReleaseVersion b) =>
    !isNewerRelease(a, b) && !isNewerRelease(b, a);

/// On launch: a package that is not newer than the running app was installed
/// (or is stale) and is deleted.
bool shouldDiscardOnLaunch(StoredPackage? stored, ReleaseVersion current) {
  if (stored == null) return false;
  final v = stored.parsed;
  return v == null || !isNewerRelease(v, current);
}

enum UpdateStep { upToDate, download, resume, install }

class UpdatePlan {
  const UpdatePlan(this.step, {this.discardStored = false});

  final UpdateStep step;

  /// Delete the stored package (and partial file) first, without asking.
  final bool discardStored;

  @override
  bool operator ==(Object other) =>
      other is UpdatePlan &&
      other.step == step &&
      other.discardStored == discardStored;

  @override
  int get hashCode => Object.hash(step, discardStored);

  @override
  String toString() => 'UpdatePlan($step, discard: $discardStored)';
}

/// What tapping update does, given the stored package and the latest release.
///
/// - A verified package of the latest release installs without downloading.
/// - A partial download of the latest release resumes.
/// - Anything else stored (an older release, an unreadable record, a
///   different file) is deleted quietly and the latest is downloaded.
UpdatePlan planUpdate({
  required StoredPackage? stored,
  required ReleaseVersion current,
  required ReleaseVersion latest,
  required String fileName,
}) {
  if (!isNewerRelease(latest, current)) {
    return UpdatePlan(UpdateStep.upToDate, discardStored: stored != null);
  }
  if (stored == null) return const UpdatePlan(UpdateStep.download);
  final v = stored.parsed;
  if (v == null || !isSameRelease(v, latest) || stored.fileName != fileName) {
    return const UpdatePlan(UpdateStep.download, discardStored: true);
  }
  return UpdatePlan(stored.complete ? UpdateStep.install : UpdateStep.resume);
}

enum UpdateFailure { network, noSpace, damaged, install }

class UpdateException implements Exception {
  const UpdateException(this.failure);
  final UpdateFailure failure;

  @override
  String toString() => 'UpdateException($failure)';
}

bool _isNoSpace(FileSystemException e) {
  final code = e.osError?.errorCode;
  // ENOSPC on Linux/Android, ERROR_DISK_FULL / ERROR_HANDLE_DISK_FULL on
  // Windows.
  return code == 28 || code == 112 || code == 39;
}

/// Keeps at most one update package in one app-private folder:
/// `<name>` (verified), `<name>.part` (downloading) and `package.json`.
class UpdatePackageStore {
  UpdatePackageStore(this.dir);

  final Directory dir;

  File get _record => File('${dir.path}${Platform.pathSeparator}package.json');
  File fileFor(String name) =>
      File('${dir.path}${Platform.pathSeparator}$name');
  File partFor(String name) => fileFor('$name.part');

  Future<StoredPackage?> read() async {
    try {
      if (!await _record.exists()) {
        // Files without a record are leftovers.
        if (await dir.exists() && !(await dir.list().isEmpty)) await clear();
        return null;
      }
      final stored = StoredPackage.fromJson(
        jsonDecode(await _record.readAsString()),
      );
      if (stored == null) {
        await clear();
        return null;
      }
      if (stored.complete && !await fileFor(stored.fileName).exists()) {
        await clear();
        return null;
      }
      return stored;
    } catch (e) {
      AppLog.warn('update', 'Package record unreadable: ${e.runtimeType}');
      await clear();
      return null;
    }
  }

  Future<void> write(StoredPackage stored) async {
    await dir.create(recursive: true);
    await _record.writeAsString(jsonEncode(stored.toJson()), flush: true);
  }

  /// Deletes everything in the folder.
  Future<void> clear() async {
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (e) {
      AppLog.warn('update', 'Could not clear update folder: ${e.runtimeType}');
    }
  }

  /// Deletes files that do not belong to [keep].
  Future<void> _removeOthers(String keep) async {
    if (!await dir.exists()) return;
    await for (final entity in dir.list()) {
      final name = entity.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
      if (name == 'package.json' || name == keep || name == '$keep.part') {
        continue;
      }
      try {
        await entity.delete(recursive: true);
      } catch (_) {}
    }
  }

  /// Downloads [url] as [fileName], resuming a partial file when there is one,
  /// and verifies it against [sha256]. On a hash mismatch everything is
  /// deleted. Reports progress as (received, total-or-null).
  Future<File> download({
    required http.Client client,
    required Uri url,
    required String fileName,
    required String version,
    required String sha256,
    void Function(int received, int? total)? onProgress,
  }) async {
    await dir.create(recursive: true);
    await _removeOthers(fileName);
    await write(
      StoredPackage(
        version: version,
        fileName: fileName,
        sha256: sha256,
        complete: false,
      ),
    );
    final part = partFor(fileName);
    var have = await part.exists() ? await part.length() : 0;
    final request = http.Request('GET', url)
      ..headers['User-Agent'] = 'Compoise/$appVersion';
    if (have > 0) request.headers['Range'] = 'bytes=$have-';
    http.StreamedResponse res;
    try {
      res = await client.send(request);
    } catch (e) {
      AppLog.warn('update', 'Download failed: ${e.runtimeType}');
      throw const UpdateException(UpdateFailure.network);
    }
    if (res.statusCode == 416 && have > 0) {
      // The partial file is already whole (or longer): verify below.
      await res.stream.drain<void>();
    } else if (res.statusCode == 200 || res.statusCode == 206) {
      final append = res.statusCode == 206 && have > 0;
      if (!append) have = 0;
      final total = res.contentLength == null
          ? null
          : res.contentLength! + (append ? have : 0);
      IOSink? sink;
      try {
        sink = part.openWrite(mode: append ? FileMode.append : FileMode.write);
        var received = have;
        onProgress?.call(received, total);
        await for (final chunk in res.stream) {
          sink.add(chunk);
          received += chunk.length;
          onProgress?.call(received, total);
        }
        await sink.flush();
        await sink.close();
        sink = null;
      } on FileSystemException catch (e) {
        await sink?.close().catchError((_) {});
        if (_isNoSpace(e)) {
          await clear();
          throw const UpdateException(UpdateFailure.noSpace);
        }
        rethrow;
      } catch (e) {
        // Network cut mid-way: keep the partial file to resume next time.
        await sink?.close().catchError((_) {});
        if (e is UpdateException) rethrow;
        AppLog.warn('update', 'Download interrupted: ${e.runtimeType}');
        throw const UpdateException(UpdateFailure.network);
      }
    } else {
      await res.stream.drain<void>();
      AppLog.warn('update', 'Download failed: HTTP ${res.statusCode}');
      throw const UpdateException(UpdateFailure.network);
    }
    final digest = await sha256Of(part);
    if (digest != sha256.toLowerCase()) {
      await clear();
      throw const UpdateException(UpdateFailure.damaged);
    }
    final file = await part.rename(fileFor(fileName).path);
    await write(
      StoredPackage(
        version: version,
        fileName: fileName,
        sha256: sha256,
        complete: true,
      ),
    );
    return file;
  }

  /// Re-checks a stored package before installing it.
  Future<bool> verify(StoredPackage stored) async {
    final file = fileFor(stored.fileName);
    if (!stored.complete || !await file.exists()) return false;
    return await sha256Of(file) == stored.sha256.toLowerCase();
  }
}

Future<String> sha256Of(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();

/// Platform side of installing: Android hands the APK to the system
/// installer; Windows starts the setup program and the app exits.
class UpdateInstaller {
  const UpdateInstaller();

  static const _channel = MethodChannel('compoise/app_update');

  Future<List<String>> abis() async {
    try {
      final list = await _channel.invokeListMethod<String>('abis');
      return list ?? const [];
    } catch (_) {
      return const [];
    }
  }

  /// Android 8+: whether the user allowed this app to install apps.
  Future<bool> canInstall() async {
    if (!Platform.isAndroid) return true;
    try {
      return await _channel.invokeMethod<bool>('canInstall') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> openInstallSettings() async {
    try {
      await _channel.invokeMethod<void>('openInstallSettings');
    } catch (_) {}
  }

  /// Starts the installer. Returns false when it could not start.
  Future<bool> install(File file) async {
    try {
      if (Platform.isAndroid) {
        return await _channel.invokeMethod<bool>('install', {
              'path': file.path,
            }) ??
            false;
      }
      if (Platform.isWindows) {
        await Process.start(
          file.path,
          const [],
          mode: ProcessStartMode.detached,
        );
        return true;
      }
    } catch (e) {
      AppLog.warn('update', 'Installer did not start: ${e.runtimeType}');
    }
    return false;
  }
}

/// The folder that holds the one update package.
Future<Directory> updateDirectory() async {
  final base = Platform.isAndroid
      ? await getApplicationCacheDirectory()
      : await getApplicationSupportDirectory();
  return Directory('${base.path}${Platform.pathSeparator}updates');
}

/// Launch housekeeping: delete a package that is already installed or older
/// than this app, and leftovers. Returns a verified package that is still
/// newer than this app, if any.
Future<StoredPackage?> tidyUpdatePackages({
  UpdatePackageStore? store,
  String? currentVersion,
}) async {
  if (currentUpdateTarget == UpdateTarget.none && store == null) return null;
  try {
    final packages = store ?? UpdatePackageStore(await updateDirectory());
    final current = ReleaseVersion.parse(currentVersion ?? appVersionLabel);
    final stored = await packages.read();
    if (current == null) return null;
    if (shouldDiscardOnLaunch(stored, current)) {
      await packages.clear();
      return null;
    }
    return stored != null && stored.complete ? stored : null;
  } catch (e) {
    AppLog.warn('update', 'Update tidy failed: ${e.runtimeType}');
    return null;
  }
}

/// Gets the update package for a release ready: reuses a verified one,
/// resumes a partial one, or downloads it, always keeping only one.
class AppUpdater {
  AppUpdater({
    http.Client? client,
    UpdatePackageStore? store,
    UpdateInstaller? installer,
    UpdateTarget? target,
    String? currentVersion,
  }) : _client = client,
       _store = store,
       installer = installer ?? const UpdateInstaller(),
       target = target ?? currentUpdateTarget,
       _current = currentVersion ?? appVersionLabel;

  final http.Client? _client;
  UpdatePackageStore? _store;
  final UpdateInstaller installer;
  final UpdateTarget target;
  final String _current;

  bool get supported => target != UpdateTarget.none;

  Future<UpdatePackageStore> get store async =>
      _store ??= UpdatePackageStore(await updateDirectory());

  /// A verified package of [version] is already on the device.
  Future<bool> hasReadyPackage(ReleaseVersion version) async {
    final stored = await (await store).read();
    final v = stored?.parsed;
    return stored != null &&
        stored.complete &&
        v != null &&
        isSameRelease(v, version);
  }

  /// Returns the verified installer file for [tag] / [version].
  Future<File> prepare({
    required String tag,
    required ReleaseVersion version,
    void Function(int received, int? total)? onProgress,
  }) async {
    final packages = await store;
    final current = ReleaseVersion.parse(_current)!;
    final client = _client ?? http.Client();
    try {
      final abis = target == UpdateTarget.android
          ? await installer.abis()
          : const <String>[];
      final arch =
          Platform.isWindows &&
              (Platform.environment['PROCESSOR_ARCHITECTURE'] ?? '')
                  .toUpperCase()
                  .contains('ARM64')
          ? 'arm64'
          : 'x64';
      final preferred = updateAssetName(
        target,
        version.label,
        abis: abis,
        windowsArch: arch,
      );
      if (preferred == null) throw const UpdateException(UpdateFailure.install);

      // A verified package of this release needs no network at all.
      final stored = await packages.read();
      final early = planUpdate(
        stored: stored,
        current: current,
        latest: version,
        fileName: stored?.fileName ?? preferred,
      );
      if (early.step == UpdateStep.install && await packages.verify(stored!)) {
        return packages.fileFor(stored.fileName);
      }

      final sums = await _checksums(client, tag);
      final name = pickAvailableAsset(preferred, sums.keys);
      if (name == null) throw const UpdateException(UpdateFailure.network);
      final plan = planUpdate(
        stored: await packages.read(),
        current: current,
        latest: version,
        fileName: name,
      );
      if (plan.discardStored) await packages.clear();
      if (plan.step == UpdateStep.upToDate) {
        throw const UpdateException(UpdateFailure.install);
      }
      return await packages.download(
        client: client,
        url: releaseFileUri(tag, name),
        fileName: name,
        version: tag.startsWith('v') ? tag.substring(1) : tag,
        sha256: sums[name]!,
        onProgress: onProgress,
      );
    } on FileSystemException catch (e) {
      AppLog.warn('update', 'Update file error: ${e.runtimeType}');
      throw UpdateException(
        _isNoSpace(e) ? UpdateFailure.noSpace : UpdateFailure.damaged,
      );
    } finally {
      if (_client == null) client.close();
    }
  }

  Future<Map<String, String>> _checksums(http.Client client, String tag) async {
    try {
      final res = await client
          .get(
            releaseFileUri(tag, checksumsFileName),
            headers: {'User-Agent': 'Compoise/$appVersion'},
          )
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) {
        throw UpdateException(UpdateFailure.network);
      }
      return parseSha256Sums(utf8.decode(res.bodyBytes, allowMalformed: true));
    } on UpdateException {
      rethrow;
    } catch (e) {
      AppLog.warn('update', 'Checksums failed: ${e.runtimeType}');
      throw const UpdateException(UpdateFailure.network);
    }
  }
}
