import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/schedule_item.dart';
import 'package:matrixflow_native/screens/planner_screen.dart';
import 'wp15_c2_test_support.dart';

Future<void> _handles(WidgetTester tester) async {
  await c2Tap(tester, c2Key('schedule-item-2026-09-30-block'));
  await c2Tap(tester, c2Key('schedule-detail-actions'));
  await tester.tap(find.text('Show drag handles'));
  await tester.pumpAndSettle();
}

Future<TestGesture> _start(WidgetTester tester, Finder source) async {
  Scrollable.of(tester.element(source), axis: Axis.vertical).position.jumpTo(0);
  await tester.pumpAndSettle();
  await Scrollable.ensureVisible(
    tester.element(source),
    alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
  );
  await tester.pumpAndSettle();
  final gesture = await tester.startGesture(tester.getCenter(source));
  await tester.pump(const Duration(milliseconds: 600));
  return gesture;
}

Future<void> _drop(
  WidgetTester tester,
  TestGesture gesture,
  String date,
  double hour,
) async {
  final box = tester.getRect(c2Key('schedule-drop-$date'));
  expect(
    tester
        .getRect(find.byType(Scaffold).first)
        .contains(box.topLeft + Offset(220, hour * 96 + 3)),
    isTrue,
  );
  await gesture.moveTo(box.topLeft + Offset(220, hour * 96 + 3));
  await tester.pump(const Duration(milliseconds: 50));
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'large-text narrow drag handles stay sized and keyboard accessible through the form',
    (tester) async {
      final store = await c2Store(items: [c1Items().first]);
      final before = c2Library(store);
      await c2Pump(tester, store, size: const Size(320, 750), scale: 3);
      await _handles(tester);
      final handle = c2Key('schedule-handle-2026-09-30-block-resizeStart');
      await tester.ensureVisible(handle);
      await tester.pumpAndSettle();
      expect(tester.getSize(handle).height, greaterThanOrEqualTo(144));
      final text = find.descendant(of: handle, matching: find.byType(Text));
      Focus.of(tester.element(text)).requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(c2Key('schedule-editor'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await c2Tap(tester, c2Key('schedule-editor-cancel'));
      expect(c2Library(store), before);
      await c2Finish(tester, store);
    },
  );
  testWidgets(
    'week drag across day opens confirmation, keeps duration, and cancellation writes nothing',
    (tester) async {
      final store = await c2Store(items: [c1Items().first]);
      final item = store.scheduleItems.single;
      final before = c2Library(store);
      await c2Pump(
        tester,
        store,
        size: const Size(2600, 900),
        view: PlannerView.week,
      );
      var gesture = await _start(
        tester,
        c2Key('schedule-drag-2026-09-30-block'),
      );
      await _drop(tester, gesture, '2026-10-01', 1);
      expect(c2Key('schedule-editor'), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(c2Key('schedule-editor-start-date'))
            .initialValue,
        '2026-10-01',
      );
      expect(
        tester
            .widget<TextFormField>(c2Key('schedule-editor-start-time'))
            .initialValue,
        '01:00',
      );
      expect(c2Library(store), before);
      await c2Tap(tester, c2Key('schedule-editor-cancel'));
      expect(c2Library(store), before);
      gesture = await _start(tester, c2Key('schedule-drag-2026-09-30-block'));
      await _drop(tester, gesture, '2026-10-01', 1);
      await c2Tap(tester, c2Key('schedule-editor-review'));
      expect(find.text('Elapsed duration: 1:30:00.000000'), findsOneWidget);
      await c2Tap(tester, c2Key('schedule-editor-save'));
      final moved = store.scheduleItems.single;
      expect(moved.startAt, item.startAt + 24 * 3600000 + 30 * 60000);
      expect(moved.endAt - moved.startAt, item.endAt - item.startAt);
      expect(moved.timeZoneId, c1Zone);
      await c2Finish(tester, store);
    },
  );

  for (final start in [true, false]) {
    testWidgets(
      'drag ${start ? 'start' : 'end'} edge changes only that endpoint after confirmation',
      (tester) async {
        final store = await c2Store(items: [c1Items().first]);
        final item = store.scheduleItems.single;
        await c2Pump(tester, store);
        await _handles(tester);
        final mode = start ? 'resizeStart' : 'resizeEnd';
        final gesture = await _start(
          tester,
          c2Key('schedule-handle-drag-2026-09-30-block-$mode'),
        );
        await _drop(tester, gesture, '2026-09-30', start ? 0 : 3);
        expect(store.scheduleItems.single.toJson(), item.toJson());
        await c2Tap(tester, c2Key('schedule-editor-review'));
        await c2Tap(tester, c2Key('schedule-editor-save'));
        final resized = store.scheduleItems.single;
        expect(resized.startAt, start ? c1At(30, 0) : item.startAt);
        expect(resized.endAt, start ? item.endAt : c1At(30, 3));
        expect(resized.taskId, item.taskId);
        await c2Finish(tester, store);
      },
    );
  }

  testWidgets(
    'captured drag revision becomes stale after external edit while gesture is held',
    (tester) async {
      final store = await c2Store(items: [c1Items().first]);
      final item = store.scheduleItems.single;
      await c2Pump(tester, store);
      final gesture = await _start(
        tester,
        c2Key('schedule-drag-2026-09-30-block'),
      );
      final changed = ScheduleItem.fromJson({
        ...item.toJson(),
        'endAt': item.endAt + 1,
      });
      store.updateScheduleItem(
        changed,
        expectedRevision: store.scheduleRevision(item.id),
      );
      await tester.pump();
      await _drop(tester, gesture, '2026-09-30', 3);
      expect(find.text(store.t['scheduleEditorStale']!), findsOneWidget);
      expect(
        tester.widget<FilledButton>(c2Key('schedule-editor-review')).onPressed,
        isNull,
      );
      expect(store.scheduleItems.single.toJson(), changed.toJson());
      await c2Tap(tester, c2Key('schedule-editor-cancel'));
      await c2Finish(tester, store);
    },
  );

  testWidgets(
    'blank grid opens explicit creation with start suggestion and no assumed end',
    (tester) async {
      final store = await c2Store(items: []);
      await c2Pump(tester, store);
      final box = tester.getRect(c2Key('schedule-drop-2026-09-30'));
      await tester.tapAt(box.topLeft + const Offset(250, 100));
      await tester.pumpAndSettle();
      await c2Tap(tester, c2Key('schedule-create-event'));
      expect(
        tester
            .widget<TextFormField>(c2Key('schedule-editor-start-time'))
            .initialValue,
        '01:00',
      );
      expect(
        tester
            .widget<TextFormField>(c2Key('schedule-editor-end-time'))
            .initialValue,
        isEmpty,
      );
      expect(store.scheduleItems, isEmpty);
      await c2Tap(tester, c2Key('schedule-editor-cancel'));
      await c2Finish(tester, store);
    },
  );

  testWidgets(
    'form movement crosses week without changing planned date, deadline, reminder or quadrant',
    (tester) async {
      final store = await c2Store(items: [c1Items().first]);
      final before = store.tasks.first.toJson();
      await c2Pump(tester, store);
      await c2Tap(tester, c2Key('schedule-item-2026-09-30-block'));
      await c2Tap(tester, c2Key('schedule-detail-actions'));
      await tester.tap(find.text('Move schedule item'));
      await tester.pumpAndSettle();
      await c2Text(tester, 'schedule-editor-start-date', '2026-10-05');
      await c2Text(tester, 'schedule-editor-start-time', '23:30');
      await c2Tap(tester, c2Key('schedule-editor-review'));
      expect(find.text('End: 2026-10-06 01:00 UTC+08:00'), findsOneWidget);
      await c2Tap(tester, c2Key('schedule-editor-save'));
      expect(store.tasks.first.toJson(), before);
      await c2Finish(tester, store);
    },
  );
}
