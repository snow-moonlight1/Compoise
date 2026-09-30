import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/import_preview/draft_model.dart';
import 'package:matrixflow_native/import_preview/draft_preview.dart';
import 'package:matrixflow_native/l10n.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/screens/matrix_screen.dart';
import 'package:matrixflow_native/screenshot_import/screenshot_backend.dart';
import 'package:matrixflow_native/screenshot_import/screenshot_capture.dart';
import 'package:matrixflow_native/screenshot_import/screenshot_import_page.dart';
import 'package:matrixflow_native/storage.dart';
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
}) => ChangeNotifierProvider.value(
  value: store,
  child: MaterialApp(
    theme: ThemeData(platform: platform),
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

void main() {
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
        expect(tester.widget<FilledButton>(button).onPressed, isNull);
        await tester.tap(find.byKey(const ValueKey('import-quadrant')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.textContaining(dictOf(language)['q1Short']!).last,
        );
        await tester.pumpAndSettle();
        final checkbox = find.byKey(const ValueKey('confirm-root'));
        await tester.ensureVisible(checkbox);
        await tester.tap(checkbox);
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

        final backend = FakeBackend()..problem = 'ModelsMissing';
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
          find.text(dictOf(language)['screenshotImportModelsMissing']!),
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
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(
      find.text(dictOf(Language.en)['importSubmitFailed']!),
      findsOneWidget,
    );
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
      final confirm = find.byKey(const ValueKey('confirm-root'));
      await tester.ensureVisible(confirm);
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      final submit = find.byKey(const ValueKey('import-submit'));
      await tester.ensureVisible(submit);
      expect(tester.widget<FilledButton>(submit).onPressed, isNull);
      expect(tester.takeException(), isNull);
      expect(store.tasks, isEmpty);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      store.dispose();
    });
  }
}
