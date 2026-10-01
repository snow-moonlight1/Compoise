import 'dart:convert';
import 'dart:io';

// Locked plugin implementations are deliberately exercised on isolated paths.
// ignore: depend_on_referenced_packages
import 'package:path/path.dart' as p;
// ignore: depend_on_referenced_packages
import 'package:path_provider_windows/path_provider_windows.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_windows/shared_preferences_windows.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/schedule_item.dart';
import 'package:matrixflow_native/services/windows_data_upgrade.dart';

class IsolatedWindowsPathProvider extends PathProviderWindows {
  final String directory;
  IsolatedWindowsPathProvider(this.directory);

  @override
  Future<String?> getApplicationSupportPath() async => directory;
}

/// Native probes retain real exe metadata while replacing the Known Folder
/// root, so path_provider itself can verify Compoise/Compoise in a temp fixture.
class IsolatedRootWindowsPathProvider extends PathProviderWindows {
  final String root;
  IsolatedRootWindowsPathProvider(this.root);
  @override
  Future<String> getPath(String folderID) async => root;
}

Future<SharedPreferences> openIsolatedWindowsPreferences(String path) async {
  SharedPreferences.resetStatic();
  SharedPreferencesStorePlatform.instance = SharedPreferencesWindows()
    ..pathProvider = IsolatedWindowsPathProvider(path);
  return SharedPreferences.getInstance();
}

class UpgradeFixture {
  final Directory root;
  final WindowsUpgradePaths paths;
  UpgradeFixture._(this.root) : paths = WindowsUpgradePaths(root.path);

  static Future<UpgradeFixture> create() async {
    final root = await Directory.systemTemp.createTemp('wp28-u1-test-');
    final fixture = UpgradeFixture._(root);
    await Directory(fixture.paths.source).create(recursive: true);
    return fixture;
  }

  String get sourceFile =>
      p.join(paths.source, WindowsDataUpgrade.preferencesName);
  String get targetFile =>
      p.join(paths.current, WindowsDataUpgrade.preferencesName);

  WindowsDataUpgrade adapter({
    WindowsUpgradeFiles files = const WindowsUpgradeFiles(),
  }) => WindowsDataUpgrade(paths: () async => paths, files: files);

  Future<void> writeSource(Map<String, Object> envelope) =>
      File(sourceFile).writeAsString(jsonEncode(envelope), flush: true);

  Future<void> writeTarget(String text) async {
    await Directory(paths.current).create(recursive: true);
    await File(targetFile).writeAsString(text, flush: true);
  }

  Future<void> dispose() async {
    final temp = await Directory.systemTemp.resolveSymbolicLinks();
    final actual = await root.resolveSymbolicLinks();
    if (!p.isWithin(temp, actual) ||
        !p.basename(actual).startsWith('wp28-u1-test-')) {
      throw StateError('Refuse cleanup outside synthetic temporary fixture');
    }
    await Directory(actual).delete(recursive: true);
  }
}

Map<String, String> syntheticSnapshot({bool schedule = true}) => {
  'matrixflow-tasks': jsonEncode([
    Task(
      id: 'synthetic-task',
      boardId: 'synthetic-board',
      title: 'Synthetic task',
      quadrant: 2,
      createdAt: 1,
      plannedDate: 1790812800000,
      deadline: 2000000000000,
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
  'matrixflow-config': jsonEncode(AIConfig(model: 'synthetic-model').toJson()),
  'matrixflow-settings': jsonEncode(
    AppSettings(language: Language.en).toJson(),
  ),
  'matrixflow-active-board': 'synthetic-board',
  'matrixflow-has-seen-onboarding': 'true',
  if (schedule)
    'matrixflow-schedule': jsonEncode([
      ScheduleItem.timeBlock(
        id: 'synthetic-block',
        taskId: 'synthetic-task',
        startAt: 1790812800000,
        endAt: 1790816400000,
        timeZoneId: 'Asia/Shanghai',
      ).toJson(),
    ]),
};

Map<String, Object> mirrorEnvelope(Map<String, String> values) => {
  for (final entry in values.entries)
    'flutter.${entry.key}': entry.key == 'matrixflow-has-seen-onboarding'
        ? entry.value == 'true'
        : entry.value,
};
