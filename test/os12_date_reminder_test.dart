import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/calendar_dates.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/storage.dart';
import 'package:matrixflow_native/task_query.dart';
import 'package:matrixflow_native/widgets/input_sheet.dart';
import 'package:matrixflow_native/widgets/task_detail_panel.dart';
import 'package:provider/provider.dart';

import 'helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('civil dates', () {
    test('tomorrow crosses a month, a year, and a leap day', () {
      expect(
        addCivilDays(DateTime(2031, 1, 31, 23, 30), 1),
        DateTime(2031, 2, 1),
      );
      expect(
        addCivilDays(DateTime(2031, 12, 31, 0, 30), 1),
        DateTime(2032, 1, 1),
      );
      expect(addCivilDays(DateTime(2032, 2, 28, 12), 1), DateTime(2032, 2, 29));
      expect(addCivilDays(DateTime(2032, 2, 29, 12), 1), DateTime(2032, 3, 1));
      expect(addCivilDays(DateTime(2031, 2, 28, 12), 1), DateTime(2031, 3, 1));
    });

    test('five civil years keep the month and day, except leap day', () {
      expect(
        addCivilYears(DateTime(2030, 9, 23, 18, 40), 5),
        DateTime(2035, 9, 23),
      );
      expect(
        addCivilYears(DateTime(2032, 2, 29, 9), reminderPickerYearSpan),
        DateTime(2037, 2, 28),
      );
    });
  });

  group('picker windows', () {
    final now = DateTime(2030, 9, 23, 18, 40);
    final today = civilDate(now);
    final last = DateTime(2035, 9, 23);

    test('reminder initial is clamped without defining a stored value', () {
      final empty = reminderPickerWindow(now: now);
      expect(empty.first, today);
      expect(empty.last, last);
      expect(empty.initial, today);

      final past = reminderPickerWindow(
        now: now,
        deadline: DateTime(2029, 12, 31, 23, 59, 59),
      );
      expect(past.initial, today);

      final onLast = reminderPickerWindow(
        now: now,
        deadline: DateTime(2035, 9, 23, 23, 59, 59),
      );
      expect(onLast.initial, last);

      final onePast = reminderPickerWindow(
        now: now,
        deadline: DateTime(2035, 9, 24, 0, 1),
      );
      expect(onePast.initial, last);

      final decade = reminderPickerWindow(
        now: now,
        deadline: DateTime(2040, 1, 1, 15, 30),
      );
      expect(decade.initial, last);
      expect(decade.initial, isNot(civilDate(DateTime(2040, 1, 1))));

      final preferred = reminderPickerWindow(
        now: now,
        reminderAt: DateTime(2032, 1, 2, 9).millisecondsSinceEpoch,
        deadline: DateTime(2040, 1, 1),
      );
      expect(preferred.initial, DateTime(2032, 1, 2));
    });

    test('deadline window keeps an in-range far day and clamps the dialog', () {
      final kept = deadlinePickerWindow(
        now: now,
        selected: DateTime(2190, 6, 15, 15, 30, 45),
      );
      expect(kept.initial, DateTime(2190, 6, 15));
      expect(kept.first, DateTime(1900, 1, 1));
      expect(kept.last, DateTime(2200, 12, 31));

      final early = deadlinePickerWindow(
        now: now,
        selected: DateTime(1890, 5, 1, 8),
      );
      expect(early.initial, DateTime(1900, 1, 1));

      final late = deadlinePickerWindow(
        now: now,
        selected: DateTime(2210, 1, 2, 8),
      );
      expect(late.initial, DateTime(2200, 12, 31));
    });
  });

  group('this week', () {
    test('a 25-hour or 23-hour day does not move the civil week', () {
      const fallBack = <int>[24, 24, 25, 24, 24, 24, 24];
      var sundayStart = 0;
      for (var i = 0; i < 6; i++) {
        sundayStart += fallBack[i];
      }
      final sundayLate = sundayStart + 23;
      expect(sundayLate, greaterThanOrEqualTo(7 * 24));

      const springForward = <int>[24, 24, 23, 24, 24, 24, 24];
      expect(springForward.reduce((a, b) => a + b), lessThan(7 * 24));

      final now = DateTime(2032, 6, 16, 12);
      final monday = addCivilDays(now, 1 - now.weekday);
      final sunday = addCivilDays(monday, 6);
      final nextMonday = addCivilDays(monday, 7);
      expect(
        deadlineInCivilWeek(
          DateTime(
            sunday.year,
            sunday.month,
            sunday.day,
            23,
            59,
            59,
          ).millisecondsSinceEpoch,
          now,
        ),
        isTrue,
      );
      expect(
        deadlineInCivilWeek(nextMonday.millisecondsSinceEpoch, now),
        isFalse,
      );
    });

    test('query uses civil week bounds across a month and a year', () {
      final yearNow = _firstWeekCrossing(2031, 12, crossYear: true);
      final monthNow = _firstWeekCrossing(2034, 5, crossYear: false);
      for (final now in [yearNow, monthNow]) {
        final monday = addCivilDays(now, 1 - now.weekday);
        final sunday = addCivilDays(monday, 6);
        final nextMonday = addCivilDays(monday, 7);
        final previous = addCivilDays(monday, -1);
        final board = Board(id: 'b', name: 'Board', createdAt: 1);
        final tasks = [
          _dated('sun', sunday, 23, 59, 59),
          _dated('next', nextMonday, 0, 0, 0),
          _dated('prev', previous, 23, 59, 59),
          _dated('mon', monday, 0, 1, 0),
        ];
        final hits = queryTasks(
          tasks: tasks,
          boards: [board],
          activeBoardId: 'b',
          dateFilter: TaskDateFilter.thisWeek,
          now: now,
        );
        expect(hits.map((hit) => hit.task.id), containsAll(['sun', 'mon']));
        expect(hits.map((hit) => hit.task.id), isNot(contains('next')));
        expect(hits.map((hit) => hit.task.id), isNot(contains('prev')));
      }
    });
  });

  group('reminder and deadline pickers', () {
    testWidgets('OS-R06: a deadline ten years out opens and cancel keeps it', (
      tester,
    ) async {
      final deadline = DateTime(DateTime.now().year + 10);
      final (store, task) = await _task(deadline: deadline);

      await _openReminder(tester, store, task);

      final dialog = tester.widget<DatePickerDialog>(
        find.byType(DatePickerDialog),
      );
      expect(dialog.initialDate!.isAfter(dialog.lastDate), isFalse);
      expect(dialog.initialDate!.isBefore(dialog.firstDate), isFalse);
      expect(civilDate(dialog.initialDate!), isNot(civilDate(deadline)));
      expect(
        civilDate(dialog.lastDate),
        addCivilYears(civilDate(dialog.firstDate), reminderPickerYearSpan),
      );

      await _cancelPicker(tester);
      expect(store.tasks.single.deadline, deadline.millisecondsSinceEpoch);
      expect(store.tasks.single.reminderAt, isNull);
      await _finish(tester, store);
    });

    testWidgets(
      'past, today, boundary, and one day past choose a safe initial',
      (tester) async {
        final today = civilDate(DateTime.now());
        final cases = <String, DateTime>{
          'past': addCivilDays(today, -3),
          'today': today,
          'boundary': addCivilYears(today, reminderPickerYearSpan),
          'beyond': addCivilDays(
            addCivilYears(today, reminderPickerYearSpan),
            1,
          ),
        };
        for (final entry in cases.entries) {
          final stored = DateTime(
            entry.value.year,
            entry.value.month,
            entry.value.day,
            16,
            45,
            1,
          );
          final (store, task) = await _task(deadline: stored);

          await _openReminder(tester, store, task);
          final dialog = tester.widget<DatePickerDialog>(
            find.byType(DatePickerDialog),
          );
          final initial = civilDate(dialog.initialDate!);
          final first = civilDate(dialog.firstDate);
          final last = civilDate(dialog.lastDate);
          expect(initial.isBefore(first), isFalse, reason: entry.key);
          expect(initial.isAfter(last), isFalse, reason: entry.key);
          if (entry.key == 'past' || entry.key == 'today') {
            expect(initial, first, reason: entry.key);
          } else if (entry.key == 'boundary') {
            expect(initial, last, reason: entry.key);
            expect(initial, civilDate(stored), reason: entry.key);
          } else {
            expect(initial, last, reason: entry.key);
            expect(initial, isNot(civilDate(stored)), reason: entry.key);
          }
          await _cancelPicker(tester);
          expect(store.tasks.single.deadline, stored.millisecondsSinceEpoch);
          expect(store.tasks.single.reminderAt, isNull);
          await _finish(tester, store);
        }
      },
    );

    testWidgets('imported far deadline and reminder survive both pickers', (
      tester,
    ) async {
      final (store, _) = await makeStore(deviceLocales: const [Locale('en')]);

      final board = store.boards.single;
      final deadline = DateTime(2190, 6, 15, 15, 30, 45);
      final reminder = DateTime(2190, 6, 15, 9);
      store.importData({
        'version': 2,
        'boards': [board.toJson()],
        'tasks': [
          {
            'id': 'imported-far',
            'boardId': board.id,
            'title': 'Imported far',
            'quadrant': 2,
            'createdAt': 10,
            'deadline': deadline.millisecondsSinceEpoch,
            'reminderAt': reminder.millisecondsSinceEpoch,
            'subtasks': [
              {
                'id': 'imported-sub',
                'title': 'Imported child',
                'completed': false,
                'deadline': deadline.millisecondsSinceEpoch,
                'reminderAt': reminder.millisecondsSinceEpoch,
              },
            ],
          },
        ],
      }, 'merge');
      final task = store.tasks.singleWhere((item) => item.id == 'imported-far');
      await _openReminder(tester, store, task);
      final reminderDialog = tester.widget<DatePickerDialog>(
        find.byType(DatePickerDialog),
      );
      expect(
        civilDate(reminderDialog.initialDate!),
        isNot(DateTime(2190, 6, 15)),
      );
      await _cancelPicker(tester);

      await tester.tap(find.byKey(const ValueKey('deadline-custom')));
      await tester.pumpAndSettle();
      final deadlineDialog = tester.widget<DatePickerDialog>(
        find.byType(DatePickerDialog),
      );
      expect(civilDate(deadlineDialog.initialDate!), DateTime(2190, 6, 15));
      expect(civilDate(deadlineDialog.lastDate), DateTime(2200, 12, 31));
      await _cancelPicker(tester);

      final saved = store.tasks.singleWhere(
        (item) => item.id == 'imported-far',
      );
      expect(saved.deadline, deadline.millisecondsSinceEpoch);
      expect(saved.reminderAt, reminder.millisecondsSinceEpoch);
      expect(saved.subtasks.single.deadline, deadline.millisecondsSinceEpoch);
      expect(saved.subtasks.single.reminderAt, reminder.millisecondsSinceEpoch);
      await _finish(tester, store);
    });

    testWidgets('a deadline after 2200 is kept when the dialog is cancelled', (
      tester,
    ) async {
      final stored = DateTime(2210, 1, 2, 8);
      final (store, task) = await _task(deadline: stored);

      await _pumpPanel(tester, store, task);
      await tester.tap(find.byKey(const ValueKey('edit-time-btn')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('deadline-custom')));
      await tester.pumpAndSettle();
      final dialog = tester.widget<DatePickerDialog>(
        find.byType(DatePickerDialog),
      );
      expect(civilDate(dialog.initialDate!), DateTime(2200, 12, 31));
      await _cancelPicker(tester);
      expect(store.tasks.single.deadline, stored.millisecondsSinceEpoch);
      await _finish(tester, store);
    });

    testWidgets(
      'soft keyboard rejects an out-of-range reminder and cancel keeps it',
      (tester) async {
        final stored = DateTime(2190, 6, 15, 15, 30, 45);
        final (store, task) = await _task(
          deadline: stored,
          reminderAt: DateTime(2190, 6, 15, 9).millisecondsSinceEpoch,
        );

        await _openReminder(tester, store, task);
        await _switchToInput(tester);
        await tester.enterText(_dialogField(), _compact(DateTime(2190, 6, 15)));
        await tester.pump();
        await tester.tap(
          find.descendant(
            of: find.byType(DatePickerDialog),
            matching: find.text('OK'),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Out of range.'), findsOneWidget);
        expect(find.byType(DatePickerDialog), findsOneWidget);
        await _cancelPicker(tester);
        expect(store.tasks.single.deadline, stored.millisecondsSinceEpoch);
        expect(
          store.tasks.single.reminderAt,
          DateTime(2190, 6, 15, 9).millisecondsSinceEpoch,
        );
        await _finish(tester, store);
      },
    );

    testWidgets(
      'a valid keyboard date followed by cancelling time changes nothing',
      (tester) async {
        final stored = DateTime(DateTime.now().year + 10, 4, 5, 11);
        final (store, task) = await _task(deadline: stored);

        await _openReminder(tester, store, task);
        final dialog = tester.widget<DatePickerDialog>(
          find.byType(DatePickerDialog),
        );
        await _switchToInput(tester);
        await tester.enterText(_dialogField(), _compact(dialog.firstDate));
        await tester.pump();
        await tester.tap(
          find.descendant(
            of: find.byType(DatePickerDialog),
            matching: find.text('OK'),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(TimePickerDialog), findsOneWidget);
        await tester.tap(find.descendant(
          of: find.byType(TimePickerDialog),
          matching: find.text('Cancel'),
        ));
        await tester.pumpAndSettle();
        expect(store.tasks.single.deadline, stored.millisecondsSinceEpoch);
        expect(store.tasks.single.reminderAt, isNull);
        await _finish(tester, store);
      },
    );

    testWidgets(
      'subtask reminder keyboard cancel and tomorrow use civil dates',
      (tester) async {
        final deadline = DateTime(2190, 6, 15, 15, 30, 45);
        final reminder = DateTime(2190, 6, 15, 9);
        final (store, task) = await _task(
          deadline: deadline,
          subtask: SubTask(
            id: 'child-1',
            title: 'Child',
            deadline: deadline.millisecondsSinceEpoch,
            reminderAt: reminder.millisecondsSinceEpoch,
          ),
        );

        await _pumpPanel(tester, store, task);
        await tester.ensureVisible(
          find.byKey(const ValueKey('subtask-item-child-1')),
        );
        await tester.tap(find.byKey(const ValueKey('subtask-item-child-1')));
        await tester.pumpAndSettle();
        await tester.showKeyboard(
          find.byKey(const ValueKey('subtask-edit-title')),
        );
        _inset(tester);
        await tester.pump();
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const ValueKey('subtask-time-btn')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('reminder-quick-custom')));
        await tester.pumpAndSettle();
        final dialog = tester.widget<DatePickerDialog>(
          find.byType(DatePickerDialog),
        );
        expect(civilDate(dialog.initialDate!), isNot(DateTime(2190, 6, 15)));
        expect(dialog.initialDate!.isAfter(dialog.lastDate), isFalse);
        await _cancelPicker(tester);
        await tester.tap(find.text('Cancel').last);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('subtask-cancel-btn')));
        await tester.pumpAndSettle();
        expect(
          store.tasks.single.subtasks.single.deadline,
          deadline.millisecondsSinceEpoch,
        );
        expect(
          store.tasks.single.subtasks.single.reminderAt,
          reminder.millisecondsSinceEpoch,
        );

        final before = civilDate(DateTime.now());
        await tester.tap(find.byKey(const ValueKey('subtask-item-child-1')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('subtask-time-btn')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('deadline-tomorrow')));
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('time-confirm')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('subtask-save-btn')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('save-task')));
        await tester.pumpAndSettle();
        final after = civilDate(DateTime.now());
        final saved = DateTime.fromMillisecondsSinceEpoch(
          store.tasks.single.subtasks.single.deadline!,
        );
        expect(
          [addCivilDays(before, 1), addCivilDays(after, 1)].map(civilDate),
          contains(civilDate(saved)),
        );
        expect(saved.hour, 23);
        expect(saved.second, 59);
        expect(
          store.tasks.single.subtasks.single.reminderAt,
          reminder.millisecondsSinceEpoch,
        );
        expect(store.tasks.single.deadline, deadline.millisecondsSinceEpoch);
        await _finish(tester, store);
      },
    );

    testWidgets(
      'new task tomorrow follows the civil date and reminder cancel does not invent one',
      (tester) async {
        final (store, _) = await makeStore(deviceLocales: const [Locale('en')]);

        await _wide(tester);
        await tester.pumpWidget(
          _host(
            store,
            const InputSheet(initialMode: InputModePref.single, embedded: true),
          ),
        );
        await tester.pumpAndSettle();
        final before = civilDate(DateTime.now());
        await tester.showKeyboard(find.byKey(const ValueKey('task-step-0')));
        _inset(tester);
        await tester.enterText(
          find.byKey(const ValueKey('task-step-0')),
          'Tomorrow task',
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const ValueKey('input-time-btn')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('deadline-tomorrow')));
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('reminder-quick-custom')));
        await tester.pumpAndSettle();
        expect(find.byType(DatePickerDialog), findsOneWidget);
        await _cancelPicker(tester);
        await tester.tap(find.byKey(const ValueKey('time-confirm')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('submit-tasks')));
        await tester.pumpAndSettle();
        final after = civilDate(DateTime.now());
        final saved = DateTime.fromMillisecondsSinceEpoch(
          store.tasks.single.deadline!,
        );
        expect(
          [addCivilDays(before, 1), addCivilDays(after, 1)].map(civilDate),
          contains(civilDate(saved)),
        );
        expect(saved.hour, 23);
        expect(saved.minute, 59);
        expect(saved.second, 59);
        expect(store.tasks.single.reminderAt, isNull);
        await _finish(tester, store);
      },
    );

    testWidgets(
      'keyboard entry can keep a far deadline outside the reminder window',
      (tester) async {
        final (store, _) = await makeStore(deviceLocales: const [Locale('en')]);

        await _wide(tester);
        await tester.pumpWidget(
          _host(
            store,
            const InputSheet(initialMode: InputModePref.single, embedded: true),
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('task-step-0')),
          'Far deadline',
        );
        await tester.tap(find.byKey(const ValueKey('input-time-btn')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('deadline-custom')));
        await tester.pumpAndSettle();
        await _switchToInput(tester);
        await tester.enterText(_dialogField(), _compact(DateTime(2190, 6, 15)));
        await tester.pump();
        await tester.tap(
          find.descendant(
            of: find.byType(DatePickerDialog),
            matching: find.text('OK'),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('2190-06-15'), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('reminder-quick-custom')));
        await tester.pumpAndSettle();
        final dialog = tester.widget<DatePickerDialog>(
          find.byType(DatePickerDialog),
        );
        expect(civilDate(dialog.initialDate!), isNot(DateTime(2190, 6, 15)));
        expect(
          civilDate(dialog.lastDate),
          addCivilYears(civilDate(dialog.firstDate), reminderPickerYearSpan),
        );
        await _cancelPicker(tester);
        await tester.tap(find.byKey(const ValueKey('time-confirm')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('submit-tasks')));
        await tester.pumpAndSettle();
        final saved = DateTime.fromMillisecondsSinceEpoch(
          store.tasks.single.deadline!,
        );
        expect(saved, DateTime(2190, 6, 15, 23, 59, 59));
        expect(store.tasks.single.reminderAt, isNull);
        await _finish(tester, store);
      },
    );

    testWidgets(
      'due-date shortcut stores an absolute reminder and leaves the deadline',
      (tester) async {
        final stored = DateTime(2190, 6, 15, 15, 30, 45);
        final (store, task) = await _task(deadline: stored);

        await _pumpPanel(tester, store, task);
        await tester.tap(find.byKey(const ValueKey('edit-time-btn')));
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const ValueKey('reminder-quick-due-date')),
        );
        await tester.tap(find.byKey(const ValueKey('reminder-quick-due-date')));
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('time-confirm')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('save-task')));
        await tester.pumpAndSettle();
        final saved = store.tasks.single;
        final reminder = DateTime.fromMillisecondsSinceEpoch(saved.reminderAt!);
        expect(saved.deadline, stored.millisecondsSinceEpoch);
        expect(reminder, DateTime(2190, 6, 15, 9));
        await _finish(tester, store);
      },
    );
  });
}

