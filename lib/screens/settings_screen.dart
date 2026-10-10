import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../ai_capabilities.dart';
import '../ai_presets.dart';
import '../models.dart';
import '../services/desktop_shell_service.dart';
import '../shortcuts.dart';
import '../storage.dart';
import '../theme.dart';
import '../ui/font_policy.dart';
import '../ui/songti_font.dart';
import '../ui/motion_policy.dart';
import '../ui/platform_ui_policy.dart';
import '../widgets/accessible_tap_target.dart';
import 'onboarding_screen.dart';
import 'settings_backup_flow.dart';
import 'settings_desktop.dart';
import 'settings_model_request.dart';

enum _SettingsPanel { assistant, font }

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
  String? _lastSyncedBaseUrl;
  String? _lastSyncedModel;

  // Bumps while a detail route is up, because that route does not rebuild
  // when this screen's setState runs underneath it.
  final _detailUpdates = ValueNotifier<int>(0);

  // The model-list request and the backup files each own their lifecycle; the
  // screen renders their state and reports the outcome it gets back.
  late final ModelRequestSession _models = ModelRequestSession(
    onChanged: () {
      if (mounted) setState(() {});
    },
    onAdoptModel: (store, model) {
      _modelController.text = model;
      _editAIConfig(store, (config) => config.model = model);
    },
  );

  late final SettingsBackupFlow _backup = SettingsBackupFlow(
    onBusyChanged: (_) {
      if (mounted) setState(() {});
    },
  );

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
    _models.commit(context.read<Store>());
  }

  void _handleBaseUrlFocusChange() {
    if (_baseUrlFocusNode.hasFocus) {
      _baseUrlHadFocus = true;
      return;
    }
    if (!_baseUrlHadFocus) return;
    _baseUrlHadFocus = false;
    _models.commit(context.read<Store>());
  }

  Future<void> _editDesktopHotkey(
    BuildContext context,
    Store store,
    Map<String, String> t,
  ) async {
    var editedShortcut = store.settings.globalShortcut;
    final shortcut = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(t['desktopHotkeyChange'] ?? 'Change global shortcut'),
        content: TextFormField(
          key: const ValueKey('desktop-hotkey-input'),
          initialValue: editedShortcut,
          autofocus: true,
          onChanged: (value) => editedShortcut = value,
          decoration: InputDecoration(
            hintText:
                t['desktopHotkeyHint'] ?? 'Ctrl+Alt+M (leave empty to disable)',
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
    await applyDesktopSettings(store);
  }

  void _editAIConfig(Store store, void Function(AIConfig) edit) {
    final next = store.copyAIConfig();
    edit(next);
    store.updateAIConfig(next);
  }

  void _onProviderChanged(String newProvider, Store store) {
    // The old provider's list, error and in-flight reply are all obsolete now;
    // so is a custom-model choice made against the previous provider.
    _models.invalidate();
    _models.customModelMode = false;
    final preset = getAIProviderPreset(newProvider);
    _apiKeyController.clear();

    final next = store.copyAIConfig();
    next.provider = newProvider;
    next.apiKey = '';
    if (!preset.isCustom) {
      next.baseUrl = preset.defaultBaseUrl;
      next.protocol = preset.defaultProtocol;
      next.model = preset.defaultModel;
      _baseUrlController.text = preset.defaultBaseUrl;
      _modelController.text = preset.defaultModel;
    }
    store.updateAIConfig(next);

    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(store.t['providerSwitchedTip']!),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    // The font and provider pages are their own routes. Rebuilding this
    // screen does not rebuild them, so tell the open page to build again.
    if (_detailUpdates.hasListeners) _detailUpdates.value++;
  }

  @override
  void dispose() {
    _detailUpdates.dispose();
    _models.dispose();
    _backup.close();
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

    _models.syncWithLiveConfig(store);

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
              t['settingsAppearance']!,
              Icons.display_settings_outlined,
            ),
            _SettingsExpander(
              id: 'settings-language-row',
              title: t['language']!,
              value: _languageLabel(store.settings.language),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final language in Language.values)
                    _appearanceChip(
                      key: ValueKey('settings-language-${language.name}'),
                      selected: store.settings.language == language,
                      onSelected: (_) {
                        store.updateSettings(
                          (settings) => settings..language = language,
                        );
                        unawaited(applyDesktopSettings(store));
                      },
                      label: Text(switch (language) {
                        Language.en => 'EN',
                        Language.zh => '中文',
                        Language.ja => '日本語',
                      }),
                    ),
                ],
              ),
            ),
            _SettingsExpander(
              id: 'settings-theme-row',
              title: t['theme']!,
              value:
                  t[switch (store.settings.theme) {
                    ThemeModePref.light => 'themeLight',
                    ThemeModePref.dark => 'themeDark',
                    _ => 'themeSystem',
                  }]!,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final mode in ThemeModePref.values)
                    _appearanceChip(
                      selected: store.settings.theme == mode,
                      onSelected: (_) => store.updateSettings(
                        (settings) => settings..theme = mode,
                      ),
                      label: Text(
                        t[switch (mode) {
                          ThemeModePref.light => 'themeLight',
                          ThemeModePref.dark => 'themeDark',
                          _ => 'themeSystem',
                        }]!,
                      ),
                    ),
                ],
              ),
            ),
            _SettingsExpander(
              id: 'settings-color-row',
              title: t['themeColor']!,
              value: _themeColorName(t, store.settings.themeColor),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (final color in ThemeColor.values)
                    _ColorDot(
                      themeColor: color,
                      color: themeSeedColors[color]!,
                      selected: store.settings.themeColor == color,
                      tooltip: _themeColorName(t, color),
                      semanticsLabel: _themeColorLabel(t, color),
                      onTap: () => store.updateSettings(
                        (settings) => settings..themeColor = color,
                      ),
                    ),
                ],
              ),
            ),
            _navRow(
              key: const ValueKey('settings-font-row'),
              title: t['fontAndDisplay']!,
              value:
                  '${_fontSizeLabel(t, store.settings.fontSize)} · ${_fontFamilyLabel(t, store.settings.fontFamily)}',
              onTap: () => _openDetail(_SettingsPanel.font),
            ),
            _toggle(
              context,
              t['reduceMotion'] ?? 'Reduce animation',
              t['reduceMotionDesc'] ??
                  'Jump straight to the final state instead of playing entrance, strikethrough and exit animations.',
              store.settings.reduceMotion,
              (v) => store.updateSettings((s) => s..reduceMotion = v),
              key: const ValueKey('reduce-motion-toggle'),
            ),
            _toggle(
              context,
              t['comicOutline']!,
              t['comicOutlineDesc'],
              store.settings.comicOutline,
              (v) => store.updateSettings(
                (s) => s
                  ..comicOutline = v
                  // The two skins are alternatives; enabling one clears the
                  // other so the comparison is always against the default.
                  ..neumorphic = s.neumorphic && !v,
              ),
              key: const ValueKey('comic-outline-switch'),
            ),
            _toggle(
              context,
              t['neumorphic']!,
              t['neumorphicDesc'],
              store.settings.neumorphic,
              (v) => store.updateSettings(
                (s) => s
                  ..neumorphic = v
                  ..comicOutline = s.comicOutline && !v,
              ),
              key: const ValueKey('neumorphic-switch'),
            ),
            const SizedBox(height: 12),

            _sectionTitle(
              theme,
              t['settingsTaskBehavior'] ?? t['automation']!,
              Icons.auto_mode_outlined,
            ),
            _toggle(
              context,
              t['showCompletionRate'] ?? 'Show overall completion rate',
              t['showCompletionRateDesc'] ??
                  'Show the share of completed tasks across all boards at the bottom of the More panel.',
              store.settings.showCompletionRate,
              (v) => store.updateSettings((s) => s..showCompletionRate = v),
              key: const ValueKey('show-completion-rate-toggle'),
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
            _SettingsExpander(
              id: 'settings-urgency-row',
              title: t['urgencyThreshold']!,
              subtitle:
                  (t['urgencyThresholdDesc'] ??
                          'Promote uncompleted main tasks with deadlines to urgent {n} days in advance (including today).')
                      .replaceAll(
                        '{n}',
                        '${store.settings.urgencyThresholdDays}',
                      ),
              value: '${store.settings.urgencyThresholdDays}${t['daysLeft']}',
              child: Slider(
                min: 1,
                max: 14,
                divisions: 13,
                value: store.settings.urgencyThresholdDays.toDouble(),
                onChanged: (v) => store.updateSettings(
                  (settings) => settings..urgencyThresholdDays = v.round(),
                ),
              ),
            ),
            const SizedBox(height: 20),

            _sectionTitle(theme, t['provider']!, Icons.smart_toy_outlined),
            _navRow(
              key: const ValueKey('settings-assistant-row'),
              title: preset.name(t),
              subtitle: store.aiConfig.model.trim().isEmpty
                  ? null
                  : store.aiConfig.model,
              onTap: () => _openDetail(_SettingsPanel.assistant),
            ),
            const SizedBox(height: 12),

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
            if (store.windowsCredentialsNeedSetup)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(t['upgradeCredentials']!),
              ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.download_outlined, size: 18),
                    label: Text(t['exportData']!),
                    onPressed: _backup.busy
                        ? null
                        : () => _runExport(context, store),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.upload_outlined, size: 18),
                    label: Text(t['importData']!),
                    onPressed: _backup.busy
                        ? null
                        : () => _runImport(context, store),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(t['backupVersionInfo']!, style: theme.textTheme.bodySmall),
            const SizedBox(height: 24),

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
                  final result = await applyDesktopSettings(store);
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
                        color: result?.hasFailure == true
                            ? theme.colorScheme.error
                            : theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          desktopStatusText(t, shell),
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                      if (result?.hasFailure == true &&
                          !shell.isApplyingSettings)
                        TextButton(
                          key: const ValueKey('desktop-shell-retry'),
                          onPressed: () async {
                            await applyDesktopSettings(store);
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
      builder: (dialogCtx) => AlertDialog(
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
                    t['windowsGuideTrayTitle'] ?? '1. System Tray Keep-Alive',
                steps: t['windowsGuideTraySteps'] ?? '',
              ),
              const SizedBox(height: 12),
              _buildGuideItem(
                context,
                title: t['windowsGuideFocusTitle'] ?? '2. Windows Focus Assist',
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
      builder: (dialogCtx) => AlertDialog(
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
      title: t['appTitle']!,
      body: t['reminderTestBody'] ?? 'Compoise test notification',
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
      builder: (dialogCtx) => AlertDialog(
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
                    style: TextStyle(color: color, fontWeight: FontWeight.w600),
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
              child: Text(t['requestPermissionBtn'] ?? 'Request Permission'),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: Text(t['confirm'] ?? 'OK'),
          ),
        ],
      ),
    );
  }

  void _syncDetailControllers(Store store) {
    if (_lastSyncedBaseUrl != store.aiConfig.baseUrl) {
      _lastSyncedBaseUrl = store.aiConfig.baseUrl;
      _baseUrlController.text = store.aiConfig.baseUrl;
    }
    if (_lastSyncedModel != store.aiConfig.model) {
      _lastSyncedModel = store.aiConfig.model;
      _modelController.text = store.aiConfig.model;
    }
  }

  void _openDetail(_SettingsPanel panel) {
    final host = this;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _SettingsSubpage(panel: panel, host: host),
      ),
    );
  }

  Widget _navRow({
    required Key key,
    required String title,
    String? subtitle,
    String? value,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return ListTile(
      key: key,
      contentPadding: EdgeInsets.zero,
      title: Text(title, style: theme.textTheme.bodyMedium),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (value != null && value.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 148),
              child: Text(
                value,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant),
        ],
      ),
      onTap: onTap,
    );
  }

  List<Widget> _assistantFields(
    Store store,
    Map<String, String> t,
    ThemeData theme,
    AIProviderPreset preset,
  ) {
    return [
      _raisedMenu(
        DropdownButton<String>(
          key: const ValueKey('provider-selector'),
          isExpanded: true,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          underline: NeumorphicSkin.maybeOf(context) == null
              ? null
              : const SizedBox.shrink(),
          value: store.aiConfig.provider,
          items: [
            for (final p in aiProviderPresets)
              DropdownMenuItem(value: p.id, child: Text(p.name(t))),
          ],
          onChanged: (newProvider) {
            if (newProvider != null && newProvider != store.aiConfig.provider) {
              _onProviderChanged(newProvider, store);
            }
          },
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        key: const ValueKey('api-key-input'),
        textAlignVertical: _fieldAlign,
        autocorrect: false,
        enableSuggestions: false,
        decoration: _inputDecoration(
          labelText: t['customApiKey'],
          hintText: preset.keyHint,
          suffixIcon: _models.isFetching
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
                  style: _inFieldIconStyle,
                  icon: const Icon(Icons.refresh, size: 20),
                  tooltip: t['refreshModels'],
                  onPressed: _apiKeyController.text.trim().isEmpty
                      ? null
                      : () => _models.commit(store, forceRefresh: true),
                ),
        ),
        obscureText: true,
        focusNode: _apiKeyFocusNode,
        controller: _apiKeyController,
        onSubmitted: (_) => _models.commit(store),
        onChanged: (v) {
          _editAIConfig(store, (config) => config.apiKey = v);
          _models.credentialOrEndpointChanged(store);
        },
      ),
      if (_models.isFetching) ...[
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
      ] else if (_models.error != null) ...[
        const SizedBox(height: 6),
        Row(
          children: [
            Icon(Icons.error_outline, size: 14, color: theme.colorScheme.error),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                _models.error!,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
            TextButton(
              key: const ValueKey('discovery-retry'),
              onPressed: () => _models.commit(store, forceRefresh: true),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
      if (_models.models.isNotEmpty && !_models.customModelMode) ...[
        _raisedMenu(
        DropdownButtonFormField<String>(
          key: const ValueKey('model-selector'),
          isExpanded: true,
          decoration: _inputDecoration(
            labelText: t['customModel'],
            menu: true,
          ),
          value: _models.models.contains(store.aiConfig.model)
              ? store.aiConfig.model
              : '__custom__',
          items: [
            for (final m in _models.models)
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
                _models.customModelMode = true;
              });
            } else if (val != null) {
              _modelController.text = val;
              _editAIConfig(store, (config) => config.model = val);
            }
          },
        ),
        ),
      ] else ...[
        TextField(
          key: const ValueKey('model-input'),
          textAlignVertical: _fieldAlign,
          decoration: _inputDecoration(
            labelText: t['customModel'],
            hintText: preset.defaultModel.isNotEmpty
                ? preset.defaultModel
                : t['enterModelHint'],
            suffixIcon: _models.models.isNotEmpty
                ? IconButton(
                    style: _inFieldIconStyle,
                    icon: const Icon(Icons.list, size: 20),
                    tooltip: t['selectModel'],
                    onPressed: () {
                      setState(() {
                        _models.customModelMode = false;
                      });
                    },
                  )
                : null,
          ),
          controller: _modelController,
          onChanged: (v) {
            _editAIConfig(store, (config) => config.model = v);
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
            t[planThinking(store.aiConfig).hintCode ?? 'enableThinkingDesc']!,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          value: store.aiConfig.enableThinking,
          onChanged: (v) =>
              _editAIConfig(store, (config) => config.enableThinking = v),
        ),
      ],
      if (preset.isCustom) ...[
        const SizedBox(height: 10),
        _raisedMenu(
          DropdownButton<AIProtocol>(
          key: const ValueKey('protocol-selector'),
          isExpanded: true,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          underline: NeumorphicSkin.maybeOf(context) == null
              ? null
              : const SizedBox.shrink(),
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
              _editAIConfig(store, (config) => config.protocol = value);
              _models.invalidate();
              setState(() {});
            }
          },
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('base-url-input'),
          textAlignVertical: _fieldAlign,
          autocorrect: false,
          keyboardType: TextInputType.url,
          decoration: _inputDecoration(
            labelText: t['customBaseUrl'],
            hintText: 'https://api.deepseek.com',
          ),
          focusNode: _baseUrlFocusNode,
          controller: _baseUrlController,
          onSubmitted: (_) => _models.commit(store),
          onChanged: (v) {
            _editAIConfig(store, (config) => config.baseUrl = v);
            _models.credentialOrEndpointChanged(store);
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
                textAlignVertical: _fieldAlign,
                autocorrect: false,
                keyboardType: TextInputType.url,
                decoration: _inputDecoration(
                  labelText: t['customBaseUrl'],
                  hintText: preset.defaultBaseUrl,
                ),
                focusNode: _baseUrlFocusNode,
                controller: _baseUrlController,
                onSubmitted: (_) => _models.commit(store),
                onChanged: (v) {
                  _editAIConfig(store, (config) => config.baseUrl = v);
                  _models.credentialOrEndpointChanged(store);
                },
              ),
              const SizedBox(height: 6),
              Text(
                t['customUrlHint']!,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ],
      Builder(
        builder: (context) {
          final tip = Row(
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
          );
          if (NeumorphicSkin.maybeOf(context) != null) {
            return neuSlab(
              context,
              inset: true,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: tip,
              ),
            );
          }
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            margin: const EdgeInsets.only(top: 4, bottom: 4),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: theme.colorScheme.primary.withValues(alpha: 0.25),
              ),
            ),
            child: tip,
          );
        },
      ),
      const SizedBox(height: 10),
      TestConnectionButton(t: t, store: store),
    ];
  }

  List<Widget> _fontFields(
    Store store,
    Map<String, String> t,
    ThemeData theme,
  ) {
    return [
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
        runSpacing: 8,
        children: [
          for (final size in FontSizePref.values)
            _appearanceChip(
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
        runSpacing: 8,
        children: [
          for (final family in FontFamilyPref.values)
            _appearanceChip(
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
              onSelected: (_) => unawaited(_chooseFamily(store, family)),
            ),
        ],
      ),
      const SizedBox(height: 14),

      Builder(
        builder: (context) {
          final fonts = AppFontPolicy.of(context);
          final family = fonts.familyFor(store.settings.fontFamily);
          final fallback = fonts.fallbackFor(store.settings.fontFamily);
          // The app-wide CombinedTextScaler already applies the font size
          // preference, so the base sizes here stay unscaled.
          final neuPreview = NeumorphicSkin.maybeOf(context) != null;
          final card = Container(
            key: const ValueKey('font-preview-card'),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: neuPreview
                ? null
                : BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.4,
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t['fontPreviewTitle'] ??
                      'Urgent and Important · Compoise 123',
                  key: const ValueKey('font-preview-title'),
                  style: TextStyle(
                    fontFamily: family,
                    fontFamilyFallback: fallback,
                    fontWeight: fonts.titleWeight,
                    fontSize: 16,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  t['fontPreview'] ?? 'Preview: Urgent & Important Task 123',
                  key: const ValueKey('font-preview-body'),
                  style: TextStyle(
                    fontFamily: family,
                    fontFamilyFallback: fallback,
                    fontWeight: fonts.bodyWeight,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  t['fontPreviewSample'] ?? '紧急且重要，购买牛奶；方寸 123；日本語テスト',
                  key: const ValueKey('font-preview-sample'),
                  style: TextStyle(
                    fontFamily: family,
                    fontFamilyFallback: fallback,
                    fontWeight: fonts.bodyWeight,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
                if (store.settings.fontFamily == FontFamilyPref.monospace) ...[
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
          return neuPreview
              ? neuSlab(context, inset: true, child: card)
              : card;
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
    ];
  }

  Future<void> _chooseFamily(Store store, FontFamilyPref family) async {
    if (family != FontFamilyPref.serif) {
      store.setFontFamily(family);
      return;
    }
    final installed = await SongtiFonts.isInstalled();
    if (SongtiFonts.loaded || installed) {
      await SongtiFonts.ensureLoaded();
      if (!mounted) return;
      store.setFontFamily(FontFamilyPref.serif);
      return;
    }
    if (!mounted) return;
    final agreed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const ValueKey('songti-download-dialog'),
        title: Text(store.t['songtiDownloadTitle']!),
        content: Text(
          store.t['songtiDownloadBody']!.replaceAll(
            '{n}',
            '${SongtiFonts.approxMegabytes}',
          ),
        ),
        actions: [
          TextButton(
            key: const ValueKey('songti-download-cancel'),
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(store.t['cancel']!),
          ),
          FilledButton(
            key: const ValueKey('songti-download-confirm'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(store.t['songtiDownloadAction']!),
          ),
        ],
      ),
    );
    if (agreed != true || !mounted) return;
    BuildContext? dialogContext;
    void Function(double? value)? report;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        dialogContext = ctx;
        return _SongtiProgressDialog(
          message: store.t['songtiDownloading']!,
          onReady: (fn) => report = fn,
        );
      },
    );
    await WidgetsBinding.instance.endOfFrame;
    try {
      await SongtiFonts.download(onProgress: (value) => report?.call(value));
      if (!mounted) return;
      store.setFontFamily(FontFamilyPref.serif);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(store.t['songtiDownloadFailed']!)));
    } finally {
      final ctx = dialogContext;
      if (ctx != null && ctx.mounted) Navigator.pop(ctx);
    }
  }

  /// A chooser is a raised control. A text field stays an inset well.
  /// Horizontal gutter stays zero so both faces are the same width.
  /// Vertical padding holds the raised pair, which reaches about 10px
  /// past the face, so it does not land on the next label.
  Widget _raisedMenu(Widget child) {
    if (NeumorphicSkin.maybeOf(context) == null) return child;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: neuSlab(context, gutter: 0, child: child),
    );
  }

  TextAlignVertical? get _fieldAlign => NeumorphicSkin.maybeOf(context) == null
      ? null
      : TextAlignVertical.top;

  InputDecoration _inputDecoration({
    String? labelText,
    String? hintText,
    Widget? suffixIcon,
    bool menu = false,
  }) {
    final neu = NeumorphicSkin.maybeOf(context) != null;
    const none = InputBorder.none;
    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      floatingLabelBehavior: FloatingLabelBehavior.always,
      // The icon is centered on the whole field, including the label band.
      // Nudge it down so it sits on the same line as the value.
      suffixIcon: suffixIcon == null || !neu || menu
          ? suffixIcon
          : Padding(padding: const EdgeInsets.only(top: 12), child: suffixIcon),
      filled: menu && neu ? false : null,
      border: menu && neu ? none : null,
      enabledBorder: menu && neu ? none : null,
      focusedBorder: menu && neu ? none : null,
      errorBorder: menu && neu ? none : null,
      focusedErrorBorder: menu && neu ? none : null,
      disabledBorder: menu && neu ? none : null,
      contentPadding: menu && neu
          ? const EdgeInsets.symmetric(horizontal: 16, vertical: 16)
          : null,
    );
  }

  /// Stays inside the field. The themed icon button would grow its own face
  /// and make this well shorter than the others.
  ButtonStyle get _inFieldIconStyle {
    return IconButton.styleFrom(
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.all(8),
      minimumSize: const Size(48, 48),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ).copyWith(
      overlayColor: const WidgetStatePropertyAll(Color(0x00000000)),
      splashFactory: NoSplash.splashFactory,
      backgroundBuilder: (context, states, child) =>
          child ?? const SizedBox.shrink(),
    );
  }

  Widget _appearanceChip({
    Key? key,
    required bool selected,
    required Widget label,
    required ValueChanged<bool> onSelected,
  }) {
    final neu = NeumorphicSkin.maybeOf(context);
    if (neu == null) {
      return ChoiceChip(
        key: key,
        label: label,
        selected: selected,
        onSelected: onSelected,
      );
    }
    // Same face either way. Selected sinks in; a check would turn it back
    // into a flat Material pill and make it look smaller than its neighbors.
    final accent = Theme.of(context).colorScheme.primary;
    return neuSlab(
      context,
      inset: selected,
      gutter: 6,
      child: TextButton(
        key: key,
        onPressed: () => onSelected(true),
        style: TextButton.styleFrom(
          foregroundColor: selected ? accent : neu.ink,
          backgroundColor: const Color(0x00000000),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          minimumSize: const Size(48, 40),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(NeumorphicSkin.radius),
          ),
        ).copyWith(
          overlayColor: const WidgetStatePropertyAll(Color(0x00000000)),
          splashFactory: NoSplash.splashFactory,
          backgroundBuilder: (context, states, child) =>
              child ?? const SizedBox.shrink(),
        ),
        child: label,
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
      subtitle: subtitle == null
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

  Future<void> _runExport(BuildContext context, Store store) async {
    final result = await _backup.export(context, store);
    if (!context.mounted || result.message == null) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(result.message!)));
  }

  Future<void> _runImport(BuildContext context, Store store) async {
    final result = await _backup.importBackup(
      context,
      store,
      syncAiFields: () {
        _baseUrlController.text = store.aiConfig.baseUrl;
        _apiKeyController.text = store.aiConfig.apiKey;
        _modelController.text = store.aiConfig.model;
      },
    );
    if (!context.mounted || result.message == null) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(result.message!)));
  }
}

