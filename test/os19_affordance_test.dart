import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/screens/completed_screen.dart';
import 'package:matrixflow_native/screens/settings_screen.dart';
import 'package:matrixflow_native/storage.dart';
import 'package:matrixflow_native/widgets/task_card.dart';
import 'package:matrixflow_native/widgets/task_hierarchy_checkbox.dart';
import 'package:provider/provider.dart';

import 'helpers.dart';
import 'support/settings_panels.dart';

Widget _app(
  Store store,
  Widget child, {
  double textScale = 1,
  TargetPlatform platform = TargetPlatform.windows,
  Size size = const Size(420, 900),
}) {
  return ChangeNotifierProvider.value(
    value: store,
    child: MaterialApp(
      theme: ThemeData(useMaterial3: true, platform: platform),
      locale: Locale(store.settings.language.name),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('en'), Locale('zh'), Locale('ja')],
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(textScale),
        ),
        child: child,
      ),
    ),
  );
}

/// The [FocusNode] installed above the element carrying [key].
FocusNode _nodeAt(WidgetTester tester, Key key) =>
    Focus.of(tester.element(find.byKey(key)));

/// The [FocusNode] of a tappable that owns no key of its own, such as the
/// `InkWell` behind a subtask toggle or a task title.
FocusNode _nodeBeneath(WidgetTester tester, Finder base, Type descendant) =>
    Focus.of(
      tester.element(
        find.descendant(of: base, matching: find.byType(descendant)).first,
      ),
    );

bool _paintsRing(WidgetTester tester, Key hitKey) {
  final ring = find.descendant(
    of: find.byKey(hitKey),
    matching: find.byType(CustomPaint),
  );
  return ring.evaluate().isNotEmpty &&
      tester.widget<CustomPaint>(ring.first).foregroundPainter != null;
}

SemanticsData _data(WidgetTester tester, Key key) =>
    tester.getSemantics(find.byKey(key)).getSemanticsData();

Size _size(WidgetTester tester, Key key) => tester.getSize(find.byKey(key));

Offset _tl(WidgetTester tester, Key key) => tester.getTopLeft(find.byKey(key));

double _paintedEdge(WidgetTester tester, Key visualKey) {
  final transform = tester.widget<Transform>(find.byKey(visualKey));
  // Z stays 1, so getMaxScaleOnAxis() reports 1 whenever the box is
  // smaller than Checkbox.width. The painted edge is the X scale.
  return Checkbox.width * transform.transform.entry(0, 0);
}

Task _seedParent(Store store, {String title = 'Ship release notes'}) {
  final parent = store.newTask(title, quadrant: qDo)
    ..subtasks = [
      SubTask(id: 'sub-a', title: 'Draft changelog'),
      SubTask(id: 'sub-b', title: 'Screenshot the matrix'),
    ];
  store.addTasks([parent]);
  return parent;
}

Widget _card(
  Task task, {
  bool expanded = false,
  required VoidCallback onChanged,
  VoidCallback? onToggleExpand,
  double width = 400,
}) {
  return Scaffold(
    body: SizedBox(
      width: width,
      child: TaskCard(
        task: task,
        entranceIndex: 0,
        onChanged: onChanged,
        onEdit: () {},
        onDelete: () {},
        onDecompose: () {},
        onDecomposeStart: () {},
        expanded: expanded,
        onToggleExpand: onToggleExpand,
      ),
    ),
  );
}

