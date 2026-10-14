import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:compoise/import_preview/draft_model.dart';
import 'package:compoise/import_preview/draft_preview.dart';
import 'package:compoise/models.dart';
import 'package:compoise/theme.dart';

import 'import_preview_test.dart' show batch, imageJson, taskJson;
import 'support/text_clip_probe.dart';

DraftBatch selection() => batch()
  ..boardId = 'board'
  ..quadrant = 1;

Future<void> pumpReview(
  WidgetTester tester,
  DraftBatch value, {
  Future<void> Function(ImportSubmission)? submit,
  VoidCallback? cancel,
  TargetPlatform platform = TargetPlatform.android,
  String skin = 'default',
  Language language = Language.zh,
  Size size = const Size(360, 780),
  double keyboard = 0,
  double scale = 1,
  String? fontFamily,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
  final theme = buildTheme(
    Brightness.light,
    ThemeColor.purple,
    comicOutline: skin == 'comic',
    neumorphic: skin == 'neumorphic',
  ).copyWith(platform: platform);
  await tester.pumpWidget(
    RepaintBoundary(
      key: const ValueKey('review-boundary'),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: fontFamily == null
            ? theme
            : theme.copyWith(
                textTheme: theme.textTheme.apply(fontFamily: fontFamily),
                primaryTextTheme: theme.primaryTextTheme.apply(
                  fontFamily: fontFamily,
                ),
              ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: DraftPreview(
            key: ObjectKey(value),
            batch: value,
            language: language,
            boards: const [ImportBoardChoice('board', 'My Tasks')],
            onSubmit: submit ?? (_) async {},
            onCancel: cancel ?? () {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder keyed(String key) => find.byKey(ValueKey(key));
bool enabled(WidgetTester tester) =>
    tester.widget<FilledButton>(keyed('import-submit')).onPressed != null;

Future<void> tap(WidgetTester tester, String key) async {
  await tester.ensureVisible(keyed(key));
  await tester.tap(keyed(key));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'default selection imports without per-item or duplicate approval',
    (tester) async {
      addTearDown(tester.view.reset);
      final value = selection();
      ImportSubmission? result;
      await pumpReview(
        tester,
        value,
        submit: (snapshot) async => result = snapshot,
      );
      expect(value.activeTasks, hasLength(4));
      expect(enabled(tester), isTrue);
      expect(find.byKey(const ValueKey('confirm-one:3')), findsNothing);
      expect(keyed('duplicate-0'), findsNothing);
      expect(keyed('parent-one:3'), findsNothing);
      expect(keyed('title-one:dropped:0:0'), findsNothing);
      expect(find.text('可能重复'), findsWidgets);
      expect(find.text('导入 4 项'), findsOneWidget);
      await tap(tester, 'import-submit');
      expect(result!.tasks, hasLength(4));
      expect(result!.tasks.first.dueText, isNull);
      expect(enabled(tester), isFalse);
    },
  );

  testWidgets(
    'edit, deselect, restore other text and keep completion separate',
    (tester) async {
      addTearDown(tester.view.reset);
      final value = selection();
      await pumpReview(tester, value);
      await tester.enterText(keyed('title-one:3'), '改过的任务');
      await tester.pump();
      expect(enabled(tester), isTrue);
      await tap(tester, 'exclude-one:3');
      expect(value.images.first.tasks[1].excluded, isTrue);
      expect(value.images.first.tasks[2].parentId, isNull);
      expect(find.text('导入 3 项'), findsOneWidget);
      await tap(tester, 'exclude-one:3');
      expect(value.images.first.tasks[1].title, '改过的任务');
      await tap(tester, 'import-other-one');
      final other = value.images.first.tasks.first;
      await tap(tester, 'exclude-${other.id}');
      expect(other.excluded, isFalse);
      expect(find.text('导入 5 项'), findsOneWidget);
      await tap(tester, 'options-one:3');
      await tap(tester, 'checked-one:3');
      expect(value.images.first.tasks[1].checked, isTrue);
      expect(value.images.first.tasks[1].excluded, isFalse);
      expect(enabled(tester), isTrue);
    },
  );

  testWidgets(
    'more keeps split, merge, parent and literal date note available',
    (tester) async {
      addTearDown(tester.view.reset);
      final value = selection();
      await pumpReview(tester, value);
      await tester.enterText(keyed('title-one:3'), 'Milk\nBread');
      await tap(tester, 'options-one:3');
      await tap(tester, 'split-one:3');
      expect(value.activeTasks, hasLength(5));
      expect(enabled(tester), isTrue);
      await tap(tester, 'options-one:edit:0');
      await tap(tester, 'merge-one:edit:0');
      expect(value.images.first.tasks[1].title, 'Milk Bread');
      expect(value.activeTasks, hasLength(4));
      await tap(tester, 'keep-due-one:3');
      expect(value.snapshot().tasks.first.dueText, 'today 18:00');
      await tap(tester, 'options-one:4');
      await tap(tester, 'parent-one:4');
      await tester.tap(find.text('无父任务').last);
      await tester.pumpAndSettle();
      expect(value.images.first.tasks.last.parentId, isNull);
      expect(enabled(tester), isTrue);
    },
  );

  testWidgets(
    'image order and skip remain available; duplicate hints do not block',
    (tester) async {
      addTearDown(tester.view.reset);
      final value = selection();
      await pumpReview(tester, value);
      await tap(tester, 'image-down-one');
      expect(value.images.map((image) => image.id), ['broken', 'one', 'two']);
      await tap(tester, 'image-skip-one');
      expect(value.activeTasks, hasLength(2));
      expect(enabled(tester), isTrue);
      await tap(tester, 'image-skip-one');
      expect(value.activeTasks, hasLength(4));
      expect(enabled(tester), isTrue);
    },
  );

  testWidgets(
    'invalid title, destination, parent and empty selection block import',
    (tester) async {
      addTearDown(tester.view.reset);
      var calls = 0;
      for (final condition in [
        'title',
        'board',
        'quadrant',
        'parent',
        'empty',
        'failed',
      ]) {
        final value = selection();
        if (condition == 'title') value.activeTasks.first.title = ' ';
        if (condition == 'board') value.boardId = 'deleted';
        if (condition == 'quadrant') value.quadrant = null;
        if (condition == 'parent') value.activeTasks.first.parentId = 'missing';
        if (condition == 'empty') {
          for (final image in value.images) {
            image.skipped = true;
          }
        }
        if (condition == 'failed') {
          for (final image in value.images.where((image) => !image.failed)) {
            image.skipped = true;
          }
        }
        await pumpReview(tester, value, submit: (_) async => calls++);
        expect(enabled(tester), isFalse, reason: condition);
        expect(tester.takeException(), isNull);
      }
      expect(calls, 0);
    },
  );

  testWidgets(
    'failed save keeps edits, shows one short notice and retries once',
    (tester) async {
      addTearDown(tester.view.reset);
      final value = selection();
      var calls = 0;
      await pumpReview(
        tester,
        value,
        submit: (_) async {
          if (++calls == 1) throw StateError('synthetic save failure');
        },
      );
      await tester.enterText(keyed('title-one:3'), '保留修改');
      await tap(tester, 'import-submit');
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('任务没能保存，请重试。'), findsOneWidget);
      expect(enabled(tester), isTrue);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
      expect(value.activeTasks.first.title, '保留修改');
      await tap(tester, 'import-submit');
      expect(calls, 2);
      expect(find.byType(SnackBar), findsNothing);
    },
  );

  testWidgets(
    'saving blocks cancellation and edits, and submits at most once',
    (tester) async {
      addTearDown(tester.view.reset);
      final gate = Completer<void>();
      var calls = 0, cancels = 0;
      await pumpReview(
        tester,
        selection(),
        submit: (_) async {
          calls++;
          await gate.future;
        },
        cancel: () => cancels++,
      );
      final action = tester
          .widget<FilledButton>(keyed('import-submit'))
          .onPressed!;
      action();
      action();
      await tester.pump();
      expect(enabled(tester), isFalse);
      expect(
        tester.widget<OutlinedButton>(keyed('import-cancel')).onPressed,
        isNull,
      );
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: keyed('title-one:3'),
                matching: find.byType(TextField),
              ),
            )
            .readOnly,
        isTrue,
      );
      gate.complete();
      await tester.pumpAndSettle();
      action();
      expect(calls, 1);
      expect(cancels, 0);
    },
  );

  testWidgets(
    'keyboard editing stays in the title; focused import uses Enter',
    (tester) async {
      addTearDown(tester.view.reset);
      var calls = 0;
      await pumpReview(
        tester,
        selection(),
        platform: TargetPlatform.windows,
        size: const Size(1200, 900),
        submit: (_) async => calls++,
      );
      await tester.tap(keyed('title-one:3'));
      await tester.enterText(keyed('title-one:3'), 'Edited');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(calls, 0);
      final target = tester.element(keyed('import-submit'));
      for (var i = 0; i < 80; i++) {
        final focus = FocusManager.instance.primaryFocus?.context;
        var reached = false;
        void visit(Element element) {
          if (element == focus) reached = true;
          if (!reached) element.visitChildren(visit);
        }

        visit(target);
        if (reached) break;
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(calls, 1);
    },
  );

  for (final platform in [
    TargetPlatform.android,
    TargetPlatform.windows,
    TargetPlatform.linux,
  ]) {
    for (final skin in ['default', 'comic', 'neumorphic']) {
      for (final language in Language.values) {
        testWidgets(
          '$platform/$skin/$language fixed footer and vertical review at 1.3x',
          (tester) async {
            addTearDown(tester.view.reset);
            final desktop = platform != TargetPlatform.android;
            await pumpReview(
              tester,
              selection(),
              platform: platform,
              skin: skin,
              language: language,
              scale: 1.3,
              keyboard: desktop ? 0 : 280,
              size: desktop ? const Size(1200, 900) : const Size(360, 780),
            );
            expect(tester.takeException(), isNull);
            expect(findTextClips(tester), isEmpty);
            final title = tester.getRect(keyed('title-one:3'));
            for (final key in ['exclude-one:3', 'options-one:3']) {
              expect(
                (tester.getRect(keyed(key)).center.dy - title.center.dy).abs(),
                lessThan(1),
                reason: '$skin $key aligns with the title',
              );
            }
            final buttonBefore = tester.getRect(keyed('import-submit'));
            expect(buttonBefore.bottom, lessThanOrEqualTo(desktop ? 900 : 500));
            expect(buttonBefore.height, greaterThanOrEqualTo(48));
            await tester.drag(
              keyed('import-review-scroll'),
              const Offset(0, -220),
            );
            await tester.pumpAndSettle();
            expect(tester.getRect(keyed('import-submit')), buttonBefore);
            expect(findTextClips(tester), isEmpty);
            final board = tester.getRect(keyed('import-board'));
            final quadrant = tester.getRect(keyed('import-quadrant'));
            expect(
              desktop
                  ? (board.top - quadrant.top).abs() < 1
                  : board.bottom < quadrant.top,
              isTrue,
            );
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  testWidgets(
    'review visual evidence in three themes',
    (tester) async {
      addTearDown(tester.view.reset);
      final output = Platform.environment['COMPOISE_REVIEW_SCREENSHOTS'];
      if (output == null) return;
      // Flutter widget tests use Ahem. Optional exports load real local fonts
      // so the screenshots can be reviewed, without changing the app's fonts.
      await tester.runAsync(() async {
        for (final entry in {
          'ReviewEvidence': Platform.environment['COMPOISE_REVIEW_FONT']!,
          'MaterialIcons': Platform.environment['COMPOISE_REVIEW_ICONS']!,
        }.entries) {
          final loader = FontLoader(entry.key)
            ..addFont(
              Future.value(
                ByteData.sublistView(await File(entry.value).readAsBytes()),
              ),
            );
          await loader.load();
        }
      });
      for (final skin in ['default', 'comic', 'neumorphic']) {
        final value =
            DraftBatch.fromJson(
                imageJson('one', [
                  taskJson(row: 1, title: '整理季度报告'),
                  taskJson(row: 2, title: '确认会议安排'),
                  taskJson(row: 3, title: '买牛奶', checked: true),
                ]),
              )
              ..boardId = 'board'
              ..quadrant = 1;
        await pumpReview(
          tester,
          value,
          skin: skin,
          scale: 1.3,
          fontFamily: 'ReviewEvidence',
        );
        expect(findTextClips(tester), isEmpty);
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          keyed('review-boundary'),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          try {
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File(
              '$output/review-$skin.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
          } finally {
            image.dispose();
          }
        });
      }
    },
    skip: Platform.environment['COMPOISE_REVIEW_SCREENSHOTS'] == null,
  );
}
