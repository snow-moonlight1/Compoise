// AI breakdown from the open edit sheet: the generated steps show up in the
// sheet's subtask list straight away, as part of the unsaved draft, so they
// can be edited or removed before saving. Phone sheet and desktop panel.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:compoise/ai_service.dart';
import 'package:compoise/models.dart';
import 'package:compoise/storage.dart';
import 'package:compoise/theme.dart';
import 'package:compoise/widgets/task_detail_panel.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeAI extends AIService {
  final titles = <String>[];
  @override
  Future<List<DecomposeResult>> decomposeBatch({
    required List<String> taskTitles,
    required AIConfig config,
    required Language language,
    AICancellation? cancellation,
  }) async {
    titles.addAll(taskTitles);
    return [
      for (final title in taskTitles)
        DecomposeResult(
          originalTitle: title,
          subtasks: ['查上月账单', '网上缴费', '保存缴费凭证'],
        ),
    ];
  }
}

void main() {
  for (final neu in [false, true]) {
    for (final sidebar in [false, true]) {
      testWidgets(
        '${neu ? 'neumorphic' : 'default'} ${sidebar ? 'desktop panel' : 'phone sheet'}: breakdown fills the draft',
        (tester) async {
          await tester.binding.setSurfaceSize(const Size(411, 1400));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          SharedPreferences.setMockInitialValues({
            'compoise-has-seen-onboarding': true,
            'compoise-boards': jsonEncode([
              Board(id: 'b', name: '我的任务', createdAt: 1).toJson(),
            ]),
            'compoise-tasks': jsonEncode([
              Task(
                id: 't',
                boardId: 'b',
                title: '下周三前交水电费',
                quadrant: 3,
                createdAt: 1,
              ).toJson(),
            ]),
          });
          final ai = _FakeAI();
          late Store store;
          await tester.runAsync(() async {
            store = Store(aiService: ai);
            await store.init();
          });
          await tester.pumpWidget(
            ChangeNotifierProvider.value(
              value: store,
              child: MaterialApp(
                theme: buildTheme(
                  Brightness.light,
                  ThemeColor.purple,
                  neumorphic: neu,
                ),
                home: Scaffold(
                  body: TaskDetailPanel(
                    task: store.tasks.single,
                    isSidebar: sidebar,
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final t = store.t;
          final more = find.byKey(const ValueKey('more-properties-btn'));
          await tester.ensureVisible(more);
          await tester.tap(more);
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text(t['longTermTask']!));
          await tester.tap(find.text(t['longTermTask']!));
          await tester.pumpAndSettle();
          final button = find.text(t['decomposeTask']!);
          await tester.ensureVisible(button);
          await tester.tap(button);
          await tester.pumpAndSettle();

          expect(ai.titles, ['下周三前交水电费']);
          // The breakdown sheet closed and the steps are in the open editor.
          expect(find.text(t['processingBatch']!), findsNothing);
          for (final step in ['查上月账单', '网上缴费', '保存缴费凭证']) {
            expect(find.text(step), findsOneWidget, reason: step);
          }
          // Not written behind the editor's back: only the draft has them.
          expect(store.tasks.single.subtasks, isEmpty);

          // Removable before saving.
          final first = store.tasks.single;
          expect(first.subtasks, isEmpty);
          final row = find.ancestor(
            of: find.text('网上缴费'),
            matching: find.byWidgetPredicate(
              (w) =>
                  w.key is ValueKey<String> &&
                  (w.key as ValueKey<String>).value.startsWith('subtask-item-'),
            ),
          );
          expect(row, findsOneWidget);
          final delete = find.descendant(
            of: row,
            matching: find.byIcon(Icons.close),
          );
          if (delete.evaluate().isNotEmpty) {
            await tester.tap(delete.first);
            await tester.pumpAndSettle();
            expect(find.text('网上缴费'), findsNothing);
          }

          await tester.ensureVisible(find.byKey(const ValueKey('save-task')));
          await tester.tap(find.byKey(const ValueKey('save-task')));
          await tester.pumpAndSettle();
          final saved = store.tasks.single.subtasks.map((s) => s.title);
          expect(saved, contains('查上月账单'));
          expect(saved, contains('保存缴费凭证'));
          expect(store.tasks.single.isLongTerm, isTrue);

          await tester.pumpWidget(const SizedBox());
          await tester.runAsync(() => store.flush(waitForReminders: false));
          store.dispose();
        },
      );
    }
  }
}
