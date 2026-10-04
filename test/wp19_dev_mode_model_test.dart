// WP19-R prototype guards: the isolation boundary the demo claims, plus the
// action rules the headless harness does not cover.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/experiments/wp19_dev_mode/wp19_dev_data.dart';
import 'package:matrixflow_native/experiments/wp19_dev_mode/wp19_dev_model.dart';
import 'package:matrixflow_native/models.dart';

// Anything that could reach the library, the platform, or an AI call.
const _forbiddenFragments = [
  'storage.dart',
  'shared_preferences',
  'flutter_secure_storage',
  'package:provider',
  'window_manager',
  'tray_manager',
  'path_provider',
  'file_picker',
  'backup_export',
  'import_preflight',
  'ai_service',
  'ai_presets',
  'model_discovery',
  'services/',
  'screenshot_import',
  'planner/',
  'reminder',
];

const _experimentDir = 'lib/experiments/wp19_dev_mode';

List<File> _dartFiles(String dir) =>
    Directory(dir).listSync(recursive: true).whereType<File>().where((file) => file.path.endsWith('.dart')).toList()
      ..sort((a, b) => a.path.compareTo(b.path));

Task _task(String id, {String boardId = releaseBoardId, bool completed = false}) =>
  Task(
    id: id,
    boardId: boardId,
    title: '任务 $id',
    quadrant: qDo,
    completed: completed,
    createdAt: 0,
  );

DevExperiment _session(
  List<Task> tasks,
  Map<String, DevFields> fields, {
  List<Board>? boards,
}) => DevExperiment(
  boards: boards ?? [Board(id: releaseBoardId, name: '项目', createdAt: 0)],
  tasks: tasks,
  fields: fields,
  startClockMs: 1000,
);

