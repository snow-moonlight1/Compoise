import 'dart:convert';

import 'package:flutter/material.dart';
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

Future<void> _menu(WidgetTester tester) =>
    _tap(tester, _key('schedule-menu'));

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
    'board filter includes task-derived and independent board associations',
    (tester) async {
      final snapshot = c1Snapshot();
      final before = _snapshotBytes(snapshot);
      await _pump(tester, snapshot: snapshot);
      await _menu(tester);
      await _tap(tester, _key('schedule-filter'));
      await _tap(tester, _key('schedule-board-work'));
      expect(_item('block'), findsOneWidget);
      expect(_item('linked'), findsOneWidget);
      expect(_item('independent'), findsNothing);
      expect(_item('done'), findsNothing);
      await _menu(tester);
      await _tap(tester, _key('schedule-filter'));
      await _tap(tester, _key('schedule-board-home'));
      expect(_item('block'), findsNothing);
      expect(_item('independent'), findsOneWidget);
      await _menu(tester);
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
      expect(find.text('Sep 28–Oct 4'), findsOneWidget);
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
      expect(find.text('Oct 5–11'), findsOneWidget);
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
      if (hours == 23) {
        expect(find.text('2:00'), findsNothing);
        expect(find.text('3:00'), findsOneWidget);
      } else {
        expect(find.text('1:00'), findsNWidgets(2));
      }
      await _tap(tester, _item('dst', date: scheduleDateLabel(date)));
      // The detail panel states the real elapsed time, never a raw duration.
      expect(find.textContaining('$hours h'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }



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
        await _menu(tester);
        await _tap(tester, _key('schedule-filter'));
        await _tap(tester, _key('schedule-board-work'));
        expect(tester.takeException(), isNull);
        await _tap(tester, _item('linked'));
        expect(_key('schedule-detail'), findsOneWidget);
        expect(find.textContaining(snapshot.tasks.first.title), findsWidgets);
        expect(tester.takeException(), isNull);
        expect(tester.takeException(), isNull);
      },
    );
  }



  testWidgets(
    'empty schedule retains navigation, board scope and real day grid',
    (tester) async {
      await _pump(tester, snapshot: c1Snapshot(items: []));
      expect(find.text('No schedule items in this range'), findsNothing);
      expect(find.text('0:00'), findsOneWidget);
      await _tap(tester, _key('schedule-next'));
      expect(_key('schedule-day-2026-10-01'), findsOneWidget);
      await _menu(tester);
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
