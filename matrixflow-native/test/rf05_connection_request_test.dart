// RF05 default regression: the connection panel's request lifecycle.
//
// Migrated from the review counterexample RF-R06 (test/review/
// os_final_review_probe.dart, which stays untouched) and extended over the rest
// of the RF05 acceptance list. Synthetic keys, mock prefs, fake HTTP: nothing
// here reaches a real provider, and no test starts a billed generation without
// going through the confirmation dialog.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrixflow_native/ai_service.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/screens/settings_model_request.dart';
import 'package:matrixflow_native/screens/settings_screen.dart';
import 'package:matrixflow_native/storage.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _secret = 'synthetic-rf05-key';
const _otherSecret = 'synthetic-rf05-other-key';

AIConfig _cfg({
  String base = 'https://one.invalid',
  String key = _secret,
  String model = 'probe-model',
}) => AIConfig(
  provider: 'custom',
  protocol: AIProtocol.openai,
  baseUrl: base,
  apiKey: key,
  model: model,
  enableThinking: false,
);

http.Response _models() =>
    http.Response('{"data":[{"id":"listed-model"}]}', 200);
http.Response _unauthorized() => http.Response('{}', 401);
http.Response _pong() => http.Response(
  '{"choices":[{"message":{"content":"pong"}}]}',
  200,
);

/// Records the cancellation handed to each call, so a test can say "the retired
/// request was really cancelled" instead of inferring it from a missing reply.
class _SpyService extends AIService {
  _SpyService({required super.client, super.timeout = aiRequestTimeout});

  final List<AICancellation> cancellations = [];

  @override
  Future<ConnectionProbe> testConnection(
    AIConfig config, {
    AICancellation? cancellation,
  }) {
    if (cancellation != null) cancellations.add(cancellation);
    return super.testConnection(config, cancellation: cancellation);
  }

  @override
  Future<AiProbeStep> testModelGeneration(
    AIConfig config, {
    AICancellation? cancellation,
  }) {
    if (cancellation != null) cancellations.add(cancellation);
    return super.testModelGeneration(config, cancellation: cancellation);
  }
}

/// A service whose replies the test releases one at a time.
class _Gated {
  _Gated({this.timeout = aiRequestTimeout});

  final Duration timeout;
  final gates = <Completer<http.Response>>[];
  final requests = <String>[];
  late final _SpyService service = _SpyService(
    client: MockClient((request) async {
      requests.add('${request.method} ${request.url.path}');
      final gate = Completer<http.Response>();
      gates.add(gate);
      return gate.future;
    }),
    timeout: timeout,
  );

  List<AICancellation> get cancellations => service.cancellations;

  /// Releases reply [i]; the caller pumps or awaits so the request can resume.
  void answer(int i, http.Response response) => gates[i].complete(response);

  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 1));
}

/// A service that fails the way only a bug can: the call itself throws, so the
/// panel must still come back to life.
class _ThrowingService extends AIService {
  _ThrowingService() : super(client: MockClient((request) async => _models()));

  @override
  Future<ConnectionProbe> testConnection(
    AIConfig config, {
    AICancellation? cancellation,
  }) async {
    throw StateError('synthetic unexpected failure');
  }
}

Future<Store> _openStore(AIService service, {AIConfig? config}) async {
  SharedPreferences.setMockInitialValues({
    'matrixflow-has-seen-onboarding': true,
  });
  final store = Store(aiService: service);
  await store.init();
  addTearDown(store.dispose);
  await store.updateAIConfig(config ?? _cfg());
  return store;
}

/// The same store for widget tests: the Store's periodic bookkeeping timer must
/// live outside fake async, which is what runAsync buys here.
Future<Store> _openUiStore(WidgetTester tester, AIService service) async {
  final store = await tester.runAsync(() => _openStore(service));
  return store!;
}

