// WP18-R offline conflict simulator. Pure Dart: it reads v3 backup files (or
// the synthetic scenario catalogue), prints a reviewable conflict plan, applies
// an explicit policy, and writes merged files into a directory the caller
// chooses. It never opens the Store, never writes SharedPreferences, and never
// touches the network. Product entry points are unchanged by this tool.
//
// Usage:
//   dart run tool/wp18_sync_lab.dart list
//   dart run tool/wp18_sync_lab.dart plan <scenario> [--policy P] [--presence M]
//   dart run tool/wp18_sync_lab.dart policies <scenario>
//   dart run tool/wp18_sync_lab.dart catalog
//   dart run tool/wp18_sync_lab.dart files --base A.json --local B.json
//        --peer C.json [--policy P] [--out DIR] [--resolve key=action]
//   dart run tool/wp18_sync_lab.dart transport [--root DIR] [--keep]
import 'dart:convert';
import 'dart:io';

import 'package:matrixflow_native/experiments/wp18_sync/applier.dart';
import 'package:matrixflow_native/experiments/wp18_sync/demo_fixtures.dart';
import 'package:matrixflow_native/experiments/wp18_sync/plan.dart';
import 'package:matrixflow_native/experiments/wp18_sync/planner.dart';
import 'package:matrixflow_native/experiments/wp18_sync/snapshot.dart';
import 'package:matrixflow_native/experiments/wp18_sync/transport.dart';

// Dart io accepts forward slashes on every supported host, so paths here stay readable.

Future<void> main(List<String> args) async {
  final out = stdout;
  if (args.isEmpty) {
    _usage(out);
    exitCode = 64;
    return;
  }
  final command = args.first;
  final flags = _Flags(args.skip(1).toList());
  try {
    switch (command) {
      case 'list':
        _list(out);
      case 'plan':
        _plan(out, flags);
      case 'policies':
        _policies(out, flags);
      case 'catalog':
        _catalog(out);
      case 'files':
        _files(out, flags);
      case 'dump':
        _dump(out, flags);
      case 'transport':
        await _transportDemo(out, flags);
      default:
        _usage(out);
        exitCode = 64;
    }
  } on SimulatorRefused catch (refusal) {
    out.writeln('refused: ${refusal.message}');
    exitCode = 1;
  } on SnapshotFormatException catch (error) {
    out.writeln('refused: ${error.errors.join('; ')}');
    exitCode = 1;
  } catch (error, stack) {
    out.writeln('error: $error');
    out.writeln(stack.toString().split('\n').take(6).join('\n'));
    exitCode = 1;
  }
}

class SimulatorRefused implements Exception {
  const SimulatorRefused(this.message);

  final String message;
}

class _Flags {
  _Flags(this.argv);

  final List<String> argv;

  String? value(String name) {
    final index = argv.indexOf('--$name');
    if (index < 0 || index + 1 >= argv.length) return null;
    return argv[index + 1];
  }

  bool flag(String name) => argv.contains('--$name');

  List<String> many(String name) {
    final out = <String>[];
    for (var i = 0; i < argv.length; i++) {
      if (argv[i] == '--$name' && i + 1 < argv.length) out.add(argv[i + 1]);
    }
    return out;
  }

  String positional(int index) {
    final rest = [
      for (var i = 0; i < argv.length; i++)
        if (!argv[i].startsWith('--') &&
            (i == 0 || !argv[i - 1].startsWith('--')))
          argv[i],
    ];
    if (index >= rest.length) {
      throw SimulatorRefused('missing positional argument ${index + 1}');
    }
    return rest[index];
  }
}

void _usage(Stdout out) {
  out.writeln(
    'wp18_sync_lab <list|plan|policies|catalog|files|transport> [options]\n'
    '  --policy holdPending|preferLocal|preferPeer|fieldwiseAuto|manual\n'
    '  --presence tombstoneAware|presenceOnly\n'
    '  --out DIR   where the merged files and the report are written\n'
    '  --resolve key=action   an explicit human decision on one record\n',
  );
}

void _list(Stdout out) {
  for (final scenario in wp18Scenarios()) {
    out.writeln(
      '${scenario.name}\t${scenario.teaches.replaceAll('\n', ' ')}',
    );
  }
}

