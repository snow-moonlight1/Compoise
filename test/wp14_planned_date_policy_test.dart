import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/calendar_dates.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/planned_policy.dart';
import 'package:matrixflow_native/storage.dart';

import 'helpers.dart';

/// WP14's contract: a plan is the day work is scheduled, a deadline is how late
/// it may slip. Only the deadline drives urgency.
Task _task({
  required String id,
  String boardId = 'b-1',
  int quadrant = qPlan,
  int? plannedDate,
  int? deadline,
  bool completed = false,
  int? completedAt,
  int createdAt = 1700000000000,
}) => Task(
  id: id,
  boardId: boardId,
  title: id,
  quadrant: quadrant,
  createdAt: createdAt,
  plannedDate: plannedDate,
  deadline: deadline,
  completed: completed,
  completedAt: completedAt,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // A Thursday, mid-morning: every bucket below is measured against it.
  final now = DateTime(2026, 3, 5, 9, 30);
  final mondayLastWeek = plannedDayMs(DateTime(2026, 3, 2))!;
  final yesterday = plannedDayMs(DateTime(2026, 3, 4))!;
  final today = plannedDayMs(now)!;
  final tomorrow = plannedDayMs(DateTime(2026, 3, 6))!;
  final endOfToday = DateTime(2026, 3, 5, 23, 59, 59).millisecondsSinceEpoch;

  group('WP14 planned day arithmetic', () {
    test('a plan is stored as the civil day, not the moment', () {
      expect(plannedDayMs(DateTime(2026, 3, 5, 21, 45)), today);
      expect(plannedDayMs(DateTime(2026, 3, 5)), today);
      expect(plannedDayMs(null), isNull);
    });

    test('plannedDaysLeft counts civil days, ignoring the clock', () {
      expect(plannedDaysLeft(today, now: now), 0);
      expect(plannedDaysLeft(today, now: DateTime(2026, 3, 5, 23, 59)), 0);
      expect(plannedDaysLeft(tomorrow, now: now), 1);
      expect(plannedDaysLeft(yesterday, now: now), -1);
      expect(plannedDaysLeft(null, now: now), isNull);
    });

    test('a plan stored at midnight and a deadline stored at day end agree', () {
      expect(plannedDaysLeft(endOfToday, now: now), 0);
    });
  });

  group('WP14 today bucket', () {
    test('nothing planned and nothing due stays off the Today list', () {
      expect(todaySectionOf(_task(id: 'plain'), now: now), isNull);
      expect(
        todaySectionOf(_task(id: 'future', deadline: tomorrow), now: now),
        isNull,
      );
    });

    test('a plan for today wins over an earlier or later deadline', () {
      expect(
        todaySectionOf(
          _task(id: 'p', plannedDate: today, deadline: mondayLastWeek),
          now: now,
        ),
        TodaySection.plannedToday,
      );
      expect(
        todaySectionOf(_task(id: 'p', plannedDate: today, deadline: tomorrow), now: now),
        TodaySection.plannedToday,
      );
    });

    test('an earlier plan carries over', () {
      expect(
        todaySectionOf(_task(id: 'p', plannedDate: yesterday), now: now),
        TodaySection.carriedOver,
      );
    });

    test('a later plan does not appear until its deadline arrives', () {
      expect(
        todaySectionOf(_task(id: 'p', plannedDate: tomorrow), now: now),
        isNull,
      );
      expect(
        todaySectionOf(
          _task(id: 'p', plannedDate: tomorrow, deadline: today),
          now: now,
        ),
        TodaySection.dueNow,
      );
    });

    test('an overdue deadline is listed even without a plan', () {
      expect(
        todaySectionOf(
          _task(id: 'p', deadline: mondayLastWeek),
          now: now,
        ),
        TodaySection.dueNow,
      );
      expect(
        todaySectionOf(_task(id: 'p', deadline: today), now: now),
        TodaySection.dueNow,
      );
    });

    test('a completed task is never listed, planned or not', () {
      expect(
        todaySectionOf(
          _task(id: 'p', plannedDate: today, completed: true, completedAt: now.millisecondsSinceEpoch),
          now: now,
        ),
        isNull,
      );
    });

    test('completedOnDay only matches the same civil day', () {
      final done = _task(
        id: 'd',
        completed: true,
        completedAt: DateTime(2026, 3, 5, 22, 5).millisecondsSinceEpoch,
      );
      expect(completedOnDay(done, now: now), isTrue);
      expect(completedOnDay(done, now: DateTime(2026, 3, 6, 8)), isFalse);
      expect(completedOnDay(_task(id: 'open'), now: now), isFalse);
    });
  });

  group('WP14 today grouping', () {
    test('buckets come back in section order with empty ones dropped', () {
      final groups = groupForToday([
        _task(id: 'due', deadline: today),
        _task(id: 'late', plannedDate: mondayLastWeek),
        _task(id: 'plan', plannedDate: today),
        _task(id: 'later', plannedDate: tomorrow),
      ], now: now);

      expect(groups.map((g) => g.section), [
        TodaySection.carriedOver,
        TodaySection.plannedToday,
        TodaySection.dueNow,
      ]);
      expect(groups.singleWhere((g) => g.section == TodaySection.dueNow).tasks.single.id, 'due');
    });

    test('one bucket mixes quadrants instead of splitting by them', () {
      final groups = groupForToday([
        _task(id: 'q1', quadrant: qDo, plannedDate: today),
        _task(id: 'q2', quadrant: qPlan, plannedDate: today),
        _task(id: 'q3', quadrant: qDelegate, plannedDate: today),
        _task(id: 'q4', quadrant: qEliminate, plannedDate: today),
      ], now: now);

      expect(groups, hasLength(1));
      expect(
        groups.single.tasks.map((task) => task.quadrant).toSet(),
        allQuadrants.toSet(),
      );
    });

    test('within a bucket the nearest deadline leads, then the plan', () {
      final groups = groupForToday([
        _task(id: 'no-date', plannedDate: today),
        _task(id: 'due-later', plannedDate: today, deadline: tomorrow),
        _task(id: 'due-now', plannedDate: today, deadline: today),
      ], now: now);

      expect(groups.single.tasks.map((task) => task.id), [
        'due-now',
        'due-later',
        'no-date',
      ]);
    });
  });

  group('WP14 store today API', () {
    // These go through the real clock: the store reads today when asked.
    final realNow = DateTime.now();
    final realToday = plannedDayMs(realNow)!;
    final realTomorrowDay = addCivilDays(realNow, 1);
    final realTomorrow = plannedDayMs(realTomorrowDay)!;

    Future<Store> seeded({bool planToday = true}) async {
      final (store, _) = await makeStore(
        boards: [
          Board(id: 'b-1', name: 'Work', createdAt: 1000),
          Board(id: 'b-2', name: 'Home', createdAt: 1000),
        ],
        tasks: [
          _task(
            id: 'here',
            plannedDate: planToday ? realToday : null,
            createdAt: 1700000000000,
          ),
          _task(
            id: 'there',
            boardId: 'b-2',
            quadrant: qDelegate,
            plannedDate: planToday ? realToday : null,
            createdAt: 1700000001000,
          ),
          _task(
            id: 'done',
            plannedDate: planToday ? realToday : null,
            completed: true,
            completedAt: realNow.millisecondsSinceEpoch,
            createdAt: 1700000002000,
          ),
        ],
      );
      return store;
    }

    Task stored(Store store, String id) =>
        store.tasks.firstWhere((task) => task.id == id);

    List<String> listed(Store store, {bool allBoards = false}) => [
      for (final group in store.todayGroups(allBoards: allBoards))
        for (final task in group.tasks) task.id,
    ];

    test('the default scope is the active board', () async {
      final store = await seeded();
      addTearDown(store.dispose);

      expect(store.activeBoardId, 'b-1');
      expect(listed(store), ['here']);
    });

    test('all-boards scope gathers across quadrants and boards', () async {
      final store = await seeded();
      addTearDown(store.dispose);

      final groups = store.todayGroups(allBoards: true);
      expect(groups, hasLength(1));
      expect(groups.single.section, TodaySection.plannedToday);
      expect(groups.single.tasks.map((task) => task.id), ['here', 'there']);
      expect(
        groups.single.tasks.map((task) => task.quadrant).toSet(),
        {qPlan, qDelegate},
      );
    });

    test('hideCompleted does not decide the Today list', () async {
      final store = await seeded();
      addTearDown(store.dispose);

      for (final hide in [false, true]) {
        store.updateSettings((s) => s..hideCompleted = hide);
        expect(listed(store, allBoards: true), ['here', 'there']);
      }
    });

    test('an unplanned library lists nothing but still counts the day', () async {
      final store = await seeded(planToday: false);
      addTearDown(store.dispose);

      expect(store.todayGroups(allBoards: true), isEmpty);
      expect(store.completedTodayCount(allBoards: true), 1);
      expect(store.completedTodayCount(), 1);
    });

    test('planning a task moves no quadrant and touches no deadline', () async {
      final store = await seeded(planToday: false);
      addTearDown(store.dispose);
      expect(stored(store, 'here').quadrant, qPlan);

      store.setPlannedDay('here', DateTime.now().add(const Duration(hours: 9)));
      final after = stored(store, 'here');
      expect(after.plannedDate, realToday);
      expect(after.quadrant, qPlan);
      expect(after.urgencyMode, UrgencyMode.auto);
      expect(after.deadline, isNull);
      expect(listed(store), ['here']);
    });

    test('re-applying the same plan is not a mutation', () async {
      final store = await seeded();
      addTearDown(store.dispose);
      final revision = store.taskSeq('here');

      store.setPlannedDay('here', DateTime.now());
      expect(store.taskSeq('here'), revision);

      store.setPlannedDay('here', null);
      expect(store.taskSeq('here'), greaterThan(revision));
      expect(stored(store, 'here').plannedDate, isNull);
    });

    test('a plan never promotes, a reached deadline still does', () async {
      final store = await seeded(planToday: false);
      addTearDown(store.dispose);

      store.setPlannedDay('here', realNow);
      store.promoteDeadlinesNow(now: realNow);
      expect(
        stored(store, 'here').quadrant,
        qPlan,
        reason: 'a plan alone is not urgency',
      );

      store.setPlannedDay('here', realTomorrowDay);
      store.updateTask(
        Task.fromJson(stored(store, 'here').toJson())
          ..deadline = DateTime(
            realNow.year,
            realNow.month,
            realNow.day,
            23,
            59,
            59,
          ).millisecondsSinceEpoch,
      );
      store.promoteDeadlinesNow(now: realNow);
      expect(stored(store, 'here').quadrant, qDo);
    });

    test('newTask carries a planned day into the library', () async {
      final store = await seeded(planToday: false);
      addTearDown(store.dispose);

      store.addTasks([store.newTask('tomorrow', plannedDate: realTomorrow)]);
      final added = store.tasks.firstWhere((task) => task.title == 'tomorrow');
      expect(added.plannedDate, realTomorrow);
      expect(added.boardId, 'b-1');
      expect(listed(store, allBoards: true), isEmpty);
    });
  });
}
