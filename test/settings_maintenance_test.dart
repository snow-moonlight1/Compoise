import 'dart:convert';

import 'package:compoise/screens/settings_maintenance.dart';
import 'package:compoise/services/device_prefs.dart';
import 'package:compoise/services/update_check.dart';
import 'package:compoise/storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'helpers.dart';

Widget host(Store store, DevicePrefs prefs, UpdateChecker checker) =>
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SettingsMaintenanceTiles(
            t: store.t,
            store: store,
            prefs: prefs,
            checker: checker,
          ),
        ),
      ),
    );

UpdateChecker checkerFor(
  DevicePrefs prefs,
  Future<http.Response> Function() reply,
) => UpdateChecker(
  prefs: prefs,
  currentVersion: '1.0.0+1',
  client: MockClient((_) => reply()),
);

void main() {
  testWidgets('the update check switch is off until turned on', (tester) async {
    final (store, _) = await makeStore();
    final prefs = DevicePrefs();
    await prefs.load();
    await tester.pumpWidget(
      host(
        store,
        prefs,
        checkerFor(prefs, () async => http.Response('{}', 500)),
      ),
    );
    final toggle = find.byKey(const ValueKey('update-check-toggle'));
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    await tester.tap(toggle);
    await tester.pump();
    expect(prefs.updateCheckEnabled, isTrue);
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('checking now reports the latest version or a newer one', (
    tester,
  ) async {
    final (store, _) = await makeStore();
    final prefs = DevicePrefs();
    var tag = 'v1.0.0';
    await tester.pumpWidget(
      host(
        store,
        prefs,
        checkerFor(
          prefs,
          () async => http.Response(
            jsonEncode({
              'tag_name': tag,
              'html_url':
                  'https://github.com/snow-moonlight1/Compoise/releases/tag/$tag',
            }),
            200,
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('update-check-now')));
    await tester.pumpAndSettle();
    expect(find.text(store.t['updateUpToDate']!), findsOneWidget);

    tag = 'v1.0.1';
    await tester.tap(find.byKey(const ValueKey('update-check-now')));
    await tester.pumpAndSettle();
    expect(find.text(store.t['updateAvailableTitle']!), findsOneWidget);
    expect(
      find.text(
        'https://github.com/snow-moonlight1/Compoise/releases/tag/v1.0.1',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('update-copy-link')), findsOneWidget);
    await tester.tap(find.text(store.t['close']!));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });
}
