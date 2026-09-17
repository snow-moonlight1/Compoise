import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../ai_presets.dart';
import '../ai_service.dart';
import '../models.dart';
import '../services/desktop_shell_service.dart';
import '../shortcuts.dart';
import '../storage.dart';
import '../theme.dart';
import '../ui/platform_ui_policy.dart';
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
  bool _fileBusy = false;

  List<String> _discoveredModels = [];
  bool _fetchingModels = false;
  int _fetchGeneration = 0;
  String? _discoveryError;
  AICancellation? _discoveryCancellation;
  String? _lastFetchedKey;
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
  }

  void _handleApiKeyFocusChange() {
    if (!_apiKeyFocusNode.hasFocus) {
      final store = context.read<Store>();
      _onApiKeySubmittedOrBlurred(store);
    }
  }

  void _invalidateDiscovery() {
    _discoveryCancellation?.cancel();
    _discoveryCancellation = null;
    _fetchGeneration++;
    _fetchingModels = false;
    _lastFetchedKey = null;
    _discoveryError = null;
  }

  void _onProviderChanged(String newProvider, Store store) {
    _invalidateDiscovery();
    final preset = getAIProviderPreset(newProvider);
    _apiKeyController.clear();
    _lastFetchedKey = null;
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

  void _onApiKeySubmittedOrBlurred(Store store) {
    final key = _apiKeyController.text.trim();
    if (key.isNotEmpty && key != _lastFetchedKey && !_fetchingModels) {
      _fetchModels(store);
    }
  }

  Future<void> _fetchModels(Store store, {bool forceRefresh = false}) async {
    final key = _apiKeyController.text.trim();
    if (key.isEmpty) return;

    _discoveryCancellation?.cancel();
    final cancel = _discoveryCancellation = AICancellation();
    final generation = ++_fetchGeneration;
    _lastFetchedKey = key;
    final snapshot = AIConfig.fromJson(store.aiConfig.toJson());
    final identity = jsonEncode(snapshot.toJson());

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
      if (!mounted || generation != _fetchGeneration) return;
      if (identity != jsonEncode(store.aiConfig.toJson())) {
        setState(_invalidateDiscovery);
        return;
      }
      if (cancel.isCancelled) {
        setState(() => _fetchingModels = false);
        return;
      }

      setState(() {
        _fetchingModels = false;
        _discoveredModels = models;
        _lastFetchedKey = key;
        if (models.isEmpty) {
          _discoveryError = store.t['noModelsFound'];
          _customModelMode = true;
        } else {
          final best = pickPreferredModel(
            store.aiConfig.provider,
            models,
            currentModel: store.aiConfig.model,
          );
          store.aiConfig.model = best;
          _modelController.text = best;
          store.updateAIConfig(store.aiConfig);
          _customModelMode = false;
        }
      });
    } catch (e) {
      if (!mounted || generation != _fetchGeneration) return;
      if (identity != jsonEncode(store.aiConfig.toJson())) {
        setState(_invalidateDiscovery);
        return;
      }
      if (cancel.isCancelled) {
        setState(() => _fetchingModels = false);
        return;
      }
      setState(() {
        _fetchingModels = false;
        _discoveryError = aiErrorMessage(e, store.t);
        _customModelMode = true;
      });
    }
  }

  @override
  void dispose() {
    _discoveryCancellation?.cancel();
    _apiKeyFocusNode.removeListener(_handleApiKeyFocusChange);
    _apiKeyFocusNode.dispose();
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
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (final color in ThemeColor.values)
                  _ColorDot(
                    color: themeSeedColors[color]!,
                    selected: store.settings.themeColor == color,
                    tooltip:
                        t['color${color.name[0].toUpperCase()}${color.name.substring(1)}']!,
                    onTap:
                        () => store.updateSettings(
                          (settings) => settings..themeColor = color,
                        ),
                  ),
              ],
            ),
            const SizedBox(height: 20),

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
                        fontWeight: FontWeight.w800,
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
                                  : () =>
                                      _fetchModels(store, forceRefresh: true),
                        ),
              ),
              obscureText: true,
              focusNode: _apiKeyFocusNode,
              controller: _apiKeyController,
              onSubmitted: (_) => _onApiKeySubmittedOrBlurred(store),
              onChanged: (v) {
                _invalidateDiscovery();
                store.aiConfig.apiKey = v;
                store.updateAIConfig(store.aiConfig);
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
                    onPressed: () => _fetchModels(store, forceRefresh: true),
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
                  _invalidateDiscovery();
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
                          : 'deepseek-v4-flash',
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
                  _invalidateDiscovery();
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
                  t['enableThinkingDesc']!,
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
                  if (value != null) {
                    _invalidateDiscovery();
                    store.updateAIConfig(store.aiConfig..protocol = value);
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
                controller: _baseUrlController,
                onChanged: (v) {
                  _invalidateDiscovery();
                  store.updateAIConfig(store.aiConfig..baseUrl = v);
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
                      controller: _baseUrlController,
                      onChanged:
                          (v) =>
                              store.updateAIConfig(store.aiConfig..baseUrl = v),
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

            Container(
              key: const ValueKey('font-preview-card'),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      t['fontPreview'] ?? 'Preview',
                      style: TextStyle(
                        fontFamily: fontFamilyFor(store.settings.fontFamily),
                        fontFamilyFallback: fontFallbackFor(
                          store.settings.fontFamily,
                        ),
                        fontWeight: FontWeight.w600,
                        fontSize: 14 * fontScaleFactor(store.settings.fontSize),
                      ),
                    ),
                  ),
                ],
              ),
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
                (v) {
                  store.updateSettings((s) => s..closeToTray = v);
                  DesktopShellService.instance.applyCloseToTray(v);
                  if (v && mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          t['closeToTrayNotice'] ??
                              'When enabled, closing the window minimizes to the system tray. Right-click the tray icon to exit.',
                        ),
                        duration: const Duration(seconds: 4),
                      ),
                    );
                  }
                },
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      t['globalHotkey'] ?? 'Global Shortcut',
                      style: theme.textTheme.bodyMedium,
                    ),
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
                ],
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
                      onPressed: () async {
                        final now = DateTime.now().millisecondsSinceEpoch;
                        await ReminderService.instance.scheduleReminder(
                          boardId: store.activeBoardId,
                          taskId: 'test-win-notif',
                          title: 'MatrixFlow AI',
                          body:
                              t['testNotificationSent'] ??
                              'Test notification sent!',
                          triggerAtMs: now,
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                t['testNotificationSent'] ??
                                    'Test notification sent!',
                              ),
                              duration: const Duration(seconds: 3),
                            ),
                          );
                        }
                      },
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

  Future<void> _checkAndShowPermissions(
    BuildContext context,
    Map<String, String> t,
  ) async {
    final status = await ReminderService.instance.checkPermission();
    if (!context.mounted) return;

    final String statusText;
    final Color color;
    final bool canRequest;

    switch (status) {
      case ReminderPermissionStatus.granted:
        statusText =
            defaultTargetPlatform == TargetPlatform.windows
                ? (t['windowsPermissionActive'] ??
                    'Windows Desktop Notifications are active and ready.')
                : (t['permissionGranted'] ?? 'Granted');
        color = Colors.green;
        canRequest = false;
      case ReminderPermissionStatus.denied:
        statusText = t['permissionDenied'] ?? 'Denied';
        color = Colors.red;
        canRequest = true;
      case ReminderPermissionStatus.inexactOnly:
        statusText = t['permissionInexact'] ?? 'Inexact only';
        color = Colors.orange;
        canRequest = true;
      case ReminderPermissionStatus.unsupported:
        statusText = 'Unsupported on this platform';
        color = Colors.grey;
        canRequest = false;
    }

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
                    await ReminderService.instance.requestPermission();
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
                fontWeight: FontWeight.w800,
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
      final bytes = Uint8List.fromList(utf8.encode(store.exportJson()));
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
        ).showSnackBar(SnackBar(content: Text(path)));
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
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );
      if (!context.mounted || picked == null) return;
      final file = picked.files.single;
      final bytes =
          file.bytes ??
          (file.path == null ? null : await File(file.path!).readAsBytes());
      if (bytes == null) throw const FormatException('No file data');
      final json = jsonDecode(
        utf8.decode(bytes).replaceFirst(RegExp(r'^\uFEFF'), ''),
      );
      if (json is! Map<String, dynamic> ||
          json['boards'] is! List ||
          json['tasks'] is! List) {
        throw const FormatException('bad shape');
      }
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
      if (mode == 'overwrite') {
        final sure = await showDialog<bool>(
          context: context,
          builder:
              (dialogContext) => AlertDialog(
                content: Text(t['confirmImport']!),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: Text(t['cancel']!),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.error,
                    ),
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: Text(t['confirm']!),
                  ),
                ],
              ),
        );
        if (sure != true || !context.mounted) return;
      }
      final count = store.importData(json, mode);
      _baseUrlController.text = store.aiConfig.baseUrl;
      _apiKeyController.text = store.aiConfig.apiKey;
      _modelController.text = store.aiConfig.model;
      await store.flush();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              store.persistenceError ?? '${store.t['importSuccess']} ($count)',
            ),
          ),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(t['importError']!)));
      }
    } finally {
      if (mounted) setState(() => _fileBusy = false);
    }
  }
}

