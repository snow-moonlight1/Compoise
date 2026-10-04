/// A minimal transport boundary for optional sync, plus a directory-backed fake.
///
/// The interface states what a real provider must be able to answer before this
/// prototype will accept a write, and the fake proves the engine can live with
/// offline, retry, duplicate delivery, cancellation and corruption. No product
/// network code, no account, no cloud endpoint belongs to this package.
library;

import 'dart:convert';
import 'dart:io';

import 'snapshot.dart';

class TransportCapabilities {
  const TransportCapabilities({
    required this.supportsConditionalPut,
    required this.serverKeepsTombstones,
    required this.supportsChangeFeed,
    required this.maxItemBytes,
    required this.requiresAccount,
    required this.onlineOnly,
  });

  /// A provider that cannot compare a stored digest first would let a late
  /// device silently overwrite a newer one.
  final bool supportsConditionalPut;

  /// Without server-side deletion markers, an absence cannot survive a third
  /// device joining later.
  final bool serverKeepsTombstones;

  /// A per-record change feed is what removes the need to ship the whole
  /// library on every sync.
  final bool supportsChangeFeed;

  final int maxItemBytes;
  final bool requiresAccount;
  final bool onlineOnly;

  static const ideal = TransportCapabilities(
    supportsConditionalPut: true,
    serverKeepsTombstones: true,
    supportsChangeFeed: true,
    maxItemBytes: 8 * 1024 * 1024,
    requiresAccount: false,
    onlineOnly: false,
  );

  Map<String, dynamic> toJson() => {
    'supportsConditionalPut': supportsConditionalPut,
    'serverKeepsTombstones': serverKeepsTombstones,
    'supportsChangeFeed': supportsChangeFeed,
    'maxItemBytes': maxItemBytes,
    'requiresAccount': requiresAccount,
    'onlineOnly': onlineOnly,
  };

  /// Writes a device would otherwise have to guess at.
  List<String> shortfalls() => [
    if (!supportsConditionalPut)
      'no conditional put: a stale device can overwrite a newer snapshot',
    if (!serverKeepsTombstones)
      'no stored deletions: deleted records can come back when a third device '
          'joins',
    if (!supportsChangeFeed)
      'no change feed: every sync ships the whole library',
    if (requiresAccount) 'requires an account: contradicts the current stance',
    if (onlineOnly) 'online only: the app has to keep working offline',
  ];
}

class SyncEnvelopeFile {
  SyncEnvelopeFile({
    required this.snapshotId,
    required this.deviceId,
    required this.digest,
    required this.bytes,
    required this.sequence,
    required this.takenAtMs,
  });

  final String snapshotId;
  final String deviceId;
  final String digest;
  final List<int> bytes;
  final int sequence;
  final int takenAtMs;
}

class PutResult {
  const PutResult({
    required this.stored,
    required this.reason,
    required this.digest,
    this.remoteDigest,
  });

  final bool stored;

  /// stored | duplicate | remote-diverged | oversized | offline | corrupt |
  /// cancelled | unsupported
  final String reason;
  final String digest;
  final String? remoteDigest;

  Map<String, dynamic> toJson() => {
    'stored': stored,
    'reason': reason,
    'digest': digest,
    if (remoteDigest != null) 'remoteDigest': remoteDigest,
  };
}

class PullResult {
  const PullResult({required this.entries, required this.reason});

  final List<SyncEnvelopeFile> entries;
  final String reason;
}

class TransportFault {
  TransportFault({
    this.failNextWrites = 0,
    this.offline = false,
    this.corruptNextWrite = false,
    this.cancelAfterWrite = false,
  });

  /// Writes that fail before touching storage, to exercise retry.
  int failNextWrites;
  bool offline;

  /// Writes garbage bytes once, to exercise the digest check on read.
  bool corruptNextWrite;

  /// Reports the write as cancelled after it landed, to exercise recovery.
  bool cancelAfterWrite;
}

abstract class SyncTransport {
  Future<TransportCapabilities> capabilities();

  /// Publishes one snapshot. When [expectedDigest] is supplied the provider
  /// must reject the write if its current content differs.
  Future<PutResult> put(
    SyncSnapshot snapshot, {
    String? expectedDigest,
    String? operationId,
  });

  Future<PullResult> pull({List<String>? exceptSnapshotIds});

  Future<String?> currentDigest(String deviceId);

  Future<List<String>> listDevices();
}

/// A directory standing in for a provider. Layout:
/// `<root>/remote/<deviceId>/<snapshotId>.json` plus a `HEAD` file naming the
/// newest snapshot per device, and an operation journal for idempotency.
class LocalDirectoryTransport implements SyncTransport {
  LocalDirectoryTransport(this.root, {this.faults, TransportCapabilities? caps})
    : caps = caps ?? TransportCapabilities.ideal,
      remote = Directory('${root.path}${Platform.pathSeparator}remote'),
      journal = File(
        '${root.path}${Platform.pathSeparator}journal.jsonl',
      );

