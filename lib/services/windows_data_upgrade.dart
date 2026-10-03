import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
// Use the locked FFI resolver WITHOUT creating an app directory. The public
// conditional export's analyzer stub omits Known Folder constants/nullability.
// ignore: depend_on_referenced_packages, implementation_imports
import 'package:path_provider_windows/src/path_provider_windows_real.dart';
// ignore: depend_on_referenced_packages, implementation_imports
import 'package:path_provider_windows/src/folders.dart';
// Locked dependency of path_provider/shared_preferences; no plugin change.
// ignore: depend_on_referenced_packages
import 'package:path/path.dart' as p;

import '../save_protocol.dart';

enum WindowsUpgradeStatus {
  noLegacyData,
  currentProfile,
  migrated,
  sourceUnreadable,
  currentUnreadable,
  failed,
}

class WindowsUpgradeResult {
  final WindowsUpgradeStatus status;
  final bool credentialsNeedSetup;
  final bool credentialNoticeRead;
  final bool protocolNeedsRecovery;
  final String? sourcePath;
  final String? currentPath;

  const WindowsUpgradeResult(
    this.status, {
    this.credentialsNeedSetup = false,
    this.credentialNoticeRead = false,
    this.protocolNeedsRecovery = false,
    this.sourcePath,
    this.currentPath,
  });

  bool get canOpen => switch (status) {
    WindowsUpgradeStatus.noLegacyData ||
    WindowsUpgradeStatus.currentProfile ||
    WindowsUpgradeStatus.migrated => true,
    _ => false,
  };

  bool get showCredentialNotice =>
      credentialsNeedSetup && !credentialNoticeRead;
}

/// Production uses the actual plugin's RoamingAppData Known Folder resolver.
/// Current exe identity is pinned by OS26 to Compoise/Compoise.
/// Tests always supply a temporary roaming root instead.
class WindowsUpgradePaths {
  final String roamingRoot;
  WindowsUpgradePaths(this.roamingRoot);

  String get source => p.join(roamingRoot, 'com.matrixflow', 'MatrixFlow AI');
  String get current => p.join(roamingRoot, 'Compoise', 'Compoise');
  String get stagingParent => p.join(roamingRoot, 'Compoise');

  static Future<WindowsUpgradePaths> fromPlugin() async {
    final root = await PathProviderWindows().getPath(
      WindowsKnownFolder.RoamingAppData,
    );
    if (root == null) {
      throw const FileSystemException('Missing roaming directory');
    }
    return WindowsUpgradePaths(root);
  }
}

bool _samePath(String a, String b) {
  final first = p.normalize(p.absolute(a));
  final second = p.normalize(p.absolute(b));
  return Platform.isWindows
      ? _windowsLongName(first).toLowerCase() ==
            _windowsLongName(second).toLowerCase()
      : first == second;
}

// Expand 8.3 names without resolving a directory junction/symlink to its target.
// The caller separately checks every ancestor's type and resolved path.
// https://learn.microsoft.com/windows/win32/api/fileapi/nf-fileapi-getlongpathnamew
String _windowsLongName(String path) => using((arena) {
  final expand = DynamicLibrary.open('kernel32.dll')
      .lookupFunction<
        Uint32 Function(Pointer<Utf16>, Pointer<Utf16>, Uint32),
        int Function(Pointer<Utf16>, Pointer<Utf16>, int)
      >('GetLongPathNameW');
  const capacity = 32768;
  final output = arena<Uint16>(capacity).cast<Utf16>();
  final length = expand(path.toNativeUtf16(allocator: arena), output, capacity);
  // Missing/inaccessible paths still have to pass the existing strict guard.
  if (length == 0 || length >= capacity) return path;
  return p.normalize(output.toDartString(length: length));
});

/// Inject filesystem operations (including failed writes/publish and races).
/// publish must atomically move within a volume and must NEVER replace a target.
class WindowsUpgradeFiles {
  const WindowsUpgradeFiles();

