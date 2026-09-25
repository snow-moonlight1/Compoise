import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../ai_capabilities.dart';
import '../ai_presets.dart';
import '../ai_service.dart';
import '../model_discovery.dart';
import '../models.dart';
import '../services/desktop_shell_host.dart';
import '../services/desktop_shell_service.dart';
import '../shortcuts.dart';
import '../storage.dart';
import '../theme.dart';
import '../ui/font_policy.dart';
import '../ui/platform_ui_policy.dart';
import '../widgets/accessible_tap_target.dart';
import 'onboarding_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _baseUrlController = TextEditingController();
  final _apiKeyController = TextEditingController();
  final _modelController = TextEditingController();
  final _apiKeyFocusNode = FocusNode();
  final _baseUrlFocusNode = FocusNode();
  bool _apiKeyHadFocus = false;
  bool _baseUrlHadFocus = false;
  bool _fileBusy = false;

  List<String> _discoveredModels = [];
  bool _fetchingModels = false;
  int _discoveryGeneration = 0;
  String? _discoveryError;
  AICancellation? _discoveryCancellation;
  ModelDiscoveryIdentity? _resultsIdentity;
  ModelDiscoveryIdentity? _attemptedIdentity;
  ModelDiscoveryIdentity? _requestedIdentity;
  String? _flightFingerprint;
  bool _customModelMode = false;
  String? _lastSyncedBaseUrl;
  String? _lastSyncedModel;

  @override
  void initState() {
    super.initState();
    final store = context.read<Store>();
    _lastSyncedBaseUrl = store.aiConfig.baseUrl;
    _lastSyncedModel = store.aiConfig.model;
    _baseUrlController.text = store.aiConfig.baseUrl;
    _apiKeyController.text = store.aiConfig.apiKey;
    _modelController.text = store.aiConfig.model;

    _apiKeyFocusNode.addListener(_handleApiKeyFocusChange);
    _baseUrlFocusNode.addListener(_handleBaseUrlFocusChange);
  }

  void _handleApiKeyFocusChange() {
    if (_apiKeyFocusNode.hasFocus) {
      _apiKeyHadFocus = true;
      return;
    }
    if (!_apiKeyHadFocus) return;
    _apiKeyHadFocus = false;
    _commitDiscovery(context.read<Store>());
  }

  void _handleBaseUrlFocusChange() {
    if (_baseUrlFocusNode.hasFocus) {
      _baseUrlHadFocus = true;
      return;
    }
    if (!_baseUrlHadFocus) return;
    _baseUrlHadFocus = false;
    _commitDiscovery(context.read<Store>());
  }

  Future<DesktopShellSettingsResult> _applyDesktopSettings(Store store) =>
      DesktopShellService.instance.applySettings(
        closeToTray: store.settings.closeToTray,
        globalShortcut: store.settings.globalShortcut,
      );

  Future<void> _editDesktopHotkey(
    BuildContext context,
    Store store,
    Map<String, String> t,
  ) async {
    var editedShortcut = store.settings.globalShortcut;
    final shortcut = await showDialog<String>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: Text(t['desktopHotkeyChange'] ?? 'Change global shortcut'),
            content: TextFormField(
              key: const ValueKey('desktop-hotkey-input'),
              initialValue: editedShortcut,
              autofocus: true,
              onChanged: (value) => editedShortcut = value,
              decoration: InputDecoration(
                hintText:
                    t['desktopHotkeyHint'] ??
                    'Ctrl+Alt+M (leave empty to disable)',
              ),
              onFieldSubmitted: (value) => Navigator.pop(dialogContext, value),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(t['cancel'] ?? 'Cancel'),
              ),
              FilledButton(
                key: const ValueKey('desktop-hotkey-save'),
                onPressed: () => Navigator.pop(dialogContext, editedShortcut),
                child: Text(t['save'] ?? 'Save'),
              ),
            ],
          ),
    );
    if (shortcut == null || !context.mounted) return;
    store.updateSettings((s) => s..globalShortcut = shortcut.trim());
    await _applyDesktopSettings(store);
  }

  String _desktopStatusText(Map<String, String> t, DesktopShellService shell) {
    if (shell.isApplyingSettings) {
      return t['desktopShellApplying'] ?? 'Applying Windows desktop settings…';
    }
    final result = shell.lastSettingsResult;
    if (result == null) {
      return t['desktopShellNotApplied'] ??
          'Desktop settings have not been applied yet.';
    }
    if (result.tray.isFailure) {
      return t['desktopTrayUnavailable'] ??
          'System tray is unavailable. Closing to tray is disabled.';
    }
    return switch (result.hotkey.kind) {
      DesktopShellResultKind.conflict =>
        t['desktopHotkeyConflict'] ??
            'Global shortcut conflicts with another application.',
      DesktopShellResultKind.invalid =>
        t['desktopHotkeyInvalid'] ?? 'Global shortcut format is invalid.',
      DesktopShellResultKind.unavailable =>
        t['desktopHotkeyUnavailable'] ??
            'Global shortcut could not be registered.',
      DesktopShellResultKind.disabled =>
        t['desktopHotkeyDisabled'] ?? 'Global shortcut is disabled.',
      _ => t['desktopShellReady'] ?? 'Windows desktop features are active.',
    };
  }

  String _discoveryFingerprint(AIConfig config) =>
      '${config.provider}\u0000${config.baseUrl.trim()}\u0000${config.protocol.name}\u0000${config.apiKey.trim()}';

  void _invalidateDisplayedDiscovery() {
    _discoveryCancellation?.cancel();
    _discoveryCancellation = null;
    _discoveryGeneration++;
    _fetchingModels = false;
    _discoveredModels = [];
    _discoveryError = null;
    _resultsIdentity = null;
    _attemptedIdentity = null;
    _requestedIdentity = null;
    _flightFingerprint = null;
  }

  void _onCredentialOrEndpointChanged(Store store) {
    final next = tryModelDiscoveryIdentity(store.aiConfig);
    final nextPrint = _discoveryFingerprint(store.aiConfig);
    final resultsStale = _resultsIdentity != null && _resultsIdentity != next;
    final flightStale =
        _fetchingModels &&
        _flightFingerprint != null &&
        _flightFingerprint != nextPrint;
    final errorStale =
        _discoveryError != null &&
        _flightFingerprint != nextPrint &&
        _attemptedIdentity != next;
    if (resultsStale || flightStale || errorStale) {
      _invalidateDisplayedDiscovery();
      setState(() {});
    }
  }

  void _onProviderChanged(String newProvider, Store store) {
    _invalidateDisplayedDiscovery();
    final preset = getAIProviderPreset(newProvider);
    _apiKeyController.clear();
    _discoveredModels.clear();
    _discoveryError = null;
    _customModelMode = false;

    store.aiConfig.provider = newProvider;
    store.aiConfig.apiKey = '';
    if (!preset.isCustom) {
      store.aiConfig.baseUrl = preset.defaultBaseUrl;
      store.aiConfig.protocol = preset.defaultProtocol;
      store.aiConfig.model = preset.defaultModel;
      _baseUrlController.text = preset.defaultBaseUrl;
      _modelController.text = preset.defaultModel;
    }
    store.updateAIConfig(store.aiConfig);

    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(store.t['providerSwitchedTip']!),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _commitDiscovery(Store store, {bool forceRefresh = false}) {
    if (store.aiConfig.apiKey.trim().isEmpty) return;
    final identity = tryModelDiscoveryIdentity(store.aiConfig);
    if (!forceRefresh &&
        identity != null &&
        identity == _requestedIdentity &&
        _fetchingModels) {
      return;
    }
    if (!forceRefresh &&
        identity != null &&
        identity == _attemptedIdentity &&
        (identity == _resultsIdentity || _discoveryError != null)) {
      return;
    }
    _fetchModels(store, forceRefresh: forceRefresh);
  }

  bool _discoveryStillCurrent(Store store, AIConfig snapshot) {
    final live = tryModelDiscoveryIdentity(store.aiConfig);
    final started = tryModelDiscoveryIdentity(snapshot);
    if (live != null || started != null) return live == started;
    return store.aiConfig.provider == snapshot.provider &&
        store.aiConfig.baseUrl.trim() == snapshot.baseUrl.trim() &&
        store.aiConfig.protocol == snapshot.protocol &&
        store.aiConfig.apiKey.trim() == snapshot.apiKey.trim();
  }

  Future<void> _fetchModels(Store store, {bool forceRefresh = false}) async {
    if (store.aiConfig.apiKey.trim().isEmpty) return;
    final identity = tryModelDiscoveryIdentity(store.aiConfig);

    _discoveryCancellation?.cancel();
    final cancel = _discoveryCancellation = AICancellation();
    final generation = ++_discoveryGeneration;
    _attemptedIdentity = identity;
    _requestedIdentity = identity;
    final snapshot = AIConfig.fromJson(store.aiConfig.toJson());
    _flightFingerprint = _discoveryFingerprint(snapshot);
    final modelAtStart = snapshot.model;

    setState(() {
      _fetchingModels = true;
      _discoveryError = null;
    });

    try {
      final models = await store.ai.fetchModels(
        config: snapshot,
        forceRefresh: forceRefresh,
        cancellation: cancel,
      );
      if (!mounted || generation != _discoveryGeneration) return;
      if (!_discoveryStillCurrent(store, snapshot)) {
        setState(() => _fetchingModels = false);
        return;
      }
      setState(() {
        _fetchingModels = false;
        _discoveredModels = List<String>.from(models);
        _resultsIdentity = identity;
        _discoveryError = null;
        if (models.isEmpty) {
          _discoveryError = store.t['noModelsFound'];
          _customModelMode = true;
        } else if (store.aiConfig.model != modelAtStart &&
            !models.contains(store.aiConfig.model)) {
          _customModelMode = true;
        } else if (store.aiConfig.model == modelAtStart) {
          final best = pickPreferredModel(
            store.aiConfig.provider,
            models,
            currentModel: store.aiConfig.model,
          );
          store.aiConfig.model = best;
          _modelController.text = best;
          store.updateAIConfig(store.aiConfig);
          _customModelMode = false;
        } else {
          _customModelMode = false;
        }
      });
    } catch (e) {
      if (!mounted || generation != _discoveryGeneration) return;
      if (!_discoveryStillCurrent(store, snapshot)) {
        setState(() => _fetchingModels = false);
        return;
      }
      if (e is AIException && e.code == 'aiCancelled') {
        setState(() => _fetchingModels = false);
        return;
      }
      setState(() {
        _fetchingModels = false;
        _resultsIdentity = null;
        _discoveryError = aiErrorMessage(e, store.t);
        _customModelMode = true;
      });
    }
  }

  @override
  void dispose() {
    _discoveryGeneration++;
    _discoveryCancellation?.cancel();
    _discoveryCancellation = null;
    _apiKeyFocusNode.removeListener(_handleApiKeyFocusChange);
    _baseUrlFocusNode.removeListener(_handleBaseUrlFocusChange);
    _apiKeyFocusNode.dispose();
    _baseUrlFocusNode.dispose();
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<Store>();
    final t = store.t;
    final theme = Theme.of(context);
    final policy = PlatformUiPolicy.of(context);
    final preset = getAIProviderPreset(store.aiConfig.provider);

    if (_lastSyncedBaseUrl != store.aiConfig.baseUrl) {
      _lastSyncedBaseUrl = store.aiConfig.baseUrl;
      _baseUrlController.text = store.aiConfig.baseUrl;
    }
    if (_lastSyncedModel != store.aiConfig.model) {
      _lastSyncedModel = store.aiConfig.model;
      _modelController.text = store.aiConfig.model;
    }
    final liveIdentity = tryModelDiscoveryIdentity(store.aiConfig);
    if (_requestedIdentity != null && _requestedIdentity != liveIdentity) {
      _discoveryCancellation?.cancel();
      _discoveryCancellation = null;
      _discoveryGeneration++;
      _fetchingModels = false;
      _discoveredModels = [];
      _discoveryError = null;
      _resultsIdentity = null;
      _attemptedIdentity = null;
      _requestedIdentity = null;
      _flightFingerprint = null;
    } else if (_resultsIdentity != null && _resultsIdentity != liveIdentity) {
      _discoveredModels = [];
      _discoveryError = null;
      _resultsIdentity = null;
      _attemptedIdentity = null;
    }

    return Scaffold(
      appBar: AppBar(title: Text(t['settings']!)),
      body: SafeArea(
        top: false,
        child: ListView(
          key: const ValueKey('settings-list'),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _sectionTitle(
              theme,
              t['settingsDisplay'] ?? t['fontAndDisplay']!,
              Icons.display_settings_outlined,
            ),
            Text(
              t['language']!,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 6),
            SegmentedButton<Language>(
              segments: const [
                ButtonSegment(value: Language.en, label: Text('EN')),
                ButtonSegment(value: Language.zh, label: Text('中文')),
                ButtonSegment(value: Language.ja, label: Text('日本語')),
              ],
              selected: {store.settings.language},
              onSelectionChanged:
                  (s) => store.updateSettings(
                    (settings) => settings..language = s.first,
                  ),
            ),
            const SizedBox(height: 20),

            _sectionTitle(theme, t['theme']!, Icons.brightness_6_outlined),
            Wrap(
              spacing: 8,
              children: [
                for (final mode in ThemeModePref.values)
                  ChoiceChip(
                    label: Text(
                      t[switch (mode) {
                        ThemeModePref.light => 'themeLight',
                        ThemeModePref.dark => 'themeDark',
                        _ => 'themeSystem',
                      }]!,
                    ),
                    selected: store.settings.theme == mode,
                    onSelected:
                        (_) => store.updateSettings(
                          (settings) => settings..theme = mode,
                        ),
                  ),
              ],
            ),
            // The dots now carry 48dp touch targets instead of a 34dp row, so
            // the gaps around them give back the same 14dp: this section keeps
            // the exact height it had before the targets grew.
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (final color in ThemeColor.values)
                  _ColorDot(
                    themeColor: color,
                    color: themeSeedColors[color]!,
                    selected: store.settings.themeColor == color,
                    tooltip: _themeColorName(t, color),
                    semanticsLabel: _themeColorLabel(t, color),
                    onTap:
                        () => store.updateSettings(
                          (settings) => settings..themeColor = color,
                        ),
                  ),
              ],
            ),
            const SizedBox(height: 10),

            _sectionTitle(
              theme,
              t['settingsTaskBehavior'] ?? t['automation']!,
              Icons.auto_mode_outlined,
            ),
            _toggle(
              context,
              t['autoDecomposeAI']!,
              t['autoDecomposeDesc']!,
              store.settings.autoDecomposeAI,
              (v) => store.updateSettings(
                (settings) => settings..autoDecomposeAI = v,
              ),
            ),
            _toggle(
              context,
              t['suppressLongTermPrompt']!,
              null,
              store.settings.suppressLongTermPrompt,
              (v) => store.updateSettings(
                (settings) => settings..suppressLongTermPrompt = v,
              ),
            ),
            _toggle(
              context,
              t['autoGroupAI']!,
              t['autoGroupDesc']!,
              store.settings.autoGroupAI,
              (v) =>
                  store.updateSettings((settings) => settings..autoGroupAI = v),
            ),
            _toggle(
              context,
              t['suppressGroupPrompt']!,
              null,
              store.settings.suppressGroupPrompt,
              (v) => store.updateSettings(
                (settings) => settings..suppressGroupPrompt = v,
              ),
            ),
            _toggle(
              context,
              t['autoCompleteParent']!,
              t['autoCompleteParentDesc']!,
              store.settings.autoCompleteParent,
              (v) => store.updateSettings(
                (settings) => settings..autoCompleteParent = v,
              ),
            ),
            const SizedBox(height: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        t['urgencyThreshold']!,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    Text(
                      '${store.settings.urgencyThresholdDays}${t['daysLeft']}',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  (t['urgencyThresholdDesc'] ??
                          'Promote uncompleted main tasks with deadlines to urgent {n} days in advance (including today).')
                      .replaceAll(
                        '{n}',
                        '${store.settings.urgencyThresholdDays}',
                      ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
            Slider(
              min: 1,
              max: 14,
              divisions: 13,
              value: store.settings.urgencyThresholdDays.toDouble(),
              onChanged:
                  (v) => store.updateSettings(
                    (settings) => settings..urgencyThresholdDays = v.round(),
                  ),
            ),
            const SizedBox(height: 20),

            _sectionTitle(theme, t['provider']!, Icons.smart_toy_outlined),
            DropdownButton<String>(
              key: const ValueKey('provider-selector'),
              isExpanded: true,
              value: store.aiConfig.provider,
              items: [
                for (final p in aiProviderPresets)
                  DropdownMenuItem(value: p.id, child: Text(p.name(t))),
              ],
              onChanged: (newProvider) {
                if (newProvider != null &&
                    newProvider != store.aiConfig.provider) {
                  _onProviderChanged(newProvider, store);
                }
              },
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('api-key-input'),
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: t['customApiKey'],
                hintText: preset.keyHint,
                floatingLabelBehavior: FloatingLabelBehavior.always,
                suffixIcon:
                    _fetchingModels
                        ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: Padding(
                            padding: EdgeInsets.all(12),
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                        : IconButton(
                          key: const ValueKey('refresh-models-btn'),
                          icon: const Icon(Icons.refresh, size: 20),
                          tooltip: t['refreshModels'],
                          onPressed:
                              _apiKeyController.text.trim().isEmpty
                                  ? null
                                  : () => _commitDiscovery(
                                    store,
                                    forceRefresh: true,
                                  ),
                        ),
              ),
              obscureText: true,
              focusNode: _apiKeyFocusNode,
              controller: _apiKeyController,
              onSubmitted: (_) => _commitDiscovery(store),
              onChanged: (v) {
                store.updateAIConfig(store.aiConfig..apiKey = v);
                _onCredentialOrEndpointChanged(store);
              },
            ),
            if (_fetchingModels) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 1.5),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    t['fetchingModels']!,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ] else if (_discoveryError != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 14,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _discoveryError!,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ),
                  TextButton(
                    key: const ValueKey('discovery-retry'),
                    onPressed:
                        () => _commitDiscovery(store, forceRefresh: true),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(t['retry']!),
                  ),
                ],
              ),
            ] else if (_apiKeyController.text.trim().isEmpty) ...[
              const SizedBox(height: 6),
              Text(
                t['enterApiKeyFirst']!,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ],
            const SizedBox(height: 10),
            if (_discoveredModels.isNotEmpty && !_customModelMode) ...[
              DropdownButtonFormField<String>(
                key: const ValueKey('model-selector'),
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: t['customModel'],
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                ),
                value:
                    _discoveredModels.contains(store.aiConfig.model)
                        ? store.aiConfig.model
                        : '__custom__',
                items: [
                  for (final m in _discoveredModels)
                    DropdownMenuItem(
                      value: m,
                      child: Text(m, overflow: TextOverflow.ellipsis),
                    ),
                  DropdownMenuItem(
                    value: '__custom__',
                    child: Text(
                      t['customModelOption']!,
                      style: TextStyle(color: theme.colorScheme.primary),
                    ),
                  ),
                ],
                onChanged: (val) {
                  if (val == '__custom__') {
                    setState(() {
                      _customModelMode = true;
                    });
                  } else if (val != null) {
                    _modelController.text = val;
                    store.updateAIConfig(store.aiConfig..model = val);
                  }
                },
              ),
            ] else ...[
              TextField(
                key: const ValueKey('model-input'),
                decoration: InputDecoration(
                  labelText: t['customModel'],
                  hintText:
                      preset.defaultModel.isNotEmpty
                          ? preset.defaultModel
                          : t['enterModelHint'],
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                  suffixIcon:
                      _discoveredModels.isNotEmpty
                          ? IconButton(
                            icon: const Icon(Icons.list, size: 20),
                            tooltip: t['selectModel'],
                            onPressed: () {
                              setState(() {
                                _customModelMode = false;
                              });
                            },
                          )
                          : null,
                ),
                controller: _modelController,
                onChanged: (v) {
                  store.updateAIConfig(store.aiConfig..model = v);
                },
              ),
            ],
            if (preset.supportsThinking ||
                preset.isCustom ||
                store.aiConfig.protocol == AIProtocol.anthropic ||
                store.aiConfig.protocol == AIProtocol.openaiResponses) ...[
              const SizedBox(height: 8),
              SwitchListTile(
                key: const ValueKey('thinking-switch'),
                contentPadding: EdgeInsets.zero,
                title: Text(t['enableThinking']!),
                subtitle: Text(
                  t[planThinking(store.aiConfig).hintCode ??
                      'enableThinkingDesc']!,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                value: store.aiConfig.enableThinking,
                onChanged:
                    (v) => store.updateAIConfig(
                      store.aiConfig..enableThinking = v,
                    ),
              ),
            ],
            if (preset.isCustom) ...[
              const SizedBox(height: 10),
              DropdownButton<AIProtocol>(
                key: const ValueKey('protocol-selector'),
                isExpanded: true,
                items: [
                  DropdownMenuItem(
                    value: AIProtocol.openai,
                    child: Text(
                      t['providerOpenAI']!,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  DropdownMenuItem(
                    value: AIProtocol.openaiResponses,
                    child: Text(
                      t['providerOpenAIResponses']!,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  DropdownMenuItem(
                    value: AIProtocol.anthropic,
                    child: Text(
                      t['providerAnthropic']!,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
                value: store.aiConfig.protocol,
                onChanged: (value) {
                  if (value != null && value != store.aiConfig.protocol) {
                    store.updateAIConfig(store.aiConfig..protocol = value);
                    _invalidateDisplayedDiscovery();
                    setState(() {});
                  }
                },
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('base-url-input'),
                autocorrect: false,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  labelText: t['customBaseUrl'],
                  hintText: 'https://api.deepseek.com',
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                ),
                focusNode: _baseUrlFocusNode,
                controller: _baseUrlController,
                onSubmitted: (_) => _commitDiscovery(store),
                onChanged: (v) {
                  store.updateAIConfig(store.aiConfig..baseUrl = v);
                  _onCredentialOrEndpointChanged(store);
                },
              ),
              const SizedBox(height: 6),
              Text(
                t['customUrlHint']!,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
                ),
              ),
            ] else ...[
              const SizedBox(height: 6),
              Theme(
                data: theme.copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  key: const ValueKey('advanced-settings-tile'),
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: EdgeInsets.zero,
                  title: Text(
                    t['advancedSettings']!,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                  children: [
                    const SizedBox(height: 8),
                    TextField(
                      key: const ValueKey('base-url-input'),
                      autocorrect: false,
                      keyboardType: TextInputType.url,
                      decoration: InputDecoration(
                        labelText: t['customBaseUrl'],
                        hintText: preset.defaultBaseUrl,
                        floatingLabelBehavior: FloatingLabelBehavior.always,
                      ),
                      focusNode: _baseUrlFocusNode,
                      controller: _baseUrlController,
                      onSubmitted: (_) => _commitDiscovery(store),
                      onChanged: (v) {
                        store.updateAIConfig(store.aiConfig..baseUrl = v);
                        _onCredentialOrEndpointChanged(store);
                      },
                    ),
                    const SizedBox(height: 6),
                    Text(
                      t['customUrlHint']!,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.45,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
            ],
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              margin: const EdgeInsets.only(top: 4, bottom: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withValues(
                  alpha: 0.35,
                ),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: theme.colorScheme.primary.withValues(alpha: 0.25),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.tips_and_updates_outlined,
                    size: 15,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      t['aiRecommendTip']!,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            _TestConnectionButton(t: t, store: store),
            const SizedBox(height: 20),

            _sectionTitle(
              theme,
              t['dataManagement']!,
              Icons.cloud_sync_outlined,
            ),
            if (store.credentialError != null)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      store.credentialError!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      if (await store.retryCredential()) {
                        await store.retrySave();
                      }
                    },
                    child: Text(t['retrySave']!),
                  ),
                ],
              ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.download_outlined, size: 18),
                    label: Text(t['exportData']!),
                    onPressed: _fileBusy ? null : () => _export(context, store),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.upload_outlined, size: 18),
                    label: Text(t['importData']!),
                    onPressed: _fileBusy ? null : () => _import(context, store),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            _sectionTitle(
              theme,
              t['fontAndDisplay'] ?? 'Font & Display',
              Icons.format_size,
            ),
            Text(
              t['fontSize'] ?? 'Font Size',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                for (final size in FontSizePref.values)
                  ChoiceChip(
                    key: ValueKey('font-size-${size.name}'),
                    label: Text(
                      t[switch (size) {
                            FontSizePref.small => 'fontSizeSmall',
                            FontSizePref.standard => 'fontSizeStandard',
                            FontSizePref.large => 'fontSizeLarge',
                          }] ??
                          size.name,
                    ),
                    selected: store.settings.fontSize == size,
                    onSelected: (_) => store.setFontSize(size),
                  ),
              ],
            ),
            const SizedBox(height: 14),

            Text(
              t['fontFamily'] ?? 'Font Family',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                for (final family in FontFamilyPref.values)
                  ChoiceChip(
                    key: ValueKey('font-family-${family.name}'),
                    label: Text(
                      t[switch (family) {
                            FontFamilyPref.system => 'fontSystem',
                            FontFamilyPref.sansSerif => 'fontSansSerif',
                            FontFamilyPref.serif => 'fontSerif',
                            FontFamilyPref.monospace => 'fontMonospace',
                          }] ??
                          family.name,
                    ),
                    selected: store.settings.fontFamily == family,
                    onSelected: (_) => store.setFontFamily(family),
                  ),
              ],
            ),
            const SizedBox(height: 14),

            Builder(
              builder: (context) {
                final fonts = AppFontPolicy.of(context);
                final family = fonts.familyFor(store.settings.fontFamily);
                final fallback = fonts.fallbackFor(store.settings.fontFamily);
                final scale = fontScaleFactor(store.settings.fontSize);
                return Container(
                  key: const ValueKey('font-preview-card'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.4,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant.withValues(
                        alpha: 0.4,
                      ),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t['fontPreviewTitle'] ??
                            'Urgent and Important · MatrixFlow 123',
                        key: const ValueKey('font-preview-title'),
                        style: TextStyle(
                          fontFamily: family,
                          fontFamilyFallback: fallback,
                          fontWeight: fonts.titleWeight,
                          fontSize: 16 * scale,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        t['fontPreview'] ??
                            'Preview: Urgent & Important Task 123',
                        key: const ValueKey('font-preview-body'),
                        style: TextStyle(
                          fontFamily: family,
                          fontFamilyFallback: fallback,
                          fontWeight: fonts.bodyWeight,
                          fontSize: 14 * scale,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        t['fontPreviewSample'] ??
                            '紧急且重要，购买牛奶；MatrixFlow 123；日本語テスト',
                        key: const ValueKey('font-preview-sample'),
                        style: TextStyle(
                          fontFamily: family,
                          fontFamilyFallback: fallback,
                          fontWeight: fonts.bodyWeight,
                          fontSize: 14 * scale,
                          height: 1.4,
                        ),
                      ),
                      if (store.settings.fontFamily ==
                          FontFamilyPref.monospace) ...[
                        const SizedBox(height: 8),
                        Text(
                          t['fontMonospaceHint'] ??
                              'Monospace applies to Latin letters; CJK falls back to a proportional font.',
                          key: const ValueKey('font-monospace-hint'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 8),

            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const ValueKey('reset-display-btn'),
                icon: const Icon(Icons.restore, size: 16),
                label: Text(t['resetDisplay'] ?? 'Reset Display Defaults'),
                onPressed: () => store.resetDisplayPreferences(),
              ),
            ),
            const SizedBox(height: 8),
            _toggle(
              context,
              t['showCompletionRate'] ?? 'Show overall completion rate',
              t['showCompletionRateDesc'] ??
                  'Show the share of completed tasks across all boards at the bottom of the More panel.',
              store.settings.showCompletionRate,
              (v) => store.updateSettings((s) => s..showCompletionRate = v),
              key: const ValueKey('show-completion-rate-toggle'),
            ),
            const SizedBox(height: 8),
            _toggle(
              context,
              t['reduceMotion'] ?? 'Reduce animation',
              t['reduceMotionDesc'] ??
                  'Jump straight to the final state instead of playing entrance, strikethrough and exit animations.',
              store.settings.reduceMotion,
              (v) => store.updateSettings((s) => s..reduceMotion = v),
              key: const ValueKey('reduce-motion-toggle'),
            ),
            const SizedBox(height: 20),

            if (policy.showDesktopSettings) ...[
              _sectionTitle(
                theme,
                t['desktopSection'] ?? 'Desktop & System',
                Icons.desktop_windows_outlined,
              ),
              _toggle(
                context,
                t['closeToTray'] ?? 'Minimize / Close to System Tray',
                t['closeToTraySubtitle'] ??
                    'Keep app running in system tray when window is closed',
                store.settings.closeToTray,
                (v) async {
                  store.updateSettings((s) => s..closeToTray = v);
                  final result = await _applyDesktopSettings(store);
                  if (!context.mounted) return;
                  if (v && result.closeToTrayEffective) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          t['closeToTrayNotice'] ??
                              'When enabled, closing the window minimizes to the system tray. Right-click the tray icon to exit.',
                        ),
                        duration: const Duration(seconds: 4),
                      ),
                    );
                  } else if (v && result.tray.isFailure) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          t['desktopTrayUnavailable'] ??
                              'System tray is unavailable. Closing to tray is disabled.',
                        ),
                      ),
                    );
                  }
                },
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    t['globalHotkey'] ?? 'Global Shortcut',
                    style: theme.textTheme.bodyMedium,
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant,
                      ),
                    ),
                    child: Text(
                      store.settings.globalShortcut,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton(
                    key: const ValueKey('desktop-hotkey-change'),
                    onPressed: () => _editDesktopHotkey(context, store, t),
                    child: Text(
                      t['desktopHotkeyChange'] ?? 'Change global shortcut',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ListenableBuilder(
                listenable: DesktopShellService.instance,
                builder: (context, _) {
                  final shell = DesktopShellService.instance;
                  final result = shell.lastSettingsResult;
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Icon(
                        result?.hasFailure == true
                            ? Icons.warning_amber_rounded
                            : Icons.check_circle_outline,
                        size: 18,
                        color:
                            result?.hasFailure == true
                                ? theme.colorScheme.error
                                : theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _desktopStatusText(t, shell),
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                      if (result?.hasFailure == true &&
                          !shell.isApplyingSettings)
                        TextButton(
                          key: const ValueKey('desktop-shell-retry'),
                          onPressed: () async {
                            await _applyDesktopSettings(store);
                          },
                          child: Text(t['retry'] ?? 'Retry'),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 20),
            ],

            _sectionTitle(
              theme,
              t['reminders'] ?? 'Reminders & Notifications',
              Icons.notifications_active_outlined,
            ),
            if (policy.isWindows) ...[
              ListTile(
                key: const ValueKey('windows-reminder-guide-tile'),
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.desktop_windows_outlined,
                  color: theme.colorScheme.primary,
                ),
                title: Text(
                  t['windowsReminderGuide'] ??
                      'Windows Notifications & Tray Guide',
                ),
                subtitle: Text(
                  t['windowsReminderGuideDesc'] ??
                      'Ensure punctual alerts with system tray keep-alive and Focus Assist setup',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showWindowsReminderGuideDialog(context, t),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const ValueKey('check-permissions-btn'),
                      icon: const Icon(Icons.security, size: 16),
                      label: Text(t['checkPermissions'] ?? 'Check Permissions'),
                      onPressed: () => _checkAndShowPermissions(context, t),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const ValueKey('test-windows-notif-btn'),
                      icon: const Icon(
                        Icons.notification_add_outlined,
                        size: 16,
                      ),
                      label: Text(t['testNotification'] ?? 'Test Notification'),
                      onPressed: () => _sendTestReminder(context, t, store),
                    ),
                  ),
                ],
              ),
            ] else ...[
              ListTile(
                key: const ValueKey('reminder-guide-tile'),
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.battery_charging_full_outlined,
                  color: theme.colorScheme.primary,
                ),
                title: Text(
                  t['reminderGuide'] ?? 'Punctual Alert & Keep-Alive Guide',
                ),
                subtitle: Text(
                  t['reminderGuideDesc'] ??
                      'Guide to configure battery optimization and auto-start on Android ROMs',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showReminderGuideDialog(context, t),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const ValueKey('check-permissions-btn'),
                      icon: const Icon(Icons.security, size: 16),
                      label: Text(t['checkPermissions'] ?? 'Check Permissions'),
                      onPressed: () => _checkAndShowPermissions(context, t),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const ValueKey('test-android-notif-btn'),
                      icon: const Icon(
                        Icons.notification_add_outlined,
                        size: 16,
                      ),
                      label: Text(t['testNotification'] ?? 'Test Notification'),
                      onPressed: () => _sendTestReminder(context, t, store),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 20),
            _sectionTitle(
              theme,
              t['settingsHelpAbout'] ?? t['onboarding'] ?? 'Help & About',
              Icons.help_outline,
            ),
            ListTile(
              key: const ValueKey('reopen-onboarding-btn'),
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.school_outlined,
                color: theme.colorScheme.primary,
              ),
              title: Text(t['reopenOnboarding'] ?? 'Tutorial & Gestures Guide'),
              subtitle: Text(
                t['reopenOnboardingDesc'] ??
                    'Review core operations, gestures, and features anytime',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const OnboardingScreen(isReviewMode: true),
                  ),
                );
              },
            ),
            if (policy.showDesktopShortcuts)
              ListTile(
                key: const ValueKey('shortcuts-help-tile'),
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.keyboard_outlined,
                  color: theme.colorScheme.primary,
                ),
                title: Text(t['shortcutsHelp'] ?? 'Keyboard Shortcuts'),
                subtitle: Text(
                  t['shortcutHelp'] ?? 'Keyboard Shortcuts Help',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showShortcutsHelpDialog(context, t),
              ),
          ],
        ),
      ),
    );
  }

  void _showWindowsReminderGuideDialog(
    BuildContext context,
    Map<String, String> t,
  ) {
    showDialog(
      context: context,
      builder:
          (dialogCtx) => AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.desktop_windows_outlined, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    t['windowsReminderGuideTitle'] ??
                        'Windows Notification Reliability Guide',
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    t['windowsReminderGuideIntro'] ?? '',
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  _buildGuideItem(
                    context,
                    title:
                        t['windowsGuideTrayTitle'] ??
                        '1. System Tray Keep-Alive',
                    steps: t['windowsGuideTraySteps'] ?? '',
                  ),
                  const SizedBox(height: 12),
                  _buildGuideItem(
                    context,
                    title:
                        t['windowsGuideFocusTitle'] ??
                        '2. Windows Focus Assist',
                    steps: t['windowsGuideFocusSteps'] ?? '',
                  ),
                  const SizedBox(height: 12),
                  _buildGuideItem(
                    context,
                    title:
                        t['windowsGuideActionCenterTitle'] ??
                        '3. Notifications & Sound Banners',
                    steps: t['windowsGuideActionCenterSteps'] ?? '',
                  ),
                ],
              ),
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: Text(t['confirm'] ?? 'OK'),
              ),
            ],
          ),
    );
  }

  void _showReminderGuideDialog(BuildContext context, Map<String, String> t) {
    showDialog(
      context: context,
      builder:
          (dialogCtx) => AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.tips_and_updates_outlined, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    t['reminderGuideTitle'] ?? 'Ensure Punctual Reminders',
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    t['reminderGuideIntro'] ?? '',
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  _buildGuideItem(
                    context,
                    title: t['guideXiaomiTitle'] ?? 'Xiaomi / Redmi',
                    steps: t['guideXiaomiSteps'] ?? '',
                  ),
                  const SizedBox(height: 12),
                  _buildGuideItem(
                    context,
                    title: t['guideHuaweiTitle'] ?? 'Huawei / Honor',
                    steps: t['guideHuaweiSteps'] ?? '',
                  ),
                  const SizedBox(height: 12),
                  _buildGuideItem(
                    context,
                    title: t['guideOppoVivoTitle'] ?? 'OPPO / vivo / OnePlus',
                    steps: t['guideOppoVivoSteps'] ?? '',
                  ),
                  const SizedBox(height: 12),
                  _buildGuideItem(
                    context,
                    title: t['guideOtherTitle'] ?? 'Other Android ROMs',
                    steps: t['guideOtherSteps'] ?? '',
                  ),
                ],
              ),
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: Text(t['confirm'] ?? 'OK'),
              ),
            ],
          ),
    );
  }

  Widget _buildGuideItem(
    BuildContext context, {
    required String title,
    required String steps,
  }) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            steps,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  /// Localized wording, colour and whether a runtime request is even possible
  /// for one permission probe result.
  ({String text, Color color, bool canRequest}) _permissionReport(
    ReminderPermissionStatus status,
    Map<String, String> t,
  ) {
    switch (status) {
      case ReminderPermissionStatus.granted:
        return (
          text: t['permissionGranted'] ?? 'Granted',
          color: Colors.green,
          canRequest: false,
        );
      case ReminderPermissionStatus.denied:
        return (
          text: t['permissionDenied'] ?? 'Denied',
          color: Colors.red,
          canRequest: true,
        );
      case ReminderPermissionStatus.inexactOnly:
        return (
          text: t['permissionInexact'] ?? 'Inexact only',
          color: Colors.orange,
          canRequest: true,
        );
      case ReminderPermissionStatus.unsupported:
        return (
          text: t['permissionUnsupported'] ?? 'Unsupported on this platform',
          color: Colors.grey,
          canRequest: false,
        );
      case ReminderPermissionStatus.unknown:
        return (
          text: t['permissionUnknown'] ?? 'Notification status is unknown',
          color: Colors.orange,
          canRequest: false,
        );
    }
  }

  /// Sends one notification now and reports what the platform actually did,
  /// including the permission state that decides whether the user can see it.
  Future<void> _sendTestReminder(
    BuildContext context,
    Map<String, String> t,
    Store store,
  ) async {
    final service = ReminderService.instance;
    await service.init();
    final permission = await service.checkPermission();
    if (!context.mounted) return;
    final result = await service.scheduleReminder(
      boardId: store.activeBoardId,
      taskId: 'test-win-notif',
      title: 'MatrixFlow AI',
      body: t['reminderTestBody'] ?? 'MatrixFlow test notification',
      triggerAtMs: DateTime.now().millisecondsSinceEpoch,
      recordRetry: false,
    );
    if (!context.mounted) return;
    final String message;
    switch (result.status) {
      case ReminderScheduleStatus.scheduled:
      case ReminderScheduleStatus.displayed:
        message = t['testNotificationSent'] ?? 'Test notification sent.';
      case ReminderScheduleStatus.scheduledInApp:
        message = t['reminderTestInAppOnly'] ?? 'Armed inside the app only.';
      case ReminderScheduleStatus.superseded:
      case ReminderScheduleStatus.expired:
      case ReminderScheduleStatus.unavailable:
      case ReminderScheduleStatus.failed:
        message = t['reminderTestFailed'] ?? 'Test notification failed.';
    }
    final report = _permissionReport(permission, t);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          permission == ReminderPermissionStatus.granted
              ? message
              : '$message ${report.text}',
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _checkAndShowPermissions(
    BuildContext context,
    Map<String, String> t,
  ) async {
    final service = ReminderService.instance;
    final status = await service.checkPermission();
    if (!context.mounted) return;

    final report = _permissionReport(status, t);
    final statusText = report.text;
    final color = report.color;
    final canRequest = report.canRequest;

    showDialog(
      context: context,
      builder:
          (dialogCtx) => AlertDialog(
            title: Text(t['permissionStatus'] ?? 'Permission Status'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      status == ReminderPermissionStatus.granted
                          ? Icons.check_circle
                          : Icons.warning_amber_rounded,
                      color: color,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        statusText,
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              if (canRequest)
                TextButton(
                  onPressed: () async {
                    Navigator.pop(dialogCtx);
                    final after = await service.requestPermission();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(_permissionReport(after, t).text),
                        duration: const Duration(seconds: 4),
                      ),
                    );
                  },
                  child: Text(
                    t['requestPermissionBtn'] ?? 'Request Permission',
                  ),
                ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: Text(t['confirm'] ?? 'OK'),
              ),
            ],
          ),
    );
  }

  Widget _sectionTitle(ThemeData theme, String text, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _toggle(
    BuildContext context,
    String title,
    String? subtitle,
    bool value,
    ValueChanged<bool> onChanged, {
    Key? key,
  }) {
    return SwitchListTile(
      key: key,
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(title, style: Theme.of(context).textTheme.bodyMedium),
      subtitle:
          subtitle == null
              ? null
              : Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
      value: value,
      onChanged: onChanged,
    );
  }

  Future<void> _export(BuildContext context, Store store) async {
    if (_fileBusy) return;
    setState(() => _fileBusy = true);
    try {
      final includeCredential = await showDialog<bool>(
        context: context,
        builder:
            (dialogContext) => AlertDialog(
              title: Text(store.t['exportCredentialTitle']!),
              content: Text(store.t['exportCredentialWarning']!),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(store.t['cancel']!),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: Text(store.t['exportWithoutCredential']!),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: Text(store.t['exportWithCredential']!),
                ),
              ],
            ),
      );
      if (includeCredential == null || !context.mounted) return;
      final json =
          includeCredential
              ? await store.exportJsonWithCredential()
              : store.exportJson();
      final bytes = Uint8List.fromList(utf8.encode(json));
      final path = await FilePicker.platform.saveFile(
        fileName:
            'matrixflow_backup_${DateTime.now().toIso8601String().split('T').first}.json',
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: bytes,
      );
      if (path == null) return;
      // Android's Storage Access Framework writes the bytes itself. Its return
      // value may be a content URI, not a Dart File path.
      if (!Platform.isAndroid && !Platform.isIOS) {
        await File(path).writeAsBytes(bytes, flush: true);
      }
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(store.t['exportSuccess']!)));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(store.t['exportError']!)));
      }
    } finally {
      if (mounted) setState(() => _fileBusy = false);
    }
  }

  Future<void> _import(BuildContext context, Store store) async {
    if (_fileBusy) return;
    setState(() => _fileBusy = true);
    final t = store.t;
    var applying = false;
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: false,
      );
      if (!context.mounted || picked == null) return;
      final file = picked.files.single;
      Uint8List? bytes = file.bytes;
      if (file.size > ImportPreflight.maxBytes) {
        throw const FormatException('Backup exceeds size limit');
      }
      if (bytes == null && file.path != null) {
        final source = File(file.path!);
        if (await source.length() > ImportPreflight.maxBytes) {
          throw const FormatException('Backup exceeds size limit');
        }
        final collected = <int>[];
        await for (final chunk in source.openRead(
          0,
          ImportPreflight.maxBytes + 1,
        )) {
          collected.addAll(chunk);
          if (collected.length > ImportPreflight.maxBytes) {
            throw const FormatException('Backup exceeds size limit');
          }
        }
        bytes = Uint8List.fromList(collected);
      }
      if (bytes == null) throw const FormatException('No file data');
      final json = ImportPreflight.decode(bytes);
      if (!context.mounted) return;
      final mode = await showDialog<String>(
        context: context,
        builder:
            (dialogContext) => AlertDialog(
              title: Text(t['importOptions']!),
              content: Text(t['importPrompt']!),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(t['cancel']!),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, 'merge'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t['importModeMerge']!),
                      Text(
                        t['importModeMergeDesc']!,
                        style: Theme.of(dialogContext).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                  ),
                  onPressed: () => Navigator.pop(dialogContext, 'overwrite'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t['importModeOverwrite']!),
                      Text(
                        t['importModeOverwriteDesc']!,
                        style: Theme.of(dialogContext).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
      );
      if (mode == null || !context.mounted) return;
      final plan = store.previewImport(json, mode);
      final summary =
          '${t['importAddedBoards']}: ${plan.addedBoards}\n'
          '${t['importAddedTasks']}: ${plan.addedTasks}\n'
          '${t['importSkipped']}: ${plan.skipped}\n'
          '${t['importConflicts']}: ${plan.conflicts}\n'
          '${t['importRepaired']}: ${plan.repaired}\n'
          '${t['importWarnings']}: ${plan.warnings.length}\n'
          '${t['importRemovedBoards']}: ${plan.removedBoards}\n'
          '${t['importRemovedTasks']}: ${plan.removedTasks}\n'
          '${t['importSettingsImpact']}: ${plan.settings == null ? t['importAbsent'] : t['importPresent']}\n'
          '${t['importConfigImpact']}: ${plan.aiConfig == null ? t['importAbsent'] : t['importPresent']}';
      String warningText(String warning) {
        if (warning == 'Empty backup') return t['importWarningEmpty']!;
        if (warning == 'Orphan task skipped') return t['importWarningOrphan']!;
        if (warning == 'Default board created') return t['importWarningBoard']!;
        if (warning == 'Empty board reference repaired') {
          return t['importWarningReference']!;
        }
        if (warning.startsWith('Successfully migrated legacy')) {
          return t['importWarningLegacy']!;
        }
        if (warning.endsWith('normalized')) {
          return '${t['importWarningNormalized']}: $warning';
        }
        return '${t['importWarningUnknown']}: $warning';
      }

      final warningDetails = plan.warnings.take(8).map(warningText).join('\n');
      final choice = await showDialog<String>(
        context: context,
        builder:
            (dialogContext) => AlertDialog(
              title: Text(t['importPreview']!),
              content: SingleChildScrollView(
                child: Text(
                  '${mode == 'overwrite' ? t['confirmImport'] : t['importModeMergeDesc']}\n\n$summary\n\n${plan.hasCredential ? t['importCredentialPresent'] : ''}\n\n$warningDetails\n\n${plan.conflicts > 0 ? t['importConflictBlocked'] : ''}',
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(t['cancel']!),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                  ),
                  onPressed:
                      plan.conflicts > 0
                          ? null
                          : () => Navigator.pop(dialogContext, 'keep'),
                  child: Text(
                    plan.hasCredential
                        ? t['importKeepCredential']!
                        : t['confirm']!,
                  ),
                ),
                if (plan.hasCredential)
                  TextButton(
                    onPressed:
                        plan.conflicts > 0
                            ? null
                            : () => Navigator.pop(dialogContext, 'replace'),
                    child: Text(t['importReplaceCredential']!),
                  ),
              ],
            ),
      );
      if (choice == null || !context.mounted) return;
      applying = true;
      final result = await store.applyImport(
        plan,
        importCredential: choice == 'replace',
      );
      if (!result.success) {
        throw StateError('Import save failed');
      }
      final desktopResult = await _applyDesktopSettings(store);
      _baseUrlController.text = store.aiConfig.baseUrl;
      _apiKeyController.text = store.aiConfig.apiKey;
      _modelController.text = store.aiConfig.model;
      if (context.mounted) {
        final desktopWarning =
            DesktopShellService.instance.isDesktopSupported &&
                    desktopResult.hasFailure
                ? '\n${_desktopStatusText(store.t, DesktopShellService.instance)}'
                : '';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${store.t['importSuccess']} (${plan.addedTasks})$desktopWarning',
            ),
          ),
        );
      }
    } on FormatException catch (error) {
      if (context.mounted) {
        final message =
            error.message.startsWith('Conflicting')
                ? t['importConflictBlocked']!
                : t['importError']!;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(t[applying ? 'importSaveError' : 'importError']!),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _fileBusy = false);
    }
  }
}

