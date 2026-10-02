import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/l10n.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/platform/device_time_zone.dart';
import 'package:matrixflow_native/platform/device_time_zone_picker.dart';

void main() {
  for (final unknown in [false, true]) {
    testWidgets('D2 narrow 3x zone picker scrolls search and results '
        '(unknown=$unknown)', (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      String? chosen;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(3)),
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  chosen = await showScheduleZonePicker(
                    context,
                    t: dictOf(Language.en),
                    deviceIanaId: unknown ? null : 'Asia/Tokyo',
                    deviceIdentity: unknown ? 'Unknown/Identity' : 'Asia/Tokyo',
                    problem: unknown ? DeviceTimeZoneProblem.invalid : null,
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final search = find.byKey(const ValueKey('schedule-zone-search'));
      await tester.ensureVisible(search);
      await tester.pumpAndSettle();
      await tester.enterText(search, 'America/New_York');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final option = find.byKey(
        const ValueKey('schedule-zone-option-America/New_York'),
      );
      await tester.ensureVisible(option);
      await tester.pumpAndSettle();
      await tester.tap(option);
      await tester.pumpAndSettle();
      expect(chosen, 'America/New_York');
      expect(tester.takeException(), isNull);
    });
  }
}
