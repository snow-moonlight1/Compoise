import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/screens/planner_screen.dart';
import 'package:matrixflow_native/planner/schedule_edit_session.dart';
import 'package:matrixflow_native/planner/schedule_editor.dart';
import 'package:matrixflow_native/schedule_time.dart';
import 'package:matrixflow_native/storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'wp15_c2_test_support.dart';

String? focusedScheduleKey() {
  String? result;
  FocusManager.instance.primaryFocus?.context?.visitAncestorElements((element) {
    final key = element.widget.key;
    if (key is ValueKey<String> && key.value.startsWith('schedule-')) {
      result = key.value;
      return false;
    }
    return true;
  });
  return result;
}

Future<void> tabTo(
  WidgetTester tester,
  String key, {
  bool reverse = false,
}) async {
  for (var step = 0; step < 80; step++) {
    if (focusedScheduleKey() == key) return;
    if (reverse) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    if (reverse) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
  }
  fail('Keyboard could not reach $key; stopped at ${focusedScheduleKey()}');
}

Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pumpAndSettle();
}

Future<void> openLinkedEditor(WidgetTester tester) async {
  await tabTo(tester, 'schedule-item-2026-09-30-linked');
  await press(tester, LogicalKeyboardKey.enter);
  await tabTo(tester, 'schedule-detail-edit');
  await press(tester, LogicalKeyboardKey.enter);
}

