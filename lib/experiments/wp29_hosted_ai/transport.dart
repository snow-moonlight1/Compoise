import 'dart:async';

import 'protocol.dart';

sealed class TransportEvent {
  const TransportEvent();
}

class TransportDelta extends TransportEvent {
  final String text;

  const TransportDelta(this.text);
}

class TransportTerminal extends TransportEvent {
  final HostedErrorCode? error;
  final int? httpStatus;
  final String? body;
  final int? inputTokens;
  final int? outputTokens;
  final String? capabilityFingerprint;
  final Duration? retryAfter;

  const TransportTerminal({
    this.error,
    this.httpStatus,
    this.body,
    this.inputTokens,
    this.outputTokens,
    this.capabilityFingerprint,
    this.retryAfter,
  });

  bool get retryable =>
      error == HostedErrorCode.timeout || error == HostedErrorCode.rateLimited;
}

abstract class HostedTransport {
  Stream<TransportEvent> dispatch(HostedRequest request);
}

typedef TransportScript =
    TransportTerminal Function(HostedRequest request, int index);

/// Scripted transport. It never opens a socket.
class FakeHostedTransport implements HostedTransport {
  final TransportScript script;
  final List<HostedRequest> seen = [];
  int calls = 0;

  FakeHostedTransport(this.script);

  @override
  Stream<TransportEvent> dispatch(HostedRequest request) async* {
    seen.add(request);
    final terminal = script(request, calls++);
    if (request.stream && terminal.error == null) {
      final body = terminal.body ?? '';
      if (body.isNotEmpty) yield TransportDelta(body);
      yield TransportTerminal(
        httpStatus: terminal.httpStatus,
        inputTokens: terminal.inputTokens,
        outputTokens: terminal.outputTokens,
        capabilityFingerprint: terminal.capabilityFingerprint,
        retryAfter: terminal.retryAfter,
      );
      return;
    }
    yield terminal;
  }
}

/// Events are pushed with [emit] after [dispatch] returns.
class DeferredTransport implements HostedTransport {
  final requests = <HostedRequest>[];
  final controllers = <StreamController<TransportEvent>>[];

  @override
  Stream<TransportEvent> dispatch(HostedRequest request) {
    requests.add(request);
    final controller = StreamController<TransportEvent>(sync: true);
    controllers.add(controller);
    return controller.stream;
  }

  void emit(int call, TransportEvent event) {
    controllers[call].add(event);
  }
}
