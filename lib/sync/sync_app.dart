/// Production wiring: files under the app support folder, system secure
/// storage, the app lifecycle and diagnostics logging.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';

import '../app_version.dart';
import '../diagnostics/app_log.dart';
import '../storage.dart';
import 'sync_controller.dart';
import 'sync_engine.dart';
import 'sync_local.dart';
import 'sync_provider.dart';
import 'sync_store_host.dart';

/// Builds the app's sync controller for [store]. It starts a moment after the
/// library is ready and startup recovery is resolved, so a recovering library
/// is never stamped.
SyncController createAppSyncController(
  Store store, {
  required Directory supportDirectory,
}) {
  final localStore = FileSyncLocalStore(
    Directory('${supportDirectory.path}${Platform.pathSeparator}sync'),
  );
  final secrets = SyncSecrets.system();
  final host = StoreSyncHost(store);
  final engine = SyncEngine(
    host: host,
    localStore: localStore,
    keyStore: CredentialSyncKeyStore(secrets.vaultKey),
    deviceName: defaultSyncDeviceName(),
    platform: Platform.operatingSystem,
    appVersion: appVersion,
  );
  final controller = SyncController(
    engine: engine,
    source: host,
    localStore: localStore,
    secrets: secrets,
  );

  var lastLogged = '';
  void logStatus() {
    final status = engine.status;
    final line = '${status.phase.name}/${status.issue?.name ?? '-'}';
    if (line == lastLogged || status.phase == SyncPhase.syncing) return;
    lastLogged = line;
    if (status.phase == SyncPhase.error ||
        status.phase == SyncPhase.needsAttention) {
      AppLog.warn('sync', 'Status $line');
    } else {
      AppLog.info('sync', 'Status $line');
    }
  }

  engine.addListener(logStatus);

  final lifecycle = AppLifecycleListener(
    onStateChange: (state) => controller.setForeground(
      state == AppLifecycleState.resumed || state == AppLifecycleState.inactive,
    ),
  );

  Timer? startTimer;
  void maybeStart() {
    if (!store.ready || store.hasStartupRecovery) return;
    store.removeListener(maybeStart);
    // After the first frames: reading secure storage can block the UI
    // thread on Linux while the keyring asks to be unlocked.
    startTimer = Timer(const Duration(seconds: 2), () {
      controller.start().catchError((Object error) {
        AppLog.warn('sync', 'Start failed: ${error.runtimeType}');
      });
    });
  }

  store.addListener(maybeStart);
  maybeStart();

  controller.onDispose(() {
    startTimer?.cancel();
    store.removeListener(maybeStart);
    engine.removeListener(logStatus);
    lifecycle.dispose();
  });
  return controller;
}
