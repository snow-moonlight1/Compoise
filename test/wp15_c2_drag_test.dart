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

Future<void> _dropOnDay(
  WidgetTester tester,
  TestGesture gesture,
  String date,
) async {
  final point = tester.getCenter(c2Key('schedule-drop-$date'));
  expect(tester.getRect(find.byType(Scaffold).first).contains(point), isTrue);
  await gesture.moveTo(point);
  await tester.pump(const Duration(milliseconds: 50));
  await gesture.up();
  await tester.pumpAndSettle();
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
      await _dropOnDay(tester, gesture, '2026-10-01');
      expect(c2Key('schedule-editor'), findsOneWidget);
      expect(
        find.descendant(
          of: c2Key('schedule-editor-start-date'),
          matching: find.text('2026-10-01'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: c2Key('schedule-editor-start-time'),
          matching: find.text('00:30'),
        ),
        findsOneWidget,
      );
      expect(c2Library(store), before);
      await c2Tap(tester, c2Key('schedule-editor-cancel'));
      expect(c2Library(store), before);
      gesture = await _start(tester, c2Key('schedule-drag-2026-09-30-block'));
      await _dropOnDay(tester, gesture, '2026-10-01');
      await c2Tap(tester, c2Key('schedule-editor-review'));
      expect(find.text('Elapsed duration: 1:30:00.000000'), findsOneWidget);
      await c2Tap(tester, c2Key('schedule-editor-save'));
      final moved = store.scheduleItems.single;
      expect(moved.startAt, item.startAt + 24 * 3600000);
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
    'blank grid does not create; add opens an editor with no assumed times',
    (tester) async {
      final store = await c2Store(items: []);
      await c2Pump(tester, store);
      final box = tester.getRect(c2Key('schedule-drop-2026-09-30'));
      await tester.tapAt(box.topLeft + const Offset(250, 100));
      await tester.pumpAndSettle();
      expect(c2Key('schedule-create-event'), findsNothing);
      expect(store.scheduleItems, isEmpty);
      await c2Tap(tester, c2Key('schedule-add'));
      expect(
        find.descendant(
          of: c2Key('schedule-editor-start-time'),
          matching: find.text('Choose time'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: c2Key('schedule-editor-end-time'),
          matching: find.text('Choose time'),
        ),
        findsOneWidget,
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

  testWidgets(
    'week rows share the height above the pool, and changing week or view slides',
    (tester) async {
      final store = await c2Store();
      await c2Pump(tester, store, view: PlannerView.week);
      final monday = tester.getTopLeft(c2Key('schedule-day-2026-09-28'));
      final tuesday = tester.getTopLeft(c2Key('schedule-day-2026-09-29'));
      final saturday = tester.getTopLeft(c2Key('schedule-day-2026-10-03'));
      final sunday = tester.getTopLeft(c2Key('schedule-day-2026-10-04'));
      final step = tuesday.dy - monday.dy;
      expect(step, greaterThan(88));
      expect(sunday.dy - saturday.dy, closeTo(step, 1));
      expect((sunday.dy - monday.dy) / 6, closeTo(step, 1));

      final hint = find.text(
        'Tap a date to open that day. Pinch out to return.',
      );
      final gesture = await tester.startGesture(tester.getCenter(hint));
      await gesture.moveBy(const Offset(-80, 0));
      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      expect(
        tester
            .widget<FractionalTranslation>(c2Key('schedule-motion'))
            .translation
            .dx,
        greaterThan(0),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FractionalTranslation>(c2Key('schedule-motion'))
            .translation
            .dx,
        0,
      );

      await tester.tap(c2Key('schedule-mode-day'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      expect(
        tester
            .widget<FractionalTranslation>(c2Key('schedule-motion'))
            .translation
            .dx,
        greaterThan(0),
      );
      await tester.pumpAndSettle();
      await tester.tap(c2Key('schedule-mode-week'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      expect(
        tester
            .widget<FractionalTranslation>(c2Key('schedule-motion'))
            .translation
            .dx,
        lessThan(0),
      );
      await tester.pumpAndSettle();
      await c2Finish(tester, store);
    },
  );

  testWidgets(
    'tapping the pool opens it with colored full names, and a drop lands on that hour',
    (tester) async {
      final store = await c2Store(items: []);
      await c2Pump(tester, store, provide: true);
      expect(find.text('Not Urgent but Important'), findsNothing);
      expect(find.text('Important · Urgent'), findsNothing);
      await tester.tap(find.text('Task pool · 1'));
      await tester.pumpAndSettle();
      expect(find.text('Urgent and Important'), findsOneWidget);
      expect(find.text('Not Urgent but Important'), findsOneWidget);
      expect(find.text('Urgent but Not Important'), findsOneWidget);
      expect(find.text('Neither Urgent nor Important'), findsOneWidget);
      await tester.tap(find.text('Not Urgent but Important'));
      await tester.pumpAndSettle();
      final card = c2Key('schedule-pool-outline');
      expect(
        find.descendant(of: card, matching: find.textContaining('1 h')),
        findsNothing,
      );
      expect(
        find.descendant(
          of: card,
          matching: find.textContaining('Draft outline'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.textContaining('Deadline')),
        findsOneWidget,
      );

      final gesture = await _start(tester, card);
      await tester.pump(const Duration(milliseconds: 800));
      final box = tester.getRect(c2Key('schedule-drop-2026-09-30'));
      final point = box.topLeft + const Offset(220, 4 * 96 + 3);
      await gesture.moveTo(point);
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('4:00 – 5:00'), findsOneWidget);
      expect(find.textContaining('Release to place at 4:00'), findsOneWidget);
      await gesture.up();
      await tester.pumpAndSettle();

      expect(c2Key('schedule-editor'), findsNothing);
      expect(store.scheduleItems, hasLength(1));
      final placed = store.scheduleItems.single;
      expect(placed.kind, ScheduleItemKind.timeBlock);
      expect(placed.taskId, 'outline');
      expect(placed.title, isNull);
      expect(placed.startAt, c1At(30, 4));
      expect(placed.endAt, c1At(30, 5));
      await c2Finish(tester, store);
    },
  );

  testWidgets(
    'schedule time from a pool task pulls that task up instead of opening the form',
    (tester) async {
      final store = await c2Store(items: []);
      await c2Pump(
        tester,
        store,
        provide: true,
        initialTaskId: 'outline',
        startTimeBlock: true,
      );
      expect(c2Key('schedule-editor'), findsNothing);
      expect(find.byType(PlannerScreen), findsOneWidget);
      expect(find.text('Not Urgent but Important'), findsOneWidget);
      expect(c2Key('schedule-pool-outline'), findsOneWidget);

      await c2Tap(tester, c2Key('schedule-pool-outline'));
      await c2Tap(tester, c2Key('edit-schedule-entry'));
      expect(c2Key('schedule-editor'), findsNothing);
      expect(find.byType(PlannerScreen), findsOneWidget);
      expect(find.text('Not Urgent but Important'), findsOneWidget);
      expect(store.scheduleItems, isEmpty);
      await c2Finish(tester, store);
    },
  );
}
