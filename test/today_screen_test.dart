import 'package:compoise/schedule_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:compoise/models.dart';
import 'package:compoise/planned_policy.dart';
import 'package:compoise/screens/matrix_screen.dart';
import 'package:compoise/screens/today_screen.dart';
import 'package:compoise/storage.dart';
import 'package:provider/provider.dart';

import 'helpers.dart';

/// the Today page aggregates by day across quadrants and boards. It must
/// show which quadrant a task belongs to without grouping by it, and its plan
/// actions must not disturb the deadline or the quadrant.
Widget _wrap(Store store, Widget home) => ChangeNotifierProvider.value(
  value: store,
  child: MaterialApp(
    theme: ThemeData(useMaterial3: true, platform: TargetPlatform.windows),
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    supportedLocales: const [Locale('en'), Locale('zh'), Locale('ja')],
    home: home,
  ),
);

Future<Store> _seedStore({bool planToday = true, bool withStep = false}) async {
  final now = DateTime.now();
  final today = plannedDayMs(now)!;
  final endOfToday = DateTime(
    now.year,
    now.month,
    now.day,
    23,
    59,
    59,
  ).millisecondsSinceEpoch;
  final (store, _) = await makeStore(
    boards: [
      Board(id: 'b-1', name: 'Work', createdAt: 1000),
      Board(id: 'b-2', name: 'Home', createdAt: 1000),
    ],
    tasks: [
      Task(
        id: 'carry',
        boardId: 'b-1',
        title: 'Carried over',
        urgencyMode: UrgencyMode.manual,
        quadrant: qEliminate,
        createdAt: 1700000000000,
        deadline: plannedDayMs(now.subtract(const Duration(days: 2))),
      ),
      Task(
        id: 'plan',
        boardId: 'b-1',
        title: 'Planned today',
        quadrant: qPlan,
        createdAt: 1700000001000,
        // The near deadline would otherwise auto-promote this task out of Q2 on
        // load, which would test the urgency rule instead of the Today actions.
        urgencyMode: UrgencyMode.manual,
        plannedDate: planToday ? today : null,
        deadline: endOfToday,
        subtasks: [
          if (withStep) SubTask(id: 'step-1', title: 'Open the outline'),
        ],
      ),
      Task(
        id: 'due',
        boardId: 'b-2',
        title: 'Due elsewhere',
        quadrant: qDelegate,
        createdAt: 1700000002000,
        deadline: endOfToday,
      ),
      Task(
        id: 'upcoming',
        boardId: 'b-1',
        title: 'Planned later',
        quadrant: qPlan,
        createdAt: 1700000003000,
        plannedDate: plannedDayMs(now.add(const Duration(days: 3))),
      ),
    ],
  );
  if (planToday) {
    store.addScheduleItem(
      ScheduleItem.timeBlock(
        id: 'today-slot',
        taskId: 'plan',
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
  }
  return store;
}

Future<void> _pumpToday(
  WidgetTester tester,
  Store store, {
  Size size = const Size(1200, 900),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(_wrap(store, const TodayScreen()));
  await tester.pumpAndSettle();
}

Task _stored(Store store, String id) =>
    store.tasks.firstWhere((task) => task.id == id);

/// The Store owns a periodic timer, so it has to be released inside the test
/// body: a tear-down runs after the binding has already checked for pending
/// timers and reports that instead of the assertion under test.
Future<void> _finish(WidgetTester tester, Store store) async {
  await tester.pumpWidget(const SizedBox.shrink());
  store.dispose();
  await tester.pump();
}

void main() {
  testWidgets('Today lists each bucket with the row keeping its own quadrant', (
    tester,
  ) async {
    final store = await _seedStore();
    await _pumpToday(tester, store);

    expect(
      find.byKey(const ValueKey('today-section-carriedOver')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('today-section-scheduledToday')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('today-section-dueNow')), findsOneWidget);
    expect(find.byKey(const ValueKey('today-item-carry')), findsOneWidget);
    expect(find.byKey(const ValueKey('today-item-plan')), findsOneWidget);
    expect(find.byKey(const ValueKey('today-item-upcoming')), findsNothing);

    // The bucket is by day, so the row has to say where the task lives.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('today-item-carry')),
        matching: find.text('Neither Urgent nor Important'),
      ),
      findsOneWidget,
    );
    // The retired planned-day label is absent; exact deadlines remain visible.
    final row = find.byKey(const ValueKey('today-item-plan'));
    expect(
      find.descendant(of: row, matching: find.textContaining('Planned:')),
      findsNothing,
    );
    expect(
      find.descendant(of: row, matching: find.textContaining('Deadline:')),
      findsOneWidget,
    );
    await _finish(tester, store);
  });

  testWidgets('all-boards scope labels the foreign board and lists its task', (
    tester,
  ) async {
    final store = await _seedStore();
    await _pumpToday(tester, store);

    expect(find.byKey(const ValueKey('today-item-due')), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('today-item-plan')),
        matching: find.text('Work'),
      ),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('filter-open-btn')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('completed-scope-all')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('filter-apply-btn')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('today-item-due')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('today-item-due')),
        matching: find.text('Home'),
      ),
      findsOneWidget,
    );
    // With the scope widened, every row names its own board: the same task from
    // the active board is no longer assumed to be the one being read.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('today-item-plan')),
        matching: find.text('Work'),
      ),
      findsOneWidget,
    );
    await _finish(tester, store);
  });

  testWidgets('checking a Today row completes it without moving its quadrant', (
    tester,
  ) async {
    final store = await _seedStore();
    await _pumpToday(tester, store);

    await tester.tap(find.byKey(const ValueKey('today-check-plan')));
    await tester.pumpAndSettle();

    expect(_stored(store, 'plan').completed, isTrue);
    expect(_stored(store, 'plan').quadrant, qPlan);
    expect(find.byKey(const ValueKey('today-item-plan')), findsNothing);
    // Completing today's work is counted, not celebrated.
    expect(find.byKey(const ValueKey('today-summary')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('today-summary'))).data,
      contains('1 completed today'),
    );
    await _finish(tester, store);
  });

  testWidgets('the home More panel opens Today over the active board', (
    tester,
  ) async {
    final store = await _seedStore();
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_wrap(store, const MatrixHome()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('more-btn')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('today-btn')));
    await tester.pumpAndSettle();

    expect(find.byType(TodayScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('today-item-plan')), findsOneWidget);
    // The page reads the active board, so a task from the other board stays out.
    expect(find.byKey(const ValueKey('today-item-due')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('today-back-btn')));
    await tester.pumpAndSettle();
    expect(find.byType(TodayScreen), findsNothing);
    await _finish(tester, store);
  });

  testWidgets('an empty library says so instead of listing quadrants', (
    tester,
  ) async {
    final (store, _) = await makeStore(
      boards: [Board(id: 'b-1', name: 'Work', createdAt: 1000)],
    );
    await _pumpToday(tester, store);

    expect(find.text('Nothing for today'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('today-section-scheduledToday')),
      findsNothing,
    );
    await _finish(tester, store);
  });
}