  Future<FileSystemEntityType> type(String path) =>
      FileSystemEntity.type(path, followLinks: false);
  Future<String> canonicalDirectory(String path) =>
      Directory(path).resolveSymbolicLinks();
  Future<List<String>> children(String path) => Directory(
    path,
  ).list(followLinks: false).map((entry) => entry.path).toList();
  Future<Uint8List> read(String path) => File(path).readAsBytes();
  Future<void> createDirectory(String path) async {
    await Directory(path).create(recursive: true);
  }

  Future<String> createStage(String parent) async =>
      (await Directory(parent).createTemp('.wp28-u1-')).path;

  Future<void> write(String path, List<int> bytes) async {
    await File(path).create(exclusive: true);
    await File(path).writeAsBytes(bytes, flush: true);
  }

  Future<void> removeFile(String path) async => File(path).delete();
  Future<void> removeDirectory(String path) async => Directory(path).delete();

  Future<void> publish(String staged, String target) async {
    if (!Platform.isWindows) {
      // No POSIX rename fallback: it can replace a target after a check.
      throw UnsupportedError('Windows no-replace publication required');
    }
    final kernel = DynamicLibrary.open('kernel32.dll');
    final move = kernel
        .lookupFunction<
          Int32 Function(Pointer<Utf16>, Pointer<Utf16>, Uint32),
          int Function(Pointer<Utf16>, Pointer<Utf16>, int)
        >('MoveFileExW');
    using((arena) {
      // MOVEFILE_WRITE_THROUGH, deliberately WITHOUT REPLACE_EXISTING or
      // COPY_ALLOWED. The single file is the commit point, on the same volume.
      if (move(
            staged.toNativeUtf16(allocator: arena),
            target.toNativeUtf16(allocator: arena),
            0x8,
          ) ==
          0) {
        throw const FileSystemException('Upgrade publication failed');
      }
    });
  }
}

/// One-time, conservative adoption of a historical Windows preferences file.
/// No source writes, credential decryptions, model conversion or slot repair.
class WindowsDataUpgrade {
  static const preferencesName = 'shared_preferences.json';
  static const credentialNoticeKey =
      'flutter.${SaveProtocol.windowsCredentialsRequiredKey}';
  final Future<WindowsUpgradePaths> Function() paths;
  final WindowsUpgradeFiles files;

  WindowsDataUpgrade({
    this.paths = WindowsUpgradePaths.fromPlugin,
    this.files = const WindowsUpgradeFiles(),
  });

