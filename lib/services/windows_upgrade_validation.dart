// Compiled into a usable session only with --dart-define=WP28_U2_HARNESS=true.
// The normal entry point, widgets, Store, shell, plugins and save path remain in
// use. Every diagnostic IO path is rooted in a pre-created synthetic temp root.
// Diagnostic-only injection of the locked plugin's test seams.
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
// ignore: depend_on_referenced_packages
import 'package:path/path.dart' as p;
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_windows/path_provider_windows.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_windows/shared_preferences_windows.dart';
import 'package:window_manager/window_manager.dart';

import '../models.dart';
import '../schedule_item.dart';
import '../storage.dart';
import '../screenshot_import/screenshot_submission.dart';
import 'desktop_shell_service.dart';
import 'single_instance.dart';
import 'windows_data_upgrade.dart';
import 'windows_upgrade_validation_fixture.dart';

class _ValidationPaths extends PathProviderWindows {
  final String root;
  _ValidationPaths(this.root);
  @override
  Future<String> getPath(String folderID) async => root;
}

class WindowsUpgradeValidation {
  final String root;
  final String scenario;
  final pathsKey = GlobalKey();
  final reminders = NoopReminderService();
  late final WindowsUpgradePaths paths = WindowsUpgradePaths(root);
  Store? store;
  WindowsUpgradeResult? prepared;
  List<int>? sourceBefore;
  int activations = 0;
  int notificationActivations = 0;
  int _lastCommand = 0;
  int _preparation = 0;
  bool _commandBusy = false;
  bool _failCopyOnce = false;
  bool _failPointer = false;
  static const _native = MethodChannel('matrixflow/single_instance');

  WindowsUpgradeValidation._(this.root, this.scenario);

  static Future<WindowsUpgradeValidation> open() async {
    if (!Platform.isWindows) throw StateError('Windows validation only');
    final injected = Platform.environment['WP28_U2_ROOT'];
    final namespace = Platform.environment['WP28_U2_NAMESPACE'];
    if (injected == null ||
        namespace == null ||
        !RegExp(
          r'^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$',
        ).hasMatch(namespace)) {
      throw StateError(
        'Explicit isolated validation root and namespace required',
      );
    }
    if (!await Directory(injected).exists()) {
      throw StateError('Validation root must be an existing directory');
    }
    final actual = await Directory(injected).resolveSymbolicLinks();
    final temp = await Directory.systemTemp.resolveSymbolicLinks();
    if (Platform.environment['WP28_U2_RUN'] != '1' ||
        !p.equals(p.dirname(actual), temp) ||
        p.basename(actual) != 'wp28-u2-device-$namespace' ||
        !p.equals(p.normalize(p.absolute(injected)), actual)) {
      throw StateError('Refusing a non-isolated validation root');
    }
    await _checkNative(actual, namespace);
    final request =
        jsonDecode(await File(p.join(actual, 'fixture.json')).readAsString())
            as Map;
    final session = WindowsUpgradeValidation._(
      actual,
      request['scenario'] as String,
    );
    await session._seed();
    final provider = _ValidationPaths(actual);
    final pluginPath = await provider.getApplicationSupportPath();
    if (!p.equals(pluginPath!, session.paths.current)) {
      throw StateError(
        'Compoise exe metadata must retain the production identity',
      );
    }
    PathProviderPlatform.instance = provider;
    SharedPreferences.resetStatic();
    SharedPreferencesStorePlatform.instance = SharedPreferencesWindows()
      ..pathProvider = provider;
    final source = File(
      p.join(session.paths.source, WindowsDataUpgrade.preferencesName),
    );
    if (await source.exists()) {
      session.sourceBefore = await source.readAsBytes();
    }
    Timer.periodic(const Duration(milliseconds: 150), (_) => session._poll());
    return session;
  }

  static Future<Map<String, Object?>> _checkNative(
    String root,
    String namespace,
  ) async {
    final status = await _native.invokeMapMethod<String, Object?>(
      'wp28U2Status',
    );
    if (status == null ||
        status['nativeGate'] != true ||
        status['privateDesktop'] != true ||
        status['foregroundOwned'] != false ||
        status['pid'] != pid ||
        status['root'] != root ||
        status['namespace'] != namespace ||
        status['desktop'] != 'wp28-u2-$namespace') {
      throw StateError('Native desktop isolation was not verified');
    }
    return status;
  }

