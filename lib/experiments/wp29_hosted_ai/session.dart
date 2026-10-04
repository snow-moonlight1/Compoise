import 'dart:async';

import 'budget.dart';
import 'privacy_log.dart';
import 'protocol.dart';
import 'transport.dart';

enum SessionPhase {
  idle,
  selected,
  consented,
  inFlight,
  streaming,
  validated,
  applied,
  discarded,
  cancelled,
  closed,
  failed,
}

class HostedTurn {
  final String requestId;
  final HostedErrorCode? error;
  final int attempts;
  final TaskSuggestion? suggestion;

  const HostedTurn({
    required this.requestId,
    required this.error,
    required this.attempts,
    required this.suggestion,
  });

  bool get validated => error == null && suggestion != null;

  @override
  String toString() =>
      'HostedTurn($requestId,error:${error?.name},attempts:$attempts)';
}

class ApplyReceipt {
  final String requestId;
  final TaskSuggestion suggestion;

  const ApplyReceipt(this.requestId, this.suggestion);

  @override
  String toString() => 'ApplyReceipt($requestId)';
}

class _Collected {
  final HostedErrorCode? error;
  final bool retryable;
  final bool dropped;
  final String body;
  final int? inputTokens;
  final int? outputTokens;
  final String? fingerprint;
  final Duration? retryAfter;

  const _Collected({
    required this.error,
    required this.retryable,
    required this.dropped,
    required this.body,
    required this.inputTokens,
    required this.outputTokens,
    required this.fingerprint,
    required this.retryAfter,
  });

  int? get usage {
    if (inputTokens == null && outputTokens == null) return null;
    return (inputTokens ?? 0) + (outputTokens ?? 0);
  }
}

/// One consented task exchange. Late transport results are not applied.
class HostedAiSession {
  final HostedTransport transport;
  final TokenBudget budget;
  final PrivacyLog log;
  final int maxAttempts;
  final Duration timeout;
  final Duration maxRetryWait;
  final int maxResponseChars;
  final int maxTaskChars;
  final Future<void> Function(Duration delay) _wait;
  final String Function()? _ids;
  final DateTime Function() _clock;

  CapabilitySnapshot _capability;
  SessionPhase phase = SessionPhase.idle;
  TaskSelection? _selection;
  ConsentRecord? _consent;
  TaskSuggestion? suggestion;
  String? requestId;
  var _epoch = 0;
  var _requestSerial = 0;
  var _consentSerial = 0;
  final _turns = <String, Future<HostedTurn>>{};
  void Function()? _stopActive;

  HostedAiSession({
    required this.transport,
    required CapabilitySnapshot capability,
    TokenBudget? budget,
    PrivacyLog? log,
    this.maxAttempts = 3,
    this.timeout = const Duration(seconds: 30),
    this.maxRetryWait = const Duration(seconds: 2),
    this.maxResponseChars = 4000,
    this.maxTaskChars = 2000,
    Future<void> Function(Duration delay)? wait,
    String Function()? ids,
    DateTime Function()? clock,
  }) : _capability = capability,
       budget = budget ?? TokenBudget(limit: 8000),
       log = log ?? PrivacyLog(),
       _wait = wait ?? _noop,
       _ids = ids,
       _clock = clock ?? DateTime.now;

  static Future<void> _noop(Duration delay) async {}

  CapabilitySnapshot get capability => _capability;

  TaskSelection? get selection => _selection;

  ConsentRecord? get consentRecord => _consent;

  void select(TaskSelection selection) {
    _rejectClosed();
    _rejectBusy();
    if (phase == SessionPhase.validated) {
      throw const HostedFailure(HostedErrorCode.confirmationPending);
    }
    if (selection.text.length > maxTaskChars) {
      throw const HostedFailure(HostedErrorCode.selectionTooLarge);
    }
    _selection = selection;
    _consent = null;
    suggestion = null;
    phase = SessionPhase.selected;
    log.seal(selection.text);
    final image = selection.image;
    if (image != null) log.sealBytes(image);
    log.event('selected', {
      'chars': selection.text.length,
      'image_bytes': image?.length ?? 0,
    });
  }

