import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:compoise/models.dart';
import 'package:compoise/storage.dart';
import 'helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<Store> seed(DateTime Function() clock, {int threshold = 1}) async {
    final deadline = DateTime(2060, 10, 16, 17, 25).millisecondsSinceEpoch;
    SharedPreferences.setMockInitialValues({
      'compoise-boards': jsonEncode([
        Board(id: 'b', name: 'Synthetic', createdAt: 1).toJson(),
      ]),
      'compoise-settings': jsonEncode(
        AppSettings(urgencyThresholdDays: threshold).toJson(),
      ),
      'compoise-tasks': jsonEncode([
        for (final quadrant in [qPlan, qEliminate])
          Task(
            id: 'q$quadrant',
            boardId: 'b',
            title: 'Auto $quadrant',
            quadrant: quadrant,
            createdAt: 1,
            deadline: deadline,
          ).toJson(),
        Task(
          id: 'manual',
          boardId: 'b',
          title: 'Manual',
          quadrant: qPlan,
          createdAt: 1,
          deadline: deadline,
          urgencyMode: UrgencyMode.manual,
        ).toJson(),
        Task(
          id: 'done',
          boardId: 'b',
          title: 'Done',
          quadrant: qPlan,
          createdAt: 1,
          deadline: deadline,
          completed: true,
        ).toJson(),
        Task(
          id: 'no-date',
          boardId: 'b',
          title: 'No deadline',
          quadrant: qPlan,
          createdAt: 1,
        ).toJson(),
      ]),
    });
    final store = Store(deadlineClock: clock);
    registerTestStore(store);
    await store.init();
    return store;
  }

  int quadrant(Store s, String id) =>
      s.tasks.firstWhere((t) => t.id == id).quadrant;
  void expectPromoted(Store store) {
    expect(quadrant(store, 'q2'), qDo);
    expect(quadrant(store, 'q4'), qDelegate);
    for (final id in ['manual', 'done', 'no-date']) {
      expect(quadrant(store, id), qPlan);
    }
  }

  test(
    'startup promotes at the inclusive calendar-day threshold and persists',
    () async {
      final store = await seed(() => DateTime(2060, 10, 15, 0, 1));
      addTearDown(store.dispose);
      expectPromoted(store);
      expect((await store.flush(waitForReminders: false)).success, isTrue);
      final restored = Store(deadlineClock: () => DateTime(2060, 10, 15, 0, 1));
      registerTestStore(restored);
      await restored.init();
      addTearDown(restored.dispose);
      expectPromoted(restored);
    },
  );

  testWidgets(
    'hourly check detects a new calendar day without waiting in real time',
    (tester) async {
      var now = DateTime(2060, 10, 14, 23, 50);
      final store = await seed(() => now);
      expect(quadrant(store, 'q2'), qPlan);
      expect(quadrant(store, 'q4'), qEliminate);
      now = DateTime(2060, 10, 15, 0, 1);
      await tester.pump(const Duration(hours: 1));
      expectPromoted(store);
      final revision = store.taskSeq('q2');
      await tester.pump(const Duration(hours: 1));
      expect(store.taskSeq('q2'), revision);
      store.dispose();
      await tester.pump();
    },
  );

  test(
    'returning to foreground and changing the threshold both recheck immediately',
    () async {
      var now = DateTime(2060, 10, 14, 12);
      final store = await seed(() => now);
      addTearDown(store.dispose);
      expect(quadrant(store, 'q2'), qPlan);
      store.updateSettings((s) => s..urgencyThresholdDays = 2);
      expectPromoted(store);
      final other = await seed(() => now);
      addTearDown(other.dispose);
      expect(quadrant(other, 'q2'), qPlan);
      now = DateTime(2060, 10, 15, 8);
      other.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expectPromoted(other);
    },
  );

  test(
    'editing a deadline and restoring automatic urgency apply the threshold',
    () async {
      final now = DateTime(2060, 10, 14, 12);
      final store = await seed(() => now);
      addTearDown(store.dispose);
      store.updateTask(
        Task.fromJson(store.tasks.firstWhere((t) => t.id == 'q2').toJson())
          ..deadline = DateTime(2060, 10, 15, 9, 10).millisecondsSinceEpoch,
      );
      expect(quadrant(store, 'q2'), qDo);
      store.resetTaskUrgencyMode('manual');
      expect(quadrant(store, 'manual'), qPlan); // Still two calendar days away.
      store.updateSettings((s) => s..urgencyThresholdDays = 2);
      expect(quadrant(store, 'manual'), qDo);
    },
  );
}
