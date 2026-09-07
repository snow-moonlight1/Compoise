import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/ai_service.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/screens/matrix_screen.dart';
import 'package:matrixflow_native/screens/settings_screen.dart';
import 'package:matrixflow_native/storage.dart';
import 'package:matrixflow_native/theme.dart';
import 'package:matrixflow_native/widgets/input_sheet.dart';
import 'package:matrixflow_native/widgets/task_card.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ControlledAI extends AIService {
  Completer<List<AIAnalysisResult>> analysis = Completer();
  Completer<List<DecomposeResult>> decomposition = Completer();
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

Future<Store> setup(WidgetTester tester, {AIService? ai}) async {
  SharedPreferences.setMockInitialValues({});
  late Store store;
  await tester.runAsync(() async {
    store = Store(aiService: ai);
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
        theme: buildTheme(Brightness.light, ThemeColor.blue),
        locale: Locale(store.settings.language.name),
        supportedLocales: const [Locale('en'), Locale('zh'), Locale('ja')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        builder:
            (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
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
        tester.getCenter(find.text('Plan')) + const Offset(0, 80),
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
    await tester.tap(find.byTooltip('Select'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('alpha'));
    await tester.tap(find.text('beta'));
    await tester.pumpAndSettle();
    expect(a.completed, isFalse);
    await tester.tap(find.text('Group (2)'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'combined');
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(store.tasks.single.title, 'combined');
    expect(store.tasks.single.subtasks, hasLength(2));
    await tester.tap(find.byTooltip('Select'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byTooltip('Select'), findsOneWidget);
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
}
