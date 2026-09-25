import 'package:flutter/material.dart';

import '../ai_presets.dart';
import '../ai_service.dart';
import '../model_discovery.dart';
import '../models.dart';
import '../storage.dart';

/// Owns the model-list request for the settings screen: which
/// provider/endpoint/protocol/credential the displayed results belong to, what
/// is still in flight, and when a reply has arrived too late to show. The
/// screen renders this state and never manages the request itself.
class ModelRequestSession {
  /// [onChanged] asks the host to rebuild. [onAdoptModel] writes a preferred
  /// model into the live config and the model field, which the screen owns.
  ModelRequestSession({required this.onChanged, required this.onAdoptModel});

  final VoidCallback onChanged;
  final void Function(Store store, String model) onAdoptModel;

  List<String> models = [];
  bool isFetching = false;
  String? error;

  /// Set when the chosen model is not one the provider listed, so the screen
  /// shows the free-text field instead of the discovered choices.
  bool customModelMode = false;

  int _generation = 0;
  AICancellation? _cancellation;
  ModelDiscoveryIdentity? _resultsIdentity;
  ModelDiscoveryIdentity? _attemptedIdentity;
  ModelDiscoveryIdentity? _requestedIdentity;
  String? _flightFingerprint;
  bool _disposed = false;

  static final String _fingerprintSeparator = String.fromCharCode(0);

  static String _fingerprint(AIConfig config) => [
    config.provider,
    config.baseUrl.trim(),
    config.protocol.name,
    config.apiKey.trim(),
  ].join(_fingerprintSeparator);

  /// Drops whatever the screen shows and any reply still on its way.
  void invalidate() {
    _cancellation?.cancel();
    _cancellation = null;
    _generation++;
    isFetching = false;
    models = [];
    error = null;
    _resultsIdentity = null;
    _attemptedIdentity = null;
    _requestedIdentity = null;
    _flightFingerprint = null;
  }

  /// Called after the credential or endpoint changed: only what belongs to the
  /// old identity disappears, so an unrelated edit cannot blank the list.
  void credentialOrEndpointChanged(Store store) {
    final next = tryModelDiscoveryIdentity(store.aiConfig);
    final nextPrint = _fingerprint(store.aiConfig);
    final resultsStale = _resultsIdentity != null && _resultsIdentity != next;
    final flightStale =
        isFetching &&
        _flightFingerprint != null &&
        _flightFingerprint != nextPrint;
    final errorStale =
        error != null &&
        _flightFingerprint != nextPrint &&
        _attemptedIdentity != next;
    if (resultsStale || flightStale || errorStale) {
      invalidate();
      onChanged();
    }
  }

  /// Re-runs the staleness rules against the live config. Called while
  /// building, because the config can change from anywhere in the app.
  void syncWithLiveConfig(Store store) {
    final liveIdentity = tryModelDiscoveryIdentity(store.aiConfig);
    if (_requestedIdentity != null && _requestedIdentity != liveIdentity) {
      invalidate();
    } else if (_resultsIdentity != null && _resultsIdentity != liveIdentity) {
      models = [];
      error = null;
      _resultsIdentity = null;
      _attemptedIdentity = null;
    }
  }

  /// Requests the list unless the same identity is already in flight or has
  /// already produced what is on screen. [commit] is the entry point the
  /// fields call when focus leaves them.
  void commit(Store store, {bool forceRefresh = false}) {
    if (store.aiConfig.apiKey.trim().isEmpty) return;
    final identity = tryModelDiscoveryIdentity(store.aiConfig);
    if (!forceRefresh &&
        identity != null &&
        identity == _requestedIdentity &&
        isFetching) {
      return;
    }
    if (!forceRefresh &&
        identity != null &&
        identity == _attemptedIdentity &&
        (identity == _resultsIdentity || error != null)) {
      return;
    }
    fetch(store, forceRefresh: forceRefresh);
  }

