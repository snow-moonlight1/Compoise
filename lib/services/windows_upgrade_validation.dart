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
import 'desktop_shell_service.dart';
import 'single_instance.dart';
import 'windows_data_upgrade.dart';

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
    final actual = await Directory(injected).resolveSymbolicLinks();
    final temp = await Directory.systemTemp.resolveSymbolicLinks();
    if (!p.isWithin(temp, actual) ||
        p.basename(actual) != 'wp28-u2-device-$namespace' ||
        !p.equals(p.normalize(p.absolute(injected)), actual)) {
      throw StateError('Refusing a non-isolated validation root');
    }
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

  Map<String, String> _syntheticValues() => {
    'matrixflow-tasks': jsonEncode([
      Task(
        id: 'synthetic-task',
        boardId: 'synthetic-board',
        title: 'Synthetic task',
        quadrant: 2,
        createdAt: 1,
        plannedDate: 1790812800000,
        deadline: 2000000000000,
        notesMarkdown: 'Synthetic private note',
        subtasks: [SubTask(id: 'synthetic-subtask', title: 'Synthetic child')],
      ).toJson(),
    ]),
    'matrixflow-boards': jsonEncode([
      Board(
        id: 'synthetic-board',
        name: 'Synthetic board',
        createdAt: 1,
      ).toJson(),
    ]),
    'matrixflow-config': jsonEncode(
      AIConfig(model: 'synthetic-model').toJson(includeCredential: false),
    ),
    'matrixflow-settings': jsonEncode(
      AppSettings(language: Language.en, globalShortcut: '').toJson(),
    ),
    'matrixflow-active-board': 'synthetic-board',
    'matrixflow-has-seen-onboarding': 'true',
    SaveProtocol.scheduleKey: jsonEncode([
      ScheduleItem.timeBlock(
        id: 'synthetic-block',
        taskId: 'synthetic-task',
        startAt: 1790812800000,
        endAt: 1790816400000,
        timeZoneId: 'Asia/Shanghai',
      ).toJson(),
    ]),
  };

  Map<String, Object> _envelope(Map<String, String> values) => {
    for (final e in values.entries)
      'flutter.${e.key}': e.key == 'matrixflow-has-seen-onboarding'
          ? e.value == 'true'
          : e.value,
  };

  Future<void> _seed() async {
    if (await File(p.join(root, 'seeded')).exists()) return;
    await Directory(paths.source).create(recursive: true);
    final source = File(
      p.join(paths.source, WindowsDataUpgrade.preferencesName),
    );
    final envelope = _envelope(_syntheticValues());
    if (scenario == 'slots') {
      SharedPreferences.resetStatic();
      SharedPreferencesStorePlatform.instance = SharedPreferencesWindows()
        ..pathProvider = _ValidationPaths(root);
      // Fixture generation happens before the source becomes read-only. Build
      // the two slots with the real protocol, then place that synthetic file.
      final prefs = await SharedPreferences.getInstance();
      final protocol = SaveProtocol(prefs);
      await protocol.commit(_syntheticValues());
      await protocol.commit(_syntheticValues());
      await source.writeAsBytes(
        await File(
          p.join(paths.current, WindowsDataUpgrade.preferencesName),
        ).readAsBytes(),
        flush: true,
      );
      await File(
        p.join(paths.current, WindowsDataUpgrade.preferencesName),
      ).delete();
    } else if (scenario != 'credentials-only') {
      if (scenario == 'corrupt') {
        envelope['flutter.matrixflow-tasks'] = '[broken';
      }
      if (scenario == 'pointer') {
        envelope['flutter.matrixflow-save-pointer'] = 'invalid';
      }
      await source.writeAsString(
        scenario == 'envelope' ? '{broken' : jsonEncode(envelope),
        flush: true,
      );
    }
    await File(
      p.join(paths.source, 'flutter_secure_storage.dat'),
    ).writeAsString('SYNTHETIC_OLD_ENCRYPTED_FILE_NEVER_READ', flush: true);
    if (scenario == 'empty' || scenario == 'current') {
      await Directory(paths.current).create(recursive: true);
      final target = scenario == 'empty'
          ? <String, Object>{}
          : _envelope(
              _syntheticValues()
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
      ).writeAsString(jsonEncode(target), flush: true);
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
    await _report('ready', await _library());
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
    final stage = File(p.join(root, '$name-$pid.stage'));
    await stage.writeAsString(
      jsonEncode({'pid': pid, 'scenario': scenario, ...values}),
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
          final task = Task.fromJson(store!.tasks.single.toJson())
            ..title = 'Synthetic edited task'
            ..plannedDate = 1790899200000;
          store!.updateTask(task);
          final item = store!.scheduleItems.single;
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
    } catch (_) {
      await _report('command-$_lastCommand', {
        'passed': false,
        'failure': 'Isolated validation command failed',
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
