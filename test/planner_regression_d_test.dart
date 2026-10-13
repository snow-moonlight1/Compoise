import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:compoise/planner/planner_drag_feedback.dart';
import 'package:compoise/planner/planner_toolbar.dart';
import 'package:compoise/screens/planner_screen.dart';

import 'planner_test_support.dart';

void main() {
  testWidgets('the toolbar has no "today" control; the title is whole', (
    tester,
  ) async {
    final store = await c2Store(items: []);
    await c2Pump(
      tester,
      store,
      size: const Size(320, 640),
      view: PlannerView.week,
    );
    expect(
      find.descendant(
        of: find.byType(PlannerToolbar),
        matching: c2Key('schedule-today'),
      ),
      findsNothing,
    );
    // The range title is whole, not cut with an ellipsis.
    final title = find.descendant(
      of: c2Key('schedule-date'),
      matching: find.byType(Text),
    );
    final paragraph = tester.renderObject<RenderParagraph>(title);
    expect(paragraph.didExceedMaxLines, isFalse);
    expect(tester.getSize(title).width, greaterThan(60));
    await c2Finish(tester, store);
  });

  testWidgets('a dragged week label: faded original, same-size preview', (
    tester,
  ) async {
    final store = await c2Store(
      items: [c1Event('a', c1At(30, 1), c1At(30, 2))],
    );
    await c2Pump(
      tester,
      store,
      size: const Size(640, 800),
      view: PlannerView.week,
    );
    final label = c2Key('schedule-item-2026-09-30-a');
    final original = tester.getRect(label);
    final start = original.center;
    final g = await tester.startGesture(start);
    await tester.pump(const Duration(milliseconds: 700));
    await g.moveBy(const Offset(0, 60));
    await tester.pump();
    final feedback = find.byType(PlannerDragFeedback);
    expect(feedback, findsOneWidget);
    // Same size as the label it came from.
    final box = tester.getSize(
      find.descendant(of: feedback, matching: find.byType(SizedBox)).last,
    );
    expect(box.width, closeTo(original.width, 0.5));
    expect(box.height, closeTo(original.height, 0.5));
    // A small step up-left of the finger.
    final shown = tester.getRect(
      find.descendant(of: feedback, matching: find.byType(SizedBox)).last,
    );
    final finger = start + const Offset(0, 60);
    expect(shown.right - finger.dx, inInclusiveRange(0, 12));
    expect(shown.bottom - finger.dy, inInclusiveRange(0, 12));
    // The original stays behind, faded.
    expect(
      find.byWidgetPredicate((w) => w is Opacity && w.opacity == 0.38),
      findsOneWidget,
    );
    await g.up();
    await tester.pumpAndSettle();
    await c2Finish(tester, store);
  });
}