ConnectionRequestSession _session() {
  final session = ConnectionRequestSession(onChanged: () {});
  addTearDown(session.dispose);
  return session;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('request lifecycle', () {
    test('a first probe answers for its own identity and frees the panel', () async {
      final gated = _Gated();
      final store = await _openStore(gated.service);
      final session = _session();

      final running = session.runProbe(store);
      expect(session.isBusy, isTrue);
      expect(session.request, ConnectionRequestKind.probe);
      await gated.settle();
      gated.answer(0, _models());
      await running;

      expect(session.isBusy, isFalse);
      expect(session.request, ConnectionRequestKind.none);
      expect(session.probe?.endpointAuth.code, 'aiEndpointReachable');
      expect(session.probe?.modelDiscovery.code, 'aiDiscoveryOk');
      expect(gated.requests, ['GET /models']);
    });

    test('re-testing replaces the previous report', () async {
      final gated = _Gated();
      final store = await _openStore(gated.service);
      final session = _session();

      final first = session.runProbe(store);
      await gated.settle();
      gated.answer(0, _unauthorized());
      await first;
      expect(session.probe?.endpointAuth.code, 'aiUnauthorized');

      final second = session.runProbe(store);
      await gated.settle();
      gated.answer(1, _models());
      await second;
      expect(session.probe?.endpointAuth.code, 'aiEndpointReachable');
      expect(session.isBusy, isFalse);
    });

    test('a refused second request cannot disturb the one in flight', () async {
      final gated = _Gated();
      final store = await _openStore(gated.service);
      final session = _session();

      final first = session.runProbe(store);
      await gated.settle();
      await session.runProbe(store);
      expect(gated.gates, hasLength(1));
      expect(session.isBusy, isTrue);

      gated.answer(0, _models());
      await first;
      expect(session.isBusy, isFalse);
    });

    test('a timeout is reported and the panel works again', () async {
      final gated = _Gated(timeout: const Duration(milliseconds: 20));
      final store = await _openStore(gated.service);
      final session = _session();

      await session.runProbe(store);
      expect(session.probe?.endpointAuth.code, 'requestTimeout');
      expect(session.isBusy, isFalse);

      final retry = session.runProbe(store);
      await gated.settle();
      gated.answer(1, _models());
      await retry;
      expect(session.probe?.modelDiscovery.code, 'aiDiscoveryOk');
    });

    test('a network failure is a report, not a stuck spinner', () async {
      final service = _SpyService(
        client: MockClient((request) async => throw http.ClientException('down')),
        timeout: aiRequestTimeout,
      );
      final store = await _openStore(service);
      final session = _session();

      await session.runProbe(store);
      expect(session.probe?.endpointAuth.code, 'aiNetworkError');
      expect(session.isBusy, isFalse);
    });

    test('an unexpected throw from the service still releases busy', () async {
      final store = await _openStore(_ThrowingService());
      final session = _session();

      Object? thrown;
      try {
        await session.runProbe(store);
      } catch (error) {
        thrown = error;
      }
      expect(thrown, isA<StateError>());
      expect(session.isBusy, isFalse);
      expect(session.request, ConnectionRequestKind.none);
    });

    test('generation is a separate call that reports on its own line', () async {
      final gated = _Gated();
      final store = await _openStore(gated.service);
      final session = _session();

      final probe = session.runProbe(store);
      await gated.settle();
      gated.answer(0, _models());
      await probe;
      expect(session.generationResult, isNull);
      expect(gated.requests, ['GET /models']);

      final generation = session.runGeneration(store);
      await gated.settle();
      expect(session.request, ConnectionRequestKind.generation);
      gated.answer(1, _pong());
      await generation;
      expect(session.generationResult?.code, 'aiGenerationOk');
      expect(session.isBusy, isFalse);
      expect(gated.requests, ['GET /models', 'POST /chat/completions']);
    });
  });

  group('retirement', () {
    test('changing the identity cancels the pending probe and frees the panel',
        () async {
      final gated = _Gated();
      final store = await _openStore(gated.service);
      final session = _session();

      final first = session.runProbe(store);
      await gated.settle();
      gated.answer(0, _models());
      await first;
      expect(session.probe, isNotNull);

      final pending = session.runProbe(store);
      await gated.settle();
      await store.updateAIConfig(_cfg(base: 'https://two.invalid'));
      session.syncWithLiveConfig(store);

      expect(session.isBusy, isFalse);
      expect(session.probe, isNull);
      expect(gated.cancellations.last.isCancelled, isTrue);

      gated.answer(1, _unauthorized());
      await pending;
      expect(session.probe, isNull);
      expect(session.isBusy, isFalse);
    });

    test('a late reply cannot overwrite a newer one or free its spinner',
        () async {
      final gated = _Gated();
      final store = await _openStore(gated.service);
      final session = _session();

      final retired = session.runProbe(store);
      await gated.settle();
      await store.updateAIConfig(_cfg(base: 'https://two.invalid'));
      session.syncWithLiveConfig(store);

      final current = session.runProbe(store);
      await gated.settle();
      expect(session.isBusy, isTrue);

      // The abandoned reply lands first: it must leave the running request's
      // busy flag alone.
      gated.answer(0, _unauthorized());
      await retired;
      expect(session.isBusy, isTrue);
      expect(session.probe, isNull);

      gated.answer(1, _models());
      await current;
      expect(session.isBusy, isFalse);
      expect(session.probe?.endpointAuth.code, 'aiEndpointReachable');
      expect(session.probe?.modelDiscovery.code, 'aiDiscoveryOk');
      expect(gated.cancellations.first.isCancelled, isTrue);
    });

    test('a reply whose config moved on is dropped without a rebuild', () async {
      final gated = _Gated();
      final store = await _openStore(gated.service);
      final session = _session();

      final running = session.runProbe(store);
      await gated.settle();
      await store.updateAIConfig(_cfg(key: _otherSecret));
      // Deliberately no syncWithLiveConfig: the reply itself must notice the new
      // config and hand the buttons back instead of painting with the old answer.
      gated.answer(0, _models());
      await running;

      expect(session.probe, isNull);
      expect(session.isBusy, isFalse);
    });

    test('changing the model retires a pending generation', () async {
      final gated = _Gated();
      final store = await _openStore(gated.service);
      final session = _session();

      final generating = session.runGeneration(store);
      await gated.settle();
      await store.updateAIConfig(_cfg(model: 'other-model'));
      session.syncWithLiveConfig(store);
      expect(session.isBusy, isFalse);
      expect(gated.cancellations.last.isCancelled, isTrue);

      gated.answer(0, _pong());
      await generating;
      expect(session.generationResult, isNull);
    });

    test('a displayed generation result follows its own model', () async {
      final gated = _Gated();
      final store = await _openStore(gated.service);
      final session = _session();

      final generation = session.runGeneration(store);
      await gated.settle();
      gated.answer(0, _pong());
      await generation;
      expect(session.generationResult?.code, 'aiGenerationOk');

      await store.updateAIConfig(_cfg(model: 'other-model'));
      session.syncWithLiveConfig(store);
      expect(session.generationResult, isNull);
      // Endpoint and discovery stay: they say nothing about the model.
      final probe = session.runProbe(store);
      await gated.settle();
      gated.answer(1, _models());
      await probe;
      expect(session.probe?.modelDiscovery.code, 'aiDiscoveryOk');
    });

    test('a model edit does not strand a discovery probe', () async {
      final gated = _Gated();
      final store = await _openStore(gated.service);
      final session = _session();

      final probing = session.runProbe(store);
      await gated.settle();
      await store.updateAIConfig(_cfg(model: 'other-model'));
      session.syncWithLiveConfig(store);
      expect(session.isBusy, isTrue);

      gated.answer(0, _models());
      await probing;
      expect(session.probe?.modelDiscovery.code, 'aiDiscoveryOk');
      expect(session.isBusy, isFalse);
    });

    test('a half-typed endpoint drops the report and the pending reply',
        () async {
      final gated = _Gated();
      final store = await _openStore(gated.service);
      final session = _session();

      final first = session.runProbe(store);
      await gated.settle();
      gated.answer(0, _models());
      await first;

      final pending = session.runProbe(store);
      await gated.settle();
      await store.updateAIConfig(_cfg(base: 'not a url'));
      session.syncWithLiveConfig(store);
      expect(session.isBusy, isFalse);
      expect(session.probe, isNull);

      gated.answer(1, _models());
      await pending;
      expect(session.probe, isNull);
    });

    test('dispose cancels, and a closed panel starts nothing', () async {
      final gated = _Gated();
      final store = await _openStore(gated.service);
      final session = ConnectionRequestSession(onChanged: () {});

      final running = session.runProbe(store);
      await gated.settle();
      session.dispose();
      expect(gated.cancellations.single.isCancelled, isTrue);

      gated.answer(0, _models());
      await running;
      expect(session.isBusy, isFalse);
      expect(session.probe, isNull);

      await session.runProbe(store);
      await session.runGeneration(store);
      expect(gated.gates, hasLength(1));
    });

    test('the host is told when busy starts and when the reply ends it',
        () async {
      final gated = _Gated();
      final store = await _openStore(gated.service);
      var notifications = 0;
      final session = ConnectionRequestSession(
        onChanged: () => notifications++,
      );
      addTearDown(session.dispose);

      final running = session.runProbe(store);
      await gated.settle();
      expect(notifications, 1);
      gated.answer(0, _models());
      await running;
      expect(notifications, 2);
    });

    test('a retired reply notifies no further, so the panel cannot flicker',
        () async {
      final gated = _Gated();
      final store = await _openStore(gated.service);
      var notifications = 0;
      final session = ConnectionRequestSession(
        onChanged: () => notifications++,
      );
      addTearDown(session.dispose);

      final running = session.runProbe(store);
      await gated.settle();
      expect(notifications, 1);
      // Retirement hands the buttons back in the state; the host that calls it
      // from its widget lifecycle renders that in the same build.
      await store.updateAIConfig(_cfg(base: 'https://two.invalid'));
      session.syncWithLiveConfig(store);
      expect(session.isBusy, isFalse);
      gated.answer(0, _models());
      await running;
      expect(notifications, 1);
    });
  });

  group('settings page', () {
    testWidgets('RF-R06 connection retry can recover after config changes', (
      tester,
    ) async {
      final gated = _Gated();
      final store = await _openUiStore(tester, gated.service);
      await _pumpSettings(tester, store);
      final connection = find.byKey(const ValueKey('test-connection-btn'));
      await _reveal(tester, connection);

      final t = store.t;
      await tester.tap(connection);
      await tester.pump();
      expect(_onPressed(connection, tester), isNull);
      expect(_buttonLabel(connection, tester), t['processing']!);
      gated.answer(0, _models());
      await _flush(tester);
      expect(_onPressed(connection, tester), isNotNull);
      expect(_status(tester, 'connection-endpoint-status'), isNotNull);

      // Re-test, then change the key while that reply is still on its way.
      await tester.tap(connection);
      await tester.pump();
      expect(_onPressed(connection, tester), isNull);
      expect(_buttonLabel(connection, tester), t['processing']!);
      await tester.enterText(
        find.byKey(const ValueKey('api-key-input')),
        _otherSecret,
      );
      await tester.pump();

      // The panel is usable again before the abandoned reply even lands.
      expect(_onPressed(connection, tester), isNotNull);
      expect(_buttonLabel(connection, tester), t['testConnection']!);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(_status(tester, 'connection-endpoint-status'), isNot(contains('200')));
      await _reply(tester, gated, 1, _unauthorized());
      expect(_onPressed(connection, tester), isNotNull);
      // The abandoned answer is not shown as the current endpoint's result.
      expect(_status(tester, 'connection-endpoint-status'), isNot(contains('401')));
      await _close(tester);
    });

    testWidgets('changing the endpoint mid-generation frees the panel', (
      tester,
    ) async {
      final gated = _Gated();
      final store = await _openUiStore(tester, gated.service);
      await _pumpSettings(tester, store);
      final generation = find.byKey(const ValueKey('test-generation-btn'));
      await _reveal(tester, generation);

      await tester.tap(generation);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('generation-billing-confirm')));
      await tester.pump();
      expect(_onPressed(generation, tester), isNull);

      await tester.enterText(
        find.byKey(const ValueKey('api-key-input')),
        _otherSecret,
      );
      await tester.pump();
      expect(_onPressed(generation, tester), isNotNull);
      expect(_onPressed(find.byKey(const ValueKey('test-connection-btn')), tester), isNotNull);
      await _reply(tester, gated, 0, _pong());
      expect(
        _status(tester, 'connection-generation-status'),
        contains(store.t['aiGenerationNotRun']!),
      );
      await _close(tester);
    });

    testWidgets('closing the settings page retires the pending probe', (
      tester,
    ) async {
      final gated = _Gated();
      final store = await _openUiStore(tester, gated.service);
      await _pumpSettings(tester, store);
      await _reveal(tester, find.byKey(const ValueKey('test-connection-btn')));
      await tester.tap(find.byKey(const ValueKey('test-connection-btn')));
      await tester.pump();

      await tester.pumpWidget(const SizedBox.shrink());
      expect(gated.cancellations.single.isCancelled, isTrue);

      gated.answer(0, _models());
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('dismissing the billing dialog never generates', (tester) async {
      final gated = _Gated();
      final store = await _openUiStore(tester, gated.service);
      await _pumpSettings(tester, store);
      final generation = find.byKey(const ValueKey('test-generation-btn'));
      await _reveal(tester, generation);

      await tester.tap(generation);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('generation-billing-dialog')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('generation-billing-cancel')));
      await tester.pumpAndSettle();
      expect(gated.requests, isEmpty);
      expect(_onPressed(generation, tester), isNotNull);

      await tester.tap(generation);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('generation-billing-confirm')));
      await _reply(tester, gated, 0, _pong());
      expect(
        _status(tester, 'connection-generation-status'),
        contains(store.t['aiGenerationOk']!),
      );
      expect(gated.requests, ['POST /chat/completions']);
      await _close(tester);
    });
  });
}

