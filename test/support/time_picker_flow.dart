import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Choose a concrete instant through the actual date and 24-hour time dialogs.
Future<void> chooseTaskMoment(
  WidgetTester tester,
  String key,
  DateTime moment,
) async {
  final entry = find.byKey(ValueKey(key));
  await tester.ensureVisible(entry);
  await tester.tap(entry);
  await tester.pumpAndSettle();
  final dateDialog = find.byType(DatePickerDialog);
  final input = find.descendant(
    of: dateDialog,
    matching: find.byIcon(Icons.edit_outlined),
  );
  if (input.evaluate().isNotEmpty) {
    await tester.tap(input);
    await tester.pumpAndSettle();
  }
  final labels = MaterialLocalizations.of(tester.element(dateDialog));
  await tester.enterText(
    find.descendant(of: dateDialog, matching: find.byType(TextField)),
    labels.formatCompactDate(moment),
  );
  await tester.tap(
    find.descendant(of: dateDialog, matching: find.text(labels.okButtonLabel)),
  );
  await tester.pumpAndSettle();
  await chooseTaskClock(tester, TimeOfDay.fromDateTime(moment));
}

Future<void> chooseTaskClock(WidgetTester tester, TimeOfDay time) async {
  final dialog = find.byType(TimePickerDialog);
  expect(dialog, findsOneWidget);
  final input = find.descendant(
    of: dialog,
    matching: find.byIcon(Icons.keyboard_outlined),
  );
  if (input.evaluate().isNotEmpty) {
    await tester.tap(input);
    await tester.pumpAndSettle();
  }
  final fields = find.descendant(of: dialog, matching: find.byType(TextField));
  await tester.enterText(fields.at(0), '${time.hour}');
  await tester.enterText(fields.at(1), '${time.minute}');
  final labels = MaterialLocalizations.of(tester.element(dialog));
  await tester.tap(
    find.descendant(of: dialog, matching: find.text(labels.okButtonLabel)),
  );
  await tester.pumpAndSettle();
}
