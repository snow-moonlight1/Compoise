import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:compoise/import_preview/draft_model.dart';
import 'package:compoise/import_preview/draft_preview.dart';
import 'package:compoise/l10n.dart';
import 'package:compoise/models.dart';
import 'package:compoise/screens/matrix_screen.dart';
import 'package:compoise/screenshot_import/screenshot_backend.dart';
import 'package:compoise/screenshot_import/screenshot_capture.dart';
import 'package:compoise/screenshot_import/screenshot_import_page.dart';
import 'package:compoise/storage.dart';
import 'package:compoise/theme.dart';
import 'package:provider/provider.dart';

import 'helpers.dart';

class FakeBackend implements ScreenshotBackend {
  String? problem;
  ScreenshotCaptureResult result = const ScreenshotCaptureResult(
    cancelled: true,
  );
  Completer<ScreenshotCaptureResult>? pending;
  int picks = 0, cancels = 0, disposals = 0;
  @override
  Future<String?> availability() async => problem;
  @override
  Future<ScreenshotCaptureResult> capture(
    void Function(int, int) progress,
  ) async {
    picks++;
    progress(0, 2);
    return pending == null ? result : await pending!.future;
  }

  @override
  void cancel() {
    cancels++;
  }

  @override
  Future<void> dispose() async {
    disposals++;
    cancel();
  }
}

Widget app(
  Store store,
  Widget home, {
  TargetPlatform platform = TargetPlatform.android,
  double keyboard = 0,
  double scale = 1,
  ThemeData? theme,
  NavigatorObserver? observer,
}) => ChangeNotifierProvider.value(
  value: store,
  child: MaterialApp(
    theme: theme ?? ThemeData(platform: platform),
    navigatorObservers: [if (observer != null) observer],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    supportedLocales: const [Locale('en'), Locale('zh'), Locale('ja')],
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        viewInsets: EdgeInsets.only(bottom: keyboard),
        textScaler: TextScaler.linear(scale),
      ),
      child: child!,
    ),
    home: home,
  ),
);

DraftBatch draft() => DraftBatch(
  images: [
    DraftImage(
      id: 'image-1',
      tasks: [
        DraftTask(
          id: 'root',
          imageId: 'image-1',
          sourceRow: 0,
          title: 'Synthetic task',
          checked: false,
        ),
      ],
    ),
    DraftImage(id: 'image-2', tasks: [], error: 'screenshotImportSafFileLimit'),
  ],
);

Future<Store> storeFor(Language language) async {
  final (store, _) = await makeStore(
    boards: [
      Board(id: 'board', name: 'Board', createdAt: 1),
      Board(id: 'other', name: 'Other', createdAt: 2),
    ],
    settings: AppSettings()..language = language,
  );
  await store.flush();
  return store;
}

class PopObserver extends NavigatorObserver {
  int pops = 0;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pops++;
  }
}