  void consent({required String purpose}) {
    _rejectClosed();
    _rejectBusy();
    final selection = _selection;
    if (selection == null) {
      throw const HostedFailure(HostedErrorCode.selectionRequired);
    }
    if (purpose.trim().isEmpty) {
      throw const HostedFailure(HostedErrorCode.consentRequired);
    }
    log.seal(purpose);
    _consentSerial += 1;
    _consent = ConsentRecord(
      id: 'consent-$_consentSerial',
      purpose: purpose,
      selectionFingerprint: selectionFingerprint(selection),
      capabilityFingerprint: _capability.fingerprint,
      at: _clock(),
    );
    suggestion = null;
    phase = SessionPhase.consented;
    log.event('consented', {
      'consent_id': _consent!.id,
      'purpose_chars': purpose.length,
    });
  }

  void replaceCapability(CapabilitySnapshot next) {
    _rejectClosed();
    _rejectBusy();
    if (phase == SessionPhase.validated) {
      throw const HostedFailure(HostedErrorCode.confirmationPending);
    }
    _capability = next;
    _consent = null;
    if (_selection != null) phase = SessionPhase.selected;
    log.event('capability_replaced', {'fingerprint': next.fingerprint});
  }

  Future<HostedTurn> send({bool stream = false, String? requestId}) {
    if (requestId != null) {
      final existing = _turns[requestId];
      if (existing != null) {
        log.event('duplicate_joined', {'request_id': requestId});
        return existing;
      }
    }
    _ensureSendable();
    final id = requestId ?? _nextRequestId();
    final raced = _turns[id];
    if (raced != null) {
      log.event('duplicate_joined', {'request_id': id});
      return raced;
    }
    final future = _execute(id, stream);
    _turns[id] = future;
    return future;
  }

  ApplyReceipt confirmApply() {
    final current = suggestion;
    if (phase != SessionPhase.validated ||
        current == null ||
        requestId == null) {
      throw const HostedFailure(HostedErrorCode.notReady);
    }
    phase = SessionPhase.applied;
    log.event('applied', {'request_id': requestId});
    return ApplyReceipt(requestId!, current);
  }

  void discard() {
    if (phase != SessionPhase.validated) {
      throw const HostedFailure(HostedErrorCode.notReady);
    }
    suggestion = null;
    phase = SessionPhase.discarded;
    log.event('discarded', {'request_id': requestId});
  }

  void cancel() {
    if (phase != SessionPhase.inFlight && phase != SessionPhase.streaming) {
      throw const HostedFailure(HostedErrorCode.wrongPhase);
    }
    _epoch++;
    phase = SessionPhase.cancelled;
    log.event('cancelled', {'request_id': requestId});
    _stopActive?.call();
  }

  void close() {
    if (phase == SessionPhase.closed) return;
    final active =
        phase == SessionPhase.inFlight || phase == SessionPhase.streaming;
    _epoch++;
    phase = SessionPhase.closed;
    log.event('closed', {'request_id': requestId});
    if (active) _stopActive?.call();
  }

  void beginAgain() {
    _rejectClosed();
    _rejectBusy();
    if (phase == SessionPhase.validated) {
      throw const HostedFailure(HostedErrorCode.confirmationPending);
    }
    _selection = null;
    _consent = null;
    suggestion = null;
    requestId = null;
    phase = SessionPhase.idle;
    log.event('reset');
  }

