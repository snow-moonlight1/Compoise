import 'dart:convert';

import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Creates a Store backed by mock SharedPreferences with the given seed data.
Future<(Store, Map<String, Object>)> makeStore({
  List<Board>? boards,
  List<Task>? tasks,
  AppSettings? settings,
  AIConfig? aiConfig,
  List<Locale>? deviceLocales,
}) async {
  final backend = <String, Object>{
    if (boards != null) 'matrixflow-boards': jsonEncode(boards.map((b) => b.toJson()).toList()),
    if (tasks != null) 'matrixflow-tasks': jsonEncode(tasks.map((t) => t.toJson()).toList()),
    if (settings != null) 'matrixflow-settings': jsonEncode(settings.toJson()),
    if (aiConfig != null) 'matrixflow-config': jsonEncode(aiConfig.toJson()),
  };
  SharedPreferences.setMockInitialValues(backend);
  final store = Store(deviceLocales: deviceLocales);
  await store.init();
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