DateTime _firstWeekCrossing(int year, int month, {required bool crossYear}) {
  for (var day = 1; day <= 31; day++) {
    final candidate = DateTime(year, month, day, 22, 40);
    if (candidate.month != month) continue;
    final monday = addCivilDays(candidate, 1 - candidate.weekday);
    final sunday = addCivilDays(monday, 6);
    final crosses = crossYear
        ? monday.year != sunday.year
        : monday.month != sunday.month;
    if (crosses) return candidate;
  }
  throw StateError('No crossing week in $year-$month');
}

Task _dated(String id, DateTime day, int hour, int minute, int second) {
  return Task(
    id: id,
    boardId: 'b',
    title: id,
    quadrant: qPlan,
    createdAt: 1,
    deadline: DateTime(
      day.year,
      day.month,
      day.day,
      hour,
      minute,
      second,
    ).millisecondsSinceEpoch,
  );
}

Widget _host(Store store, Widget child) {
  return ChangeNotifierProvider.value(
    value: store,
    child: MaterialApp(
      locale: const Locale('en'),
      home: Scaffold(body: child),
    ),
  );
}

Future<(Store, Task)> _task({
  required DateTime deadline,
  int? reminderAt,
  SubTask? subtask,
}) async {
  final (store, _) = await makeStore(deviceLocales: const [Locale('en')]);
  final task = store.newTask(
    'Dated',
    deadline: deadline.millisecondsSinceEpoch,
  );
  task.reminderAt = reminderAt;
  if (subtask != null) task.subtasks = [subtask];
  store.addTasks([task]);
  return (store, task);
}

