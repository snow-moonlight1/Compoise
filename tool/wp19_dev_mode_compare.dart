// WP19-R headless comparison harness.
//
// Run it by explicit path; the default suite never collects files under
// `tool/` (only `**/*_test.dart`), so this stays out of `flutter test`:
//
//     flutter test --no-pub tool/wp19_dev_mode_compare.dart
//
// Optional: set WP19R_OUT to a directory in this package's private root to
// write the report and the exported experiment state there.
//
// It drives the same fixture the prototype screen uses, prints how the two
// organizations differ, and fails on any invariant the demo claims.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/experiments/wp19_dev_mode/wp19_dev_data.dart';
import 'package:matrixflow_native/experiments/wp19_dev_mode/wp19_dev_model.dart';
import 'package:matrixflow_native/models.dart';

const _productTaskKeys = [
  'id',
  'boardId',
  'title',
  'quadrant',
  'isLongTerm',
  'completed',
  'createdAt',
  'subtasks',
  'urgencyMode',
];

void main() {
  test('wp19-r: ordinary board cannot express what the lens derives', () {
    final session = buildWp19Session();
    final experiment = session.toExperiment();

    // The product model is untouched: no dev field can reach a stored task.
    for (final task in session.tasks) {
      final json = task.toJson();
      for (final forbidden in ['phase', 'blockedBy', 'acceptance']) {
        expect(json.containsKey(forbidden), isFalse, reason: forbidden);
      }
      for (final key in _productTaskKeys) {
        expect(json.containsKey(key), isTrue, reason: key);
      }
    }

    // Ordinary organization: quadrant plus tags. Nothing here says whether a
    // task can be started, and the tags that look like phases are free text.
    final byQuadrant = <int, List<String>>{};
    for (final view in experiment.tasks) {
      byQuadrant.putIfAbsent(view.source.quadrant, () => []).add(view.id);
    }
    final waiting = openTasksWaiting(experiment);
    final inNormalOrder = [
      for (final quadrant in [qDo, qPlan, qDelegate, qEliminate])
        for (final id in byQuadrant[quadrant] ?? const <String>[]) id,
    ];
    expect(inNormalOrder.length, experiment.tasks.length);

    // Development organization: the same rows, ordered by flow, and a start
    // decision the ordinary view simply does not have.
    final inFlowOrder = [
      for (final phase in devPhaseOrder)
        for (final view in experiment.inPhase(phase)) view.id,
      for (final view in experiment.inPhase(null)) view.id,
    ];
    expect(inFlowOrder.toSet(), experiment.tasks.map((v) => v.id).toSet());
    expect(inFlowOrder.contains('r-tag'), isTrue);

    final report = [
      'WP19-R 组织方式对照（同一份合成数据，${experiment.tasks.length} 个任务）',
      '',
      '普通模式（象限 + 标签）看不到依赖；开发视角多出阶段/阻塞/完成三态。',
      '当前等待中的开放任务：${waiting.length} 个',
      for (final view in waiting)
        '  - ${view.source.title}：等待 '
            '${_titles(experiment, experiment.readiness(view).waitingOn)}'
            '${experiment.readiness(view).cycle.isNotEmpty ? '（循环）' : ''}',
      '',
      '普通模式顺序：${_titles(experiment, inNormalOrder)}',
      '开发视角顺序：${_titles(experiment, inFlowOrder)}',
      '',
      '结论：阶段可用现有标签近似，完成标准可塞进备注；只有「谁挡住谁」在现模型里没有落点。',
    ].join('\n');

    stdout.write('$report\n');
    _maybeWrite('compare_report.txt', report);
  });

  test('wp19-r: derived readiness, undo and export invariants', () {
    final experiment = buildWp19Session().toExperiment();
    final pristineFull = buildWp19Session().toExperiment().exportJson();
    final pristine = _withoutSessionNoise(pristineFull);

    DevReadiness reason(String id) =>
        experiment.readiness(experiment.view(id)!);

    // Done tasks report done, not ready.
    expect(reason('r-scope').reason, DevBlockReason.done);
    // Its dependent is still open but its only blocker is complete.
    expect(reason('r-upgrade-doc').reason, DevBlockReason.ready);
    // Two open blockers.
    expect(reason('r-in-place').reason, DevBlockReason.waitingOnBlockers);
    expect(reason('r-in-place').waitingOn, ['r-pipeline', 'r-changelog']);
    // A pointer into another project is a defect, not a cross-project link.
    expect(reason('r-website').unresolved, ['d-water']);
    expect(reason('r-website').reason, DevBlockReason.ready);
    // A two-way wait must never present either side as startable.
    expect(reason('d-refactor').reason, DevBlockReason.inCycle);
    expect(reason('d-tests').reason, DevBlockReason.inCycle);
    expect(reason('d-refactor').cycle, ['d-refactor', 'd-tests']);

    // What finishing the release pipeline unlocks, one step at a time.
    expect(experiment.unlockedBy(['r-pipeline']), ['r-clean-install']);

    // Work the chain: the ship step only becomes startable once its own two
    // blockers are done, not before.
    expect(reason('r-tag').reason, DevBlockReason.waitingOnBlockers);
    for (final id in [
      'r-upgrade-doc',
      'r-pipeline',
      'r-changelog',
      'r-clean-install',
      'r-in-place',
      'r-backup',
    ]) {
      expect(experiment.toggleComplete(id), isTrue, reason: id);
    }
    expect(reason('r-tag').reason, DevBlockReason.ready);
    expect(experiment.view('r-tag')!.done, isFalse);

    // Undo walks the journal back exactly, and the product task objects were
    // never written — the overlay is the only thing that moved.
    while (experiment.intentCount > 0) {
      expect(experiment.undoLast(), isTrue);
    }
    expect(experiment.undoLast(), isFalse);
    expect(
      _withoutSessionNoise(experiment.exportJson()),
      pristine,
      reason: 'full undo must return the seeded session',
    );
    expect(reason('r-tag').reason, DevBlockReason.waitingOnBlockers);
    for (final task in buildWp19Session().tasks) {
      expect(task.completed, equals(_seedCompleted(task.id)), reason: task.id);
    }

    // Batch completion is one intent and reverses as one unit.
    expect(experiment.unlockedBy(['r-pipeline', 'r-changelog']).length, 2);
    expect(experiment.completeBatch(['r-pipeline', 'r-changelog']), isTrue);
    expect(experiment.intentCount, 1);
    expect(reason('r-in-place').reason, DevBlockReason.ready);
    expect(reason('r-clean-install').reason, DevBlockReason.ready);
    expect(experiment.undoLast(), isTrue);
    expect(experiment.intentCount, 0);
    expect(_withoutSessionNoise(experiment.exportJson()), pristine);

    // Removing a task also removes every pointer that named it, and undo puts
    // both the task and the pointers back.
    expect(experiment.removeTask('r-pipeline'), isTrue);
    expect(experiment.view('r-pipeline'), isNull);
    expect(experiment.view('r-clean-install')!.blockedBy, isEmpty);
    expect(experiment.view('r-in-place')!.blockedBy, ['r-changelog']);
    expect(experiment.undoLast(), isTrue);
    expect(experiment.view('r-pipeline'), isNotNull);
    expect(experiment.view('r-clean-install')!.blockedBy, ['r-pipeline']);
    expect(experiment.view('r-in-place')!.blockedBy, ['r-pipeline', 'r-changelog']);
    expect(_withoutSessionNoise(experiment.exportJson()), pristine);

    // Export is deterministic for the same session, and is not a backup.
    expect(
      buildWp19Session().toExperiment().exportJson(),
      equals(pristineFull),
    );
    final state = experiment.exportState();
    expect(state['schema'], DevExperiment.exportSchema);
    for (final forbidden in ['settings', 'aiConfig', 'scheduleItems']) {
      expect(state.containsKey(forbidden), isFalse, reason: forbidden);
    }
    _maybeWrite('export_state.json', const JsonEncoder.withIndent('  ').convert(state));
  });
}

List<DevTaskView> openTasksWaiting(DevExperiment experiment) => [
  for (final view in experiment.openTasks)
    if (experiment.readiness(view).reason != DevBlockReason.ready) view,
];

String _titles(DevExperiment experiment, List<String> ids) => [
  for (final id in ids)
    experiment.view(id)?.source.title ?? id,
].join('、');

/// Completion flags the fixture seeds, so the harness can prove the product
/// task objects were never written.
bool _seedCompleted(String id) => switch (id) {
  'r-scope' => true,
  'd-renew' => true,
  _ => false,
};

/// Drops the two fields that legitimately differ after any interaction, so the
/// remaining export bytes can be compared for a full undo round trip.
String _withoutSessionNoise(String json) {
  final decoded = jsonDecode(json) as Map<String, dynamic>;
  decoded.remove('clockMs');
  decoded.remove('intents');
  return jsonEncode(decoded);
}

void _maybeWrite(String name, String contents) {
  final dir = Platform.environment['WP19R_OUT'];
  if (dir == null || dir.isEmpty) return;
  Directory(dir).createSync(recursive: true);
  File('$dir/$name').writeAsStringSync(contents);
}