  bool _stillCurrent(Store store, AIConfig snapshot) {
    final live = tryModelDiscoveryIdentity(store.aiConfig);
    final started = tryModelDiscoveryIdentity(snapshot);
    if (live != null || started != null) return live == started;
    return store.aiConfig.provider == snapshot.provider &&
        store.aiConfig.baseUrl.trim() == snapshot.baseUrl.trim() &&
        store.aiConfig.protocol == snapshot.protocol &&
        store.aiConfig.apiKey.trim() == snapshot.apiKey.trim();
  }

  Future<void> fetch(Store store, {bool forceRefresh = false}) async {
    if (store.aiConfig.apiKey.trim().isEmpty) return;
    final identity = tryModelDiscoveryIdentity(store.aiConfig);

    _cancellation?.cancel();
    final cancel = _cancellation = AICancellation();
    final generation = ++_generation;
    _attemptedIdentity = identity;
    _requestedIdentity = identity;
    final snapshot = store.copyAIConfig();
    _flightFingerprint = _fingerprint(snapshot);
    final modelAtStart = snapshot.model;

    isFetching = true;
    error = null;
    onChanged();

    try {
      final discovered = await store.ai.fetchModels(
        config: snapshot,
        forceRefresh: forceRefresh,
        cancellation: cancel,
      );
      if (!_canApply(generation)) return;
      if (!_stillCurrent(store, snapshot)) {
        isFetching = false;
        onChanged();
        return;
      }
      isFetching = false;
      models = List<String>.from(discovered);
      _resultsIdentity = identity;
      error = null;
      if (discovered.isEmpty) {
        error = store.t['noModelsFound'];
        customModelMode = true;
      } else if (store.aiConfig.model != modelAtStart &&
          !discovered.contains(store.aiConfig.model)) {
        customModelMode = true;
      } else if (store.aiConfig.model == modelAtStart) {
        final best = pickPreferredModel(
          store.aiConfig.provider,
          discovered,
          currentModel: store.aiConfig.model,
        );
        onAdoptModel(store, best);
        customModelMode = false;
      } else {
        customModelMode = false;
      }
      onChanged();
    } catch (e) {
      if (!_canApply(generation)) return;
      if (!_stillCurrent(store, snapshot)) {
        isFetching = false;
        onChanged();
        return;
      }
      if (e is AIException && e.code == 'aiCancelled') {
        isFetching = false;
        onChanged();
        return;
      }
      isFetching = false;
      _resultsIdentity = null;
      error = aiErrorMessage(e, store.t);
      customModelMode = true;
      onChanged();
    }
  }

  /// A reply only lands while this session is alive and still the newest one.
  bool _canApply(int generation) => !_disposed && generation == _generation;

  /// Cancels the in-flight request and refuses any late reply, so the host can
  /// call it straight from its own dispose.
  void dispose() {
    _disposed = true;
    invalidate();
  }
}

/// Which request the connection panel is waiting for, if any.
enum ConnectionRequestKind { none, probe, generation }

/// One started connection request, together with the identity and model its
/// reply is allowed to speak for.
class _ConnectionRequest {
  _ConnectionRequest(this.kind, this.identity, this.model);

  final ConnectionRequestKind kind;
  final ModelDiscoveryIdentity? identity;

  /// Non-null only for generation, which also depends on the chosen model.
  final String? model;
  final AICancellation cancellation = AICancellation();
}

/// Owns the connection panel's request lifecycle: what is in flight, which
/// identity and model a reply belongs to, and what may be shown.
///
/// Retirement is the only place that frees a request the panel is no longer
/// waiting for, so a config change cannot leave a button spinning forever. A
/// reply in turn only ever releases the busy flag of the request that started
/// it, so an old answer cannot switch off a newer one's spinner.
class ConnectionRequestSession {
  ConnectionRequestSession({required this.onChanged});

  final VoidCallback onChanged;