  final Directory root;
  final Directory remote;
  final File journal;
  final TransportCapabilities caps;
  final TransportFault? faults;

  void _ensureLayout() {
    if (!remote.existsSync()) remote.createSync(recursive: true);
  }

  File _headFile(String deviceId) => File(
    '${remote.path}${Platform.pathSeparator}$deviceId.HEAD',
  );

  Directory _snapshotDir(String deviceId) => Directory(
    '${remote.path}${Platform.pathSeparator}$deviceId',
  );

  List<Map<String, dynamic>> _readJournal() {
    if (!journal.existsSync()) return [];
    return [
      for (final line in journal.readAsLinesSync())
        if (line.trim().isNotEmpty)
          Map<String, dynamic>.from(jsonDecode(line) as Map),
    ];
  }

  void _appendJournal(Map<String, dynamic> entry) {
    _ensureLayout();
    journal.writeAsStringSync(
      '${jsonEncode(entry)}\n',
      mode: FileMode.append,
      flush: true,
    );
  }

  @override
  Future<TransportCapabilities> capabilities() async => caps;

  @override
  Future<PutResult> put(
    SyncSnapshot snapshot, {
    String? expectedDigest,
    String? operationId,
  }) async {
    final fault = faults;
    if (fault != null && fault.offline) {
      _appendJournal({
        'op': 'put',
        'device': snapshot.device.deviceId,
        'result': 'offline',
      });
      return PutResult(
        stored: false,
        reason: 'offline',
        digest: snapshot.libraryDigest,
      );
    }
    final text = snapshot.encodeEnvelope();
    final bytes = utf8.encode(text);
    if (bytes.lengthInBytes > caps.maxItemBytes) {
      _appendJournal({
        'op': 'put',
        'device': snapshot.device.deviceId,
        'result': 'oversized',
        'bytes': bytes.lengthInBytes,
      });
      return PutResult(
        stored: false,
        reason: 'oversized',
        digest: snapshot.libraryDigest,
      );
    }
    if (operationId != null) {
      final already = _readJournal().any(
        (entry) => entry['operationId'] == operationId,
      );
      if (already) {
        _appendJournal({
          'op': 'put',
          'device': snapshot.device.deviceId,
          'result': 'duplicate',
          'operationId': operationId,
        });
        return PutResult(
          stored: false,
          reason: 'duplicate',
          digest: snapshot.libraryDigest,
        );
      }
    }
    final current = await currentDigest(snapshot.device.deviceId);
    if (expectedDigest != null &&
        current != null &&
        current != expectedDigest) {
      _appendJournal({
        'op': 'put',
        'device': snapshot.device.deviceId,
        'result': 'remote-diverged',
        'expected': expectedDigest,
        'found': current,
      });
      return PutResult(
        stored: false,
        reason: 'remote-diverged',
        digest: snapshot.libraryDigest,
        remoteDigest: current,
      );
    }
    if (fault != null && fault.failNextWrites > 0) {
      fault.failNextWrites--;
      _appendJournal({
        'op': 'put',
        'device': snapshot.device.deviceId,
        'result': 'write-failed',
      });
      throw const FileSystemException('injected write failure');
    }
    _ensureLayout();
    final dir = _snapshotDir(snapshot.device.deviceId);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final file = File(
      '${dir.path}${Platform.pathSeparator}${snapshot.snapshotId}.wp18',
    );
    if (fault != null && fault.corruptNextWrite) {
      fault.corruptNextWrite = false;
      file.writeAsStringSync(
        text.substring(0, text.length ~/ 2),
        flush: true,
      );
    } else {
      file.writeAsStringSync(text, flush: true);
      _headFile(snapshot.device.deviceId)
          .writeAsStringSync(
            jsonEncode({
              'snapshotId': snapshot.snapshotId,
              'digest': snapshot.libraryDigest,
              'sequence': snapshot.sequence,
              'bytes': bytes.lengthInBytes,
            }),
            flush: true,
          );
    }
    _appendJournal({
      'op': 'put',
      'device': snapshot.device.deviceId,
      'snapshotId': snapshot.snapshotId,
      'digest': snapshot.libraryDigest,
      'result': 'stored',
      if (operationId != null) 'operationId': operationId,
    });
    if (fault != null && fault.cancelAfterWrite) {
      fault.cancelAfterWrite = false;
      throw const TransportCancelled('cancelled after the remote write');
    }
    return PutResult(
      stored: true,
      reason: 'stored',
      digest: snapshot.libraryDigest,
    );
  }

  @override
  Future<String?> currentDigest(String deviceId) async {
    final head = _headFile(deviceId);
    if (!head.existsSync()) return null;
    final decoded = jsonDecode(head.readAsStringSync());
    if (decoded is! Map) return null;
    return decoded['digest'] as String?;
  }

  @override
  Future<List<String>> listDevices() async {
    _ensureLayout();
    return [
      for (final entity in remote.listSync())
        if (entity is Directory) uriToName(entity.uri),
    ]..sort();
  }

