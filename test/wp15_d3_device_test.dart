import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'dart:ui' as ui;
import 'wp15_d3_support.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/platform/device_time_zone.dart';
import 'package:matrixflow_native/schedule_item.dart';
import 'package:matrixflow_native/schedule_time.dart';
import 'package:matrixflow_native/screens/matrix_screen.dart';
import 'package:matrixflow_native/screens/planner_screen.dart';
import 'package:matrixflow_native/storage.dart';
import 'package:matrixflow_native/widgets/task_detail_panel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Disabled in the default unit/widget suite. A device run must use the runner:
// it verifies the SDK, platform identity, isolation and actual process exit.
const _enabled = bool.fromEnvironment('WP15_D3_DEVICE');
const _zone = 'America/New_York';
const _changedZone = 'Asia/Tokyo';
late String _expectedZone;
late String _dataRoot;
final _captureKey = GlobalKey();
const _commit = String.fromEnvironment('WP15_D3_COMMIT');
bool _isolated = false;
Finder _key(String value) => find.byKey(ValueKey(value));

class _NoCredentials implements CredentialStore {
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String value) async {
    if (value.isNotEmpty) throw StateError('Synthetic runs cannot store a key');
  }

  @override
  Future<void> delete() async {}
}

int _at(int month, int day, int hour, int minute, {int? offset}) =>
    resolveWallTime(
      ScheduleWallTime(
        ScheduleCivilDate(2026, month, day),
        hour: hour,
        minute: minute,
      ),
      _zone,
      offset: offset == null ? null : Duration(minutes: offset),
    );

Map<String, Object?> _fixture() => {
  'version': 3,
  'boards': [
    Board(id: 'd2-board', name: 'Synthetic D2', createdAt: 1).toJson(),
  ],
  'tasks': [
    Task(
      id: 'd2-parent',
      boardId: 'd2-board',
      title: 'D2 parent',
      quadrant: 2,
      createdAt: 1,
      urgencyMode: UrgencyMode.manual,
      plannedDate: DateTime.utc(2026, 3, 7).millisecondsSinceEpoch,
      deadline: DateTime.utc(2030, 3, 9, 23, 59, 59).millisecondsSinceEpoch,
      reminderAt: DateTime.utc(2030, 3, 9, 9).millisecondsSinceEpoch,
      notesMarkdown: 'Synthetic **parent** notes',
      tags: ['d2'],
      subtasks: [
        SubTask(
          id: 'd2-child',
          title: 'D2 child',
          completed: true,
          completedAt: 2,
          notesMarkdown: 'Synthetic child notes',
          deadline: DateTime.utc(2030, 3, 8).millisecondsSinceEpoch,
          reminderAt: DateTime.utc(2030, 3, 7).millisecondsSinceEpoch,
        ),
      ],
    ).toJson(),
  ],
  'scheduleItems': [
    ScheduleItem.timeBlock(
      id: 'overlap-block',
      taskId: 'd2-parent',
      startAt: _at(3, 8, 0, 45),
      endAt: _at(3, 8, 1, 45),
      timeZoneId: _zone,
    ),
    ScheduleItem.event(
      id: 'overlap-event',
      boardId: 'd2-board',
      title: 'D2 overlap',
      startAt: _at(3, 8, 0, 30),
      endAt: _at(3, 8, 1, 30),
      timeZoneId: _zone,
    ),
    ScheduleItem.event(
      id: 'midnight',
      taskId: 'd2-parent',
      title: 'D2 midnight',
      startAt: _at(3, 7, 23, 0),
      endAt: _at(3, 8, 0, 0),
      timeZoneId: _zone,
    ),
    ScheduleItem.event(
      id: 'cross',
      boardId: 'd2-board',
      title: 'D2 cross day',
      startAt: _at(3, 8, 23, 30),
      endAt: _at(3, 9, 0, 30),
      timeZoneId: _zone,
    ),
    ScheduleItem.event(
      id: 'fold',
      boardId: 'd2-board',
      title: 'D2 fold',
      startAt: _at(11, 1, 1, 15, offset: -240),
      endAt: _at(11, 1, 1, 45, offset: -300),
      timeZoneId: _zone,
    ),
  ].map((item) => item.toJson()).toList(),
  'settings': AppSettings(language: Language.en, reduceMotion: true).toJson(),
  'aiConfig': AIConfig().toJson(),
};

