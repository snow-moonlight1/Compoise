import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/screens/completed_screen.dart';
import 'package:matrixflow_native/screens/search_screen.dart';
import 'package:matrixflow_native/storage.dart';
import 'package:matrixflow_native/widgets/task_card.dart';
import 'package:matrixflow_native/widgets/task_hierarchy_checkbox.dart';
import 'package:provider/provider.dart';

import 'helpers.dart';

Widget _app(Store store, Widget child, {double textScale = 1}) {
  return ChangeNotifierProvider.value(
    value: store,
    child: MaterialApp(
      theme: ThemeData(useMaterial3: true, platform: TargetPlatform.windows),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('en'), Locale('zh'), Locale('ja')],
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(900, 800),
          textScaler: TextScaler.linear(textScale),
        ),
        child: child,
      ),
    ),
  );
}

double _paintedCheckboxEdge(WidgetTester tester, Key visualKey) {
  final transform = tester.widget<Transform>(find.byKey(visualKey));
  // Z stays 1, so getMaxScaleOnAxis() reports 1 whenever the box is
  // smaller than Checkbox.width. The painted edge is the X scale.
  return Checkbox.width * transform.transform.entry(0, 0);
}

void main() {
  testWidgets('OS02: checkbox paint tracks the title and the hit target stays 48dp', (
    tester,
  ) async {
    var parentToggles = 0;
    var childToggles = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              TaskHierarchyCheckbox(
                level: TaskHierarchyLevel.parent,
                value: false,
                onChanged: (_) => parentToggles++,
                hitTargetKey: const ValueKey('parent-hit'),
                visualKey: const ValueKey('parent-visual'),
              ),
              TaskHierarchyCheckbox(
                level: TaskHierarchyLevel.child,
                value: false,
                onChanged: (_) => childToggles++,
                hitTargetKey: const ValueKey('child-hit'),
                visualKey: const ValueKey('child-visual'),
              ),
            ],
          ),
        ),
      ),
    );

    expect(
      tester.getSize(find.byKey(const ValueKey('parent-hit'))),
      const Size.square(TaskHierarchyStyle.hitTargetSize),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('child-hit'))),
      const Size.square(TaskHierarchyStyle.hitTargetSize),
    );
    expect(
      _paintedCheckboxEdge(tester, const ValueKey('parent-visual')),
      closeTo(TaskHierarchyStyle.parentCheckboxVisualSize, 0.01),
    );
    expect(
      _paintedCheckboxEdge(tester, const ValueKey('child-visual')),
      closeTo(TaskHierarchyStyle.childCheckboxVisualSize, 0.01),
    );
    expect(
      _paintedCheckboxEdge(tester, const ValueKey('parent-visual')),
      greaterThan(_paintedCheckboxEdge(tester, const ValueKey('child-visual'))),
    );

    await tester.tap(find.byKey(const ValueKey('parent-hit')));
    await tester.tap(find.byKey(const ValueKey('child-hit')));
    expect(parentToggles, 1);
    expect(childToggles, 1);
  });

  testWidgets(
    'OS02: matrix card keeps parent/child text, alignment and independent controls at 200% text',
    (tester) async {
      final (store, _) = await makeStore();
      final task = store.newTask(
          'A very long parent task title that should still fit safely',
          quadrant: qDo,
        )
        ..subtasks = [
          SubTask(id: 'c1', title: 'A long first child task title'),
          SubTask(id: 'c2', title: 'A second child keeps parent incomplete'),
        ];
      store.addTasks([task]);

      await tester.pumpWidget(
        _app(
          store,
          Scaffold(
            body: SizedBox(
              width: 320,
              child: TaskCard(
                task: task,
                entranceIndex: 0,
                onChanged: () {},
                onEdit: () {},
                onDelete: () {},
                onDecompose: () {},
                onDecomposeStart: () {},
                expanded: true,
              ),
            ),
          ),
          textScale: 2,
        ),
      );
      await tester.pumpAndSettle();

      final parentHit = find.byKey(ValueKey('complete-${task.id}'));
      final childHit = find.byKey(const ValueKey('task-subtask-check-c1'));
      expect(tester.getSize(parentHit), const Size.square(48));
      expect(tester.getSize(childHit), const Size.square(48));
      expect(
        (tester.getCenter(parentHit).dx - tester.getCenter(childHit).dx).abs(),
        lessThanOrEqualTo(1),
      );
      expect(
        (tester.getTopLeft(find.text(task.title)).dx -
                tester
                    .getTopLeft(find.text('A long first child task title'))
                    .dx)
            .abs(),
        lessThanOrEqualTo(1),
      );

      final parentText = tester.widget<Text>(
        find.byKey(ValueKey('task-title-${task.id}')),
      );
      final childText = tester.widget<Text>(
        find.byKey(const ValueKey('subtask-title-text-c1')),
      );
      expect(parentText.style?.fontSize, TaskHierarchyStyle.parentTitleSize);
      expect(childText.style?.fontSize, TaskHierarchyStyle.childTitleSize);
      expect(tester.takeException(), isNull);

      await tester.tap(childHit);
      await tester.pump();
      expect(task.subtasks.first.completed, isTrue);
      expect(task.subtasks.last.completed, isFalse);
      expect(task.completed, isFalse);

      await tester.tap(parentHit);
      await tester.pump();
      expect(task.completed, isTrue);

      await tester.pumpWidget(const SizedBox());
      store.dispose();
    },
  );

  testWidgets('OS02: search, detail and completed views use shared hierarchy', (
    tester,
  ) async {
    final (store, _) = await makeStore();
    final task = store.newTask('Parent Search Target', quadrant: qDo)
      ..subtasks = [SubTask(id: 'search-child', title: 'Child Search Target')];
    store.addTasks([task]);

    await tester.pumpWidget(_app(store, const SearchScreen()));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('search-input')),
      'Child Search',
    );
    await tester.pumpAndSettle();

    final searchHit = find.byKey(
      ValueKey('search-check-hit-${task.id}:search-child'),
    );
    final searchVisual = ValueKey(
      'search-check-visual-${task.id}:search-child',
    );
    expect(tester.getSize(searchHit), const Size.square(48));
    expect(
      _paintedCheckboxEdge(tester, searchVisual),
      closeTo(TaskHierarchyStyle.childCheckboxVisualSize, 0.01),
    );
    expect(
      tester.widget<Text>(find.text('Child Search Target')).style?.fontSize,
      TaskHierarchyStyle.childTitleSize,
    );

    await tester.tap(find.text('Child Search Target'));
    await tester.pumpAndSettle();
    final detailHit = find.byKey(
      const ValueKey('detail-subtask-check-search-child'),
    );
    expect(tester.getSize(detailHit), const Size.square(48));
    expect(
      _paintedCheckboxEdge(
        tester,
        const ValueKey('detail-subtask-check-search-child-visual'),
      ),
      closeTo(TaskHierarchyStyle.childCheckboxVisualSize, 0.01),
    );

    await tester.pumpWidget(const SizedBox());
    store.dispose();

    final (completedStore, _) = await makeStore();
    final completed =
        completedStore.newTask('Completed Parent', quadrant: qDo)
          ..completed = true
          ..completedAt = DateTime(2026, 9, 22).millisecondsSinceEpoch
          ..subtasks = [SubTask(id: 'done-child', title: 'Completed Child')];
    completedStore.addTasks([completed]);
    await tester.pumpWidget(_app(completedStore, const CompletedScreen()));
    await tester.pumpAndSettle();

    final completedHit = find.byKey(
      ValueKey('completed-check-${completed.id}'),
    );
    expect(tester.getSize(completedHit), const Size.square(48));
    expect(
      _paintedCheckboxEdge(
        tester,
        ValueKey('completed-check-${completed.id}-visual'),
      ),
      closeTo(TaskHierarchyStyle.parentCheckboxVisualSize, 0.01),
    );
    expect(
      tester.widget<Text>(find.text('Completed Parent')).style?.fontSize,
      TaskHierarchyStyle.parentTitleSize,
    );

    await tester.tap(find.byKey(ValueKey('completed-expand-${completed.id}')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.text('Completed Child')).style?.fontSize,
      TaskHierarchyStyle.childTitleSize,
    );

    await tester.pumpWidget(const SizedBox());
    completedStore.dispose();
  });
}
