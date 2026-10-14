import 'package:compoise/models.dart';
import 'package:compoise/planned_policy.dart';
import 'package:compoise/schedule_item.dart';
import 'package:compoise/storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final today = DateTime(2026, 10, 14);
  final tomorrow = DateTime(2026, 10, 15);
  ScheduleItem block(String id, String taskId, DateTime start, DateTime end) =>
      ScheduleItem.timeBlock(
        id: id,
        taskId: taskId,
        startAt: start.millisecondsSinceEpoch,
        endAt: end.millisecondsSinceEpoch,
        timeZoneId: 'Asia/Shanghai',
      );
  List<String> listed(Store store, {bool allBoards = false}) => [
    for (final group in store.todayGroups(now: today, allBoards: allBoards))
      for (final task in group.tasks) task.id,
  ];

  test(
    'Today includes linked schedules once, without rewriting task dates',
    () async {
      final (store, _) = await makeStore();
      addTearDown(store.dispose);
      final task = store.newTask('Scheduled only', quadrant: qPlan);
      task.plannedDate = plannedDayMs(DateTime(2026, 10, 13));
      store.addTasks([task]);
      final before = store.tasks.single.toJson();
      store.addScheduleItem(
        block(
          'a',
          task.id,
          today.add(const Duration(hours: 9)),
          today.add(const Duration(hours: 10)),
        ),
      );
      store.addScheduleItem(
        block(
          'b',
          task.id,
          today.add(const Duration(hours: 11)),
          today.add(const Duration(hours: 12)),
        ),
      );
      expect(listed(store), [task.id]);
      expect(
        store.todayGroups(now: today).single.section,
        TodaySection.plannedToday,
      );
      expect(store.tasks.single.toJson(), before);
      store.deleteScheduleItem(
        'a',
        expectedRevision: store.scheduleRevision('a'),
      );
      expect(listed(store), [task.id]);
      store.deleteScheduleItem(
        'b',
        expectedRevision: store.scheduleRevision('b'),
      );
      expect(
        store.todayGroups(now: today).single.section,
        TodaySection.carriedOver,
      );
    },
  );

  test('local day overlap excludes midnight endings and future blocks', () async {
    final (store, _) = await makeStore();
    addTearDown(store.dispose);
    final titles = ['crossing', 'ending', 'future', 'full-day', 'completed'];
    final tasks = [for (final title in titles) store.newTask(title)];
    tasks.last.completed = true;
    store.addTasks(tasks);
    store.addScheduleItem(
      block(
        'cross',
        tasks[0].id,
        today.subtract(const Duration(hours: 1)),
        today.add(const Duration(hours: 1)),
      ),
    );
    store.addScheduleItem(
      block(
        'end',
        tasks[1].id,
        today.subtract(const Duration(hours: 1)),
        today,
      ),
    );
    store.addScheduleItem(
      block(
        'future',
        tasks[2].id,
        tomorrow,
        tomorrow.add(const Duration(hours: 1)),
      ),
    );
    store.addScheduleItem(block('day', tasks[3].id, today, tomorrow));
    store.addScheduleItem(block('done', tasks[4].id, today, tomorrow));
    expect(listed(store).toSet(), {tasks[0].id, tasks[3].id});
    // The record's creation zone does not determine its day in the device zone.
    expect(
      store
          .todayGroups(now: today.toUtc())
          .expand((g) => g.tasks)
          .map((t) => t.id)
          .toSet(),
      {tasks[0].id, tasks[3].id},
    );
  });

  test(
    'linked events follow board scope and moving or deleting updates Today',
    () async {
      final (store, _) = await makeStore(
        boards: [
          Board(id: 'a', name: 'Work', createdAt: 1),
          Board(id: 'b', name: 'Home', createdAt: 2),
        ],
      );
      addTearDown(store.dispose);
      final task = store.newTask('Linked event')..boardId = 'b';
      store.addTasks([task]);
      ScheduleItem event(DateTime day) => ScheduleItem.event(
        id: 'linked',
        title: 'Meeting',
        taskId: task.id,
        startAt: day.millisecondsSinceEpoch,
        endAt: day.add(const Duration(hours: 1)).millisecondsSinceEpoch,
        timeZoneId: 'Etc/UTC',
      );
      store.addScheduleItem(event(today));
      store.addScheduleItem(
        ScheduleItem.event(
          id: 'standalone',
          title: 'Appointment',
          boardId: 'a',
          startAt: today.millisecondsSinceEpoch,
          endAt: tomorrow.millisecondsSinceEpoch,
          timeZoneId: 'Etc/UTC',
        ),
      );
      expect(listed(store), isEmpty);
      expect(listed(store, allBoards: true), [task.id]);
      store.updateScheduleItem(
        event(tomorrow),
        expectedRevision: store.scheduleRevision('linked'),
      );
      expect(listed(store, allBoards: true), isEmpty);
      store.updateScheduleItem(
        event(today),
        expectedRevision: store.scheduleRevision('linked'),
      );
      expect(listed(store, allBoards: true), [task.id]);
      store.deleteScheduleItem(
        'linked',
        expectedRevision: store.scheduleRevision('linked'),
      );
      expect(listed(store, allBoards: true), isEmpty);
    },
  );
}