Map<String, dynamic> _content(Store store) {
  final value = jsonDecode(store.exportJson()) as Map<String, dynamic>;
  value.remove('timestamp');
  return value;
}

Future<Store> _open({SaveWrite? writer}) async {
  final store = Store(
    saveWriter: writer,
    credentialStore: _NoCredentials(),
    reminders: InMemoryReminderService(),
  );
  await store.init();
  expect(store.ready, isTrue);
  expect(store.hasStartupRecovery, isFalse);
  return store;
}

Future<Store> _fresh({SaveWrite? writer}) async {
  // The platform guard in setUpAll runs before any preferences are touched.
  final prefs = await SharedPreferences.getInstance();
  await prefs.clear();
  await prefs.setBool('matrixflow-has-seen-onboarding', true);
  final store = await _open(writer: writer);
  final plan = store.previewImport(_fixture(), 'overwrite');
  expect((await store.applyImport(plan)).success, isTrue);
  return store;
}

Widget _app(Store store, Widget home, {bool narrow = false}) =>
    ChangeNotifierProvider.value(
      value: store,
      child: RepaintBoundary(
        key: _captureKey,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          supportedLocales: const [Locale('en'), Locale('zh'), Locale('ja')],
          builder: narrow
              ? (context, child) => Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: 320,
                    child: MediaQuery(
                      data: MediaQuery.of(context).copyWith(
                        size: Size(320, MediaQuery.sizeOf(context).height),
                        textScaler: TextScaler.linear(3),
                      ),
                      child: child!,
                    ),
                  ),
                )
              : null,
          home: home,
        ),
      ),
    );

Future<void> _readMenu(WidgetTester tester) async {
  if (find.byType(PopupMenuItem<String>).evaluate().isNotEmpty) {
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
  }
  await _tap(tester, 'schedule-menu');
}

Future<void> _tap(
  WidgetTester tester,
  String key, {
  PointerDeviceKind kind = PointerDeviceKind.touch,
}) async {
  final target = _key(key);
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  final visible = tester
      .getRect(target)
      .intersect(tester.getRect(find.byType(Scaffold).first));
  expect(visible.isEmpty, isFalse);
  await tester.tapAt(visible.center, kind: kind);
  await tester.pumpAndSettle();
}

Future<void> _text(WidgetTester tester, String key, String text) async {
  await tester.ensureVisible(_key(key));
  await tester.pumpAndSettle();
  await tester.enterText(_key(key), text);
  // Dismiss the real IME so it cannot cover the following action.
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
}

Future<void> _finish(WidgetTester tester, Store store) async {
  await tester.pumpWidget(const SizedBox.shrink());
  expect((await store.flush(waitForReminders: false)).success, isTrue);
  await tester.pump();
}

Future<void> _planner(
  WidgetTester tester,
  Store store,
  int month,
  int day, {
  bool narrow = false,
}) async {
  // Mount a new route for each fixture date; initialDate is an entry hint,
  // not a command to reset an already mounted Planner state.
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.pumpWidget(
    _app(
      store,
      PlannerScreen(
        store: store,
        initialDate: ScheduleCivilDate(2026, month, day),
      ),
      narrow: narrow,
    ),
  );
  await tester.pumpAndSettle();
  expect(_key('schedule-zone-required'), findsNothing);
  await _readMenu(tester);
  await _tap(tester, 'schedule-zone-switch');
  await _text(tester, 'schedule-zone-search', _zone);
  await _tap(tester, 'schedule-zone-option-$_zone');
}

Future<void> _edit(WidgetTester tester, String date, String id) async {
  await _tap(tester, 'schedule-item-$date-$id');
  expect(_key('schedule-detail'), findsOneWidget);
  await _tap(tester, 'schedule-detail-edit');
  expect(_key('schedule-editor'), findsOneWidget);
}

Future<void> _save(
  WidgetTester tester, {
  bool keyboard = false,
  bool reviewed = false,
}) async {
  if (!reviewed) {
    await _tap(tester, 'schedule-editor-review');
    if (_key('schedule-editor-allow-overlap').evaluate().isNotEmpty) {
      await _tap(tester, 'schedule-editor-allow-overlap');
    }
  }
  if (keyboard) {
    final save = _key('schedule-editor-save');
    await tester.ensureVisible(save);
    Focus.of(
      tester.element(find.descendant(of: save, matching: find.byType(Text))),
    ).requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
  } else {
    await _tap(tester, 'schedule-editor-save');
  }
  expect(_key('schedule-editor'), findsNothing);
}

