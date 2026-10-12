import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/schedule_item.dart';
import 'package:matrixflow_native/schedule_time.dart';
import 'package:matrixflow_native/widgets/schedule_layout.dart';

import 'package:matrixflow_native/screens/planner_screen.dart';
import 'package:matrixflow_native/save_protocol.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'wp15_c2_test_support.dart';

/// At most one floating layer is ever up: a dialog, the selection bar, or the
/// opened task pool. Never two of them, and never a toast.
void main() {
  const size = Size(400, 800);
  const block = 'schedule-item-2026-09-30-block';

  int layers(WidgetTester tester) {
    var n = 0;
    n += find.byType(Dialog).evaluate().length;
    n += find.byType(AlertDialog).evaluate().length;
    if (c2Key('schedule-detail').evaluate().isNotEmpty) n++;
    final tab = c2Key('schedule-pool-tab-1');
    if (tab.evaluate().isNotEmpty &&
        tester.getTopLeft(tab).dy < size.height - 90) {
      n++;
    }
    expect(find.byType(SnackBar), findsNothing);
    return n;
  }

  testWidgets('pool, selection bar and dialogs never stack', (tester) async {
    final store = await c2Store(items: [c1Items().first]);
    await c2Pump(tester, store, size: size);
    expect(layers(tester), 0);

    await tester.tap(find.textContaining('Task pool'));
    await tester.pumpAndSettle();
    expect(layers(tester), 1);

    // Selecting folds the pool, then only the bar is up.
    await c2Tap(tester, c2Key(block));
    expect(c2Key('schedule-detail'), findsOneWidget);
    expect(layers(tester), 1);

    // Edit: the bar steps aside for the one centered dialog.
    await c2Tap(tester, c2Key('schedule-detail-edit'));
    expect(c2Key('schedule-editor'), findsOneWidget);
    expect(c2Key('schedule-detail'), findsNothing);
    expect(layers(tester), 1);
    final width = tester.getSize(find.byType(Dialog)).width;
    expect(width, lessThanOrEqualTo(420));
    expect(width, greaterThan(300));
    await c2Tap(tester, c2Key('schedule-editor-cancel'));
    expect(layers(tester), 1);

    // Opening the pool drops the selection and its bar.
    await tester.tap(find.textContaining('Task pool'));
    await tester.pumpAndSettle();
    expect(c2Key('schedule-detail'), findsNothing);
    expect(layers(tester), 1);
    await c2Finish(tester, store);
  });

  testWidgets('new and edit share one dialog size', (tester) async {
    final store = await c2Store(items: [c1Items().first]);
    await c2Pump(tester, store, size: size);
    await tester.tap(c2Key('schedule-add'));
    await tester.pumpAndSettle();
    final created = tester.getSize(find.byType(Dialog)).width;
    await c2Tap(tester, c2Key('schedule-editor-cancel'));
    await c2Tap(tester, c2Key(block));
    await c2Tap(tester, c2Key('schedule-detail-edit'));
    expect(tester.getSize(find.byType(Dialog)).width, created);
    await c2Tap(tester, c2Key('schedule-editor-cancel'));
    await c2Finish(tester, store);
  });

  testWidgets('week lists every label, wraps, and has no +N or side scroll', (
    tester,
  ) async {
    final store = await c2Store();
    await c2Pump(tester, store, size: size, view: PlannerView.week);
    expect(find.textContaining(RegExp(r'^\+\d')), findsNothing);
    expect(find.textContaining('more'), findsNothing);
    expect(find.text('Nothing planned'), findsWidgets);
    for (final id in ['block', 'linked', 'independent', 'done']) {
      expect(c2Key('schedule-item-2026-09-30-$id'), findsOneWidget);
    }
    final horizontal = find.byWidgetPredicate(
      (w) => w is SingleChildScrollView && w.scrollDirection == Axis.horizontal,
    );
    expect(horizontal, findsNothing);
    await c2Finish(tester, store);
  });

  Future<void> resizeEnd(WidgetTester tester) async {
    await c2Tap(tester, c2Key(block));
    final handle = c2Key('schedule-handle-2026-09-30-block-resizeEnd');
    final g = await tester.startGesture(tester.getCenter(handle));
    await g.moveBy(const Offset(0, 24));
    await tester.pump();
    await g.moveBy(const Offset(0, 66));
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
  }

  testWidgets('a failed save says so once, then goes away by itself', (
    tester,
  ) async {
    var fail = false;
    final store = await c2Store(
      items: [c1Items().first],
      writer: (key, value) async {
        if (fail && key == SaveProtocol.pointerKey) return false;
        return (await SharedPreferences.getInstance()).setString(key, value);
      },
    );
    await c2Pump(tester, store, size: size);
    fail = true;
    await resizeEnd(tester);
    expect(find.text(store.t['scheduleEditorUnsaved']!), findsOneWidget);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text('Undo'), findsNothing);
    // The message sits above the selection bar, not on top of it.
    final bar = tester.getRect(c2Key('schedule-detail'));
    final toast = tester.getRect(find.text(store.t['scheduleEditorUnsaved']!));
    expect(toast.bottom, lessThanOrEqualTo(bar.top));
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
    await c2Finish(tester, store);
  });

  testWidgets('a failed delete says so; a successful one is silent', (
    tester,
  ) async {
    var fail = false;
    final store = await c2Store(
      items: [c1Items().first],
      writer: (key, value) async {
        if (fail && key == SaveProtocol.pointerKey) return false;
        return (await SharedPreferences.getInstance()).setString(key, value);
      },
    );
    await c2Pump(tester, store, size: size);
    await c2Tap(tester, c2Key(block));
    fail = true;
    await c2Tap(tester, c2Key('schedule-detail-delete'));
    await c2Tap(tester, c2Key('schedule-delete-submit'));
    expect(find.text(store.t['scheduleDeleteFailed']!), findsOneWidget);
    expect(find.byType(SnackBar), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
    await c2Finish(tester, store);
  });

  testWidgets('a successful resize shows nothing', (tester) async {
    final store = await c2Store(items: [c1Items().first]);
    await c2Pump(tester, store, size: size);
    await resizeEnd(tester);
    expect(find.byType(SnackBar), findsNothing);
    await c2Finish(tester, store);
  });

  testWidgets('a bad time stays inside the dialog as plain text', (
    tester,
  ) async {
    final store = await c2Store(items: [c1Items().first]);
    await c2Pump(tester, store, size: size);
    await c2Tap(tester, c2Key(block));
    await c2Tap(tester, c2Key('schedule-detail-edit'));
    await c2Text(tester, 'schedule-editor-start-time', '10:00');
    await c2Text(tester, 'schedule-editor-end-time', '09:00');
    await c2Tap(tester, c2Key('schedule-editor-save'));
    expect(c2Key('schedule-editor'), findsOneWidget);
    expect(
      find.descendant(
        of: c2Key('schedule-editor'),
        matching: find.text(store.t['scheduleEditorEndBeforeStart']!),
      ),
      findsOneWidget,
    );
    expect(find.byType(SnackBar), findsNothing);
    await c2Tap(tester, c2Key('schedule-editor-cancel'));
    await c2Finish(tester, store);
  });

  test('columns are per overlap cluster, not per day', () {
    ScheduleItem ev(String id, int h1, int h2) => ScheduleItem.event(
      id: id,
      title: id,
      boardId: 'b',
      startAt: DateTime.utc(2026, 9, 30, h1).millisecondsSinceEpoch,
      endAt: DateTime.utc(2026, 9, 30, h2).millisecondsSinceEpoch,
      timeZoneId: 'UTC',
    );
    final day = ScheduleDayLayout(
      date: ScheduleCivilDate(2026, 9, 30),
      timeZoneId: 'UTC',
      entries: [
        for (final i in [
          ev('lone', 6, 7),
          ev('a', 9, 12),
          ev('b', 9, 11),
          ev('c', 10, 12),
          ev('after', 12, 13), // touches the cluster's end, does not overlap
        ])
          ScheduleEntry(item: i, title: i.title!, boardId: 'b', boardName: 'B'),
      ],
      pixelsPerHour: 60,
      minimumItemHeight: 10,
    );
    SchedulePlacement of(String id) =>
        day.placements.firstWhere((p) => p.entry.item.id == id);
    expect(of('lone').lanes, 1);
    expect(of('after').lanes, 1);
    for (final id in ['a', 'b', 'c']) {
      expect(of(id).lanes, 3, reason: id);
    }
    expect({of('a').lane, of('b').lane, of('c').lane}, {0, 1, 2});
    expect(day.laneCount, 3);
  });
}
