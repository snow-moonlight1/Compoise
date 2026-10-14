// Every input field (TextField, TextFormField, DropdownButtonFormField,
// search field) keeps its value, or its hint when empty, vertically centered
// in the visible well, in all three themes. A neumorphic floating label sits
// above the well and the value is centered in what is left.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:compoise/import_preview/draft_model.dart';
import 'package:compoise/import_preview/draft_preview.dart';
import 'package:compoise/l10n.dart';
import 'package:compoise/models.dart';
import 'package:compoise/planner/schedule_edit_session.dart';
import 'package:compoise/planner/schedule_editor.dart';
import 'package:compoise/platform/device_time_zone_picker.dart';
import 'package:compoise/schedule_item.dart';
import 'package:compoise/schedule_time.dart';
import 'package:compoise/screens/search_screen.dart';
import 'package:compoise/screens/settings_screen.dart';
import 'package:compoise/storage.dart';
import 'package:compoise/theme.dart';
import 'package:compoise/widgets/input_sheet.dart';
import 'package:compoise/widgets/subtask_edit_dialog.dart';
import 'package:compoise/widgets/task_detail_panel.dart';
import 'package:compoise/widgets/text_prompt.dart';
import 'package:provider/provider.dart';

import 'helpers.dart';
import 'planner_test_support.dart';
import 'support/field_center_probe.dart';
import 'support/settings_panels.dart';

enum _Skin { plain, comic, neu }

