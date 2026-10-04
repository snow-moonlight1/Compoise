// Offline WP29-R demo. Synthetic text only. No socket and no provider key.
import 'dart:io';
import 'dart:typed_data';

import 'package:matrixflow_native/experiments/wp29_hosted_ai/wp29_hosted_ai.dart';

const demoTaskText = 'SYNTHETIC-WP29-TASK-9f3c-not-a-user';
const demoImage = [7, 7, 7, 9, 1, 2, 3, 4];

Future<int> runWp29Demo(StringSink out) async {
  final lines = <String>[];
  void say(String line) => lines.add(line);

  await _happy(say, stream: false);
  await _happy(say, stream: true);
  await _retry(say, HostedErrorCode.timeout, 408);
  await _retry(say, HostedErrorCode.rateLimited, 429);
  await _once(say, HostedErrorCode.authInvalid, 401);
  await _once(say, HostedErrorCode.quotaExhausted, 402);
  await _once(say, HostedErrorCode.duplicate, 409);
  await _capabilityShift(say);
  await _cancelLate(say);
  await _duplicateJoin(say);
  _costs(say);

  final rendered = lines.join('\n');
  if (rendered.contains(demoTaskText)) {
    out.writeln('privacy_fail task_text_leaked');
    return 2;
  }
  for (final line in lines) {
    out.writeln(line);
  }
  out.writeln('demo_ok');
  return 0;
}

Future<void> _happy(void Function(String) say, {required bool stream}) async {
  final session = _session(FakeHostedTransport(_okScript()));
  _prepare(session, withImage: false);
  final turn = await session.send(stream: stream);
  final receipt = session.confirmApply();
  say(
    'happy stream=$stream error=${turn.error?.name} '
    'attempts=${turn.attempts} applied=${session.phase == SessionPhase.applied} '
    'receipt=${receipt.requestId.isNotEmpty}',
  );
}

Future<void> _retry(
  void Function(String) say,
  HostedErrorCode code,
  int status,
) async {
  var index = 0;
  final transport = FakeHostedTransport((request, call) {
    index = call;
    if (call == 0) {
      return TransportTerminal(
        error: code,
        httpStatus: status,
        retryAfter: const Duration(milliseconds: 25),
      );
    }
    return _ok(request);
  });
  final session = _session(transport);
  _prepare(session, withImage: false);
  final turn = await session.send();
  say(
    'retry code=${code.name} calls=${transport.calls} '
    'last_index=$index validated=${turn.validated} '
    'phase=${session.phase.name}',
  );
}

Future<void> _once(
  void Function(String) say,
  HostedErrorCode code,
  int status,
) async {
  final transport = FakeHostedTransport(
    (request, call) => TransportTerminal(error: code, httpStatus: status),
  );
  final session = _session(transport);
  _prepare(session, withImage: false);
  final turn = await session.send();
  say(
    'once code=${turn.error?.name} calls=${transport.calls} '
    'applied=${session.phase == SessionPhase.applied}',
  );
}

Future<void> _capabilityShift(void Function(String) say) async {
  final transport = FakeHostedTransport(
    (request, call) => TransportTerminal(
      body: '{"title":"Do not apply"}',
      inputTokens: 4,
      outputTokens: 4,
      capabilityFingerprint: 'different-fingerprint',
      httpStatus: 200,
    ),
  );
  final session = _session(transport);
  _prepare(session, withImage: false);
  final turn = await session.send();
  var applyBlocked = false;
  try {
    session.confirmApply();
  } on HostedFailure {
    applyBlocked = true;
  }
  say(
    'capability error=${turn.error?.name} apply_blocked=$applyBlocked '
    'suggestion=${session.suggestion == null}',
  );
}