  Future<WindowsUpgradeResult> prepare() async {
    WindowsUpgradePaths? locations;
    String? stage;
    try {
      locations = await paths();
      final root = locations.roamingRoot;
      if (!p.isAbsolute(root) || p.normalize(root) != root) {
        throw const FileSystemException('Invalid roaming root');
      }
      await _guardDirectory(root, mustExist: true);
      await _guardDirectory(locations.current);
      final existing = await _current(locations);
      if (existing != null) return existing;

      await _guardDirectory(locations.source);
      final sourceFile = p.join(locations.source, preferencesName);
      final sourceType = await files.type(sourceFile);
      if (sourceType == FileSystemEntityType.notFound) {
        // A legacy encrypted file without a library is still never copied.
        return _result(
          WindowsUpgradeStatus.noLegacyData,
          locations,
          credentials: await _legacyCredentialsExist(locations),
        );
      }
      if (sourceType != FileSystemEntityType.file) {
        throw const FileSystemException('Unsafe source file');
      }
      await _guardFile(sourceFile);
      final sourceBytes = await files.read(sourceFile);
      Map<String, Object> envelope;
      try {
        envelope = decodePreferences(sourceBytes);
      } catch (_) {
        return _result(WindowsUpgradeStatus.sourceUnreadable, locations);
      }
      final credentials = await _legacyCredentialsExist(locations);
      // A warning travels in the same file/commit as the library, so a crash
      // immediately after publication cannot lose the reconfiguration notice.
      final bytes = credentials
          ? utf8.encode(jsonEncode({...envelope, credentialNoticeKey: true}))
          : sourceBytes;

      await _guardDirectory(locations.stagingParent);
      await files.createDirectory(locations.stagingParent);
      await _guardDirectory(locations.stagingParent, mustExist: true);
      stage = await files.createStage(locations.stagingParent);
      if (!p.isWithin(locations.stagingParent, stage) ||
          p.dirname(stage) != locations.stagingParent ||
          !p.basename(stage).startsWith('.wp28-u1-')) {
        // Never clean up an injected/out-of-range path.
        stage = null;
        throw const FileSystemException('Invalid staging path');
      }
      await _guardDirectory(stage, mustExist: true);
      final staged = p.join(stage, preferencesName);
      await files.write(staged, bytes);
      await _guardFile(staged);
      final copied = await files.read(staged);
      if (!listEquals(bytes, copied)) {
        throw const FileSystemException('Upgrade copy verification failed');
      }
      decodePreferences(copied);
      // Old builds can still be running under their former mutex identity.
      // Do not publish a snapshot while that file changes underneath us.
      await _guardDirectory(locations.source, mustExist: true);
      await _guardFile(sourceFile);
      if (!listEquals(sourceBytes, await files.read(sourceFile))) {
        throw const FileSystemException('Source changed during upgrade');
      }
      await _guardDirectory(locations.current);
      final raced = await _current(locations);
      if (raced != null) return raced;
      await files.createDirectory(locations.current);
      await _guardDirectory(locations.current, mustExist: true);
      final target = p.join(locations.current, preferencesName);
      try {
        await files.publish(staged, target);
      } catch (_) {
        // Includes an interrupted call AFTER an atomic publish. Whichever
        // file exists is now authoritative; never delete/replace it to retry.
        final committed = await _current(locations);
        if (committed != null) return committed;
        rethrow;
      }
      await _guardFile(target);
      if (!listEquals(bytes, await files.read(target))) {
        return _result(WindowsUpgradeStatus.currentUnreadable, locations);
      }
      return _result(
        WindowsUpgradeStatus.migrated,
        locations,
        credentials: credentials,
        recovery: _protocolDamaged(envelope),
      );
    } catch (_) {
      // Do not surface plugin/IO exceptions: they may contain config text.
      return WindowsUpgradeResult(
        WindowsUpgradeStatus.failed,
        sourcePath: locations?.source,
        currentPath: locations?.current,
      );
    } finally {
      if (stage != null && locations != null) {
        await _cleanOwnedStage(stage, locations);
      }
    }
  }

