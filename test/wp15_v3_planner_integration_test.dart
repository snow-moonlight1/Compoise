import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/schedule_item.dart';
import 'package:matrixflow_native/schedule_time.dart';
import 'package:matrixflow_native/screens/planner_screen.dart';
import 'package:matrixflow_native/storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('v3 import appears in the live Planner only after commit', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final store = Store();
    await store.init();
    await store.flush();

    final start = DateTime.utc(2026, 9, 30, 1).millisecondsSinceEpoch;
    final payload = ExportData(
      boards: [Board(id: 'work', name: 'Work', createdAt: 1)],
      tasks: [
        Task(
          id: 'task',
          boardId: 'work',
          title: 'Imported task',
          quadrant: 2,
          createdAt: 1,
        ),
      ],
      scheduleItems: [
        ScheduleItem.timeBlock(
          id: 'block',
          taskId: 'task',
          startAt: start,
          endAt: start + const Duration(hours: 1).inMilliseconds,
          timeZoneId: 'Asia/Shanghai',
        ),
      ],
      settings: AppSettings(language: Language.en),
      aiConfig: AIConfig(),
      timestamp: 1,
    ).toJson();
    expect(payload['version'], 3);
    final plan = store.previewImport(payload, 'overwrite');
    expect(plan.conflicts, 0);
    expect(store.scheduleItems, isEmpty);
    expect((await store.applyImport(plan)).success, isTrue);
    await store.flush();

    final before = jsonEncode(store.scheduleItems.single.toJson());
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('en')],
        home: PlannerScreen(
          store: store,
          displayTimeZoneId: 'Asia/Shanghai',
          initialDate: ScheduleCivilDate(2026, 9, 30),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('schedule-item-2026-09-30-block')),
      findsOneWidget,
    );
    expect(find.textContaining('Imported task'), findsWidgets);
    expect(jsonEncode(store.scheduleItems.single.toJson()), before);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(store.flush);
    store.dispose();
  });
}
