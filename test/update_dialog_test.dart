import 'dart:async';
import 'dart:io';

import 'package:compoise/l10n.dart';
import 'package:compoise/models.dart';
import 'package:compoise/services/app_update.dart';
import 'package:compoise/services/update_check.dart';
import 'package:compoise/theme.dart';
import 'package:compoise/widgets/update_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/text_clip_probe.dart';

enum _Skin { material, comic, neumorphic }

class _FakeInstaller extends UpdateInstaller {
  _FakeInstaller({this.allowed = true});
  bool allowed;
  int installs = 0;
  int settingsOpened = 0;
  @override
  Future<bool> canInstall() async => allowed;
  @override
  Future<void> openInstallSettings() async => settingsOpened++;
  @override
  Future<bool> install(File file) async {
    installs++;
    return true;
  }
}

class _FakeUpdater extends AppUpdater {
  _FakeUpdater(this.fake, {this.ready = false, this.failure})
    : super(installer: fake, target: UpdateTarget.android);
  final _FakeInstaller fake;
  final bool ready;
  final UpdateFailure? failure;
  final gate = Completer<void>();
  void Function(int, int?)? progress;

  @override
  Future<bool> hasReadyPackage(ReleaseVersion version) async => ready;

  @override
  Future<File> prepare({
    required String tag,
    required ReleaseVersion version,
    void Function(int received, int? total)? onProgress,
  }) async {
    progress = onProgress;
    if (failure != null) throw UpdateException(failure!);
    if (!ready) await gate.future;
    return File('pkg.apk');
  }
}

final _result = UpdateCheckResult(
  UpdateCheckStatus.available,
  latest: '1.2.2',
  tag: 'v1.2.2',
  version: ReleaseVersion.parse('1.2.2'),
);

void main() {
  for (final skin in _Skin.values) {
    for (final lang in ['zh', 'en']) {
      testWidgets('update dialog shows progress inline and installs '
          '(${skin.name}, $lang)', (tester) async {
        tester.view.physicalSize = const Size(360, 740) * 3;
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        final t = dictOf(Language.values.byName(lang));
        final installer = _FakeInstaller();
        final updater = _FakeUpdater(installer);
        await tester.pumpWidget(
          MaterialApp(
            theme: buildTheme(
              Brightness.light,
              ThemeColor.blue,
              platform: TargetPlatform.android,
              comicOutline: skin == _Skin.comic,
              neumorphic: skin == _Skin.neumorphic,
            ),
            home: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(1.3)),
                child: Scaffold(
                  body: UpdateDialog(
                    t: t,
                    result: _result,
                    updater: updater,
                    noticeContext: context,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(t['updateNow']!), findsOneWidget);
        expect(findTextClips(tester), isEmpty);

        await tester.tap(find.byKey(const ValueKey('update-start')));
        await tester.pump();
        updater.progress!(50, 200);
        await tester.pump();
        expect(find.byKey(const ValueKey('update-progress')), findsOneWidget);
        expect(
          find.text(t['updateDownloading']!.replaceAll('{percent}', '25')),
          findsOneWidget,
        );
        // Only the close button while downloading.
        expect(find.byKey(const ValueKey('update-start')), findsNothing);
        expect(findTextClips(tester), isEmpty);
        expect(tester.takeException(), isNull);

        updater.gate.complete();
        await tester.pumpAndSettle();
        expect(installer.installs, 1);
      });
    }
  }

  testWidgets('a ready package installs; permission asked plainly', (
    tester,
  ) async {
    final t = dictOf(Language.zh);
    final installer = _FakeInstaller(allowed: false);
    final updater = _FakeUpdater(installer, ready: true);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: UpdateDialog(
              t: t,
              result: _result,
              updater: updater,
              noticeContext: context,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(t['updateInstall']!), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('update-start')));
    await tester.pumpAndSettle();
    expect(find.text(t['updateAllowInstall']!), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('update-open-settings')));
    expect(installer.settingsOpened, 1);
    installer.allowed = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(installer.installs, 1);
  });

  testWidgets('a failure is one sentence', (tester) async {
    final t = dictOf(Language.zh);
    final updater = _FakeUpdater(
      _FakeInstaller(),
      failure: UpdateFailure.noSpace,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => UpdateDialog(
                  t: t,
                  result: _result,
                  updater: updater,
                  noticeContext: context,
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('update-start')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(t['updateFailedSpace']!), findsOneWidget);
    expect(find.byType(UpdateDialog), findsNothing);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });
}
