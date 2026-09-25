import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/storage.dart';
import 'package:matrixflow_native/ui/motion_policy.dart';
import 'package:matrixflow_native/widgets/task_card.dart';
import 'package:matrixflow_native/widgets/task_exit.dart';
import 'package:matrixflow_native/widgets/task_list_view.dart';
import 'package:provider/provider.dart';

import 'helpers.dart';

void main() {
  Future<({Store store, GlobalKey<_HostState> key})> pumpList(
    WidgetTester tester, {
    required List<Task> Function(Store store) seed,
    AppSettings? settings,
    Size size = const Size(800, 640),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final (store, _) = await makeStore(settings: settings);
    store.addTasks(seed(store));
    final key = GlobalKey<_HostState>();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: store,
        child: MaterialApp(
          home: _Host(key: key, store: store),
        ),
      ),
    );
    await tester.pump();
    return (store: store, key: key);
  }

  Future<void> finish(WidgetTester tester, Store store) async {
    // StaggerIn queues a one-shot delay per row. Flush it before the binding
    // checks for pending timers, then stop the store's deadline timer.
    await tester.pump(const Duration(milliseconds: 600));
    store.dispose();
  }

  ScrollableState primaryScrollable(WidgetTester tester) {
    final states = tester.stateList<ScrollableState>(find.byType(Scrollable));
    return states.reduce(
      (a, b) =>
          a.position.maxScrollExtent >= b.position.maxScrollExtent ? a : b,
    );
  }

  testWidgets('OS22: a long list mounts only the visible window', (
    tester,
  ) async {
    final harness = await pumpList(
      tester,
      seed: (store) => [
        for (var i = 0; i < 80; i++) store.newTask('合成行 $i', quadrant: qDo),
      ],
    );
    await tester.pump();
    final mounted = tester.widgetList<TaskCard>(find.byType(TaskCard)).length;
    expect(mounted, greaterThan(3));
    expect(mounted, lessThan(30));
    await finish(tester, harness.store);
  });

  testWidgets('OS22: list scroll offset survives a new TaskListView', (
    tester,
  ) async {
    final harness = await pumpList(
      tester,
      seed: (store) => [
        for (var i = 0; i < 40; i++) store.newTask('锚点 $i', quadrant: qDo),
      ],
    );
    await tester.pump();
    final before = primaryScrollable(tester);
    expect(before.position.maxScrollExtent, greaterThan(480));
    before.position.jumpTo(480);
    await tester.pump();
    expect(before.position.pixels, 480);

    harness.key.currentState!.setVisible(false);
    await tester.pump();
    harness.key.currentState!.setVisible(true);
    await tester.pump();

    expect(primaryScrollable(tester).position.pixels, closeTo(480, 1));
    await finish(tester, harness.store);
  });

  testWidgets('OS22: a visible row still plays the exit animation', (
    tester,
  ) async {
    final harness = await pumpList(
      tester,
      settings: AppSettings(hideCompleted: true),
      seed: (store) => [store.newTask('即将完成', quadrant: qDo)],
    );
    final taskId = harness.store.tasks.single.id;
    harness.store.setTaskCompleted(taskId, true);
    await tester.pump();

    final exiting = find.byWidgetPredicate(
      (widget) => widget is ExitingRow && widget.exiting,
    );
    expect(exiting, findsOneWidget);
    expect(find.text('即将完成'), findsOneWidget);

    await tester.pump(MotionPolicy.exitHold + MotionPolicy.exitCollapse);
    await tester.pump();
    expect(exiting, findsNothing);
    expect(find.text('即将完成'), findsNothing);
    await finish(tester, harness.store);
  });

  testWidgets(
    'OS22: parent expansion remains after the row leaves and returns',
    (tester) async {
      final harness = await pumpList(
        tester,
        seed: (store) {
          final parent = Task(
            id: 'parent-os22',
            boardId: store.activeBoardId,
            title: '父任务',
            quadrant: qDo,
            createdAt: 1,
            subtasks: [SubTask(id: 'child-os22', title: '子任务')],
          );
          return [
            parent,
            for (var i = 0; i < 30; i++) store.newTask('填充 $i', quadrant: qDo),
          ];
        },
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('expand-parent-os22')));
      await tester.pump();
      expect(find.text('子任务'), findsOneWidget);

      final scrollable = primaryScrollable(tester);
      scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
      await tester.pump();
      expect(find.text('子任务'), findsNothing);

      scrollable.position.jumpTo(0);
      await tester.pump();
      expect(find.text('父任务'), findsOneWidget);
      expect(find.text('子任务'), findsOneWidget);
      expect(harness.key.currentState!.expanded, contains('parent-os22'));
      await finish(tester, harness.store);
    },
  );
}

class _Host extends StatefulWidget {
  const _Host({super.key, required this.store});

  final Store store;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  bool visible = true;
  final Set<String> expanded = <String>{};

  void setVisible(bool value) => setState(() => visible = value);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: visible
          ? TaskListView(
              expandedIds: expanded,
              onToggleExpand: (id) {
                setState(() {
                  if (!expanded.add(id)) expanded.remove(id);
                });
              },
              onEdit: (_) {},
              onEditSubtask: (_, __) {},
            )
          : const SizedBox.shrink(),
    );
  }
}