String _languageLabel(Language language) => switch (language) {
  Language.en => 'EN',
  Language.zh => '中文',
  Language.ja => '日本語',
};

String _fontSizeLabel(Map<String, String> t, FontSizePref size) =>
    t[switch (size) {
      FontSizePref.small => 'fontSizeSmall',
      FontSizePref.standard => 'fontSizeStandard',
      FontSizePref.large => 'fontSizeLarge',
    }] ??
    size.name;

String _fontFamilyLabel(Map<String, String> t, FontFamilyPref family) =>
    t[switch (family) {
      FontFamilyPref.system => 'fontSystem',
      FontFamilyPref.sansSerif => 'fontSansSerif',
      FontFamilyPref.serif => 'fontSerif',
      FontFamilyPref.monospace => 'fontMonospace',
    }] ??
    family.name;

String _themeColorName(Map<String, String> t, ThemeColor color) =>
    t['color${color.name[0].toUpperCase()}${color.name.substring(1)}']!;

/// The dot's own name plus what it changes: `selected` carries which one is on,
/// so the label stays the same across selection.
String _themeColorLabel(Map<String, String> t, ThemeColor color) =>
    (t['a11yThemeColorOption'] ?? 'Theme color: {color}').replaceAll(
      '{color}',
      _themeColorName(t, color),
    );