void main() {
  testWidgets('drag proposal has leave protection before any form typing', (
    tester,
  ) async {
    final store = await c2Store();
    final before = c2Library(store);
    await c2Pump(tester, store);
    final session = ScheduleEditSession.edit(
      store,
      store.scheduleItems.singleWhere((item) => item.id == 'block'),
      mode: ScheduleEditMode.move,
      displayZone: c1Zone,
      target: ScheduleWallTime(
        ScheduleCivilDate(2026, 9, 30),
        hour: 5,
        minute: 0,
      ),
    );
    final result = showScheduleEditor(
      tester.element(find.byType(PlannerScreen)),
      session,
    );
    await tester.pumpAndSettle();
    await press(tester, LogicalKeyboardKey.escape);
    expect(c2Key('schedule-editor-discard-confirm'), findsOneWidget);
    await press(tester, LogicalKeyboardKey.escape);
    expect(c2Key('schedule-editor'), findsOneWidget);
    expect(c2Key('schedule-editor-discard-confirm'), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tabTo(tester, 'schedule-editor-discard');
    await press(tester, LogicalKeyboardKey.enter);
    expect(await result, isFalse);
    expect(c2Library(store), before);
    await c2Finish(tester, store);
  });

  testWidgets(
    'Escape cannot interrupt saving; failure focuses retry and preserves one revision',
    (tester) async {
      final gate = Completer<void>();
      var hold = false;
      var failWrite = false;
      final store = await c2Store(
        writer: (key, value) async {
          if (hold && key == SaveProtocol.pointerKey) {
            await gate.future;
            if (failWrite) return false;
          }
          return (await SharedPreferences.getInstance()).setString(key, value);
        },
      );
      await c2Pump(tester, store);
      await openLinkedEditor(tester);
      await c2Text(tester, 'schedule-editor-title', 'Durable keyboard edit');
      await tabTo(tester, 'schedule-editor-review');
      await press(tester, LogicalKeyboardKey.enter);
      await press(tester, LogicalKeyboardKey.space);
      await tabTo(tester, 'schedule-editor-save');
      hold = true;
      failWrite = true;
      await press(tester, LogicalKeyboardKey.enter);
      await press(tester, LogicalKeyboardKey.escape);
      expect(c2Key('schedule-editor'), findsOneWidget);
      expect(c2Key('schedule-editor-discard-confirm'), findsNothing);
      expect(
        tester.widget<TextButton>(c2Key('schedule-editor-cancel')).onPressed,
        isNull,
      );
      gate.complete();
      await tester.pumpAndSettle();
      expect(focusedScheduleKey(), 'schedule-editor-retry');
      final revision = store.scheduleRevision('linked');
      hold = false;
      failWrite = false;
      await press(tester, LogicalKeyboardKey.enter);
      expect(c2Key('schedule-editor'), findsNothing);
      expect(store.scheduleRevision('linked'), revision);
      expect(focusedScheduleKey(), 'schedule-item-2026-09-30-linked');
      await c2Finish(tester, store);
    },
  );
  testWidgets(
    'dirty Escape and system back protect the draft, including review',
    (tester) async {
      final store = await c2Store();
      final before = c2Library(store);
      await c2Pump(tester, store);
      await openLinkedEditor(tester);
      await c2Text(tester, 'schedule-editor-title', 'Keep this draft');
      await press(tester, LogicalKeyboardKey.escape);
      expect(c2Key('schedule-editor-discard-confirm'), findsOneWidget);
      expect(c2Key('schedule-editor'), findsOneWidget);
      // The safe choice is initially focused; Enter resumes editing.
      expect(focusedScheduleKey(), 'schedule-editor-keep-editing');
      await press(tester, LogicalKeyboardKey.enter);
      expect(c2Key('schedule-editor-discard-confirm'), findsNothing);
      expect(find.text('Keep this draft'), findsOneWidget);
      await tabTo(tester, 'schedule-editor-review');
      await press(tester, LogicalKeyboardKey.enter);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(c2Key('schedule-editor-discard-confirm'), findsOneWidget);
      await tabTo(tester, 'schedule-editor-discard');
      await press(tester, LogicalKeyboardKey.enter);
      expect(c2Key('schedule-editor'), findsNothing);
      expect(c2Library(store), before);
      expect(focusedScheduleKey(), 'schedule-item-2026-09-30-linked');
      await c2Finish(tester, store);
    },
  );

  testWidgets(
    'unchanged Escape restores the originating overlap and ShiftTab reverses',
    (tester) async {
      final store = await c2Store();
      await c2Pump(tester, store);
      await openLinkedEditor(tester);
      await press(tester, LogicalKeyboardKey.escape);
      expect(c2Key('schedule-editor'), findsNothing);
      expect(c2Key('schedule-editor-discard-confirm'), findsNothing);
      expect(focusedScheduleKey(), 'schedule-item-2026-09-30-linked');
      await tabTo(tester, 'schedule-item-2026-09-30-block', reverse: true);
      await press(tester, LogicalKeyboardKey.enter);
      expect(c2Key('schedule-detail'), findsOneWidget);
      await press(tester, LogicalKeyboardKey.escape);
      expect(focusedScheduleKey(), 'schedule-item-2026-09-30-block');
      await c2Finish(tester, store);
    },
  );

  testWidgets(
    'review transfers focus to explicit overlap consent before keyboard save',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final store = await c2Store();
      final parents = jsonEncode(
        store.tasks.map((task) => task.toJson()).toList(),
      );
      await c2Pump(tester, store);
      await openLinkedEditor(tester);
      await c2Text(tester, 'schedule-editor-title', 'Keyboard review');
      await tabTo(tester, 'schedule-editor-review');
      await press(tester, LogicalKeyboardKey.enter);
      expect(focusedScheduleKey(), 'schedule-editor-allow-overlap');
      expect(
        tester
            .getSemantics(c2Key('schedule-editor-save'))
            .getSemanticsData()
            .hasFlag(SemanticsFlag.isEnabled),
        isFalse,
      );
      await press(tester, LogicalKeyboardKey.space);
      await tabTo(tester, 'schedule-editor-save');
      await press(tester, LogicalKeyboardKey.enter);
      expect(c2Key('schedule-editor'), findsNothing);
      expect(
        store.scheduleItems.singleWhere((item) => item.id == 'linked').title,
        'Keyboard review',
      );
      expect(
        jsonEncode(store.tasks.map((task) => task.toJson()).toList()),
        parents,
      );
      expect(focusedScheduleKey(), 'schedule-item-2026-09-30-linked');
      await c2Finish(tester, store);
      semantics.dispose();
    },
  );

  testWidgets(
    'keyboard deletion cancels safely and restores focus after deleting a record',
    (tester) async {
      final store = await c2Store();
      final before = c2Library(store);
      await c2Pump(tester, store);
      Future<void> openDelete() async {
        await tabTo(tester, 'schedule-item-2026-09-30-linked');
        await press(tester, LogicalKeyboardKey.enter);
        await tabTo(tester, 'schedule-detail-actions');
        await press(tester, LogicalKeyboardKey.enter);
        for (var i = 0; i < 5; i++) {
          await press(tester, LogicalKeyboardKey.arrowDown);
        }
        await press(tester, LogicalKeyboardKey.enter);
        expect(c2Key('schedule-delete-confirm'), findsOneWidget);
      }

      await openDelete();
      await press(tester, LogicalKeyboardKey.escape);
      expect(c2Library(store), before);
      expect(focusedScheduleKey(), 'schedule-item-2026-09-30-linked');
      await openDelete();
      await tabTo(tester, 'schedule-delete-submit');
      await press(tester, LogicalKeyboardKey.enter);
      expect(store.scheduleItems.any((item) => item.id == 'linked'), isFalse);
      expect(
        store.scheduleItems.map((item) => item.id),
        containsAll(['block', 'independent', 'done']),
      );
      expect(focusedScheduleKey(), 'schedule-add');
      await c2Finish(tester, store);
    },
  );

  for (final width in [320.0, 390.0]) {
    for (final scale in [2.0, 3.0]) {
      testWidgets(
        '${width}px / ${scale}x week allows keyboard navigation and independent overlaps',
        (tester) async {
          final semantics = tester.ensureSemantics();
          final store = await c2Store();
          final before = c2Library(store);
          await c2Pump(
            tester,
            store,
            size: Size(width, 850),
            scale: scale,
            view: PlannerView.week,
          );
          await tabTo(tester, 'schedule-next');
          await press(tester, LogicalKeyboardKey.enter);
          expect(c2Key('schedule-day-2026-10-05'), findsOneWidget);
          await tabTo(tester, 'schedule-previous', reverse: true);
          await press(tester, LogicalKeyboardKey.enter);
          for (final id in ['block', 'linked', 'independent', 'done']) {
            await tabTo(tester, 'schedule-item-2026-09-30-$id');
            final card = c2Key('schedule-item-2026-09-30-$id');
            expect(
              tester.getRect(card).overlaps(Offset.zero & Size(width, 850)),
              isTrue,
            );
            final data = tester
                .getSemantics(c2Key('schedule-semantics-2026-09-30-$id'))
                .getSemanticsData();
            expect(data.hasAction(SemanticsAction.tap), isTrue);
            expect(data.hasFlag(SemanticsFlag.isFocused), isTrue);
            expect(data.label, contains('UTC+08:00'));
            if (id == 'done') expect(data.label, contains('Completed'));
            await press(tester, LogicalKeyboardKey.enter);
            await press(tester, LogicalKeyboardKey.escape);
          }
          expect(c2Library(store), before);
          expect(tester.takeException(), isNull);
          await c2Finish(tester, store);
          semantics.dispose();
        },
      );
    }
  }
}
