import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:compoise/screens/startup_recovery_screen.dart';
import 'package:compoise/storage.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/text_clip_probe.dart';

void main() {
  for (final language in ['zh', 'en', 'ja']) {
    for (final size in const [Size(360, 640), Size(1280, 800)]) {
      testWidgets('recovery screen reads plainly ($language, $size)', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        SharedPreferences.setMockInitialValues({
          'compoise-tasks': '[{"id":"broken","title":"unfin',
          'compoise-save-pointer': '{not json',
          'compoise-settings': '{"language":"$language"}',
        });
        final store = Store();
        addTearDown(store.dispose);
        await store.init();
        expect(store.hasStartupRecovery, isTrue);
        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: store,
            child: MediaQuery(
              data: MediaQueryData(
                size: size,
                textScaler: const TextScaler.linear(1.3),
              ),
              child: const MaterialApp(home: StartupRecoveryScreen()),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final t = store.t;
        expect(find.text(t['recoveryDescription']!), findsOneWidget);
        for (final banned in ['批次', '损坏值', '原始值', 'batch', 'damaged']) {
          for (final key in t.keys.where((k) => k.startsWith('recovery'))) {
            expect(t[key]!, isNot(contains(banned)));
          }
        }
        expect(findTextClips(tester), isEmpty);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