Future<void> _finish(WidgetTester tester, Store store) async {
  await tester.pumpWidget(const SizedBox.shrink());
  store.dispose();
}

Future<void> _wide(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1000, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

void _inset(WidgetTester tester) {
  tester.view.viewInsets = const FakeViewPadding(bottom: 280);
  addTearDown(tester.view.reset);
}

Future<void> _pumpPanel(WidgetTester tester, Store store, Task task) async {
  await _wide(tester);
  await tester.pumpWidget(_host(store, TaskDetailPanel(task: task)));
  await tester.pumpAndSettle();
}

Future<void> _openReminder(WidgetTester tester, Store store, Task task) async {
  await _pumpPanel(tester, store, task);
  await tester.tap(find.byKey(const ValueKey('edit-time-btn')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('reminder-quick-custom')));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  expect(find.byType(DatePickerDialog), findsOneWidget);
}

Future<void> _cancelPicker(WidgetTester tester) async {
  await tester.tap(
    find.descendant(
      of: find.byType(DatePickerDialog),
      matching: find.text('Cancel'),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _switchToInput(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Switch to input'));
  await tester.pumpAndSettle();
  _inset(tester);
  await tester.showKeyboard(_dialogField());
  await tester.pump();
  expect(tester.takeException(), isNull);
  expect(find.byType(TextField), findsWidgets);
}

Finder _dialogField() {
  return find.descendant(
    of: find.byType(DatePickerDialog),
    matching: find.byType(TextField),
  );
}

String _compact(DateTime day) {
  final month = day.month.toString().padLeft(2, '0');
  final date = day.day.toString().padLeft(2, '0');
  final year = day.year.toString().padLeft(4, '0');
  return '$month/$date/$year';
}
