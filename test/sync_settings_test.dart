// Settings → Sync: the entry row, WebDAV setup against an in-memory server,
// the dashboard's password prompts and disconnecting.
import 'package:compoise/l10n.dart';
import 'package:compoise/models.dart';
import 'package:compoise/screens/settings_screen.dart';
import 'package:compoise/screens/settings_sync.dart';
import 'package:compoise/storage.dart';
import 'package:compoise/sync/onedrive_auth.dart';
import 'package:compoise/sync/onedrive_remote.dart';
import 'package:compoise/sync/sync_controller.dart';
import 'package:compoise/sync/sync_engine.dart';
import 'package:compoise/sync/sync_local.dart';
import 'package:compoise/sync/sync_provider.dart';
import 'package:compoise/sync/webdav_remote.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'helpers.dart';
import 'onedrive_fake.dart';
import 'sync_controller_fakes.dart';
import 'webdav_fake.dart';

final en = dictOf(Language.en);

class UiRig {
  UiRig(this.store) {
    engine = SyncEngine(
      host: host,
      localStore: local,
      keyStore: MemorySyncKeyStore(),
      deviceName: 'unnamed',
      platform: 'android',
      appVersion: '1.2.0',
      runner: inlineSyncRunner,
      inlineKdf: true,
    );
    controller = SyncController(
      engine: engine,
      source: host,
      localStore: local,
      secrets: SyncSecrets(vaultKey: MemoryCredentials(), provider: secret),
      remoteFactory: (config, value, save) => switch (config.kind) {
        SyncProviderKind.onedrive => OneDriveRemote(
          tokens: OneDriveTokens.decode(value),
          saveTokens: save,
          client: graph.client,
        ),
        _ => WebDavRemote(
          baseUrl: normalizeWebDavUrl(config.webdav!.url)!,
          username: config.webdav!.username,
          password: value,
          client: server.client,
        ),
      },
      oneDrive: browser.authorizer(),
      timer: timers.call,
    );
  }

  final Store store;
  final server = FakeDavServer(root: '/dav/');
  final graph = FakeGraphServer();
  late final browser = FakeBrowser(graph);
  final host = SourceHost();
  final local = MemorySyncLocalStore();
  final secret = MemoryCredentials();
  final timers = ManualTimers();
  late final SyncEngine engine;
  late final SyncController controller;

  Widget app(Widget home) => MultiProvider(
    providers: [
      ChangeNotifierProvider<Store>.value(value: store),
      ChangeNotifierProvider<SyncController?>.value(value: controller),
    ],
    child: MaterialApp(
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('en'), Locale('zh'), Locale('ja')],
      home: home,
    ),
  );
}

Future<UiRig> _rig(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(480, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  // The store reads real files; everything sync-side is built on the test
  // clock so that the futures it creates complete under `pump`.
  final (store, _) = (await tester.runAsync(makeStore))!;
  final rig = UiRig(store);
  await _wait(tester, rig.controller.start());
  addTearDown(() {
    rig.controller.dispose();
    rig.store.dispose();
  });
  return rig;
}

Future<void> _fillWebDav(
  WidgetTester tester, {
  String url = 'https://dav.example.com/dav',
  String password = 'secret',
}) async {
  await tester.enterText(find.byKey(const ValueKey('sync-webdav-url')), url);
  await tester.enterText(
    find.byKey(const ValueKey('sync-webdav-user')),
    'user',
  );
  await tester.enterText(
    find.byKey(const ValueKey('sync-webdav-password')),
    password,
  );
  await tester.enterText(
    find.byKey(const ValueKey('sync-device-name')),
    'Test phone',
  );
  await tester.pump();
}

Future<void> _tapAndSettle(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Lets real work finish (key derivation uses isolates) and then moves the
/// test clock, on which the sync code's own futures run.
Future<void> _step(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 5)),
  );
  await tester.pump(const Duration(milliseconds: 50));
}

