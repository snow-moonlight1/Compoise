import 'package:flutter_test/flutter_test.dart';
import 'package:compoise/models.dart';
import 'package:compoise/planned_policy.dart';

void main() {
  final now = DateTime(2026, 10, 14, 12);
  Task task(
    String id, {
    int? deadline,
    int? retiredPlan,
    bool completed = false,
  }) => Task(
    id: id,
    boardId: 'b',
    title: id,
    quadrant: qPlan,
    createdAt: 1,
    deadline: deadline,
    plannedDate: retiredPlan,
    completed: completed,
  );
  test('retired planning dates do not populate Today or affect sorting', () {
    for (final day in [DateTime(2026, 10, 13), now, DateTime(2026, 10, 15)]) {
      expect(
        todaySectionOf(
          task('old', retiredPlan: day.millisecondsSinceEpoch),
          now: now,
        ),
        isNull,
      );
    }
    final a = task(
      'a',
      retiredPlan: DateTime(2026, 1, 1).millisecondsSinceEpoch,
    )..createdAt = 2;
    final b = task('b')..createdAt = 1;
    expect(compareTodayTasks(a, b), greaterThan(0));
  });
  test(
    'Today includes due and overdue dates and excludes tomorrow or completed',
    () {
      expect(
        todaySectionOf(
          task(
            'due',
            deadline: DateTime(2026, 10, 14, 17).millisecondsSinceEpoch,
          ),
          now: now,
        ),
        TodaySection.dueNow,
      );
      expect(
        todaySectionOf(
          task(
            'old',
            deadline: DateTime(2026, 10, 13, 17).millisecondsSinceEpoch,
          ),
          now: now,
        ),
        TodaySection.dueNow,
      );
      expect(
        todaySectionOf(
          task(
            'later',
            deadline: DateTime(2026, 10, 15, 9).millisecondsSinceEpoch,
          ),
          now: now,
        ),
        isNull,
      );
      expect(
        todaySectionOf(
          task('done', completed: true, deadline: now.millisecondsSinceEpoch),
          now: now,
        ),
        isNull,
      );
    },
  );
  test(
    'scheduled tasks take precedence over due dates and are listed once',
    () {
      final a = task('scheduled', deadline: now.millisecondsSinceEpoch);
      final b = task('due', deadline: now.millisecondsSinceEpoch);
      final groups = groupForToday(
        [a, b],
        now: now,
        scheduledTaskIds: {'scheduled'},
      );
      expect(groups.map((g) => g.section), [
        TodaySection.scheduledToday,
        TodaySection.dueNow,
      ]);
      expect(groups.expand((g) => g.tasks).map((t) => t.id), [
        'scheduled',
        'due',
      ]);
    },
  );
  test('completion counts use the local completion day', () {
    final done = task('done', completed: true)
      ..completedAt = now.millisecondsSinceEpoch;
    expect(completedOnDay(done, now: now), isTrue);
    expect(completedOnDay(done, now: DateTime(2026, 10, 15)), isFalse);
  });
}
