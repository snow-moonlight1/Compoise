import 'package:compoise/models.dart';
import 'package:compoise/theme.dart';
import 'package:compoise/widgets/date_edit_fields.dart';
import 'package:compoise/widgets/task_edit_draft.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'helpers.dart';
import 'support/text_clip_probe.dart';
import 'support/time_picker_flow.dart';

void main() {
  test(
    'changing only the clock time is dirty and persists the exact new deadline',
    () {
      final task = Task(
        id: 't',
        boardId: 'b',
        title: 'Synthetic',
        quadrant: qPlan,
        createdAt: 1,
        deadline: DateTime(2060, 10, 14, 9, 15, 37).millisecondsSinceEpoch,
      );
      final draft = TaskEditDraft(task, onChanged: () {});
      addTearDown(draft.dispose);
      expect(draft.isDirty, isFalse);
      expect(draft.applyTo(task).deadline, task.deadline);
      draft.deadline = DateTime(2060, 10, 14, 14, 35);
      expect(draft.isDirty, isTrue);
      expect(
        draft.applyTo(task).deadline,
        DateTime(2060, 10, 14, 14, 35).millisecondsSinceEpoch,
      );
      expect(
        isAfterParentDay(DateTime(2060, 10, 14, 15), draft.deadline),
        isTrue,
      );
      expect(
        isAfterParentDay(DateTime(2060, 10, 14, 14), draft.deadline),
        isFalse,
      );
    },
  );

  for (final skin in ['default', 'comic', 'neumorphic']) {
    for (final platform in [
      TargetPlatform.android,
      TargetPlatform.windows,
      TargetPlatform.linux,
    ]) {
      testWidgets(
        'choose exact time, clear and cancel ($skin, ${platform.name})',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = platform == TargetPlatform.android
              ? const Size(360, 800)
              : const Size(1000, 850);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final (store, _) = await makeStore(
            settings: AppSettings(language: Language.zh),
          );
          TaskTimeSelection? result;
          final original = DateTime(2060, 10, 14, 15, 30, 45);
          await tester.pumpWidget(
            ChangeNotifierProvider.value(
              value: store,
              child: MaterialApp(
                theme: buildTheme(
                  Brightness.light,
                  store.settings.themeColor,
                  platform: platform,
                  comicOutline: skin == 'comic',
                  neumorphic: skin == 'neumorphic',
                ),
                locale: const Locale('zh'),
                supportedLocales: const [
                  Locale('en'),
                  Locale('zh'),
                  Locale('ja'),
                ],
                localizationsDelegates: GlobalMaterialLocalizations.delegates,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: const TextScaler.linear(1.3)),
                  child: child!,
                ),
                home: Scaffold(
                  body: Builder(
                    builder: (context) => TextButton(
                      onPressed: () async {
                        result = await showTaskTimeEditor(
                          context,
                          t: store.t,
                          deadline: original,
                        );
                      },
                      child: const Text('open'),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('open'));
          await tester.pumpAndSettle();
          expect(find.text('截止与提醒'), findsOneWidget);
          expect(find.byType(AlertDialog), findsOneWidget);
          // Phones edit in the same compact dialog as desktop, not a new page.
          expect(find.byType(Scaffold), findsOneWidget);
          expect(find.text('计划日'), findsNothing);
          expect(find.byKey(const ValueKey('deadline-today')), findsNothing);
          expect(
            find.byKey(const ValueKey('reminder-quick-tomorrow-9')),
            findsNothing,
          );
          expect(find.text('2060-10-14 15:30'), findsOneWidget);
          expect(findTextClips(tester), isEmpty);
          // Cancel the time picker after choosing a date: no partial deadline is applied.
          await tester.tap(find.byKey(const ValueKey('deadline-custom')));
          await tester.pumpAndSettle();
          final dateDialog = find.byType(DatePickerDialog);
          await tester.tap(
            find.descendant(of: dateDialog, matching: find.text('确定')),
          );
          await tester.pumpAndSettle();
          await tester.tap(
            find.descendant(
              of: find.byType(TimePickerDialog),
              matching: find.text('取消'),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('2060-10-14 15:30'), findsOneWidget);
          await chooseTaskMoment(
            tester,
            'deadline-custom',
            DateTime(2060, 10, 14, 18, 25),
          );
          await tester.tap(find.byKey(const ValueKey('time-confirm')));
          await tester.pumpAndSettle();
          expect(result!.deadline, DateTime(2060, 10, 14, 18, 25));
          expect(result!.reminderAt, isNull);
          await tester.tap(find.text('open'));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('deadline-clear')));
          await tester.tap(find.byKey(const ValueKey('time-confirm')));
          await tester.pumpAndSettle();
          expect(result!.deadline, isNull);
          await tester.pumpWidget(const SizedBox());
          store.dispose();
        },
      );
    }
  }
}