ResolutionPolicy _policy(String? name) {
  if (name == null) return ResolutionPolicy.holdPending;
  for (final value in ResolutionPolicy.values) {
    if (value.name == name) return value;
  }
  throw SimulatorRefused('unknown policy "$name"');
}

PresenceModel _presence(String? name) {
  if (name == null) return PresenceModel.tombstoneAware;
  for (final value in PresenceModel.values) {
    if (value.name == name) return value;
  }
  throw SimulatorRefused('unknown presence model "$name"');
}

Map<String, Override> _overrides(List<String> specs) {
  final out = <String, Override>{};
  for (final spec in specs) {
    final parts = spec.split('=');
    if (parts.length != 2) {
      throw SimulatorRefused('bad --resolve "$spec", want key=action');
    }
    final match = Override.values.where((value) => value.name == parts[1]);
    if (match.isEmpty) {
      throw SimulatorRefused('unknown action "${parts[1]}"');
    }
    out[parts[0]] = match.first;
  }
  return out;
}

SyncPlan _planFor(
  ScenarioInput input,
  ResolutionPolicy policy,
  PresenceModel presence,
  Map<String, Override> overrides, {
  SafetyGuards guards = SafetyGuards.standard,
}) {
  final pair = input.pair();
  return ConflictPlanner(
    base: input.baseSnapshot(),
    local: pair.$1,
    peer: pair.$2,
    presence: presence,
    policy: policy,
    guards: guards,
    overrides: overrides,
  ).build();
}

void _plan(Stdout out, _Flags flags) {
  final scenario = _scenarioByName(flags.positional(0));
  out.writeln('# ${scenario.name}');
  out.writeln(scenario.teaches);
  out.writeln('');
  final plan = _planFor(
    scenario.input(),
    _policy(flags.value('policy')),
    _presence(flags.value('presence')),
    _overrides(flags.many('resolve')),
  );
  out.writeln(plan.describe());
  if (scenario.safetyNote != null) {
    out.writeln('safety: ${scenario.safetyNote}');
  }
}

void _policies(Stdout out, _Flags flags) {
  final scenario = _scenarioByName(flags.positional(0));
  final input = scenario.input();
  out.writeln('# ${scenario.name}: one library, five choices');
  out.writeln(scenario.teaches);
  for (final policy in ResolutionPolicy.values) {
    for (var resurrect = 0; resurrect < 2; resurrect++) {
      if (resurrect == 1 &&
          policy != ResolutionPolicy.preferPeer &&
          policy != ResolutionPolicy.preferLocal) {
        continue;
      }
      final plan = _planFor(
        input,
        policy,
        _presence(flags.value('presence')),
        _overrides(flags.many('resolve')),
        guards: SafetyGuards(allowResurrection: resurrect == 1),
      );
      final outcome = MergeApplier(plan).apply();
      out.writeln(
        '  policy=${policy.name.padRight(13)}'
        ' resurrect=${resurrect == 1 ? 'on ' : 'off'}'
        ' auto=${plan.auto.length.toString().padLeft(2)}'
        ' pending=${plan.pending.length.toString().padLeft(2)}'
        ' blocked=${plan.blocked.length.toString().padLeft(2)}'
        ' applied=${outcome.applied.length.toString().padLeft(2)}'
        ' records=${outcome.mergedSnapshot.records.length}'
        ' resurrected=${outcome.resurrected.length}'
        ' clean=${outcome.isClean ? 'yes' : 'no '}',
      );
      for (final decision in plan.pending) {
        out.writeln('      pending ${decision.key} ${decision.reason}');
      }
    }
  }
}

