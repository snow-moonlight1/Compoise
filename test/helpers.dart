import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stores whose current test case still owes them a save.
final List<Store> _caseStores = <Store>[];
bool _drainRegistered = false;

/// Enrolls [store] so every save it queued lands before the case ends.
///
/// `SharedPreferences.setMockInitialValues` replaces the process-global
/// platform store, but a `SharedPreferences` handle resolves that store on
/// every call. A whole-library commit the previous case left in flight
/// therefore lands in the next case's mock, and that case boots from the
/// previous library instead of its own seed.
///
/// [makeStore] enrolls the store it builds. A test that opens a `Store`
/// directly can call this to get the same guarantee; the drain only waits for
/// work the store already queued, so it never commits state a test left
/// deliberately dirty.
void registerTestStore(Store store) {
  if (_caseStores.contains(store)) return;
  _caseStores.add(store);
  if (_drainRegistered) return;
  _drainRegistered = true;
  addTearDown(drainTestStores);
}

/// Settles every enrolled store, so no write can outlive the case that queued
/// it.
///
/// Reminder delivery is not awaited: its ledger performs real file I/O, which
/// stalls under the `testWidgets` fake clock, and no reminder path dirties the
/// library. Stores the case already disposed are drained too, because
/// `Store.dispose` stops the queue without waiting for the batch in flight.
Future<void> drainTestStores() async {
  _drainRegistered = false;
  final stores = List<Store>.of(_caseStores);
  _caseStores.clear();
  for (final store in stores) {
    await store.flush(waitForReminders: false);
  }
}

/// Creates a Store backed by mock SharedPreferences with the given seed data.
///
/// The returned store has no save outstanding: `Store.init` only queues its
/// trailing whole-library commit, so the helper flushes it before handing the
/// store back. [saveWriter] replaces the Store's own write path, letting a
/// test see when the library bytes actually reach the mock platform store; it
/// defaults to null, which keeps every existing caller on the plain
/// SharedPreferences route.
Future<(Store, Map<String, Object>)> makeStore({
  List<Board>? boards,
  List<Task>? tasks,
  AppSettings? settings,
  AIConfig? aiConfig,
  List<Locale>? deviceLocales,
  bool hasSeenOnboarding = true,
  SaveWrite? saveWriter,
}) async {
  final backend = <String, Object>{
    if (boards != null) 'matrixflow-boards': jsonEncode(boards.map((b) => b.toJson()).toList()),
    if (tasks != null) 'matrixflow-tasks': jsonEncode(tasks.map((t) => t.toJson()).toList()),
    if (settings != null) 'matrixflow-settings': jsonEncode(settings.toJson()),
    if (aiConfig != null) 'matrixflow-config': jsonEncode(aiConfig.toJson()),
    'matrixflow-has-seen-onboarding': hasSeenOnboarding,
  };
  SharedPreferences.setMockInitialValues(backend);
  final store = Store(
    deviceLocales: deviceLocales,
    saveWriter: saveWriter,
  );
  registerTestStore(store);
  await store.init();
  await store.flush(waitForReminders: false);
  return (store, backend);
}

extension StoreTestHooks on Store {
  /// Exposes the private promotion pass for deterministic tests.
  void applyDeadlinePromotionForTest() {
    // Deadline promotion runs on init; this re-triggers it by touching state.
    // The logic itself is private, so emulate one timer tick via a no-op
    // settings update followed by the internal check that init performs.
    updateSettings((s) => s);
    promoteDeadlinesNow();
  }
}
