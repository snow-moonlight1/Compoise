/// The CPU-heavy middle of one sync round, as a pure function.
///
/// The engine downloads the files, then hands everything to
/// [computeSyncRound] on a background isolate: decrypt, merge, derive the new
/// library and seal this device's next upload. The function sees no network,
/// disk or store, so the same input always gives the same output.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'sync_clock.dart';
import 'sync_crypto.dart';
import 'sync_files.dart';
import 'sync_json.dart';
import 'sync_library.dart';
import 'sync_state.dart';

/// Deleted records keep their content this long, so an edit another device
/// made offline can still bring the whole record back. After that only the
/// tombstone stays.
const Duration deletedContentRetention = Duration(days: 30);

class PeerBlob {
  const PeerBlob({
    required this.name,
    required this.version,
    required this.bytes,
  });

  final String name;
  final String version;
  final Uint8List bytes;
}

enum PeerProblem {
  needsKey,
  wrongKeyOrTampered,
  corrupt,
  newerFormat,
  otherVault,
  notEncrypted,
}

class PeerOutcome {
  const PeerOutcome({
    required this.name,
    required this.version,
    this.device,
    this.writtenAt,
    this.problem,
  });

  final String name;
  final String version;
  final SyncDeviceInfo? device;
  final int? writtenAt;
  final PeerProblem? problem;

  bool get ok => problem == null;
}

/// How the live library enters the state at the start of a round.
enum AbsorbMode {
  /// Ordinary round: every difference is a new edit made now.
  edits,

  /// Joining or rebuilding: the library is added with the oldest possible
  /// clock, so whatever the vault already says about a record wins, deleted
  /// records stay deleted, and only records the vault has never seen are new.
  baseline,

  /// "Use the cloud copy": the live library is replaced, not merged.
  none,
}

/// Clock used for [AbsorbMode.baseline]. Any real edit is later.
const int baselineClock = 1;

class SyncRoundInput {
  const SyncRoundInput({
    required this.localState,
    required this.live,
    required this.absorb,
    required this.nowMs,
    required this.peers,
    required this.key,
    required this.encrypted,
    required this.vaultId,
    required this.device,
    required this.uploadedDigest,
    required this.forceUpload,
  });

  /// JSON of the persisted state, or null for a device that has none yet.
  final String? localState;
  final SyncLibrary live;

  /// [AbsorbMode.none] is ignored when the merged state has no board, because
  /// replacing the library with nothing is never what was meant.
  final AbsorbMode absorb;
  final int nowMs;
  final List<PeerBlob> peers;
  final Uint8List? key;
  final bool encrypted;
  final String vaultId;
  final SyncDeviceInfo device;
  final String? uploadedDigest;

  /// Upload even when nothing changed, for example because our file is gone.
  final bool forceUpload;
}

class SyncRoundOutput {
  const SyncRoundOutput({
    required this.state,
    required this.digest,
    required this.derived,
    required this.upload,
    required this.peers,
    required this.recordCount,
    required this.tombstoneCount,
  });

  /// JSON of the new state. Persist it only after [derived] is committed.
  final String state;
  final String digest;

  /// The library to apply, or null when the live library already matches.
  final SyncLibrary? derived;

  /// Sealed device file, or null when the remote copy is already current.
  final Uint8List? upload;
  final List<PeerOutcome> peers;
  final int recordCount;
  final int tombstoneCount;
}

PeerProblem _problemOf(SyncCryptoError kind) => switch (kind) {
  SyncCryptoError.needsKey => PeerProblem.needsKey,
  SyncCryptoError.wrongKeyOrTampered => PeerProblem.wrongKeyOrTampered,
  SyncCryptoError.corrupt => PeerProblem.corrupt,
  SyncCryptoError.unsupported => PeerProblem.newerFormat,
  SyncCryptoError.notEncrypted => PeerProblem.notEncrypted,
};

