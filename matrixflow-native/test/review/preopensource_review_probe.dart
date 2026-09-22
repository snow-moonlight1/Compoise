// Review counterexamples, 2026-09-20. Desired behavior is asserted, so these
// deliberately fail on the reviewed baseline. Run explicitly; do not add this
// file to the default suite until each corresponding implementation is fixed.
// All data and credentials are synthetic; no real files or network are used.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrixflow_native/ai_service.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/screens/settings_screen.dart';
import 'package:matrixflow_native/storage.dart';
import 'package:matrixflow_native/widgets/task_detail_panel.dart';
import 'package:matrixflow_native/widgets/task_exit.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers.dart';

Widget app(Store store, Widget child) => ChangeNotifierProvider.value(
  value: store,
  child: MaterialApp(home: Scaffold(body: child)),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('OS-R01: corrupt source is retained until recovery is resolved', () async {
    const corrupt = '[{"id":"recoverable","title":"unfinished';
    SharedPreferences.setMockInitialValues({
      'matrixflow-tasks': corrupt,
      'matrixflow-has-seen-onboarding': true,
    });
    final store = Store();
    addTearDown(store.dispose);
    await store.init();
    await store.flush();
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString('matrixflow-tasks'),
      corrupt,
      reason:
          'Startup must preserve the only recoverable source before saving defaults',
    );
  });

  test(
    'OS-R02: conflicting child IDs reject overwrite before mutation',
    () async {
      final (store, _) = await makeStore();
      addTearDown(store.dispose);
      store.addTasks([store.newTask('Existing data')]);
      final duplicate = store.newTask('Imported parent')
        ..subtasks = [
          SubTask(id: 'same-child', title: 'First'),
          SubTask(id: 'same-child', title: 'Second'),
        ];
      final payload = <String, dynamic>{
        'version': 2,
        'boards': store.boards.map((b) => b.toJson()).toList(),
        'tasks': [duplicate.toJson()],
      };
      expect(
        () => store.importData(payload, 'overwrite'),
        throwsFormatException,
      );
      expect(store.tasks.single.title, 'Existing data');
    },
  );

  test('OS-R03: custom model survives config round trip', () {
    final original = AIConfig(
      provider: 'custom',
      baseUrl: 'https://example.invalid/v1',
      model: 'gpt-4o-mini',
    );
    expect(AIConfig.fromJson(original.toJson()).model, original.model);
  });

  test('OS-R04: model discovery cache separates protocols', () async {
    var calls = 0;
    final service = AIService(
      client: MockClient((request) async {
        calls++;
        return http.Response(
          jsonEncode({
            'data': [
              {
                'id':
                    request.url.path == '/v1/models'
                        ? 'anthropic-model'
                        : 'chat-model',
              },
            ],
          }),
          200,
        );
      }),
    );
    addTearDown(service.close);
    final config = AIConfig(
      provider: 'custom',
      baseUrl: 'https://example.invalid',
      apiKey: 'synthetic-review-key',
      model: 'test-model',
    );
    await service.fetchModels(config: config);
    config.protocol = AIProtocol.anthropic;
    final models = await service.fetchModels(config: config);
    expect(models, ['anthropic-model']);
    expect(calls, 2);
  });

  testWidgets('OS-R05: imported unknown provider still opens settings', (
    tester,
  ) async {
    final (store, _) = await makeStore();
    store.importData({
      'version': 2,
      'boards': store.boards.map((b) => b.toJson()).toList(),
      'tasks': [],
      'aiConfig': {
        'providerId': 'future-provider',
        'protocol': 'openai',
        'customBaseUrl': 'https://example.invalid',
        'customModel': 'test-model',
      },
    }, 'overwrite');
    await tester.pumpWidget(app(store, const SettingsScreen()));
    final error = tester.takeException();
    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
    expect(error, isNull);
  });

  testWidgets('OS-R06: far-future deadline does not break reminder picker', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final (store, _) = await makeStore();
    final task = store.newTask(
      'Future task',
      deadline: DateTime(DateTime.now().year + 10).millisecondsSinceEpoch,
    );
    store.addTasks([task]);
    await tester.pumpWidget(app(store, TaskDetailPanel(task: task)));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('edit-reminder-btn')));
    final button = tester.widget<OutlinedButton>(
      find.byKey(const ValueKey('edit-reminder-btn')),
    );
    Object? error;
    // Await the actual async callback so the expected picker assertion is
    // captured and the Store can be disposed before test invariants run.
    final pending = (button.onPressed! as Future<void> Function())().then<void>(
      (_) {},
      onError: (Object value) {
        error = value;
      },
    );
    await tester.pumpAndSettle();
    final dialog = find.byType(DatePickerDialog);
    if (dialog.evaluate().isNotEmpty) Navigator.pop(tester.element(dialog));
    await pending;
    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
    expect(error, isNull);
  });

  testWidgets('OS-R07: exiting row excludes keyboard activation', (
    tester,
  ) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    var exiting = false;
    var actions = 0;
    late StateSetter change;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, set) {
            change = set;
            return Scaffold(
              body: ExitingRow(
                exiting: exiting,
                child: TextButton(
                  focusNode: focus,
                  onPressed: () => actions++,
                  child: const Text('Action'),
                ),
              ),
            );
          },
        ),
      ),
    );
    focus.requestFocus();
    await tester.pump();
    change(() => exiting = true);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    expect(
      actions,
      0,
      reason: 'IgnorePointer and ExcludeSemantics do not remove keyboard focus',
    );
  });
}