void main() {
  for (final platform in [
    TargetPlatform.android,
    TargetPlatform.windows,
    TargetPlatform.linux,
  ]) {
    for (final skin in ['default', 'comic', 'neumorphic']) {
      for (final exit in ['app bar', 'system', 'cancel', 'submit']) {
        testWidgets('$platform/$skin review $exit pops once; home stays usable', (
          tester,
        ) async {
          final store = await storeFor(Language.en);
          final batch = draft()..quadrant = 1;
          batch.activeTasks.first.confirmed = true;
          final backend = FakeBackend()
            ..result = ScreenshotCaptureResult(batch: batch);
          final observer = PopObserver();
          await tester.pumpWidget(
            app(
              store,
              Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ScreenshotImportPage(backend: backend),
                      ),
                    ),
                    child: const Text('Open'),
                  ),
                ),
              ),
              observer: observer,
              theme: buildTheme(
                Brightness.light,
                ThemeColor.purple,
                comicOutline: skin == 'comic',
                neumorphic: skin == 'neumorphic',
              ).copyWith(platform: platform),
            ),
          );
          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('screenshot-choose')));
          await tester.pumpAndSettle();
          switch (exit) {
            case 'app bar':
              await tester.tap(find.byType(BackButton));
            case 'system':
              await tester.binding.handlePopRoute();
            case 'cancel':
              final cancel = find.byKey(const ValueKey('import-cancel'));
              await tester.ensureVisible(cancel);
              // Two invocations before a frame must not pop the underlying home.
              final action = tester.widget<OutlinedButton>(cancel).onPressed!;
              action();
              action();
            case 'submit':
              final submit = find.byKey(const ValueKey('import-submit'));
              await tester.ensureVisible(submit);
              await tester.tap(submit);
          }
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.text('Open'), findsOneWidget);
          expect(find.byType(ScreenshotImportPage), findsNothing);
          expect(observer.pops, 1);
          expect(backend.disposals, 1);
          expect(store.tasks.length, exit == 'submit' ? 1 : 0);
          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();
          expect(find.byType(ScreenshotImportPage), findsOneWidget);
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
          store.dispose();
        });
      }
    }
  }

  testWidgets('system back stops capture before the exit animation ends', (
    tester,
  ) async {
    final store = await storeFor(Language.en);
    final backend = FakeBackend()
      ..pending = Completer<ScreenshotCaptureResult>();
    await tester.pumpWidget(
      app(
        store,
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ScreenshotImportPage(backend: backend),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('screenshot-choose')));
    await tester.pump();
    await tester.binding.handlePopRoute();
    expect(backend.cancels, 1);
    expect(backend.disposals, 0);
    // Finish while the exiting State is still mounted.
    backend.pending!.complete(ScreenshotCaptureResult(batch: draft()));
    await tester.pump();
    expect(find.byType(DraftPreview), findsNothing);
    await tester.pumpAndSettle();
    expect(find.text('Open'), findsOneWidget);
    expect(backend.disposals, 1);
    expect(store.tasks, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  for (final language in Language.values) {
    testWidgets(
      '$language More entry -> pick -> review -> single confirmed import',
      (tester) async {
        tester.view.physicalSize = const Size(400, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final store = await storeFor(language);

        final backend = FakeBackend()
          ..result = ScreenshotCaptureResult(batch: draft());
        await tester.pumpWidget(
          app(store, MatrixHome(screenshotBackend: backend)),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('more-btn')));
        await tester.pumpAndSettle();
        expect(
          find.text(dictOf(language)['screenshotImportTitle']!),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const ValueKey('more-screenshot-import')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('screenshot-choose')));
        await tester.pumpAndSettle();
        expect(find.byType(DraftPreview), findsOneWidget);
        expect(store.tasks, isEmpty);
        expect(
          find.text(dictOf(language)['screenshotImportSafFileLimit']!),
          findsOneWidget,
        );
        final button = find.byKey(const ValueKey('import-submit'));
        expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
        await tester.tap(find.byKey(const ValueKey('import-quadrant')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.textContaining(dictOf(language)['q1Short']!).last,
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(store.tasks.single.title, 'Synthetic task');
        expect(store.tasks.single.quadrant, 1);
        expect(find.byType(ScreenshotImportPage), findsNothing);
        expect(backend.disposals, 1);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        store.dispose();
      },
    );

    testWidgets(
      '$language unavailable / retry and narrow keyboard remain reachable',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final store = await storeFor(language);

        final backend = FakeBackend()..problem = 'NativeMissing';
        await tester.pumpWidget(
          app(
            store,
            ScreenshotImportPage(backend: backend),
            keyboard: 260,
            scale: 1.7,
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(dictOf(language)['screenshotImportNativeMissing']!),
          findsOneWidget,
        );
        final choose = find.byKey(const ValueKey('screenshot-choose'));
        expect(tester.widget<FilledButton>(choose).onPressed, isNull);
        expect(backend.picks, 0);
        final retry = find.byKey(const ValueKey('screenshot-retry'));
        backend.problem = null;
        await tester.ensureVisible(retry);
        await tester.tap(retry);
        await tester.pumpAndSettle();
        expect(tester.widget<FilledButton>(choose).onPressed, isNotNull);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        store.dispose();
      },
    );
  }

  testWidgets('missing models offer a verified download, then recheck', (
    tester,
  ) async {
    final store = await storeFor(Language.en);
    final backend = FakeBackend()..problem = 'ModelsMissing';
    var calls = 0;
    var fail = true;
    Future<void> fakeDownload({
      void Function(double progress)? onProgress,
    }) async {
      calls++;
      onProgress?.call(0.5);
      if (fail) throw Exception('offline');
      backend.problem = null;
    }

    await tester.pumpWidget(
      app(
        store,
        ScreenshotImportPage(backend: backend, downloadModels: fakeDownload),
      ),
    );
    await tester.pumpAndSettle();
    final choose = find.byKey(const ValueKey('screenshot-choose'));
    expect(tester.widget<FilledButton>(choose).onPressed, isNull);
    expect(find.byKey(const ValueKey('screenshot-retry')), findsNothing);
    final download = find.byKey(const ValueKey('ocr-model-download'));
    await tester.ensureVisible(download);
    await tester.tap(download);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('ocr-model-download-failed')),
      findsOneWidget,
    );
    fail = false;
    await tester.tap(download);
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(tester.widget<FilledButton>(choose).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    store.dispose();
  });

  testWidgets(
    'cancel pending capture and unmount suppress late result and writes',
    (tester) async {
      final store = await storeFor(Language.en);

      final backend = FakeBackend()
        ..pending = Completer<ScreenshotCaptureResult>();
      await tester.pumpWidget(
        app(
          store,
          Builder(
            builder: (ctx) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(ctx).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ScreenshotImportPage(backend: backend),
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('screenshot-choose')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('screenshot-cancel')));
      await tester.pumpAndSettle();
      backend.pending!.complete(ScreenshotCaptureResult(batch: draft()));
      await tester.pumpAndSettle();
      expect(store.tasks, isEmpty);
      expect(backend.disposals, 1);
      expect(backend.cancels, greaterThan(0));
      expect(find.byType(DraftPreview), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    },
  );

  testWidgets('live deleted destination cannot show successful submission', (
    tester,
  ) async {
    final store = await storeFor(Language.en);

    final batch = draft();
    batch.quadrant = 1;
    batch.activeTasks.first.confirmed = true;
    final backend = FakeBackend()
      ..result = ScreenshotCaptureResult(batch: batch);
    await tester.pumpWidget(app(store, ScreenshotImportPage(backend: backend)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('screenshot-choose')));
    await tester.pumpAndSettle();
    final selected = store.activeBoardId;
    store.deleteBoard(selected);
    await tester.pumpAndSettle();
    final submit = find.byKey(const ValueKey('import-submit'));
    await tester.ensureVisible(submit);
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);
    expect(store.tasks, isEmpty);
    expect(find.byType(DraftPreview), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    store.dispose();
  });
  for (final language in Language.values) {
    testWidgets('$language review at 320px with keyboard and large type', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = await storeFor(language);
      final backend = FakeBackend()
        ..result = ScreenshotCaptureResult(batch: draft());
      await tester.pumpWidget(
        app(
          store,
          ScreenshotImportPage(backend: backend),
          keyboard: 250,
          scale: 1.7,
        ),
      );
      await tester.pumpAndSettle();
      final choose = find.byKey(const ValueKey('screenshot-choose'));
      await tester.ensureVisible(choose);
      await tester.tap(choose);
      await tester.pumpAndSettle();
      final submit = find.byKey(const ValueKey('import-submit'));
      await tester.ensureVisible(submit);
      expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
      expect(store.tasks, isEmpty);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      store.dispose();
    });
  }
}
