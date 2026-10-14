import 'package:compoise/screens/today_screen.dart';
import 'package:compoise/schedule_item.dart';
import 'package:compoise/storage.dart';
import 'package:compoise/theme.dart';
import 'package:compoise/ui/motion_policy.dart';
import 'package:compoise/widgets/animated_task_title.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'helpers.dart';

Widget app(Store store, String skin, TargetPlatform platform) =>
    ChangeNotifierProvider.value(
      value: store,
      child: MaterialApp(
        theme: buildTheme(
          Brightness.light,
          store.settings.themeColor,
          platform: platform,
          comicOutline: skin == 'comic',
          neumorphic: skin == 'neumorphic',
        ),
        home: const TodayScreen(),
      ),
    );

void main() {
  testWidgets(
    'another section finishing does not restart a pending strikethrough',
    (tester) async {
      final (store, _) = await makeStore();
      final scheduled = store.newTask('Scheduled');
      final due = store.newTask(
        'Due',
        deadline: DateTime.now().millisecondsSinceEpoch,
      );
      store.addTasks([scheduled, due]);
      final now = DateTime.now();
      store.addScheduleItem(
        ScheduleItem.timeBlock(
          id: 'slot',
          taskId: scheduled.id,
          startAt: DateTime(
            now.year,
            now.month,
            now.day,
            9,
          ).millisecondsSinceEpoch,
          endAt: DateTime(
            now.year,
            now.month,
            now.day,
            10,
          ).millisecondsSinceEpoch,
          timeZoneId: 'Asia/Shanghai',
        ),
      );
      await tester.pumpWidget(app(store, 'default', TargetPlatform.android));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('today-check-${scheduled.id}')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.byKey(ValueKey('today-check-${due.id}')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 320));
      expect(find.byKey(ValueKey('today-item-${scheduled.id}')), findsNothing);
      final painter =
          tester
                  .widget<CustomPaint>(
                    find.byKey(ValueKey('today-strike-${due.id}')),
                  )
                  .foregroundPainter!
              as StrikeThroughPainter;
      expect(painter.progress, inExclusiveRange(0, 1));
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('today-item-${due.id}')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    },
  );

  for (final skin in ['default', 'comic', 'neumorphic']) {
    for (final platform in [
      TargetPlatform.android,
      TargetPlatform.windows,
      TargetPlatform.linux,
    ]) {
      testWidgets(
        'Today draws wrapped lines before collapsing ($skin, ${platform.name})',
        (tester) async {
          tester.view.physicalSize = const Size(390, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final (store, _) = await makeStore();
          final task = store.newTask(
            'Prepare the project materials and check the meeting agenda with the team',
            deadline: DateTime.now().millisecondsSinceEpoch,
          );
          store.addTasks([task]);
          await tester.pumpWidget(app(store, skin, platform));
          await tester.pumpAndSettle();
          final strike = find.byKey(ValueKey('today-strike-${task.id}'));
          StrikeThroughPainter painter() =>
              tester.widget<CustomPaint>(strike).foregroundPainter!
                  as StrikeThroughPainter;
          expect(painter().progress, 0);
          await tester.tap(find.byKey(ValueKey('today-check-${task.id}')));
          await tester.pump();
          expect(store.tasks.single.completed, isTrue);
          expect(find.byKey(ValueKey('today-item-${task.id}')), findsOneWidget);
          expect(find.byKey(const ValueKey('today-celebration')), findsNothing);
          await tester.pump(MotionPolicy.strikethrough ~/ 2);
          expect(painter().progress, inExclusiveRange(0, 1));
          expect(painter().lineCount, greaterThan(1));
          await tester.pump(MotionPolicy.strikethrough ~/ 2);
          expect(painter().progress, 1);
          await tester.pump(MotionPolicy.exitCollapse);
          await tester.pump();
          expect(find.byKey(ValueKey('today-item-${task.id}')), findsNothing);
          expect(
            find.byKey(const ValueKey('today-celebration')),
            findsOneWidget,
          );
          await tester.pumpWidget(const SizedBox());
          store.dispose();
        },
      );
    }
  }

  testWidgets(
    'restoring during exit cancels the collapse and leaving disposes pending timers',
    (tester) async {
      final (store, _) = await makeStore();
      final task = store.newTask(
        'Restore during completion',
        deadline: DateTime.now().millisecondsSinceEpoch,
      );
      store.addTasks([task]);
      await tester.pumpWidget(app(store, 'neumorphic', TargetPlatform.android));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('today-check-${task.id}')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      store.setParentCompleted(task, false);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(ValueKey('today-item-${task.id}')), findsOneWidget);
      expect(find.byKey(const ValueKey('today-celebration')), findsNothing);
      await tester.tap(find.byKey(ValueKey('today-check-${task.id}')));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
      store.dispose();
    },
  );
}
