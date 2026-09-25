// Review counterexample for F16 / OS19, added 2026-09-25. Desired behaviour is
// asserted, so these deliberately fail on the reviewed baseline (main before
// OS19). Run explicitly:
//   flutter test --no-pub test/review/os19_review_probe.dart
// Named *_probe.dart so it stays out of the default suite, matching the other
// files in this directory. All data is synthetic.
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/screens/settings_screen.dart';
import 'package:matrixflow_native/storage.dart';
import 'package:matrixflow_native/widgets/task_card.dart';
import 'package:matrixflow_native/widgets/task_hierarchy_checkbox.dart';
import 'package:provider/provider.dart';

import '../helpers.dart';

Widget _app(Store store, Widget child) => ChangeNotifierProvider.value(
  value: store,
  child: MaterialApp(
    theme: ThemeData(useMaterial3: true, platform: TargetPlatform.windows),
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    supportedLocales: const [Locale('en'), Locale('zh'), Locale('ja')],
    home: MediaQuery(
      data: const MediaQueryData(size: Size(420, 900)),
      child: child,
    ),
  ),
);

Task _seed(Store store) {
  final parent = store.newTask('Ship release notes', quadrant: qDo)
    ..subtasks = [
      SubTask(id: 'sub-a', title: 'Draft changelog'),
      SubTask(id: 'sub-b', title: 'Screenshot the matrix'),
    ];
  store.addTasks([parent]);
  return parent;
}

Widget _cardOf(Task task, Store store, {bool expanded = true}) => Scaffold(
  body: SizedBox(
    width: 400,
    child: TaskCard(
      task: task,
      entranceIndex: 0,
      onChanged: () {},
      onEdit: () {},
      onDelete: () {},
      onDecompose: () {},
      onDecomposeStart: () {},
      expanded: expanded,
      onToggleExpand: () {},
    ),
  ),
);

SemanticsData _data(WidgetTester tester, Key key) =>
    tester.getSemantics(find.byKey(key)).getSemanticsData();

Offset _topLeft(WidgetTester tester, Key key) =>
    tester.getTopLeft(find.byKey(key));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'OS-R08a: the subtask toggle offers a real 48dp band and an expanded state',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final (store, _) = await makeStore();
      final parent = _seed(store);
      await tester.pumpWidget(_app(store, _cardOf(parent, store)));
      await tester.pumpAndSettle();

      final toggle = ValueKey('expand-${parent.id}');
      expect(
        tester.getSize(find.byKey(toggle)).height,
        greaterThanOrEqualTo(TaskHierarchyStyle.hitTargetSize),
        reason: 'the only pointer target of the toggle must reach 48dp',
      );
      final data = _data(tester, toggle);
      expect(
        data.hasFlag(SemanticsFlag.hasExpandedState),
        isTrue,
        reason: 'a screen reader must be told this control expands',
      );
      expect(
        data.label,
        isNot(contains('Expand')),
        reason: 'the state belongs to isExpanded, not to a second label',
      );

      semantics.dispose();
      store.dispose();
    },
  );

  testWidgets(
    'OS-R08b: one parent card names its parent and each subtask box apart',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final (store, _) = await makeStore();
      final parent = _seed(store);
      await tester.pumpWidget(_app(store, _cardOf(parent, store)));
      await tester.pumpAndSettle();

      final parentLabel = _data(
        tester,
        ValueKey('complete-${parent.id}'),
      ).label;
      final childA = _data(tester, const ValueKey('task-subtask-check-sub-a'));
      final childB = _data(tester, const ValueKey('task-subtask-check-sub-b'));

      expect(
        parentLabel,
        isNot(childA.label),
        reason: 'parent and subtask boxes must not share one announcement',
      );
      expect(childA.label, isNot(childB.label));
      expect(childA.label, contains('Draft changelog'));
      expect(childA.hasFlag(SemanticsFlag.hasCheckedState), isTrue);

      semantics.dispose();
      store.dispose();
    },
  );

  testWidgets(
    'OS-R08c: a completion box is one Tab stop and answers Space',
    (tester) async {
      final (store, _) = await makeStore();
      final parent = _seed(store);
      await tester.pumpWidget(_app(store, _cardOf(parent, store)));
      await tester.pumpAndSettle();

      final box = _topLeft(tester, ValueKey('complete-${parent.id}'));
      const boxSize = Size.square(TaskHierarchyStyle.hitTargetSize);

      var hops = 0;
      while (!parent.completed && hops < 6) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        hops++;
        final focused = tester.binding.focusManager.primaryFocus;
        final center = focused?.context?.findRenderObject();
        if (center is RenderBox) {
          final origin = center.localToGlobal(Offset.zero);
          final coversTheBox =
              origin.dx <= box.dx + 1 &&
              origin.dy <= box.dy + 1 &&
              origin.dx + center.size.width >= box.dx + boxSize.width - 1 &&
              origin.dy + center.size.height >= box.dy + boxSize.height - 1;
          if (!coversTheBox) continue;
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pumpAndSettle();
      }
      expect(
        parent.completed,
        isTrue,
        reason:
            'Space on the box must complete the task, not activate a decorative inner control ($hops hops)',
      );

      store.dispose();
    },
  );

  testWidgets('OS-R08d: a theme colour is reachable and chosen without a mouse', (
    tester,
  ) async {
    final (store, _) = await makeStore();
    await tester.pumpWidget(_app(store, const SettingsScreen()));
    await tester.pumpAndSettle();
    expect(store.settings.themeColor, ThemeColor.blue);

    // 20dp above the centre is outside a 28dp painted dot but inside a 48dp
    // target, so only a genuinely enlarged hit box can serve this tap.
    final greenCenter = tester.getCenter(find.byTooltip('Green'));
    await tester.tapAt(greenCenter + const Offset(0, -20));
    await tester.pumpAndSettle();
    expect(
      store.settings.themeColor,
      ThemeColor.green,
      reason: 'the painted dot is 28dp; the touch target must still be 48dp',
    );

    // Now leave the pointer alone: Tab until focus sits on the purple dot's own
    // target and press Enter there.
    final purpleCenter = tester.getCenter(find.byTooltip('Purple'));
    var hops = 0;
    var landed = false;
    while (!landed && hops < 30) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      hops++;
      final box =
          tester.binding.focusManager.primaryFocus?.context
              ?.findRenderObject() as RenderBox?;
      if (box == null) continue;
      final rect = box.localToGlobal(Offset.zero) & box.size;
      if (!rect.contains(purpleCenter)) continue;
      landed = true;
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
    }
    expect(
      landed,
      isTrue,
      reason: 'no keyboard stop ever covered the purple colour control',
    );
    expect(
      store.settings.themeColor,
      ThemeColor.purple,
      reason: 'Enter on the focused colour must select it ($hops hops)',
    );

    store.dispose();
  });
}
