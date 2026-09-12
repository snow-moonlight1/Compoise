import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/ai_service.dart';
import 'package:matrixflow_native/main.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/screens/matrix_screen.dart';
import 'package:matrixflow_native/screens/search_screen.dart';
import 'package:matrixflow_native/screens/settings_screen.dart';
import 'package:matrixflow_native/storage.dart';
import 'package:matrixflow_native/theme.dart';
import 'package:matrixflow_native/widgets/anim.dart';
import 'package:matrixflow_native/widgets/input_sheet.dart';
import 'package:matrixflow_native/widgets/quadrant_focus_view.dart';
import 'package:matrixflow_native/widgets/quadrant_pane.dart';
import 'package:matrixflow_native/widgets/task_card.dart';
import 'package:matrixflow_native/widgets/task_detail_panel.dart';
import 'package:matrixflow_native/widgets/task_list_view.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ControlledAI extends AIService {
  Completer<List<AIAnalysisResult>> analysis = Completer();
  Completer<List<DecomposeResult>> decomposition = Completer();
  Future<List<String>> Function({
    required AIConfig config,
    bool forceRefresh,
    AICancellation? cancellation,
  })? onFetchModels;

  @override
  Future<List<String>> fetchModels({
    required AIConfig config,
    bool forceRefresh = false,
    AICancellation? cancellation,
  }) async {
    if (onFetchModels != null) {
      return onFetchModels!(
        config: config,
        forceRefresh: forceRefresh,
        cancellation: cancellation,
      );
    }
    return super.fetchModels(
      config: config,
      forceRefresh: forceRefresh,
      cancellation: cancellation,
    );
  }

  @override
  Future<List<AIAnalysisResult>> analyzeTasks({
    required List<String> inputs,
    required AIConfig config,
    required Language language,
    required bool autoDecompose,
    AICancellation? cancellation,
  }) => analysis.future;
  @override
  Future<List<DecomposeResult>> decomposeBatch({
    required List<String> taskTitles,
    required AIConfig config,
    required Language language,
    AICancellation? cancellation,
  }) => decomposition.future;
}

class TestPicker extends FilePicker {
  Uint8List? savedBytes;
  bool failPick = false;
  Uint8List? incoming;
  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    savedBytes = bytes;
    return null;
  }

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    if (failPick) throw StateError('picker failed');
    return incoming == null
        ? null
        : FilePickerResult([
          PlatformFile(
            name: 'backup.json',
            size: incoming!.length,
            bytes: incoming,
          ),
        ]);
  }
}

Future<Store> setup(
  WidgetTester tester, {
  AIService? ai,
  List<Locale>? deviceLocales,
  Map<String, Object>? initialPrefs,
}) async {
  SharedPreferences.setMockInitialValues(initialPrefs ?? {});
  late Store store;
  await tester.runAsync(() async {
    store = Store(aiService: ai, deviceLocales: deviceLocales);
    await store.init();
    await store.flush();
  });
  addTearDown(store.dispose);
  return store;
}

Widget app(Store store, Widget home, {double scale = 1}) =>
    ChangeNotifierProvider.value(
      value: store,
      child: MaterialApp(
        theme: buildTheme(
          Brightness.light,
          store.settings.themeColor,
          fontFamilyPref: store.settings.fontFamily,
        ),
        locale: Locale(store.settings.language.name),
        supportedLocales: const [Locale('en'), Locale('zh'), Locale('ja')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        builder:
            (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: CombinedTextScaler(
                  TextScaler.linear(scale),
                  fontScaleFactor(store.settings.fontSize),
                ),
              ),
              child: child!,
            ),
        home: home,
      ),
    );

void viewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  setUp(() => FilePicker.platform = TestPicker());
  testWidgets(
    'export passes UTF-8 bytes to Android picker and cancel shows no backup dialog',
    (tester) async {
      final store = await setup(tester);
      store.addTasks([store.newTask('备份任务')]);
      final original = FilePicker.platform;
      final picker = TestPicker();
      FilePicker.platform = picker;
      addTearDown(() => FilePicker.platform = original);
      await tester.pumpWidget(app(store, const SettingsScreen()));
      await tester.scrollUntilVisible(
        find.text('Export JSON'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Export JSON'));
      await tester.pumpAndSettle();
      final json = jsonDecode(utf8.decode(picker.savedBytes!));
      expect(json['tasks'][0]['title'], '备份任务');
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(SelectableText), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('file picker exception is shown and import can be retried', (
    tester,
  ) async {
    final store = await setup(tester);
    final original = FilePicker.platform;
    final picker = TestPicker()..failPick = true;
    FilePicker.platform = picker;
    addTearDown(() => FilePicker.platform = original);
    await tester.pumpWidget(app(store, const SettingsScreen()));
    await tester.scrollUntilVisible(
      find.text('Import JSON'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Import JSON'));
    await tester.pumpAndSettle();
    expect(find.text('Invalid data format.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    final button = tester.widget<OutlinedButton>(
      find
          .ancestor(
            of: find.text('Import JSON'),
            matching: find.byWidgetPredicate(
              (widget) => widget is OutlinedButton,
            ),
          )
          .first,
    );
    expect(button.onPressed, isNotNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'overwrite import reads bytes without path and refreshes visible AI fields',
    (tester) async {
      final store = await setup(tester);
      final original = FilePicker.platform;
      final picker =
          TestPicker()
            ..incoming = Uint8List.fromList(
              utf8.encode(
                jsonEncode({
                  'version': 1,
                  'boards': [
                    {'id': 'import', 'name': 'Imported'},
                  ],
                  'tasks': [],
                  'aiConfig': {
                    'customBaseUrl': 'https://new.example.test',
                    'customModel': 'new-model',
                  },
                }),
              ),
            );
      FilePicker.platform = picker;
      addTearDown(() => FilePicker.platform = original);
      await tester.pumpWidget(app(store, const SettingsScreen()));
      await tester.scrollUntilVisible(
        find.text('Import JSON'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Import JSON'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Overwrite All'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(store.aiConfig.baseUrl, 'https://new.example.test');
      await tester.scrollUntilVisible(
        find.text('new-model'),
        -250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('https://new.example.test'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'ordinary swipe scrolls tasks; long press moves to another quadrant',
    (tester) async {
      viewport(tester, const Size(500, 900));
      final store = await setup(tester);
      store.addTasks([for (var i = 0; i < 12; i++) store.newTask('Task $i')]);
      await tester.pumpWidget(app(store, const MatrixHome()));
      await tester.pumpAndSettle();
      await tester.drag(find.text('Task 0'), const Offset(0, -220));
      await tester.pumpAndSettle();
      expect(store.tasks.every((task) => task.quadrant == qDo), isTrue);
      expect(find.text('Task 0').hitTestable(), findsNothing);
      final list = find.byType(ListView).first;
      await tester.drag(list, const Offset(0, 1200));
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Task 0')),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await gesture.moveTo(
        tester.getCenter(find.text('Not Urgent but Important')) +
            const Offset(0, 80),
      );
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(store.tasks.first.quadrant, qPlan);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('AI error keeps input and re-enables submit', (tester) async {
    final ai = ControlledAI();
    final store = await setup(tester, ai: ai);
    await tester.pumpWidget(
      app(
        store,
        const Scaffold(
          body: InputSheet(
            initialMode: InputModePref.brainDump,
            embedded: true,
          ),
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey('task-input')),
      'do not lose this',
    );
    await tester.tap(find.byKey(const ValueKey('submit-tasks')));
    await tester.pump();
    ai.analysis.completeError(const AIException('aiInvalidResponse'));
    await tester.pumpAndSettle();
    expect(find.text('do not lose this'), findsOneWidget);
    expect(store.tasks, isEmpty);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('submit-tasks')))
          .onPressed,
      isNotNull,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'AI automatic decomposition never asks to split its steps as a group',
    (tester) async {
      final ai = ControlledAI();
      final store = await setup(tester, ai: ai);
      store.settings.autoDecomposeAI = true;
      await tester.pumpWidget(
        app(
          store,
          const Scaffold(
            body: InputSheet(
              initialMode: InputModePref.brainDump,
              embedded: true,
            ),
          ),
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('task-input')),
        'project',
      );
      await tester.tap(find.byKey(const ValueKey('submit-tasks')));
      await tester.pump();
      ai.analysis.complete([
        AIAnalysisResult(
          title: 'project',
          quadrant: qPlan,
          isLongTerm: true,
          subtasks: ['step'],
        ),
      ]);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(store.tasks.single.subtasks.single.title, 'step');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('mobile AI result opens decomposition from live home context', (
    tester,
  ) async {
    viewport(tester, const Size(390, 844));
    final ai = ControlledAI();
    final store = await setup(tester, ai: ai);
    store.settings.defaultInputMode = InputModePref.brainDump;
    await tester.pumpWidget(app(store, const MatrixHome()));
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('task-input')), 'project');
    await tester.tap(find.byKey(const ValueKey('submit-tasks')));
    await tester.pump();
    ai.analysis.complete([
      AIAnalysisResult(title: 'project', quadrant: qPlan, isLongTerm: true),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('Review Long-Term Tasks'), findsOneWidget);
    expect(find.byType(InputSheet), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  for (final language in Language.values) {
    testWidgets(
      '320px matrix with long titles, children and ${language.name} text scaling',
      (tester) async {
        viewport(tester, const Size(320, 700));
        final store = await setup(tester);
        store.settings.language = language;
        store.renameBoard(
          store.activeBoardId,
          'A very long board name 很长的任务板标题',
        );
        store.addTasks([
          for (final q in allQuadrants)
            store.newTask('Long task title 长任务タイトル', quadrant: q)
              ..isLongTerm = true
              ..subtasks = [
                SubTask(id: newId(), title: 'Long child title 子任务タイトル'),
              ],
        ]);
        await tester.pumpWidget(app(store, const MatrixHome(), scale: 1.5));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets('320px settings ${language.name} do not overflow', (
      tester,
    ) async {
      viewport(tester, const Size(320, 700));
      final store = await setup(tester);
      store.settings.language = language;
      await tester.pumpWidget(app(store, const SettingsScreen(), scale: 1.5));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.drag(find.byType(ListView), const Offset(0, -1300));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('keyboard input sheet has one inset and reachable submit', (
    tester,
  ) async {
    viewport(tester, const Size(360, 640));
    final store = await setup(tester);
    await tester.pumpWidget(app(store, const MatrixHome()));
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.enterText(
      find.byKey(const ValueKey('task-input')),
      'first\nsecond',
    );
    await tester.ensureVisible(find.byKey(const ValueKey('submit-tasks')));
    await tester.pumpAndSettle();
    expect(
      tester.getBottomRight(find.byKey(const ValueKey('submit-tasks'))).dy,
      lessThanOrEqualTo(340),
    );
    await tester.tap(find.byKey(const ValueKey('submit-tasks')));
    await tester.pumpAndSettle();
    expect(store.tasks, hasLength(2));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('selection selects cards, groups and Back exits selection', (
    tester,
  ) async {
    viewport(tester, const Size(390, 844));
    final store = await setup(tester);
    final a = store.newTask('alpha');
    final b = store.newTask('beta', quadrant: qPlan);
    store.addTasks([a, b]);
    await tester.pumpWidget(app(store, const MatrixHome()));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Multi-select'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('alpha'));
    await tester.tap(find.text('beta'));
    await tester.pumpAndSettle();
    expect(a.completed, isFalse);
    expect(b.completed, isFalse);
    final alphaCard = find.ancestor(
      of: find.text('alpha'),
      matching: find.byType(TaskCard),
    );
    expect(
      tester
          .widget<Checkbox>(
            find.descendant(of: alphaCard, matching: find.byType(Checkbox)),
          )
          .value,
      isFalse,
    );
    await tester.tap(find.text('Group (2)'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'combined');
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(store.tasks.single.title, 'combined');
    expect(store.tasks.single.subtasks, hasLength(2));
    await tester.tap(find.byTooltip('Multi-select'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byTooltip('Multi-select'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('embedded AI submits repeatedly and keeps original board', (
    tester,
  ) async {
    viewport(tester, const Size(1200, 800));
    final ai = ControlledAI();
    final store = await setup(tester, ai: ai);
    store.settings.suppressLongTermPrompt = true;
    final originalBoard = store.activeBoardId;
    await tester.pumpWidget(
      app(
        store,
        const Scaffold(
          body: InputSheet(
            initialMode: InputModePref.brainDump,
            embedded: true,
          ),
        ),
      ),
    );
    await tester.enterText(find.byKey(const ValueKey('task-input')), 'first');
    await tester.tap(find.byKey(const ValueKey('submit-tasks')));
    await tester.pump();
    store.createBoard('second board');
    ai.analysis.complete([AIAnalysisResult(title: 'first', quadrant: qDo)]);
    await tester.pumpAndSettle();
    expect(store.tasks.single.boardId, originalBoard);
    ai.analysis = Completer();
    await tester.enterText(find.byKey(const ValueKey('task-input')), 'second');
    await tester.tap(find.byKey(const ValueKey('submit-tasks')));
    await tester.pump();
    ai.analysis.complete([AIAnalysisResult(title: 'second', quadrant: qDo)]);
    await tester.pumpAndSettle();
    expect(store.tasks, hasLength(2));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'closing decomposition ignores delayed errors and does not pop home',
    (tester) async {
      final ai = ControlledAI();
      final store = await setup(tester, ai: ai);
      store.addTasks([store.newTask('long task', isLongTerm: true)]);
      await tester.pumpWidget(app(store, const MatrixHome()));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.call_split));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      ai.decomposition.completeError(const AIException('aiInvalidResponse'));
      await tester.pumpAndSettle();
      expect(find.byType(MatrixHome), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(store.tasks.single.subtasks, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  Widget pumpTaskCard(
    Store store,
    Task task, {
    bool selecting = false,
    bool selected = false,
    VoidCallback? onSelect,
  }) => app(
    store,
    Scaffold(
      body: TaskCard(
        task: task,
        entranceIndex: 0,
        onChanged: () {},
        onEdit: () {},
        onDelete: () {},
        onDecompose: () {},
        onDecomposeStart: () {},
        selecting: selecting,
        selected: selected,
        onSelect: onSelect,
      ),
    ),
  );

  testWidgets(
    'complete checkbox stays completed in multi-select even when the row is unselected',
    (tester) async {
      final store = await setup(tester);
      final task = store.newTask('already done')..completed = true;
      store.addTasks([task]);
      await tester.pumpWidget(
        pumpTaskCard(store, task, selecting: true, selected: false),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
      final title = tester.widget<Text>(find.text('already done'));
      expect(title.style?.decoration, TextDecoration.lineThrough);
      expect(
        find.descendant(
          of: find.byType(StrikeThrough),
          matching: find.byType(FractionallySizedBox),
        ),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'selecting an incomplete task does not check the box or strike the title',
    (tester) async {
      var selects = 0;
      final store = await setup(tester);
      final task = store.newTask('still open');
      store.addTasks([task]);
      await tester.pumpWidget(
        pumpTaskCard(
          store,
          task,
          selecting: true,
          selected: true,
          onSelect: () => selects++,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
      expect(
        tester.widget<Text>(find.text('still open')).style?.decoration,
        isNot(TextDecoration.lineThrough),
      );
      expect(find.text('Selected'), findsOneWidget);
      expect(task.completed, isFalse);
      expect(selects, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'checkbox in multi-select completes the task and does not toggle selection',
    (tester) async {
      var selects = 0;
      final store = await setup(tester);
      final task = store.newTask('tap complete')
        ..subtasks = [
          SubTask(id: 'c1', title: 'child one'),
          SubTask(id: 'c2', title: 'child two'),
        ];
      store.addTasks([task]);
      await tester.pumpWidget(
        pumpTaskCard(
          store,
          task,
          selecting: true,
          selected: false,
          onSelect: () => selects++,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      expect(task.completed, isTrue);
      expect(task.subtasks.every((sub) => sub.completed), isTrue);
      expect(selects, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'multiline completed titles use per-line text decoration',
    (tester) async {
      final store = await setup(tester);
      final task = store.newTask('first line\nsecond line\nthird line')
        ..completed = true;
      store.addTasks([task]);
      await tester.pumpWidget(pumpTaskCard(store, task));
      await tester.pumpAndSettle();
      final title = tester.widget<Text>(
        find.text('first line\nsecond line\nthird line'),
      );
      expect(title.style?.decoration, TextDecoration.lineThrough);
      expect(
        find.descendant(
          of: find.byType(StrikeThrough),
          matching: find.byType(FractionallySizedBox),
        ),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'subtasks stay collapsed by default and expand in browse and multi-select',
    (tester) async {
      viewport(tester, const Size(390, 844));
      final store = await setup(tester);
      store.createBoard('other board');
      final boardA = store.boards.first.id;
      final boardB = store.boards.last.id;
      store.setActiveBoard(boardA);
      final parent = store.newTask('expand parent')
        ..subtasks = [
          SubTask(id: 's1', title: 'hidden child', completed: true),
          SubTask(id: 's2', title: 'open child'),
        ];
      store.addTasks([parent]);
      await tester.pumpWidget(app(store, const MatrixHome()));
      await tester.pumpAndSettle();
      expect(find.text('hidden child'), findsNothing);
      expect(find.textContaining('Subtasks 1/2'), findsOneWidget);

      await tester.tap(find.textContaining('Subtasks 1/2'));
      await tester.pumpAndSettle();
      expect(find.text('hidden child'), findsOneWidget);
      expect(parent.completed, isFalse);

      await tester.tap(find.byTooltip('Multi-select'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Multi-select · 0 selected'), findsOneWidget);
      expect(find.text('hidden child'), findsOneWidget);
      expect(parent.completed, isFalse);
      await tester.tap(find.textContaining('Subtasks 1/2'));
      await tester.pumpAndSettle();
      expect(find.text('hidden child'), findsNothing);
      expect(find.textContaining('Multi-select · 0 selected'), findsOneWidget);
      expect(parent.completed, isFalse);
      await tester.tap(find.textContaining('Subtasks 1/2'));
      await tester.pumpAndSettle();
      expect(find.text('hidden child'), findsOneWidget);

      store.setActiveBoard(boardB);
      await tester.pumpAndSettle();
      expect(find.text('hidden child'), findsNothing);
      store.setActiveBoard(boardA);
      await tester.pumpAndSettle();
      expect(find.text('hidden child'), findsOneWidget);

      await tester.tap(find.byTooltip('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('hidden child'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('adding a subtask expands that parent only', (tester) async {
    viewport(tester, const Size(390, 844));
    final store = await setup(tester);
    final parent = store.newTask('needs children');
    final other = store.newTask('other parent', quadrant: qPlan)
      ..subtasks = [SubTask(id: 'o1', title: 'other child')];
    store.addTasks([parent, other]);
    await tester.pumpWidget(app(store, const MatrixHome()));
    await tester.pumpAndSettle();
    expect(find.text('other child'), findsNothing);
    store.appendSubtasks(parent.id, [
      SubTask(id: newId(), title: 'brand new child'),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('brand new child'), findsOneWidget);
    expect(find.text('other child'), findsNothing);
    expect(
      store.tasks
          .firstWhere((task) => task.id == parent.id)
          .subtasks
          .single
          .title,
      'brand new child',
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'complete then multi-select then hide stays completed; select-only does not complete',
    (tester) async {
      viewport(tester, const Size(390, 844));
      final store = await setup(tester);
      final done = store.newTask('finish me');
      final open = store.newTask('leave open', quadrant: qPlan);
      store.addTasks([done, open]);
      await tester.pumpWidget(app(store, const MatrixHome()));
      await tester.pumpAndSettle();

      final doneCard = find.ancestor(
        of: find.text('finish me'),
        matching: find.byType(TaskCard),
      );
      await tester.tap(
        find.descendant(of: doneCard, matching: find.byType(Checkbox)),
      );
      await tester.pumpAndSettle();
      expect(done.completed, isTrue);
      expect(open.completed, isFalse);

      await tester.tap(find.byTooltip('Multi-select'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Checkbox>(
              find.descendant(of: doneCard, matching: find.byType(Checkbox)),
            )
            .value,
        isTrue,
      );
      expect(
        tester.widget<Text>(find.text('finish me')).style?.decoration,
        TextDecoration.lineThrough,
      );

      await tester.tap(find.text('leave open'));
      await tester.pumpAndSettle();
      expect(open.completed, isFalse);
      expect(find.textContaining('Multi-select · 1 selected'), findsOneWidget);

      await tester.tap(find.byTooltip('Hide Completed'));
      await tester.pumpAndSettle();
      expect(find.text('finish me'), findsNothing);
      expect(find.text('leave open'), findsOneWidget);
      expect(done.completed, isTrue);
      expect(open.completed, isFalse);
      expect(find.textContaining('Multi-select · 1 selected'), findsOneWidget);

      await tester.tap(find.byTooltip('Cancel'));
      await tester.pumpAndSettle();
      expect(open.completed, isFalse);
      expect(done.completed, isTrue);

      await tester.tap(find.byTooltip('Hide Completed'));
      await tester.pumpAndSettle();
      expect(find.text('finish me'), findsOneWidget);
      expect(
        tester.widget<Text>(find.text('finish me')).style?.decoration,
        TextDecoration.lineThrough,
      );

      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(app(store, const MatrixHome()));
      await tester.pumpAndSettle();
      expect(done.completed, isTrue);
      expect(open.completed, isFalse);
      expect(find.textContaining('Subtasks'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'date editor scrolls above keyboard and supports Chinese date picker',
    (tester) async {
      viewport(tester, const Size(360, 640));
      final store = await setup(tester);
      store.settings.language = Language.zh;
      final task = store.newTask('task')
        ..deadline = DateTime(2300).millisecondsSinceEpoch;
      store.addTasks([task]);
      await tester.pumpWidget(app(store, const MatrixHome()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('task'));
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('save-task')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.calendar_month).last);
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);
      final picker = tester.element(find.byType(DatePickerDialog));
      expect(
        MaterialLocalizations.of(picker).cancelButtonLabel,
        isNot('CANCEL'),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'matrix and editor show full dimension names and keep 不 at 360dp',
    (tester) async {
      viewport(tester, const Size(360, 780));
      final store = await setup(tester);
      store.settings.language = Language.zh;
      store.addTasks([
        store.newTask('q1 task', quadrant: qDo),
        store.newTask('q2 task', quadrant: qPlan),
        store.newTask('q3 task', quadrant: qDelegate),
        store.newTask('q4 task', quadrant: qEliminate),
      ]);
      await tester.pumpWidget(app(store, const MatrixHome()));
      await tester.pumpAndSettle();
      for (final label in [
        '紧急且重要',
        '不紧急但重要',
        '紧急但不重要',
        '不紧急也不重要',
      ]) {
        expect(find.text(label), findsWidgets);
      }
      expect(find.text('马上做'), findsNothing);
      expect(find.text('不要做'), findsNothing);
      await tester.tap(find.text('q1 task'));
      await tester.pumpAndSettle();
      expect(find.text('紧急且重要'), findsWidgets);
      expect(find.text('不紧急也不重要'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'WP03-N: central cross dividers, no white task cards, and bottom safe area add button',
    (tester) async {
      viewport(tester, const Size(390, 844));
      final store = await setup(tester);
      final task1 = store.newTask('task one', quadrant: qDo);
      final task2 = store.newTask('task two', quadrant: qPlan);
      store.addTasks([task1, task2]);
      await tester.pumpWidget(app(store, const MatrixHome()));
      await tester.pumpAndSettle();

      expect(find.byType(VerticalDivider), findsNWidgets(2));
      expect(find.byType(Divider), findsOneWidget);

      expect(
        find.descendant(
          of: find.byType(QuadrantPane),
          matching: find.byType(Card),
        ),
        findsNothing,
      );

      expect(find.byType(FloatingActionButton), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'WP03-N: multi-select toolbar offers Edit button for single selection and opens editor',
    (tester) async {
      viewport(tester, const Size(390, 844));
      final store = await setup(tester);
      final taskA = store.newTask('first task');
      final taskB = store.newTask('second task', quadrant: qPlan);
      store.addTasks([taskA, taskB]);
      await tester.pumpWidget(app(store, const MatrixHome()));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Multi-select'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('first task'));
      await tester.pumpAndSettle();

      expect(find.text('Edit Task'), findsOneWidget);
      await tester.tap(find.text('Edit Task'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('edit-title')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('save-task')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('second task'));
      await tester.pumpAndSettle();
      expect(find.text('Edit Task'), findsNothing);
      expect(find.text('Group (2)'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'WP03-N: tap checkbox completes without opening editor; subtask has no vertical line',
    (tester) async {
      viewport(tester, const Size(390, 844));
      final store = await setup(tester);
      final parent = store.newTask('parent task')
        ..subtasks = [SubTask(id: 's1', title: 'child item')];
      store.addTasks([parent]);
      await tester.pumpWidget(app(store, const MatrixHome()));
      await tester.pumpAndSettle();

      final checkbox =
          find
              .descendant(
                of: find.byType(TaskCard),
                matching: find.byType(Checkbox),
              )
              .first;
      await tester.tap(checkbox);
      await tester.pumpAndSettle();

      expect(parent.completed, isTrue);
      expect(find.byKey(const ValueKey('edit-title')), findsNothing);

      await tester.tap(find.textContaining('Subtasks'));
      await tester.pumpAndSettle();
      expect(find.text('child item'), findsOneWidget);

      await tester.tap(find.text('parent task'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('edit-title')), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    },
  );

  test(
    'deadline badge counts local calendar days, including yesterday evening',
    () {
      expect(
        calendarDaysLeft(
          DateTime(2026, 9, 6, 23).millisecondsSinceEpoch,
          now: DateTime(2026, 9, 7, 8),
        ),
        -1,
      );
    },
  );

  testWidgets(
    'WP04-N: title multiline Enter newline, Ctrl+Enter saves, handles 1/5/20 lines without overflow',
    (tester) async {
      viewport(tester, const Size(390, 844));
      final store = await setup(tester);
      final task = store.newTask('initial title');
      store.addTasks([task]);
      await tester.pumpWidget(app(store, const MatrixHome()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('initial title'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('edit-title')), findsOneWidget);

      // 1 line
      await tester.enterText(find.byKey(const ValueKey('edit-title')), 'line 1');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // 5 lines
      final text5 = 'Line 1\nLine 2\nLine 3\nLine 4\nLine 5';
      await tester.enterText(find.byKey(const ValueKey('edit-title')), text5);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // 20 lines
      final text20 = List.generate(20, (i) => 'Line ${i + 1} of long task').join('\n');
      await tester.enterText(find.byKey(const ValueKey('edit-title')), text20);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Save via button
      await tester.tap(find.byKey(const ValueKey('save-task')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('edit-title')), findsNothing);
      expect(task.title, text20);

      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'WP04-N: subtasks edit, add, delete, and cascade with autoCompleteParent',
    (tester) async {
      viewport(tester, const Size(390, 844));
      final store = await setup(tester);
      store.settings.autoCompleteParent = true;
      final task = store.newTask('parent task')
        ..subtasks = [SubTask(id: 's1', title: 'subtask 1')];
      store.addTasks([task]);
      await tester.pumpWidget(app(store, const MatrixHome()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('parent task'));
      await tester.pumpAndSettle();
      expect(find.text('subtask 1'), findsOneWidget);

      // Add a subtask
      final addField = find.widgetWithText(TextField, 'Add subtask');
      await tester.ensureVisible(addField);
      await tester.enterText(addField, 'subtask 2');
      final addBtn = find.byTooltip('Add subtask');
      await tester.ensureVisible(addBtn);
      await tester.tap(addBtn);
      await tester.pumpAndSettle();
      expect(find.text('subtask 2'), findsOneWidget);

      // Complete both subtasks in details panel
      final subCheckboxes = find.descendant(
        of: find.byType(TaskDetailPanel),
        matching: find.byType(Checkbox),
      );
      expect(subCheckboxes, findsNWidgets(2));
      await tester.ensureVisible(subCheckboxes.first);
      await tester.tap(subCheckboxes.first);
      await tester.pumpAndSettle();
      await tester.ensureVisible(subCheckboxes.last);
      await tester.tap(subCheckboxes.last);
      await tester.pumpAndSettle();

      // Save
      await tester.tap(find.byKey(const ValueKey('save-task')));
      await tester.pumpAndSettle();

      expect(store.tasks.first.completed, isTrue);
      expect(store.tasks.first.subtasks.length, 2);

      // Open detail again and delete one subtask
      await tester.tap(find.text('parent task'));
      await tester.pumpAndSettle();
      final deleteBtn = find.byTooltip('Delete').first;
      await tester.ensureVisible(deleteBtn);
      await tester.tap(deleteBtn);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('save-task')));
      await tester.pumpAndSettle();

      expect(store.tasks.first.subtasks.length, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'WP04-N: barrier dismiss with clean vs dirty draft, internal blank tap only unfocuses',
    (tester) async {
      viewport(tester, const Size(390, 844));
      final store = await setup(tester);
      final task = store.newTask('clean task');
      store.addTasks([task]);
      await tester.pumpWidget(app(store, const MatrixHome()));
      await tester.pumpAndSettle();

      // Open detail
      await tester.tap(find.text('clean task'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('edit-title')), findsOneWidget);

      // Tap close without changes -> closes directly
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('edit-title')), findsNothing);

      // Open detail again and make dirty change
      await tester.tap(find.text('clean task'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('edit-title')), 'modified dirty task');
      await tester.pumpAndSettle();

      // Tap close -> discard dialog appears
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);

      // Click "Keep Editing" -> stays open
      await tester.tap(find.text('Keep Editing'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('edit-title')), findsOneWidget);
      expect(task.title, 'clean task');

      // Tap close -> click "Discard"
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('edit-title')), findsNothing);
      expect(task.title, 'clean task');

      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'WP04-N: wide screen sidebar renders side-by-side and does not cover matrix',
    (tester) async {
      viewport(tester, const Size(1000, 700));
      final store = await setup(tester);
      final task = store.newTask('wide task');
      store.addTasks([task]);
      await tester.pumpWidget(app(store, const MatrixHome()));
      await tester.pumpAndSettle();

      // Tapping task on wide screen opens right sidebar
      await tester.tap(find.text('wide task'));
      await tester.pumpAndSettle();

      // Sidebar open: matrix and detail panel visible simultaneously
      expect(find.byKey(const ValueKey('edit-title')), findsOneWidget);
      expect(find.byType(QuadrantPane), findsNWidgets(4));

      // Close sidebar
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('edit-title')), findsNothing);

      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'WP04-N: task deletion and deleted task cannot be resurrected on save',
    (tester) async {
      viewport(tester, const Size(390, 844));
      final store = await setup(tester);
      final task = store.newTask('to delete');
      store.addTasks([task]);
      await tester.pumpWidget(app(store, const MatrixHome()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('to delete'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Delete Task'));
      await tester.pumpAndSettle();
      expect(find.text('Delete this task?'), findsOneWidget);

      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      expect(store.tasks, isEmpty);
      expect(find.byKey(const ValueKey('edit-title')), findsNothing);

      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'WP04-N: manual input with empty lines creates exact number of tasks (regression MF23)',
    (tester) async {
      viewport(tester, const Size(390, 844));
      final store = await setup(tester);
      await tester.pumpWidget(app(store, const MatrixHome()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add Task'));
      await tester.pumpAndSettle();

      const input = 'Task 1\n\nTask 2\n\n\nTask 3\n';
      await tester.enterText(find.byKey(const ValueKey('task-input')), input);
      await tester.tap(find.byKey(const ValueKey('submit-tasks')));
      await tester.pumpAndSettle();

      expect(store.tasks.length, 3);
      expect(store.tasks.map((t) => t.title).toList(), ['Task 1', 'Task 2', 'Task 3']);

      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'WP23-N: tap quadrant header enters focus view with full width main list and 3 collapsed bottom cards',
    (tester) async {
      viewport(tester, const Size(390, 844));
      final store = await setup(tester);
      final t1 = store.newTask('Q1 Task', quadrant: qDo);
      final t2 = store.newTask('Q2 Task', quadrant: qPlan);
      final t3 = store.newTask('Q3 Task', quadrant: qDelegate);
      store.addTasks([t1, t2, t3]);
      await tester.pumpWidget(app(store, const MatrixHome()));
      await tester.pumpAndSettle();

      // Tap Q1 header to enter focus mode
      await tester.tap(find.byKey(const ValueKey('quadrant-header-1')));
      await tester.pumpAndSettle();

      // Focus view is shown
      expect(find.byType(QuadrantFocusView), findsOneWidget);
      expect(find.byKey(const ValueKey('focus-back-btn')), findsOneWidget);

      // Q1 task in main area
      expect(find.text('Q1 Task'), findsOneWidget);

      // 3 bottom cards for Q2, Q3, Q4 in order
      expect(find.byKey(const ValueKey('focus-card-2')), findsOneWidget);
      expect(find.byKey(const ValueKey('focus-card-3')), findsOneWidget);
      expect(find.byKey(const ValueKey('focus-card-4')), findsOneWidget);
      expect(find.byKey(const ValueKey('focus-card-1')), findsNothing);

      // FAB add button is visible and not obscured
      expect(find.text('Add Task'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'WP23-N: switch between collapsed cards and exit focus via back button or header tap',
    (tester) async {
      viewport(tester, const Size(390, 844));
      final store = await setup(tester);
      final t1 = store.newTask('Q1 Task', quadrant: qDo);
      final t2 = store.newTask('Q2 Task', quadrant: qPlan);
      store.addTasks([t1, t2]);
      await tester.pumpWidget(app(store, const MatrixHome()));
      await tester.pumpAndSettle();

      // Enter Q1 focus
      await tester.tap(find.byKey(const ValueKey('quadrant-header-1')));
      await tester.pumpAndSettle();
      expect(find.text('Q1 Task'), findsOneWidget);

      // Tap bottom card for Q2 to switch focus
      await tester.tap(find.byKey(const ValueKey('focus-card-2')));
      await tester.pumpAndSettle();

      // Now focused on Q2: Q2 task is visible in main area
      expect(find.text('Q2 Task'), findsOneWidget);
      // Bottom cards now show Q1, Q3, Q4
      expect(find.byKey(const ValueKey('focus-card-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('focus-card-3')), findsOneWidget);
      expect(find.byKey(const ValueKey('focus-card-4')), findsOneWidget);
      expect(find.byKey(const ValueKey('focus-card-2')), findsNothing);

      // Tap back button to return to matrix view
      await tester.tap(find.byKey(const ValueKey('focus-back-btn')));
      await tester.pumpAndSettle();

      expect(find.byType(QuadrantFocusView), findsNothing);
      expect(find.byKey(const ValueKey('focus-back-btn')), findsNothing);
      expect(find.byType(QuadrantPane), findsNWidgets(4));

      // Re-enter Q3 focus by tapping Q3 header
      await tester.tap(find.byKey(const ValueKey('quadrant-header-3')));
      await tester.pumpAndSettle();
      expect(find.byType(QuadrantFocusView), findsOneWidget);

      // Tap Q3 header inside focus view to restore matrix
      await tester.tap(find.byKey(const ValueKey('quadrant-header-3')));
      await tester.pumpAndSettle();
      expect(find.byType(QuadrantFocusView), findsNothing);
      expect(find.byType(QuadrantPane), findsNWidgets(4));

      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'WP23-N: task completion, details edit, hide completed and empty count in focus view',
    (tester) async {
      viewport(tester, const Size(390, 844));
      final store = await setup(tester);
      final t1 = store.newTask('Complete me', quadrant: qDo);
      store.addTasks([t1]);
      await tester.pumpWidget(app(store, const MatrixHome()));
      await tester.pumpAndSettle();

      // Enter Q1 focus
      await tester.tap(find.byKey(const ValueKey('quadrant-header-1')));
      await tester.pumpAndSettle();

      // Complete task in focus view
      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();
      expect(t1.completed, isTrue);

      // Open task details in focus view
      await tester.tap(find.text('Complete me'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('edit-title')), findsOneWidget);
      // Close details
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      // Empty Q4 card shows count 0
      expect(find.byKey(const ValueKey('focus-card-4')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('focus-card-4')), matching: find.text('0')), findsOneWidget);

      // Toggle hideCompleted: completed task is hidden
      await tester.tap(find.byTooltip('Hide Completed'));
      await tester.pumpAndSettle();
      expect(find.text('Complete me'), findsNothing);

      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'WP23-N: board switching exits focus view and cleans cache',
    (tester) async {
      viewport(tester, const Size(390, 844));
      final store = await setup(tester);
      store.createBoard('Second Board');
      // Switch back to first board
      store.setActiveBoard(store.boards.first.id);
      await tester.pumpWidget(app(store, const MatrixHome()));
      await tester.pumpAndSettle();

      // Enter Q1 focus on first board
      await tester.tap(find.byKey(const ValueKey('quadrant-header-1')));
      await tester.pumpAndSettle();
      expect(find.byType(QuadrantFocusView), findsOneWidget);

      // Open board switcher and pick second board
      await tester.tap(find.text(store.boards.first.name));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Second Board').last);
      await tester.pumpAndSettle();

      // Focus view has exited, showing 4 quadrants of second board
      expect(find.byType(QuadrantFocusView), findsNothing);
      expect(find.text('Second Board'), findsOneWidget);
      expect(find.byType(QuadrantPane), findsNWidgets(4));

      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'WP12-S-N: tap search icon opens SearchScreen with current board default, filter chips and empty query list',
    (tester) async {
      viewport(tester, const Size(390, 844));
      final store = await setup(tester);
      final b1Id = store.activeBoardId;

      // 2 tasks in current board
      final t1 = store.newTask('Alpha Task', quadrant: qDo);
      final t2 = store.newTask('Beta Task', quadrant: qPlan);
      store.addTasks([t1, t2]);

      // Create second board and 1 task in second board
      store.createBoard('Second Board');
      final b2Id = store.boards.firstWhere((b) => b.name == 'Second Board').id;
      final t3 = Task(
        id: 't-b2',
        boardId: b2Id,
        title: 'Gamma Task in Board 2',
        quadrant: qDelegate,
        createdAt: 100,
      );
      store.tasks.add(t3);

      // Switch back to first board
      store.setActiveBoard(b1Id);

      await tester.pumpWidget(app(store, const MatrixHome()));
      await tester.pumpAndSettle();

      // Tap search icon
      await tester.tap(find.byKey(const ValueKey('search-btn')));
      await tester.pumpAndSettle();

      expect(find.byType(SearchScreen), findsOneWidget);
      // Results count summary
      expect(find.text('2 results'), findsOneWidget);
      expect(find.text('Alpha Task'), findsOneWidget);
      expect(find.text('Beta Task'), findsOneWidget);
      expect(find.text('Gamma Task in Board 2'), findsNothing);

      // Back to MatrixHome
      await tester.tap(find.byKey(const ValueKey('search-back-btn')));
      await tester.pumpAndSettle();

      expect(find.byType(SearchScreen), findsNothing);
      expect(find.byType(QuadrantPane), findsNWidgets(4));

      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'WP12-S-N: search by keyword matches parent and subtask, subtask shows breadcrumb and opens detail with highlight',
    (tester) async {
      viewport(tester, const Size(390, 844));
      final store = await setup(tester);
      final parent = store.newTask('Major Feature', quadrant: qDo)
        ..subtasks = [
          SubTask(id: 'sub-target', title: 'Special Unique Subtask', completed: false),
        ];
      store.addTasks([parent]);

      await tester.pumpWidget(app(store, const MatrixHome()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('search-btn')));
      await tester.pumpAndSettle();

      // Type subtask keyword
      await tester.enterText(find.byKey(const ValueKey('search-input')), 'Special');
      await tester.pumpAndSettle();

      expect(find.text('1 results'), findsOneWidget);
      expect(find.text('Special Unique Subtask'), findsOneWidget);
      // Breadcrumb contains board name and parent task title
      expect(find.textContaining('Major Feature'), findsWidgets);

      // Tap subtask item -> opens TaskDetailPanel with highlight
      await tester.tap(find.text('Special Unique Subtask'));
      await tester.pumpAndSettle();

      expect(find.byType(TaskDetailPanel), findsOneWidget);
      expect(find.byKey(const ValueKey('detail-subtask-sub-target')), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'WP12-S-N: combined filters (quadrant, status, date) and live edit/completion/deletion reflection',
    (tester) async {
      viewport(tester, const Size(390, 844));
      final store = await setup(tester);
      final now = DateTime.now();

      final tQ1 = store.newTask('Q1 Done Today', quadrant: qDo)
        ..completed = true
        ..deadline = DateTime(now.year, now.month, now.day, 23, 59).millisecondsSinceEpoch;

      final tQ2 = store.newTask('Q2 Open Future', quadrant: qPlan)
        ..completed = false
        ..deadline = DateTime(now.year, now.month, now.day + 10, 12).millisecondsSinceEpoch;

      store.addTasks([tQ1, tQ2]);

      await tester.pumpWidget(app(store, const MatrixHome()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('search-btn')));
      await tester.pumpAndSettle();

      expect(find.text('2 results'), findsOneWidget);

      // Filter by Q1
      await tester.ensureVisible(find.byKey(const ValueKey('filter-q-1')));
      await tester.tap(find.byKey(const ValueKey('filter-q-1')));
      await tester.pumpAndSettle();
      expect(find.text('1 results'), findsOneWidget);
      expect(find.text('Q1 Done Today'), findsOneWidget);
      expect(find.text('Q2 Open Future'), findsNothing);

      // Filter by Incomplete: Q1 is completed, so 0 results
      await tester.ensureVisible(find.byKey(const ValueKey('filter-status-incomplete')));
      await tester.tap(find.byKey(const ValueKey('filter-status-incomplete')));
      await tester.pumpAndSettle();
      expect(find.text('0 results'), findsOneWidget);
      expect(find.byType(Icon), findsWidgets); // empty state

      // Switch back to All status
      await tester.ensureVisible(find.byKey(const ValueKey('filter-status-all')));
      await tester.tap(find.byKey(const ValueKey('filter-status-all')));
      await tester.pumpAndSettle();
      expect(find.text('1 results'), findsOneWidget);

      // Toggle checkbox directly in search result: uncomplete Q1
      await tester.tap(find.byKey(ValueKey('search-check-${tQ1.id}')));
      await tester.pumpAndSettle();
      expect(tQ1.completed, isFalse);

      // Now filter by Incomplete -> Q1 now appears!
      await tester.ensureVisible(find.byKey(const ValueKey('filter-status-incomplete')));
      await tester.tap(find.byKey(const ValueKey('filter-status-incomplete')));
      await tester.pumpAndSettle();
      expect(find.text('1 results'), findsOneWidget);
      expect(find.text('Q1 Done Today'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'WP12-S-N: switch to allBoards, exit preserves original board, "Go to Board" explicitly switches board',
    (tester) async {
      viewport(tester, const Size(390, 844));
      final store = await setup(tester);
      store.createBoard('Project Second');
      final secondBoard = store.boards.firstWhere((b) => b.name == 'Project Second');
      store.setActiveBoard(store.boards.first.id);
      final originalBoardId = store.activeBoardId;

      final taskBoard2 = Task(
        id: 'task-board-2',
        boardId: secondBoard.id,
        title: 'Work on Second Board',
        quadrant: qDo,
        createdAt: 100,
      );
      store.tasks.add(taskBoard2);

      await tester.pumpWidget(app(store, const MatrixHome()));
      await tester.pumpAndSettle();

      // Open search
      await tester.tap(find.byKey(const ValueKey('search-btn')));
      await tester.pumpAndSettle();

      // Switch scope to allBoards
      await tester.tap(find.byKey(const ValueKey('filter-scope-all')));
      await tester.pumpAndSettle();

      expect(find.text('Work on Second Board'), findsOneWidget);

      // Exit search via back button without "Go to Board"
      await tester.tap(find.byKey(const ValueKey('search-back-btn')));
      await tester.pumpAndSettle();

      // Active board is still the original board!
      expect(store.activeBoardId, originalBoardId);

      // Re-open search and explicitly use "Go to Board"
      await tester.tap(find.byKey(const ValueKey('search-btn')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('filter-scope-all')));
      await tester.pumpAndSettle();

      // Open popup menu on task-board-2
      await tester.tap(find.byType(PopupMenuButton<String>).last);
      await tester.pumpAndSettle();

      // Select "Go to Board"
      await tester.tap(find.byKey(const ValueKey('go-to-board-btn-task-board-2')));
      await tester.pumpAndSettle();

      // MatrixHome has switched to Project Second!
      expect(store.activeBoardId, secondBoard.id);
      expect(find.text('Project Second'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'WP22-A-N: manual input with quick dates (Today/Tomorrow), custom date, and clearing date',
    (tester) async {
      final store = await setup(tester);
      await tester.pumpWidget(
        app(
          store,
          const Scaffold(
            body: InputSheet(
              initialMode: InputModePref.single,
              embedded: true,
            ),
          ),
        ),
      );

      // Initially no date selected
      expect(find.byKey(const ValueKey('deadline-clear')), findsNothing);

      // Select Today
      await tester.tap(find.byKey(const ValueKey('deadline-today')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('deadline-clear')), findsOneWidget);
      expect(find.text(store.t['deadlineBatchScope']!), findsOneWidget);

      // Submit multiple manual tasks
      await tester.enterText(
        find.byKey(const ValueKey('task-input')),
        'Buy milk\nFinish report',
      );
      await tester.tap(find.byKey(const ValueKey('submit-tasks')));
      await tester.pumpAndSettle();

      expect(store.tasks.length, 2);
      final now = DateTime.now();
      for (final t in store.tasks) {
        expect(t.deadline, isNotNull);
        final d = DateTime.fromMillisecondsSinceEpoch(t.deadline!);
        expect(d.year, now.year);
        expect(d.month, now.month);
        expect(d.day, now.day);
      }

      // Input field and deadline are reset on success
      expect(find.byKey(const ValueKey('deadline-clear')), findsNothing);

      // Now test Tomorrow and clear button
      await tester.tap(find.byKey(const ValueKey('deadline-tomorrow')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('deadline-clear')), findsOneWidget);

      // Clear the deadline
      await tester.tap(find.byKey(const ValueKey('deadline-clear')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('deadline-clear')), findsNothing);

      // Enter task without date
      await tester.enterText(
        find.byKey(const ValueKey('task-input')),
        'No deadline task',
      );
      await tester.tap(find.byKey(const ValueKey('submit-tasks')));
      await tester.pumpAndSettle();

      final noDateTask = store.tasks.firstWhere((t) => t.title == 'No deadline task');
      expect(noDateTask.deadline, isNull);

      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'WP22-A-N: AI input with deadline sets parent deadline, subtasks do NOT inherit, and clears on success',
    (tester) async {
      final ai = ControlledAI();
      final store = await setup(tester, ai: ai);
      store.settings.autoGroupAI = true;

      await tester.pumpWidget(
        app(
          store,
          const Scaffold(
            body: InputSheet(
              initialMode: InputModePref.brainDump,
              embedded: true,
            ),
          ),
        ),
      );

      // Select Tomorrow
      await tester.tap(find.byKey(const ValueKey('deadline-tomorrow')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('task-input')),
        'Launch project with milestones',
      );
      await tester.tap(find.byKey(const ValueKey('submit-tasks')));
      await tester.pump();

      // Complete AI analysis with a parent containing subtasks
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      ai.analysis.complete([
        AIAnalysisResult(
          title: 'Launch project',
          quadrant: qPlan,
          isGrouped: true,
          subtasks: ['Write spec', 'Implement core'],
        ),
      ]);
      await tester.pumpAndSettle();

      expect(store.tasks.length, 1);
      final parent = store.tasks.first;
      expect(parent.title, 'Launch project');
      expect(parent.deadline, isNotNull);
      final d = DateTime.fromMillisecondsSinceEpoch(parent.deadline!);
      expect(d.year, tomorrow.year);
      expect(d.month, tomorrow.month);
      expect(d.day, tomorrow.day);

      // Verify subtasks do NOT inherit the deadline
      expect(parent.subtasks.length, 2);
      for (final sub in parent.subtasks) {
        expect(sub.deadline, isNull);
      }

      // Input sheet draft and deadline cleared on success
      expect(find.byKey(const ValueKey('deadline-clear')), findsNothing);

      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'WP22-A-N: AI error or cancel retains input draft and selected date',
    (tester) async {
      final ai = ControlledAI();
      final store = await setup(tester, ai: ai);

      await tester.pumpWidget(
        app(
          store,
          const Scaffold(
            body: InputSheet(
              initialMode: InputModePref.brainDump,
              embedded: true,
            ),
          ),
        ),
      );

      // Select Today and enter draft
      await tester.tap(find.byKey(const ValueKey('deadline-today')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('task-input')),
        'Draft that will fail',
      );

      await tester.tap(find.byKey(const ValueKey('submit-tasks')));
      await tester.pump();

      // AI errors out
      ai.analysis.completeError(const AIException('aiNetworkError'));
      await tester.pumpAndSettle();

      // Error message shown
      expect(find.text(store.t['aiNetworkError']!), findsOneWidget);

      // Input draft and deadline choice are both retained!
      final textField = tester.widget<TextField>(find.byKey(const ValueKey('task-input')));
      expect(textField.controller!.text, 'Draft that will fail');
      expect(find.byKey(const ValueKey('deadline-clear')), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'WP22-B-N: subtask deadline set, edited, cleared, and dirty draft tracking',
    (tester) async {
      viewport(tester, const Size(390, 844));
      final store = await setup(tester);
      final parent = store.newTask('Parent with Subtasks')
        ..subtasks = [SubTask(id: 's1', title: 'Subtask Alpha')];
      store.addTasks([parent]);

      await tester.pumpWidget(app(store, const MatrixHome()));
      await tester.pumpAndSettle();

      // Open task detail panel
      await tester.tap(find.text('Parent with Subtasks'));
      await tester.pumpAndSettle();
      expect(find.byType(TaskDetailPanel), findsOneWidget);

      // Open subtask editor
      await tester.ensureVisible(find.byKey(const ValueKey('subtask-item-s1')));
      await tester.tap(find.byKey(const ValueKey('subtask-item-s1')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('subtask-edit-title')), findsOneWidget);
      expect(find.byKey(const ValueKey('subtask-deadline-today')), findsOneWidget);
      expect(find.byKey(const ValueKey('subtask-deadline-clear')), findsNothing);

      // Select Today deadline and edit title
      await tester.tap(find.byKey(const ValueKey('subtask-deadline-today')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('subtask-deadline-clear')), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('subtask-edit-title')),
        'Subtask Alpha Edited',
      );
      await tester.pumpAndSettle();

      // Save subtask
      await tester.tap(find.byKey(const ValueKey('subtask-save-btn')));
      await tester.pumpAndSettle();

      // Verify subtask item reflects new title and calendar icon
      expect(find.text('Subtask Alpha Edited'), findsOneWidget);
      expect(find.byIcon(Icons.calendar_month), findsWidgets);

      // Try closing without saving parent -> dirty dialog appears because subtask was changed
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);

      // Stay in editor
      await tester.tap(find.text('Keep Editing'));
      await tester.pumpAndSettle();

      // Save parent task
      await tester.tap(find.byKey(const ValueKey('save-task')));
      await tester.pumpAndSettle();

      final savedSub = store.tasks.first.subtasks.first;
      expect(savedSub.title, 'Subtask Alpha Edited');
      expect(savedSub.deadline, isNotNull);
      final now = DateTime.now();
      final subD = DateTime.fromMillisecondsSinceEpoch(savedSub.deadline!);
      expect(subD.year, now.year);
      expect(subD.month, now.month);
      expect(subD.day, now.day);

      // Re-open detail panel and clear subtask deadline
      await tester.tap(find.text('Parent with Subtasks'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const ValueKey('subtask-item-s1')));
      await tester.tap(find.byKey(const ValueKey('subtask-item-s1')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('subtask-deadline-clear')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('subtask-deadline-clear')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('subtask-save-btn')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('save-task')));
      await tester.pumpAndSettle();

      expect(store.tasks.first.subtasks.first.deadline, isNull);

      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'WP22-B-N: parent and subtask deadlines are independent, subtask deadline can be later than parent with advisory warning',
    (tester) async {
      viewport(tester, const Size(390, 844));
      final store = await setup(tester);
      final today = DateTime.now();
      final tomorrow = today.add(const Duration(days: 1));

      // Parent task has deadline Today
      final parent = store.newTask('Independent Dates Task')
        ..deadline = DateTime(today.year, today.month, today.day, 23, 59, 59).millisecondsSinceEpoch
        ..subtasks = [SubTask(id: 's1', title: 'Child Task')];
      store.addTasks([parent]);

      await tester.pumpWidget(app(store, const MatrixHome()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Independent Dates Task'));
      await tester.pumpAndSettle();

      // Edit subtask to have deadline Tomorrow (> parent deadline Today)
      await tester.ensureVisible(find.byKey(const ValueKey('subtask-item-s1')));
      await tester.tap(find.byKey(const ValueKey('subtask-item-s1')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('subtask-deadline-tomorrow')));
      await tester.pumpAndSettle();

      // Advisory warning is displayed, but doesn't prevent saving
      expect(find.byKey(const ValueKey('subtask-after-parent-warning')), findsOneWidget);
      expect(find.text(store.t['subtaskDeadlineAfterParent']!), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('subtask-save-btn')));
      await tester.pumpAndSettle();

      // Save parent task
      await tester.tap(find.byKey(const ValueKey('save-task')));
      await tester.pumpAndSettle();

      final updatedParent = store.tasks.first;
      final pDate = DateTime.fromMillisecondsSinceEpoch(updatedParent.deadline!);
      final sDate = DateTime.fromMillisecondsSinceEpoch(updatedParent.subtasks.first.deadline!);

      expect(pDate.day, today.day);
      expect(sDate.day, tomorrow.day);
      // Independent: modifying parent deadline does not alter subtask deadline
      updatedParent.deadline = null;
      store.updateTask(updatedParent);
      expect(store.tasks.first.subtasks.first.deadline, isNotNull);

      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'WP22-B-N: task_card displays subtask deadline badge on matrix screen and completes independently',
    (tester) async {
      viewport(tester, const Size(390, 844));
      final store = await setup(tester);
      final today = DateTime.now();

      final parent = store.newTask('Parent with Dated Subtask')
        ..subtasks = [
          SubTask(
            id: 's1',
            title: 'Dated Subtask',
            deadline: DateTime(today.year, today.month, today.day, 23, 59, 59).millisecondsSinceEpoch,
          ),
        ];
      store.addTasks([parent]);

      await tester.pumpWidget(app(store, const MatrixHome()));
      await tester.pumpAndSettle();

      // Expand subtasks
      await tester.tap(find.textContaining('Subtasks'));
      await tester.pumpAndSettle();

      // Verify subtask item and its deadline badge are rendered
      expect(find.text('Dated Subtask'), findsOneWidget);
      expect(find.text(store.t['today']!), findsOneWidget);

      // Check subtask checkbox
      final subCheck = find.descendant(
        of: find.byType(TaskCard),
        matching: find.byType(Checkbox),
      ).last;
      await tester.tap(subCheck);
      await tester.pumpAndSettle();

      expect(store.tasks.first.subtasks.first.completed, isTrue);
      // Deadline is still preserved after completion
      expect(store.tasks.first.subtasks.first.deadline, isNotNull);

      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'WP05-N: cross-quadrant move prepends to target quadrant, preserves relative order, and does not alter createdAt',
    (tester) async {
      viewport(tester, const Size(800, 600));
      final store = await setup(tester);
      final boardA = store.activeBoardId;
      store.createBoard('Board B');
      final boardB = store.boards.firstWhere((b) => b.name == 'Board B').id;

      // Tasks on Board B
      final taskB1 = store.newTask('B1 Task')..boardId = boardB;
      final taskB2 = store.newTask('B2 Task')..boardId = boardB;
      store.addTasks([taskB1, taskB2]);

      // Switch back to Board A
      store.setActiveBoard(boardA);

      // Tasks on Board A: Q1 has A1, A2, A3; Q2 has P1, P2
      final a1 = store.newTask('A1', quadrant: qDo);
      final a2 = store.newTask('A2', quadrant: qDo);
      final a3 = store.newTask('A3', quadrant: qDo);
      final p1 = store.newTask('P1', quadrant: qPlan);
      final p2 = store.newTask('P2', quadrant: qPlan);

      store.addTasks([a3]);
      store.addTasks([a2]);
      store.addTasks([a1]);
      store.addTasks([p2]);
      store.addTasks([p1]);

      expect(store.tasksIn(qDo).map((t) => t.title).toList(), ['A1', 'A2', 'A3']);
      expect(store.tasksIn(qPlan).map((t) => t.title).toList(), ['P1', 'P2']);

      final originalCreatedAt = a2.createdAt;

      // Move A2 from Q1 to Q2 (qPlan)
      store.moveTask(a2.id, qPlan);

      // A2 must be prepended to Q2, ahead of P1 and P2
      expect(store.tasksIn(qPlan).map((t) => t.title).toList(), ['A2', 'P1', 'P2']);
      // Q1 keeps A1 and A3 in order
      expect(store.tasksIn(qDo).map((t) => t.title).toList(), ['A1', 'A3']);
      // createdAt is preserved
      expect(store.tasks.firstWhere((t) => t.id == a2.id).createdAt, originalCreatedAt);

      // Same quadrant move must NOT reorder
      store.moveTask(a2.id, qPlan);
      expect(store.tasksIn(qPlan).map((t) => t.title).toList(), ['A2', 'P1', 'P2']);

      // Board B tasks are completely unchanged
      store.setActiveBoard(boardB);
      expect(store.tasksIn(qDo).map((t) => t.title).toList(), ['B1 Task', 'B2 Task']);

      // Re-switch to Board A and export/import roundtrip test
      store.setActiveBoard(boardA);
      final exportedJson = store.exportJson();
      store.importData(jsonDecode(exportedJson) as Map<String, dynamic>, 'overwrite');
      expect(store.tasksIn(qPlan).map((t) => t.title).toList(), ['A2', 'P1', 'P2']);
      expect(store.tasksIn(qDo).map((t) => t.title).toList(), ['A1', 'A3']);

      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'WP05-N: TaskDetailPanel quadrant change prepends task to target quadrant',
    (tester) async {
      viewport(tester, const Size(800, 600));
      final store = await setup(tester);

      final t1 = store.newTask('Task Q1', quadrant: qDo);
      final p1 = store.newTask('Plan 1', quadrant: qPlan);
      final p2 = store.newTask('Plan 2', quadrant: qPlan);
      store.addTasks([p2]);
      store.addTasks([p1]);
      store.addTasks([t1]);

      expect(store.tasksIn(qPlan).map((t) => t.title).toList(), ['Plan 1', 'Plan 2']);

      await tester.pumpWidget(app(store, const MatrixHome()));
      await tester.pumpAndSettle();

      // Tap Task Q1 to open TaskDetailPanel
      await tester.tap(find.text('Task Q1'));
      await tester.pumpAndSettle();

      // Select Q2 (Plan) ChoiceChip
      await tester.tap(find.widgetWithText(ChoiceChip, store.t['q2']!));
      await tester.pumpAndSettle();

      // Save
      await tester.tap(find.widgetWithText(FilledButton, store.t['save']!));
      await tester.pumpAndSettle();

      // Verify Task Q1 is now at the top of Q2
      expect(store.tasksIn(qPlan).map((t) => t.title).toList(), ['Task Q1', 'Plan 1', 'Plan 2']);
      expect(store.tasksIn(qDo), isEmpty);

      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'WP05-N: secondary click Move Menu moves task to target quadrant and prepends',
    (tester) async {
      viewport(tester, const Size(800, 600));
      final store = await setup(tester);

      final t1 = store.newTask('Task to Move', quadrant: qDo);
      final d1 = store.newTask('Delegate 1', quadrant: qDelegate);
      store.addTasks([d1]);
      store.addTasks([t1]);

      await tester.pumpWidget(app(store, const MatrixHome()));
      await tester.pumpAndSettle();

      // Secondary click (right click on Windows) on Task to Move
      final cardFinder = find.text('Task to Move');
      final center = tester.getCenter(cardFinder);
      final gesture = await tester.startGesture(center, kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
      await gesture.up();
      await tester.pumpAndSettle();

      // Menu should appear with option to move to Q3 (Delegate)
      final moveToQ3Finder = find.byKey(ValueKey('move-to-q$qDelegate-${t1.id}'));
      expect(moveToQ3Finder, findsOneWidget);

      await tester.tap(moveToQ3Finder);
      await tester.pumpAndSettle();

      // Verify task moved to top of Q3
      expect(store.tasksIn(qDelegate).map((t) => t.title).toList(), ['Task to Move', 'Delegate 1']);
      expect(store.tasksIn(qDo), isEmpty);

      // Verify confirmation SnackBar is displayed
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.textContaining(store.t['q3']!),
        ),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'WP05-N: drag and drop scrolls scrolled target quadrant to top and prepends task',
    (tester) async {
      viewport(tester, const Size(600, 700));
      final store = await setup(tester);

      // Fill Q2 with 15 tasks so it can scroll
      final qPlanTasks = [for (var i = 0; i < 15; i++) store.newTask('Plan $i', quadrant: qPlan)];
      final qDoTask = store.newTask('Moving Task', quadrant: qDo);
      for (final t in qPlanTasks.reversed) {
        store.addTasks([t]);
      }
      store.addTasks([qDoTask]);

      await tester.pumpWidget(app(store, const MatrixHome()));
      await tester.pumpAndSettle();

      // Scroll Q2 down
      final q2ListFinder = find.byKey(PageStorageKey('${store.activeBoardId}-$qPlan'));
      await tester.drag(q2ListFinder, const Offset(0, -300));
      await tester.pumpAndSettle();

      // Verify Q2 is scrolled down
      final scrollableState = tester.state<ScrollableState>(
        find.descendant(of: q2ListFinder, matching: find.byType(Scrollable)),
      );
      expect(scrollableState.position.pixels, greaterThan(100));

      // Drag Moving Task from Q1 to Q2 with long press
      final gesture = await tester.startGesture(tester.getCenter(find.text('Moving Task')));
      await tester.pump(const Duration(milliseconds: 600));

      // Drag to Q2 list area
      await gesture.moveTo(tester.getCenter(q2ListFinder));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      // Verify Moving Task is at the top of Q2
      expect(store.tasksIn(qPlan).first.title, 'Moving Task');

      // Verify Q2 list scrolled back to top (offset == 0) so the task is visible
      expect(scrollableState.position.pixels, 0.0);

      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'WP06-N: fresh launch with Chinese device locale initializes Language.zh, localized board and quadrant names',
    (tester) async {
      viewport(tester, const Size(390, 844));
      final store = await setup(
        tester,
        deviceLocales: [const Locale('zh', 'CN')],
      );
      expect(store.settings.language, Language.zh);
      expect(store.boards.first.name, '我的任务');
      expect(store.t['q1'], '紧急且重要');

      await tester.pumpWidget(app(store, const MatrixHome()));
      await tester.pumpAndSettle();

      expect(find.text('我的任务'), findsOneWidget);
      expect(find.text('紧急且重要'), findsOneWidget);
      expect(find.text('不紧急但重要'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'WP06-N: fresh launch with Japanese device locale initializes Language.ja and localized board',
    (tester) async {
      viewport(tester, const Size(390, 844));
      final store = await setup(
        tester,
        deviceLocales: [const Locale('ja', 'JP')],
      );
      expect(store.settings.language, Language.ja);
      expect(store.boards.first.name, 'マイタスク');
      expect(store.t['q1'], '緊急かつ重要');

      await tester.pumpWidget(app(store, const MatrixHome()));
      await tester.pumpAndSettle();

      expect(find.text('マイタスク'), findsOneWidget);
      expect(find.text('緊急かつ重要'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'WP06-N: fresh launch with unsupported device locale falls back to Language.en',
    (tester) async {
      viewport(tester, const Size(390, 844));
      final store = await setup(
        tester,
        deviceLocales: [const Locale('de', 'DE')],
      );
      expect(store.settings.language, Language.en);
      expect(store.boards.first.name, 'My Tasks');
      expect(store.t['q1'], 'Urgent and Important');

      await tester.pumpWidget(app(store, const MatrixHome()));
      await tester.pumpAndSettle();

      expect(find.text('My Tasks'), findsOneWidget);
      expect(find.text('Urgent and Important'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'WP06-N: existing saved settings with explicit en on Chinese device is preserved and not overwritten',
    (tester) async {
      viewport(tester, const Size(390, 844));
      final store = await setup(
        tester,
        deviceLocales: [const Locale('zh', 'CN')],
        initialPrefs: {
          'matrixflow-settings': jsonEncode(AppSettings(language: Language.en).toJson()),
          'matrixflow-boards': jsonEncode([Board(id: 'b1', name: 'Custom Board', createdAt: 1).toJson()]),
        },
      );
      expect(store.settings.language, Language.en);
      expect(store.t['q1'], 'Urgent and Important');

      await tester.pumpWidget(app(store, const MatrixHome()));
      await tester.pumpAndSettle();

      expect(find.text('Urgent and Important'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'WP06-N: manual language switch and subsequent launch keeps user choice across reboots',
    (tester) async {
      viewport(tester, const Size(390, 844));
      // First boot on zh device
      final store1 = await setup(
        tester,
        deviceLocales: [const Locale('zh', 'CN')],
      );
      expect(store1.settings.language, Language.zh);

      // User manually changes language to Japanese
      await tester.runAsync(() async {
        store1.updateSettings((s) => s..language = Language.ja);
        await store1.flush();
      });
      expect(store1.settings.language, Language.ja);

      // Simulate app restart with same backend prefs and zh device locale
      final store2 = Store(deviceLocales: [const Locale('zh', 'CN')]);
      await tester.runAsync(() async {
        await store2.init();
      });
      addTearDown(store2.dispose);

      // Saved user choice 'ja' must NOT be overwritten by device locale 'zh'
      expect(store2.settings.language, Language.ja);
      expect(store2.t['q1'], '緊急かつ重要');
    },
  );

  testWidgets(
    'WP06-N: import data with overwrite respects imported language and does not get overwritten',
    (tester) async {
      final store = await setup(
        tester,
        deviceLocales: [const Locale('zh', 'CN')],
      );
      expect(store.settings.language, Language.zh);

      await tester.runAsync(() async {
        store.importData({
          'version': 1,
          'boards': [{'id': 'b1', 'name': 'Imported', 'createdAt': 1}],
          'tasks': [],
          'settings': {'language': 'en'},
        }, 'overwrite');
        await store.flush();
      });

      expect(store.settings.language, Language.en);

      // Re-boot store with zh device locale
      final store2 = Store(deviceLocales: [const Locale('zh', 'CN')]);
      await tester.runAsync(() async {
        await store2.init();
      });
      addTearDown(store2.dispose);

      expect(store2.settings.language, Language.en);
    },
  );

  testWidgets(
    'WP06-N: MatrixFlowApp widget entry point respects injected deviceLocales',
    (tester) async {
      viewport(tester, const Size(390, 844));
      SharedPreferences.setMockInitialValues({});

      await tester.pumpWidget(
        const MatrixFlowApp(deviceLocales: [Locale('zh', 'CN')]),
      );
      await tester.pumpAndSettle();

      expect(find.text('我的任务'), findsOneWidget);
      expect(find.text('紧急且重要'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'WP02-N: clear board menu item is disabled on empty board, enabled when tasks exist',
    (tester) async {
      viewport(tester, const Size(390, 844));
      final store = await setup(tester);
      await tester.pumpWidget(app(store, const MatrixHome()));
      await tester.pumpAndSettle();

      // Board is empty initially; tap board switcher to open menu
      await tester.tap(find.text(store.boards.first.name));
      await tester.pumpAndSettle();

      // Clear menu item is present but disabled
      final clearItem = find.byKey(const ValueKey('clear-board-menu-item'));
      expect(clearItem, findsOneWidget);
      await tester.tap(clearItem);
      await tester.pumpAndSettle();
      // Dialog did NOT open
      expect(find.byKey(const ValueKey('clear-board-dialog')), findsNothing);

      // Close menu
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      // Add a task
      store.addTasks([store.newTask('Task 1', quadrant: qDo)]);
      await tester.pumpAndSettle();

      // Open menu again
      await tester.tap(find.text(store.boards.first.name));
      await tester.pumpAndSettle();

      // Tap clear menu item
      await tester.tap(find.byKey(const ValueKey('clear-board-menu-item')));
      await tester.pumpAndSettle();

      // Dialog is now open!
      expect(find.byKey(const ValueKey('clear-board-dialog')), findsOneWidget);

      // Dismiss dialog
      await tester.tap(find.byKey(const ValueKey('clear-board-cancel-btn')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('clear-board-dialog')), findsNothing);

      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'WP02-N: cancel clear board keeps all tasks intact (including hidden and completed)',
    (tester) async {
      viewport(tester, const Size(390, 844));
      final store = await setup(tester);
      final b1Id = store.activeBoardId;

      // Add tasks across Q1-Q4 on Board 1, some completed
      final t1 = store.newTask('Task Q1', quadrant: qDo);
      final t2 = store.newTask('Task Q2', quadrant: qPlan);
      final t3 = store.newTask('Task Q3', quadrant: qDelegate)..completed = true;
      final t4 = store.newTask('Task Q4', quadrant: qEliminate)..completed = true;
      store.addTasks([t1, t2, t3, t4]);

      // Enable hide completed
      store.updateSettings((s) => s..hideCompleted = true);

      await tester.pumpWidget(app(store, const MatrixHome()));
      await tester.pumpAndSettle();

      expect(store.boardTaskCount(b1Id), 4);

      // Open board switcher
      await tester.tap(find.text(store.boards.first.name));
      await tester.pumpAndSettle();

      // Tap clear board
      await tester.tap(find.byKey(const ValueKey('clear-board-menu-item')));
      await tester.pumpAndSettle();

      // Dialog shows board name and count 4
      expect(find.byKey(const ValueKey('clear-board-dialog')), findsOneWidget);
      expect(find.textContaining('4'), findsOneWidget);

      // Tap Cancel
      await tester.tap(find.byKey(const ValueKey('clear-board-cancel-btn')));
      await tester.pumpAndSettle();

      // All 4 tasks still intact in store
      expect(store.boardTaskCount(b1Id), 4);
      expect(store.tasks.where((t) => t.boardId == b1Id).length, 4);

      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'WP02-N: confirm clear board deletes all 4 quadrants, completed/hidden tasks, resets selection/focus, keeps other boards',
    (tester) async {
      viewport(tester, const Size(390, 844));
      final store = await setup(tester);
      final b1Id = store.activeBoardId;

      // Tasks on Board 1
      final t1 = store.newTask('B1 Q1', quadrant: qDo);
      final t2 = store.newTask('B1 Q2', quadrant: qPlan)..completed = true;
      final t3 = store.newTask('B1 Q3', quadrant: qDelegate);
      final t4 = store.newTask('B1 Q4', quadrant: qEliminate)..completed = true;
      t1.subtasks.add(SubTask(id: 's1', title: 'child 1'));
      store.addTasks([t1, t2, t3, t4]);

      // Create Board 2 with tasks
      store.createBoard('Board 2');
      final b2Id = store.boards.firstWhere((b) => b.name == 'Board 2').id;
      final t2_1 = Task(id: 't2-1', boardId: b2Id, title: 'B2 Task 1', quadrant: qDo, createdAt: 1);
      final t2_2 = Task(id: 't2-2', boardId: b2Id, title: 'B2 Task 2', quadrant: qPlan, createdAt: 2);
      store.tasks.addAll([t2_1, t2_2]);

      // Switch back to Board 1
      store.setActiveBoard(b1Id);
      store.updateSettings((s) => s..hideCompleted = true);

      await tester.pumpWidget(app(store, const MatrixHome()));
      await tester.pumpAndSettle();

      // Enter selection mode and select B1 Q1
      await tester.tap(find.byTooltip(store.t['selectionMode']!));
      await tester.pumpAndSettle();
      await tester.tap(find.text('B1 Q1'));
      await tester.pumpAndSettle();

      // Open board menu and tap clear
      await tester.tap(find.text(store.boards.first.name));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('clear-board-menu-item')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('clear-board-confirm-btn')));
      await tester.pumpAndSettle();

      // SnackBar shown
      expect(find.text(store.t['boardCleared']!), findsOneWidget);

      // Board 1 has 0 tasks
      expect(store.boardTaskCount(b1Id), 0);
      expect(store.tasks.where((t) => t.boardId == b1Id), isEmpty);
      expect(store.tasksIn(qDo), isEmpty);
      expect(store.tasksIn(qPlan), isEmpty);
      expect(store.tasksIn(qDelegate), isEmpty);
      expect(store.tasksIn(qEliminate), isEmpty);

      // Board 2 tasks completely untouched
      expect(store.boardTaskCount(b2Id), 2);
      expect(store.tasks.where((t) => t.boardId == b2Id).length, 2);

      // Both boards still exist
      expect(store.boards.length, 2);

      // Export json has 0 tasks for Board 1 and 2 tasks for Board 2
      final exportMap = jsonDecode(store.exportJson()) as Map<String, dynamic>;
      final exportedTasks = (exportMap['tasks'] as List).cast<Map<String, dynamic>>();
      expect(exportedTasks.where((t) => t['boardId'] == b1Id), isEmpty);
      expect(exportedTasks.where((t) => t['boardId'] == b2Id).length, 2);

      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'WP02-N: in-flight AI submission does not resurrect tasks on cleared board',
    (tester) async {
      viewport(tester, const Size(390, 844));
      final ai = ControlledAI();
      final store = await setup(tester, ai: ai);
      final b1Id = store.activeBoardId;

      store.addTasks([
        Task(
          id: 't1',
          boardId: b1Id,
          title: 'Existing task',
          quadrant: qDo,
          createdAt: 1,
        ),
      ]);
      expect(store.boardTaskCount(b1Id), 1);

      await tester.pumpWidget(
        app(
          store,
          const Scaffold(
            body: InputSheet(
              initialMode: InputModePref.brainDump,
              embedded: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Enter text into AI brain dump
      await tester.enterText(
        find.byKey(const ValueKey('task-input')),
        'Test AI task to be cleared',
      );
      await tester.pumpAndSettle();

      // Submit AI request (enters in-flight state)
      await tester.tap(find.byKey(const ValueKey('submit-tasks')));
      await tester.pump();

      // Clear board while AI request is in-flight
      final beforeEpoch = store.boardEpoch(b1Id);
      store.clearBoard(b1Id);
      expect(store.boardEpoch(b1Id), greaterThan(beforeEpoch));

      // Now complete AI future
      ai.analysis.complete([
        AIAnalysisResult(title: 'Resurrected Task', quadrant: qDo),
      ]);
      await tester.pumpAndSettle();

      // Verify that no task was added to Board 1, and input kept error message shown
      expect(store.boardTaskCount(b1Id), 0);
      expect(store.tasks.where((t) => t.boardId == b1Id), isEmpty);
      expect(find.text(store.t['boardUnavailable']!), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'WP01-N: provider switching clears API key, updates defaults, and toggles thinking option',
    (tester) async {
      final ai = ControlledAI();
      final store = await setup(tester, ai: ai);
      await tester.pumpWidget(app(store, const SettingsScreen()));
      await tester.pumpAndSettle();

      // Scroll to AI section
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('thinking-switch')),
        50,
        scrollable: find.byType(Scrollable).first,
      );

      // Default provider is DeepSeek
      expect(store.aiConfig.provider, 'deepseek');
      expect(find.byKey(const ValueKey('thinking-switch')), findsOneWidget);

      // Enter API key
      await tester.enterText(
        find.byKey(const ValueKey('api-key-input')),
        'sk-secret-deepseek',
      );
      await tester.pumpAndSettle();
      expect(store.aiConfig.apiKey, 'sk-secret-deepseek');

      // Switch provider to Volcengine
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('provider-selector')),
        -50,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const ValueKey('provider-selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(store.t['providerVolcengine']!).last);
      await tester.pumpAndSettle();

      // Key should be cleared to prevent cross-provider leakage
      expect(store.aiConfig.provider, 'volcengine');
      expect(store.aiConfig.apiKey, '');
      final apiKeyField = tester.widget<TextField>(find.byKey(const ValueKey('api-key-input')));
      expect(apiKeyField.controller?.text, '');

      // Thinking switch is not present for Volcengine (does not support proprietary thinking)
      expect(find.byKey(const ValueKey('thinking-switch')), findsNothing);

      // Switch to Custom
      await tester.tap(find.byKey(const ValueKey('provider-selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(store.t['providerCustom']!).last);
      await tester.pumpAndSettle();

      // Custom directly exposes protocol and base URL
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('base-url-input')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const ValueKey('protocol-selector')), findsOneWidget);
      expect(find.byKey(const ValueKey('base-url-input')), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'WP01-N: entering API key triggers model discovery on submit, populates dropdown and allows manual override',
    (tester) async {
      final ai = ControlledAI();
      final discoveryCompleter = Completer<List<String>>();
      int fetchCalls = 0;
      ai.onFetchModels = ({required config, bool forceRefresh = false, cancellation}) {
        fetchCalls++;
        return discoveryCompleter.future;
      };

      final store = await setup(tester, ai: ai);
      await tester.pumpWidget(app(store, const SettingsScreen()));
      await tester.pumpAndSettle();

      // Scroll to AI section
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('api-key-input')),
        400,
        scrollable: find.byType(Scrollable).first,
      );

      // Initially, model selector dropdown does not exist; only model-input textfield
      expect(find.byKey(const ValueKey('model-input')), findsOneWidget);
      expect(find.byKey(const ValueKey('model-selector')), findsNothing);

      // Enter API key and submit
      await tester.enterText(
        find.byKey(const ValueKey('api-key-input')),
        'sk-test-ds-key',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      // Expect fetchModels called and fetching indicator shown
      expect(fetchCalls, 1);
      expect(find.text(store.t['fetchingModels']!), findsOneWidget);

      // Complete model discovery
      discoveryCompleter.complete(['deepseek-chat', 'deepseek-v4-flash', 'deepseek-reasoner']);
      await tester.pumpAndSettle();

      // Discovered models dropdown is now visible with preferred model auto-selected
      expect(find.byKey(const ValueKey('model-selector')), findsOneWidget);
      expect(store.aiConfig.model, 'deepseek-v4-flash');

      // Select custom manual override
      await tester.tap(find.byKey(const ValueKey('model-selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(store.t['customModelOption']!).last);
      await tester.pumpAndSettle();

      // Now manual text field is shown
      expect(find.byKey(const ValueKey('model-input')), findsOneWidget);

      // Tapping the list icon toggles back to dropdown
      final listIcon = find.descendant(
        of: find.byKey(const ValueKey('model-input')),
        matching: find.byIcon(Icons.list),
      );
      expect(listIcon, findsOneWidget);
      await tester.tap(listIcon);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('model-selector')), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'WP07-N: header completed-btn opens CompletedScreen, displays empty state, and switches scope between current board and all boards',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final store = await setup(tester);
      final b1Id = store.activeBoardId;
      store.createBoard('Board Two');
      final b2Id = store.boards.firstWhere((b) => b.name == 'Board Two').id;
      store.setActiveBoard(b1Id);

      final tActive = store.newTask('Active on B1', quadrant: qDo);
      final tDoneB2 = Task(
        id: 't-done-b2',
        boardId: b2Id,
        title: 'Done on B2',
        quadrant: qPlan,
        completed: true,
        createdAt: 201,
      );
      store.addTasks([tActive, tDoneB2]);

      await tester.pumpWidget(app(store, const MatrixHome()));
      await tester.pumpAndSettle();

      // Find completed-btn in header and tap it
      expect(find.byKey(const ValueKey('completed-btn')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('completed-btn')));
      await tester.pumpAndSettle();

      // In CompletedScreen: scope defaults to currentBoard ('b1Id'), which has no completed tasks
      expect(find.text(store.t['completedTasks']!), findsOneWidget);
      expect(find.byKey(const ValueKey('completed-scope-current')), findsOneWidget);
      expect(find.byKey(const ValueKey('completed-scope-all')), findsOneWidget);
      expect(find.text(store.t['noCompletedTasks']!), findsOneWidget);

      // Switch scope to all boards
      await tester.tap(find.byKey(const ValueKey('completed-scope-all')));
      await tester.pumpAndSettle();

      // Now B2's completed task is visible
      expect(find.text(store.t['noCompletedTasks']!), findsNothing);
      expect(find.text('Done on B2'), findsOneWidget);
      expect(find.text('Board Two'), findsOneWidget);
      expect(find.text(store.t['q$qPlan']!), findsOneWidget);

      // Switch back to current board
      await tester.tap(find.byKey(const ValueKey('completed-scope-current')));
      await tester.pumpAndSettle();
      expect(find.text(store.t['noCompletedTasks']!), findsOneWidget);

      // Back button pops back to MatrixHome
      await tester.tap(find.byKey(const ValueKey('completed-back-btn')));
      await tester.pumpAndSettle();
      expect(find.text('Active on B1'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'WP07-N: CompletedScreen unchecking or tapping restore button restores task to original quadrant and shows SnackBar',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final store = await setup(tester);
      final tDone = store.newTask('Finished Task', quadrant: qDo)..completed = true;
      store.addTasks([tDone]);

      // Hide completed on main matrix
      store.updateSettings((s) => s..hideCompleted = true);

      await tester.pumpWidget(app(store, const MatrixHome()));
      await tester.pumpAndSettle();

      // Initially on MatrixHome, because hideCompleted is true, tDone is not visible
      expect(find.text('Finished Task'), findsNothing);

      // Open CompletedScreen
      await tester.tap(find.byKey(const ValueKey('completed-btn')));
      await tester.pumpAndSettle();

      // In CompletedScreen, task is visible despite hideCompleted
      expect(find.text('Finished Task'), findsOneWidget);
      expect(find.byKey(ValueKey('completed-restore-${tDone.id}')), findsOneWidget);

      // Tap restore button
      await tester.tap(find.byKey(ValueKey('completed-restore-${tDone.id}')));
      await tester.pump();

      // SnackBar is displayed
      expect(find.text(store.t['taskRestored']!), findsOneWidget);
      await tester.pumpAndSettle();

      // CompletedScreen now shows empty state
      expect(find.text(store.t['noCompletedTasks']!), findsOneWidget);

      // Return to MatrixHome
      await tester.tap(find.byKey(const ValueKey('completed-back-btn')));
      await tester.pumpAndSettle();

      // Back on MatrixHome: task is restored (completed == false) so it is now visible in Q1!
      expect(find.text('Finished Task'), findsOneWidget);
      expect(store.tasks.first.completed, isFalse);

      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'WP08-V-N: toggle view mode between grid and list via header button',
    (tester) async {
      viewport(tester, const Size(400, 800));
      final store = await setup(tester);
      final t1 = store.newTask('Task Alpha', quadrant: qDo);
      final t2 = store.newTask('Task Beta', quadrant: qPlan);
      store.addTasks([t1, t2]);

      await tester.pumpWidget(app(store, const MatrixHome()));
      await tester.pumpAndSettle();

      // Initially grid mode: 4 QuadrantPane instances, 0 TaskListView
      expect(find.byType(QuadrantPane), findsNWidgets(4));
      expect(find.byType(TaskListView), findsNothing);
      expect(find.text('Task Alpha'), findsOneWidget);
      expect(find.text('Task Beta'), findsOneWidget);

      // Tap view mode toggle button in header
      await tester.tap(find.byKey(const ValueKey('view-mode-toggle-btn')));
      await tester.pumpAndSettle();

      // Now in list mode: 1 TaskListView instance, 0 QuadrantPane
      expect(find.byType(TaskListView), findsOneWidget);
      expect(find.byType(QuadrantPane), findsNothing);
      expect(store.settings.viewMode, ViewMode.list);

      // Check quadrant headers in list view
      expect(find.byKey(const ValueKey('list-quadrant-header-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('list-quadrant-header-2')), findsOneWidget);
      expect(find.byKey(const ValueKey('list-quadrant-header-3')), findsOneWidget);
      expect(find.byKey(const ValueKey('list-quadrant-header-4')), findsOneWidget);

      // Tasks are visible in list view
      expect(find.text('Task Alpha'), findsOneWidget);
      expect(find.text('Task Beta'), findsOneWidget);

      // Tap toggle button again: switches back to grid mode
      await tester.tap(find.byKey(const ValueKey('view-mode-toggle-btn')));
      await tester.pumpAndSettle();

      expect(find.byType(QuadrantPane), findsNWidgets(4));
      expect(find.byType(TaskListView), findsNothing);
      expect(store.settings.viewMode, ViewMode.grid);

      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'WP08-V-N: list view task completion, quadrant focus transition, and settings viewMode choice',
    (tester) async {
      viewport(tester, const Size(400, 800));
      final store = await setup(tester);
      final t1 = store.newTask('List Item One', quadrant: qDo);
      store.addTasks([t1]);
      store.setViewMode(ViewMode.list);

      await tester.pumpWidget(app(store, const MatrixHome()));
      await tester.pumpAndSettle();

      expect(find.byType(TaskListView), findsOneWidget);

      // Tap checkbox to complete task
      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();
      expect(store.tasks.first.completed, isTrue);

      // Tap quadrant header in list view: enters single quadrant focus view
      await tester.tap(find.byKey(const ValueKey('list-quadrant-header-1')));
      await tester.pumpAndSettle();
      expect(find.byType(QuadrantFocusView), findsOneWidget);

      // Exit focus view: returns to list view
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.byType(TaskListView), findsOneWidget);

      // Tap task text to open edit sheet
      await tester.tap(find.text('List Item One'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('edit-title')), findsOneWidget);

      // Close edit sheet
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      // Toggle view mode via store.setViewMode and store.toggleViewMode
      store.setViewMode(ViewMode.grid);
      await tester.pumpAndSettle();
      expect(find.byType(QuadrantPane), findsNWidgets(4));
      expect(find.byType(TaskListView), findsNothing);

      store.toggleViewMode();
      await tester.pumpAndSettle();
      expect(find.byType(TaskListView), findsOneWidget);
      expect(store.settings.viewMode, ViewMode.list);

      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'WP08-T-N: SettingsScreen font size and font family controls, preview, and reset defaults',
    (tester) async {
      viewport(tester, const Size(400, 900));
      final store = await setup(tester);

      await tester.pumpWidget(app(store, const SettingsScreen()));
      await tester.pumpAndSettle();

      // Scroll to Font & Display section
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('font-preview-card')),
        400,
        scrollable: find.byType(Scrollable).first,
      );

      // Verify preview card is visible
      expect(find.byKey(const ValueKey('font-preview-card')), findsOneWidget);
      expect(find.text(store.t['fontPreview']!), findsOneWidget);

      // Select 'large' font size
      await tester.tap(find.byKey(const ValueKey('font-size-large')));
      await tester.pumpAndSettle();
      expect(store.settings.fontSize, FontSizePref.large);

      // Select 'serif' font family
      await tester.tap(find.byKey(const ValueKey('font-family-serif')));
      await tester.pumpAndSettle();
      expect(store.settings.fontFamily, FontFamilyPref.serif);

      // Tap reset display button
      await tester.tap(find.byKey(const ValueKey('reset-display-btn')));
      await tester.pumpAndSettle();
      expect(store.settings.fontSize, FontSizePref.standard);
      expect(store.settings.fontFamily, FontFamilyPref.system);

      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'WP08-T-N: CombinedTextScaler respects both system scaling and app font scale without disabling TextScaler',
    (tester) async {
      final baseScaler = TextScaler.linear(1.3);
      final smallCombined = CombinedTextScaler(baseScaler, fontScaleFactor(FontSizePref.small));
      final stdCombined = CombinedTextScaler(baseScaler, fontScaleFactor(FontSizePref.standard));
      final largeCombined = CombinedTextScaler(baseScaler, fontScaleFactor(FontSizePref.large));

      // Font size 14 with system 1.3x and small (0.88x)
      expect(smallCombined.scale(14), closeTo(14 * 1.3 * 0.88, 0.001));
      // Font size 14 with system 1.3x and standard (1.0x)
      expect(stdCombined.scale(14), closeTo(14 * 1.3 * 1.0, 0.001));
      // Font size 14 with system 1.3x and large (1.16x)
      expect(largeCombined.scale(14), closeTo(14 * 1.3 * 1.16, 0.001));

      // Equality and hashcode
      expect(smallCombined, equals(CombinedTextScaler(baseScaler, fontScaleFactor(FontSizePref.small))));
      expect(smallCombined.hashCode, equals(CombinedTextScaler(baseScaler, fontScaleFactor(FontSizePref.small)).hashCode));
    },
  );

  testWidgets(
    'WP24-N: horizontal swipe right completes task, shows SnackBar with Undo action, tapping Undo restores task',
    (tester) async {
      viewport(tester, const Size(800, 600));
      final store = await setup(tester);
      final t = store.newTask('Task to Complete', quadrant: qDo);
      store.addTasks([t]);

      await tester.pumpWidget(app(store, const MatrixHome()));
      await tester.pumpAndSettle();

      expect(t.completed, isFalse);

      // Swipe right on the task card (startToEnd)
      await tester.drag(find.text('Task to Complete'), const Offset(300, 0));
      await tester.pumpAndSettle();

      // Task should be marked complete
      expect(t.completed, isTrue);

      // Undo SnackBar should be displayed
      expect(find.byKey(const ValueKey('task-undo-snackbar')), findsOneWidget);
      expect(find.byKey(const ValueKey('undo-action-btn')), findsOneWidget);
      expect(find.textContaining('Task to Complete'), findsWidgets);

      // Tap Undo
      await tester.tap(find.byKey(const ValueKey('undo-action-btn')));
      await tester.pumpAndSettle();

      // Task should be restored to incomplete
      expect(t.completed, isFalse);

      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'WP24-N: horizontal swipe left deletes task, shows SnackBar with Undo action, tapping Undo restores task',
    (tester) async {
      viewport(tester, const Size(800, 600));
      final store = await setup(tester);
      final t = store.newTask('Task to Swipe Delete', quadrant: qDo);
      store.addTasks([t]);

      await tester.pumpWidget(app(store, const MatrixHome()));
      await tester.pumpAndSettle();

      expect(store.tasksIn(qDo).map((x) => x.title), contains('Task to Swipe Delete'));

      // Swipe left on the task card (endToStart)
      await tester.drag(find.text('Task to Swipe Delete'), const Offset(-400, 0));
      await tester.pumpAndSettle();

      // Task should be deleted
      expect(store.tasksIn(qDo), isEmpty);
      expect(find.text('Task to Swipe Delete'), findsNothing);

      // Undo SnackBar should be displayed
      expect(find.byKey(const ValueKey('task-undo-snackbar')), findsOneWidget);
      expect(find.byKey(const ValueKey('undo-action-btn')), findsOneWidget);

      // Tap Undo
      await tester.tap(find.byKey(const ValueKey('undo-action-btn')));
      await tester.pumpAndSettle();

      // Task should be restored
      expect(store.tasksIn(qDo).map((x) => x.title), contains('Task to Swipe Delete'));
      expect(find.text('Task to Swipe Delete'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'WP24-N: multi-select mode disables swipe dismissible',
    (tester) async {
      viewport(tester, const Size(800, 600));
      final store = await setup(tester);
      final t = store.newTask('MultiSelect Task', quadrant: qDo);
      store.addTasks([t]);

      await tester.pumpWidget(app(store, const MatrixHome()));
      await tester.pumpAndSettle();

      // Enter multi-select mode
      await tester.tap(find.byTooltip(store.t['multiSelect'] ?? 'Multi-select'));
      await tester.pumpAndSettle();

      // Check Dismissible has direction none
      final dismissible = tester.widget<Dismissible>(find.byKey(ValueKey('dismiss-${t.id}')));
      expect(dismissible.direction, DismissDirection.none);

      // Swipe should not delete or complete the task
      await tester.drag(find.text('MultiSelect Task'), const Offset(-300, 0));
      await tester.pumpAndSettle();
      expect(store.tasksIn(qDo).length, 1);
      expect(t.completed, isFalse);

      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'WP24-N: context menu offers complete, delete, and undo operations',
    (tester) async {
      viewport(tester, const Size(800, 600));
      final store = await setup(tester);
      final t = store.newTask('Context Menu Task', quadrant: qDo);
      store.addTasks([t]);

      await tester.pumpWidget(app(store, const MatrixHome()));
      await tester.pumpAndSettle();

      // Right-click / secondary click on task
      final cardFinder = find.text('Context Menu Task');
      final center = tester.getCenter(cardFinder);
      final gesture = await tester.startGesture(center, kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
      await gesture.up();
      await tester.pumpAndSettle();

      // Verify menu items
      expect(find.byKey(ValueKey('context-complete-${t.id}')), findsOneWidget);
      expect(find.byKey(ValueKey('context-delete-${t.id}')), findsOneWidget);
      expect(find.byKey(ValueKey('move-to-q$qPlan-${t.id}')), findsOneWidget);

      // Tap complete from context menu
      await tester.tap(find.byKey(ValueKey('context-complete-${t.id}')));
      await tester.pumpAndSettle();

      expect(t.completed, isTrue);
      expect(find.byKey(const ValueKey('task-undo-snackbar')), findsOneWidget);

      // Tap Undo
      await tester.tap(find.byKey(const ValueKey('undo-action-btn')));
      await tester.pumpAndSettle();
      expect(t.completed, isFalse);

      // Right-click again and delete
      final gesture2 = await tester.startGesture(center, kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
      await gesture2.up();
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(ValueKey('context-delete-${t.id}')));
      await tester.pumpAndSettle();

      expect(store.tasksIn(qDo), isEmpty);
      expect(find.byKey(const ValueKey('task-undo-snackbar')), findsOneWidget);

      // Tap Undo to restore
      await tester.tap(find.byKey(const ValueKey('undo-action-btn')));
      await tester.pumpAndSettle();
      expect(store.tasksIn(qDo).length, 1);

      await tester.pumpWidget(const SizedBox());
    },
  );
}

