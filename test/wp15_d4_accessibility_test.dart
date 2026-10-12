
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:compoise/screens/planner_screen.dart';

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
            expect(data.label, contains('–'));
            expect(data.label, isNot(contains('UTC')));
            if (id == 'done') expect(data.label, contains('Completed'));
            await press(tester, LogicalKeyboardKey.enter);
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