Future<void> _cancelLate(void Function(String) say) async {
  final transport = DeferredTransport();
  final session = _session(transport, budgetLimit: 1000);
  _prepare(session, withImage: true);
  final pending = session.send();
  await Future<void>.delayed(Duration.zero);
  session.cancel();
  transport.emit(
    0,
    TransportTerminal(
      body: '{"title":"$demoTaskText"}',
      inputTokens: 3,
      outputTokens: 3,
      capabilityFingerprint: session.capability.fingerprint,
      httpStatus: 200,
    ),
  );
  final turn = await pending;
  say(
    'cancel error=${turn.error?.name} phase=${session.phase.name} '
    'suggestion=${session.suggestion == null} '
    'unapplied=${session.budget.unapplied} '
    'late=${session.log.dump().contains('late_result_dropped')}',
  );
}

Future<void> _duplicateJoin(void Function(String) say) async {
  final transport = FakeHostedTransport((request, call) => _ok(request));
  final session = _session(transport);
  _prepare(session, withImage: false);
  final first = session.send(requestId: 'req-join');
  final second = session.send(requestId: 'req-join');
  final turn = await first;
  final replay = await second;
  say(
    'join calls=${transport.calls} same=${turn.requestId == replay.requestId} '
    'validated=${turn.validated}',
  );
}

void _costs(void Function(String) say) {
  const calculator = CostCalculator();
  const scenario = CostScenario(
    calls: 1,
    inputTokensPerCall: 1000000,
    outputTokensPerCall: 1000000,
  );
  final flash = quoteById('deepseek-flash-offpeak');
  final priced = calculator.estimate(flash, scenario);
  say(
    'cost id=${flash.id} kind=${flash.kind.name} currency=${flash.currency} '
    'vendor=${priced.vendorTokenCost} assumption=${priced.assumptionCost} '
    'quote=${priced.quote.isVendorQuote}',
  );
  final overridden = calculator.estimate(
    flash.override(outputPerMillion: 1),
    scenario,
  );
  say(
    'cost_override kind=${overridden.quote.kind.name} '
    'vendor=${overridden.vendorTokenCost} quote=${overridden.quote.isVendorQuote}',
  );
  final abused = calculator.estimate(
    flash,
    const CostScenario(
      calls: 1,
      inputTokensPerCall: 1000000,
      outputTokensPerCall: 1000000,
      retryFactor: 1.5,
      abuseFraction: 0.25,
    ),
  );
  final assumptionLines = abused.lines.where((line) => line.assumption).length;
  say(
    'cost_assumption lines=$assumptionLines '
    'assumption=${abused.assumptionCost} vendor=${abused.vendorTokenCost}',
  );
  var refused = false;
  try {
    calculator.estimate(quoteById('preset-doubao-pro-32k'), scenario);
  } on UnverifiedQuote {
    refused = true;
  }
  say('cost_unverified_refused=$refused');
}

HostedAiSession _session(HostedTransport transport, {int budgetLimit = 8000}) {
  return HostedAiSession(
    transport: transport,
    capability: const CapabilitySnapshot(
      modelId: 'demo-model',
      vision: true,
      maxOutputTokens: 256,
    ),
    budget: TokenBudget(
      limit: budgetLimit,
      counter: const ExactTokenCounter(20),
    ),
    wait: (_) async {},
    clock: () => DateTime.utc(2026, 10, 4),
  );
}

void _prepare(HostedAiSession session, {required bool withImage}) {
  session.select(
    TaskSelection(
      text: demoTaskText,
      includeImage: withImage,
      imageBytes: withImage ? Uint8List.fromList(demoImage) : null,
    ),
  );
  session.consent(purpose: 'classify the selected synthetic task');
}

TransportScript _okScript() =>
    (request, call) => _ok(request);

TransportTerminal _ok(HostedRequest request) {
  return TransportTerminal(
    body: '{"title":"Synthetic title","quadrant":1}',
    inputTokens: 20,
    outputTokens: 8,
    capabilityFingerprint: request.capabilityFingerprint,
    httpStatus: 200,
  );
}

Future<void> main() async {
  exit(await runWp29Demo(stdout));
}
