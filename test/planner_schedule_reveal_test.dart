// Task page -> task -> "Schedule time" opens the schedule tab with the task
// pool raised to its usual opened height and the task pointed out first,
// in every theme, on a phone.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:compoise/models.dart';
import 'package:compoise/planner/planner_task_pool.dart';
import 'package:compoise/screens/matrix_screen.dart';
import 'package:compoise/storage.dart';
import 'package:compoise/theme.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'planner_navigation_test.dart' show mockDeviceTimeZone;

enum _Skin { plain, comic, neu }

Task _make(int i) => Task(
  id: 'T$i',
  boardId: 'b',
  title: 'Task $i',
  quadrant: 1,
  createdAt: i,
  urgencyMode: UrgencyMode.manual,
);

void main() {
  setUp(() => ReminderService.resetForTest(InMemoryReminderService()));
  tearDown(() => ReminderService.resetForTest());

  for (final skin in _Skin.values) {
    for (final (guideSeen, visited) in [
      (true, false),
      (false, false),
      (true, true),
    ]) {
      testWidgets(
        '${skin.name}${guideSeen ? '' : ' (first visit)'}${visited ? ' (schedule opened before)' : ''}: schedule time raises the pool',
        (tester) async {
          mockDeviceTimeZone(identity: 'Asia/Shanghai');
          await tester.binding.setSurfaceSize(const Size(411, 900));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          SharedPreferences.setMockInitialValues({
            'compoise-has-seen-onboarding': true,
            if (guideSeen) 'compoise-planner-guide-seen': true,
            if (guideSeen) 'compoise-planner-tabhint-seen': true,
            'compoise-boards': jsonEncode([
              Board(id: 'b', name: 'Board', createdAt: 1).toJson(),
            ]),
            'compoise-tasks': jsonEncode([
              for (var i = 1; i <= 3; i++) _make(i).toJson(),
            ]),
          });
          final store = Store();
          await store.init();
          // Like the app root: the theme is rebuilt on every Store change.
          await tester.pumpWidget(
            ChangeNotifierProvider.value(
              value: store,
              child: Consumer<Store>(
                builder: (context, store, _) => MaterialApp(
                  theme: buildTheme(
                    Brightness.light,
                    ThemeColor.purple,
                    comicOutline: skin == _Skin.comic,
                    neumorphic: skin == _Skin.neu,
                  ),
                  localizationsDelegates: GlobalMaterialLocalizations.delegates,
                  supportedLocales: const [Locale('en'), Locale('zh')],
                  home: const MatrixHome(),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          if (visited) {
            await tester.tap(find.byKey(const ValueKey('schedule-btn')));
            await tester.pumpAndSettle();
            final skip = find.byKey(const ValueKey('schedule-guide-skip'));
            if (skip.evaluate().isNotEmpty) {
              await tester.tap(skip);
              await tester.pumpAndSettle();
            }
            // The pool is opened and folded again while the keyboard is up
            // (a shorter page), then the keyboard goes away.
            tester.view.viewInsets = FakeViewPadding(
              bottom: 300 * tester.view.devicePixelRatio,
            );
            addTearDown(tester.view.resetViewInsets);
            await tester.pumpAndSettle();
            Offset bar() => tester.getCenter(
              find
                  .descendant(
                    of: find.byType(DraggableScrollableSheet),
                    matching: find.textContaining(store.t['schedulePool']!),
                  )
                  .first,
            );
            await tester.tapAt(bar());
            await tester.pumpAndSettle();
            await tester.tapAt(bar());
            await tester.pumpAndSettle();
            tester.view.viewInsets = FakeViewPadding.zero;
            await tester.pumpAndSettle();
            final c = tester
                .widget<DraggableScrollableSheet>(
                  find.byType(DraggableScrollableSheet),
                )
                .controller!;
            final min = tester
                .widget<DraggableScrollableSheet>(
                  find.byType(DraggableScrollableSheet),
                )
                .minChildSize;
            expect(
              c.size,
              closeTo(min, 0.005),
              reason: 'folded pool stays a bar',
            );
            await tester.tap(find.byKey(const ValueKey('home-tab-tasks')));
            await tester.pumpAndSettle();
          }
          await tester.tap(find.text('Task 2').first);
          await tester.pumpAndSettle();
          // An edit in the sheet: "Schedule time" saves it on the way out,
          // and that Store change rebuilds the theme mid-animation.
          await tester.enterText(
            find.byKey(const ValueKey('edit-title')),
            'Task 2 edited',
          );
          await tester.pumpAndSettle();
          final entry = find.byKey(const ValueKey('edit-schedule-entry'));
          await tester.ensureVisible(entry);
          await tester.pumpAndSettle();
          // The title field autofocuses, so on a phone the keyboard is up.
          // Tapping the entry closes the sheet and the keyboard slides away
          // while the schedule tab opens.
          // (Not in the "opened before" case: there the keyboard was
          // dismissed before tapping, which is what left the pool stale.)
          final keyboard = !visited;
          if (keyboard) {
            tester.view.viewInsets = FakeViewPadding(
              bottom: 300 * tester.view.devicePixelRatio,
            );
            addTearDown(tester.view.resetViewInsets);
          }
          await tester.pump();
          await tester.tap(entry);
          for (var i = keyboard ? 9 : -1; i >= 0; i--) {
            await tester.pump(const Duration(milliseconds: 30));
            tester.view.viewInsets = FakeViewPadding(
              bottom: 30.0 * i * tester.view.devicePixelRatio,
            );
          }
          await tester.pumpAndSettle();
          final skip = find.byKey(const ValueKey('schedule-guide-skip'));
          if (skip.evaluate().isNotEmpty) {
            await tester.tap(skip);
            await tester.pumpAndSettle();
          }

          final sheet = find.byType(DraggableScrollableSheet);
          expect(sheet, findsOneWidget);
          final controller = tester
              .widget<DraggableScrollableSheet>(sheet)
              .controller!;
          expect(
            controller.size,
            closeTo(plannerPoolOpenSize, 0.02),
            reason: 'pool open extent',
          );
          final card = find.byKey(const ValueKey('schedule-pool-T2'));
          expect(card.hitTestable(), findsOneWidget);
          for (final other in ['T1', 'T3']) {
            final f = find.byKey(ValueKey('schedule-pool-$other'));
            if (f.evaluate().isNotEmpty) {
              expect(
                tester.getTopLeft(f).dy,
                greaterThan(tester.getTopLeft(card).dy),
              );
            }
          }
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.runAsync(() => store.flush(waitForReminders: false));
          store.dispose();
          await tester.pump();
        },
      );
    }
  }
}