class _SettingsExpander extends StatefulWidget {
  final String id;
  final String title;
  final String? subtitle;
  final String? value;
  final Widget child;

  const _SettingsExpander({
    required this.id,
    required this.title,
    this.subtitle,
    this.value,
    required this.child,
  });

  @override
  State<_SettingsExpander> createState() => _SettingsExpanderState();
}

class _SettingsExpanderState extends State<_SettingsExpander>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final CurvedAnimation _curve;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
      reverseDuration: const Duration(milliseconds: 240),
    );
    // Emphasized decelerate on the way open, emphasized accelerate on the
    // way shut. A linear tween reads as a mechanical slide.
    _curve = CurvedAnimation(
      parent: _controller,
      curve: const Cubic(0.05, 0.7, 0.1, 1.0),
      reverseCurve: const Cubic(0.3, 0.0, 0.8, 0.15),
    );
  }

  @override
  void dispose() {
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    if (MotionPolicy.reduceMotionNow(context)) {
      _controller.value = _controller.value == 0 ? 1 : 0;
      return;
    }
    if (_controller.value == 0) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          key: ValueKey(widget.id),
          contentPadding: EdgeInsets.zero,
          title: Text(widget.title, style: theme.textTheme.bodyMedium),
          subtitle: widget.subtitle == null
              ? null
              : Text(
                  widget.subtitle!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.value != null && widget.value!.isNotEmpty)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 148),
                  child: Text(
                    widget.value!,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              AnimatedBuilder(
                animation: _curve,
                builder: (context, child) {
                  return AnimatedRotation(
                    key: ValueKey('${widget.id}-chevron'),
                    turns: _curve.value * 0.25,
                    duration: Duration.zero,
                    child: child,
                  );
                },
                child: Icon(
                  Icons.chevron_right,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          onTap: _toggle,
        ),
        AnimatedBuilder(
          animation: _curve,
          builder: (context, child) {
            final show =
                _curve.value > 0 ||
                _controller.status == AnimationStatus.forward;
            if (!show) return const SizedBox(width: double.infinity);
            return ClipRect(
              child: Align(
                alignment: Alignment.topCenter,
                heightFactor: _curve.value,
                child: child,
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 12),
            child: widget.child,
          ),
        ),
      ],
    );
  }
}