Future<void> _waitReads(WidgetTester tester, int before) async {
  final end = DateTime.now().add(const Duration(seconds: 8));
  while ((await d3Native())['reads'] as int <= before &&
      DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect((await d3Native())['reads'] as int, greaterThan(before));
  await tester.pumpAndSettle();
}

void main() {
  if (!_enabled) {
    test('WP15-D3 real device acceptance is opt-in', () {}, skip: true);
    return;
  }
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    expect(Platform.isWindows, isTrue);
    expect(_commit, isNotEmpty);
    final native = await d3Native();
    _dataRoot = await d3Isolate(native);
    final support = await getApplicationSupportDirectory();
    expect(support.path.startsWith(_dataRoot), isTrue);
    expect(native['queryInjected'], isFalse);
    final real = await defaultDeviceTimeZoneSource().read();
    final realStatus = resolveDeviceTimeZone(real);
    expect(real.identity, native['actualIdentity']);
    expect(realStatus.resolved, isTrue);
    _expectedZone = realStatus.ianaId!;
    _isolated = true;
    final reading = await defaultDeviceTimeZoneSource().read();
    final status = resolveDeviceTimeZone(reading);
    expect(status.resolved, isTrue);
    expect(status.ianaId, _expectedZone);
    debugPrint(
      'WP15_D3_PLATFORM platform=${reading.platform.name} '
      'identity=${reading.identity} iana=${status.ianaId} commit=$_commit',
    );
    binding.reportData = {
      'commit': _commit,
      'platform': reading.platform.name,
      'identity': reading.identity,
      'iana': status.ianaId,
      'native': native,
      'hostGlobalZoneChanged': false,
      'injected': [
        'Win32 query override',
        'window settings/time messages',
        'framework resume',
      ],
      'credentials': 'disabled',
      'reminders': 'in-memory',
    };
  });
  tearDown(() async {
    // Only the identity guarded above may be cleared. No real user library.
    if (_isolated) {
      await d3Control('queryOverride');
      await (await SharedPreferences.getInstance()).clear();
    }
  });

  testWidgets('real home/parent entry, failed draft, save and disk reopen', (
    tester,
  ) async {
    var fail = false;
    final store = await _fresh(
      writer: (key, value) async {
        if (fail && key == SaveProtocol.pointerKey) return false;
        return (await SharedPreferences.getInstance()).setString(key, value);
      },
    );
    try {
      await tester.pumpWidget(_app(store, const MatrixHome()));
      await tester.pumpAndSettle();
      await _tap(tester, 'more-btn');
      await _tap(tester, 'more-schedule');
      expect(find.byType(PlannerScreen), findsOneWidget);
      await _readMenu(tester);
      expect(
        find.text('${store.t['scheduleZoneDevice']}: $_expectedZone'),
        findsOneWidget,
      );
      Navigator.of(tester.element(find.byType(PlannerScreen))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.text('D2 parent').first);
      await tester.pumpAndSettle();
      await _text(tester, 'edit-title', 'D2 renamed');
      fail = true;
      await _tap(tester, 'edit-schedule-entry');
      expect(find.byType(PlannerScreen), findsNothing);
      expect(find.byType(TaskDetailPanel), findsOneWidget);
      expect(find.text(store.persistenceError!), findsWidgets);
      fail = false;
      await _tap(tester, 'edit-schedule-entry');
      expect(_key('schedule-editor'), findsOneWidget);
      expect(find.textContaining('D2 renamed'), findsWidgets);
      final protectedTask = store.tasks.single.toJson();
      await _text(tester, 'schedule-editor-start-date', '2026-03-08');
      await _text(tester, 'schedule-editor-end-date', '2026-03-08');
      await _text(tester, 'schedule-editor-start-time', '10:00');
      await _text(tester, 'schedule-editor-end-time', '11:00');
      await _save(tester);
      expect(store.tasks.single.toJson(), protectedTask);
      final expected = _content(store);
      await tester.pumpWidget(const SizedBox.shrink());
      expect((await store.flush(waitForReminders: false)).success, isTrue);
      await (await SharedPreferences.getInstance()).reload();
      final reopened = await _open();
      try {
        expect(_content(reopened), expected);
        final saved = reopened.scheduleItems.last;
        await tester.pumpWidget(
          _app(
            reopened,
            PlannerScreen(
              store: reopened,
              initialDate: ScheduleCivilDate(2026, 3, 8),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await _edit(tester, '2026-03-08', saved.id);
        expect(find.textContaining('D2 renamed'), findsWidgets);
        await _tap(tester, 'schedule-editor-cancel');
        await _finish(tester, reopened);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        reopened.dispose();
      }
      debugPrint('WP15_D3_PASS navigation draft_failure disk_reopen');
    } finally {
      fail = false;
      await tester.pumpWidget(const SizedBox.shrink());
      store.dispose();
    }
  });

  testWidgets('production time zone refresh and display choice are zero write', (
    tester,
  ) async {
    final store = await _fresh();
    try {
      await tester.pumpWidget(_app(store, PlannerScreen(store: store)));
      await tester.pumpAndSettle();
      final before = _content(store);
      if (Platform.isWindows) {
        final reads = (await d3Native())['reads'] as int;
        await d3Control('queryOverride', 'Tokyo Standard Time');
        await d3Control('settingsEvent');
        final deadline = DateTime.now().add(const Duration(seconds: 90));
        final label = '${store.t['scheduleZoneDevice']}: $_changedZone';
        while (find.text(label).evaluate().isEmpty &&
            DateTime.now().isBefore(deadline)) {
          await tester.pump(const Duration(milliseconds: 400));
          await _readMenu(tester);
        }
        expect(
          find.text(label),
          findsOneWidget,
          reason:
              'Process-local query injection must refresh through WM_SETTINGCHANGE',
        );
        expect((await d3Native())['reads'] as int, greaterThan(reads));
        expect((await d3Native())['settingsEvents'] as int, greaterThan(0));
        debugPrint('WP15_D3_PASS real_window_setting_message injected_query');
      }
      await _readMenu(tester);
      await _tap(tester, 'schedule-zone-switch');
      await _text(tester, 'schedule-zone-search', _zone);
      await _tap(tester, 'schedule-zone-option-$_zone');
      await _readMenu(tester);
      expect(
        find.text('${store.t['scheduleDisplayZone']}: $_zone'),
        findsOneWidget,
      );
      expect(_content(store), before);
      final reads = (await d3Native())['reads'] as int;
      await d3Control('queryOverride', 'China Standard Time');
      await d3Control('timeEvent');
      await _waitReads(tester, reads);
      expect((await d3Native())['timeEvents'] as int, greaterThan(0));
      expect((await d3Native())['reads'] as int, greaterThan(reads));
      await _readMenu(tester);
      expect(
        find.text('${store.t['scheduleDisplayZone']}: $_zone'),
        findsOneWidget,
      );
      expect(_content(store), before);
      final resumeReads = (await d3Native())['reads'] as int;
      await d3Control('queryOverride');
      await d3Control('resumeEvent');
      await _waitReads(tester, resumeReads);
      await _finish(tester, store);
      debugPrint(
        'WP15_D3_PASS display_zone_zero_write window_time_message resume_injected',
      );
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      store.dispose();
    }
  });

  testWidgets(
    'real DST axis, gap/fold, midnight, cross day and overlap editors',
    (tester) async {
      final store = await _fresh();
      try {
        final protectedTasks = store.tasks
            .map((task) => task.toJson())
            .toList();
        await _planner(tester, store, 3, 8);
        expect(find.text('2:00'), findsNothing);
        expect(find.text('3:00'), findsOneWidget);
        expect(_key('schedule-item-2026-03-08-midnight'), findsNothing);
        expect(_key('schedule-item-2026-03-08-cross'), findsOneWidget);
        for (final id in ['overlap-event', 'overlap-block']) {
          await _edit(tester, '2026-03-08', id);
          await _text(tester, 'schedule-editor-start-time', '01:00');
          await _save(tester);
          expect(
            store.scheduleItems.singleWhere((item) => item.id == id).startAt,
            _at(3, 8, 1, 0),
          );
        }
        await _tap(tester, 'schedule-mode-week');
        expect(_key('schedule-day-2026-03-02'), findsOneWidget);
        await _tap(tester, 'schedule-mode-day');
        await _tap(tester, 'schedule-next');
        expect(_key('schedule-item-2026-03-09-cross'), findsOneWidget);
        await _edit(tester, '2026-03-09', 'cross');
        await _tap(tester, 'schedule-editor-cancel');
        await _planner(tester, store, 11, 1);
        expect(find.text('1:00'), findsNWidgets(2));
        await _edit(tester, '2026-11-01', 'fold');
        expect(
          tester
              .widget<RadioListTile<Duration>>(
                _key('schedule-editor-start-offset--240'),
              )
              .groupValue,
          const Duration(minutes: -240),
        );
        expect(
          tester
              .widget<RadioListTile<Duration>>(
                _key('schedule-editor-end-offset--300'),
              )
              .groupValue,
          const Duration(minutes: -300),
        );
        final foldBefore = store.scheduleItems
            .singleWhere((i) => i.id == 'fold')
            .toJson();
        await _save(tester);
        expect(
          store.scheduleItems.singleWhere((i) => i.id == 'fold').toJson(),
          foldBefore,
        );
        await _tap(tester, 'schedule-add');
        await _tap(tester, 'schedule-create-event');
        await _text(tester, 'schedule-editor-title', 'D2 gap then fold');
        await _tap(tester, 'schedule-editor-choose-association');
        await _tap(tester, 'schedule-editor-association-d2-board');
        await _text(tester, 'schedule-editor-start-date', '2026-03-08');
        await _text(tester, 'schedule-editor-end-date', '2026-03-08');
        await _text(tester, 'schedule-editor-start-time', '02:30');
        await _text(tester, 'schedule-editor-end-time', '04:00');
        final beforeGap = _content(store);
        await _tap(tester, 'schedule-editor-review');
        expect(find.text(store.t['scheduleEditorGap']!), findsWidgets);
        expect(_content(store), beforeGap);
        await _text(tester, 'schedule-editor-start-date', '2026-11-01');
        await _text(tester, 'schedule-editor-end-date', '2026-11-01');
        await _text(tester, 'schedule-editor-start-time', '01:15');
        await _text(tester, 'schedule-editor-end-time', '01:45');
        await _tap(tester, 'schedule-editor-review');
        expect(_key('schedule-editor-save'), findsNothing);
        await _tap(tester, 'schedule-editor-start-offset--300');
        await _tap(tester, 'schedule-editor-end-offset--300');
        await _save(tester);
        final created = store.scheduleItems.last;
        expect(created.startAt, _at(11, 1, 1, 15, offset: -300));
        expect(created.endAt - created.startAt, 1800000);
        await _edit(tester, '2026-11-01', created.id);
        expect(
          tester
              .widget<RadioListTile<Duration>>(
                _key('schedule-editor-start-offset--300'),
              )
              .groupValue,
          const Duration(minutes: -300),
        );
        await _tap(tester, 'schedule-editor-cancel');
        expect(
          store.tasks.map((task) => task.toJson()).toList(),
          protectedTasks,
        );
        await _finish(tester, store);
        await (await SharedPreferences.getInstance()).reload();
        final reopened = await _open();
        try {
          expect(
            reopened.scheduleItems
                .singleWhere((i) => i.id == created.id)
                .toJson(),
            created.toJson(),
          );
          await _planner(tester, reopened, 11, 1);
          await _edit(tester, '2026-11-01', created.id);
          expect(
            tester
                .widget<RadioListTile<Duration>>(
                  _key('schedule-editor-start-offset--300'),
                )
                .groupValue,
            const Duration(minutes: -300),
          );
          await _tap(tester, 'schedule-editor-cancel');
          await _finish(tester, reopened);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          reopened.dispose();
        }
        debugPrint('WP15_D3_PASS DST_gap_fold_23_25 midnight cross overlap');
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        store.dispose();
      }
    },
  );

  testWidgets('320px/3x text touch, mouse, keyboard and v3 disk restore', (
    tester,
  ) async {
    final store = await _fresh();
    Directory? backupRoot;
    try {
      final ratio = tester.view.devicePixelRatio;
      await d3Control('resize', [(320 * ratio).round(), (720 * ratio).round()]);
      await tester.pumpAndSettle();
      expect((tester.view.physicalSize.width / ratio - 320).abs(), lessThan(2));
      await _planner(tester, store, 11, 1, narrow: true);
      await _tap(tester, 'schedule-mode-week', kind: PointerDeviceKind.mouse);
      await _tap(tester, 'schedule-mode-day');
      await _edit(tester, '2026-11-01', 'fold');
      await _text(tester, 'schedule-editor-title', 'D2 keyboard edited');
      await _save(tester, keyboard: true);
      expect(tester.takeException(), isNull);
      final expected = _content(store);
      final boundary =
          _captureKey.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      expect(bytes, isNotNull);
      await File(
        '$_dataRoot/planner-narrow-3x.png',
      ).writeAsBytes(bytes!.buffer.asUint8List(), flush: true);
      image.dispose();
      backupRoot = await Directory(_dataRoot).createTemp('backup-');
      final backup = File('${backupRoot.path}/synthetic-v3.json');
      await backup.writeAsString(store.exportJson(), flush: true);
      expect(jsonDecode(await backup.readAsString())['version'], 3);
      await tester.pumpWidget(const SizedBox.shrink());
      expect((await store.flush(waitForReminders: false)).success, isTrue);
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final reopened = await _open();
      try {
        expect(_content(reopened), expected);
      } finally {
        reopened.dispose();
      }
      await prefs.clear();
      final restored = await _open();
      try {
        final plan = restored.previewImport(
          jsonDecode(await backup.readAsString()) as Map<String, dynamic>,
          'overwrite',
        );
        expect((await restored.applyImport(plan)).success, isTrue);
        expect(
          _content(restored),
          expected,
          reason:
              'Deep comparison includes every serialized board/task/subtask/'
              'schedule/settings/AI field, not just collection counts',
        );
        await _planner(tester, restored, 11, 1, narrow: true);
        await _edit(tester, '2026-11-01', 'fold');
        expect(find.text('D2 keyboard edited'), findsOneWidget);
        await _tap(tester, 'schedule-editor-cancel');
        await _finish(tester, restored);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        restored.dispose();
      }
      debugPrint(
        'WP15_D3_PASS narrow_3x touch_mouse_keyboard v3_field_restore',
      );
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      store.dispose();
      await backupRoot?.delete(recursive: true);
      await d3Control('resize', [1280, 900]);
    }
  });
  testWidgets(
    'Windows messages retain an open fold draft and semantic keyboard actions',
    (tester) async {
      final store = await _fresh();
      final semantics = tester.ensureSemantics();
      try {
        await _planner(tester, store, 11, 1);
        await _edit(tester, '2026-11-01', 'fold');
        await _text(tester, 'schedule-editor-title', 'D3 Windows draft');
        final before = _content(store);
        final start = tester
            .widget<EditableText>(
              find.descendant(
                of: _key('schedule-editor-start-time'),
                matching: find.byType(EditableText),
              ),
            )
            .controller
            .text;
        final end = tester
            .widget<EditableText>(
              find.descendant(
                of: _key('schedule-editor-end-time'),
                matching: find.byType(EditableText),
              ),
            )
            .controller
            .text;
        for (final event in ['settingsEvent', 'timeEvent', 'resumeEvent']) {
          final reads = (await d3Native())['reads'] as int;
          await d3Control(
            'queryOverride',
            event == 'timeEvent'
                ? 'Eastern Standard Time'
                : 'Tokyo Standard Time',
          );
          await d3Control(event);
          await _waitReads(tester, reads);
          expect(_content(store), before);
          expect(
            tester
                .widget<EditableText>(
                  find.descendant(
                    of: _key('schedule-editor-title'),
                    matching: find.byType(EditableText),
                  ),
                )
                .controller
                .text,
            'D3 Windows draft',
          );
          expect(
            tester
                .widget<EditableText>(
                  find.descendant(
                    of: _key('schedule-editor-start-time'),
                    matching: find.byType(EditableText),
                  ),
                )
                .controller
                .text,
            start,
          );
          expect(
            tester
                .widget<EditableText>(
                  find.descendant(
                    of: _key('schedule-editor-end-time'),
                    matching: find.byType(EditableText),
                  ),
                )
                .controller
                .text,
            end,
          );
          expect(
            tester
                .widget<RadioListTile<Duration>>(
                  _key('schedule-editor-start-offset--240'),
                )
                .groupValue,
            const Duration(minutes: -240),
          );
          expect(
            tester
                .widget<RadioListTile<Duration>>(
                  _key('schedule-editor-end-offset--300'),
                )
                .groupValue,
            const Duration(minutes: -300),
          );
        }
        await tester.ensureVisible(_key('schedule-editor-title'));
        await tester.tap(_key('schedule-editor-title'));
        await tester.pumpAndSettle();
        final focus = FocusManager.instance.primaryFocus;
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        expect(FocusManager.instance.primaryFocus, isNot(same(focus)));
        await _tap(tester, 'schedule-editor-review');
        if (_key('schedule-editor-allow-overlap').evaluate().isNotEmpty) {
          await _tap(tester, 'schedule-editor-allow-overlap');
        }
        expect(
          tester
              .getSemantics(_key('schedule-editor-save'))
              .getSemanticsData()
              .hasAction(SemanticsAction.tap),
          isTrue,
        );
        await _save(tester, keyboard: true, reviewed: true);
        expect(
          store.scheduleItems.singleWhere((i) => i.id == 'fold').title,
          'D3 Windows draft',
        );
        await _finish(tester, store);
        debugPrint(
          'WP15_D3_PASS fold_draft_preserved native_messages lifecycle_injected semantics_tab_enter',
        );
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        semantics.dispose();
        store.dispose();
      }
    },
  );

  testWidgets(
    'Windows delete confirmation and real corrupt-library recovery prohibit writes',
    (tester) async {
      final store = await _fresh();
      try {
        await _planner(tester, store, 3, 8);
        final before = _content(store);
        Future<void> remove() async {
          await _tap(tester, 'schedule-item-2026-03-08-overlap-block');
          await _tap(tester, 'schedule-detail-actions');
          await tester.tap(find.text(store.t['scheduleEditorDelete']!));
          await tester.pumpAndSettle();
        }

        await remove();
        await _tap(tester, 'schedule-delete-cancel');
        expect(_content(store), before);
        await remove();
        await _tap(tester, 'schedule-delete-submit');
        final expected = jsonDecode(jsonEncode(before)) as Map<String, dynamic>;
        (expected['scheduleItems'] as List).removeWhere(
          (dynamic item) => item['id'] == 'overlap-block',
        );
        expect(_content(store), expected);
        await _finish(tester, store);
        await (await SharedPreferences.getInstance()).reload();
        final reopened = await _open();
        expect(_content(reopened), expected);
        reopened.dispose();
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        store.dispose();
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      final fixture = _fixture();
      await prefs.setString('matrixflow-boards', jsonEncode(fixture['boards']));
      await prefs.setString('matrixflow-tasks', jsonEncode(fixture['tasks']));
      await prefs.setString(
        'matrixflow-settings',
        jsonEncode(fixture['settings']),
      );
      await prefs.setString(SaveProtocol.scheduleKey, 'broken');
      final locked = Store(
        credentialStore: _NoCredentials(),
        reminders: InMemoryReminderService(),
      );
      try {
        await locked.init();
        expect(locked.hasStartupRecovery, isTrue);
        final raw = {for (final key in prefs.getKeys()) key: prefs.get(key)};
        await tester.pumpWidget(_app(locked, PlannerScreen(store: locked)));
        await tester.pumpAndSettle();
        expect(find.text(locked.t['scheduleRecovery']!), findsOneWidget);
        expect(_key('schedule-add'), findsNothing);
        expect(_key('schedule-editor'), findsNothing);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        await prefs.reload();
        expect({for (final key in prefs.getKeys()) key: prefs.get(key)}, raw);
        expect(prefs.getString(SaveProtocol.scheduleKey), 'broken');
        debugPrint('WP15_D3_PASS delete_cancel_commit_disk recovery_no_write');
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        locked.dispose();
      }
    },
  );

  tearDownAll(() async {
    if (_isolated) {
      final native = await d3Native();
      expect(native['queryInjected'], isFalse);
      expect(native['windowVisible'], isTrue);
      expect(native['foregroundOwned'], isFalse);
      expect(native['privateDesktop'], isTrue);
      binding.reportData!['finalNative'] = native;
    }
  });
}