void main() {
  testWidgets('OS19: checkbox keeps a 48dp box and every edge activates it', (
    tester,
  ) async {
    final (store, _) = await makeStore();
    final parent = _seedParent(store);
    var refreshes = 0;
    await tester.pumpWidget(
      _app(store, _card(parent, expanded: true, onChanged: () => refreshes++)),
    );
    await tester.pumpAndSettle();

    final parentHit = ValueKey('complete-${parent.id}');
    const childHit = ValueKey('task-subtask-check-sub-a');

    expect(_size(tester, parentHit), const Size.square(48));
    expect(_size(tester, childHit), const Size.square(48));
    // Only the touch box is 48dp. The painted box tracks the title size.
    expect(
      _paintedEdge(tester, ValueKey('complete-${parent.id}-visual')),
      closeTo(TaskHierarchyStyle.parentCheckboxVisualSize, 0.01),
    );
    expect(
      _paintedEdge(tester, const ValueKey('task-subtask-check-sub-a-visual')),
      closeTo(TaskHierarchyStyle.childCheckboxVisualSize, 0.01),
    );

    for (final offset in [
      const Offset(1, 1),
      const Offset(46, 1),
      const Offset(1, 46),
      const Offset(46, 46),
      const Offset(24, 24),
    ]) {
      await tester.tapAt(_tl(tester, childHit) + offset);
      await tester.pumpAndSettle();
      expect(
        parent.subtasks.first.completed,
        isTrue,
        reason: 'child box must react at $offset',
      );
      await tester.tapAt(_tl(tester, childHit) + offset);
      await tester.pumpAndSettle();
      expect(
        parent.subtasks.first.completed,
        isFalse,
        reason: 'child box must toggle back at $offset',
      );
      expect(parent.completed, isFalse);
    }

    final beforeParentTaps = refreshes;
    await tester.tapAt(_tl(tester, parentHit) + const Offset(1, 46));
    await tester.pumpAndSettle();
    expect(parent.completed, isTrue);
    expect(refreshes, beforeParentTaps + 1);
    await tester.tapAt(_tl(tester, parentHit) + const Offset(46, 1));
    await tester.pumpAndSettle();
    expect(parent.completed, isFalse);
    expect(refreshes, beforeParentTaps + 2);
    expect(tester.takeException(), isNull);

    store.dispose();
  });

  testWidgets(
    'OS19: checkbox is Tab-reachable, shows a focus ring and toggles on Enter/Space',
    (tester) async {
      tester.binding.focusManager.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      final semantics = tester.ensureSemantics();
      final (store, _) = await makeStore();
      final parent = _seedParent(store);
      var refreshes = 0;
      await tester.pumpWidget(
        _app(
          store,
          _card(parent, expanded: true, onChanged: () => refreshes++),
        ),
      );
      await tester.pumpAndSettle();

      final parentHit = ValueKey('complete-${parent.id}');
      final checkbox = _nodeAt(tester, parentHit);
      expect(checkbox.canRequestFocus, isTrue);
      expect(_paintsRing(tester, parentHit), isFalse);
      expect(
        _data(tester, parentHit).hasFlag(SemanticsFlag.isFocusable),
        isTrue,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(
        tester.binding.focusManager.primaryFocus,
        same(checkbox),
        reason: 'Tab must land on the first control of the card',
      );
      expect(_paintsRing(tester, parentHit), isTrue);
      expect(_data(tester, parentHit).hasFlag(SemanticsFlag.isFocused), isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(parent.completed, isTrue);
      expect(refreshes, 1);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(parent.completed, isFalse);
      expect(refreshes, 2);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expect(_paintsRing(tester, parentHit), isFalse);
      expect(tester.takeException(), isNull);

      semantics.dispose();
      store.dispose();
    },
  );

  testWidgets(
    'OS19: parent and subtask boxes announce distinct labelled targets',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final (store, _) = await makeStore();
      final parent = _seedParent(store);
      await tester.pumpWidget(
        _app(store, _card(parent, expanded: true, onChanged: () {})),
      );
      await tester.pumpAndSettle();

      final parentHit = ValueKey('complete-${parent.id}');
      const childA = ValueKey('task-subtask-check-sub-a');
      const childB = ValueKey('task-subtask-check-sub-b');

      final parentData = _data(tester, parentHit);
      final childAData = _data(tester, childA);
      final childBData = _data(tester, childB);

      expect(
        parentData.label,
        'Mark parent task "Ship release notes" complete',
      );
      expect(childAData.label, 'Mark subtask "Draft changelog" complete');
      expect(childBData.label, 'Mark subtask "Screenshot the matrix" complete');

      for (final data in [parentData, childAData, childBData]) {
        expect(data.hasFlag(SemanticsFlag.hasCheckedState), isTrue);
        expect(data.hasFlag(SemanticsFlag.isChecked), isFalse);
        expect(data.hasFlag(SemanticsFlag.isButton), isTrue);
        // One announcement per control, not the label merged with title text.
        expect(data.label.split('"').length, 3, reason: data.label);
      }

      await tester.tapAt(_tl(tester, childA) + const Offset(24, 24));
      await tester.pumpAndSettle();
      expect(_data(tester, childA).label, isNot(childAData.label));
      expect(
        _data(tester, childA).label,
        'Mark subtask "Draft changelog" incomplete',
      );
      expect(_data(tester, childA).hasFlag(SemanticsFlag.isChecked), isTrue);
      expect(
        _data(tester, parentHit).label,
        'Mark parent task "Ship release notes" complete',
        reason: 'sibling boxes must not shift identity',
      );

      semantics.dispose();
      store.dispose();
    },
  );

  testWidgets(
    'OS19: subtask toggle enlarges only its hit box and reports expanded state',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final (store, _) = await makeStore();
      final parent = _seedParent(store);
      var expanded = false;
      await tester.pumpWidget(
        _app(
          store,
          StatefulBuilder(
            builder: (context, set) => _card(
              parent,
              expanded: expanded,
              onChanged: () {},
              onToggleExpand: () => set(() => expanded = !expanded),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final toggle = ValueKey('expand-${parent.id}');
      expect(_size(tester, toggle).height, greaterThanOrEqualTo(48));
      // The affordance itself is untouched: an 18dp glyph and the small label.
      expect(
        tester
            .widget<Icon>(
              find.descendant(
                of: find.byKey(toggle),
                matching: find.byType(Icon),
              ),
            )
            .size,
        18,
      );

      final collapsed = _data(tester, toggle);
      expect(collapsed.hasFlag(SemanticsFlag.hasExpandedState), isTrue);
      expect(collapsed.hasFlag(SemanticsFlag.isExpanded), isFalse);
      expect(collapsed.label, 'Subtasks of "Ship release notes", 0 of 2 done');

      await tester.tapAt(_tl(tester, toggle) + const Offset(4, 1));
      await tester.pumpAndSettle();
      expect(expanded, isTrue);
      expect(find.text('Draft changelog'), findsOneWidget);

      final open = _data(tester, toggle);
      expect(open.hasFlag(SemanticsFlag.isExpanded), isTrue);
      expect(
        open.label,
        collapsed.label,
        reason: 'expanded carries the state, so the label must not repeat it',
      );
      expect(tester.takeException(), isNull);

      semantics.dispose();
      store.dispose();
    },
  );

  testWidgets('OS19: Tab walks checkbox then title then subtask toggle', (
    tester,
  ) async {
    tester.binding.focusManager.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    final (store, _) = await makeStore();
    final parent = _seedParent(store);
    var expanded = false;
    await tester.pumpWidget(
      _app(
        store,
        StatefulBuilder(
          builder: (context, set) => _card(
            parent,
            expanded: expanded,
            onChanged: () {},
            onToggleExpand: () => set(() => expanded = !expanded),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final checkbox = _nodeAt(tester, ValueKey('complete-${parent.id}'));
    final title = _nodeBeneath(
      tester,
      find.ancestor(
        of: find.byKey(ValueKey('task-title-${parent.id}')),
        matching: find.byType(InkWell),
      ),
      GestureDetector,
    );
    final toggle = _nodeBeneath(
      tester,
      find.byKey(ValueKey('expand-${parent.id}')),
      GestureDetector,
    );
    expect(identical(checkbox, title), isFalse);
    expect(identical(title, toggle), isFalse);

    final order = <FocusNode>[];
    for (var i = 0; i < 3; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      order.add(tester.binding.focusManager.primaryFocus!);
    }
    expect(order, [checkbox, title, toggle]);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(expanded, isTrue);

    store.dispose();
  });

  testWidgets('OS19: theme colour dots are selectable without a mouse', (
    tester,
  ) async {
    tester.binding.focusManager.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    final semantics = tester.ensureSemantics();
    final (store, _) = await makeStore();
    await tester.pumpWidget(_app(store, const SettingsScreen()));
    await tester.pumpAndSettle();
    await openSettingsPanel(tester, 'settings-color-row');

    const blue = ValueKey('theme-color-hit-blue');
    const green = ValueKey('theme-color-hit-green');
    expect(store.settings.themeColor, ThemeColor.blue);

    expect(_size(tester, blue), const Size.square(48));
    expect(_size(tester, green), const Size.square(48));
    Size painted(Key key) => tester.getSize(
      find
          .descendant(
            of: find.byKey(key),
            matching: find.byType(AnimatedContainer),
          )
          .first,
    );
    // The painted dots keep their 34/28dp sizes inside the 48dp targets.
    expect(painted(blue).width, 34);
    expect(painted(green).width, 28);

    expect(_data(tester, blue).label, 'Theme color: Blue');
    expect(_data(tester, green).label, 'Theme color: Green');
    expect(_data(tester, blue).hasFlag(SemanticsFlag.isSelected), isTrue);
    expect(_data(tester, green).hasFlag(SemanticsFlag.isSelected), isFalse);
    expect(
      _data(tester, green).hasFlag(SemanticsFlag.isInMutuallyExclusiveGroup),
      isTrue,
    );

    final greenNode = _nodeAt(tester, green);
    var hops = 0;
    while (!identical(tester.binding.focusManager.primaryFocus, greenNode) &&
        hops < 12) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      hops++;
    }
    expect(
      identical(tester.binding.focusManager.primaryFocus, greenNode),
      isTrue,
      reason: 'every dot must be reachable by Tab alone ($hops hops)',
    );
    expect(_paintsRing(tester, green), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(store.settings.themeColor, ThemeColor.green);
    expect(_data(tester, green).hasFlag(SemanticsFlag.isSelected), isTrue);
    expect(_data(tester, blue).hasFlag(SemanticsFlag.isSelected), isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(store.settings.themeColor, ThemeColor.green);

    // The enlarged box pays off for thumbs too: an edge tap selects.
    await tester.tapAt(_tl(tester, blue) + const Offset(1, 46));
    await tester.pumpAndSettle();
    expect(store.settings.themeColor, ThemeColor.blue);
    expect(tester.takeException(), isNull);

    semantics.dispose();
    store.dispose();
  });

  testWidgets('OS19: completed screen names the restore box and toggle state', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final (store, _) = await makeStore();
    final done = store.newTask('Archived parent', quadrant: qPlan)
      ..completed = true
      ..completedAt = DateTime(2026, 9, 24).millisecondsSinceEpoch
      ..subtasks = [SubTask(id: 'done-sub', title: 'Archived child')];
    store.addTasks([done]);
    await tester.pumpWidget(_app(store, const CompletedScreen()));
    await tester.pumpAndSettle();

    final hit = ValueKey('completed-check-${done.id}');
    final toggle = ValueKey('completed-expand-${done.id}');
    expect(_size(tester, hit), const Size.square(48));
    expect(
      _size(tester, toggle).height,
      greaterThanOrEqualTo(48),
      reason: 'the archive toggle needs a touch-sized target too',
    );
    expect(
      _data(tester, hit).label,
      'Mark parent task "Archived parent" incomplete',
    );
    expect(_data(tester, hit).hasFlag(SemanticsFlag.isChecked), isTrue);
    expect(_data(tester, toggle).hasFlag(SemanticsFlag.isExpanded), isFalse);

    await tester.tapAt(_tl(tester, toggle) + const Offset(6, 1));
    await tester.pumpAndSettle();
    expect(_data(tester, toggle).hasFlag(SemanticsFlag.isExpanded), isTrue);
    expect(find.text('Archived child'), findsOneWidget);

    await tester.tapAt(_tl(tester, hit) + const Offset(1, 1));
    await tester.pumpAndSettle();
    expect(done.completed, isFalse);

    semantics.dispose();
    store.dispose();
  });

  testWidgets('OS19: 200% text keeps 48dp targets and separates the labels', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    for (final language in Language.values) {
      final (store, _) = await makeStore(
        settings: AppSettings()..language = language,
      );
      final parent = _seedParent(store);
      await tester.pumpWidget(
        _app(
          store,
          _card(parent, expanded: true, onChanged: () {}, width: 440),
          textScale: 2,
          size: const Size(460, 1400),
        ),
      );
      await tester.pumpAndSettle();

      final parentHit = ValueKey('complete-${parent.id}');
      const childHit = ValueKey('task-subtask-check-sub-a');
      final toggle = ValueKey('expand-${parent.id}');
      expect(
        _size(tester, parentHit),
        const Size.square(48),
        reason: '${language.name}: parent box',
      );
      expect(
        _size(tester, childHit),
        const Size.square(48),
        reason: '${language.name}: child box',
      );
      expect(
        _size(tester, toggle).height,
        greaterThanOrEqualTo(48),
        reason: '${language.name}: toggle box',
      );

      final parentLabel = _data(tester, parentHit).label;
      final childLabel = _data(tester, childHit).label;
      expect(parentLabel, contains(store.t['a11yRoleParent']!));
      expect(childLabel, contains(store.t['a11yRoleSubtask']!));
      expect(parentLabel, isNot(childLabel));
      expect(parentLabel, contains('Ship release notes'));
      expect(childLabel, contains('Draft changelog'));
      expect(
        _data(tester, toggle).label,
        contains(store.t['a11ySubtaskToggle']!.split('{title}').first.trim()),
        reason: '${language.name}: toggle label',
      );
      expect(
        tester.takeException(),
        isNull,
        reason: '${language.name}: layout',
      );

      await tester.pumpWidget(const SizedBox());
      store.dispose();
    }
    semantics.dispose();
  });
}
