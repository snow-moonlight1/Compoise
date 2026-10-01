import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/l10n.dart';
import 'package:matrixflow_native/main.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/screens/windows_upgrade_screen.dart';
import 'package:matrixflow_native/services/windows_data_upgrade.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final language in Language.values) {
    testWidgets(
      'failed upgrade blocks startup and offers retry/import ($language)',
      (tester) async {
        var attempts = 0;
        var opened = 0;
        await tester.pumpWidget(
          WindowsUpgradeStartup(
            deviceLocales: [Locale(language.name)],
            prepare: () async {
              attempts++;
              return const WindowsUpgradeResult(WindowsUpgradeStatus.failed);
            },
            openApplication: () async {
              opened++;
              return const Text('application');
            },
          ),
        );
        await tester.pumpAndSettle();
        final t = dictOf(language);
        expect(find.text(t['upgradeFailed']!), findsOneWidget);
        expect(opened, 0);
        await tester.tap(find.text(t['upgradeManual']!));
        await tester.pumpAndSettle();
        expect(find.text(t['upgradeManualInstructions']!), findsOneWidget);
        await tester.tap(find.text(t['upgradeRetry']!));
        await tester.pumpAndSettle();
        expect(attempts, 2);
        expect(opened, 0);
      },
    );
  }

  testWidgets('successful retry runs preparation before reminders and Store', (
    tester,
  ) async {
    final events = <String>[];
    var attempts = 0;
    await tester.pumpWidget(
      WindowsUpgradeStartup(
        deviceLocales: const [Locale('en')],
        prepare: () async {
          events.add('prepare');
          return WindowsUpgradeResult(
            ++attempts == 1
                ? WindowsUpgradeStatus.sourceUnreadable
                : WindowsUpgradeStatus.migrated,
          );
        },
        openApplication: () async {
          events.add('reminders');
          events.add('Store');
          return const MaterialApp(home: Text('opened synthetic app'));
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(events, ['prepare']);
    await tester.tap(find.text(dictOf(Language.en)['upgradeRetry']!));
    await tester.pumpAndSettle();
    expect(events, ['prepare', 'prepare', 'reminders', 'Store']);
    expect(find.text('opened synthetic app'), findsOneWidget);
  });

  for (final language in Language.values) {
    testWidgets(
      'credential/recovery notices require explicit continue ($language)',
      (tester) async {
        var opened = false;
        await tester.pumpWidget(
          WindowsUpgradeStartup(
            deviceLocales: [Locale(language.name)],
            prepare: () async => const WindowsUpgradeResult(
              WindowsUpgradeStatus.migrated,
              credentialsNeedSetup: true,
              protocolNeedsRecovery: true,
            ),
            openApplication: () async {
              opened = true;
              return const MaterialApp(home: Text('existing recovery'));
            },
          ),
        );
        await tester.pumpAndSettle();
        final t = dictOf(language);
        expect(find.text(t['upgradeCredentials']!), findsOneWidget);
        expect(find.text(t['upgradeRecovery']!), findsOneWidget);
        expect(opened, isFalse);
        await tester.ensureVisible(find.text(t['upgradeContinue']!));
        await tester.tap(find.text(t['upgradeContinue']!));
        await tester.pumpAndSettle();
        expect(opened, isTrue);
      },
    );
  }

  testWidgets(
    'adopted corrupt tasks use the actual existing Store recovery page',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'matrixflow-tasks': '[{"id":"synthetic-incomplete"',
        'matrixflow-settings': '{"language":"en"}',
      });
      await tester.pumpWidget(
        WindowsUpgradeStartup(
          prepare: () async =>
              const WindowsUpgradeResult(WindowsUpgradeStatus.migrated),
          openApplication: () async => const MatrixFlowApp(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(dictOf(Language.en)['recoveryTitle']!), findsOneWidget);
      expect(
        (await SharedPreferences.getInstance()).getString('matrixflow-tasks'),
        '[{"id":"synthetic-incomplete"',
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('unreadable current file never proceeds to Store', (
    tester,
  ) async {
    var opened = false;
    await tester.pumpWidget(
      WindowsUpgradeStartup(
        deviceLocales: const [Locale('en')],
        prepare: () async =>
            const WindowsUpgradeResult(WindowsUpgradeStatus.currentUnreadable),
        openApplication: () async {
          opened = true;
          return const SizedBox();
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(dictOf(Language.en)['upgradeCurrentUnreadable']!),
      findsOneWidget,
    );
    expect(opened, isFalse);
  });

  for (final language in Language.values) {
    testWidgets(
      'damaged optional schedule renders existing recovery ($language)',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          'matrixflow-tasks': '[]',
          'matrixflow-boards': '[]',
          'matrixflow-schedule': '[{"id":"synthetic-broken"}]',
          'matrixflow-settings': '{"language":"${language.name}"}',
        });
        await tester.pumpWidget(
          WindowsUpgradeStartup(
            prepare: () async =>
                const WindowsUpgradeResult(WindowsUpgradeStatus.migrated),
            openApplication: () async => const MatrixFlowApp(),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(dictOf(language)['recoveryTitle']!), findsOneWidget);
        expect(find.text(dictOf(language)['scheduleTitle']!), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