/// Moves both clocks until [future] completes.
Future<T> _wait<T>(WidgetTester tester, Future<T> future) async {
  var finished = false;
  late T value;
  Object? error;
  future.then(
    (result) {
      value = result;
      finished = true;
    },
    onError: (Object failure) {
      error = failure;
      finished = true;
    },
  );
  for (var i = 0; i < 200 && !finished; i++) {
    await _step(tester);
  }
  if (error != null) throw error!;
  expect(finished, isTrue, reason: 'timed out');
  return value;
}

/// Taps [finder] and keeps both clocks moving until [done]: a sync round
/// spans many futures, and `pumpAndSettle` stops once no frame is pending.
Future<void> _tapAndWait(
  WidgetTester tester,
  Finder finder,
  bool Function() done,
) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  for (var i = 0; i < 200 && !done(); i++) {
    await _step(tester);
  }
  await tester.pumpAndSettle();
}

Future<void> _connect(WidgetTester tester, UiRig rig) => _wait(
  tester,
  rig.controller.connect(
    const SyncProviderConfig(
      kind: SyncProviderKind.webdav,
      deviceName: 'Phone',
      webdav: WebDavSettings(
        url: 'https://dav.example.com/dav/',
        username: 'user',
      ),
    ),
    'secret',
  ),
);

