import 'package:compoise/models.dart';
import 'package:compoise/schedule_item.dart';
import 'package:compoise/screens/matrix_screen.dart';
import 'package:compoise/storage.dart';
import 'package:compoise/theme.dart';
import 'package:compoise/widgets/app_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'helpers.dart';
import 'support/text_clip_probe.dart';

enum _Skin { material, comic, neumorphic }

Widget _app(Store store, TargetPlatform platform, _Skin skin, Widget home) =>
    ChangeNotifierProvider.value(
      value: store,
      child: MaterialApp(
        locale: Locale(store.settings.language.name),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('en'), Locale('zh'), Locale('ja')],
        theme: buildTheme(
          Brightness.light,
          store.settings.themeColor,
          platform: platform,
          comicOutline: skin == _Skin.comic,
          neumorphic: skin == _Skin.neumorphic,
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

Future<void> _finish(WidgetTester tester, Store store) async {
  await tester.pumpWidget(const SizedBox());
  store.dispose();
  await tester.pump();
}

void main() {
  for (final skin in _Skin.values) {
    for (final language in Language.values) {
      testWidgets(
        'mobile selection only offers exit (${skin.name}, ${language.name})',
        (tester) async {
          await tester.binding.setSurfaceSize(const Size(360, 800));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(360, 800);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          final (store, _) = await makeStore(
            settings: AppSettings(language: language),
          );
          store.addTasks([store.newTask('Synthetic task')]);
          await tester.pumpWidget(
            _app(store, TargetPlatform.android, skin, const MatrixHome()),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('more-btn')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('select-tasks-btn')));
          await tester.pumpAndSettle();
          for (final selected in [false, true]) {
            if (selected) {
              await tester.tap(find.text('Synthetic task'));
              await tester.pumpAndSettle();
            }
            final withinBar = find
                .ancestor(
                  of: find.byKey(const ValueKey('exit-selection-btn')),
                  matching: find.byType(Row),
                )
                .first;
            expect(
              find.descendant(of: withinBar, matching: find.byType(IconButton)),
              findsOneWidget,
            );
            expect(
              find.byKey(const ValueKey('exit-selection-btn')),
              findsOneWidget,
            );
            expect(find.byKey(const ValueKey('more-btn')), findsNothing);
            expect(find.byKey(const ValueKey('more-panel')), findsNothing);
            final barRect = tester.getRect(withinBar);
            expect(
              findTextClips(
                tester,
              ).where((clip) => clip.rect.overlaps(barRect)),
              isEmpty,
            );
            expect(tester.takeException(), isNull);
          }
          await tester.tap(find.byKey(const ValueKey('exit-selection-btn')));
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('more-btn')), findsOneWidget);
          await _finish(tester, store);
        },
      );
    }
    for (final platform in [
      TargetPlatform.android,
      TargetPlatform.windows,
      TargetPlatform.linux,
    ]) {
      testWidgets(
        'home Today follows live schedule changes (${skin.name}, ${platform.name})',
        (tester) async {
          await tester.binding.setSurfaceSize(
            platform == TargetPlatform.android
                ? const Size(360, 800)
                : const Size(1200, 900),
          );
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final (store, _) = await makeStore(
            settings: AppSettings(language: Language.zh),
          );
          final task = store.newTask('准备会议材料', quadrant: qPlan);
          store.addTasks([task]);
          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);
          ScheduleItem at(DateTime day) => ScheduleItem.timeBlock(
            id: 'slot',
            taskId: task.id,
            startAt: DateTime(
              day.year,
              day.month,
              day.day,
              9,
            ).millisecondsSinceEpoch,
            endAt: DateTime(
              day.year,
              day.month,
              day.day,
              10,
            ).millisecondsSinceEpoch,
            timeZoneId: 'Asia/Shanghai',
          );
          store.addScheduleItem(at(today));
          await tester.pumpWidget(
            _app(store, platform, skin, const MatrixHome()),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('more-btn')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('today-btn')));
          await tester.pumpAndSettle();
          final row = find.byKey(ValueKey('today-item-${task.id}'));
          expect(row, findsOneWidget);
          expect(
            find.byKey(const ValueKey('today-section-scheduledToday')),
            findsOneWidget,
          );
          expect(findTextClips(tester), isEmpty);
          store.updateScheduleItem(
            at(DateTime(now.year, now.month, now.day + 1)),
            expectedRevision: store.scheduleRevision('slot'),
          );
          await tester.pumpAndSettle();
          expect(row, findsNothing);
          store.updateScheduleItem(
            at(today),
            expectedRevision: store.scheduleRevision('slot'),
          );
          await tester.pumpAndSettle();
          expect(row, findsOneWidget);
          store.deleteScheduleItem(
            'slot',
            expectedRevision: store.scheduleRevision('slot'),
          );
          await tester.pumpAndSettle();
          expect(row, findsNothing);
          expect(find.byKey(const ValueKey('today-celebration')), findsNothing);
          expect(store.tasks.single.plannedDate, isNull);
          expect(store.tasks.single.deadline, isNull);
          expect(store.tasks.single.quadrant, qPlan);
          expect(tester.takeException(), isNull);
          await _finish(tester, store);
        },
      );
    }

    for (final direction in [-1.0, 1.0]) {
      testWidgets(
        'notice swipes away horizontally (${skin.name}, $direction)',
        (tester) async {
          tester.platformDispatcher.accessibilityFeaturesTestValue =
              const FakeAccessibilityFeatures(accessibleNavigation: true);
          addTearDown(
            tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
          );
          final (store, _) = await makeStore();
          var undone = false;
          await tester.pumpWidget(
            _app(
              store,
              TargetPlatform.android,
              skin,
              Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () => showAppNotice(
                      context,
                      'Deleted',
                      actionLabel: 'Undo',
                      onAction: () => undone = true,
                    ),
                    child: const Text('go'),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('go'));
          await tester.pumpAndSettle();
          await tester.drag(find.byType(SnackBar), Offset(direction * 600, 0));
          await tester.pumpAndSettle();
          expect(find.byType(SnackBar), findsNothing);
          expect(undone, isFalse);
          expect(tester.takeException(), isNull);
          await _finish(tester, store);
        },
      );
    }
  }

  testWidgets(
    'notice expires under a dialog with system accessibility enabled',
    (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(accessibleNavigation: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      final (store, _) = await makeStore();
      await tester.pumpWidget(
        _app(
          store,
          TargetPlatform.android,
          _Skin.material,
          Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () {
                  showAppNotice(
                    context,
                    'Deleted',
                    actionLabel: 'Undo',
                    onAction: () {},
                  );
                  showDialog<void>(
                    context: context,
                    builder: (_) =>
                        const AlertDialog(content: Text('Dialog stays')),
                  );
                },
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsOneWidget);
      await tester.pump(kNoticeDuration);
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
      expect(find.text('Dialog stays'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _finish(tester, store);
    },
  );
}
