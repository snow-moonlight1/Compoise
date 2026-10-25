import 'package:flutter_test/flutter_test.dart';
import 'package:compoise/l10n.dart';
import 'package:compoise/models.dart';
import 'package:compoise/planner/schedule_edit_session.dart';
import 'package:compoise/schedule_item.dart';
import 'package:compoise/schedule_time.dart';
import 'planner_test_support.dart';

Future<void> _detail(WidgetTester tester, {String id = 'block'}) =>
    c2Tap(tester, c2Key('schedule-item-2026-09-30-$id'));

void main() {
  testWidgets(
    'an unknown zone is still rejected, and the form no longer asks for one',
    (tester) async {
      final store = await c2Store();
      final before = c2Library(store);
      final session = ScheduleEditSession.edit(
        store,
        store.scheduleItems.first,
      );
      session.timeZoneId = 'Bad/Zone';
      expect(
        () => session.review(),
        throwsA(
          isA<ScheduleTimeException>().having(
            (error) => error.reason,
            'reason',
            ScheduleTimeError.unknownZone,
          ),
        ),
      );
      await c2Pump(tester, store);
      await _detail(tester);
      await c2Tap(tester, c2Key('schedule-detail-edit'));
      expect(c2Key('schedule-editor-zone'), findsNothing);
      expect(tester.takeException(), isNull);
      await c2Tap(tester, c2Key('schedule-editor-cancel'));
      expect(c2Library(store), before);
      await c2Finish(tester, store);
    },
  );

  for (final delete in [false, true]) {
    testWidgets(
      'external ${delete ? 'deletion' : 'edit'} saves nothing and says the form is stale',
      (tester) async {
        final store = await c2Store();
        final item = store.scheduleItems.first;
        await c2Pump(tester, store);
        await _detail(tester);
        await c2Tap(tester, c2Key('schedule-detail-edit'));
        if (delete) {
          store.deleteScheduleItem(
            item.id,
            expectedRevision: store.scheduleRevision(item.id),
          );
        } else {
          store.updateScheduleItem(
            ScheduleItem.fromJson({
              ...item.toJson(),
              'startAt': item.startAt + 1,
            }),
            expectedRevision: store.scheduleRevision(item.id),
          );
        }
        await tester.pumpAndSettle();
        final before = c2Library(store);
        // Saving a form whose record changed underneath says so and writes
        // nothing.
        await c2Tap(tester, c2Key('schedule-editor-save'));
        expect(find.text(store.t['scheduleEditorStale']!), findsOneWidget);
        expect(c2Library(store), before);
        await c2Tap(tester, c2Key('schedule-editor-cancel'));
        await c2Finish(tester, store);
      },
    );
  }

  testWidgets('recovery Planner exposes no create or edit controls', (
    tester,
  ) async {
    final store = await c2Store(recovery: true);
    await c2Pump(tester, store);
    expect(find.text(store.t['scheduleRecovery']!), findsOneWidget);
    expect(c2Key('schedule-add'), findsNothing);
    await c2Finish(tester, store);
  });

  test(
    'all editor strings are translated without touching other dictionary regions',
    () {
      final keys = dictOf(
        Language.en,
      ).keys.where((key) => key.startsWith('scheduleEditor'));
      for (final language in Language.values) {
        for (final key in keys) {
          expect(dictOf(language)[key], isNotEmpty);
        }
      }
    },
  );
}