void main() {
  group('isolation boundary', () {
    test('the experiment cannot reach persistence, platform or AI layers', () {
      final files = _dartFiles(_experimentDir);
      expect(files, isNotEmpty);
      for (final file in files) {
        final imports = [
          for (final line in file.readAsLinesSync())
            if (line.trim().startsWith('import ')) line,
        ];
        for (final line in imports) {
          for (final fragment in _forbiddenFragments) {
            expect(
              line.contains(fragment),
              isFalse,
              reason: '${file.path} imports $fragment: $line',
            );
          }
        }
      }
    });

    test('no product source file references the experiment', () {
      final productFiles = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where(
            (file) =>
                file.path.endsWith('.dart') &&
                !file.path.replaceAll('\\', '/').contains('lib/experiments/'),
          );
      for (final file in productFiles) {
        expect(
          file.readAsStringSync().contains('experiments/wp19_dev_mode'),
          isFalse,
          reason: '${file.path} would pull the prototype into the app',
        );
      }
    });

    test('the normal entry point still builds the product app', () {
      final mainSource = File('lib/main.dart').readAsStringSync();
      expect(mainSource.contains('home: const MatrixHome()'), isTrue);
      expect(mainSource.contains('wp19'), isFalse);
    });
  });

  group('action guards', () {
    test('phase, acceptance and blocker edits reject no-ops', () {
      final experiment = _session(
        [_task('a'), _task('b'), _task('other', boardId: 'p-other')],
        {
          'a': const DevFields(phase: DevPhase.build, acceptance: '可用'),
        },
      );

      expect(experiment.setPhase('a', DevPhase.build), isFalse);
      expect(experiment.setPhase('a', DevPhase.verify), isTrue);
      expect(experiment.view('a')!.phase, DevPhase.verify);
      expect(experiment.setPhase('missing', DevPhase.build), isFalse);

      expect(experiment.setAcceptance('a', '可用'), isFalse);
      expect(experiment.setAcceptance('a', null), isTrue);
      expect(experiment.view('a')!.acceptance, isNull);

      expect(experiment.addBlocker('a', 'a'), isFalse, reason: 'self block');
      expect(experiment.addBlocker('a', 'ghost'), isFalse, reason: 'unknown');
      expect(experiment.addBlocker('a', 'b'), isTrue);
      expect(experiment.addBlocker('a', 'b'), isFalse, reason: 'duplicate');
      expect(experiment.view('a')!.blockedBy, ['b']);
      expect(experiment.removeBlocker('a', 'ghost'), isFalse);
      expect(experiment.removeBlocker('a', 'b'), isTrue);
      expect(experiment.view('a')!.blockedBy, isEmpty);
      // Cross-project pointers are kept but reported, never dropped silently.
      expect(experiment.addBlocker('a', 'other'), isTrue);
      expect(experiment.readiness(experiment.view('a')!).unresolved, ['other']);
      expect(experiment.intentCount, 5);
    });

    test('resetFields drops only this session and restores seeded completion', () {
      final experiment = _session(
        [_task('a', completed: true)],
        {
          'a': const DevFields(phase: DevPhase.design),
        },
      );
      expect(experiment.resetFields('a'), isTrue);
      expect(experiment.view('a')!.phase, isNull);
      expect(experiment.view('a')!.done, isTrue, reason: 'source stays done');

      expect(experiment.resetFields('a'), isFalse, reason: 'already clean');

      experiment.toggleComplete('a');
      expect(experiment.view('a')!.done, isFalse);
      expect(experiment.resetFields('a'), isTrue);
      expect(experiment.view('a')!.done, isTrue);
    });

    test('batch completion skips finished work and records one intent', () {
      final experiment = _session(
        [_task('a'), _task('b'), _task('c', completed: true)],
        {},
      );
      expect(experiment.completeBatch(['a', 'b', 'c']), isTrue);
      expect(experiment.intentCount, 1);
      expect(experiment.journal.single.taskIds, ['a', 'b']);
      expect(experiment.completeBatch(['a', 'b', 'c']), isFalse);
      expect(experiment.journal.single.after['a']!['done'], isTrue);
    });

    test('a three-task wait is reported as a cycle, not as work to do', () {
      final experiment = _session(
        [_task('a'), _task('b'), _task('c')],
        {
          'a': const DevFields(blockedBy: ['b']),
          'b': const DevFields(blockedBy: ['c']),
          'c': const DevFields(blockedBy: ['a']),
        },
      );
      for (final id in ['a', 'b', 'c']) {
        final readiness = experiment.readiness(experiment.view(id)!);
        expect(readiness.reason, DevBlockReason.inCycle, reason: id);
        expect(readiness.cycle.length, 3, reason: id);
      }
      expect(experiment.unlockedBy(['a']), isEmpty);
    });

    test('a wait that loops through finished work is not a deadlock', () {
      final experiment = _session(
        [_task('a'), _task('b'), _task('c', completed: true)],
        {
          'a': const DevFields(blockedBy: ['b']),
          'b': const DevFields(blockedBy: ['c']),
          'c': const DevFields(blockedBy: ['a']),
        },
      );
      // c is done, so b has nothing holding it and a only waits on b.
      expect(experiment.readiness(experiment.view('b')!).reason,
          DevBlockReason.ready);
      final readiness = experiment.readiness(experiment.view('a')!);
      expect(readiness.reason, DevBlockReason.waitingOnBlockers);
      expect(readiness.cycle, isEmpty);
      expect(readiness.waitingOn, ['b']);
    });

    test('unlock preview ignores work that is already startable', () {
      final experiment = _session(
        [_task('a'), _task('b'), _task('free')],
        {
          'b': const DevFields(blockedBy: ['a']),
        },
      );
      experiment.toggleComplete('b');
      final unlocked = experiment.unlockedBy(['a']);
      expect(unlocked, isEmpty, reason: 'the only dependent is already done');

      experiment.toggleComplete('b');
      expect(experiment.unlockedBy(['a']), ['b']);
      expect(experiment.unlockedBy(['free']), isEmpty);
    });

    test('touch count counts sessions that differ from the loaded library', () {
      final experiment = buildWp19Session().toExperiment();
      final seeded = experiment.touchedTaskCount;
      expect(seeded, greaterThan(0));

      experiment.toggleComplete('d-water');
      expect(experiment.touchedTaskCount, greaterThan(seeded));
      experiment.toggleComplete('d-water');
      expect(experiment.touchedTaskCount, seeded);
    });
  });

  group('fixture shape', () {
    test('the synthetic session stays small and deterministic', () {
      final first = buildWp19Session();
      final second = buildWp19Session();
      expect(first.boards.length, 2);
      expect(first.tasks.length, 13);
      expect(
        first.toExperiment().exportJson(),
        equals(second.toExperiment().exportJson()),
      );
      expect(
        first.tasks.map((task) => task.id).toSet().length,
        first.tasks.length,
        reason: 'ids must be unique',
      );
    });

    test('every seeded blocker names a task or is a deliberate defect', () {
      final session = buildWp19Session();
      final ids = session.tasks.map((task) => task.id).toSet();
      final knownDefects = {'d-water'};
      for (final entry in session.fields.entries) {
        for (final blocker in entry.value.blockedBy) {
          expect(
            ids.contains(blocker) || knownDefects.contains(blocker),
            isTrue,
            reason: '${entry.key} -> $blocker',
          );
        }
      }
    });
  });
}
