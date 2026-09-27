import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/screens/matrix_screen.dart';
import 'package:matrixflow_native/storage.dart';
import 'package:matrixflow_native/widgets/task_card.dart';
import 'package:matrixflow_native/widgets/task_detail_panel.dart';
import 'package:provider/provider.dart';

import 'helpers.dart';

Widget wrapApp(Store store, {Size size = const Size(360, 800)}) {
  return ChangeNotifierProvider.value(
    value: store,
    child: MaterialApp(
      theme: ThemeData(useMaterial3: true, platform: TargetPlatform.android),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('en'), Locale('zh'), Locale('ja')],
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: const MatrixHome(),
      ),
    ),
  );
}

void main() {
  Future<Store> pumpMatrix(
    WidgetTester tester, {
    Size size = const Size(360, 800),
    required List<Task> Function(Store store) seed,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final (store, _) = await makeStore();
    store.addTasks(seed(store));
    await tester.pumpWidget(wrapApp(store, size: size));
    await tester.pumpAndSettle();
    return store;
  }

  testWidgets('UX05: matrix parent and child titles share an x origin', (
    tester,
  ) async {
    final store = await pumpMatrix(
      tester,
      seed: (store) {
        final parent = store.newTask('Parent Feature', quadrant: qDo)
          ..subtasks = [SubTask(id: 's1', title: 'Nested child')];
        return [parent];
      },
    );
    await tester.tap(find.byKey(ValueKey('expand-${store.tasks.first.id}')));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Add subtask'), findsNothing);
    final parentX = tester.getTopLeft(find.text('Parent Feature')).dx;
    final childX = tester.getTopLeft(find.text('Nested child')).dx;
    expect((parentX - childX).abs(), lessThanOrEqualTo(1));
    final parentBox = tester.getCenter(
      find.byKey(ValueKey('complete-${store.tasks.first.id}')),
    );
    final childBox = tester.getCenter(
      find.byKey(const ValueKey('task-subtask-check-s1')),
    );
    expect((parentBox.dx - childBox.dx).abs(), lessThanOrEqualTo(1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('UX05: focus and list indent children by 16dp', (tester) async {
    final store = await pumpMatrix(
      tester,
      size: const Size(412, 844),
      seed: (store) {
        final parent = store.newTask('Aligned Parent', quadrant: qDo)
          ..subtasks = [SubTask(id: 's1', title: 'Indented child')];
        return [parent];
      },
    );
    await tester.tap(find.byKey(ValueKey('expand-${store.tasks.first.id}')));
    await tester.pumpAndSettle();
    final matrixDelta =
        tester.getTopLeft(find.text('Indented child')).dx -
        tester.getTopLeft(find.text('Aligned Parent')).dx;

    await tester.tap(find.byKey(const ValueKey('quadrant-header-1')));
    await tester.pumpAndSettle();
    final focusDelta =
        tester.getTopLeft(find.text('Indented child')).dx -
        tester.getTopLeft(find.text('Aligned Parent')).dx;
    expect(focusDelta, closeTo(TaskCard.hierarchicalIndent, 2));
    expect(matrixDelta.abs(), lessThanOrEqualTo(1));

    await tester.tap(find.byKey(const ValueKey('focus-back-btn')));
    await tester.pumpAndSettle();
    expect(find.text('Indented child'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('more-btn')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('view-mode-toggle-btn')));
    await tester.pumpAndSettle();
    final more = find.byKey(const ValueKey('more-panel'));
    if (more.evaluate().isNotEmpty) {
      Navigator.of(tester.element(more)).pop();
      await tester.pumpAndSettle();
    }
    final listDelta =
        tester.getTopLeft(find.text('Indented child')).dx -
        tester.getTopLeft(find.text('Aligned Parent')).dx;
    expect(listDelta, closeTo(TaskCard.hierarchicalIndent, 2));
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('UX05: subtask title opens parent detail; checkbox only completes', (
    tester,
  ) async {
    final store = await pumpMatrix(
      tester,
      seed: (store) {
        final parent = store.newTask('Host task', quadrant: qDo)
          ..subtasks = [SubTask(id: 's1', title: 'Open me')];
        return [parent];
      },
    );
    await tester.tap(find.byKey(ValueKey('expand-${store.tasks.first.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('task-subtask-check-s1')));
    await tester.pumpAndSettle();
    expect(store.tasks.first.subtasks.single.completed, isTrue);
    expect(find.byType(TaskDetailPanel), findsNothing);
    await tester.tap(find.byKey(const ValueKey('subtask-title-s1')));
    await tester.pumpAndSettle();
    expect(find.byType(TaskDetailPanel), findsOneWidget);
    expect(find.byKey(const ValueKey('detail-subtask-s1')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('UX05: 320dp long titles and 10 children do not overflow', (
    tester,
  ) async {
    final store = await pumpMatrix(
      tester,
      size: const Size(320, 720),
      seed: (store) {
        final parent = store.newTask(
          '紧急且重要的很长很长很长很长很长很长的父任务标题',
          quadrant: qDo,
        )..subtasks = [
          for (var i = 0; i < 10; i++)
            SubTask(id: 's$i', title: '子项 $i 也很长很长很长很长很长'),
        ];
        return [parent];
      },
    );
    await tester.tap(find.byKey(ValueKey('expand-${store.tasks.first.id}')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final hit = tester.getSize(
      find.byKey(const ValueKey('task-subtask-check-s0')),
    );
    expect(hit.width, greaterThanOrEqualTo(48));
    expect(hit.height, greaterThanOrEqualTo(48));
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });
}
