import 'dart:async';
import 'package:compoise/models.dart';
import 'package:compoise/screens/android_reminder_setup_screen.dart';
import 'package:compoise/screens/matrix_screen.dart';
import 'package:compoise/screens/onboarding_screen.dart';
import 'package:compoise/services/android_reminder_settings.dart';
import 'package:compoise/storage.dart';
import 'package:compoise/theme.dart';
import 'package:compoise/widgets/app_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'helpers.dart';
import 'support/text_clip_probe.dart';

class FakeSettings extends AndroidReminderSettings {
  bool notifications = false,
      exact = false,
      background = false,
      autoStart = true;
  bool unavailable = false;
  String? declined, failed;
  Completer<bool>? gate;
  final opened = <String>[];
  @override
  Future<AndroidReminderStatus?> status() async => unavailable
      ? null
      : AndroidReminderStatus(
          notifications: notifications,
          exactAlarms: exact,
          background: background,
          autoStartAvailable: autoStart,
        );
  @override
  Future<bool> open(String setting) async {
    opened.add(setting);
    if (gate != null) return gate!.future;
    if (failed == setting) return false;
    if (declined != setting) {
      if (setting == 'notifications' || setting == 'notificationSettings') {
        notifications = true;
      }
      if (setting == 'exactAlarms') exact = true;
      if (setting == 'background') background = true;
    }
    return true;
  }
}

Widget app(
  Store store,
  Widget home, {
  String skin = 'default',
  TargetPlatform platform = TargetPlatform.android,
}) => ChangeNotifierProvider.value(
  value: store,
  child: MaterialApp(
    locale: Locale(store.settings.language.name),
    supportedLocales: const [Locale('en'), Locale('zh'), Locale('ja')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: buildTheme(
      Brightness.light,
      store.settings.themeColor,
      platform: platform,
      comicOutline: skin == 'comic',
      neumorphic: skin == 'neumorphic',
    ),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: const TextScaler.linear(1.3)),
      child: child!,
    ),
    home: home,
  ),
);

Future<void> finish(WidgetTester tester, Store store) async {
  await tester.pumpWidget(const SizedBox());
  store.dispose();
  await tester.pump();
}