/// Frames while the sign-in dialog's spinner runs; `pumpAndSettle` would
/// never return.
Future<void> _frames(WidgetTester tester, [int count = 8]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _connectOneDrive(WidgetTester tester, UiRig rig) => _wait(
  tester,
  rig.controller.connect(
    const SyncProviderConfig(
      kind: SyncProviderKind.onedrive,
      deviceName: 'Phone',
      account: 'me@outlook.com',
      accountId: 'user-1',
    ),
    rig.graph.tokens().encode(),
  ),
);

void main() {
  testWidgets('the settings row opens the sync page', (tester) async {
    final rig = await _rig(tester);
    await tester.pumpWidget(rig.app(const SettingsScreen()));
    await tester.pumpAndSettle();
    final row = find.byKey(const ValueKey('settings-sync-row'));
    await tester.scrollUntilVisible(row, 300);
    expect(
      find.descendant(of: row, matching: find.text(en['syncOff']!)),
      findsOneWidget,
    );
    await _tapAndSettle(tester, row);
    expect(find.byKey(const ValueKey('sync-intro')), findsOneWidget);
    expect(find.text(en['syncIntro']!), findsOneWidget);
  });

  testWidgets('WebDAV setup creates a vault and shows the dashboard', (
    tester,
  ) async {
    final rig = await _rig(tester);
    await tester.pumpWidget(rig.app(const SyncSettingsScreen()));
    await tester.pumpAndSettle();
    await _tapAndSettle(
      tester,
      find.byKey(const ValueKey('sync-choose-webdav')),
    );
    await _fillWebDav(tester);
    await _tapAndSettle(
      tester,
      find.byKey(const ValueKey('sync-webdav-connect')),
    );
    expect(find.byKey(const ValueKey('sync-new-vault')), findsOneWidget);

    await _tapAndWait(
      tester,
      find.byKey(const ValueKey('sync-start')),
      () => rig.controller.joined,
    );
    expect(find.byKey(const ValueKey('sync-dashboard')), findsOneWidget);
    expect(rig.controller.joined, isTrue);
    expect(rig.secret.value, 'secret');
    expect(rig.controller.config?.deviceName, 'Test phone');
    expect(rig.server.files.keys, contains('/dav/Compoise/vault.json'));
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('sync-status-text'))).data,
      startsWith('Synced'),
    );
    expect(find.text('Test phone'), findsOneWidget);
    expect(find.text(en['syncEncryptedOff']!), findsOneWidget);
  });

  testWidgets('a rejected password is explained and nothing is saved', (
    tester,
  ) async {
    final rig = await _rig(tester);
    await tester.pumpWidget(rig.app(const WebDavSetupScreen()));
    await tester.pumpAndSettle();
    await _fillWebDav(tester, password: 'wrong');
    await _tapAndSettle(
      tester,
      find.byKey(const ValueKey('sync-webdav-connect')),
    );
    expect(find.text(en['syncErrorAuth']!), findsOneWidget);
    expect(rig.secret.value, isNull);
    expect(rig.local.provider, isNull);
  });

  testWidgets('bad and plain-http addresses are flagged', (tester) async {
    final rig = await _rig(tester);
    await tester.pumpWidget(rig.app(const WebDavSetupScreen()));
    await tester.pumpAndSettle();
    await _fillWebDav(tester, url: 'dav.example.com');
    await _tapAndSettle(
      tester,
      find.byKey(const ValueKey('sync-webdav-connect')),
    );
    expect(find.text(en['syncWebdavUrlInvalid']!), findsOneWidget);

    await _fillWebDav(tester, url: 'http://dav.example.com/dav');
    expect(find.byKey(const ValueKey('sync-webdav-insecure')), findsOneWidget);
    await _fillWebDav(tester, url: 'http://192.168.1.2/dav');
    expect(find.byKey(const ValueKey('sync-webdav-insecure')), findsNothing);
  });

  testWidgets('joining an encrypted vault asks for its password', (
    tester,
  ) async {
    final rig = await _rig(tester);
    await _wait(tester, () async {
      final owner = SyncEngine(
        host: SourceHost(),
        localStore: MemorySyncLocalStore(),
        keyStore: MemorySyncKeyStore(),
        deviceName: 'Owner',
        platform: 'windows',
        appVersion: '1.2.0',
        runner: inlineSyncRunner,
        inlineKdf: true,
      );
      await owner.load();
      await owner.createVault(
        WebDavRemote(
          baseUrl: Uri.parse('https://dav.example.com/dav/'),
          username: 'user',
          password: 'secret',
          client: rig.server.client,
        ),
        provider: 'webdav',
        password: 'vault password',
      );
    }());
    await tester.pumpWidget(rig.app(const WebDavSetupScreen()));
    await tester.pumpAndSettle();
    await _fillWebDav(tester);
    await _tapAndSettle(
      tester,
      find.byKey(const ValueKey('sync-webdav-connect')),
    );
    expect(find.byKey(const ValueKey('sync-found-vault')), findsOneWidget);
    expect(find.text(en['syncFoundEncrypted']!), findsOneWidget);

    await _tapAndSettle(tester, find.byKey(const ValueKey('sync-start')));
    expect(find.text(en['syncErrorPasswordRequired']!), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('sync-password')),
      'not it',
    );
    // Key derivation runs for real here.
    await _tapAndWait(
      tester,
      find.byKey(const ValueKey('sync-start')),
      () => find.text(en['syncErrorWrongPassword']!).evaluate().isNotEmpty,
    );
    expect(find.text(en['syncErrorWrongPassword']!), findsOneWidget);
    expect(rig.controller.joined, isFalse);
  });

  testWidgets('disconnecting returns to the intro', (tester) async {
    final rig = await _rig(tester);
    await _connect(tester, rig);
    await tester.pumpWidget(rig.app(const SyncSettingsScreen()));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sync-dashboard')), findsOneWidget);

    await _tapAndSettle(tester, find.byKey(const ValueKey('sync-disconnect')));
    await _tapAndSettle(
      tester,
      find.byKey(const ValueKey('sync-disconnect-delete')),
    );
    await _tapAndWait(
      tester,
      find.byKey(const ValueKey('sync-disconnect-confirm')),
      () => !rig.controller.joined,
    );
    expect(find.byKey(const ValueKey('sync-intro')), findsOneWidget);
    expect(rig.controller.joined, isFalse);
    expect(rig.secret.value, isNull);
    expect(
      rig.server.files.keys.where((path) => path.endsWith('.cps')),
      isEmpty,
    );
  });

  testWidgets('a rejected sign-in offers to enter the password again', (
    tester,
  ) async {
    final rig = await _rig(tester);
    await _connect(tester, rig);
    rig.server.password = 'rotated';
    await _wait(tester, rig.controller.syncNow());
    await tester.pumpWidget(rig.app(const SyncSettingsScreen()));
    await tester.pumpAndSettle();
    expect(rig.controller.status.issue, SyncIssue.auth);
    expect(find.text(en['syncIssueAuth']!), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('sync-action-input')),
      'rotated',
    );
    await _tapAndWait(
      tester,
      find.byKey(const ValueKey('sync-action-submit')),
      () => rig.controller.status.phase == SyncPhase.idle,
    );
    expect(rig.secret.value, 'rotated');
    expect(rig.controller.status.phase, SyncPhase.idle);
    expect(find.byKey(const ValueKey('sync-action-input')), findsNothing);
  });

  testWidgets('renaming this device closes the dialog cleanly', (tester) async {
    final rig = await _rig(tester);
    await _connect(tester, rig);
    await tester.pumpWidget(rig.app(const SyncSettingsScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Phone'), findsOneWidget);

    await _tapAndSettle(
      tester,
      find.byKey(const ValueKey('sync-rename-device')),
    );
    await tester.enterText(
      find.byKey(const ValueKey('sync-rename-input')),
      '  Desk PC  ',
    );
    await _tapAndWait(
      tester,
      find.byKey(const ValueKey('sync-rename-save')),
      () => rig.controller.config?.deviceName == 'Desk PC',
    );
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('sync-rename-input')), findsNothing);
    expect(rig.controller.config?.deviceName, 'Desk PC');
    expect(find.text('Desk PC'), findsOneWidget);

    // Cancelling keeps the name.
    await _tapAndSettle(
      tester,
      find.byKey(const ValueKey('sync-rename-device')),
    );
    await _tapAndSettle(tester, find.text(en['cancel']!));
    expect(tester.takeException(), isNull);
    expect(rig.controller.config?.deviceName, 'Desk PC');
  });

  testWidgets('sync data without devices is described plainly', (tester) async {
    final rig = await _rig(tester);
    await _connect(tester, rig);
    await _wait(tester, rig.controller.disconnect(deleteOwnFile: true));
    expect(
      rig.server.files.keys.where((path) => path.endsWith('.cps')),
      isEmpty,
    );

    await tester.pumpWidget(rig.app(const WebDavSetupScreen()));
    await tester.pumpAndSettle();
    await _fillWebDav(tester);
    await _tapAndSettle(
      tester,
      find.byKey(const ValueKey('sync-webdav-connect')),
    );
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('sync-found-vault'))).data,
      en['syncFoundVaultNoDevices'],
    );
  });

  testWidgets(
    'OneDrive setup signs in, creates a vault and shows the account',
    (tester) async {
      final rig = await _rig(tester);
      await tester.pumpWidget(rig.app(const SyncSettingsScreen()));
      await tester.pumpAndSettle();
      await _tapAndSettle(
        tester,
        find.byKey(const ValueKey('sync-choose-onedrive')),
      );
      expect(find.text(en['syncOnedriveIntro']!), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('sync-device-name')),
        'Laptop',
      );
      await tester.tap(find.byKey(const ValueKey('sync-onedrive-sign-in')));
      await _frames(tester);
      expect(
        find.byKey(const ValueKey('sync-onedrive-dialog')),
        findsOneWidget,
      );
      expect(find.text(en['syncOnedriveBrowserOpened']!), findsOneWidget);
      expect(rig.browser.opened?.host, 'login.microsoftonline.com');

      rig.browser.approve();
      await _frames(tester);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('sync-onedrive-dialog')), findsNothing);
      expect(find.text('Signed in as me@outlook.com'), findsOneWidget);
      expect(find.byKey(const ValueKey('sync-new-vault')), findsOneWidget);
      expect(rig.secret.value, isNull, reason: 'nothing saved before start');

      await _tapAndWait(
        tester,
        find.byKey(const ValueKey('sync-start')),
        () => rig.controller.joined,
      );
      expect(find.byKey(const ValueKey('sync-dashboard')), findsOneWidget);
      final config = rig.controller.config!;
      expect(config.kind, SyncProviderKind.onedrive);
      expect(config.deviceName, 'Laptop');
      expect(config.account, 'me@outlook.com');
      expect(config.accountId, 'user-1');
      final saved = OneDriveTokens.decode(rig.secret.value)!;
      expect(rig.graph.refreshTokens, contains(saved.refreshToken));
      expect(rig.graph.files.keys, contains('vault.json'));
      expect(find.text('me@outlook.com · Apps/Compoise'), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('sync-status-text')))
            .data,
        startsWith('Synced'),
      );
    },
  );

  testWidgets('a cancelled or declined OneDrive sign-in saves nothing', (
    tester,
  ) async {
    final rig = await _rig(tester);
    rig.browser.opens = false;
    await tester.pumpWidget(rig.app(const OneDriveSetupScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('sync-onedrive-sign-in')));
    await _frames(tester);
    expect(find.text(en['syncOnedriveBrowserFailed']!), findsOneWidget);
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.tap(find.byKey(const ValueKey('sync-onedrive-copy-link')));
    await _frames(tester);
    expect(copied, rig.browser.opened.toString());
    await tester.tap(find.byKey(const ValueKey('sync-onedrive-cancel')));
    await _frames(tester);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sync-onedrive-dialog')), findsNothing);
    expect(find.byKey(const ValueKey('sync-setup-error')), findsNothing);
    expect(rig.browser.listener!.closed, isTrue);

    rig.browser.opens = true;
    await tester.tap(find.byKey(const ValueKey('sync-onedrive-sign-in')));
    await _frames(tester);
    rig.browser.deny();
    await _frames(tester);
    await tester.pumpAndSettle();
    expect(find.text(en['syncOnedriveDenied']!), findsOneWidget);
    expect(find.byKey(const ValueKey('sync-onedrive-sign-in')), findsOneWidget);
    expect(rig.secret.value, isNull);
    expect(rig.local.provider, isNull);
    expect(rig.graph.redeemCount, 0);
  });

  testWidgets('an expired OneDrive sign-in is renewed from the dashboard', (
    tester,
  ) async {
    final rig = await _rig(tester);
    await _connectOneDrive(tester, rig);
    rig.graph.revokeSignIn();
    await _wait(tester, rig.controller.syncNow());
    expect(rig.controller.status.issue, SyncIssue.auth);
    await tester.pumpWidget(rig.app(const SyncSettingsScreen()));
    await tester.pumpAndSettle();
    expect(find.text(en['syncIssueAuthOnedrive']!), findsOneWidget);
    expect(find.byKey(const ValueKey('sync-action-input')), findsNothing);

    // Another account is refused: its app folder holds other data.
    final before = rig.secret.value;
    await tester.tap(find.byKey(const ValueKey('sync-onedrive-reauth')));
    await _frames(tester);
    rig.browser.approve(account: 'other@outlook.com', id: 'user-2');
    await _frames(tester);
    expect(
      find.text(
        en['syncOnedriveOtherAccount']!.replaceAll(
          '{account}',
          'me@outlook.com',
        ),
      ),
      findsOneWidget,
    );
    expect(rig.secret.value, before);
    await tester.pumpAndSettle(const Duration(seconds: 5));

    await tester.tap(find.byKey(const ValueKey('sync-onedrive-reauth')));
    await _frames(tester);
    rig.browser.approve();
    for (var i = 0; i < 100 && rig.controller.status.issue != null; i++) {
      await _step(tester);
    }
    await tester.pumpAndSettle();
    expect(rig.controller.status.phase, SyncPhase.idle);
    expect(rig.controller.status.issue, isNull);
    expect(find.byKey(const ValueKey('sync-onedrive-reauth')), findsNothing);
    final saved = OneDriveTokens.decode(rig.secret.value)!;
    expect(rig.graph.refreshTokens, contains(saved.refreshToken));
  });
}
