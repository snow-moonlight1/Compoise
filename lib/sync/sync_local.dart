/// What one device remembers about its sync vault, kept apart from the task
/// library's own slots (docs/sync.md). Losing these files never loses tasks:
/// the next round treats the library as new local edits and merges it again.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'sync_files.dart';

enum SyncJoinMode {
  /// This device created the vault.
  create,

  /// Keep this device's library and merge it into the vault; vault settings
  /// win on the first round.
  merge,

  /// Replace this device's library with the vault's.
  replaceLocal,
}

class SyncPeerRecord {
  const SyncPeerRecord({
    required this.version,
    this.device,
    this.writtenAt,
    this.problem,
  });

  final String version;
  final SyncDeviceInfo? device;
  final int? writtenAt;

  /// Name of a [PeerProblem] when the file could not be read.
  final String? problem;

  Map<String, dynamic> toJson() => {
    'version': version,
    if (device != null) 'device': device!.toJson(),
    if (writtenAt != null) 'writtenAt': writtenAt,
    if (problem != null) 'problem': problem,
  };

  static SyncPeerRecord? fromJson(Object? json) {
    if (json is! Map || json['version'] is! String) return null;
    SyncDeviceInfo? device;
    try {
      if (json['device'] != null) {
        device = SyncDeviceInfo.fromJson(json['device']);
      }
    } on SyncFileException {
      device = null;
    }
    return SyncPeerRecord(
      version: json['version'] as String,
      device: device,
      writtenAt: json['writtenAt'] is int ? json['writtenAt'] as int : null,
      problem: json['problem'] is String ? json['problem'] as String : null,
    );
  }
}

class SyncLocalMeta {
  SyncLocalMeta({
    required this.deviceId,
    this.provider,
    this.vaultId,
    this.encrypted = false,
    this.joinMode,
    this.uploadedDigest,
    this.lastSuccessAt,
    Map<String, SyncPeerRecord>? peers,
  }) : peers = peers ?? <String, SyncPeerRecord>{};

  /// Stable per installation; names this device's file.
  final String deviceId;

  /// Which transport the vault lives on, for example `webdav`.
  String? provider;
  String? vaultId;
  bool encrypted;

  /// Set until the first round after joining has committed.
  SyncJoinMode? joinMode;
  String? uploadedDigest;
  int? lastSuccessAt;

  /// Peer device files by name.
  final Map<String, SyncPeerRecord> peers;

  bool get joined => vaultId != null;

  static String newDeviceId({Random? random}) {
    final source = random ?? Random.secure();
    const alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return List.generate(
      20,
      (_) => alphabet[source.nextInt(alphabet.length)],
    ).join();
  }

  Map<String, dynamic> toJson() => {
    'format': 1,
    'deviceId': deviceId,
    'provider': provider,
    'vaultId': vaultId,
    'encrypted': encrypted,
    'joinMode': joinMode?.name,
    'uploadedDigest': uploadedDigest,
    'lastSuccessAt': lastSuccessAt,
    'peers': {
      for (final entry in peers.entries) entry.key: entry.value.toJson(),
    },
  };

  /// Returns null for anything unreadable; the caller starts over with a new
  /// device id, which is safe because the library itself is untouched.
  static SyncLocalMeta? fromJson(Object? json) {
    if (json is! Map || json['format'] != 1) return null;
    final deviceId = json['deviceId'];
    if (deviceId is! String || !isValidSyncId(deviceId)) return null;
    final vaultId = json['vaultId'];
    final joinName = json['joinMode'];
    final peers = <String, SyncPeerRecord>{};
    final rawPeers = json['peers'];
    if (rawPeers is Map) {
      for (final entry in rawPeers.entries) {
        final record = SyncPeerRecord.fromJson(entry.value);
        if (entry.key is String && record != null) {
          peers[entry.key as String] = record;
        }
      }
    }
    return SyncLocalMeta(
      deviceId: deviceId,
      provider: json['provider'] is String ? json['provider'] as String : null,
      vaultId: vaultId is String && isValidSyncId(vaultId) ? vaultId : null,
      encrypted: json['encrypted'] == true,
      joinMode: SyncJoinMode.values
          .where((mode) => mode.name == joinName)
          .firstOrNull,
      uploadedDigest: json['uploadedDigest'] is String
          ? json['uploadedDigest'] as String
          : null,
      lastSuccessAt: json['lastSuccessAt'] is int
          ? json['lastSuccessAt'] as int
          : null,
      peers: peers,
    );
  }
}

/// Persistence for [SyncLocalMeta], the merged state, and the state a round
/// is about to commit ("pending"), so a crash between the library commit and
/// the state write does not re-stamp merged records as local edits.
abstract class SyncLocalStore {
  Future<SyncLocalMeta?> loadMeta();
  Future<void> saveMeta(SyncLocalMeta meta);
  Future<String?> loadState();

  /// Null removes the file.
  Future<void> saveState(String? json);
  Future<String?> loadPending();
  Future<void> savePending(String? json);
}

class MemorySyncLocalStore implements SyncLocalStore {
  String? meta;
  String? state;
  String? pending;
  int writes = 0;

  /// Makes the next state write throw, like a full disk.
  bool failNextStateWrite = false;

  @override
  Future<SyncLocalMeta?> loadMeta() async =>
      meta == null ? null : SyncLocalMeta.fromJson(jsonDecode(meta!));

  @override
  Future<void> saveMeta(SyncLocalMeta value) async {
    writes++;
    meta = jsonEncode(value.toJson());
  }

  @override
  Future<String?> loadState() async => state;

  @override
  Future<void> saveState(String? json) async {
    if (failNextStateWrite) {
      failNextStateWrite = false;
      throw const FileSystemException('disk full');
    }
    writes++;
    state = json;
  }

  @override
  Future<String?> loadPending() async => pending;

  @override
  Future<void> savePending(String? json) async {
    writes++;
    pending = json;
  }
}

/// Files under `<app support>/sync/`. Every write goes to a temporary file
/// that is flushed and renamed over the old one.
class FileSyncLocalStore implements SyncLocalStore {
  FileSyncLocalStore(this.directory);

  final Directory directory;

  File _file(String name) => File('${directory.path}/$name');

  Future<String?> _read(String name) async {
    final file = _file(name);
    try {
      return await file.readAsString();
    } on PathNotFoundException {
      return null;
    }
  }

  Future<void> _write(String name, String? content) async {
    final file = _file(name);
    if (content == null) {
      try {
        await file.delete();
      } on PathNotFoundException {
        // Already gone.
      }
      return;
    }
    await directory.create(recursive: true);
    final temp = _file('$name.tmp');
    final handle = await temp.open(mode: FileMode.write);
    try {
      await handle.writeString(content);
      await handle.flush();
    } finally {
      await handle.close();
    }
    await temp.rename(file.path);
  }

  @override
  Future<SyncLocalMeta?> loadMeta() async {
    final raw = await _read('sync-meta.json');
    if (raw == null) return null;
    try {
      return SyncLocalMeta.fromJson(jsonDecode(raw));
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> saveMeta(SyncLocalMeta meta) =>
      _write('sync-meta.json', jsonEncode(meta.toJson()));

  @override
  Future<String?> loadState() => _read('sync-state.json');

  @override
  Future<void> saveState(String? json) => _write('sync-state.json', json);

  @override
  Future<String?> loadPending() => _read('sync-pending.json');

  @override
  Future<void> savePending(String? json) => _write('sync-pending.json', json);
}
