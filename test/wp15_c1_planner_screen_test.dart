import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/l10n.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/schedule_time.dart';
import 'package:matrixflow_native/screens/planner_screen.dart';
import 'package:matrixflow_native/storage.dart';
import 'package:matrixflow_native/widgets/schedule_layout.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/wp15_c1_fixtures.dart';

Finder _key(String key) => find.byKey(ValueKey(key));
Finder _item(String id, {String date = '2026-09-30'}) =>
    _key('schedule-item-$date-$id');

Widget _app(
  Widget page, {
  double scale = 1,
  Locale locale = const Locale('en'),
}) => MaterialApp(
  theme: ThemeData(useMaterial3: true, platform: TargetPlatform.windows),
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  supportedLocales: const [Locale('en'), Locale('zh'), Locale('ja')],
  locale: locale,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: page,
);

Future<void> _pump(
  WidgetTester tester, {
  StoreSnapshot? snapshot,
  Store? store,
  String zone = c1Zone,
  ScheduleCivilDate? date,
  PlannerView view = PlannerView.day,
  Size size = const Size(1200, 850),
  double scale = 1,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    _app(
      PlannerScreen(
        snapshot: store == null ? snapshot ?? c1Snapshot() : null,
        store: store,
        displayTimeZoneId: zone,
        initialDate: date ?? ScheduleCivilDate(2026, 9, 30),
        initialView: view,
        now: () => DateTime.utc(2026, 9, 29, 20),
      ),
      scale: scale,
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  final visible = tester
      .getRect(target)
      .intersect(tester.getRect(find.byType(Scaffold).first));
  expect(
    visible.isEmpty,
    isFalse,
    reason: 'Target must have a visible touch area',
  );
  await tester.tapAt(visible.center);
  await tester.pumpAndSettle();
}

String _snapshotBytes(StoreSnapshot snapshot) => jsonEncode({
  'boards': snapshot.boards.map((board) => board.toJson()).toList(),
  'tasks': snapshot.tasks.map((task) => task.toJson()).toList(),
  'schedule': snapshot.scheduleItems.map((item) => item.toJson()).toList(),
  'active': snapshot.activeBoardId,
  'settings': snapshot.settings.toJson(),
  'revisions': snapshot.scheduleRevisions,
});

Future<Store> _store() async {
  SharedPreferences.setMockInitialValues({
    'matrixflow-boards': jsonEncode(
      c1Boards().map((board) => board.toJson()).toList(),
    ),
    'matrixflow-tasks': jsonEncode(
      c1Tasks().map((task) => task.toJson()).toList(),
    ),
    'matrixflow-schedule': jsonEncode(
      c1Items().map((item) => item.toJson()).toList(),
    ),
    'matrixflow-settings': jsonEncode(
      AppSettings(language: Language.en).toJson(),
    ),
  });
  final store = Store();
  await store.init();
  await store.flush();
  return store;
}

Future<void> _finish(WidgetTester tester, Store store) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.runAsync(store.flush);
  store.dispose();
  await tester.pump();
}

void main() {
  testWidgets(
    'mixed records label kind, current task/board and completed parent',
    (tester) async {
      await _pump(tester);
      for (final id in ['block', 'linked', 'independent', 'done']) {
        expect(_item(id), findsOneWidget);
      }
      expect(
        find.descendant(
          of: _item('block'),
          matching: find.textContaining('Time block · Draft outline'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _item('linked'),
          matching: find.textContaining('Task: Draft outline'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _item('done'),
          matching: find.textContaining('Completed'),
        ),
        findsOneWidget,
      );
      final block = tester.widget<OutlinedButton>(_item('block'));
      final done = tester.widget<OutlinedButton>(_item('done'));
      expect(
        block.style!.backgroundColor!.resolve({}),
        isNot(done.style!.backgroundColor!.resolve({})),
      );
      expect(find.byType(Checkbox), findsNothing);
      expect(find.byType(Draggable<Object>), findsNothing);
      expect(find.byType(TextField), findsNothing);
    },
  );

  testWidgets(
    'board filter includes task-derived and independent board associations',
    (tester) async {
      final snapshot = c1Snapshot();
      final before = _snapshotBytes(snapshot);
      await _pump(tester, snapshot: snapshot);
      await _tap(tester, _key('schedule-filter'));
      await _tap(tester, _key('schedule-board-work'));
      expect(_item('block'), findsOneWidget);
      expect(_item('linked'), findsOneWidget);
      expect(_item('independent'), findsNothing);
      expect(_item('done'), findsNothing);
      await _tap(tester, _key('schedule-filter'));
      await _tap(tester, _key('schedule-board-home'));
      expect(_item('block'), findsNothing);
      expect(_item('independent'), findsOneWidget);
      await _tap(tester, _key('schedule-filter'));
      await _tap(tester, _key('schedule-board-'));
      expect(_item('block'), findsOneWidget);
      expect(_snapshotBytes(snapshot), before);
    },
  );

  testWidgets(
    'day/week navigation preserves selected date and today uses display zone',
    (tester) async {
      await _pump(tester);
      await _tap(tester, _key('schedule-next'));
      expect(_key('schedule-day-2026-10-01'), findsOneWidget);
      await _tap(tester, _key('schedule-mode-week'));
      expect(find.text('2026-09-28 – 2026-10-04'), findsOneWidget);
      for (final date in [
        '2026-09-28',
        '2026-09-29',
        '2026-09-30',
        '2026-10-01',
        '2026-10-02',
        '2026-10-03',
        '2026-10-04',
      ]) {
        expect(_key('schedule-day-$date'), findsOneWidget);
      }
      await _tap(tester, _key('schedule-next'));
      expect(find.text('2026-10-05 – 2026-10-11'), findsOneWidget);
      await _tap(tester, _key('schedule-previous'));
      await _tap(tester, _key('schedule-mode-day'));
      expect(_key('schedule-day-2026-10-01'), findsOneWidget);
      await _tap(tester, _key('schedule-today'));
      expect(_key('schedule-day-2026-09-30'), findsOneWidget);
      await _tap(tester, _key('schedule-previous'));
      expect(_key('schedule-day-2026-09-29'), findsOneWidget);
    },
  );

  testWidgets('calendar navigation selects a date and can be cancelled', (
    tester,
  ) async {
    await _pump(tester);
    await _tap(tester, _key('schedule-date'));
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await tester.tap(find.text('29').last);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(_key('schedule-day-2026-09-29'), findsOneWidget);
    await _tap(tester, _key('schedule-date'));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(_key('schedule-day-2026-09-29'), findsOneWidget);
  });

  testWidgets(
    'cross-day midnight slices expose the full immutable record in detail',
    (tester) async {
      final snapshot = c1Snapshot(
        items: [
          c1Event('ends', c1At(29, 23), c1At(30, 0)),
          c1Event('starts', c1At(30, 0), c1At(30, 1)),
          c1Event('cross', c1At(29, 23), c1At(30, 1)),
        ],
      );
      final before = _snapshotBytes(snapshot);
      await _pump(tester, snapshot: snapshot);
      expect(_item('ends'), findsNothing);
      expect(_item('starts'), findsOneWidget);
      expect(_item('cross'), findsOneWidget);
      expect(
        find.descendant(
          of: _item('cross'),
          matching: find.textContaining('Continues from previous day'),
        ),
        findsOneWidget,
      );
      await _tap(tester, _item('cross'));
      expect(find.text('Start: 2026-09-29 23:00 UTC+08:00'), findsNWidgets(2));
      expect(find.text('Elapsed duration: 2:00:00.000000'), findsOneWidget);
      await _tap(tester, _key('schedule-detail-close'));
      await _tap(tester, _key('schedule-previous'));
      expect(_item('starts', date: '2026-09-29'), findsNothing);
      await _tap(tester, _item('cross', date: '2026-09-29'));
      expect(find.text('Start: 2026-09-29 23:00 UTC+08:00'), findsNWidgets(2));
      expect(_snapshotBytes(snapshot), before);
    },
  );

  testWidgets(
    'week clips both edges and shows continuing id in each intersecting day',
    (tester) async {
      await _pump(
        tester,
        view: PlannerView.week,
        snapshot: c1Snapshot(
          items: [
            c1Event(
              'wide',
              c1At(27, 23),
              resolveWallTime(
                ScheduleWallTime(
                  ScheduleCivilDate(2026, 10, 5),
                  hour: 1,
                  minute: 0,
                ),
                c1Zone,
              ),
            ),
            c1Event('previous', c1At(27, 22), c1At(28, 0)),
          ],
        ),
      );
      expect(_item('previous', date: '2026-09-28'), findsNothing);
      final first = _item('wide', date: '2026-09-28');
      final last = _item('wide', date: '2026-10-04');
      expect(first, findsOneWidget);
      expect(last, findsOneWidget);
      await _tap(tester, last);
      expect(find.text('Event wide'), findsOneWidget);
      expect(find.text('Start: 2026-09-27 23:00 UTC+08:00'), findsNWidgets(2));
    },
  );

  for (final (month, day, hours) in [(3, 8, 23), (11, 1, 25)]) {
    testWidgets('$hours-hour day shows actual elapsed axis and offset labels', (
      tester,
    ) async {
      const zone = 'America/New_York';
      final date = ScheduleCivilDate(2026, month, day);
      final window = dayWindow(date, zone);
      await _pump(
        tester,
        date: date,
        zone: zone,
        snapshot: c1Snapshot(
          items: [c1Event('dst', window.startAt, window.endAt, zone: zone)],
        ),
      );
      expect(find.textContaining('$hours.0 hours'), findsOneWidget);
      if (hours == 23) {
        expect(find.text('02:00 UTC-05:00'), findsNothing);
        expect(find.text('03:00 UTC-04:00'), findsOneWidget);
      } else {
        expect(find.text('01:00 UTC-04:00'), findsOneWidget);
        expect(find.text('01:00 UTC-05:00'), findsOneWidget);
      }
      await _tap(tester, _item('dst', date: scheduleDateLabel(date)));
      expect(
        find.text('Elapsed duration: $hours:00:00.000000'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'overlap cards have separate bounds, tap actions and complete semantics',
    (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester);
      final bounds = [
        for (final id in ['block', 'linked', 'independent'])
          tester.getRect(_item(id)),
      ];
      for (var i = 0; i < bounds.length; i++) {
        for (var j = i + 1; j < bounds.length; j++) {
          expect(bounds[i].overlaps(bounds[j]), isFalse);
        }
      }
      for (final id in ['block', 'linked', 'independent', 'done']) {
        await tester.ensureVisible(_item(id));
        await tester.pumpAndSettle();
        final node = tester.getSemantics(
          _key('schedule-semantics-2026-09-30-$id'),
        );
        expect(node.getSemanticsData().hasFlag(SemanticsFlag.isButton), isTrue);
        expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
        expect(node.label, contains(id == 'block' ? 'Time block' : 'Event'));
        expect(node.label, contains('board'));
        if (id == 'linked') expect(node.label, contains('Task: Draft outline'));
        if (id == 'done') expect(node.label, contains('Completed'));
        await _tap(tester, _item(id));
        expect(_key('schedule-detail'), findsOneWidget);
        await _tap(tester, _key('schedule-detail-close'));
      }
      handle.dispose();
    },
  );

  for (final mode in PlannerView.values) {
    testWidgets(
      '320px width with 3x text in ${mode.name} remains scrollable and readable',
      (tester) async {
        final snapshot = c1Snapshot(language: Language.zh);
        snapshot.tasks.first.title = '很长的父任务标题，用于检查大字号时仍能访问完整详情。' * 3;
        snapshot.boards.first.name = '很长的所属看板名称，用于窄屏筛选测试';
        await _pump(
          tester,
          snapshot: snapshot,
          view: mode,
          size: const Size(320, 700),
          scale: 3,
        );
        expect(tester.takeException(), isNull);
        await _tap(tester, _key('schedule-filter'));
        await _tap(tester, _key('schedule-board-work'));
        expect(tester.takeException(), isNull);
        await _tap(tester, _item('linked'));
        expect(_key('schedule-detail'), findsOneWidget);
        expect(find.textContaining(snapshot.tasks.first.title), findsWidgets);
        expect(tester.takeException(), isNull);
        await _tap(tester, _key('schedule-detail-close'));
        await _tap(tester, _key('schedule-next'));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Tab reaches every overlap; Enter and Space open details on narrow week',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await _pump(tester, size: const Size(360, 800), view: PlannerView.week);
      FocusManager.instance.primaryFocus?.unfocus();
      final visited = <String>{};
      for (var i = 0; i < 45 && visited.length < 4; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        final element = FocusManager.instance.primaryFocus?.context;
        final button = element?.findAncestorWidgetOfExactType<OutlinedButton>();
        final key = button?.key;
        if (key is! ValueKey<String> ||
            !key.value.startsWith('schedule-item-2026-09-30-')) {
          continue;
        }
        final id = key.value.substring('schedule-item-2026-09-30-'.length);
        visited.add(id);
        expect(
          tester
              .getSemantics(_key('schedule-semantics-2026-09-30-$id'))
              .getSemanticsData()
              .hasFlag(SemanticsFlag.isFocused),
          isTrue,
        );
        expect(
          tester
              .getRect(_item(id))
              .overlaps(Offset.zero & const Size(360, 800)),
          isTrue,
        );
        await tester.sendKeyEvent(
          visited.length.isOdd
              ? LogicalKeyboardKey.enter
              : LogicalKeyboardKey.space,
        );
        await tester.pumpAndSettle();
        expect(_key('schedule-detail'), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(_key('schedule-detail'), findsNothing);
      }
      expect(visited, {'block', 'linked', 'independent', 'done'});
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );

  testWidgets(
    'empty schedule retains navigation, board scope and real day grid',
    (tester) async {
      await _pump(tester, snapshot: c1Snapshot(items: []));
      expect(find.text('No schedule items in this range'), findsOneWidget);
      expect(find.text('00:00 UTC+08:00'), findsOneWidget);
      await _tap(tester, _key('schedule-next'));
      expect(_key('schedule-day-2026-10-01'), findsOneWidget);
      await _tap(tester, _key('schedule-filter'));
      expect(_key('schedule-board-work'), findsOneWidget);
    },
  );

  testWidgets(
    'snapshot replacement and display-zone changes reproject current items',
    (tester) async {
      final item = c1Event('zone', c1At(30, 0), c1At(30, 1));
      final snapshot = c1Snapshot(items: [item]);
      final date = ScheduleCivilDate(2026, 9, 30);
      await tester.pumpWidget(
        _app(
          PlannerScreen(
            snapshot: snapshot,
            initialDate: date,
            displayTimeZoneId: c1Zone,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(_item('zone'), findsOneWidget);
      await tester.pumpWidget(
        _app(
          PlannerScreen(
            snapshot: snapshot,
            initialDate: date,
            displayTimeZoneId: 'UTC',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(_item('zone'), findsNothing);
      await _tap(tester, _key('schedule-previous'));
      expect(_item('zone', date: '2026-09-29'), findsOneWidget);
      await tester.pumpWidget(
        _app(
          PlannerScreen(
            snapshot: c1Snapshot(items: []),
            initialDate: date,
            displayTimeZoneId: 'UTC',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(_item('zone', date: '2026-09-29'), findsNothing);
      expect(item.timeZoneId, c1Zone);
    },
  );

  testWidgets(
    'live Store refreshes associations, detail and deletions without view writes',
    (tester) async {
      final store = await _store();
      final before = _snapshotBytes(store.captureSnapshot());
      await _pump(tester, store: store);
      await _tap(tester, _item('block'));
      expect(_snapshotBytes(store.captureSnapshot()), before);
      store.updateTask(
        Task.fromJson(store.tasks.first.toJson())
          ..title = 'New title'
          ..boardId = 'home'
          ..completed = true,
      );
      await tester.pumpAndSettle();
      expect(find.text('New title'), findsOneWidget);
      expect(
        find.textContaining('Home board · Task: New title'),
        findsOneWidget,
      );
      store.deleteScheduleItem(
        'block',
        expectedRevision: store.scheduleRevision('block'),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('This schedule item is no longer available.'),
        findsNWidgets(2),
      );
      await _tap(tester, _key('schedule-detail-close'));
      expect(_item('block'), findsNothing);
      await _tap(tester, _key('schedule-filter'));
      await _tap(tester, _key('schedule-board-home'));
      expect(_item('linked'), findsOneWidget);
      expect(
        store.activeBoardId,
        before.contains('"active":"work"') ? 'work' : 'home',
      );
      await _finish(tester, store);
    },
  );

  testWidgets(
    'provider Store refreshes new records and deleted board filters',
    (tester) async {
      final store = await _store();
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: store,
          child: _app(
            PlannerScreen(
              displayTimeZoneId: c1Zone,
              initialDate: ScheduleCivilDate(2026, 9, 30),
              initialBoardId: 'home',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(_item('block'), findsNothing);
      store.addScheduleItem(c1Event('added', c1At(30, 5), c1At(30, 6)));
      await tester.pumpAndSettle();
      expect(_item('added'), findsOneWidget);
      store.deleteBoard('home');
      await tester.pumpAndSettle();
      expect(_item('added'), findsNothing);
      expect(_item('block'), findsOneWidget);
      await _finish(tester, store);
    },
  );

  testWidgets('loading and unsaved states never claim a saved empty schedule', (
    tester,
  ) async {
    final loading = Store();
    await _pump(tester, store: loading);
    expect(_key('schedule-day-2026-09-30'), findsNothing);
    expect(find.text(loading.t['scheduleLoading']!), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    loading.dispose();
    final store = await _store();
    store.persistenceError = 'test failure';
    await _pump(tester, store: store);
    expect(find.text(store.t['scheduleUnsaved']!), findsOneWidget);
    expect(_item('block'), findsOneWidget);
    await _finish(tester, store);
  });

  testWidgets(
    'corrupt saved schedule displays recovery rather than a false empty grid',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'matrixflow-boards': jsonEncode(
          c1Boards().map((board) => board.toJson()).toList(),
        ),
        'matrixflow-tasks': jsonEncode(
          c1Tasks().map((task) => task.toJson()).toList(),
        ),
        'matrixflow-schedule': 'broken schedule',
      });
      final store = Store();
      await store.init();
      expect(store.hasStartupRecovery, isTrue);
      await _pump(tester, store: store);
      expect(find.text(store.t['scheduleRecovery']!), findsOneWidget);
      expect(_key('schedule-day-2026-09-30'), findsNothing);
      expect(find.text(store.t['scheduleEmpty']!), findsNothing);
      await _finish(tester, store);
    },
  );

  test('schedule strings exist in all supported dictionaries', () {
    final keys = dictOf(
      Language.en,
    ).keys.where((key) => key.startsWith('schedule'));
    for (final language in Language.values) {
      for (final key in keys) {
        expect(dictOf(language)[key], isNotEmpty, reason: '$language $key');
      }
    }
  });
}