  Future<bool> write(String key, String value) async {
    if (_failPointer && key == SaveProtocol.pointerKey) return false;
    return (await SharedPreferences.getInstance()).setString(key, value);
  }

  Map<String, String> _syntheticValues() => r2SyntheticValues();

  Map<String, Object> _envelope(Map<String, String> values) => {
    for (final e in values.entries)
      'flutter.${e.key}': e.key == 'matrixflow-has-seen-onboarding'
          ? e.value == 'true'
          : e.value,
  };

  Future<void> _seed() async {
    if (await File(p.join(root, 'seeded')).exists()) return;
    final target = File(
      p.join(paths.current, WindowsDataUpgrade.preferencesName),
    );
    await Directory(paths.current).create(recursive: true);
    if (scenario == 'backup-v3') {
      final empty = _syntheticValues()
        ..['matrixflow-tasks'] = '[]'
        ..[SaveProtocol.scheduleKey] = '[]';
      await target.writeAsString(jsonEncode(_envelope(empty)), flush: true);
      await File(
        p.join(root, 'seeded'),
      ).writeAsString('synthetic', flush: true);
      return;
    }
    final values = _syntheticValues();
    await target.writeAsString(jsonEncode(_envelope(values)), flush: true);
    SharedPreferences.resetStatic();
    SharedPreferencesStorePlatform.instance = SharedPreferencesWindows()
      ..pathProvider = _ValidationPaths(root);
    final seededStore = Store(
      reminders: NoopReminderService(),
      credentialStore: R2SeedCredentials(),
      saveWriter: write,
    );
    try {
      await seededStore.init();
      if (!(await seededStore.flush()).success) throw StateError('Seed failed');
      final prefs = await SharedPreferences.getInstance();
      final before = jsonEncode(r2Library(seededStore));
      final committedBefore = SaveProtocol(prefs).load()!;
      final batch = r2ScreenshotBatch('synthetic-second-board');
      final submitted = batch.snapshot(); // Public detached ImportSubmission.
      var allocated = 0;
      final submission = ScreenshotSubmission(
        batch,
        idFactory: () => 'synthetic-screenshot-${allocated++}',
      );
      _failPointer = true;
      var rejected = false;
      try {
        await submission.commit(seededStore, submitted);
      } on StateError {
        rejected = true;
      }
      final failedBatch = SaveProtocol(prefs).load()!;
      if (!rejected ||
          before != jsonEncode(r2Library(seededStore)) ||
          committedBefore.revision != failedBatch.revision ||
          jsonEncode(committedBefore.values) !=
              jsonEncode(failedBatch.values) ||
          allocated != 2) {
        throw StateError('Screenshot transaction did not roll back');
      }
      _failPointer = false;
      await submission.commit(seededStore, submitted);
      await submission.commit(seededStore, submitted);
      final imported = seededStore.tasks.singleWhere(
        (task) => task.id == 'synthetic-screenshot-0',
      );
      if (allocated != 2 ||
          imported.subtasks.single.id != 'synthetic-screenshot-1' ||
          imported.deadline != null ||
          imported.plannedDate != null ||
          imported.reminderAt != null ||
          !imported.subtasks.single.completed ||
          imported.notesMarkdown != r2DateNotes ||
          imported.subtasks.single.notesMarkdown != r2ChildDateNotes ||
          imported.subtasks.single.deadline != null ||
          imported.subtasks.single.reminderAt != null ||
          jsonEncode(imported.toJson()).contains('synthetic-image')) {
        throw StateError('Screenshot retry changed ids or inferred a date');
      }
      seededStore.addScheduleItem(
        ScheduleItem.timeBlock(
          id: 'synthetic-screenshot-block',
          taskId: imported.id,
          startAt: 1790812800000,
          endAt: 1790816400000,
          timeZoneId: 'Asia/Shanghai',
        ),
      );
      seededStore.addScheduleItem(
        ScheduleItem.event(
          id: 'synthetic-empty-board-event',
          title: 'Independent event on an empty board',
          boardId: 'synthetic-empty-board',
          startAt: 1790812800000,
          endAt: 1790816400000,
          timeZoneId: 'Asia/Tokyo',
        ),
      );
      if (!(await seededStore.flush()).success) {
        throw StateError('Seed save failed');
      }
      values.addAll(SaveProtocol(prefs).load()!.values);
      await _report('screenshot-transaction', {
        'passed': true,
        'publicSubmission': true,
        'ocrLoaded': false,
        'rejectedPointerCommit': rejected,
        'statePreservedOnFailure': true,
        'committedRevisionOnFailure': failedBatch.revision,
        'before': jsonDecode(before),
        'afterFailure': r2LibraryFromValues(failedBatch.values),
        'committedBefore': committedBefore.values,
        'committedAfterFailure': failedBatch.values,
        'stableIds': [imported.id, imported.subtasks.single.id],
        'dateText': r2DateText,
        'childDateText': r2ChildDateText,
        'imported': imported.toJson(),
      });
    } finally {
      _failPointer = false;
      seededStore.dispose();
    }
    final legacy = scenario.startsWith('legacy-');
    if (legacy) values.remove(SaveProtocol.scheduleKey);
    await File(
      p.join(root, 'expected-library.json'),
    ).writeAsString(jsonEncode(r2LibraryFromValues(values)), flush: true);
    await Directory(paths.source).create(recursive: true);
    final source = File(
      p.join(paths.source, WindowsDataUpgrade.preferencesName),
    );
    final envelope = _envelope(values);
    if (scenario == 'slots' ||
        scenario == 'legacy-slots' ||
        scenario == 'slot-schedule-corrupt') {
      if (scenario == 'slot-schedule-corrupt') {
        values[SaveProtocol.scheduleKey] = '[broken';
      }
      SharedPreferences.resetStatic();
      SharedPreferencesStorePlatform.instance = SharedPreferencesWindows()
        ..pathProvider = _ValidationPaths(root);
      // Fixture generation happens before the source becomes read-only. Build
      // the two slots with the real protocol, then place that synthetic file.
      final prefs = await SharedPreferences.getInstance();
      final protocol = SaveProtocol(prefs);
      // Load the real pointer first; don't replace the currently selected slot.
      protocol.load();
      await protocol.commit(values);
      await protocol.commit(values);
      await source.writeAsBytes(
        await File(
          p.join(paths.current, WindowsDataUpgrade.preferencesName),
        ).readAsBytes(),
        flush: true,
      );
    } else if (scenario != 'credentials-only') {
      if (scenario == 'corrupt') {
        envelope['flutter.matrixflow-tasks'] = '[broken';
      }
      if (scenario == 'pointer') {
        envelope['flutter.matrixflow-save-pointer'] = 'invalid';
      }
      if (scenario == 'schedule-corrupt') {
        envelope['flutter.${SaveProtocol.scheduleKey}'] = '[broken';
      }
      await source.writeAsString(
        scenario == 'envelope' ? '{broken' : jsonEncode(envelope),
        flush: true,
      );
    }
    await target.delete();
    await File(
      p.join(paths.source, 'flutter_secure_storage.dat'),
    ).writeAsString('SYNTHETIC_OLD_ENCRYPTED_FILE_NEVER_READ', flush: true);
    if (scenario == 'empty' ||
        scenario == 'current' ||
        scenario == 'current-corrupt') {
      await Directory(paths.current).create(recursive: true);
      final target = scenario == 'empty'
          ? <String, Object>{}
          : _envelope(
              values
                ..['matrixflow-tasks'] = jsonEncode([
                  Task(
                    id: 'synthetic-current',
                    boardId: 'synthetic-board',
                    title: 'Current library wins',
                    quadrant: 1,
                    createdAt: 2,
                  ).toJson(),
                ])
                ..[SaveProtocol.scheduleKey] = '[]',
            );
      await File(
        p.join(paths.current, WindowsDataUpgrade.preferencesName),
      ).writeAsString(
        scenario == 'current-corrupt' ? '{broken' : jsonEncode(target),
        flush: true,
      );
      if (scenario == 'current') {
        await File(
          p.join(root, 'expected-current.json'),
        ).writeAsString(jsonEncode(r2LibraryFromValues(values)), flush: true);
      }
    }
    await File(p.join(root, 'seeded')).writeAsString('synthetic', flush: true);
  }

