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
  bool _probing = false;
  bool _generating = false;
  int _generation = 0;
  ConnectionProbe? _probe;
  AiProbeStep? _generationResult;
  ModelDiscoveryIdentity? _probeIdentity;
  String? _generationModel;

  bool get _busy => _probing || _generating;

  @override
  void dispose() {
    // Retire any reply still on its way before the State goes away.
    _generation++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final theme = Theme.of(context);
    final live = tryModelDiscoveryIdentity(widget.store.aiConfig);
    if (_probeIdentity != null && _probeIdentity != live) {
      _probe = null;
      _generationResult = null;
      _probeIdentity = null;
      _generationModel = null;
      _generation++;
    } else if (_generationResult != null &&
        widget.store.aiConfig.model.trim() != _generationModel) {
      _generationResult = null;
      _generationModel = null;
      _generation++;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _statusLine(
          theme,
          key: const ValueKey('connection-endpoint-status'),
          label: t['connectionEndpointLabel']!,
          step: _probe?.endpointAuth,
          idle: t['aiCheckSkipped']!,
        ),
        _statusLine(
          theme,
          key: const ValueKey('connection-discovery-status'),
          label: t['connectionDiscoveryLabel']!,
          step: _probe?.modelDiscovery,
          idle: t['aiCheckSkipped']!,
        ),
        _statusLine(
          theme,
          key: const ValueKey('connection-generation-status'),
          label: t['connectionGenerationLabel']!,
          step: _generationResult,
          idle: t['aiGenerationNotRun']!,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              key: const ValueKey('test-connection-btn'),
              onPressed: _busy ? null : _runProbe,
              icon:
                  _probing
                      ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Icon(Icons.wifi_tethering, size: 18),
              label: Text(_probing ? t['processing']! : t['testConnection']!),
            ),
            OutlinedButton.icon(
              key: const ValueKey('test-generation-btn'),
              onPressed: _busy ? null : _confirmGeneration,
              icon:
                  _generating
                      ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Icon(Icons.play_circle_outline, size: 18),
              label: Text(
                _generating ? t['processing']! : t['testGeneration']!,
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

  Future<void> _runProbe() async {
    final snapshot = AIConfig.fromJson(widget.store.aiConfig.toJson());
    final identity = tryModelDiscoveryIdentity(snapshot);
    final ticket = ++_generation;
    setState(() => _probing = true);
    final result = await widget.store.ai.testConnection(snapshot);
    if (!mounted || ticket != _generation) return;
    if (tryModelDiscoveryIdentity(widget.store.aiConfig) != identity) {
      setState(() => _probing = false);
      return;
    }
    setState(() {
      _probing = false;
      _probe = result;
      _probeIdentity = identity;
    });
  }

  Future<void> _confirmGeneration() async {
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
    if (accepted != true || !mounted) return;
    final snapshot = AIConfig.fromJson(widget.store.aiConfig.toJson());
    final identity = tryModelDiscoveryIdentity(snapshot);
    final model = snapshot.model.trim();
    final ticket = ++_generation;
    setState(() => _generating = true);
    final result = await widget.store.ai.testModelGeneration(snapshot);
    if (!mounted || ticket != _generation) return;
    if (tryModelDiscoveryIdentity(widget.store.aiConfig) != identity ||
        widget.store.aiConfig.model.trim() != model) {
      setState(() => _generating = false);
      return;
    }
    setState(() {
      _generating = false;
      _generationResult = result;
      _probeIdentity = identity;
      _generationModel = model;
    });
  }
}