  Future<HostedTurn> _execute(String id, bool stream) async {
    final selection = _selection!;
    final estimate = budget.counter.estimate(selection.text);
    try {
      budget.hold(estimate);
    } on BudgetExceeded {
      phase = SessionPhase.failed;
      log.event('budget_exceeded', {'request_id': id, 'estimate': estimate});
      return HostedTurn(
        requestId: id,
        error: HostedErrorCode.budgetExceeded,
        attempts: 0,
        suggestion: null,
      );
    }
    requestId = id;
    phase = SessionPhase.inFlight;
    var holdOpen = true;
    void releaseHold() {
      if (!holdOpen) return;
      holdOpen = false;
      budget.release(estimate);
    }

    log.event('request', {
      'held_tokens': estimate,
      ..._request(id, stream, 1).logView(),
    });

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      if (phase == SessionPhase.cancelled || phase == SessionPhase.closed) {
        releaseHold();
        return _stopped(id, attempt);
      }
      final epoch = _epoch;
      final collected = await _collect(_request(id, stream, attempt), epoch);
      if (phase == SessionPhase.cancelled ||
          phase == SessionPhase.closed ||
          collected.dropped ||
          epoch != _epoch) {
        releaseHold();
        return _stopped(id, attempt);
      }
      if (collected.retryable && attempt < maxAttempts) {
        log.event('retry', {
          'request_id': id,
          'attempt': attempt,
          'code': collected.error?.name,
        });
        await _wait(_capped(collected.retryAfter));
        continue;
      }
      return _finishTurn(
        id: id,
        attempt: attempt,
        collected: collected,
        estimate: estimate,
        closeHold: (actual, {required bool unapplied}) {
          if (!holdOpen) {
            if (unapplied && actual > 0) budget.recordUnapplied(actual);
            return;
          }
          holdOpen = false;
          if (unapplied) {
            budget.release(estimate);
            if (actual > 0) budget.recordUnapplied(actual);
          } else {
            budget.settle(estimate, actual);
          }
        },
      );
    }
    releaseHold();
    phase = SessionPhase.failed;
    return HostedTurn(
      requestId: id,
      error: HostedErrorCode.incomplete,
      attempts: maxAttempts,
      suggestion: null,
    );
  }

  HostedRequest _request(String id, bool stream, int attempt) {
    final selection = _selection!;
    return HostedRequest(
      requestId: id,
      consentId: _consent!.id,
      selectionFingerprint: selectionFingerprint(selection),
      stream: stream,
      maxOutputTokens: _capability.maxOutputTokens,
      capabilityFingerprint: _capability.fingerprint,
      taskText: selection.text,
      imageBytes: selection.image,
      attempt: attempt,
    );
  }

  HostedTurn _finishTurn({
    required String id,
    required int attempt,
    required _Collected collected,
    required int estimate,
    required void Function(int actual, {required bool unapplied}) closeHold,
  }) {
    final error = collected.error;
    if (error != null) {
      closeHold(collected.usage ?? 0, unapplied: true);
      suggestion = null;
      phase = SessionPhase.failed;
      log.event('failed', {
        'request_id': id,
        'attempt': attempt,
        'code': error.name,
      });
      return HostedTurn(
        requestId: id,
        error: error,
        attempts: attempt,
        suggestion: null,
      );
    }
    if (collected.fingerprint != _capability.fingerprint) {
      closeHold(collected.usage ?? 0, unapplied: true);
      suggestion = null;
      phase = SessionPhase.failed;
      log.event('failed', {
        'request_id': id,
        'attempt': attempt,
        'code': HostedErrorCode.capabilityChanged.name,
      });
      return HostedTurn(
        requestId: id,
        error: HostedErrorCode.capabilityChanged,
        attempts: attempt,
        suggestion: null,
      );
    }
    final outputTokens = collected.outputTokens ?? 0;
    if (outputTokens > _capability.maxOutputTokens ||
        collected.body.length > maxResponseChars) {
      closeHold(collected.usage ?? 0, unapplied: true);
      suggestion = null;
      phase = SessionPhase.failed;
      log.event('failed', {
        'request_id': id,
        'attempt': attempt,
        'code': HostedErrorCode.maxResponseExceeded.name,
      });
      return HostedTurn(
        requestId: id,
        error: HostedErrorCode.maxResponseExceeded,
        attempts: attempt,
        suggestion: null,
      );
    }
    TaskSuggestion parsed;
    try {
      parsed = parseSuggestion(collected.body);
    } on HostedFailure {
      closeHold(collected.usage ?? 0, unapplied: true);
      suggestion = null;
      phase = SessionPhase.failed;
      log.event('failed', {
        'request_id': id,
        'attempt': attempt,
        'code': HostedErrorCode.schemaInvalid.name,
      });
      return HostedTurn(
        requestId: id,
        error: HostedErrorCode.schemaInvalid,
        attempts: attempt,
        suggestion: null,
      );
    }
    final actual = collected.usage ?? estimate;
    closeHold(actual, unapplied: false);
    if (budget.overLimit) {
      suggestion = null;
      phase = SessionPhase.failed;
      log.event('failed', {
        'request_id': id,
        'attempt': attempt,
        'code': HostedErrorCode.budgetExceeded.name,
      });
      return HostedTurn(
        requestId: id,
        error: HostedErrorCode.budgetExceeded,
        attempts: attempt,
        suggestion: null,
      );
    }
    suggestion = parsed;
    phase = SessionPhase.validated;
    log.event('validated', {
      'request_id': id,
      'attempt': attempt,
      'output_tokens': outputTokens,
    });
    return HostedTurn(
      requestId: id,
      error: null,
      attempts: attempt,
      suggestion: parsed,
    );
  }

  HostedTurn _stopped(String id, int attempt) {
    suggestion = null;
    final error = phase == SessionPhase.closed
        ? HostedErrorCode.closed
        : HostedErrorCode.cancelled;
    log.event('stopped', {
      'request_id': id,
      'attempt': attempt,
      'code': error.name,
    });
    return HostedTurn(
      requestId: id,
      error: error,
      attempts: attempt,
      suggestion: null,
    );
  }

  Future<_Collected> _collect(HostedRequest request, int epoch) {
    final done = Completer<_Collected>();
    final buffer = StringBuffer();
    Timer? timer;
    StreamSubscription<TransportEvent>? sub;
    var finishing = false;

    void finish(_Collected value) {
      if (finishing || done.isCompleted) return;
      finishing = true;
      timer?.cancel();
      final current = sub;
      sub = null;
      current?.cancel();
      if (!done.isCompleted) done.complete(value);
    }

    void abandon() {
      if (!finishing && !done.isCompleted) {
        finishing = true;
        done.complete(_dropped());
      }
      timer?.cancel();
      final current = sub;
      scheduleMicrotask(() => current?.cancel());
    }

    timer = Timer(timeout, () {
      if (epoch != _epoch) {
        abandon();
        return;
      }
      finish(
        _Collected(
          error: HostedErrorCode.timeout,
          retryable: true,
          dropped: false,
          body: '',
          inputTokens: null,
          outputTokens: null,
          fingerprint: null,
          retryAfter: null,
        ),
      );
    });

    sub = transport
        .dispatch(request)
        .listen(
          (event) {
            final current =
                epoch == _epoch &&
                phase != SessionPhase.cancelled &&
                phase != SessionPhase.closed;
            if (!current || done.isCompleted) {
              final usage = event is TransportTerminal ? _usageOf(event) : null;
              if (usage != null) budget.recordUnapplied(usage);
              log.event('late_result_dropped', {
                'request_id': request.requestId,
                'usage': usage ?? 0,
              });
              return;
            }
            if (event is TransportDelta) {
              phase = SessionPhase.streaming;
              buffer.write(event.text);
              if (buffer.length > maxResponseChars) {
                finish(
                  _Collected(
                    error: HostedErrorCode.maxResponseExceeded,
                    retryable: false,
                    dropped: false,
                    body: '',
                    inputTokens: null,
                    outputTokens: null,
                    fingerprint: null,
                    retryAfter: null,
                  ),
                );
              }
              return;
            }
            if (event is TransportTerminal) {
              final code = _codeOf(event);
              final text = buffer.isEmpty
                  ? (event.body ?? '')
                  : buffer.toString();
              finish(
                _Collected(
                  error: code,
                  retryable:
                      code == HostedErrorCode.timeout ||
                      code == HostedErrorCode.rateLimited,
                  dropped: false,
                  body: code == null ? text : '',
                  inputTokens: event.inputTokens,
                  outputTokens: event.outputTokens,
                  fingerprint: event.capabilityFingerprint,
                  retryAfter: event.retryAfter,
                ),
              );
            }
          },
          onError: (Object _) {
            finish(
              _Collected(
                error: HostedErrorCode.transport,
                retryable: false,
                dropped: false,
                body: '',
                inputTokens: null,
                outputTokens: null,
                fingerprint: null,
                retryAfter: null,
              ),
            );
          },
          onDone: () {
            finish(
              const _Collected(
                error: HostedErrorCode.incomplete,
                retryable: false,
                dropped: false,
                body: '',
                inputTokens: null,
                outputTokens: null,
                fingerprint: null,
                retryAfter: null,
              ),
            );
          },
          cancelOnError: true,
        );
    _stopActive = abandon;
    return done.future.whenComplete(() {
      if (_stopActive == abandon) _stopActive = null;
    });
  }

  Duration _capped(Duration? retryAfter) {
    final delay = retryAfter ?? Duration.zero;
    return delay > maxRetryWait ? maxRetryWait : delay;
  }

  void _ensureSendable() {
    _rejectClosed();
    _rejectBusy();
    if (phase == SessionPhase.validated) {
      throw const HostedFailure(HostedErrorCode.confirmationPending);
    }
    final selection = _selection;
    final consent = _consent;
    if (selection == null) {
      throw const HostedFailure(HostedErrorCode.selectionRequired);
    }
    if (consent == null ||
        consent.selectionFingerprint != selectionFingerprint(selection) ||
        consent.capabilityFingerprint != _capability.fingerprint) {
      throw const HostedFailure(HostedErrorCode.consentRequired);
    }
    if (selection.includeImage && !_capability.vision) {
      throw const HostedFailure(HostedErrorCode.capabilityRejected);
    }
  }

  void _rejectClosed() {
    if (phase == SessionPhase.closed) {
      throw const HostedFailure(HostedErrorCode.closed);
    }
  }

  void _rejectBusy() {
    if (phase == SessionPhase.inFlight || phase == SessionPhase.streaming) {
      throw const HostedFailure(HostedErrorCode.wrongPhase);
    }
  }

  String _nextRequestId() {
    final generated = _ids?.call();
    if (generated != null && generated.isNotEmpty) return generated;
    _requestSerial += 1;
    return 'req-$_requestSerial';
  }
}

_Collected _dropped() => const _Collected(
  error: HostedErrorCode.lateResultDropped,
  retryable: false,
  dropped: true,
  body: '',
  inputTokens: null,
  outputTokens: null,
  fingerprint: null,
  retryAfter: null,
);

HostedErrorCode? _codeOf(TransportTerminal event) {
  if (event.error != null) return event.error;
  switch (event.httpStatus) {
    case 401:
    case 403:
      return HostedErrorCode.authInvalid;
    case 402:
      return HostedErrorCode.quotaExhausted;
    case 429:
      return HostedErrorCode.rateLimited;
    case 408:
      return HostedErrorCode.timeout;
    default:
      if ((event.httpStatus ?? 0) >= 400) return HostedErrorCode.transport;
      return null;
  }
}

int? _usageOf(TransportTerminal event) {
  if (event.inputTokens == null && event.outputTokens == null) return null;
  return (event.inputTokens ?? 0) + (event.outputTokens ?? 0);
}