  /// Mirrors the plugin's JSON envelope, while refusing the empty/scalar files
  /// the plugin would silently read as an empty database. {} is a legal empty
  /// profile. Domain validation remains exclusively with Store on startup.
  static Map<String, Object> decodePreferences(List<int> bytes) {
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, dynamic> ||
        decoded.values.any((value) => value == null)) {
      throw const FormatException('Invalid preferences envelope');
    }
    return Map<String, Object>.from(decoded);
  }

  static bool _protocolDamaged(Map<String, Object> envelope) {
    try {
      SaveProtocol.readCommitted((key) => envelope['flutter.$key']);
      return false;
    } catch (_) {
      return true;
    }
  }

  WindowsUpgradeResult _result(
    WindowsUpgradeStatus status,
    WindowsUpgradePaths locations, {
    bool credentials = false,
    bool noticeRead = false,
    bool recovery = false,
  }) => WindowsUpgradeResult(
    status,
    credentialsNeedSetup: credentials,
    credentialNoticeRead: noticeRead,
    protocolNeedsRecovery: recovery,
    sourcePath: locations.source,
    currentPath: locations.current,
  );

  Future<WindowsUpgradeResult?> _current(WindowsUpgradePaths locations) async {
    await _guardDirectory(locations.current);
    if (await files.type(locations.current) == FileSystemEntityType.notFound) {
      return null;
    }
    final children = await files.children(locations.current);
    if (children.isEmpty) return null;
    for (final child in children) {
      // Store will open these independently after the gate. Do not allow its
      // credential plugin to follow a file alias into another profile either.
      if (p.basename(child) == 'flutter_secure_storage.dat' ||
          p.basename(child).endsWith('.secure')) {
        await _guardFile(child);
      }
    }
    final target = p.join(locations.current, preferencesName);
    if (await files.type(target) == FileSystemEntityType.notFound) {
      return _result(WindowsUpgradeStatus.currentProfile, locations);
    }
    await _guardFile(target);
    Map<String, Object> envelope;
    try {
      envelope = decodePreferences(await files.read(target));
    } catch (_) {
      return _result(WindowsUpgradeStatus.currentUnreadable, locations);
    }
    WindowsCredentialState state;
    try {
      final committed = SaveProtocol.readCommitted(
        (key) => envelope['flutter.$key'],
      );
      state = WindowsCredentialState.read(
        committed?.values,
        (key) => envelope['flutter.$key'],
      );
    } catch (_) {
      return _result(
        WindowsUpgradeStatus.currentProfile,
        locations,
        credentials: envelope[credentialNoticeKey] == true,
        recovery: true,
      );
    }
    return _result(
      WindowsUpgradeStatus.currentProfile,
      locations,
      credentials: state.needsSetup,
      noticeRead: state.noticeRead,
      recovery: _protocolDamaged(envelope),
    );
  }

  Future<bool> _legacyCredentialsExist(WindowsUpgradePaths locations) async {
    await _guardDirectory(locations.source);
    if (await files.type(locations.source) == FileSystemEntityType.notFound) {
      return false;
    }
    // File names only, never contents or Windows Credential Manager entries.
    return (await files.children(locations.source)).any(
      (entry) =>
          p.basename(entry) == 'flutter_secure_storage.dat' ||
          p.basename(entry).endsWith('.secure'),
    );
  }

  Future<void> _guardFile(String path) async {
    await _guardDirectory(p.dirname(path), mustExist: true);
    if (await files.type(path) != FileSystemEntityType.file) {
      throw const FileSystemException('Unsafe upgrade file');
    }
    // Resolve the file too: reject reparse redirection, allowing 8.3 names.
    final canonical = await files.canonicalDirectory(path);
    if (!_samePath(canonical, path)) {
      throw const FileSystemException('Aliased upgrade file');
    }
  }

  Future<void> _guardDirectory(String path, {bool mustExist = false}) async {
    // Walk from the volume root, rejecting links before resolving descendants.
    final absolute = p.absolute(path);
    var part = p.rootPrefix(absolute);
    for (final component in p.split(absolute).skip(1)) {
      part = p.join(part, component);
      final kind = await files.type(part);
      if (kind == FileSystemEntityType.notFound) {
        if (mustExist) throw const FileSystemException('Missing directory');
        return;
      }
      if (kind != FileSystemEntityType.directory ||
          !_samePath(await files.canonicalDirectory(part), part)) {
        throw const FileSystemException('Aliased upgrade directory');
      }
    }
  }

  Future<void> _cleanOwnedStage(
    String stage,
    WindowsUpgradePaths locations,
  ) async {
    try {
      if (p.dirname(stage) != locations.stagingParent ||
          !p.basename(stage).startsWith('.wp28-u1-')) {
        return;
      }
      await _guardDirectory(stage, mustExist: true);
      final staged = p.join(stage, preferencesName);
      if (await files.type(staged) == FileSystemEntityType.file) {
        await _guardFile(staged);
        await files.removeFile(staged);
      }
      // Non-recursive. Unknown entries, aliases, or interrupted prior stages
      // are never swept. Residual stages remain outside the user profile.
      await files.removeDirectory(stage);
    } catch (_) {
      // Cleanup failure must not hide a successful commit or delete user data.
    }
  }
}
