/// The storage boundary every sync provider implements.
///
/// A remote is one flat folder that only Compoise writes to. The engine needs
/// five operations and nothing else: no rename, no conditional overwrite, no
/// change feed. Each device only ever overwrites its own file, so a provider
/// that offers plain upload and download is enough.
library;

import 'dart:async';
import 'dart:typed_data';

enum SyncRemoteFailure {
  /// No connection, DNS failure, timeout, TLS failure.
  network,

  /// Sign-in expired or the credentials were rejected.
  auth,

  /// The account cannot reach the folder (permissions, wrong path).
  forbidden,

  notFound,

  /// [SyncRemote.create] found an existing file.
  conflict,

  /// The account is out of space.
  quota,

  /// The provider asked us to slow down; see [SyncRemoteException.retryAfter].
  rateLimited,

  /// 5xx or an equivalent temporary provider failure.
  server,

  /// The provider answered with something this client cannot understand.
  protocol,
}

class SyncRemoteException implements Exception {
  const SyncRemoteException(this.kind, [this.message = '', this.retryAfter]);

  final SyncRemoteFailure kind;
  final String message;
  final Duration? retryAfter;

  /// Failures worth retrying later without asking the user.
  bool get isTransient =>
      kind == SyncRemoteFailure.network ||
      kind == SyncRemoteFailure.rateLimited ||
      kind == SyncRemoteFailure.server;

  @override
  String toString() => 'SyncRemoteException(${kind.name}): $message';
}

class RemoteEntry {
  const RemoteEntry({required this.name, required this.version, this.size});

  final String name;

  /// Changes whenever the content changes: an ETag, or modification time plus
  /// size when the provider has no ETag. Only compared for equality.
  final String version;
  final int? size;
}

abstract class SyncRemote {
  /// Short provider label for diagnostics, never shown with secrets.
  String get label;

  /// Files directly in the sync folder. A missing folder lists as empty.
  Future<List<RemoteEntry>> list();

  /// Throws [SyncRemoteFailure.notFound] when [name] does not exist.
  Future<Uint8List> read(String name);

  /// Creates or replaces [name]. Creates the folder when needed.
  Future<void> write(String name, Uint8List bytes);

  /// Like [write] but fails with [SyncRemoteFailure.conflict] when [name]
  /// already exists. Providers without an atomic check may list first; the
  /// engine re-reads the result, so a lost race is still detected.
  Future<void> create(String name, Uint8List bytes);

  /// Removing a missing file succeeds.
  Future<void> delete(String name);
}

/// In-memory remote for tests and the developer lab. Faults can be queued per
/// operation to simulate a flaky provider.
class MemorySyncRemote implements SyncRemote {
  MemorySyncRemote({this.label = 'memory'});

  @override
  final String label;

  final Map<String, Uint8List> files = {};
  final Map<String, int> _versions = {};
  int _counter = 0;

  /// Operation name ('list', 'read', 'write', 'create', 'delete') to the
  /// failures the next calls throw, in order.
  final Map<String, List<SyncRemoteException>> faults = {};

  /// When set, `read` returns only this many leading bytes once, like a
  /// download that raced a half-finished upload.
  int? truncateNextRead;

  final List<String> log = [];

  void failNext(String operation, SyncRemoteException error, {int times = 1}) {
    final queue = faults[operation] ??= [];
    for (var i = 0; i < times; i++) {
      queue.add(error);
    }
  }

  void _maybeFail(String operation, [String? name]) {
    log.add(name == null ? operation : '$operation $name');
    final queue = faults[operation];
    if (queue != null && queue.isNotEmpty) throw queue.removeAt(0);
  }

  @override
  Future<List<RemoteEntry>> list() async {
    _maybeFail('list');
    final names = files.keys.toList()..sort();
    return [
      for (final name in names)
        RemoteEntry(
          name: name,
          version: 'v${_versions[name]}',
          size: files[name]!.length,
        ),
    ];
  }

  @override
  Future<Uint8List> read(String name) async {
    _maybeFail('read', name);
    final bytes = files[name];
    if (bytes == null) {
      throw SyncRemoteException(SyncRemoteFailure.notFound, name);
    }
    final cut = truncateNextRead;
    if (cut != null) {
      truncateNextRead = null;
      return Uint8List.fromList(bytes.sublist(0, cut.clamp(0, bytes.length)));
    }
    return Uint8List.fromList(bytes);
  }

  @override
  Future<void> write(String name, Uint8List bytes) async {
    _maybeFail('write', name);
    files[name] = Uint8List.fromList(bytes);
    _versions[name] = ++_counter;
  }

  @override
  Future<void> create(String name, Uint8List bytes) async {
    _maybeFail('create', name);
    if (files.containsKey(name)) {
      throw SyncRemoteException(SyncRemoteFailure.conflict, name);
    }
    files[name] = Uint8List.fromList(bytes);
    _versions[name] = ++_counter;
  }

  @override
  Future<void> delete(String name) async {
    _maybeFail('delete', name);
    files.remove(name);
    _versions.remove(name);
  }
}