String _themeColorName(Map<String, String> t, ThemeColor color) =>
    t['color${color.name[0].toUpperCase()}${color.name.substring(1)}']!;

/// The dot's own name plus what it changes: `selected` carries which one is on,
/// so the label stays the same across selection.
String _themeColorLabel(Map<String, String> t, ThemeColor color) =>
    (t['a11yThemeColorOption'] ?? 'Theme color: {color}').replaceAll(
      '{color}',
      _themeColorName(t, color),
    );

class _ColorDot extends StatelessWidget {
  final ThemeColor themeColor;
  final Color color;
  final bool selected;
  final String tooltip;
  final String semanticsLabel;
  final VoidCallback onTap;
  const _ColorDot({
    required this.themeColor,
    required this.color,
    required this.selected,
    required this.tooltip,
    required this.semanticsLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AccessibleTapTarget(
      hitTargetKey: ValueKey('theme-color-hit-${themeColor.name}'),
      minSide: AccessibleTapTarget.minTouchTarget,
      ring: AccessibleTapTargetRing.circle,
      ringInset: 4,
      semanticsLabel: semanticsLabel,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      onTap: onTap,
      child: Tooltip(
        message: tooltip,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          width: selected ? 34 : 28,
          height: selected ? 34 : 28,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border:
                selected
                    ? Border.all(
                      width: 3,
                      color: Theme.of(context).colorScheme.surface,
                    )
                    : null,
            boxShadow:
                selected
                    ? [
                      BoxShadow(
                        color: color.withValues(alpha: 0.5),
                        blurRadius: 10,
                        spreadRadius: 1,
                      ),
                    ]
                    : null,
          ),
          child:
              selected
                  ? const Icon(Icons.check, size: 16, color: Colors.white)
                  : null,
        ),
      ),
    );
  }
}

class _TestConnectionButton extends StatefulWidget {
  final Map<String, String> t;
  final Store store;
  const _TestConnectionButton({required this.t, required this.store});

  @override
  State<_TestConnectionButton> createState() => _TestConnectionButtonState();
}

class _TestConnectionButtonState extends State<_TestConnectionButton> {
  bool _probing = false;
  bool _generating = false;
  int _generation = 0;
  ConnectionProbe? _probe;
  AiProbeStep? _generationResult;
  ModelDiscoveryIdentity? _probeIdentity;
  String? _generationModel;

  bool get _busy => _probing || _generating;

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
