import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/calendar_dates.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/planned_policy.dart';
import 'package:matrixflow_native/screens/today_screen.dart';
import 'package:matrixflow_native/storage.dart';
import 'package:matrixflow_native/today_celebration.dart';
import 'package:matrixflow_native/ui/motion_policy.dart';
import 'package:provider/provider.dart';

import 'helpers.dart';

/// WP16: the Today page celebrates only when the user completes tasks there
/// and that clears a list which actually had open rows. Passive empties must
/// not celebrate and must not consume the day's one celebration.
Widget _wrap(Store store, Widget home, {bool disableAnimations = false}) =>
    ChangeNotifierProvider.value(
      value: store,
      child: MaterialApp(
        theme: ThemeData(useMaterial3: true, platform: TargetPlatform.windows),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('en'), Locale('zh'), Locale('ja')],
        builder: disableAnimations
            ? (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(disableAnimations: true),
                child: child ?? const SizedBox.shrink(),
              )
            : null,
        home: home,
      ),
    );

int _midnight() => plannedDayMs(DateTime.now())!;

int _endOfToday() {
  final now = DateTime.now();
  return DateTime(
    now.year,
    now.month,
    now.day,
    23,
    59,
    59,
  ).millisecondsSinceEpoch;
}

List<Board> _boards() => [
  Board(id: 'b-1', name: 'Work', createdAt: 1000),
  Board(id: 'b-2', name: 'Home', createdAt: 1000),
];

Task _task({
  required String id,
  String boardId = 'b-1',
  String title = 'Write the note',
  int quadrant = qPlan,
  bool planToday = true,
  int? plannedDate,
  int? deadline,
  List<SubTask>? subtasks,
}) => Task(
  id: id,
  boardId: boardId,
  title: title,
  quadrant: quadrant,
  createdAt: 1700000000000,
  urgencyMode: UrgencyMode.manual,
  plannedDate: planToday ? _midnight() : plannedDate,
  deadline: deadline,
  subtasks: subtasks ?? [],
);

Future<Store> _seed(List<Task> tasks, {AppSettings? settings}) async {
  final (store, _) = await makeStore(
    settings: settings,
    boards: _boards(),
    tasks: tasks,
  );
  return store;
}

