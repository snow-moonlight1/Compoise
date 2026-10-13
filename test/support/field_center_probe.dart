import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:compoise/theme.dart';

/// One input field measured on screen.
class FieldCenter {
  FieldCenter(this.name, this.offset, this.labelGap);
  final String name;

  /// Value (or hint) center minus well center, in logical px.
  final double offset;

  /// Neumorphic floating label: well top minus label bottom (>= 0 is clear).
  final double? labelGap;
  @override
  String toString() =>
      '$name: off ${offset.toStringAsFixed(1)}px'
      '${labelGap == null ? '' : ', label gap ${labelGap!.toStringAsFixed(1)}px'}';
}

String _textOf(Widget w) => switch (w) {
  Text(:final data?) => data,
  Text(:final textSpan?) => textSpan.toPlainText(),
  _ => '',
};

/// Measures every visible [InputDecorator] (TextField, TextFormField,
/// DropdownButtonFormField, search fields): the shown value, or the hint
/// when empty, against the middle of the visible well. In the neumorphic
/// skin a floating label leaves [neuLabelBand] above and below the well.
List<FieldCenter> measureFields(WidgetTester tester) {
  final out = <FieldCenter>[];
  final screen =
      Offset.zero & tester.view.physicalSize / tester.view.devicePixelRatio;
  for (final element in find.byType(InputDecorator).evaluate()) {
    final decorator = element.widget as InputDecorator;
    final box = element.renderObject as RenderBox?;
    if (box == null || !box.attached || !box.hasSize) continue;
    final decoration = decorator.decoration;
    final ofDecorator = find.byElementPredicate((e) => e == element);
    final container = find.descendant(
      of: ofDecorator,
      matching: find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == '_BorderContainer',
      ),
    );
    if (container.evaluate().isEmpty) continue;
    final rect = tester.getRect(container.first);
    if (!screen.contains(rect.center) || rect.height < 24) continue;
    final neu = NeumorphicSkin.maybeOf(element) != null;
    final label = decoration.labelText ?? '';
    final floats =
        label.isNotEmpty &&
        (decoration.floatingLabelBehavior == FloatingLabelBehavior.always ||
            !decorator.isEmpty ||
            decorator.isFocused);
    // The border the decorator paints (TextField already merged the theme).
    final border =
        decoration.enabledBorder ??
        Theme.of(element).inputDecorationTheme.enabledBorder;
    final well = border is NeuInputBorder
        ? border.wellRect(rect, labelFloats: floats)
        : rect;

    Rect? value;
    String what = '';
    if (!decorator.isEmpty) {
      final editable = find.descendant(
        of: ofDecorator,
        matching: find.byType(EditableText),
      );
      if (editable.evaluate().isNotEmpty) {
        final r = editable.first.evaluate().first.renderObject as RenderBox;
        // One line only: a wrapped value is centered by its own height.
        value = tester.getRect(editable.first);
        what =
            (editable.evaluate().first.widget as EditableText).controller.text;
        if (r.size.height > 40) value = null;
      } else {
        for (final t
            in find
                .descendant(of: ofDecorator, matching: find.byType(Text))
                .evaluate()) {
          final s = _textOf(t.widget);
          if (s.isEmpty ||
              s == label ||
              s == decoration.hintText ||
              s == decoration.helperText ||
              s == decoration.errorText) {
            continue;
          }
          final r = tester.getRect(find.byElementPredicate((e) => e == t));
          if (!rect.contains(r.center)) continue;
          value = r;
          what = s;
          break;
        }
      }
    } else if (decoration.hintText != null && (label.isEmpty || floats)) {
      final hint = find.descendant(
        of: ofDecorator,
        matching: find.text(decoration.hintText!),
      );
      if (hint.evaluate().isNotEmpty) {
        value = tester.getRect(hint.first);
        what = 'hint ${decoration.hintText}';
      }
    }
    if (value == null) continue;
    double? gap;
    if (neu && floats) {
      final l = find.descendant(of: ofDecorator, matching: find.text(label));
      if (l.evaluate().isNotEmpty) {
        gap = well.top - tester.getRect(l.first).bottom;
      }
    }
    final key =
        decorator.key ??
        (element.findAncestorWidgetOfExactType<TextField>()?.key);
    out.add(
      FieldCenter(
        '${label.isEmpty ? '' : '[$label] '}$what ${key ?? ''}'.trim(),
        value.center.dy - well.center.dy,
        gap,
      ),
    );
  }
  return out;
}

/// Fields whose value is more than [tolerance] px off the well center, or
/// whose floating label runs into the neumorphic well.
List<FieldCenter> offCenterFields(
  WidgetTester tester, {
  double tolerance = 1.5,
}) => measureFields(
  tester,
).where((f) => f.offset.abs() > tolerance || (f.labelGap ?? 0) < -1).toList();
