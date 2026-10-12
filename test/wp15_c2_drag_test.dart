import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:compoise/schedule_item.dart';
import 'wp15_c2_test_support.dart';

/// Gestures on a schedule block: tap selects, handles resize, long press
/// moves, and nothing asks for a confirmation form.
void main() {
  const block = 'schedule-item-2026-09-30-block';
  const minute = Duration.millisecondsPerMinute;

  Future<void> select(WidgetTester tester) async {
    await c2Tap(tester, c2Key(block));
    expect(c2Key('schedule-detail'), findsOneWidget);
  }

  testWidgets(
    'tap selects: a small bar shows time and length, no developer text',
    (tester) async {
      final store = await c2Store(items: [c1Items().first]);
      await c2Pump(tester, store);
      await select(tester);
      expect(find.textContaining('1 h 30 min'), findsOneWidget);
      expect(find.textContaining('UTC'), findsNothing);
      expect(find.textContaining('Asia/Shanghai'), findsNothing);
      expect(find.textContaining('000'), findsNothing);
      expect(
        find.byKey(const ValueKey('schedule-detail-edit')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('schedule-detail-delete')),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey('schedule-handle-2026-09-30-block-resizeStart'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey('schedule-handle-2026-09-30-block-resizeEnd'),
        ),
        findsOneWidget,
      );
      // Both knobs sit on the horizontal middle of the block.
      final box = tester.getRect(c2Key(block));
      for (final mode in ['resizeStart', 'resizeEnd']) {
        final h = tester.getRect(
          c2Key('schedule-handle-2026-09-30-block-$mode'),
        );
        expect(h.center.dx, closeTo(box.center.dx, 1));
        expect(h.height, greaterThanOrEqualTo(48));
      }
      expect(find.byType(SnackBar), findsNothing);
      // Tapping empty grid space clears the selection.
      await tester.tapAt(const Offset(900, 600));
      await tester.pumpAndSettle();
      expect(c2Key('schedule-detail'), findsNothing);
      await c2Finish(tester, store);
    },
  );

  testWidgets('second tap opens the plain edit form (no review step)', (
    tester,
  ) async {
    final store = await c2Store(items: [c1Items().first]);
    await c2Pump(tester, store);
    await select(tester);
    await c2Tap(tester, c2Key(block));
    expect(c2Key('schedule-editor'), findsOneWidget);
    expect(find.text('Edit schedule item'), findsOneWidget);
    expect(c2Key('schedule-editor-review'), findsNothing);
    await c2Tap(tester, c2Key('schedule-editor-cancel'));
    await c2Finish(tester, store);
  });

  for (final start in [true, false]) {
    testWidgets(
      'dragging the ${start ? 'top' : 'bottom'} handle moves only that edge, '
      'in 15 minute steps, with no form and no toast',
      (tester) async {
        final store = await c2Store(items: [c1Items().first]);
        final item = store.scheduleItems.single;
        await c2Pump(tester, store);
        await select(tester);
        final handle = c2Key(
          'schedule-handle-2026-09-30-block-${start ? 'resizeStart' : 'resizeEnd'}',
        );
        final target = tester.getCenter(handle);
        final g = await tester.startGesture(
          Offset(tester.getRect(handle).right - 22, target.dy),
        );
        final dy = start ? -1.0 : 1.0;
        // The first move only crosses the touch slop and starts the drag.
        await g.moveBy(Offset(0, dy * 24));
        await tester.pump();
        await g.moveBy(Offset(0, dy * 66));
        await tester.pump();
        expect(
          find.byKey(const ValueKey('schedule-drag-time')),
          findsOneWidget,
        );
        await g.up();
        await tester.pumpAndSettle();
        final changed = store.scheduleItems.single;
        expect(c2Key('schedule-editor'), findsNothing);
        if (start) {
          expect(changed.endAt, item.endAt);
          final delta = (item.startAt - changed.startAt) ~/ minute;
          expect(delta, greaterThanOrEqualTo(30));
          expect(delta % 15, 0);
        } else {
          expect(changed.startAt, item.startAt);
          final delta = (changed.endAt - item.endAt) ~/ minute;
          expect(delta, greaterThanOrEqualTo(30));
          expect(delta % 15, 0);
        }
        expect(changed.taskId, item.taskId);
        expect(find.byType(SnackBar), findsNothing);
        await c2Finish(tester, store);
      },
    );
  }

  testWidgets('long press then drag moves the whole block by whole quarters', (
    tester,
  ) async {
    final store = await c2Store(items: [c1Items().first]);
    final item = store.scheduleItems.single;
    await c2Pump(tester, store);
    await tester.ensureVisible(c2Key(block));
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(tester.getCenter(c2Key(block)));
    await tester.pump(const Duration(milliseconds: 700));
    await gesture.moveBy(const Offset(0, 96));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveBy(const Offset(0, 96));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.up();
    await tester.pumpAndSettle();
    final moved = store.scheduleItems.single;
    expect(moved.endAt - moved.startAt, item.endAt - item.startAt);
    expect(moved.startAt - item.startAt, 120 * minute);
    expect(c2Key('schedule-editor'), findsNothing);
    await c2Finish(tester, store);
  });

  testWidgets('desktop: block edges show the up-down resize cursor', (
    tester,
  ) async {
    final store = await c2Store(items: [c1Items().first]);
    await c2Pump(tester, store, platform: TargetPlatform.windows);
    await tester.ensureVisible(c2Key(block));
    await tester.pumpAndSettle();
    for (final mode in ['resizeStart', 'resizeEnd']) {
      final region = tester.widget<MouseRegion>(
        c2Key('schedule-handle-2026-09-30-block-$mode'),
      );
      expect(region.cursor, SystemMouseCursors.resizeUpDown);
    }
    await c2Finish(tester, store);
  });

  testWidgets('delete asks once in a centered dialog, keeps the task', (
    tester,
  ) async {
    final store = await c2Store(items: [c1Items().first]);
    final item = store.scheduleItems.single;
    await c2Pump(tester, store);
    await select(tester);
    await c2Tap(tester, c2Key('schedule-detail-delete'));
    expect(c2Key('schedule-delete-confirm'), findsOneWidget);
    expect(store.scheduleItems, isNotEmpty);
    // Cancel keeps it.
    await c2Tap(tester, c2Key('schedule-delete-cancel'));
    expect(store.scheduleItems, isNotEmpty);
    await c2Tap(tester, c2Key('schedule-detail-delete'));
    await c2Tap(tester, c2Key('schedule-delete-submit'));
    expect(store.scheduleItems, isEmpty);
    expect(store.tasks.any((task) => task.id == item.taskId), isTrue);
    expect(find.byType(SnackBar), findsNothing);
    await c2Finish(tester, store);
  });

  testWidgets('overlapping items sit side by side and say so', (tester) async {
    final store = await c2Store();
    await c2Pump(tester, store);
    expect(find.textContaining('Same time as'), findsWidgets);
    final a = tester.getRect(c2Key('schedule-item-2026-09-30-block'));
    final b = tester.getRect(c2Key('schedule-item-2026-09-30-linked'));
    expect(a.overlaps(b), isFalse);
    expect(store.scheduleItems.length, c1Items().length);
    await c2Finish(tester, store);
  });

  testWidgets('saving an overlapping item from the form never asks first', (
    tester,
  ) async {
    final store = await c2Store(items: [c1Items().first]);
    await c2Pump(tester, store);
    await tester.tap(c2Key('schedule-add'));
    await tester.pumpAndSettle();
    await tester.enterText(c2Key('schedule-editor-title'), 'Parallel');
    await c2Text(tester, 'schedule-editor-start-time', '01:00');
    await c2Text(tester, 'schedule-editor-end-time', '02:00');
    await c2Tap(tester, c2Key('schedule-editor-save'));
    expect(c2Key('schedule-editor'), findsNothing);
    expect(store.scheduleItems.length, 2);
    expect(
      store.scheduleItems.any((i) => i.kind == ScheduleItemKind.event),
      isTrue,
    );
    expect(find.byType(SnackBar), findsNothing);
    await c2Finish(tester, store);
  });
}
