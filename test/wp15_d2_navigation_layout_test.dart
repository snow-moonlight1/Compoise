import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/screens/matrix_screen.dart';
import 'package:matrixflow_native/widgets/task_detail_panel.dart';
import 'package:provider/provider.dart';

import 'helpers.dart';

void main() {
  testWidgets(
    'D2 narrow home keeps plan, deadline and reminder while opening detail',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final (store, _) = await makeStore(
        settings: AppSettings(language: Language.en, reduceMotion: true),
      );
      final parent = store.newTask('D2 parent', quadrant: 2)
        ..plannedDate = DateTime(2026, 3, 7).millisecondsSinceEpoch
        ..deadline = DateTime(2030, 3, 9, 23, 59, 59).millisecondsSinceEpoch
        ..reminderAt = DateTime(2030, 3, 9, 9).millisecondsSinceEpoch
        ..subtasks = [
          SubTask(id: 'd2-child', title: 'D2 child', completed: true),
        ];
      store.addTasks([parent]);
      try {
        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: store,
            child: MaterialApp(
              theme: ThemeData(platform: TargetPlatform.android),
              locale: const Locale('en'),
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              supportedLocales: const [
                Locale('en'),
                Locale('zh'),
                Locale('ja'),
              ],
              home: const MatrixHome(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          find.byKey(ValueKey('task-planned-${parent.id}')),
          findsOneWidget,
        );
        expect(
          find.byIcon(Icons.notifications_active_outlined),
          findsOneWidget,
        );
        await tester.tap(find.text('D2 parent').first);
        await tester.pumpAndSettle();
        expect(find.byType(TaskDetailPanel), findsOneWidget);
        expect(
          find.byKey(const ValueKey('edit-schedule-entry')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        store.dispose();
      }
    },
  );
}
