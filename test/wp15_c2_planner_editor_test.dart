import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/l10n.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/schedule_item.dart';
import 'package:matrixflow_native/screens/planner_screen.dart';
import 'package:matrixflow_native/storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'wp15_c2_test_support.dart';

Future<void> _new(WidgetTester tester, {String kind = 'event'}) async {
  await c2Tap(tester, c2Key('schedule-add'));
  await c2Tap(tester, c2Key('schedule-create-$kind'));
}

Future<void> _association(WidgetTester tester, String id) async {
  await c2Tap(tester, c2Key('schedule-editor-choose-association'));
  await c2Tap(tester, c2Key('schedule-editor-association-$id'));
}

Future<void> _event(WidgetTester tester) async {
  await c2Text(tester, 'schedule-editor-title', 'Meeting');
  await _association(tester, 'home');
  await c2Text(tester, 'schedule-editor-start-time', '10:00');
  await c2Text(tester, 'schedule-editor-end-time', '11:00');
}

Future<void> _detail(WidgetTester tester, {String id = 'block'}) =>
    c2Tap(tester, c2Key('schedule-item-2026-09-30-$id'));
Future<void> _action(WidgetTester tester, String label) async {
  await _detail(tester);
  await c2Tap(tester, c2Key('schedule-detail-actions'));
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'typing an unknown zone with task references renders validation without throwing',
    (tester) async {
      final store = await c2Store();
      final before = c2Library(store);
      await c2Pump(tester, store);
      await _detail(tester);
      await c2Tap(tester, c2Key('schedule-detail-edit'));
      await c2Text(tester, 'schedule-editor-zone', 'Bad/Zone');
      expect(tester.takeException(), isNull);
      await c2Tap(tester, c2Key('schedule-editor-review'));
      expect(find.text(store.t['scheduleEditorZoneError']!), findsOneWidget);
      expect(c2Library(store), before);
      await c2Tap(tester, c2Key('schedule-editor-cancel'));
      await c2Finish(tester, store);
    },
  );
  testWidgets(
    'live Planner create form has explicit association and blank times; cancel is zero write',
    (tester) async {
      final store = await c2Store(items: []);
      final before = c2Library(store);
      await c2Pump(tester, store);
      await _new(tester, kind: 'timeBlock');
      expect(
        tester
            .widget<TextFormField>(c2Key('schedule-editor-start-time'))
            .initialValue,
        isEmpty,
      );
      expect(
        tester
            .widget<TextFormField>(c2Key('schedule-editor-end-time'))
            .initialValue,
        isEmpty,
      );
      await _association(tester, 'outline');
      expect(
        find.textContaining('Task dates (reference only)'),
        findsOneWidget,
      );
      await c2Tap(tester, c2Key('schedule-editor-cancel'));
      expect(c2Library(store), before);
      await c2Finish(tester, store);
    },
  );

  testWidgets(
    'create time block and independent event from Planner review; task properties unchanged',
    (tester) async {
      final store = await c2Store(items: []);
      final tasks = jsonEncode(
        store.tasks.map((task) => task.toJson()).toList(),
      );
      await c2Pump(tester, store);
      await _new(tester, kind: 'timeBlock');
      await _association(tester, 'outline');
      await c2Text(tester, 'schedule-editor-start-time', '09:00');
      await c2Text(tester, 'schedule-editor-end-time', '10:00');
      await c2Tap(tester, c2Key('schedule-editor-review'));
      expect(store.scheduleItems, isEmpty);
      await c2Tap(tester, c2Key('schedule-editor-save'));
      expect(store.scheduleItems.single.kind, ScheduleItemKind.timeBlock);
      await _new(tester);
      await _event(tester);
      await c2Tap(tester, c2Key('schedule-editor-review'));
      await c2Tap(tester, c2Key('schedule-editor-save'));
      expect(store.scheduleItems, hasLength(2));
      expect(store.scheduleItems.last.boardId, 'home');
      expect(
        jsonEncode(store.tasks.map((task) => task.toJson()).toList()),
        tasks,
      );
      await c2Finish(tester, store);
    },
  );

  testWidgets(
    'event can explicitly choose parent task; crossing week and midnight is reviewed before save',
    (tester) async {
      final store = await c2Store(items: []);
      await c2Pump(tester, store, view: PlannerView.week);
      await _new(tester);
      await c2Text(tester, 'schedule-editor-title', 'Linked');
      await c2Tap(tester, c2Key('schedule-editor-associate-task'));
      await _association(tester, 'outline');
      await c2Text(tester, 'schedule-editor-start-date', '2026-09-27');
      await c2Text(tester, 'schedule-editor-start-time', '23:00');
      await c2Text(tester, 'schedule-editor-end-date', '2026-10-05');
      await c2Text(tester, 'schedule-editor-end-time', '00:00');
      await c2Tap(tester, c2Key('schedule-editor-review'));
      expect(find.text('End: 2026-10-05 00:00 UTC+08:00'), findsOneWidget);
      await c2Tap(tester, c2Key('schedule-editor-save'));
      expect(store.scheduleItems.single.taskId, 'outline');
      expect(store.scheduleItems.single.boardId, isNull);
      expect(
        c2Key('schedule-item-2026-10-04-${store.scheduleItems.single.id}'),
        findsOneWidget,
      );
      await c2Finish(tester, store);
    },
  );

  testWidgets(
    'overlap requires explicit confirmation; returning or cancelling never writes',
    (tester) async {
      final store = await c2Store();
      final before = c2Library(store);
      await c2Pump(tester, store);
      await _new(tester);
      await _event(tester);
      await c2Text(tester, 'schedule-editor-start-time', '01:00');
      await c2Text(tester, 'schedule-editor-end-time', '02:00');
      await c2Tap(tester, c2Key('schedule-editor-review'));
      expect(find.text('Overlapping records'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(c2Key('schedule-editor-save')).onPressed,
        isNull,
      );
      await c2Tap(tester, c2Key('schedule-editor-modify'));
      await c2Tap(tester, c2Key('schedule-editor-cancel'));
      expect(c2Library(store), before);
      await _new(tester);
      await _event(tester);
      await c2Text(tester, 'schedule-editor-start-time', '01:00');
      await c2Text(tester, 'schedule-editor-end-time', '02:00');
      await c2Tap(tester, c2Key('schedule-editor-review'));
      await c2Tap(tester, c2Key('schedule-editor-allow-overlap'));
      await c2Tap(tester, c2Key('schedule-editor-save'));
      expect(store.scheduleItems, hasLength(5));
      await c2Finish(tester, store);
    },
  );

  testWidgets(
    'unchanged edit retains revision and original absolute milliseconds',
    (tester) async {
      final item = c1Event(
        'precise',
        c1At(30, 0) + 12345,
        c1At(30, 1) + 23456,
        zone: 'UTC',
      );
      final store = await c2Store(items: [item]);
      final before = c2Library(store);
      await c2Pump(tester, store);
      await _detail(tester, id: 'precise');
      await c2Tap(tester, c2Key('schedule-detail-edit'));
      expect(
        tester
            .widget<TextFormField>(c2Key('schedule-editor-zone'))
            .initialValue,
        'UTC',
      );
      await c2Tap(tester, c2Key('schedule-editor-review'));
      await c2Tap(tester, c2Key('schedule-editor-save'));
      expect(c2Library(store), before);
      await c2Finish(tester, store);
    },
  );

  testWidgets(
    'DST gap message rejects; each repeated endpoint needs explicit UTC offset',
    (tester) async {
      final store = await c2Store(items: []);
      await c2Pump(tester, store);
      await _new(tester);
      await _event(tester);
      await c2Text(tester, 'schedule-editor-zone', 'America/New_York');
      await c2Text(tester, 'schedule-editor-start-date', '2026-03-08');
      await c2Text(tester, 'schedule-editor-start-time', '02:30');
      await c2Text(tester, 'schedule-editor-end-date', '2026-03-08');
      await c2Text(tester, 'schedule-editor-end-time', '04:00');
      await c2Tap(tester, c2Key('schedule-editor-review'));
      expect(find.text(store.t['scheduleEditorGap']!), findsWidgets);
      expect(store.scheduleItems, isEmpty);
      await c2Text(tester, 'schedule-editor-start-date', '2026-11-01');
      await c2Text(tester, 'schedule-editor-start-time', '01:15');
      await c2Text(tester, 'schedule-editor-end-date', '2026-11-01');
      await c2Text(tester, 'schedule-editor-end-time', '01:45');
      await c2Tap(tester, c2Key('schedule-editor-review'));
      expect(c2Key('schedule-editor-save'), findsNothing);
      await c2Tap(tester, c2Key('schedule-editor-start-offset--240'));
      await c2Tap(tester, c2Key('schedule-editor-end-offset--300'));
      await c2Tap(tester, c2Key('schedule-editor-review'));
      expect(find.text('Elapsed duration: 1:30:00.000000'), findsOneWidget);
      await c2Tap(tester, c2Key('schedule-editor-save'));
      expect(
        store.scheduleItems.single.endAt - store.scheduleItems.single.startAt,
        5400000,
      );
      await c2Finish(tester, store);
    },
  );

  for (final delete in [false, true]) {
    testWidgets(
      'external ${delete ? 'deletion' : 'edit'} displays stale form and disables writes',
      (tester) async {
        final store = await c2Store();
        final item = store.scheduleItems.first;
        await c2Pump(tester, store);
        await _detail(tester);
        await c2Tap(tester, c2Key('schedule-detail-edit'));
        if (delete) {
          store.deleteScheduleItem(
            item.id,
            expectedRevision: store.scheduleRevision(item.id),
          );
        } else {
          store.updateScheduleItem(
            ScheduleItem.fromJson({
              ...item.toJson(),
              'startAt': item.startAt + 1,
            }),
            expectedRevision: store.scheduleRevision(item.id),
          );
        }
        await tester.pumpAndSettle();
        expect(find.text(store.t['scheduleEditorStale']!), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(c2Key('schedule-editor-review'))
              .onPressed,
          isNull,
        );
        await c2Tap(tester, c2Key('schedule-editor-cancel'));
        await c2Finish(tester, store);
      },
    );
  }

  testWidgets(
    'delete requires confirmation; cancel is zero write and confirmed delete preserves parent/overlaps',
    (tester) async {
      final store = await c2Store();
      final before = c2Library(store);
      final tasks = jsonEncode(
        store.tasks.map((task) => task.toJson()).toList(),
      );
      await c2Pump(tester, store);
      await _action(tester, 'Delete schedule item');
      expect(c2Key('schedule-delete-confirm'), findsOneWidget);
      await c2Tap(tester, c2Key('schedule-delete-cancel'));
      expect(c2Library(store), before);
      await _action(tester, 'Delete schedule item');
      await c2Tap(tester, c2Key('schedule-delete-submit'));
      expect(store.scheduleItems.map((item) => item.id), [
        'linked',
        'independent',
        'done',
      ]);
      expect(
        jsonEncode(store.tasks.map((task) => task.toJson()).toList()),
        tasks,
      );
      await c2Finish(tester, store);
    },
  );

  testWidgets(
    'failed save stays open without success, retry lands once without another revision',
    (tester) async {
      var fail = false;
      final store = await c2Store(
        items: [],
        writer: (key, value) async {
          if (fail && key == SaveProtocol.pointerKey) return false;
          return (await SharedPreferences.getInstance()).setString(key, value);
        },
      );
      await c2Pump(tester, store);
      await _new(tester);
      await _event(tester);
      await c2Tap(tester, c2Key('schedule-editor-review'));
      fail = true;
      await c2Tap(tester, c2Key('schedule-editor-save'));
      expect(find.text(store.t['scheduleEditorUnsaved']!), findsOneWidget);
      expect(find.text('Schedule saved'), findsNothing);
      final revision = store.scheduleRevision(store.scheduleItems.single.id);
      fail = false;
      await c2Tap(tester, c2Key('schedule-editor-retry'));
      expect(c2Key('schedule-editor'), findsNothing);
      expect(store.scheduleRevision(store.scheduleItems.single.id), revision);
      expect(find.text('Schedule saved'), findsOneWidget);
      await c2Finish(tester, store);
    },
  );

  testWidgets(
    'waiting save disables repeat submit and cancellation until persistence settles',
    (tester) async {
      final gate = Completer<void>();
      var hold = false;
      final store = await c2Store(
        items: [],
        writer: (key, value) async {
          if (hold && key == SaveProtocol.pointerKey) await gate.future;
          return (await SharedPreferences.getInstance()).setString(key, value);
        },
      );
      await c2Pump(tester, store);
      await _new(tester);
      await _event(tester);
      await c2Tap(tester, c2Key('schedule-editor-review'));
      hold = true;
      await c2Tap(tester, c2Key('schedule-editor-save'));
      expect(
        tester.widget<TextButton>(c2Key('schedule-editor-cancel')).onPressed,
        isNull,
      );
      expect(c2Key('schedule-editor-save'), findsNothing);
      expect(store.scheduleItems, hasLength(1));
      gate.complete();
      await tester.pumpAndSettle();
      await c2Finish(tester, store);
    },
  );

  testWidgets(
    '320px / 3x text editor, association picker, review and keyboard save stay accessible',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final store = await c2Store(items: []);
      await c2Pump(tester, store, size: const Size(320, 750), scale: 3);
      await _new(tester);
      await _event(tester);
      expect(tester.takeException(), isNull);
      await c2Tap(tester, c2Key('schedule-editor-review'));
      final save = c2Key('schedule-editor-save');
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      final text = find.descendant(of: save, matching: find.byType(Text));
      Focus.of(tester.element(text)).requestFocus();
      await tester.pumpAndSettle();
      expect(
        tester
            .getSemantics(save)
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(store.scheduleItems, hasLength(1));
      expect(tester.takeException(), isNull);
      await c2Finish(tester, store);
      semantics.dispose();
    },
  );

  testWidgets('recovery Planner exposes no create or edit controls', (
    tester,
  ) async {
    final store = await c2Store(recovery: true);
    await c2Pump(tester, store);
    expect(find.text(store.t['scheduleRecovery']!), findsOneWidget);
    expect(c2Key('schedule-add'), findsNothing);
    await c2Finish(tester, store);
  });

  test(
    'all editor strings are translated without touching other dictionary regions',
    () {
      final keys = dictOf(
        Language.en,
      ).keys.where((key) => key.startsWith('scheduleEditor'));
      for (final language in Language.values) {
        for (final key in keys) {
          expect(dictOf(language)[key], isNotEmpty);
        }
      }
    },
  );
}
