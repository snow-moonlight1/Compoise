// Review-only counterexamples. Synthetic data, memory prefs, fake HTTP/keys.
// Run explicitly; these assert desired behavior and are not default tests.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrixflow_native/ai_service.dart';
import 'package:matrixflow_native/ai_capabilities.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/screens/settings_model_request.dart';
import 'package:matrixflow_native/storage.dart';
import 'package:matrixflow_native/widgets/task_edit_draft.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MemoryKeys implements CredentialStore {
  String? value;
  Completer<void>? gate;
  final entered = Completer<void>();
  @override
  Future<String?> read() async => value;
  @override
  Future<void> delete() async {
    value = null;
  }

  @override
  Future<void> write(String next) async {
    if (!entered.isCompleted) entered.complete();
    await gate?.future;
    value = next;
  }
}

void main() {
  test('RF-R07 original GPT-5 must not receive unsupported none effort', () {
    final config = AIConfig(
      provider: 'custom',
      protocol: AIProtocol.openaiResponses,
      model: 'gpt-5',
      enableThinking: false,
    );
    expect(planThinking(config).fields['reasoning'], isNot({'effort': 'none'}));
  });
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('RF-R01 import must not erase edits made during its commit', () async {
    final gate = Completer<void>();
    final entered = Completer<void>();
    var armed = false;
    final store = Store(
      saveWriter: (key, value) async {
        if (armed &&
            key.startsWith('matrixflow-save-') &&
            key != SaveProtocol.pointerKey) {
          armed = false;
          entered.complete();
          await gate.future;
        }
        return (await SharedPreferences.getInstance()).setString(key, value);
      },
    );
    await store.init();
    await store.flush();
    final plan = store.previewImport({
      'version': 2,
      'boards': store.boards.map((b) => b.toJson()).toList(),
      'tasks': [store.newTask('Imported').toJson()],
    }, 'merge');
    armed = true;
    final importing = store.applyImport(plan);
    await entered.future;
    store.addTasks([store.newTask('Concurrent edit')]);
    gate.complete();
    await importing;
    await store.flush();
    final titles = store.tasks.map((t) => t.title).toList();
    store.dispose();
    expect(titles, contains('Concurrent edit'));
  });

  test('RF-R02 exit flush must include pending credential write', () async {
    final keys = MemoryKeys()..gate = Completer<void>();
    final store = Store(credentialStore: keys);
    await store.init();
    await store.flush();
    final config = store.copyAIConfig()..apiKey = 'synthetic-new';
    final updating = store.updateAIConfig(config);
    await keys.entered.future;
    var finished = false;
    final saving = store.flush().then((_) {
      finished = true;
    });
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final finishedBeforeKey = finished;
    keys.gate!.complete();
    await updating;
    await saving;
    store.dispose();
    expect(finishedBeforeKey, isFalse);
  });

  test(
    'RF-R03 clearing key while previous write runs keeps latest choice',
    () async {
      final keys = MemoryKeys()..gate = Completer<void>();
      final store = Store(credentialStore: keys);
      await store.init();
      await store.flush();
      final first = store.updateAIConfig(
        store.copyAIConfig()..apiKey = 'synthetic-first',
      );
      await keys.entered.future;
      await store.updateAIConfig(store.copyAIConfig()..apiKey = '');
      keys.gate!.complete();
      await first;
      await store.flush();
      final isEmpty = store.aiConfig.apiKey.isEmpty && keys.value == null;
      store.dispose();
      expect(isEmpty, isTrue);
    },
  );

  test(
    'RF-R04 app-produced backup must be accepted by its import gate',
    () async {
      final store = Store();
      await store.init();
      final task = store.newTask('Large valid notes')
        ..notesMarkdown = 'x' * ImportPreflight.maxBytes;
      store.addTasks([task]);
      final backup = store.exportJson();
      Object? error;
      try {
        ImportPreflight.decode(Uint8List.fromList(utf8.encode(backup)));
      } catch (e) {
        error = e;
      }
      await store.flush();
      store.dispose();
      expect(error, isNull);
    },
  );

  test('RF-R05 collapsed IME range is not unfinished composition', () {
    final controller = TextEditingController.fromValue(
      const TextEditingValue(
        text: '已完成输入',
        composing: TextRange(start: 5, end: 5),
      ),
    );
    final pending = hasPendingImeComposition(controller);
    controller.dispose();
    expect(pending, isFalse);
  });

  testWidgets('RF-R06 connection retry can recover after config changes', (
    tester,
  ) async {
    final delayed = Completer<http.Response>();
    var count = 0;
    final ai = AIService(
      client: MockClient((request) async {
        count++;
        if (count == 2) return delayed.future;
        return http.Response('{"data":[{"id":"test"}]}', 200);
      }),
    );
    final store = Store(aiService: ai);
    await store.init();
    await store.updateAIConfig(store.copyAIConfig()..apiKey = 'synthetic-test');
    await store.flush();
    late StateSetter rebuild;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, set) {
              rebuild = set;
              return TestConnectionButton(t: store.t, store: store);
            },
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('test-connection-btn')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('test-connection-btn')));
    await tester.pump();
    await store.updateAIConfig(
      store.copyAIConfig()..baseUrl = 'https://example.invalid',
    );
    rebuild(() {});
    await tester.pump();
    delayed.complete(http.Response('{"data":[]}', 200));
    await tester.pump(const Duration(milliseconds: 100));
    final enabled =
        tester
            .widget<OutlinedButton>(
              find.byKey(const ValueKey('test-connection-btn')),
            )
            .onPressed !=
        null;
    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
    expect(enabled, isTrue);
  });
}
