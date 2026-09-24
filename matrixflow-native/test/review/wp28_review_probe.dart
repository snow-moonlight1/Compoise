// Review probes: assert required behavior, intentionally fail on baseline 3a711c8.
// Filename deliberately does not end in _test.dart: run this probe explicitly.
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/storage.dart';
import 'package:matrixflow_native/task_stats.dart';
import 'package:matrixflow_native/screens/matrix_screen.dart';
import 'package:matrixflow_native/screens/settings_screen.dart';
import 'package:matrixflow_native/ai_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:matrixflow_native/widgets/task_detail_panel.dart';
import '../helpers.dart';

class RecordingPlugin implements FlutterLocalNotificationsPlugin {
  RecordingPlugin({this.android, this.failScheduling = false});
  final AndroidFlutterLocalNotificationsPlugin? android;
  final bool failScheduling;
  final List<Symbol> calls = [];
  final Completer<bool?> initialization = Completer<bool?>();
  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls.add(invocation.memberName);
    if (invocation.memberName == #initialize) return initialization.future;
    if (invocation.memberName == #resolvePlatformSpecificImplementation) return android;
    if (invocation.memberName == #zonedSchedule && failScheduling) {
      return Future<void>.error(StateError('Synthetic schedule failure'));
    }
    return Future<void>.value();
  }
}

class DiscoveryAI extends AIService {
  final pending = Completer<List<String>>();
  @override
  Future<List<String>> fetchModels({required AIConfig config, bool forceRefresh = false,
    AICancellation? cancellation}) => pending.future;
}

class DeniedReminder extends InMemoryReminderService {
  int requestCount = 0;
  @override
  Future<ReminderPermissionStatus> probePermission() async => ReminderPermissionStatus.denied;
  @override
  Future<ReminderPermissionStatus> requestPermission() async { requestCount++; return ReminderPermissionStatus.denied; }
}

Task sample(String id, {int q = 1, List<SubTask>? subs}) => Task(
  id: id, boardId: 'b', title: id, quadrant: q, createdAt: 1, subtasks: subs,
);

Future<Store> seeded(List<Task> tasks) async {
  final (store, _) = await makeStore(
    boards: [Board(id: 'b', name: 'Synthetic board', createdAt: 1)], tasks: tasks,
  );
  addTearDown(store.dispose);
  return store;
}

Widget app(Store store, Widget child) => ChangeNotifierProvider.value(
  value: store,
  child: MaterialApp(
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    supportedLocales: const [Locale('en'), Locale('zh'), Locale('ja')],
    home: child,
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => ReminderService.resetForTest(InMemoryReminderService()));
  tearDown(() => ReminderService.resetForTest());

  testWidgets('R01 switching desktop details must not overwrite task B with task A', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 950));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = await seeded([sample('Alpha'), sample('Beta')]);
    await tester.pumpWidget(app(store, const MatrixHome()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alpha').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Beta').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('save-task')));
    await tester.pumpAndSettle();
    expect(store.tasks.firstWhere((t) => t.id == 'Beta').title, 'Beta');
  });

  testWidgets('R02 editing quadrant in details must put moved task first', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 1300));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = await seeded([sample('Existing', q: 2), sample('Moving')]);
    await tester.pumpWidget(app(store, Scaffold(body: TaskDetailPanel(
      task: store.tasks.last, isSidebar: true, onClose: () {},
    ))));
    await tester.pumpAndSettle();
    final chip = find.widgetWithText(ChoiceChip, store.t['q2']!);
    await tester.ensureVisible(chip);
    await tester.tap(chip);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('save-task')));
    await tester.pumpAndSettle();
    expect(store.tasksIn(2).first.id, 'Moving');
  });

  testWidgets('R03 checking a child on its card must record completedAt', (tester) async {
    final store = await seeded([sample('Parent', subs: [SubTask(id: 's', title: 'Child')])]);
    await tester.pumpWidget(app(store, const MatrixHome()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('expand-Parent')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('task-subtask-check-s')));
    await tester.pumpAndSettle();
    expect(store.tasks.single.subtasks.single.completed, isTrue);
    expect(store.tasks.single.subtasks.single.completedAt, isNotNull);
  });

  test('R04 removing a child must cancel its scheduled notification', () async {
    final service = ReminderService.instance as InMemoryReminderService;
    final store = await seeded([sample('Parent', subs: [SubTask(
      id: 's', title: 'Child', reminderAt: DateTime.now().millisecondsSinceEpoch + 3600000,
    )])]);
    await Future<void>.delayed(Duration.zero);
    expect(service.scheduled, isNotEmpty);
    store.updateTask(Task.fromJson(store.tasks.single.toJson())..subtasks = []);
    expect(service.scheduled, isEmpty);
  });

  test('R05 undo must not overwrite a subsequent child completion command', () async {
    final store = await seeded([sample('Parent', subs: [
      SubTask(id: 's1', title: 'One'), SubTask(id: 's2', title: 'Two'),
    ])]);
    final undo = store.toggleCompleteWithUndo(store.tasks.single)!;
    var task = Task.fromJson(store.tasks.single.toJson());
    task.subtasks.first.completed = false;
    store.updateTask(task);
    task = Task.fromJson(store.tasks.single.toJson());
    task.subtasks.first.completed = true;
    store.updateTask(task);
    expect(store.applyUndo(undo), isFalse);
  });

  test('R06 corrupt overwrite payload must not silently erase existing tasks', () async {
    final store = await seeded([sample('Keep me')]);
    try {
      store.importData({
        'version': 2,
        'boards': [store.boards.single.toJson()],
        'tasks': [{'title': 'Missing required id'}],
      }, 'overwrite');
    } on FormatException { /* Safe rejection is acceptable. */ }
    expect(store.tasks.map((t) => t.id), contains('Keep me'));
  });

  test('R07 grouping must preserve existing completion timestamps', () async {
    final completed = sample('Done')..completed = true..completedAt = 12345;
    final store = await seeded([completed, sample('Pending')]);
    final grouped = store.groupTasks(['Done', 'Pending'], 'Group');
    expect(grouped.subtasks.firstWhere((s) => s.title == 'Done').completedAt, 12345);
  });

  test('R08 child completion history must not require completed parent', () {
    final now = DateTime.now();
    final task = sample('Pending', subs: [SubTask(
      id: 's', title: 'Done child', completed: true, completedAt: now.millisecondsSinceEpoch,
    )]);
    final history = computeCompletionHistoryStats(tasks: [task], now: now);
    expect(history.dailyBuckets.fold<int>(0, (n, b) => n + b.subtaskCount), 1);
  });

  test('R09 completed unknown-date task must not acquire invented completion date', () async {
    final store = await seeded([sample('Legacy')..completed = true]);
    store.setParentCompleted(store.tasks.single, true);
    expect(store.tasks.single.completedAt, isNull);
  });

  testWidgets('R10 system back must protect a text-only unsaved draft', (tester) async {
    final store = await seeded([sample('Original')]);
    await tester.pumpWidget(app(store, const MatrixHome()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Original').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('edit-title')), 'Unsaved');
    await tester.pump();
    final context = tester.element(find.byType(TaskDetailPanel));
    Navigator.of(context).maybePop();
    await tester.pumpAndSettle();
    expect(find.byType(TaskDetailPanel), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets('R11 saving notes must not reverse externally completed child', (tester) async {
    final store = await seeded([sample('Parent', subs: [SubTask(id: 's', title: 'Child')])]);
    await tester.pumpWidget(app(store, Scaffold(body: TaskDetailPanel(
      task: store.tasks.single, isSidebar: true, onClose: () {},
    ))));
    await tester.pumpAndSettle();
    store.setParentCompleted(store.tasks.single, true);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('save-task')));
    await tester.pumpAndSettle();
    expect(store.tasks.single.subtasks.single.completed, isTrue);
  });

  testWidgets('R12 slow notification init must not drop startup rescheduling', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final plugin = RecordingPlugin();
    final service = FlutterLocalNotificationsReminderService(plugin: plugin);
    final init = service.init(onNotificationSelected: (_) {});
    final task = sample('Future')..reminderAt = DateTime.now().millisecondsSinceEpoch + 3600000;
    await service.rescheduleAllFuture([task]);
    plugin.initialization.complete(true);
    await init;
    await tester.pump();
    final count = plugin.calls.where((s) => s == #zonedSchedule).length;
    await service.cancelAll();
    expect(count, 1);
  });

  testWidgets('R13 Windows scheduling must choose one delivery mechanism', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final plugin = RecordingPlugin();
    final service = FlutterLocalNotificationsReminderService(plugin: plugin);
    service.setInitializedForTest(true);
    await service.scheduleReminder(boardId: 'b', taskId: 't', title: 'Synthetic',
      triggerAtMs: DateTime.now().millisecondsSinceEpoch + 1000);
    await tester.pump(const Duration(seconds: 2));
    final deliveries = plugin.calls.where((s) => s == #zonedSchedule || s == #show).length;
    await service.cancelAll();
    expect(deliveries, 1);
  });

  testWidgets('R14 cancelling while Android permission check awaits must win', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    const channel = MethodChannel('dexterous.com/flutter/local_notifications');
    final pendingPermission = Completer<bool>();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'canScheduleExactNotifications') return pendingPermission.future;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
    final plugin = RecordingPlugin(android: AndroidFlutterLocalNotificationsPlugin());
    final service = FlutterLocalNotificationsReminderService(plugin: plugin)..setInitializedForTest(true);
    final pending = service.scheduleReminder(boardId: 'b', taskId: 't', title: 'Synthetic',
      triggerAtMs: DateTime.now().millisecondsSinceEpoch + 3600000);
    await tester.pump();
    await service.cancelReminder('t');
    pendingPermission.complete(true);
    await pending;
    debugDefaultTargetPlatformOverride = null;
    expect(plugin.calls.where((m) => m == #zonedSchedule), isEmpty);
  });

  testWidgets('R15 switching provider during discovery must clear loading state', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({'matrixflow-has-seen-onboarding': true});
    final ai = DiscoveryAI();
    final store = Store(aiService: ai);
    await store.init();
    addTearDown(store.dispose);
    store.updateAIConfig(AIConfig(apiKey: 'synthetic-not-a-secret'));
    await tester.pumpWidget(app(store, const SettingsScreen()));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('refresh-models-btn')));
    await tester.tap(find.byKey(const ValueKey('refresh-models-btn')));
    await tester.pump();
    tester.widget<DropdownButton<String>>(find.byKey(const ValueKey('provider-selector')))
      .onChanged!('bailian');
    await tester.pump();
    ai.pending.complete(['old-provider-model']);
    await tester.pump();
    expect(find.byKey(const ValueKey('refresh-models-btn')), findsOneWidget);
  });

  testWidgets('R16 custom providers must retain the thinking control', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 2500));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = await seeded([]);
    store.updateAIConfig(AIConfig(provider: 'custom', protocol: AIProtocol.anthropic));
    await tester.pumpWidget(app(store, const SettingsScreen()));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('thinking-switch')), findsOneWidget);
  });

  testWidgets('R17 narrow focused quadrant must handle large system text', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = await seeded([sample('Task')]);
    store.updateSettings((s) => s..language = Language.zh);
    await tester.pumpWidget(app(store, MediaQuery(
      data: const MediaQueryData(size: Size(360, 800), textScaler: TextScaler.linear(2.32)),
      child: const MatrixHome(),
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('quadrant-header-1')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('R18 checkbox must respond throughout its advertised 48dp target', (tester) async {
    final store = await seeded([sample('Target')]);
    await tester.pumpWidget(app(store, const MatrixHome()));
    await tester.pumpAndSettle();
    final center = tester.getCenter(find.byKey(const ValueKey('complete-Target')));
    await tester.tapAt(center + const Offset(18, 0));
    await tester.pumpAndSettle();
    expect(store.tasks.single.completed, isTrue);
  });


  testWidgets('R20 first reminder must ask for notification permission', (tester) async {
    final service = DeniedReminder();
    ReminderService.instance = service;
    final store = await seeded([sample('Reminder')]);
    await tester.binding.setSurfaceSize(const Size(1000, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(app(store, Scaffold(body: TaskDetailPanel(
      task: store.tasks.single, isSidebar: true, onClose: () {},
    ))));
    await tester.pumpAndSettle();
    final quick = find.byKey(const ValueKey('reminder-quick-tomorrow-9'));
    await tester.ensureVisible(quick);
    await tester.tap(quick);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('save-task')));
    await tester.pumpAndSettle();
    expect(store.tasks.single.reminderAt, isNotNull);
    expect(service.requestCount, 1);
  });

  testWidgets('R21 failed scheduling must not show a future reminder immediately', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final plugin = RecordingPlugin(failScheduling: true);
    final service = FlutterLocalNotificationsReminderService(plugin: plugin)..setInitializedForTest(true);
    await service.scheduleReminder(boardId: 'b', taskId: 't', title: 'Future',
      triggerAtMs: DateTime.now().millisecondsSinceEpoch + 86400000);
    debugDefaultTargetPlatformOverride = null;
    expect(plugin.calls.where((m) => m == #show), isEmpty);
  });
}