Future<void> _pump(
  WidgetTester tester,
  Store store, {
  Size size = const Size(1200, 900),
  bool disableAnimations = false,
  Widget? home,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    _wrap(
      store,
      home ?? const TodayScreen(),
      disableAnimations: disableAnimations,
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _finish(WidgetTester tester, Store store) async {
  await tester.pumpWidget(const SizedBox.shrink());
  store.dispose();
  await tester.pump();
}

Finder get _celebration => find.byKey(const ValueKey('today-celebration'));
Finder get _static => find.byKey(const ValueKey('today-celebration-static'));
Finder get _motion => find.byKey(const ValueKey('today-celebration-motion'));
Finder get _close => find.byKey(const ValueKey('today-celebration-close'));

Future<void> _check(WidgetTester tester, String id) async {
  await tester.tap(find.byKey(ValueKey('today-check-$id')));
  await tester.pumpAndSettle();
}

void _expectLatchClear(Store store) {
  expect(store.todayCelebration.celebratedDayMs, isNull);
}

void _expectFields(
  Task task, {
  required int quadrant,
  int? planned,
  int? deadline,
}) {
  expect(task.quadrant, quadrant);
  expect(task.plannedDate, planned);
  expect(task.deadline, deadline);
}

Future<void> _applyScope(WidgetTester tester, {required bool allBoards}) async {
  await tester.tap(find.byKey(const ValueKey('filter-open-btn')));
  await tester.pumpAndSettle();
  await tester.tap(
    find.byKey(
      ValueKey(allBoards ? 'completed-scope-all' : 'completed-scope-current'),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('filter-apply-btn')));
  await tester.pumpAndSettle();
}

void main() {
  group('TodayCelebrationMemory', () {
    TodayCelebrationMemory memory() =>
        TodayCelebrationMemory(clock: () => DateTime(2031, 6, 1, 9));

    bool clear(
      TodayCelebrationMemory gate, {
      bool scopeUnchanged = true,
      int openBefore = 1,
      int openAfter = 0,
      Set<String> removedIds = const {'a'},
      bool Function(String id)? isCompleted,
    }) => gate.consider(
      scopeUnchanged: scopeUnchanged,
      openBefore: openBefore,
      openAfter: openAfter,
      removedIds: removedIds,
      isCompleted: isCompleted ?? (_) => true,
    );

    test(
      'a non-empty list clearing by completion celebrates once that day',
      () {
        final gate = memory();
        expect(clear(gate, openBefore: 2, removedIds: {'a', 'b'}), isTrue);
        final day = gate.celebratedDayMs;
        expect(day, civilDate(DateTime(2031, 6, 1)).millisecondsSinceEpoch);
        expect(clear(gate, removedIds: {'c'}), isFalse);
        expect(gate.celebratedDayMs, day);

        gate.clock = () => DateTime(2031, 6, 1, 23, 30);
        expect(clear(gate, removedIds: {'d'}), isFalse);

        gate.clock = () => DateTime(2031, 6, 2, 0, 30);
        expect(clear(gate, removedIds: {'e'}), isTrue);
        expect(
          isSameCivilDay(
            DateTime.fromMillisecondsSinceEpoch(gate.celebratedDayMs!),
            DateTime(2031, 6, 2),
          ),
          isTrue,
        );
      },
    );

    test(
      'passive and partial transitions do not celebrate or consume the day',
      () {
        final gate = memory();
        expect(clear(gate, scopeUnchanged: false), isFalse);
        expect(
          clear(gate, openBefore: 0, openAfter: 0, removedIds: {}),
          isFalse,
        );
        expect(
          clear(gate, openBefore: 2, openAfter: 1, removedIds: {'a'}),
          isFalse,
        );
        expect(
          clear(gate, openBefore: 2, openAfter: 0, removedIds: {'a'}),
          isFalse,
        );
        expect(
          clear(
            gate,
            openBefore: 2,
            removedIds: {'a', 'b'},
            isCompleted: (id) => id == 'a',
          ),
          isFalse,
        );
        expect(clear(gate, isCompleted: (_) => false), isFalse);
        expect(gate.celebratedDayMs, isNull);
        expect(clear(gate), isTrue);
      },
    );

    test('the latch is not a persisted settings field', () {
      final keys = AppSettings().toJson().keys.toSet();
      expect(keys, isNot(contains('todayCelebration')));
      expect(keys, isNot(contains('celebratedDayMs')));
      expect(AppSettings.fromJson({}).toJson().keys.toSet(), keys);
      expect(MotionPolicy.celebration, const Duration(milliseconds: 280));
    });
  });

  testWidgets('completing the last open Today row celebrates once', (
    tester,
  ) async {
    final planned = _midnight();
    final deadline = _endOfToday();
    final store = await _seed([
      _task(
        id: 'only',
        deadline: deadline,
        subtasks: [SubTask(id: 'step', title: 'Open the outline')],
      ),
    ]);
    final settingsBefore = store.settings.toJson();
    try {
      await _pump(tester, store);
      expect(_celebration, findsNothing);

      await _check(tester, 'only');

      expect(_celebration, findsOneWidget);
      expect(find.text('Today is clear'), findsOneWidget);
      expect(
        find.text('Every open task in this view is done.'),
        findsOneWidget,
      );
      expect(_close, findsOneWidget);
      final task = store.tasks.firstWhere((item) => item.id == 'only');
      expect(task.completed, isTrue);
      expect(task.subtasks.single.completed, isTrue);
      _expectFields(
        task,
        quadrant: qPlan,
        planned: planned,
        deadline: deadline,
      );
      expect(store.settings.toJson(), settingsBefore);
      expect(
        isSameCivilDay(
          DateTime.fromMillisecondsSinceEpoch(
            store.todayCelebration.celebratedDayMs!,
          ),
          DateTime.now(),
        ),
        isTrue,
      );
    } finally {
      await _finish(tester, store);
    }
  });

  testWidgets('one remaining open row does not celebrate; the last one does', (
    tester,
  ) async {
    final store = await _seed([
      _task(id: 'first', title: 'First', quadrant: qDo),
      _task(id: 'second', title: 'Second', quadrant: qDelegate),
    ]);
    try {
      await _pump(tester, store);
      await _check(tester, 'first');
      expect(_celebration, findsNothing);
      _expectLatchClear(store);
      expect(find.byKey(const ValueKey('today-item-second')), findsOneWidget);

      await _check(tester, 'second');
      expect(_celebration, findsOneWidget);
      _expectFields(
        store.tasks.firstWhere((task) => task.id == 'first'),
        quadrant: qDo,
        planned: _midnight(),
      );
      _expectFields(
        store.tasks.firstWhere((task) => task.id == 'second'),
        quadrant: qDelegate,
        planned: _midnight(),
      );
    } finally {
      await _finish(tester, store);
    }
  });

  testWidgets('current-board scope ignores open rows on other boards', (
    tester,
  ) async {
    final store = await _seed([
      _task(id: 'here', title: 'Here'),
      _task(id: 'there', title: 'There', boardId: 'b-2', quadrant: qDo),
    ]);
    try {
      await _pump(tester, store);
      await _check(tester, 'here');
      expect(_celebration, findsOneWidget);
      expect(
        store.tasks.firstWhere((task) => task.id == 'there').completed,
        isFalse,
      );
      _expectFields(
        store.tasks.firstWhere((task) => task.id == 'there'),
        quadrant: qDo,
        planned: _midnight(),
      );
    } finally {
      await _finish(tester, store);
    }
  });

  testWidgets('all-boards scope celebrates only when every open row is done', (
    tester,
  ) async {
    final store = await _seed([
      _task(id: 'here', title: 'Here'),
      _task(id: 'there', title: 'There', boardId: 'b-2', quadrant: qDo),
    ]);
    try {
      await _pump(tester, store);
      await _applyScope(tester, allBoards: true);
      expect(_celebration, findsNothing);
      _expectLatchClear(store);

      await _check(tester, 'here');
      expect(_celebration, findsNothing);
      _expectLatchClear(store);
      expect(find.byKey(const ValueKey('today-item-there')), findsOneWidget);

      await _check(tester, 'there');
      expect(_celebration, findsOneWidget);
    } finally {
      await _finish(tester, store);
    }
  });

  testWidgets(
    'opening an empty Today list does not celebrate or consume the day',
    (tester) async {
      final store = await _seed([
        _task(
          id: 'later',
          title: 'Later',
          planToday: false,
          plannedDate: plannedDayMs(
            DateTime.now().add(const Duration(days: 3)),
          ),
        ),
      ]);
      try {
        await _pump(tester, store);
        expect(find.text('Nothing is planned for today'), findsOneWidget);
        expect(_celebration, findsNothing);
        _expectLatchClear(store);

        final added = store.newTask(
          'Added',
          quadrant: qDo,
          plannedDate: _midnight(),
        );
        store.addTasks([added]);
        await tester.pumpAndSettle();
        expect(_celebration, findsNothing);
        _expectLatchClear(store);

        await _check(tester, added.id);
        expect(_celebration, findsOneWidget);
      } finally {
        await _finish(tester, store);
      }
    },
  );

  testWidgets(
    'tasks completed before Today opens do not celebrate on arrival',
    (tester) async {
      final store = await _seed([_task(id: 'only')]);
      store.setParentCompleted(store.tasks.single, true);
      try {
        await _pump(tester, store);
        expect(find.text('Nothing is planned for today'), findsOneWidget);
        expect(_celebration, findsNothing);
        _expectLatchClear(store);
      } finally {
        await _finish(tester, store);
      }
    },
  );

  testWidgets('switching the board filter does not celebrate', (tester) async {
    final store = await _seed([
      _task(
        id: 'later',
        title: 'Later',
        planToday: false,
        plannedDate: plannedDayMs(DateTime.now().add(const Duration(days: 2))),
      ),
      _task(id: 'home', title: 'Home row', boardId: 'b-2', quadrant: qDo),
    ]);
    try {
      await _pump(tester, store);
      expect(_celebration, findsNothing);

      await _applyScope(tester, allBoards: true);
      expect(find.byKey(const ValueKey('today-item-home')), findsOneWidget);
      expect(_celebration, findsNothing);

      await _applyScope(tester, allBoards: false);
      expect(find.byKey(const ValueKey('today-item-home')), findsNothing);
      expect(_celebration, findsNothing);
      _expectLatchClear(store);

      await _applyScope(tester, allBoards: true);
      await _check(tester, 'home');
      expect(_celebration, findsOneWidget);
    } finally {
      await _finish(tester, store);
    }
  });

  testWidgets('switching the active board does not celebrate', (tester) async {
    final store = await _seed([_task(id: 'only')]);
    try {
      await _pump(tester, store);
      store.setActiveBoard('b-2');
      await tester.pumpAndSettle();
      expect(find.text('Nothing is planned for today'), findsOneWidget);
      expect(_celebration, findsNothing);
      _expectLatchClear(store);

      store.setActiveBoard('b-1');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('today-item-only')), findsOneWidget);
      expect(_celebration, findsNothing);

      await _check(tester, 'only');
      expect(_celebration, findsOneWidget);
      _expectFields(
        store.tasks.firstWhere((task) => task.id == 'only'),
        quadrant: qPlan,
        planned: _midnight(),
      );
    } finally {
      await _finish(tester, store);
    }
  });

  testWidgets('clearing a plan that empties Today does not celebrate', (
    tester,
  ) async {
    final store = await _seed([_task(id: 'only', quadrant: qEliminate)]);
    try {
      await _pump(tester, store);
      await tester.tap(find.byKey(const ValueKey('today-menu-only')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear plan'));
      await tester.pumpAndSettle();

      expect(find.text('Nothing is planned for today'), findsOneWidget);
      expect(_celebration, findsNothing);
      _expectLatchClear(store);
      final cleared = store.tasks.single;
      expect(cleared.completed, isFalse);
      _expectFields(cleared, quadrant: qEliminate, planned: null);

      final added = store.newTask('Replacement', plannedDate: _midnight());
      store.addTasks([added]);
      await tester.pumpAndSettle();
      await _check(tester, added.id);
      expect(_celebration, findsOneWidget);
    } finally {
      await _finish(tester, store);
    }
  });

  testWidgets('moving a deadline off Today does not celebrate', (tester) async {
    final deadline = _endOfToday();
    final store = await _seed([
      _task(
        id: 'only',
        planToday: false,
        deadline: deadline,
        quadrant: qDelegate,
      ),
    ]);
    try {
      await _pump(tester, store);
      final live = store.tasks.single;
      store.updateTask(
        Task.fromJson(live.toJson())
          ..deadline = DateTime.now()
              .add(const Duration(days: 40))
              .millisecondsSinceEpoch,
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('today-item-only')), findsNothing);
      expect(_celebration, findsNothing);
      _expectLatchClear(store);
      expect(store.tasks.single.quadrant, qDelegate);
      expect(store.tasks.single.plannedDate, isNull);
      expect(store.tasks.single.completed, isFalse);
    } finally {
      await _finish(tester, store);
    }
  });

  testWidgets('deleting the last Today row does not celebrate', (tester) async {
    final store = await _seed([_task(id: 'only')]);
    try {
      await _pump(tester, store);
      store.deleteTaskWithUndo('only');
      await tester.pumpAndSettle();
      expect(find.text('Nothing is planned for today'), findsOneWidget);
      expect(_celebration, findsNothing);
      _expectLatchClear(store);
    } finally {
      await _finish(tester, store);
    }
  });

  testWidgets('completing a task that is not on Today does not celebrate', (
    tester,
  ) async {
    final store = await _seed([
      _task(id: 'only'),
      _task(
        id: 'later',
        title: 'Later',
        planToday: false,
        plannedDate: plannedDayMs(DateTime.now().add(const Duration(days: 5))),
        quadrant: qDo,
      ),
    ]);
    try {
      await _pump(tester, store);
      final later = store.tasks.firstWhere((task) => task.id == 'later');
      final laterPlan = later.plannedDate;
      store.setParentCompleted(later, true);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('today-item-only')), findsOneWidget);
      expect(_celebration, findsNothing);
      _expectLatchClear(store);
      _expectFields(later, quadrant: qDo, planned: laterPlan);

      await _check(tester, 'only');
      expect(_celebration, findsOneWidget);
    } finally {
      await _finish(tester, store);
    }
  });

  testWidgets('a cross-day refresh does not celebrate', (tester) async {
    final store = await _seed([_task(id: 'only', deadline: _endOfToday())]);
    try {
      await _pump(tester, store);
      store.promoteDeadlinesNow();
      store.didChangeAppLifecycleState(AppLifecycleState.resumed);
      store.notifyListeners();
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('today-item-only')), findsOneWidget);
      expect(_celebration, findsNothing);
      _expectLatchClear(store);
      _expectFields(
        store.tasks.single,
        quadrant: qPlan,
        planned: _midnight(),
        deadline: _endOfToday(),
      );

      await _check(tester, 'only');
      expect(_celebration, findsOneWidget);
    } finally {
      await _finish(tester, store);
    }
  });

  testWidgets('an already empty Today list stays quiet across a refresh', (
    tester,
  ) async {
    final store = await _seed(const <Task>[]);
    try {
      await _pump(tester, store);
      store.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(_celebration, findsNothing);
      _expectLatchClear(store);
    } finally {
      await _finish(tester, store);
    }
  });

  testWidgets('close is explicit and a second clear the same day stays quiet', (
    tester,
  ) async {
    final store = await _seed([_task(id: 'only')]);
    try {
      await _pump(tester, store);
      await _check(tester, 'only');
      expect(_celebration, findsOneWidget);

      await tester.pump(const Duration(seconds: 3));
      expect(_celebration, findsOneWidget);
      expect(_close, findsOneWidget);

      await tester.tap(_close);
      await tester.pumpAndSettle();
      expect(_celebration, findsNothing);
      expect(store.todayCelebration.celebratedDayMs, isNotNull);

      final added = store.newTask('Another', plannedDate: _midnight());
      store.addTasks([added]);
      await tester.pumpAndSettle();
      expect(_celebration, findsNothing);
      await _check(tester, added.id);
      expect(_celebration, findsNothing);
    } finally {
      await _finish(tester, store);
    }
  });

  testWidgets('leaving Today and coming back keeps the same-day latch', (
    tester,
  ) async {
    final store = await _seed([_task(id: 'only')]);
    try {
      await _pump(tester, store);
      await _check(tester, 'only');
      await tester.tap(_close);
      await tester.pumpAndSettle();

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(_wrap(store, const TodayScreen()));
      await tester.pumpAndSettle();
      expect(_celebration, findsNothing);

      final added = store.newTask('After return', plannedDate: _midnight());
      store.addTasks([added]);
      await tester.pumpAndSettle();
      await _check(tester, added.id);
      expect(_celebration, findsNothing);
    } finally {
      await _finish(tester, store);
    }
  });

  testWidgets('the next civil day can celebrate again', (tester) async {
    final store = await _seed([_task(id: 'only')]);
    store.todayCelebration.clock = () => DateTime(2031, 6, 1, 12);
    try {
      await _pump(tester, store);
      await _check(tester, 'only');
      expect(_celebration, findsOneWidget);
      await tester.tap(_close);
      await tester.pumpAndSettle();

      store.todayCelebration.clock = () => DateTime(2031, 6, 1, 23);
      final sameDay = store.newTask('Same day', plannedDate: _midnight());
      store.addTasks([sameDay]);
      await tester.pumpAndSettle();
      await _check(tester, sameDay.id);
      expect(_celebration, findsNothing);

      store.todayCelebration.clock = () => DateTime(2031, 6, 2, 8);
      final nextDay = store.newTask('Next day', plannedDate: _midnight());
      store.addTasks([nextDay]);
      await tester.pumpAndSettle();
      await _check(tester, nextDay.id);
      expect(_celebration, findsOneWidget);
      expect(
        isSameCivilDay(
          DateTime.fromMillisecondsSinceEpoch(
            store.todayCelebration.celebratedDayMs!,
          ),
          DateTime(2031, 6, 2),
        ),
        isTrue,
      );
    } finally {
      await _finish(tester, store);
    }
  });

  testWidgets('app reduce-motion shows the settled card immediately', (
    tester,
  ) async {
    final store = await _seed([
      _task(id: 'only'),
    ], settings: AppSettings()..reduceMotion = true);
    try {
      await _pump(tester, store);
      await tester.tap(find.byKey(const ValueKey('today-check-only')));
      await tester.pump();

      expect(_celebration, findsOneWidget);
      expect(_static, findsOneWidget);
      expect(_motion, findsNothing);
      expect(_close, findsOneWidget);
      expect(find.text('Close'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 400));
      expect(_static, findsOneWidget);
      expect(_motion, findsNothing);
      await tester.tap(_close);
      await tester.pump();
      expect(_celebration, findsNothing);
    } finally {
      await _finish(tester, store);
    }
  });

  testWidgets('system reduce-motion shows the settled card immediately', (
    tester,
  ) async {
    final store = await _seed([_task(id: 'only')]);
    expect(store.settings.reduceMotion, isFalse);
    try {
      await _pump(tester, store, disableAnimations: true);
      await tester.tap(find.byKey(const ValueKey('today-check-only')));
      await tester.pump();

      expect(_static, findsOneWidget);
      expect(_motion, findsNothing);
      expect(_close, findsOneWidget);
      expect(store.settings.reduceMotion, isFalse);
    } finally {
      await _finish(tester, store);
    }
  });

  testWidgets('with motion on, the card fades in and then holds', (
    tester,
  ) async {
    final store = await _seed([_task(id: 'only')]);
    try {
      await _pump(tester, store);
      await tester.tap(find.byKey(const ValueKey('today-check-only')));
      await tester.pump();

      expect(_motion, findsOneWidget);
      expect(_static, findsNothing);
      // The fade is mounted at rest. The pump that built it does not also
      // advance the new ticker, so the first frame is fully transparent.
      expect(tester.widget<FadeTransition>(_motion).opacity.value, 0);

      await tester.pump(const Duration(milliseconds: 80));
      final mid = tester.widget<FadeTransition>(_motion).opacity.value;
      expect(mid, greaterThan(0));
      expect(mid, lessThan(1));

      await tester.pump(MotionPolicy.celebration);
      expect(tester.widget<FadeTransition>(_motion).opacity.value, 1);
      expect(_close, findsOneWidget);
    } finally {
      await _finish(tester, store);
    }
  });

  testWidgets(
    'saving a subtask does not celebrate until the parent is completed',
    (tester) async {
      final planned = _midnight();
      final store = await _seed([
        _task(
          id: 'only',
          subtasks: [SubTask(id: 'step', title: 'Draft')],
        ),
      ]);
      try {
        await _pump(tester, store);
        await tester.tap(find.byKey(const ValueKey('today-item-only')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('detail-subtask-check-step')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('save-task')));
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('today-item-only')), findsOneWidget);
        expect(_celebration, findsNothing);
        _expectLatchClear(store);
        final parent = store.tasks.single;
        expect(parent.completed, isFalse);
        expect(parent.subtasks.single.completed, isTrue);
        _expectFields(parent, quadrant: qPlan, planned: planned);

        await _check(tester, 'only');
        expect(_celebration, findsOneWidget);
      } finally {
        await _finish(tester, store);
      }
    },
  );

  testWidgets('auto-completing the last parent from Today detail celebrates', (
    tester,
  ) async {
    final planned = _midnight();
    final deadline = _endOfToday();
    final store = await _seed([
      _task(
        id: 'only',
        deadline: deadline,
        subtasks: [SubTask(id: 'step', title: 'Draft')],
      ),
    ], settings: AppSettings()..autoCompleteParent = true);
    try {
      await _pump(tester, store);
      await tester.tap(find.byKey(const ValueKey('today-item-only')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('detail-subtask-check-step')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('save-task')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('today-item-only')), findsNothing);
      expect(_celebration, findsOneWidget);
      final parent = store.tasks.single;
      expect(parent.completed, isTrue);
      _expectFields(
        parent,
        quadrant: qPlan,
        planned: planned,
        deadline: deadline,
      );
    } finally {
      await _finish(tester, store);
    }
  });

  testWidgets('the close action stays reachable in a narrow window', (
    tester,
  ) async {
    final store = await _seed([_task(id: 'only')]);
    try {
      await _pump(tester, store, size: const Size(390, 844));
      await _check(tester, 'only');
      expect(tester.takeException(), isNull);
      expect(_close, findsOneWidget);
      await tester.tap(_close);
      await tester.pumpAndSettle();
      expect(_celebration, findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      await _finish(tester, store);
    }
  });
}