Future<SyncRoundOutput> computeSyncRound(SyncRoundInput input) async {
  final state = input.localState == null
      ? SyncState()
      : SyncState.fromJson(jsonDecode(input.localState!));
  final clock = HybridClock(last: state.clock, nowMs: () => input.nowMs);
  switch (input.absorb) {
    case AbsorbMode.edits:
      absorbLibrary(state, input.live, clock.tick());
    case AbsorbMode.baseline:
      absorbLibrary(state, input.live, baselineClock);
    case AbsorbMode.none:
      break;
  }

  final outcomes = <PeerOutcome>[];
  for (final peer in input.peers) {
    outcomes.add(await _mergePeer(state, peer, input));
  }

  var derived = deriveLibrary(state);
  if (input.absorb == AbsorbMode.none && derived.boards.isEmpty) {
    // Nothing usable in the vault: keep this device's library after all.
    absorbLibrary(state, input.live, baselineClock);
    derived = deriveLibrary(state);
  }

  final horizon =
      (input.nowMs - deletedContentRetention.inMilliseconds) * clockCounterSpan;
  if (horizon > 0) state.prune(horizon);

  final stateJson = state.encode();
  final digest = SyncState.digestOf(stateJson);
  Uint8List? upload;
  if (input.forceUpload || digest != input.uploadedDigest) {
    final payload = DevicePayload(
      vaultId: input.vaultId,
      device: input.device,
      writtenAt: input.nowMs,
      state: state,
    );
    upload = await sealEnvelope(
      payload.encodeJson(encodedState: stateJson),
      name: deviceFileName(input.device.id),
      key: input.encrypted ? input.key : null,
    );
  }
  return SyncRoundOutput(
    state: stateJson,
    digest: digest,
    derived: libraryMatches(derived, input.live) ? null : derived,
    upload: upload,
    peers: outcomes,
    recordCount: state.records.length,
    tombstoneCount: state.tombstones.length,
  );
}

Future<PeerOutcome> _mergePeer(
  SyncState state,
  PeerBlob peer,
  SyncRoundInput input,
) async {
  PeerOutcome problem(PeerProblem kind) =>
      PeerOutcome(name: peer.name, version: peer.version, problem: kind);
  final Uint8List content;
  try {
    content = await openEnvelope(
      peer.bytes,
      name: peer.name,
      key: input.key,
      requireEncryption: input.encrypted,
    );
  } on SyncCryptoException catch (error) {
    return problem(_problemOf(error.kind));
  }
  final DevicePayload payload;
  try {
    payload = DevicePayload.decodeJson(content);
  } on SyncFileException catch (error) {
    return problem(
      error.newerFormat ? PeerProblem.newerFormat : PeerProblem.corrupt,
    );
  }
  if (payload.vaultId != input.vaultId) return problem(PeerProblem.otherVault);
  if (deviceFileName(payload.device.id) != peer.name) {
    return problem(PeerProblem.corrupt);
  }
  state.mergeFrom(payload.state);
  return PeerOutcome(
    name: peer.name,
    version: peer.version,
    device: payload.device,
    writtenAt: payload.writtenAt,
  );
}

/// True when applying [derived] would not change [live]: same records, and
/// the synced settings already hold on this device.
bool libraryMatches(SyncLibrary derived, SyncLibrary live) {
  final a = derived.flatten()..remove(settingsKey);
  final b = live.flatten()..remove(settingsKey);
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    final theirs = b[entry.key];
    if (theirs == null || !_sameFields(entry.value, theirs)) return false;
  }
  for (final entry in derived.settings.entries) {
    if (!_sameValue(entry.value, live.settings[entry.key])) return false;
  }
  return true;
}

bool _sameFields(Map<String, Object?> a, Map<String, Object?> b) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (!b.containsKey(entry.key) || !_sameValue(entry.value, b[entry.key])) {
      return false;
    }
  }
  return true;
}

bool _sameValue(Object? a, Object? b) => identical(a, b) || sameJson(a, b);

/// Records local edits without touching the network, so each edit is stamped
/// close to when it was made rather than when the device next goes online.
/// Returns the new state JSON, or null when nothing changed.
String? computeAbsorb(String? localState, SyncLibrary live, int nowMs) {
  final state = localState == null
      ? SyncState()
      : SyncState.fromJson(jsonDecode(localState));
  final clock = HybridClock(last: state.clock, nowMs: () => nowMs);
  final changed = absorbLibrary(state, live, clock.tick());
  return changed ? state.encode() : null;
}