Widget _app(Store store, _Skin skin, Widget home) =>
    ChangeNotifierProvider.value(
      value: store,
      child: MaterialApp(
        theme: buildTheme(
          Brightness.light,
          ThemeColor.purple,
          comicOutline: skin == _Skin.comic,
          neumorphic: skin == _Skin.neu,
        ),
        locale: const Locale('zh'),
        supportedLocales: const [Locale('en'), Locale('zh'), Locale('ja')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: home,
      ),
    );

Future<Store> _store(_Skin skin, {List<Task>? tasks}) async {
  final (store, _) = await makeStore(
    boards: tasks == null ? null : [Board(id: 'b', name: '我的任务', createdAt: 1)],
    tasks: tasks,
    settings: AppSettings(
      language: Language.zh,
      neumorphic: skin == _Skin.neu,
      comicOutline: skin == _Skin.comic,
      themeColor: ThemeColor.purple,
    ),
  );
  return store;
}

Task _task() => Task(
  id: 'task-1',
  boardId: 'b',
  title: '下周三前交水电费',
  quadrant: 1,
  createdAt: 1,
  subtasks: [SubTask(id: 's1', title: '查账单')],
);

/// Opens [open] from a button so dialogs get a real route.
Widget _launcher(void Function(BuildContext) open) => Scaffold(
  body: Builder(
    builder: (context) => Center(
      child: TextButton(
        onPressed: () => open(context),
        child: const Text('open'),
      ),
    ),
  ),
);

void main() {
  final seen = <String>{};
  Future<void> check(WidgetTester tester, String where) async {
    final fields = measureFields(tester);
    for (final f in fields) {
      seen.add('$where ${f.name}');
    }
    final bad = fields
        .where((f) => f.offset.abs() > 1.5 || (f.labelGap ?? 0) < -1)
        .toList();
    expect(bad, isEmpty, reason: '$where\n${bad.join('\n')}');
  }

  for (final skin in _Skin.values) {
    testWidgets('${skin.name}: edit task sheet', (tester) async {
      await tester.binding.setSurfaceSize(const Size(411, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final store = await _store(skin, tasks: [_task()]);
      final task = store.tasks.single;
      await tester.pumpWidget(
        _app(store, skin, Scaffold(body: TaskDetailPanel(task: task))),
      );
      await tester.pumpAndSettle();
      expect(measureFields(tester).length, greaterThanOrEqualTo(2));
      await check(tester, 'edit task');
      await tester.enterText(
        find.byKey(const ValueKey('edit-new-subtask')),
        '打印',
      );
      await tester.pumpAndSettle();
      await check(tester, 'edit task typed');
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    });

    testWidgets('${skin.name}: settings assistant fields', (tester) async {
      await tester.binding.setSurfaceSize(const Size(411, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final store = await _store(skin);
      await tester.pumpWidget(_app(store, skin, const SettingsScreen()));
      await tester.pumpAndSettle();
      await openSettingsPanel(tester, 'settings-assistant-row');
      expect(measureFields(tester).length, greaterThanOrEqualTo(2));
      await check(tester, 'assistant empty');
      for (final field in find.byType(TextField).evaluate().toList()) {
        await tester.enterText(find.byWidget(field.widget), 'sk-test');
      }
      await tester.pumpAndSettle();
      await check(tester, 'assistant filled');
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    });

    testWidgets('${skin.name}: search field', (tester) async {
      await tester.binding.setSurfaceSize(const Size(411, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final store = await _store(skin);
      await tester.pumpWidget(_app(store, skin, const SearchScreen()));
      await tester.pumpAndSettle();
      await check(tester, 'search empty');
      await tester.enterText(find.byType(TextField).first, '水电费');
      await tester.pumpAndSettle();
      await check(tester, 'search typed');
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    });

    testWidgets('${skin.name}: add task sheet', (tester) async {
      await tester.binding.setSurfaceSize(const Size(411, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final store = await _store(skin);
      await tester.pumpWidget(
        _app(
          store,
          skin,
          const Scaffold(
            body: InputSheet(initialMode: InputModePref.single, embedded: true),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await check(tester, 'add task empty');
      await tester.enterText(find.byType(TextField).first, '交水电费');
      await tester.pumpAndSettle();
      await check(tester, 'add task typed');
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    });

    testWidgets('${skin.name}: dialogs with fields', (tester) async {
      await tester.binding.setSurfaceSize(const Size(411, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final store = await _store(skin);
      final t = dictOf(Language.zh);
      Future<void> run(String where, void Function(BuildContext) open) async {
        await tester.pumpWidget(_app(store, skin, _launcher(open)));
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        await check(tester, where);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      }

      await run(
        'subtask dialog',
        (c) => showSubtaskEditDialog(
          c,
          t: t,
          subtask: SubTask(id: 's', title: '查账单'),
        ),
      );
      await run(
        'text prompt',
        (c) => askText(
          c,
          title: '重命名',
          label: '名称',
          cancel: '取消',
          confirm: '确定',
          initial: '我的任务',
        ),
      );
      await run('zone picker', (c) => showScheduleZonePicker(c, t: t));
      store.dispose();
    });

    testWidgets('${skin.name}: schedule editor title', (tester) async {
      await tester.binding.setSurfaceSize(const Size(411, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final store = await c2Store();
      final session = ScheduleEditSession.create(
        store,
        ScheduleItemKind.event,
        c1Zone,
        ScheduleCivilDate(2026, 9, 30),
      )..title = '组会';
      await tester.pumpWidget(
        _app(store, skin, _launcher((c) => showScheduleEditor(c, session))),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(measureFields(tester), isNotEmpty);
      await check(tester, 'schedule editor');
      await tester.pumpWidget(const SizedBox());
      await store.flush(waitForReminders: false);
      store.dispose();
    });

    testWidgets('${skin.name}: screenshot review page', (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final batch = DraftBatch.fromJson({
        'schema': 'wp17r2-draft/1',
        'images': [
          {
            'schema': 'wp17r2-draft/1',
            'id': 'one',
            'width': 1080,
            'height': 1403,
            'engine': 'ncnn-ppocrv5-mobile',
            'rows': [],
            'noise_lines': [],
            'notes': [],
            'tasks': [
              {
                'row': 3,
                'title': '周五前提交季度报告',
                'checked': false,
                'level': 0,
                'parent': null,
                'due': '周五',
                'needs_confirmation': [],
              },
            ],
            'dropped': [],
          },
        ],
      });
      batch.boardId = 'board';
      batch.quadrant = 1;
      final store = await _store(skin);
      await tester.pumpWidget(
        _app(
          store,
          skin,
          Scaffold(
            body: DraftPreview(
              batch: batch,
              language: Language.zh,
              boards: const [ImportBoardChoice('board', '我的任务')],
              thumbnails: const {},
              onSubmit: (_) async {},
              onCancel: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('options-one:3')));
      await tester.pumpAndSettle();
      expect(measureFields(tester).length, greaterThanOrEqualTo(4));
      await check(tester, 'review page');
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    });
  }

  tearDownAll(() {
    // ignore: avoid_print
    print('measured ${seen.length} field states:\n${seen.join('\n')}');
  });
}