  WindowsDataUpgrade upgrade() => WindowsDataUpgrade(
    paths: () async => paths,
    files: switch (scenario) {
      'retry' => _FailFirstCopy(this),
      'race' => _RacedPublish(this),
      'concurrent' => _DelayedCopy(this),
      _ => const WindowsUpgradeFiles(),
    },
  );

  Widget wrap(Widget app) => RepaintBoundary(key: pathsKey, child: app);

  void onActivation(List<String> args) {
    activations++;
    if (notificationPayloadFromArguments(args) != null) {
      notificationActivations++;
    }
  }

  Future<WindowsUpgradeResult> prepare() async {
    prepared = await upgrade().prepare();
    await _report('prepared-${++_preparation}', {
      'status': prepared!.status.name,
      'needsSetup': prepared!.credentialsNeedSetup,
      'noticeRead': prepared!.credentialNoticeRead,
      'showNotice': prepared!.showCredentialNotice,
      'recovery': prepared!.protocolNeedsRecovery,
    });
    return prepared!;
  }

  Future<void> onStoreReady(Store value) async {
    store = value;
    if (!value.hasStartupRecovery && !(await value.flush()).success) {
      throw StateError('Isolated Store startup save failed');
    }
    await _report('ready', await _library());
  }

  Future<void> waitForStoreApproval() async {
    // Let the controller measure the published upgrade file before Store can
    // write it. A Windows evidence reader must not hold a deny-write file
    // handle across the real preferences plugin's startup commit.
    final approved = File(p.join(root, 'store-open-approved-$pid'));
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (!await approved.exists()) {
      if (DateTime.now().isAfter(deadline)) {
        throw StateError('Isolated Store approval timed out');
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  Future<Map<String, Object?>> _library() async {
    final currentStore = store;
    final source = File(
      p.join(paths.source, WindowsDataUpgrade.preferencesName),
    );
    final preserved = sourceBefore == null
        ? !await source.exists()
        : (await source.readAsBytes()).join(',') == sourceBefore!.join(',');
    return {
      'sourceUnchanged': preserved,
      'ready': currentStore?.ready,
      'recovery': currentStore?.hasStartupRecovery,
      'needsSetup': currentStore?.windowsCredentialsNeedSetup,
      'noticeRead': currentStore?.windowsCredentialNoticeRead,
      'tasks': currentStore?.tasks.map((t) => t.toJson()).toList(),
      'boards': currentStore?.boards.map((b) => b.toJson()).toList(),
      'schedule': currentStore?.scheduleItems.map((s) => s.toJson()).toList(),
      'config': currentStore?.aiConfig.toJson(includeCredential: false),
      'settings': currentStore?.settings.toJson(),
      'activeBoard': currentStore?.activeBoardId,
      'onboarding': currentStore?.hasSeenOnboarding,
      'activations': activations,
      'notificationActivations': notificationActivations,
    };
  }

  Future<void> _report(String name, Map<String, Object?> values) async {
    final native = await _checkNative(
      root,
      p.basename(root).substring('wp28-u2-device-'.length),
    );
    final stage = File(p.join(root, '$name-$pid.stage'));
    await stage.writeAsString(
      jsonEncode({
        'pid': pid,
        'scenario': scenario,
        'native': native,
        ...values,
      }),
      flush: true,
    );
    await stage.rename(p.join(root, '$name-$pid.json'));
  }

  Future<void> _capture(String name) async {
    await WidgetsBinding.instance.endOfFrame;
    final boundary =
        pathsKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final picture = await boundary.toImage();
    final data = await picture.toByteData(format: ui.ImageByteFormat.png);
    await File(
      p.join(root, '$name-$pid.png'),
    ).writeAsBytes(data!.buffer.asUint8List(), flush: true);
    picture.dispose();
  }

  Future<void> _tap(String label) async {
    Element? found;
    void visit(Element element) {
      if (element.widget is Text && (element.widget as Text).data == label) {
        found = element;
      }
      element.visitChildren(visit);
    }

    WidgetsBinding.instance.rootElement!.visitChildren(visit);
    if (found == null) throw StateError('Expected rendered action missing');
    final box = found!.findRenderObject()! as RenderBox;
    final position = box.localToGlobal(box.size.center(Offset.zero));
    GestureBinding.instance.handlePointerEvent(
      PointerDownEvent(pointer: 91, position: position),
    );
    GestureBinding.instance.handlePointerEvent(
      PointerUpEvent(pointer: 91, position: position),
    );
    await Future<void>.delayed(const Duration(milliseconds: 350));
  }

  Future<void> _poll() async {
    if (_commandBusy) return;
    _commandBusy = true;
    try {
      final file = File(p.join(root, 'request-$pid-${_lastCommand + 1}.json'));
      if (!await file.exists()) return;
      final command = jsonDecode(await file.readAsString()) as Map;
      final id = command['id'] as int;
      if (id <= _lastCommand) return;
      _lastCommand = id;
      final action = command['action'] as String;
      await _capture('ui-$id');
      switch (action) {
        case 'continue':
          await _tap('Continue to app / recovery');
        case 'retry':
          await _tap('Retry upgrade');
        case 'observe':
          break;
        case 'export-backups':
          await File(
            p.join(root, 'backup-v3.json'),
          ).writeAsString(store!.exportJson(), flush: true);
          for (final version in [1, 2]) {
            var loss = -1;
            try {
              store!.exportJson(version: version);
            } on ScheduleExportLossException catch (error) {
              loss = error.lostScheduleItems;
            }
            if (store!.scheduleItems.isNotEmpty &&
                loss != store!.scheduleItems.length) {
              throw StateError('Legacy export did not report schedule loss');
            }
            final result = store!.exportJsonResult(
              version: version,
              allowScheduleLoss: true,
            );
            await File(
              p.join(root, 'backup-v$version.json'),
            ).writeAsString(result.json, flush: true);
            await _report('downgrade-v$version', {
              'ordinaryExportBlocked': loss > 0,
              'lostScheduleItems': result.lostScheduleItems,
              'lossNotice':
                  'Explicit downgrade loses ${result.lostScheduleItems} schedule records; v1 also loses v2 task fields.',
            });
          }
        case 'import-v1':
        case 'import-v2':
        case 'import-v3':
          final backup = ImportPreflight.decode(
            await File(
              p.join(root, 'backup-${action.substring(7)}.json'),
            ).readAsBytes(),
          );
          final plan = store!.previewImport(backup, 'overwrite');
          if (plan.conflicts != 0 ||
              !(await store!.applyImport(plan)).success) {
            throw StateError('Native backup import failed');
          }
          final expectedTasks = (backup['tasks'] as List)
              .map(
                (task) => Task.fromJson(
                  Map<String, dynamic>.from(task as Map),
                ).toJson(),
              )
              .toList();
          if (jsonEncode(expectedTasks) !=
              jsonEncode(store!.tasks.map((task) => task.toJson()).toList())) {
            throw StateError('Native backup task fields differ');
          }
        case 'import-failure-retry':
          final before = r2Library(store!);
          final prefs = await SharedPreferences.getInstance();
          final prior = SaveProtocol(prefs).load()!;
          final payload =
              jsonDecode(store!.exportJson()) as Map<String, dynamic>;
          (payload['tasks'] as List).first['title'] =
              'Synthetic transaction retry';
          final plan = store!.previewImport(payload, 'overwrite');
          _failPointer = true;
          final failed = await store!.applyImport(plan);
          final after = SaveProtocol(prefs).load()!;
          if (failed.success ||
              jsonEncode(before) != jsonEncode(r2Library(store!)) ||
              prior.revision != after.revision ||
              jsonEncode(prior.values) != jsonEncode(after.values)) {
            throw StateError('Native import failure changed committed state');
          }
          await _report('failed-import', {
            'passed': true,
            'commitRejected': true,
            'memoryPreserved': true,
            'committedStatePreserved': true,
            'before': before,
            'after': r2Library(store!),
            'committedBefore': prior.values,
            'committedAfter': after.values,
          });
          _failPointer = false;
          if (!(await store!.applyImport(plan)).success) {
            throw StateError('Native import retry failed');
          }
        case 'configure':
        case 'delete':
          final config =
              AIConfig.fromJson(
                  store!.aiConfig.toJson(includeCredential: false),
                )
                ..apiKey = action == 'configure'
                    ? 'SYNTHETIC_U2_NATIVE_RECONFIGURED_INVALID'
                    : '';
          if (!await store!.updateAIConfig(config)) {
            throw StateError('Synthetic secure configuration failed');
          }
        case 'modify':
          final task = Task.fromJson(store!.tasks.first.toJson())
            ..title = 'Synthetic edited task'
            ..plannedDate = 1790899200000;
          store!.updateTask(task);
          final item = store!.scheduleItems.first;
          if (!store!.updateScheduleItem(
            ScheduleItem.fromJson({
              ...item.toJson(),
              'startAt': item.startAt + 60000,
              'endAt': item.endAt + 60000,
            }),
            expectedRevision: store!.scheduleRevision(item.id),
          )) {
            throw StateError('Synthetic schedule edit failed');
          }
        case 'discard':
          if (!await store!.discardDamagedStartupData()) {
            throw StateError('Recovery choice failed');
          }
        case 'close':
          await _report('exit-requested', {
            'saveComplete': store == null,
            ...await _library(),
          });
          await windowManager.destroy();
        case 'exit':
          final saved = await store!.flush(includeReminderLedger: true);
          await _report('exit-requested', {
            'saveComplete': saved.success,
            'revision': saved.revision,
            ...await _library(),
          });
          if (!saved.success) throw StateError('Exit save incomplete');
          await DesktopShellService.instance.exitApplication();
        default:
          throw StateError('Unknown synthetic command');
      }
      if (store != null && !store!.hasStartupRecovery) {
        final saved = await store!.flush();
        if (!saved.success) throw StateError('Synthetic save incomplete');
      }
      await _report('command-$id', {
        'passed': true,
        'action': action,
        ...await _library(),
      });
    } catch (error, stack) {
      _failPointer = false;
      await _report('command-$_lastCommand', {
        'passed': false,
        'failure': 'Isolated validation command failed: $error',
        'stack': '$stack',
      });
    } finally {
      _commandBusy = false;
    }
  }
}

class _FailFirstCopy extends WindowsUpgradeFiles {
  final WindowsUpgradeValidation session;
  const _FailFirstCopy(this.session);
  @override
  Future<void> write(String path, List<int> bytes) async {
    if (!session._failCopyOnce) {
      session._failCopyOnce = true;
      throw const FileSystemException('Synthetic first copy failure');
    }
    await super.write(path, bytes);
  }
}

class _RacedPublish extends WindowsUpgradeFiles {
  final WindowsUpgradeValidation session;
  const _RacedPublish(this.session);
  @override
  Future<void> publish(String staged, String target) async {
    final values = session._syntheticValues()
      ..['matrixflow-tasks'] = jsonEncode([
        Task(
          id: 'synthetic-current',
          boardId: 'synthetic-board',
          title: 'Current library wins',
          quadrant: 1,
          createdAt: 2,
        ).toJson(),
      ])
      ..[SaveProtocol.scheduleKey] = '[]';
    await File(target).create(exclusive: true);
    await File(
      target,
    ).writeAsString(jsonEncode(session._envelope(values)), flush: true);
    await session._report('raced-current', r2LibraryFromValues(values));
    // Exercise the actual no-replace OS publish failure and production retry.
    await super.publish(staged, target);
  }
}

class _DelayedCopy extends WindowsUpgradeFiles {
  final WindowsUpgradeValidation session;
  const _DelayedCopy(this.session);
  @override
  Future<void> write(String path, List<int> bytes) async {
    await session._report('copy-wait', {'waiting': true});
    await Future<void>.delayed(const Duration(seconds: 3));
    await super.write(path, bytes);
  }
}
