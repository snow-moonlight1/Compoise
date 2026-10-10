import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/schedule_item.dart';
import 'package:matrixflow_native/schedule_time.dart';
import 'package:matrixflow_native/screens/planner_screen.dart';
import 'package:matrixflow_native/storage.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/wp15_c1_fixtures.dart';
export 'support/wp15_c1_fixtures.dart';

Finder c2Key(String key) => find.byKey(ValueKey(key));
Future<Store> c2Store({
  List<ScheduleItem>? items,
  SaveWrite? writer,
  bool recovery = false,
}) async {
  SharedPreferences.setMockInitialValues({
    'matrixflow-boards': jsonEncode(c1Boards().map((b) => b.toJson()).toList()),
    'matrixflow-tasks': jsonEncode(c1Tasks().map((t) => t.toJson()).toList()),
    'matrixflow-schedule': recovery
        ? 'broken'
        : jsonEncode((items ?? c1Items()).map((i) => i.toJson()).toList()),
    'matrixflow-settings': jsonEncode(
      AppSettings(language: Language.en).toJson(),
    ),
  });
  final store = Store(saveWriter: writer);
  await store.init();
  if (!recovery) await store.flush(waitForReminders: false);
  return store;
}

Future<void> c2Pump(
  WidgetTester tester,
  Store store, {
  double scale = 1,
  Size size = const Size(1200, 900),
  PlannerView view = PlannerView.day,
  String? zone,
  String? initialTaskId,
  bool startTimeBlock = false,
  bool provide = false,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final app = MaterialApp(
    theme: ThemeData(useMaterial3: true, platform: TargetPlatform.windows),
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    supportedLocales: const [Locale('en'), Locale('zh'), Locale('ja')],
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: PlannerScreen(
      store: store,
      displayTimeZoneId: zone ?? c1Zone,
      initialDate: ScheduleCivilDate(2026, 9, 30),
      initialView: view,
      initialTaskId: initialTaskId,
      startTimeBlock: startTimeBlock,
    ),
  );
  await tester.pumpWidget(
    provide ? ChangeNotifierProvider<Store>.value(value: store, child: app) : app,
  );
  await tester.pumpAndSettle();
}

Future<void> c2Tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  final visible = tester
      .getRect(target)
      .intersect(tester.getRect(find.byType(Scaffold).first));
  expect(visible.isEmpty, isFalse);
  await tester.tapAt(visible.center);
  await tester.pumpAndSettle();
}

Future<void> c2Enter(WidgetTester tester, Finder target, String value) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  final widget = tester.widget(target);
  if (widget is TextFormField || widget is TextField) {
    await tester.enterText(target, value);
    await tester.pumpAndSettle();
    return;
  }
  await tester.tap(target);
  await tester.pumpAndSettle();
  final dateDialog = find.byType(DatePickerDialog);
  if (dateDialog.evaluate().isNotEmpty) {
    final edit = find.descendant(
      of: dateDialog,
      matching: find.byIcon(Icons.edit_outlined),
    );
    if (edit.evaluate().isNotEmpty) {
      await tester.tap(edit);
      await tester.pumpAndSettle();
    }
    final parts = value.split('-');
    final typed = parts.length == 3
        ? '${parts[1]}/${parts[2]}/${parts[0]}'
        : value;
    await tester.enterText(
      find.descendant(of: dateDialog, matching: find.byType(TextField)).last,
      typed,
    );
    await tester.tap(
      find.descendant(of: dateDialog, matching: find.text('OK')),
    );
    await tester.pumpAndSettle();
    return;
  }
  final timeDialog = find.byType(TimePickerDialog);
  if (timeDialog.evaluate().isNotEmpty) {
    final keyboard = find.descendant(
      of: timeDialog,
      matching: find.byIcon(Icons.keyboard_outlined),
    );
    if (keyboard.evaluate().isNotEmpty) {
      await tester.tap(keyboard);
      await tester.pumpAndSettle();
    }
    final fields = find.descendant(
      of: timeDialog,
      matching: find.byType(TextField),
    );
    final parts = value.split(':');
    await tester.enterText(fields.at(0), parts[0]);
    await tester.enterText(fields.at(1), parts[1]);
    await tester.tap(
      find.descendant(of: timeDialog, matching: find.text('OK')),
    );
    await tester.pumpAndSettle();
    return;
  }
  await tester.enterText(target, value);
  await tester.pumpAndSettle();
}

Future<void> c2Text(WidgetTester tester, String key, String value) async {
  await c2Enter(tester, c2Key(key), value);
}

Future<void> c2Finish(WidgetTester tester, Store store) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.runAsync(() => store.flush(waitForReminders: false));
  store.dispose();
  await tester.pump();
}

String c2Library(Store store) => jsonEncode({
  'tasks': store.tasks.map((task) => task.toJson()).toList(),
  'boards': store.boards.map((board) => board.toJson()).toList(),
  'items': store.scheduleItems.map((item) => item.toJson()).toList(),
  'revisions': store.captureSnapshot().scheduleRevisions,
  'active': store.activeBoardId,
});