  _ConnectionRequest? _running;
  ConnectionProbe? _probe;
  AiProbeStep? _generationResult;
  ModelDiscoveryIdentity? _probeIdentity;
  ModelDiscoveryIdentity? _generationIdentity;
  String? _generationModel;
  bool _disposed = false;

  /// The endpoint/auth + discovery report, or null once its identity is gone.
  ConnectionProbe? get probe => _probe;

  /// The separately confirmed generation result, or null once its identity or
  /// model is gone.
  AiProbeStep? get generationResult => _generationResult;

  bool get isBusy => _running != null;

  ConnectionRequestKind get request =>
      _running?.kind ?? ConnectionRequestKind.none;

  /// Checks the endpoint and the model list for the config as it is now. Sends
  /// no text, so it cannot be billed.
  Future<void> runProbe(Store store) async {
    if (!_startable) return;
    final snapshot = store.copyAIConfig();
    final request = _ConnectionRequest(
      ConnectionRequestKind.probe,
      tryModelDiscoveryIdentity(snapshot),
      null,
    );
    _running = request;
    onChanged();
    try {
      final result = await store.ai.testConnection(
        snapshot,
        cancellation: request.cancellation,
      );
      if (_isLive(store, request)) {
        _probe = result;
        _probeIdentity = request.identity;
      }
    } finally {
      _settle(request);
    }
  }

  /// One short completion against the selected model. The panel calls this only
  /// after the user confirmed it may be billed.
  Future<void> runGeneration(Store store) async {
    if (!_startable) return;
    final snapshot = store.copyAIConfig();
    final request = _ConnectionRequest(
      ConnectionRequestKind.generation,
      tryModelDiscoveryIdentity(snapshot),
      snapshot.model.trim(),
    );
    _running = request;
    onChanged();
    try {
      final result = await store.ai.testModelGeneration(
        snapshot,
        cancellation: request.cancellation,
      );
      if (_isLive(store, request)) {
        _generationResult = result;
        _generationIdentity = request.identity;
        _generationModel = request.model;
      }
    } finally {
      _settle(request);
    }
  }

  /// Re-runs the ownership rules against the live config: a result whose
  /// identity or model has moved on disappears, and a reply that can no longer
  /// be shown is cancelled and stops holding the buttons.
  ///
  /// Cancelling is a side effect, so the host calls this from its widget
  /// lifecycle rather than while building. That rebuild renders the new state.
  void syncWithLiveConfig(Store store) {
    if (_disposed) return;
    final request = _running;
    if (request != null && !_belongs(store, request)) {
      request.cancellation.cancel();
      _running = null;
    }
    final live = tryModelDiscoveryIdentity(store.aiConfig);
    if (_probe != null && _probeIdentity != live) {
      _probe = null;
      _probeIdentity = null;
    }
    if (_generationResult != null &&
        (_generationIdentity != live ||
            store.aiConfig.model.trim() != _generationModel)) {
      _generationResult = null;
      _generationIdentity = null;
      _generationModel = null;
    }
  }

  /// Cancels what is in flight and refuses any late reply, so the host can call
  /// it straight from its own dispose.
  void dispose() {
    _disposed = true;
    final request = _running;
    _running = null;
    request?.cancellation.cancel();
  }

  bool get _startable => !_disposed && _running == null;

  /// Whether the live config is still the one [request] started against. A
  /// probe answer says nothing about the chosen model, so only generation
  /// compares it.
  bool _belongs(Store store, _ConnectionRequest request) {
    if (request.identity != tryModelDiscoveryIdentity(store.aiConfig)) {
      return false;
    }
    return
        request.model == null || store.aiConfig.model.trim() == request.model;
  }

  bool _isLive(Store store, _ConnectionRequest request) =>
      !_disposed && identical(_running, request) && _belongs(store, request);

  /// Frees busy for [request] and only for [request]: whoever retired it
  /// already gave the buttons back, and a newer request keeps its spinner.
  void _settle(_ConnectionRequest request) {
    if (!identical(_running, request)) return;
    _running = null;
    onChanged();
  }
}

