import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/screens/completed_screen.dart';
import 'package:matrixflow_native/screens/matrix_screen.dart';
import 'package:matrixflow_native/screens/search_screen.dart';
import 'package:matrixflow_native/widgets/reminder_failure_banner.dart';
import 'helpers.dart';
import 'shortcuts_command_palette_test.dart' show wrapApp;

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    testWidgets('UX01: $platform home and focus have no retired entries', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await tester.binding.setSurfaceSize(
        platform == TargetPlatform.android
            ? const Size(390, 844)
            : const Size(1200, 900),
      );
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final (store, _) = await makeStore();
      await tester.pumpWidget(wrapApp(store, const MatrixHome()));
      await tester.pumpAndSettle();
      void verify() {
        expect(find.byKey(const ValueKey('command-palette-btn')), findsNothing);
        expect(find.byIcon(Icons.terminal_outlined), findsNothing);
        expect(find.byKey(const ValueKey('task-stats-bar')), findsNothing);
        expect(
          find.byKey(const ValueKey('stats-scope-toggle-btn')),
          findsNothing,
        );
        expect(find.byType(ReminderFailureBanner), findsOneWidget);
      }

      verify();
      for (final modifier in [
        LogicalKeyboardKey.control,
        LogicalKeyboardKey.meta,
      ]) {
        await tester.sendKeyDownEvent(modifier);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
        await tester.sendKeyUpEvent(modifier);
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsNothing);
        expect(
          find.byKey(const ValueKey('command-palette-input')),
          findsNothing,
        );
      }
      await tester.tap(find.byKey(const ValueKey('quadrant-header-1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('focus-back-btn')), findsOneWidget);
      verify();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('focus-back-btn')), findsNothing);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
      await tester.pumpAndSettle();
      expect(find.byType(SearchScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('UX01: $platform archive scopes are lists and restore works', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await tester.binding.setSurfaceSize(
        platform == TargetPlatform.android
            ? const Size(390, 844)
            : const Size(1200, 900),
      );
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final (store, _) = await makeStore(
        boards: [
          Board(id: 'b1', name: 'One', createdAt: 1),
          Board(id: 'b2', name: 'Two', createdAt: 1),
        ],
        tasks: [
          Task(
            id: 'a',
            boardId: 'b1',
            title: 'Done A',
            quadrant: 1,
            createdAt: 1,
            completed: true,
            completedAt: 1000,
          ),
          Task(
            id: 'b',
            boardId: 'b2',
            title: 'Done B',
            quadrant: 2,
            createdAt: 2,
            completed: true,
            completedAt: 2000,
          ),
          Task(
            id: 'c',
            boardId: 'b1',
            title: 'Pending C',
            quadrant: 3,
            createdAt: 3,
          ),
        ],
      );
      await tester.pumpWidget(
        wrapApp(store, const CompletedScreen(initialBoardId: 'b1')),
      );
      await tester.pumpAndSettle();
      void verifyCount(int n) {
        expect(
          find.text(store.t['completedCount']!.replaceAll('{n}', '$n')),
          findsOneWidget,
        );
        expect(find.textContaining('%'), findsNothing);
        expect(find.text('Completion Trends'), findsNothing);
        expect(find.byType(LinearProgressIndicator), findsNothing);
        expect(find.byType(ReminderFailureBanner), findsOneWidget);
      }

      verifyCount(1);
      await tester.tap(find.byKey(const ValueKey('filter-open-btn')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('completed-scope-all')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('filter-apply-btn')));
      await tester.pumpAndSettle();
      verifyCount(2);
      expect(find.byKey(const ValueKey('completed-time-b')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('completed-restore-b')));
      await tester.pumpAndSettle();
      expect(store.tasks.singleWhere((t) => t.id == 'b').completed, isFalse);
      verifyCount(1);
      await tester.tap(find.byKey(const ValueKey('filter-open-btn')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('completed-scope-current')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('filter-apply-btn')));
      await tester.pumpAndSettle();
      verifyCount(1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