void _catalog(Stdout out) {
  final rows = <List<String>>[];
  var failures = 0;
  for (final scenario in wp18Scenarios()) {
    final input = scenario.input();
    if (scenario.expectLoadError != null) {
      final error = _loadError(input);
      final ok = error != null && error.contains(scenario.expectLoadError!);
      if (!ok) failures++;
      rows.add([
        scenario.name,
        'load',
        ok ? 'ok' : 'MISMATCH',
        error ?? 'no error was raised',
      ]);
      continue;
    }
    final plan = _planFor(
      input,
      ResolutionPolicy.holdPending,
      input.presence,
      const {},
    );
    final outcome = MergeApplier(plan).apply();
    final mismatch = [
      ..._catalogMismatch(scenario, plan),
      ..._selfCheckMismatch(scenario, outcome),
    ];
    if (mismatch.isNotEmpty) failures++;
    rows.add([
      scenario.name,
      '${plan.auto.length}/${plan.pending.length}/${plan.blocked.length}',
      mismatch.isEmpty ? 'ok' : 'MISMATCH',
      mismatch.join('; '),
    ]);
  }
  out.writeln('scenario                     auto/pen/blo status   detail');
  for (final row in rows) {
    out.writeln(
      '${row[0].padRight(28)} ${row[1].padRight(11)} '
          '${row[2].padRight(7)} ${row[3]}',
    );
  }
  out.writeln('');
  out.writeln(
    'scenarios=${rows.length} mismatches=$failures '
        '(0 means the printed catalogue matches every stated expectation)',
  );
  if (failures > 0) exitCode = 1;
}

SyncScenario _scenarioByName(String name) {
  for (final scenario in wp18Scenarios()) {
    if (scenario.name == name) return scenario;
  }
  throw SimulatorRefused('unknown scenario "$name"');
}

String? _loadError(ScenarioInput input) {
  try {
    input.baseSnapshot();
    input.pair();
    return null;
  } on SnapshotFormatException catch (error) {
    return error.errors.join('; ');
  }
}

List<String> _catalogMismatch(SyncScenario scenario, SyncPlan plan) {
  final out = <String>[];
  void check(
    Map<String, String> expected,
    DecisionStatus status,
    String label,
  ) {
    for (final entry in expected.entries) {
      final found = plan.decisions
          .where((decision) => decision.key == entry.key)
          .toList();
      if (found.isEmpty) {
        out.add('$label missing ${entry.key}');
        continue;
      }
      final decision = found.first;
      if (decision.status != status) {
        out.add(
          '${entry.key}: want $label, got ${decision.status.name} '
              '(${decision.reason})',
        );
      } else if (decision.reason != entry.value) {
        out.add('${entry.key}: want reason ${entry.value}, got '
            '${decision.reason}');
      }
    }
  }

  check(scenario.expectAuto, DecisionStatus.auto, 'auto');
  check(scenario.expectPending, DecisionStatus.pending, 'pending');
  check(scenario.expectBlocked, DecisionStatus.blocked, 'blocked');
  for (final warning in scenario.expectWarnings) {
    if (!plan.warnings.any((text) => text.contains(warning))) {
      out.add('warning missing: $warning');
    }
  }
  return out;
}

List<String> _selfCheckMismatch(SyncScenario scenario, MergeOutcome outcome) {
  final expected = scenario.expectSelfCheck ?? const <String>[];
  final got = outcome.selfCheck;
  if (expected.length != got.length) {
    return [
      'selfCheck: got [${got.join('; ')}] expected [${expected.join('; ')}]',
    ];
  }
  for (var i = 0; i < expected.length; i++) {
    if (expected[i] != got[i]) {
      return [
        'selfCheck: got [${got.join('; ')}] expected [${expected.join('; ')}]',
      ];
    }
  }
  return const [];
}

/// Writes one scenario's three snapshots out as real files, so a person can
/// open them, edit them, and feed them back through the `files` command.
void _dump(Stdout out, _Flags flags) {
  final scenario = _scenarioByName(flags.positional(0));
  final dir = flags.value('out');
  if (dir == null) throw SimulatorRefused('dump needs --out DIR');
  final root = Directory(dir)..createSync(recursive: true);
  final input = scenario.input();
  final pair = input.pair();
  final three = <String, SyncSnapshot>{
    'base': input.baseSnapshot(),
    'local': pair.$1,
    'peer': pair.$2,
  };
  for (final entry in three.entries) {
    final name = '${scenario.name}-${entry.key}';
    File('${root.path}/$name.envelope.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(entry.value.toEnvelope()),
      flush: true,
    );
    File('${root.path}/$name.v3.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(entry.value.toV3Payload()),
      flush: true,
    );
  }
  out.writeln(
    'wrote ${scenario.name} as base/local/peer envelope and plain v3 files '
        'under ${root.path}',
  );
  out.writeln(
    'replay them: dart run tool/wp18_sync_lab.dart files '
        '--base ${root.path}/${scenario.name}-base.envelope.json '
        '--local ${root.path}/${scenario.name}-local.envelope.json '
        '--peer ${root.path}/${scenario.name}-peer.envelope.json '
        '--out ${root.path}/merged',
  );
}