class _ColorDot extends StatelessWidget {
  final Color color;
  final bool selected;
  final String tooltip;
  final VoidCallback onTap;
  const _ColorDot({
    required this.color,
    required this.selected,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
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
    ).gestures(onTap: onTap);
  }
}

extension _Gestures on Widget {
  Widget gestures({VoidCallback? onTap}) =>
      GestureDetector(onTap: onTap, child: this);
}

class _TestConnectionButton extends StatefulWidget {
  final Map<String, String> t;
  final Store store;
  const _TestConnectionButton({required this.t, required this.store});

  @override
  State<_TestConnectionButton> createState() => _TestConnectionButtonState();
}

class _TestConnectionButtonState extends State<_TestConnectionButton> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: _busy ? null : _run,
      icon:
          _busy
              ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
              : const Icon(Icons.wifi_tethering, size: 18),
      label: Text(
        _busy ? widget.t['processing']! : widget.t['testConnection']!,
      ),
    );
  }

  Future<void> _run() async {
    setState(() => _busy = true);
    final result = await widget.store.ai.testConnection(
      AIConfig.fromJson(widget.store.aiConfig.toJson()),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.ok
              ? widget.t['testOk']!
              : widget.t[result.message] ??
                  '${widget.t['testFail']} (${result.message})',
        ),
        backgroundColor:
            result.ok
                ? Colors.green.shade600
                : Theme.of(context).colorScheme.error,
      ),
    );
  }
}
