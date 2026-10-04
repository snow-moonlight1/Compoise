import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/experiments/neumorphic/neumorphic.dart';

import 'uiexp1_harness.dart';

const _save = Key('uiexp1-one');
const _next = Key('uiexp1-two');
const _skip = Key('uiexp1-skip');

void main() {
  testWidgets('button states use fill, border, and icon; keyboard activates', (
    tester,
  ) async {
    tester.binding.focusManager.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    var presses = 0;
    final first = FocusNode();
    final third = FocusNode();
    await pumpUiexp(
      tester,
      home: Scaffold(
        body: Column(
          children: [
            NeuButton(
              key: _save,
              focusNode: first,
              label: '保存这项合成任务',
              role: NeuRole.primary,
              icon: Icons.check,
              onPressed: () => presses++,
            ),
            NeuButton(
              key: _skip,
              label: '禁用',
              role: NeuRole.secondary,
              paint: NeuPaint.disabled,
              onPressed: () => presses++,
            ),
            NeuButton(
              key: _next,
              focusNode: third,
              label: '时间',
              role: NeuRole.secondary,
              onPressed: () => presses++,
            ),
          ],
        ),
      ),
    );

    expect(tester.getSize(find.byKey(_save)).height, greaterThanOrEqualTo(48));
    expect(tester.getSize(find.byKey(_save)).width, greaterThanOrEqualTo(48));
    final resting = neuSurface(tester, _save);
    expect(resting.boxShadow, isNotEmpty);
    expect((resting.border! as Border).top.width, greaterThanOrEqualTo(2));

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(_save)),
    );
    await tester.pump();
    expect(neuSurface(tester, _save).color, isNot(resting.color));
    await gesture.up();
    await tester.pump();
    expect(presses, 1);

    expect(
      tester.getSemantics(find.byKey(_save)),
      containsSemantics(
        label: '保存这项合成任务',
        isButton: true,
        isEnabled: true,
        isFocusable: true,
      ),
    );
    expect(
      tester.getSemantics(find.byKey(_skip)),
      containsSemantics(label: '禁用', isButton: true, isEnabled: false),
    );
    final hatch = tester.widget<CustomPaint>(
      find.descendant(
        of: find.byKey(_skip),
        matching: find.byKey(NeuButton.hatchKey),
      ),
    );
    expect(hatch.foregroundPainter, isNotNull);

    first.requestFocus();
    // Focus applies in a microtask and schedules the ring rebuild for the next frame.
    await tester.pump();
    await tester.pump();
    expect(first.hasFocus, isTrue);
    expect(
      (neuRing(tester, _save).border! as Border).top.color,
      NeuSpec.resolve(
        brightness: Brightness.light,
        highContrast: false,
        reduceMotion: false,
      ).focusRing,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(presses, 3);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.pump();
    expect(third.hasFocus, isTrue);
    expect(first.hasFocus, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
    first.dispose();
    third.dispose();
  });

  testWidgets(
    'high contrast and reduced motion drop shadows and keep borders',
    (tester) async {
      Future<void> pump({required bool contrast, required bool motion}) =>
          pumpUiexp(
            tester,
            highContrast: contrast,
            reduceMotion: motion,
            home: Scaffold(
              body: NeuButton(
                key: _save,
                label: '保存',
                role: NeuRole.primary,
                onPressed: () {},
              ),
            ),
          );

      await pump(contrast: true, motion: false);
      final contrast = neuSurface(tester, _save);
      expect(contrast.boxShadow, isNull);
      expect((contrast.border! as Border).top.width, greaterThanOrEqualTo(2));

      await pump(contrast: false, motion: true);
      final motion = neuSurface(tester, _save);
      expect(motion.boxShadow, isNull);
      expect((motion.border! as Border).top.width, greaterThanOrEqualTo(2));
      expect(tester.binding.transientCallbackCount, 0);
    },
  );

  testWidgets('field keeps newline, error, disabled, and focus border', (
    tester,
  ) async {
    final focus = FocusNode();
    final controller = TextEditingController();
    await pumpUiexp(
      tester,
      home: Scaffold(
        body: Column(
          children: [
            NeuField(
              key: const Key('note'),
              label: '备注',
              controller: controller,
              focusNode: focus,
              minLines: 2,
              maxLines: 4,
            ),
            const NeuField(
              key: Key('broken'),
              label: '备注',
              errorText: '无法保存这份合成样本',
            ),
            const NeuField(key: Key('off'), label: '备注', enabled: false),
          ],
        ),
      ),
    );

    expect(
      tester.getSize(find.byKey(const Key('note'))).height,
      greaterThanOrEqualTo(48),
    );
    await tester.enterText(find.byKey(const Key('note')), '甲\n乙');
    await tester.pump();
    expect(controller.text, '甲\n乙');

    focus.requestFocus();
    await tester.pump();
    final field = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const Key('note')),
        matching: find.byType(TextField),
      ),
    );
    final focused = field.decoration!.focusedBorder! as OutlineInputBorder;
    expect(focused.borderSide.width, greaterThanOrEqualTo(3));
    expect(
      tester.getSemantics(
        find.descendant(
          of: find.byKey(const Key('note')),
          matching: find.byType(EditableText),
        ),
      ),
      containsSemantics(isTextField: true, isFocused: true),
    );

    expect(find.text('无法保存这份合成样本'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('broken')),
        matching: find.byIcon(Icons.error_outline),
      ),
      findsOneWidget,
    );
    final disabled = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const Key('off')),
        matching: find.byType(TextField),
      ),
    );
    expect(disabled.enabled, isFalse);
    expect(
      find.descendant(
        of: find.byKey(const Key('off')),
        matching: find.byIcon(Icons.block),
      ),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    focus.dispose();
    controller.dispose();
  });

  testWidgets('toolbar stacks long labels at 320dp and text scale 3', (
    tester,
  ) async {
    await pumpUiexp(
      tester,
      size: const Size(320, 800),
      textScale: 3,
      home: const Scaffold(
        body: NeuToolbar(
          title: '轻拟态外观实验的很长标题也应该换行而不是挤出屏幕',
          actions: [
            NeuToolbarAction(
              buttonKey: Key('tool-action'),
              label: '比较外观并保留普通新建一项',
              icon: Icons.compare_arrows,
              onPressed: _noop,
            ),
          ],
        ),
      ),
    );
    final title = tester.getRect(find.text('轻拟态外观实验的很长标题也应该换行而不是挤出屏幕'));
    final action = tester.getRect(find.byKey(const Key('tool-action')));
    expect(title.right, lessThanOrEqualTo(320));
    expect(action.right, lessThanOrEqualTo(320));
    expect(action.height, greaterThanOrEqualTo(48));
    expect(action.top, greaterThanOrEqualTo(title.top));
    expect(
      tester.getSemantics(find.text('轻拟态外观实验的很长标题也应该换行而不是挤出屏幕')),
      containsSemantics(isHeader: true),
    );
  });
}

void _noop() {}