class _SettingsSubpage extends StatefulWidget {
  final _SettingsPanel panel;
  final _SettingsScreenState host;

  const _SettingsSubpage({required this.panel, required this.host});

  @override
  State<_SettingsSubpage> createState() => _SettingsSubpageState();
}

class _SettingsSubpageState extends State<_SettingsSubpage> {
  @override
  void initState() {
    super.initState();
    widget.host._detailUpdates.addListener(_onHost);
  }

  @override
  void dispose() {
    widget.host._detailUpdates.removeListener(_onHost);
    super.dispose();
  }

  void _onHost() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<Store>();
    final t = store.t;
    final theme = Theme.of(context);
    final preset = getAIProviderPreset(store.aiConfig.provider);
    // The text fields live on this route, so the controllers have to be
    // aligned here. Doing it in the settings page underneath notifies a
    // field that is not its descendant.
    widget.host._models.syncWithLiveConfig(store);
    widget.host._syncDetailControllers(store);
    final title = switch (widget.panel) {
      _SettingsPanel.assistant => t['provider']!,
      _SettingsPanel.font => t['fontAndDisplay']!,
    };
    final children = switch (widget.panel) {
      _SettingsPanel.assistant => widget.host._assistantFields(
        store,
        t,
        theme,
        preset,
      ),
      _SettingsPanel.font => widget.host._fontFields(store, t, theme),
    };
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            const padding = EdgeInsets.fromLTRB(16, 8, 16, 32);
            final minHeight = constraints.maxHeight - padding.vertical;
            return ListView(
              key: const ValueKey('settings-detail-list'),
              padding: padding,
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: minHeight < 0 ? 0 : minHeight,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: children,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SongtiProgressDialog extends StatefulWidget {
  final String message;
  final void Function(void Function(double? value) report) onReady;

  const _SongtiProgressDialog({required this.message, required this.onReady});

  @override
  State<_SongtiProgressDialog> createState() => _SongtiProgressDialogState();
}

class _SongtiProgressDialogState extends State<_SongtiProgressDialog> {
  double? _value;

  @override
  void initState() {
    super.initState();
    widget.onReady((value) {
      if (mounted) setState(() => _value = value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final percent = _value == null ? null : (_value!.clamp(0, 1) * 100).round();
    return AlertDialog(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.message),
          const SizedBox(height: 16),
          LinearProgressIndicator(
            key: const ValueKey('songti-download-progress'),
            value: _value,
          ),
          if (percent != null) ...[
            const SizedBox(height: 8),
            Text('$percent%', textAlign: TextAlign.end),
          ],
        ],
      ),
    );
  }
}

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
    // Same reduced-motion policy as the task animations: the dot has to reach
    // its final size on the first frame instead of tweening to it.
    final selectionDuration = MotionPolicy.reduceMotionOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 200);
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
          duration: selectionDuration,
          curve: Curves.easeOut,
          width: selected ? 34 : 28,
          height: selected ? 34 : 28,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: selected
                ? Border.all(
                    width: 3,
                    color: Theme.of(context).colorScheme.surface,
                  )
                : null,
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.5),
                      blurRadius: 10,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: selected
              ? const Icon(Icons.check, size: 16, color: Colors.white)
              : null,
        ),
      ),
    );
  }
}
