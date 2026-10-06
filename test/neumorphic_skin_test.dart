import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/theme.dart';
import 'package:matrixflow_native/widgets/home_actions.dart';
import 'package:matrixflow_native/widgets/task_card.dart';
import 'package:provider/provider.dart';

import 'helpers.dart';

void main() {
  testWidgets('neumorphic cards and the home bar extrude from the same slab', (
    tester,
  ) async {
    final theme = buildTheme(
      Brightness.light,
      ThemeColor.blue,
      neumorphic: true,
    );
    final skin = theme.extension<NeumorphicSkin>()!;
    expect(skin.canvas, skin.field);
    expect(skin.canvas, const Color(0xFFE0DEDA));

    final (store, _) = await makeStore(
      settings: AppSettings(language: Language.zh, neumorphic: true),
    );
    final task = store.newTask('买牛奶');
    store.addTasks([task]);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: store,
        child: MaterialApp(
          theme: theme,
          home: Scaffold(
            body: Column(
              children: [
                TaskCard(
                  task: task,
                  entranceIndex: 0,
                  onChanged: () {},
                  onEdit: () {},
                  onDelete: () {},
                  onDecompose: () {},
                  onDecomposeStart: () {},
                ),
                const TextField(decoration: InputDecoration(hintText: '下一步')),
                HomeBottomActions(onSearch: () {}, onAdd: () {}, onMore: () {}),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(NeuRaised), findsWidgets);
    final raised = tester.widget<DecoratedBox>(
      find.descendant(
        of: find.byType(TaskCard),
        matching: find.byType(DecoratedBox),
      ).first,
    );
    final box = raised.decoration as BoxDecoration;
    expect(box.color, skin.canvas);
    expect(box.boxShadow, skin.raisedShadows);

    final field = tester.widget<InputDecorator>(find.byType(InputDecorator));
    final resolved = field.decoration.applyDefaults(theme.inputDecorationTheme);
    expect(resolved.enabledBorder, isA<NeuInputBorder>());

    expect(
      find.descendant(
        of: find.byType(HomeBottomActions),
        matching: find.byType(NeuPressable),
      ),
      findsNWidgets(3),
    );

    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('a selected neumorphic card is pressed in', (tester) async {
    final theme = buildTheme(
      Brightness.light,
      ThemeColor.blue,
      neumorphic: true,
    );
    final (store, _) = await makeStore(
      settings: AppSettings(language: Language.zh, neumorphic: true),
    );
    final task = store.newTask('买牛奶');
    store.addTasks([task]);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: store,
        child: MaterialApp(
          theme: theme,
          home: Scaffold(
            body: TaskCard(
              task: task,
              entranceIndex: 0,
              selected: true,
              onChanged: () {},
              onEdit: () {},
              onDelete: () {},
              onDecompose: () {},
              onDecomposeStart: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(NeuInset), findsOneWidget);
    expect(find.byType(NeuRaised), findsNothing);

    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('neumorphic home buttons still open search, add, and more', (
    tester,
  ) async {
    final theme = buildTheme(
      Brightness.light,
      ThemeColor.blue,
      neumorphic: true,
    );
    final (store, _) = await makeStore(
      settings: AppSettings(language: Language.zh, neumorphic: true),
    );
    var search = 0;
    var add = 0;
    var more = 0;

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: store,
        child: MaterialApp(
          theme: theme,
          home: Scaffold(
            body: HomeBottomActions(
              onSearch: () => search += 1,
              onAdd: () => add += 1,
              onMore: () => more += 1,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('search-btn')));
    await tester.tap(find.byKey(const ValueKey('add-task-btn')));
    await tester.tap(find.byKey(const ValueKey('more-btn')));
    await tester.pump();

    expect(search, 1);
    expect(add, 1);
    expect(more, 1);

    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });
}
