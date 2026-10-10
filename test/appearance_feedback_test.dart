import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/theme.dart';
import 'package:matrixflow_native/ui/orphan_squeeze.dart';
import 'package:matrixflow_native/widgets/home_actions.dart';
import 'package:provider/provider.dart';

import 'helpers.dart';

void main() {
  testWidgets('a one-character last line is pulled onto the line above', (
    tester,
  ) async {
    const text = '看到你的看什么';
    const style = TextStyle(fontSize: 16, height: 1.2);
    final width = _widthThatOrphans(text, style);
    expect(width, isNotNull, reason: 'need a width that wraps one character');

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: width,
            child: const OrphanSqueeze(
              child: Text(text, style: style),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(_lineCount(tester, text), 1);
  });

  testWidgets('a real second line is left alone', (tester) async {
    const text = '看到你的看什么还想再写长一点';
    const style = TextStyle(fontSize: 16, height: 1.2);
    final painter = TextPainter(
      text: const TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 64);
    final before = painter.computeLineMetrics().length;
    painter.dispose();
    expect(before, greaterThan(1));

    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: SizedBox(
            width: 64,
            child: OrphanSqueeze(
              child: Text(text, style: style),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(_lineCount(tester, text), before);
  });

  testWidgets('neumorphic buttons extrude and do not paint a splash', (
    tester,
  ) async {
    final theme = buildTheme(
      Brightness.light,
      ThemeColor.blue,
      neumorphic: true,
    );
    expect(theme.splashFactory, NoSplash.splashFactory);
    expect(
      theme.outlinedButtonTheme.style?.overlayColor?.resolve({
        WidgetState.pressed,
      }),
      const Color(0x00000000),
    );
    expect(theme.extension<NeumorphicSkin>(), isNotNull);

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          appBar: AppBar(title: const Text('设置')),
          body: OutlinedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.security),
            label: const Text('检查提醒与通知权限'),
          ),
        ),
      ),
    );
    await tester.pump();

    final shadows = tester
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .map((box) => box.decoration)
        .whereType<BoxDecoration>()
        .where((decoration) => decoration.boxShadow != null);
    expect(shadows, isNotEmpty);

    await tester.tap(find.bySubtype<OutlinedButton>());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('comic home buttons are inset like the neumorphic bar', (
    tester,
  ) async {
    final theme = buildTheme(
      Brightness.light,
      ThemeColor.blue,
      comicOutline: true,
    );
    final (store, _) = await makeStore(
      settings: AppSettings(language: Language.zh, comicOutline: true),
    );
    await tester.binding.setSurfaceSize(const Size(360, 200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: store,
        child: MaterialApp(
          theme: theme,
          home: Scaffold(
            body: HomeBottomActions(
              onSearch: () {},
              onAdd: () {},
              onMore: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final row = tester.getSize(find.byType(Row).first);
    final button = tester.getSize(find.byKey(const ValueKey('search-btn')));
    expect(button.width, lessThan(row.width / 3 - 10));
    expect(button.height, greaterThanOrEqualTo(56));
    expect(
      tester
          .widget<TextButton>(find.byKey(const ValueKey('search-btn')))
          .style
          ?.overlayColor
          ?.resolve({WidgetState.pressed}),
      const Color(0x00000000),
    );

    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });
}

double? _widthThatOrphans(String text, TextStyle style) {
  final full = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: double.infinity);
  final natural = full.width;
  full.dispose();
  for (var width = natural - 1; width > natural * 0.7; width -= 1) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: width);
    final boxes = painter.getBoxesForSelection(
      TextSelection(baseOffset: 0, extentOffset: text.length),
    );
    final orphan = lastLineIsSingleGrapheme(
      text: text,
      boxes: boxes,
      positionAt: painter.getPositionForOffset,
    );
    painter.dispose();
    if (orphan) return width;
  }
  return null;
}

int _lineCount(WidgetTester tester, String text) {
  final paragraph = tester.renderObject<RenderParagraph>(find.text(text));
  final boxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: 0, extentOffset: text.length),
  );
  final tops = <int>{};
  for (final box in boxes) {
    tops.add(box.top.round());
  }
  return tops.length;
}
