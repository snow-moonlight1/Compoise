import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Opens a settings row.
///
/// Short rows expand in place. Font and assistant open a detail page.
/// A repeated pumpWidget can leave that page up; it is closed first.
/// An expander that is already open is left open.
Future<void> openSettingsPanel(WidgetTester tester, String rowKey) async {
  final row = find.byKey(ValueKey(rowKey));
  final onDetail = find
      .byKey(const ValueKey('settings-detail-list'))
      .evaluate()
      .isNotEmpty;
  if (onDetail && row.evaluate().isEmpty) {
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
  }
  final scrollable = find.descendant(
    of: find.byKey(const ValueKey('settings-list')),
    matching: find.byType(Scrollable),
  );
  if (row.hitTestable().evaluate().isEmpty) {
    final position = tester.state<ScrollableState>(scrollable).position;
    if (position.hasPixels && position.pixels > 0) {
      position.jumpTo(0);
      await tester.pumpAndSettle();
    }
    if (row.hitTestable().evaluate().isEmpty) {
      await tester.scrollUntilVisible(row, 300, scrollable: scrollable);
    }
  }
  await tester.ensureVisible(row);
  final chevron = find.byKey(ValueKey('$rowKey-chevron'));
  if (chevron.evaluate().isNotEmpty) {
    final rotation = tester.widget<AnimatedRotation>(chevron);
    if (rotation.turns != 0) return;
  }
  await tester.tap(row);
  await tester.pumpAndSettle();
}
