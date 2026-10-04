import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/experiments/wp29_hosted_ai/wp29_hosted_ai.dart';

const secret = 'SYNTHETIC-WP29-TASK-9f3c-not-a-user';

void main() {
  test('consent, non-stream reply, validate, then human apply', () async {
    final transport = FakeHostedTransport((request, index) => _ok(request));
    final session = _session(transport);
    _prepare(session);
    final turn = await session.send();
    expect(turn.validated, isTrue);
    expect(session.phase, SessionPhase.validated);
    expect(session.suggestion?.quadrant, 1);
    expect(transport.calls, 1);
    expect(session.log.dump(), isNot(contains(secret)));
    final receipt = session.confirmApply();
    expect(receipt.suggestion.title, 'Synthetic title');
    expect(session.phase, SessionPhase.applied);
    expect(session.budget.spent, 28);
    expect(session.budget.held, 0);
  });

  test('stream deltas are buffered and still need confirmation', () async {
    final transport = DeferredTransport();
    final session = _session(transport);
    _prepare(session);
    final pending = session.send(stream: true);
    await Future<void>.delayed(Duration.zero);
    transport.emit(0, const TransportDelta('{"title":'));
    transport.emit(0, const TransportDelta('"Streamed"}'));
    transport.emit(0, _terminal(session, body: null, outputTokens: 4));
    final turn = await pending;
    expect(turn.validated, isTrue);
    expect(turn.suggestion?.title, 'Streamed');
    expect(session.phase, SessionPhase.validated);
    session.discard();
    expect(session.suggestion, isNull);
    expect(session.phase, SessionPhase.discarded);
    expect(() => session.confirmApply(), throwsA(isA<HostedFailure>()));
  });

  test(
    'timeout and 429 retry with the same request id; auth does not',
    () async {
      final retried = await _retry(HostedErrorCode.timeout, 408);
      expect(retried.calls, 2);
      expect(retried.ids.toSet(), {'req-fixed'});
      expect(retried.turn.validated, isTrue);

      final limited = await _retry(HostedErrorCode.rateLimited, 429);
      expect(limited.calls, 2);
      expect(limited.turn.attempts, 2);

      final auth = FakeHostedTransport(
        (request, index) => const TransportTerminal(
          error: HostedErrorCode.authInvalid,
          httpStatus: 401,
        ),
      );
      final session = _session(auth);
      _prepare(session);
      final turn = await session.send(requestId: 'req-auth');
      expect(turn.error, HostedErrorCode.authInvalid);
      expect(auth.calls, 1);
      expect(session.suggestion, isNull);
      expect(
        auth.seen.single.toJson().keys.toSet().intersection(envelopeSecretKeys),
        isEmpty,
      );
    },
  );

  test(
    'quota, duplicate, schema, and capability changes do not apply',
    () async {
      expect((await _fail(HostedErrorCode.quotaExhausted, 402)).calls, 1);
      expect(
        (await _fail(HostedErrorCode.duplicate, 409)).turn.error,
        HostedErrorCode.duplicate,
      );

      final bad = FakeHostedTransport(
        (request, index) => _terminal(
          null,
          body: '{"title":"x","extra":true}',
          fingerprint: request.capabilityFingerprint,
        ),
      );
      final badSession = _session(bad);
      _prepare(badSession);
      expect((await badSession.send()).error, HostedErrorCode.schemaInvalid);

      final shifted = FakeHostedTransport(
        (request, index) => _terminal(
          null,
          body: '{"title":"Do not apply"}',
          fingerprint: 'other',
        ),
      );
      final shiftedSession = _session(shifted);
      _prepare(shiftedSession);
      final turn = await shiftedSession.send();
      expect(turn.error, HostedErrorCode.capabilityChanged);
      expect(shiftedSession.suggestion, isNull);
      expect(
        () => shiftedSession.confirmApply(),
        throwsA(isA<HostedFailure>()),
      );
    },
  );

  test('a response over the output cap is not applied', () async {
    final transport = FakeHostedTransport(
      (request, index) => TransportTerminal(
        body: '{"title":"too long"}',
        inputTokens: 1,
        outputTokens: 50,
        capabilityFingerprint: request.capabilityFingerprint,
      ),
    );
    final session = _session(transport, maxOutputTokens: 8);
    _prepare(session);
    final turn = await session.send();
    expect(turn.error, HostedErrorCode.maxResponseExceeded);
    expect(session.suggestion, isNull);
  });

  test('client idempotency joins one in-flight request', () async {
    final transport = FakeHostedTransport((request, index) => _ok(request));
    final session = _session(transport);
    _prepare(session);
    final first = session.send(requestId: 'req-join');
    final second = session.send(requestId: 'req-join');
    final a = await first;
    final b = await second;
    expect(transport.calls, 1);
    expect(a.requestId, b.requestId);
    expect(session.budget.spent, 28);
  });

  test('cancel and close drop a late body', () async {
    final transport = DeferredTransport();
    final session = _session(transport);
    _prepare(session);
    final pending = session.send();
    session.cancel();
    transport.emit(0, _terminal(session, body: '{"title":"$secret"}'));
    final turn = await pending;
    expect(turn.error, HostedErrorCode.cancelled);
    expect(session.suggestion, isNull);
    expect(session.phase, SessionPhase.cancelled);
    expect(session.budget.unapplied, 28);
    expect(session.log.dump(), contains('late_result_dropped'));
    expect(session.log.dump(), isNot(contains(secret)));

    final closedTransport = DeferredTransport();
    final closed = _session(closedTransport);
    _prepare(closed);
    final hanging = closed.send();
    closed.close();
    closedTransport.emit(0, _terminal(closed, body: '{"title":"$secret"}'));
    expect((await hanging).error, HostedErrorCode.closed);
    expect(closed.suggestion, isNull);
    expect(() => closed.send(), throwsA(isA<HostedFailure>()));
  });

  test('send waits for an explicit selection and a matching consent', () async {
    final transport = FakeHostedTransport((request, index) => _ok(request));
    final session = _session(transport);
    expect(
      () => session.consent(purpose: 'classify'),
      throwsA(isA<HostedFailure>()),
    );
    session.select(TaskSelection(text: secret));
    expect(() => session.send(), throwsA(isA<HostedFailure>()));
    session.consent(purpose: 'classify the selected synthetic task');
    session.select(TaskSelection(text: '$secret more'));
    expect(() => session.send(), throwsA(isA<HostedFailure>()));
    expect(transport.calls, 0);
  });

  test('vision and budget are local gates', () async {
    final transport = FakeHostedTransport((request, index) => _ok(request));
    final blind = _session(transport, vision: false);
    blind.select(
      TaskSelection(text: secret, includeImage: true, imageBytes: Uint8List(8)),
    );
    blind.consent(purpose: 'classify the selected synthetic task');
    expect(() => blind.send(), throwsA(isA<HostedFailure>()));
    expect(transport.calls, 0);

    final poor = FakeHostedTransport((request, index) => _ok(request));
    final session = _session(poor, limit: 10, estimate: 11);
    _prepare(session);
    final turn = await session.send();
    expect(turn.error, HostedErrorCode.budgetExceeded);
    expect(poor.calls, 0);
  });

  test('request log view omits task text and image bytes', () async {
    final transport = FakeHostedTransport((request, index) => _ok(request));
    final session = _session(transport);
    final bytes = Uint8List.fromList(const [9, 8, 7, 6, 5, 4, 3, 2]);
    session.select(
      TaskSelection(text: secret, includeImage: true, imageBytes: bytes),
    );
    session.consent(purpose: 'classify the selected synthetic task');
    await session.send();
    final request = transport.seen.single;
    final wire = request.toJson();
    expect(wire.keys.toSet().intersection(envelopeSecretKeys), isEmpty);
    expect(wire.containsKey('image_bytes'), isFalse);
    expect(wire['task_text'], secret);
    expect(request.logView().containsKey('task_text'), isFalse);
    expect(request.toString(), isNot(contains(secret)));
    expect(session.log.dump(), isNot(contains(secret)));
    final encoded = String.fromCharCodes(bytes);
    expect(session.log.dump(), isNot(contains(encoded)));
  });

  test('selection fingerprint changes when the image changes', () {
    final first = TaskSelection(
      text: secret,
      includeImage: true,
      imageBytes: Uint8List.fromList(const [1, 2, 3, 4, 5, 6, 7, 8]),
    );
    final second = TaskSelection(
      text: secret,
      includeImage: true,
      imageBytes: Uint8List.fromList(const [1, 2, 3, 4, 5, 6, 7, 9]),
    );
    expect(selectionFingerprint(first), isNot(selectionFingerprint(second)));
  });

  test('client timer retries a silent transport', () async {
    final transport = DeferredTransport();
    final session = _session(
      transport,
      timeout: const Duration(milliseconds: 200),
      maxAttempts: 2,
    );
    _prepare(session);
    final pending = session.send(requestId: 'req-fixed');
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(transport.requests, hasLength(2));
    expect(transport.requests.map((request) => request.requestId).toSet(), {
      'req-fixed',
    });
    transport.emit(1, _terminal(session));
    final turn = await pending;
    expect(turn.validated, isTrue);
    expect(turn.attempts, 2);
  });
}