/// Reads real files: two snapshots plus the baseline they share.
void _files(Stdout out, _Flags flags) {
  final base = _readSnapshot(flags.value('base'), 'base');
  final local = _readSnapshot(flags.value('local'), 'local');
  final peer = _readSnapshot(flags.value('peer'), 'peer');
  final plan = ConflictPlanner(
    base: base,
    local: local,
    peer: peer,
    presence: _presence(flags.value('presence')),
    policy: _policy(flags.value('policy')),
    overrides: _overrides(flags.many('resolve')),
  ).build();
  final outcome = MergeApplier(plan).apply();
  out.writeln(plan.describe());
  out.writeln(outcome.describe());
  final dir = flags.value('out');
  if (dir == null) {
    out.writeln('(no --out DIR: nothing was written)');
    if (!outcome.isClean) exitCode = 1;
    return;
  }
  final root = Directory(dir)..createSync(recursive: true);
  File('${root.path}/wp18_plan.json')
      .writeAsStringSync(plan.encodeJson(), flush: true);
  File('${root.path}/wp18_plan.md')
      .writeAsStringSync(plan.describe(), flush: true);
  File('${root.path}/wp18_merged.v3.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(outcome.mergedV3),
    flush: true,
  );
  File('${root.path}/wp18_merged.envelope.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(outcome.mergedEnvelope),
    flush: true,
  );
  out.writeln(
    'written under ${root.path}: wp18_plan.json, wp18_plan.md, '
        'wp18_merged.v3.json, wp18_merged.envelope.json',
  );
  if (!outcome.isClean) exitCode = 1;
}

SyncSnapshot _readSnapshot(String? path, String label) {
  if (path == null) throw SimulatorRefused('--$label FILE is required');
  final file = File(path);
  if (!file.existsSync()) throw SimulatorRefused('$label file is missing');
  final decoded = jsonDecode(file.readAsStringSync());
  if (decoded is! Map) throw SimulatorRefused('$label is not a JSON object');
  final map = Map<String, dynamic>.from(decoded);
  if (map['envelope'] == SyncSnapshot.envelopeTag) {
    return SyncSnapshot.fromEnvelope(map);
  }
  // A plain backup carries no device identity, so the tool labels it by role
  // and gives every record the same clock. That is the honest limit of reading
  // hand-made files: see the presenceOnly notes in docs/WP18_R_NOTES.md.
  return SyncSnapshot.fromV3(
    payload: map,
    device: DeviceIdentity(
      deviceId: 'file-$label',
      label: 'File ($label)',
      zoneOffsetMinutes: 0,
    ),
    snapshotId: '$label-plain',
    sequence: 1,
  );
}