/// The three-step connection report: endpoint and credential, model discovery,
/// and an explicitly confirmed generation call. Each result belongs to the
/// identity it started with, so editing the config mid-flight retires it.
class TestConnectionButton extends StatefulWidget {
  final Map<String, String> t;
  final Store store;
  const TestConnectionButton({
    super.key,
    required this.t,
    required this.store,
  });

  @override
  State<TestConnectionButton> createState() => _TestConnectionButtonState();
}

class _TestConnectionButtonState extends State<TestConnectionButton> {
  /// The panel renders this session and never manages a request itself.
  late final ConnectionRequestSession _session = ConnectionRequestSession(
    onChanged: () {
      if (mounted) setState(() {});
    },
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _session.syncWithLiveConfig(widget.store);
  }

  @override
  void didUpdateWidget(TestConnectionButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    _session.syncWithLiveConfig(widget.store);
  }

  @override
  void dispose() {
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final theme = Theme.of(context);
    final probe = _session.probe;
    final request = _session.request;
    final busy = _session.isBusy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _statusLine(
          theme,
          key: const ValueKey('connection-endpoint-status'),
          label: t['connectionEndpointLabel']!,
          step: probe?.endpointAuth,
          idle: t['aiCheckSkipped']!,
        ),
        _statusLine(
          theme,
          key: const ValueKey('connection-discovery-status'),
          label: t['connectionDiscoveryLabel']!,
          step: probe?.modelDiscovery,
          idle: t['aiCheckSkipped']!,
        ),
        _statusLine(
          theme,
          key: const ValueKey('connection-generation-status'),
          label: t['connectionGenerationLabel']!,
          step: _session.generationResult,
          idle: t['aiGenerationNotRun']!,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              key: const ValueKey('test-connection-btn'),
              onPressed: busy ? null : _runProbe,
              icon:
                  request == ConnectionRequestKind.probe
                      ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Icon(Icons.wifi_tethering, size: 18),
              label: Text(
                request == ConnectionRequestKind.probe
                    ? t['processing']!
                    : t['testConnection']!,
              ),
            ),
            OutlinedButton.icon(
              key: const ValueKey('test-generation-btn'),
              onPressed: busy ? null : _confirmGeneration,
              icon:
                  request == ConnectionRequestKind.generation
                      ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Icon(Icons.play_circle_outline, size: 18),
              label: Text(
                request == ConnectionRequestKind.generation
                    ? t['processing']!
                    : t['testGeneration']!,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          t['testGenerationBilling']!,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }

  Widget _statusLine(
    ThemeData theme, {
    required Key key,
    required String label,
    required AiProbeStep? step,
    required String idle,
  }) {
    final text = step == null ? idle : _stepLabel(step);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text('$label: $text', key: key, style: theme.textTheme.labelSmall),
    );
  }

  String _stepLabel(AiProbeStep step) {
    final known = widget.t[step.code] ?? widget.t['testFail']!;
    if (step.status == null) return known;
    return '$known (${step.status})';
  }

  Future<void> _runProbe() => _session.runProbe(widget.store);

  Future<void> _confirmGeneration() async {
    if (_session.isBusy) return;
    final accepted = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            key: const ValueKey('generation-billing-dialog'),
            content: Text(widget.t['testGenerationConfirm']!),
            actions: [
              TextButton(
                key: const ValueKey('generation-billing-cancel'),
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(widget.t['cancel']!),
              ),
              TextButton(
                key: const ValueKey('generation-billing-confirm'),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(widget.t['testGenerationConfirmAction']!),
              ),
            ],
          ),
    );
    // Only an explicit yes starts a call that can be billed, and it starts
    // against the config as it is once the dialog closes.
    if (accepted != true || !mounted) return;
    await _session.runGeneration(widget.store);
  }
}