Future<void> _pumpSettings(WidgetTester tester, Store store) async {
  await tester.binding.setSurfaceSize(const Size(900, 2000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: store,
      child: const MaterialApp(home: SettingsScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _reveal(WidgetTester tester, Finder target) =>
    tester.scrollUntilVisible(
      target,
      300,
      scrollable: find.byType(Scrollable).first,
    );

/// Runs the frames a just-resolved request needs to reach the panel. Never
/// settles: a spinner that has to stay on must stay detectable.
Future<void> _flush(WidgetTester tester) async {
  for (var hop = 0; hop < 4; hop++) {
    await tester.pump();
  }
}

/// Releases reply [i] and lets its continuation run.
Future<void> _reply(
  WidgetTester tester,
  _Gated gated,
  int i,
  http.Response response,
) async {
  gated.answer(i, response);
  await _flush(tester);
}

Future<void> _close(WidgetTester tester) =>
    tester.pumpWidget(const SizedBox.shrink());

Object? _onPressed(Finder button, WidgetTester tester) =>
    tester.widget<OutlinedButton>(button).onPressed;

String _buttonLabel(Finder button, WidgetTester tester) => tester
    .widget<Text>(
      find.descendant(of: button, matching: find.byType(Text)),
    )
    .data!;

String _status(WidgetTester tester, String key) => tester
    .widget<Text>(find.byKey(ValueKey(key)))
    .data!;
