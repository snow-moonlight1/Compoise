// Destructive confirm buttons (discard, delete, clear): filled red in the
// default and comic themes; in the neumorphic theme the raised face stays
// and only the label is red, with no red plate behind it.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:compoise/models.dart';
import 'package:compoise/theme.dart';
import 'package:compoise/ui/danger_button_style.dart';

void main() {
  for (final (name, comic, neu) in [
    ('default', false, false),
    ('comic', true, false),
    ('neumorphic', false, true),
  ]) {
    testWidgets('$name: danger button', (tester) async {
      final theme = buildTheme(
        Brightness.light,
        ThemeColor.purple,
        comicOutline: comic,
        neumorphic: neu,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: Center(
              child: Builder(
                builder: (context) => FilledButton(
                  style: dangerButtonStyle(context),
                  onPressed: () {},
                  child: const Text('放弃'),
                ),
              ),
            ),
          ),
        ),
      );
      final material = tester.widget<Material>(
        find.descendant(
          of: find.byType(FilledButton),
          matching: find.byType(Material),
        ),
      );
      final error = theme.colorScheme.error;
      final label = tester.widget<RichText>(
        find.descendant(of: find.text('放弃'), matching: find.byType(RichText)),
      );
      if (neu) {
        expect(material.color?.a ?? 0, 0, reason: 'no plate behind the face');
        expect(label.text.style?.color, error);
      } else {
        expect(material.color, error);
      }
    });
  }
}
