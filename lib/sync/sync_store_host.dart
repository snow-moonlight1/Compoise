/// Connects the app [Store] to the sync engine and controller.
library;

import 'package:flutter/foundation.dart';

import '../storage.dart';
import 'sync_engine.dart';
import 'sync_library.dart';

/// What the controller watches to decide when local edits need syncing.
abstract class SyncLibrarySource implements Listenable {
  /// Changes with every accepted edit.
  int get syncRevision;

  /// The revision the last applied download produced.
  int get syncAppliedRevision;

  /// False while startup recovery or a failed save keeps the library from
  /// being the user's real, saved library. Nothing is stamped or synced then.
  bool get syncLibraryDurable;

  /// Waits for queued saves.
  Future<void> settle();
}

class StoreSyncHost implements SyncHost, SyncLibrarySource {
  StoreSyncHost(this.store);

  final Store store;

  @override
  SyncSnapshot capture() {
    // An unready or recovering store shows a partial library. Stamping it
    // would record every missing task as deleted.
    if (!store.ready || store.hasStartupRecovery) {
      throw StateError('Library is not available for sync');
    }
    return store.captureSyncSnapshot();
  }

  @override
  Future<SyncApplyOutcome> apply(int baseRevision, SyncLibrary library) =>
      store.applySyncLibrary(baseRevision, library);

  @override
  int get syncRevision => store.syncRevision;

  @override
  int get syncAppliedRevision => store.syncAppliedRevision;

  @override
  bool get syncLibraryDurable => store.syncLibraryDurable;

  @override
  Future<void> settle() => store.flush(waitForReminders: false);

  @override
  void addListener(VoidCallback listener) => store.addListener(listener);

  @override
  void removeListener(VoidCallback listener) => store.removeListener(listener);
}