  @override
  Future<PullResult> pull({List<String>? exceptSnapshotIds}) async {
    final fault = faults;
    if (fault != null && fault.offline) {
      return const PullResult(entries: [], reason: 'offline');
    }
    _ensureLayout();
    final skip = (exceptSnapshotIds ?? const <String>[]).toSet();
    final out = <SyncEnvelopeFile>[];
    final problems = <String>[];
    for (final deviceId in await listDevices()) {
      final dir = _snapshotDir(deviceId);
      if (!dir.existsSync()) continue;
      final files = dir.listSync().whereType<File>().toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      for (final file in files) {
        final name = uriToName(file.uri);
        if (!name.endsWith('.wp18')) continue;
        final snapshotId = name.substring(0, name.length - '.wp18'.length);
        if (skip.contains(snapshotId)) continue;
        final text = file.readAsStringSync();
        Map<String, dynamic> decoded;
        try {
          decoded = Map<String, dynamic>.from(jsonDecode(text) as Map);
        } on FormatException {
          problems.add('$deviceId/$snapshotId is not valid JSON');
          continue;
        }
        final digest = (decoded['snapshot'] as Map?)?['libraryDigest'];
        final recomputed = _recomputeLibraryDigest(decoded);
        if (digest is String && recomputed != null && digest != recomputed) {
          problems.add(
            '$deviceId/$snapshotId digest mismatch: stored $digest, '
                'recomputed $recomputed',
          );
          continue;
        }
        final bytes = utf8.encode(text);
        if (bytes.length > caps.maxItemBytes) {
          problems.add('$deviceId/$snapshotId exceeds maxItemBytes');
          continue;
        }
        out.add(
          SyncEnvelopeFile(
            snapshotId: snapshotId,
            deviceId: deviceId,
            digest: recomputed ?? 'unverified',
            bytes: bytes,
            sequence:
                ((decoded['snapshot'] as Map?)?['sequence'] as num?)?.toInt() ??
                    0,
            takenAtMs:
                ((decoded['snapshot'] as Map?)?['takenAtMs'] as num?)?.toInt() ??
                    0,
          ),
        );
      }
    }
    return PullResult(
      entries: out,
      reason: problems.isEmpty ? 'ok' : problems.join('; '),
    );
  }

  /// Recomputes the tag from the file's own library and tombstones, so a torn
  /// or edited copy is visible without trusting the header it carries.
  static String? _recomputeLibraryDigest(Map<String, dynamic> envelope) {
    final library = envelope['library'];
    if (library is! Map) return null;
    return SyncSnapshot.digestOf(
      library: library,
      tombstones: envelope['tombstones'] is List ? envelope['tombstones'] : [],
    );
  }

  static String uriToName(Uri uri) {
    final path = uri.toFilePath();
    final trimmed = path.endsWith(Platform.pathSeparator)
        ? path.substring(0, path.length - 1)
        : path;
    final index = trimmed.lastIndexOf(Platform.pathSeparator);
    return index < 0 ? trimmed : trimmed.substring(index + 1);
  }
}

class TransportCancelled implements Exception {
  const TransportCancelled(this.message);

  final String message;

  @override
  String toString() => 'TransportCancelled: $message';
}

/// Pushes a device snapshot with a bounded retry budget. The caller keeps the
/// local library untouched while the push fails, so a partial run is recoverable.
class PushOutcome {
  PushOutcome({
    required this.result,
    required this.attempts,
    required this.lastError,
  });

  final PutResult? result;
  final int attempts;
  final String? lastError;

  bool get delivered => result?.stored == true || result?.reason == 'duplicate';

  Map<String, dynamic> toJson() => {
    'delivered': delivered,
    'attempts': attempts,
    'result': result?.toJson(),
    'lastError': lastError,
  };
}

Future<PushOutcome> pushWithRetry(
  SyncTransport transport,
  SyncSnapshot snapshot, {
  String? expectedDigest,
  String? operationId,
  int maxAttempts = 3,
  bool Function()? cancelled,
}) async {
  PutResult? last;
  String? error;
  for (var attempt = 1; attempt <= maxAttempts; attempt++) {
    if (cancelled?.call() == true) {
      return PushOutcome(
        result: last,
        attempts: attempt,
        lastError: 'cancelled before attempt $attempt',
      );
    }
    try {
      final result = await transport.put(
        snapshot,
        expectedDigest: expectedDigest,
        operationId: operationId,
      );
      last = result;
      if (result.stored ||
          result.reason == 'duplicate' ||
          result.reason == 'remote-diverged' ||
          result.reason == 'oversized') {
        return PushOutcome(result: result, attempts: attempt, lastError: null);
      }
      error = result.reason;
    } on TransportCancelled catch (e) {
      // The remote already holds it. A re-run must see a duplicate, not a gap.
      return PushOutcome(result: null, attempts: attempt, lastError: '$e');
    } catch (e) {
      error = '$e';
    }
  }
  return PushOutcome(result: last, attempts: maxAttempts, lastError: error);
}