/// Drives a two-device round trip through the directory transport, including
/// the injected faults, and prints the operation journal.
Future<void> _transportDemo(Stdout out, _Flags flags) async {
  final keep = flags.flag('keep');
  final provided = flags.value('root');
  final root = provided == null
      ? Directory.systemTemp.createTempSync('wp18-r-transport-')
      : Directory(provided)..createSync(recursive: true);
  out.writeln('transport root: ${root.path}');
  final faults = TransportFault();
  final transport = LocalDirectoryTransport(root, faults: faults);
  final pair = _scenarioByName('add-on-peer-only').input().pair();
  final local = pair.$1;
  final peer = pair.$2;
  final failures = <String>[];

  Future<void> step(String label, Future<void> Function() body) async {
    try {
      await body();
      out.writeln('  $label: ok');
    } catch (error) {
      failures.add('$label: $error');
      out.writeln('  $label: FAILED $error');
    }
  }

  await step('offline push', () async {
    faults.offline = true;
    final result = await pushWithRetry(transport, local, maxAttempts: 2);
    faults.offline = false;
    out.writeln(
      '      attempts=${result.attempts} reason=${result.result?.reason}',
    );
    if (result.delivered) throw StateError('an offline push delivered data');
  });

  await step('peer push then pull', () async {
    await transport.put(peer, operationId: 'op-peer');
    final pulled = await transport.pull(
      exceptSnapshotIds: [local.snapshotId],
    );
    out.writeln('      entries=${pulled.entries.length} ${pulled.reason}');
    if (pulled.entries.isEmpty) throw StateError('the peer copy was not pulled');
  });

  await step('duplicate delivery', () async {
    final replay = await transport.put(peer, operationId: 'op-peer');
    out.writeln('      replay=${replay.reason}');
    if (replay.reason != 'duplicate') throw StateError('a replay was not a no-op');
  });

  await step('conditional put', () async {
    final diverged = await transport.put(
      peer,
      expectedDigest: 'not-the-current-digest',
      operationId: 'op-conditional',
    );
    out.writeln('      reason=${diverged.reason}');
    if (diverged.stored) throw StateError('a stale write was accepted');
  });

  await step('retry then succeed', () async {
    faults.failNextWrites = 1;
    final result = await pushWithRetry(
      transport,
      local,
      maxAttempts: 3,
      operationId: 'op-retry',
    );
    out.writeln(
      '      delivered=${result.delivered} attempts=${result.attempts}',
    );
    if (!result.delivered) throw StateError('the retry never landed');
  });

  await step('cancel mid flight', () async {
    faults.cancelAfterWrite = true;
    Object? caught;
    try {
      await transport.put(local, operationId: 'op-cancel');
    } catch (error) {
      caught = error;
    }
    out.writeln('      thrown=$caught');
    if (caught == null) throw StateError('the cancellation was not reported');
    final replay = await transport.put(local, operationId: 'op-cancel');
    out.writeln('      replay=${replay.reason}');
    if (replay.reason != 'duplicate') throw StateError('a replay duplicated data');
  });

  await step('corrupt remote copy', () async {
    final devices = await transport.listDevices();
    if (devices.isEmpty) throw StateError('no device on the remote');
    final dir = Directory('${root.path}/remote/${devices.first}');
    final files = dir
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.wp18'))
        .toList();
    if (files.isEmpty) throw StateError('no snapshot stored for the device');
    final stored = files.first;
    // The edit keeps the file valid JSON and only changes the library, so the
    // content tag is the only thing that can catch it.
    final decoded = Map<String, dynamic>.from(
      jsonDecode(stored.readAsStringSync()) as Map,
    );
    final envelopeLibrary = decoded['library'];
    if (envelopeLibrary is Map) {
      final tasks = envelopeLibrary['tasks'];
      if (tasks is List && tasks.isNotEmpty && tasks.first is Map) {
        (tasks.first as Map)['title'] = 'silently retitled';
      }
    }
    stored.writeAsStringSync(jsonEncode(decoded), flush: true);
    final pulled = await transport.pull(exceptSnapshotIds: const []);
    out.writeln('      pulled=${pulled.entries.length} ${pulled.reason}');
    if (!pulled.reason.contains('digest mismatch')) {
      throw StateError('a torn copy was not detected');
    }
  });

  await step('oversized item', () async {
    final capped = LocalDirectoryTransport(
      root,
      caps: const TransportCapabilities(
        supportsConditionalPut: true,
        serverKeepsTombstones: true,
        supportsChangeFeed: false,
        maxItemBytes: 64,
        requiresAccount: false,
        onlineOnly: false,
      ),
    );
    final result = await capped.put(local);
    out.writeln('      reason=${result.reason}');
    if (result.stored) throw StateError('an oversized payload was accepted');
  });

  final caps = await transport.capabilities();
  out.writeln('capabilities: ${jsonEncode(caps.toJson())}');
  for (final shortfall in const TransportCapabilities(
    supportsConditionalPut: false,
    serverKeepsTombstones: false,
    supportsChangeFeed: false,
    maxItemBytes: 1024,
    requiresAccount: true,
    onlineOnly: true,
  ).shortfalls()) {
    out.writeln('  provider gap: $shortfall');
  }
  final journal = File('${root.path}/journal.jsonl');
  if (journal.existsSync()) {
    out.writeln('journal:');
    for (final line in journal.readAsLinesSync()) {
      out.writeln('  $line');
    }
  }
  out.writeln('transport failures: ${failures.length}');
  if (failures.isNotEmpty) exitCode = 1;
  if (keep) {
    out.writeln('kept the root for inspection');
  } else {
    root.deleteSync(recursive: true);
    out.writeln('removed the temporary root (pass --keep to inspect it)');
  }
}