void main() {
  testWidgets(
    'an unreadable permission status offers retry instead of a dead end',
    (tester) async {
      final (store, _) = await makeStore(
        settings: AppSettings(language: Language.zh),
      );
      final settings = FakeSettings()..unavailable = true;
      await tester.pumpWidget(
        app(store, AndroidReminderSetupScreen(settings: settings)),
      );
      await tester.pumpAndSettle();
      expect(find.text('无法读取提醒权限'), findsOneWidget);
      settings.unavailable = false;
      await tester.tap(find.byKey(const ValueKey('reminder-setup-enable')));
      await tester.pumpAndSettle();
      expect(find.text('无法读取提醒权限'), findsNothing);
      expect(settings.opened, isEmpty);
      await finish(tester, store);
    },
  );

  testWidgets(
    'successful first setup returns to home without another confirmation',
    (tester) async {
      final (store, _) = await makeStore();
      final settings = FakeSettings();
      await tester.pumpWidget(
        app(
          store,
          Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => AndroidReminderSetupScreen(
                      settings: settings,
                      firstVisit: true,
                    ),
                  ),
                ),
                child: const Text('Home'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('reminder-setup-enable')));
      await tester.pumpAndSettle();
      expect(find.text('Home'), findsOneWidget);
      expect(find.byType(AndroidReminderSetupScreen), findsNothing);
      expect(settings.opened, [
        'notifications',
        'exactAlarms',
        'background',
        'autoStart',
      ]);
      await finish(tester, store);
    },
  );
  testWidgets(
    'enable opens missing settings in order; duplicate taps do not open twice',
    (tester) async {
      final (store, _) = await makeStore();
      final settings = FakeSettings();
      await tester.pumpWidget(
        app(store, AndroidReminderSetupScreen(settings: settings)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('reminder-setup-enable')));
      await tester.tap(find.byKey(const ValueKey('reminder-setup-enable')));
      await tester.pumpAndSettle();
      expect(settings.opened, [
        'notifications',
        'exactAlarms',
        'background',
        'autoStart',
      ]);
      expect(find.byType(SnackBar), findsNothing);
      // Auto-start remains a link, never a checkmark claiming a permission we cannot read.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('reminder-setting-autoStart')),
          matching: find.byIcon(Icons.check_circle_outline),
        ),
        findsNothing,
      );
      await finish(tester, store);
    },
  );

  for (final declined in ['notifications', 'exactAlarms', 'background']) {
    testWidgets(
      'declining $declined stops the following prompts and can be skipped',
      (tester) async {
        final (store, _) = await makeStore();
        final settings = FakeSettings()..declined = declined;
        await tester.pumpWidget(
          app(
            store,
            AndroidReminderSetupScreen(settings: settings, firstVisit: true),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('reminder-setup-enable')));
        await tester.pumpAndSettle();
        final steps = ['notifications', 'exactAlarms', 'background'];
        expect(
          settings.opened,
          steps.take(steps.indexOf(declined) + 1).toList(),
        );
        expect(find.byType(SnackBar), findsNothing);
        expect(
          find.byKey(const ValueKey('reminder-setup-skip')),
          findsOneWidget,
        );
        await finish(tester, store);
      },
    );
  }

  testWidgets(
    'already granted permissions are skipped and launch failures auto-dismiss',
    (tester) async {
      final (store, _) = await makeStore(
        settings: AppSettings(language: Language.zh),
      );
      final settings = FakeSettings()
        ..notifications = true
        ..exact = true
        ..failed = 'background';
      await tester.pumpWidget(
        app(store, AndroidReminderSetupScreen(settings: settings)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('reminder-setup-enable')));
      await tester.pumpAndSettle();
      expect(settings.opened, ['background']);
      expect(find.text('打不开系统设置'), findsOneWidget);
      await tester.pump(kNoticeDuration);
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
      await finish(tester, store);
    },
  );

  testWidgets(
    'returning from settings refreshes status; disposing a pending request is safe',
    (tester) async {
      final (store, _) = await makeStore();
      final settings = FakeSettings()..gate = Completer<bool>();
      await tester.pumpWidget(
        app(store, AndroidReminderSetupScreen(settings: settings)),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('reminder-setting-notifications')),
      );
      await tester.pump();
      settings.notifications = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('reminder-setting-notifications')),
          matching: find.byIcon(Icons.check_circle_outline),
        ),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      settings.gate!.complete(true);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      store.dispose();
    },
  );

  for (final skin in ['default', 'comic', 'neumorphic']) {
    for (final language in Language.values) {
      testWidgets('setup fits 360dp at 1.3x ($skin, ${language.name})', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(360, 800);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final (store, _) = await makeStore(
          settings: AppSettings(language: language),
        );
        await tester.pumpWidget(
          app(
            store,
            AndroidReminderSetupScreen(
              settings: FakeSettings(),
              firstVisit: true,
            ),
            skin: skin,
          ),
        );
        await tester.pumpAndSettle();
        expect(findTextClips(tester), isEmpty);
        expect(tester.takeException(), isNull);
        expect(
          find.byKey(const ValueKey('reminder-setup-enable')),
          findsOneWidget,
        );
        await finish(tester, store);
      });
    }
  }

  testWidgets(
    'first launch waits for the tutorial, shows setup once, and skip is remembered',
    (tester) async {
      final calls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        AndroidReminderSettings.channel,
        (call) async {
          calls.add(call.method);
          return {
            'notifications': false,
            'exactAlarms': false,
            'background': false,
            'autoStartAvailable': false,
          };
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          AndroidReminderSettings.channel,
          null,
        ),
      );
      final (store, _) = await makeStore(hasSeenOnboarding: false);
      await tester.pumpWidget(app(store, const MatrixHome()));
      await tester.pumpAndSettle();
      expect(find.byType(OnboardingScreen), findsOneWidget);
      expect(find.byType(AndroidReminderSetupScreen), findsNothing);
      expect(calls, isEmpty);
      await tester.tap(find.text(store.t['onboardingSkip']!));
      await tester.pumpAndSettle();
      expect(find.byType(AndroidReminderSetupScreen), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('reminder-setup-skip')));
      await tester.pumpAndSettle();
      expect(
        (await SharedPreferences.getInstance()).getBool(reminderSetupSeenKey),
        isTrue,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(app(store, const MatrixHome()));
      await tester.pumpAndSettle();
      expect(find.byType(AndroidReminderSetupScreen), findsNothing);
      await finish(tester, store);
    },
  );

  testWidgets('desktop startup does not query Android permissions', (
    tester,
  ) async {
    var called = false;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      AndroidReminderSettings.channel,
      (call) async {
        called = true;
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        AndroidReminderSettings.channel,
        null,
      ),
    );
    final (store, _) = await makeStore();
    await tester.pumpWidget(
      app(store, const MatrixHome(), platform: TargetPlatform.windows),
    );
    await tester.pumpAndSettle();
    expect(called, isFalse);
    expect(find.byType(AndroidReminderSetupScreen), findsNothing);
    await finish(tester, store);
  });
}
