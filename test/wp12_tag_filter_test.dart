import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/screens/search_screen.dart';
import 'package:matrixflow_native/storage.dart';
import 'package:matrixflow_native/task_query.dart';
import 'package:matrixflow_native/widgets/task_filter_panel.dart';
import 'package:provider/provider.dart';

import 'helpers.dart';

/// WP12 tags, query half: several tags must all be satisfied, and running a
/// query must leave the library untouched.
Task _task({
  required String id,
  required List<String> tags,
  String title = 'Task',
  int quadrant = qDo,
  bool completed = false,
  int? deadline,
  List<SubTask> subtasks = const [],
  String boardId = 'b-a',
}) => Task(
  id: id,
  boardId: boardId,
  title: title,
  quadrant: quadrant,
  completed: completed,
  createdAt: 1000,
  deadline: deadline,
  subtasks: subtasks,
  tags: tags,
);

final List<Board> _boards = [
  Board(id: 'b-a', name: 'Work', createdAt: 1000),
  Board(id: 'b-b', name: 'Personal', createdAt: 1000),
];

List<String> _ids(List<TaskSearchResult> results) => results.map((
  result,
) => result.resultKey).toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('queryTasks tag filter', () {
    final tagged = [
      _task(id: 't1', tags: ['Work', 'Urgent']),
      _task(id: 't2', tags: ['Work']),
      _task(id: 't3', tags: ['urgent', 'Home']),
      _task(id: 't4', tags: const []),
    ];

    List<TaskSearchResult> run(
      List<String> tags, {
      List<Task>? tasks,
      String query = '',
    }) => queryTasks(
      tasks: tasks ?? tagged,
      boards: _boards,
      activeBoardId: 'b-a',
      query: query,
      tags: tags,
    );

    test('no tags requested keeps every task', () {
      expect(_ids(run(const [])), ['t1', 't2', 't3', 't4']);
      expect(_ids(run(const [''])), ['t1', 't2', 't3', 't4']);
    });

    test('one tag keeps the tasks carrying it', () {
      expect(_ids(run(const ['Work'])), ['t1', 't2']);
    });

    test('two tags are an AND, not an OR', () {
      expect(_ids(run(const ['Work', 'Urgent'])), ['t1']);
    });

    test('matching ignores case and stray whitespace on both sides', () {
      expect(_ids(run(const [' work ', 'URGENT'])), ['t1']);
      expect(_ids(run(const ['home'])), ['t3']);
    });

    test('a tag nobody carries returns nothing', () {
      expect(run(const ['Someday']), isEmpty);
      expect(run(const ['Work', 'Someday']), isEmpty);
    });

    test('tags are read from the parent, never from a subtask', () {
      final withChild = [
        _task(
          id: 'p1',
          tags: const ['Work'],
          subtasks: [SubTask(id: 's1', title: 'Child of Work')],
        ),
        _task(id: 'p2', tags: const [], title: 'Untagged'),
      ];
      expect(_ids(run(const ['Work'], tasks: withChild)), ['p1']);
      expect(_ids(run(const ['Child'], tasks: withChild)), isEmpty);
    });

    test('a subtask hit is kept only when its parent has every tag', () {
      final withChild = [
        _task(
          id: 'p1',
          tags: const ['Work', 'Deep'],
          title: 'Planning',
          subtasks: [SubTask(id: 's1', title: 'Draft the outline')],
        ),
        _task(
          id: 'p2',
          tags: const ['Work'],
          title: 'Other',
          subtasks: [SubTask(id: 's2', title: 'Draft the budget')],
        ),
      ];
      expect(_ids(run(const [], tasks: withChild, query: 'draft')), [
        'p1:s1',
        'p2:s2',
      ]);
      expect(_ids(run(const ['Work'], tasks: withChild, query: 'draft')), [
        'p1:s1',
        'p2:s2',
      ]);
      expect(_ids(run(const ['Deep'], tasks: withChild, query: 'draft')), [
        'p1:s1',
      ]);
    });

    test('tags combine with quadrant, status and scope', () {
      final mixed = [
        _task(id: 't1', tags: const ['Work'], quadrant: qPlan, completed: true),
        _task(id: 't2', tags: const ['Work'], quadrant: qPlan),
        _task(id: 't3', tags: const ['Work'], quadrant: qDo),
        _task(id: 't4', tags: const ['Work'], boardId: 'b-b', quadrant: qPlan),
      ];
      List<TaskSearchResult> query({
        int? quadrant,
        TaskStatusFilter status = TaskStatusFilter.all,
        TaskScopeFilter scope = TaskScopeFilter.currentBoard,
      }) => queryTasks(
        tasks: mixed,
        boards: _boards,
        activeBoardId: 'b-a',
        quadrant: quadrant,
        status: status,
        scope: scope,
        tags: const ['Work'],
      );

      expect(_ids(query(quadrant: qPlan)), ['t1', 't2']);
      expect(_ids(query(quadrant: qPlan, status: TaskStatusFilter.completed)), [
        't1',
      ]);
      expect(
        _ids(
          query(
            quadrant: qPlan,
            status: TaskStatusFilter.incomplete,
            scope: TaskScopeFilter.allBoards,
          ),
        ),
        ['t2', 't4'],
      );
      expect(_ids(query(scope: TaskScopeFilter.allBoards)), ['t1', 't2', 't3', 't4']);
    });

    test('a keyword query still searches titles while tags narrow the set', () {
      final tasks = [
        _task(id: 't1', tags: const ['Work'], title: 'Ship release notes'),
        _task(id: 't2', tags: const ['Home'], title: 'Ship the model boat'),
      ];
      expect(_ids(run(const ['Work'], tasks: tasks, query: 'ship')), ['t1']);
      expect(_ids(run(const ['Home'], tasks: tasks, query: 'ship')), ['t2']);
      expect(_ids(run(const ['Work', 'Home'], tasks: tasks, query: 'ship')), isEmpty);
      expect(_ids(run(const ['Work'], tasks: tasks, query: 'boat')), isEmpty);
    });

    test('running a query never touches the tasks it read', () {
      final tasks = [
        _task(id: 't1', tags: ['  Work ', 'work', '', 'Urgent']),
        _task(id: 't2', tags: ['Home']),
      ];
      final before = tasks.map((task) => jsonEncodeTask(task)).toList();
      final tagLists = tasks.map((task) => task.tags).toList();

      queryTasks(
        tasks: tasks,
        boards: _boards,
        activeBoardId: 'b-a',
        query: 'work',
        tags: const [' WORK ', 'work', ''],
      );

      expect(tasks.map((task) => jsonEncodeTask(task)).toList(), before);
      for (var i = 0; i < tasks.length; i++) {
        expect(
          identical(tasks[i].tags, tagLists[i]),
          isTrue,
          reason: 'the query must not swap a task tag list out',
        );
      }
      expect(tasks.first.tags, ['  Work ', 'work', '', 'Urgent']);
    });
  });

  group('TaskFilterCriteria tags', () {
    test('an empty tag list keeps the criteria default', () {
      expect(const TaskFilterCriteria(tags: []).isDefault, isTrue);
      expect(TaskFilterCriteria.defaults.tags, isEmpty);
      expect(const TaskFilterCriteria(tags: ['Work']).isDefault, isFalse);
    });

    test('tags are one dimension however many are selected', () {
      expect(const TaskFilterCriteria(tags: ['Work']).searchDimensionCount, 1);
      expect(
        const TaskFilterCriteria(
          scope: TaskScopeFilter.allBoards,
          tags: ['Work', 'Urgent', 'Home'],
        ).searchDimensionCount,
        2,
      );
      expect(
        const TaskFilterCriteria(tags: ['Work']).archiveDimensionCount,
        0,
        reason: 'the archive editor has no tag axis',
      );
    });

    test('copyWith replaces and clears tags', () {
      const base = TaskFilterCriteria(tags: ['Work']);
      expect(base.copyWith(tags: () => const ['Home']).tags, ['Home']);
      expect(base.copyWith(tags: () => const []).tags, isEmpty);
      expect(base.copyWith().tags, ['Work']);
      expect(
        base.copyWith(tags: () => const ['Home']).status,
        TaskStatusFilter.all,
      );
    });

    test('equality and hashing see the tag list', () {
      expect(
        const TaskFilterCriteria(tags: ['Work', 'Home']),
        const TaskFilterCriteria(tags: ['Work', 'Home']),
      );
      expect(
        const TaskFilterCriteria(tags: ['Work']).hashCode,
        const TaskFilterCriteria(tags: ['Work']).hashCode,
      );
      expect(
        const TaskFilterCriteria(tags: ['Work']),
        isNot(const TaskFilterCriteria(tags: ['Home'])),
      );
      expect(
        const TaskFilterCriteria(tags: ['Work', 'Home']),
        isNot(const TaskFilterCriteria(tags: ['Home', 'Work'])),
        reason: 'order is part of the stored value, matching is not',
      );
      expect(
        const TaskFilterCriteria(),
        const TaskFilterCriteria(tags: []),
        reason: 'an explicit empty list is the same filter as none',
      );
    });
  });

  test('applied filter summary lists each tag', () {
    const criteria = TaskFilterCriteria(tags: ['Work', '家庭']);
    final labels = appliedFilterSummaryLabels(
      criteria: criteria,
      kind: TaskFilterKind.search,
      t: const {'filterTags': 'Tags'},
      currentBoardName: 'Work',
    );
    expect(labels, containsAll(['Work', '家庭']));
    expect(
      appliedFilterSummaryLabels(
        criteria: criteria,
        kind: TaskFilterKind.archive,
        t: const {},
        currentBoardName: 'Work',
      ),
      isNot(contains('Work')),
    );
  });

  group('filter panel tag section', () {
    Future<Store> taggedStore() async {
      final (store, _) = await makeStore(
        boards: [Board(id: 'b-a', name: 'Work', createdAt: 1000)],
        tasks: [
          Task(
            id: 't1',
            boardId: 'b-a',
            title: 'Tagged',
            quadrant: qDo,
            createdAt: 1000,
            tags: ['Work', '家庭'],
          ),
          Task(
            id: 't2',
            boardId: 'b-a',
            title: 'Untagged',
            quadrant: qDo,
            createdAt: 1000,
          ),
        ],
      );
      return store;
    }

    TaskFilterCriteria? applied;

    Future<void> pumpPanel(
      WidgetTester tester,
      Store store, {
      TaskFilterKind kind = TaskFilterKind.search,
      TaskFilterCriteria initial = const TaskFilterCriteria(),
    }) async {
      applied = null;
      await tester.binding.setSurfaceSize(const Size(520, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: store,
          child: MaterialApp(
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            supportedLocales: const [Locale('en'), Locale('zh'), Locale('ja')],
            home: Scaffold(
              body: TaskFilterPanel(
                initial: initial,
                currentBoardName: 'Work',
                kind: kind,
                onApply: (value) => applied = value,
                onCancel: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> toggle(WidgetTester tester, String key) async {
      final finder = find.byKey(ValueKey(key));
      await tester.ensureVisible(finder);
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    testWidgets('offers every tag in the library as an AND picker', (
      tester,
    ) async {
      final store = await taggedStore();
      await pumpPanel(tester, store);

      expect(find.text('Tags'), findsOneWidget);
      expect(find.byKey(const ValueKey('filter-tag-all')), findsOneWidget);
      expect(find.byKey(const ValueKey('filter-tag-Work')), findsOneWidget);
      expect(find.byKey(const ValueKey('filter-tag-家庭')), findsOneWidget);

      await toggle(tester, 'filter-tag-Work');
      await toggle(tester, 'filter-tag-家庭');
      await toggle(tester, 'filter-apply-btn');

      expect(applied?.tags, ['Work', '家庭']);
      expect(applied?.searchDimensionCount, 1);
      expect(applied?.isDefault, isFalse);
      store.dispose();
    });

    testWidgets('tapping a tag twice drops it, All drops them all', (
      tester,
    ) async {
      final store = await taggedStore();
      await pumpPanel(
        tester,
        store,
        initial: const TaskFilterCriteria(tags: ['Work', '家庭']),
      );

      expect(find.byKey(const ValueKey('filter-tag-Work')), findsOneWidget);
      await toggle(tester, 'filter-tag-家庭');
      expect(applied, isNull, reason: 'draft changes stay inside the panel');

      await toggle(tester, 'filter-tag-Work');
      await toggle(tester, 'filter-tag-all');
      await toggle(tester, 'filter-apply-btn');
      expect(applied?.tags, isEmpty);
      expect(applied?.isDefault, isTrue);
      store.dispose();
    });

    testWidgets('a selected tag stays listed even if no task carries it', (
      tester,
    ) async {
      final store = await taggedStore();
      await pumpPanel(
        tester,
        store,
        initial: const TaskFilterCriteria(tags: ['Archived']),
      );
      expect(find.byKey(const ValueKey('filter-tag-Archived')), findsOneWidget);
      expect(find.byKey(const ValueKey('filter-tag-Work')), findsOneWidget);
      store.dispose();
    });

    testWidgets('no tags in the library, no tag section', (tester) async {
      final (store, _) = await makeStore(
        boards: [Board(id: 'b-a', name: 'Work', createdAt: 1000)],
      );
      await pumpPanel(tester, store);
      expect(find.text('Tags'), findsNothing);
      expect(find.byKey(const ValueKey('filter-tag-all')), findsNothing);
      store.dispose();
    });

    testWidgets('the archive editor keeps tags out of its scope-only list', (
      tester,
    ) async {
      final store = await taggedStore();
      await pumpPanel(tester, store, kind: TaskFilterKind.archive);
      expect(find.text('Tags'), findsNothing);
      expect(find.byKey(const ValueKey('filter-tag-Work')), findsNothing);
      store.dispose();
    });

    test('filtering a live library narrows search results', () async {
      final store = await taggedStore();
      addTearDown(store.dispose);
      const criteria = TaskFilterCriteria(tags: ['家庭']);
      final hits = queryTasks(
        tasks: store.tasks,
        boards: store.boards,
        activeBoardId: store.activeBoardId,
        tags: criteria.tags,
      );
      expect(hits.map((hit) => hit.task.id), ['t1']);
    });
  });

  group('search screen wiring', () {
    Future<Store> library() => makeStore(
      boards: [Board(id: 'b-a', name: 'Work', createdAt: 1000)],
      tasks: [
        Task(
          id: 't1',
          boardId: 'b-a',
          title: 'Alpha',
          quadrant: qDo,
          createdAt: 1000,
          tags: ['Work', '家庭'],
        ),
        Task(
          id: 't2',
          boardId: 'b-a',
          title: 'Beta',
          quadrant: qDo,
          createdAt: 1000,
          tags: ['Work'],
        ),
        Task(
          id: 't3',
          boardId: 'b-a',
          title: 'Gamma',
          quadrant: qDo,
          createdAt: 1000,
        ),
      ],
    ).then((value) => value.$1);

    Future<void> pumpSearch(WidgetTester tester, Store store) async {
      await tester.binding.setSurfaceSize(const Size(900, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: store,
          child: MaterialApp(
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            supportedLocales: const [Locale('en'), Locale('zh'), Locale('ja')],
            home: SearchScreen(initialBoardId: 'b-a'),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> pickTag(WidgetTester tester, String tag) async {
      final finder = find.byKey(ValueKey('filter-tag-$tag'));
      await tester.ensureVisible(finder);
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    testWidgets('one tag narrows the list, a second tag narrows it further', (
      tester,
    ) async {
      final store = await library();
      await pumpSearch(tester, store);
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Beta'), findsOneWidget);
      expect(find.text('Gamma'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('filter-open-btn')));
      await tester.pumpAndSettle();
      await pickTag(tester, 'Work');
      await pickTag(tester, '家庭');
      await tester.tap(find.byKey(const ValueKey('filter-apply-btn')));
      await tester.pumpAndSettle();

      expect(find.text('Alpha'), findsOneWidget);
      expect(
        find.text('Beta'),
        findsNothing,
        reason: 'Beta misses the second tag, and tags are AND',
      );
      expect(find.text('Gamma'), findsNothing);
      expect(find.text('Work'), findsWidgets);
      expect(find.text('家庭'), findsWidgets);
      store.dispose();
    });

    testWidgets('clearing the tag filter brings every task back', (
      tester,
    ) async {
      final store = await library();
      await pumpSearch(tester, store);
      await tester.tap(find.byKey(const ValueKey('filter-open-btn')));
      await tester.pumpAndSettle();
      await pickTag(tester, '家庭');
      await tester.tap(find.byKey(const ValueKey('filter-apply-btn')));
      await tester.pumpAndSettle();
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Beta'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('clear-filters-btn')));
      await tester.pumpAndSettle();
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Beta'), findsOneWidget);
      expect(find.text('Gamma'), findsOneWidget);
      store.dispose();
    });
  });
}

String jsonEncodeTask(Task task) => jsonEncode(task.toJson());
