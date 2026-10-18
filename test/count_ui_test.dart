import 'package:compoise/models.dart';
import 'package:compoise/storage.dart';
import 'package:compoise/widgets/task_card.dart';
import 'package:compoise/widgets/task_count.dart';
import 'package:compoise/widgets/input_sheet.dart';
import 'package:compoise/services/quick_capture.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'helpers.dart';

void main() {
  testWidgets(
    'record button updates a finite task and undo restores the prior progress',
    (tester) async {
      final (store, _) = await makeStore(
        boards: [Board(id: 'b', name: 'Work', createdAt: 0)],
        tasks: [
          Task(
            id: 't',
            boardId: 'b',
            title: 'Practice',
            quadrant: 2,
            createdAt: 0,
            countProgress: CountProgress(target: 2),
          ),
        ],
      );
      await tester.pumpWidget(
        ChangeNotifierProvider<Store>.value(
          value: store,
          child: MaterialApp(
            home: Consumer<Store>(
              builder: (context, store, _) => Scaffold(
                body: TaskCard(
                  task: store.tasks.single,
                  entranceIndex: 0,
                  onChanged: () {},
                  onEdit: () {},
                  onDelete: () {},
                  onDecompose: () {},
                  onDecomposeStart: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('count-add-t')));
      await tester.pumpAndSettle();
      expect(find.text('1/2'), findsOneWidget);
      expect(store.tasks.single.completed, isFalse);
      await tester.tap(find.text(store.t['undo']!));
      await tester.pumpAndSettle();
      expect(find.text('0/2'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('count-add-t')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('count-add-t')));
      await tester.pumpAndSettle();
      expect(store.tasks.single.completed, isTrue);
      expect(find.byKey(const ValueKey('count-add-t')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
      store.dispose();
    },
  );

  testWidgets(
    'counter setup validates finite targets and supports unlimited mode',
    (tester) async {
      final (store, _) = await makeStore();
      CountProgress? progress;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TaskCountEditor(
              progress: null,
              t: store.t,
              onChanged: (value) => progress = value,
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('edit-count-progress')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('count-mode')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(store.t['countFinite']!).last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('count-target')), '0');
      await tester.tap(find.byKey(const ValueKey('count-save')));
      await tester.pumpAndSettle();
      expect(find.text(store.t['countInvalid']!), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('count-target')), '50');
      await tester.tap(find.byKey(const ValueKey('count-save')));
      await tester.pumpAndSettle();
      expect(progress, CountProgress(target: 50));
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    },
  );

  testWidgets(
    'shared multiline text previews manual independent tasks without AI',
    (tester) async {
      final (store, _) = await makeStore();
      await tester.pumpWidget(
        ChangeNotifierProvider<Store>.value(
          value: store,
          child: const MaterialApp(
            home: Scaffold(
              body: InputSheet(
                initialMode: InputModePref.single,
                initialText: 'First\nSecond\nThird',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('task-input')), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('task-input')))
            .controller!
            .text,
        'First\nSecond\nThird',
      );
      await tester.tap(find.byKey(const ValueKey('submit-tasks')));
      await tester.pumpAndSettle();
      expect(
        store.tasks.map((t) => t.title),
        unorderedEquals(['First', 'Second', 'Third']),
      );
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    },
  );

  test(
    'capture queue keeps order and acknowledging an old request does not lose the next',
    () {
      final queue = QuickCapture();
      const first = CaptureRequest('share', text: 'First');
      const second = CaptureRequest('today');
      queue.enqueue(first);
      queue.enqueue(second);
      queue.acknowledge(second);
      expect(queue.next, same(first));
      queue.acknowledge(first);
      queue.acknowledge(first);
      expect(queue.next, same(second));
      queue.dispose();
    },
  );
}