Future<_Retry> _retry(HostedErrorCode code, int status) async {
  final transport = FakeHostedTransport((request, index) {
    if (index == 0) {
      return TransportTerminal(error: code, httpStatus: status);
    }
    return _ok(request);
  });
  final session = _session(transport);
  _prepare(session);
  final turn = await session.send(requestId: 'req-fixed');
  return _Retry(
    calls: transport.calls,
    ids: transport.seen.map((request) => request.requestId).toList(),
    turn: turn,
  );
}

Future<_Retry> _fail(HostedErrorCode code, int status) async {
  final transport = FakeHostedTransport(
    (request, index) => TransportTerminal(error: code, httpStatus: status),
  );
  final session = _session(transport);
  _prepare(session);
  final turn = await session.send();
  expect(session.suggestion, isNull);
  return _Retry(calls: transport.calls, ids: const [], turn: turn);
}

class _Retry {
  final int calls;
  final List<String> ids;
  final HostedTurn turn;

  const _Retry({required this.calls, required this.ids, required this.turn});
}

HostedAiSession _session(
  HostedTransport transport, {
  bool vision = true,
  int limit = 1000,
  int estimate = 20,
  int maxOutputTokens = 256,
  Duration timeout = const Duration(seconds: 30),
  int maxAttempts = 3,
}) {
  return HostedAiSession(
    transport: transport,
    capability: CapabilitySnapshot(
      modelId: 'demo-model',
      vision: vision,
      maxOutputTokens: maxOutputTokens,
    ),
    budget: TokenBudget(limit: limit, counter: ExactTokenCounter(estimate)),
    timeout: timeout,
    maxAttempts: maxAttempts,
    wait: (_) async {},
    clock: () => DateTime.utc(2026, 10, 4),
  );
}

void _prepare(HostedAiSession session) {
  session.select(TaskSelection(text: secret));
  session.consent(purpose: 'classify the selected synthetic task');
}

TransportTerminal _ok(HostedRequest request) =>
    _terminal(null, fingerprint: request.capabilityFingerprint);

TransportTerminal _terminal(
  HostedAiSession? session, {
  String? body = '{"title":"Synthetic title","quadrant":1}',
  String? fingerprint,
  int outputTokens = 8,
}) {
  return TransportTerminal(
    body: body,
    inputTokens: 20,
    outputTokens: outputTokens,
    capabilityFingerprint: fingerprint ?? session!.capability.fingerprint,
    httpStatus: 200,
  );
}
