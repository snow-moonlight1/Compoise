import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/android_reminder_settings.dart';
import '../storage.dart';
import '../ui/platform_ui_policy.dart';
import '../widgets/app_notice.dart';

const reminderSetupSeenKey = 'compoise-android-reminder-setup-seen';

Future<void> maybeShowAndroidReminderSetup(BuildContext context) async {
  if (PlatformUiPolicy.of(context).platform != TargetPlatform.android) return;
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(reminderSetupSeenKey) == true || !context.mounted) return;
  const settings = AndroidReminderSettings();
  final status = await settings.status();
  if (status == null || !context.mounted) return;
  // Record the visit before entering system settings, where Android can kill
  // and restart the process. The setup remains reachable from Settings.
  await prefs.setBool(reminderSetupSeenKey, true);
  if (!context.mounted) return;
  if (status.granted &&
      (!status.autoStartAvailable || status.autoStart == true)) {
    return;
  }
  await Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) =>
          AndroidReminderSetupScreen(initial: status, firstVisit: true),
    ),
  );
}

class AndroidReminderSetupScreen extends StatefulWidget {
  const AndroidReminderSetupScreen({
    super.key,
    this.settings = const AndroidReminderSettings(),
    this.initial,
    this.firstVisit = false,
  });
  final AndroidReminderSettings settings;
  final AndroidReminderStatus? initial;
  final bool firstVisit;
  @override
  State<AndroidReminderSetupScreen> createState() =>
      _AndroidReminderSetupScreenState();
}

class _AndroidReminderSetupScreenState extends State<AndroidReminderSetupScreen>
    with WidgetsBindingObserver {
  AndroidReminderStatus? _status;
  bool _busy = false;
  bool _reading = true;
  int _refreshVersion = 0;
  @override
  void initState() {
    super.initState();
    _status = widget.initial;
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshVersion++;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<AndroidReminderStatus?> _refresh() async {
    final version = ++_refreshVersion;
    final status = await widget.settings.status();
    if (mounted && version == _refreshVersion) {
      setState(() {
        _status = status;
        _reading = false;
      });
    }
    return status;
  }

  Future<bool> _open(String setting) async {
    final before = _status;
    final opened = await widget.settings.open(setting);
    if (!mounted) return false;
    if (!opened) {
      showAppNotice(
        context,
        context.read<Store>().t['reminderSettingsOpenFailed']!,
      );
      return false;
    }
    final status = await _refresh();
    if (mounted &&
        (before?.notifications != true || before?.exactAlarms != true) &&
        status?.notifications == true &&
        status?.exactAlarms == true) {
      unawaited(context.read<Store>().reconcileReminders());
    }
    return true;
  }

  Future<void> _single(String setting) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _open(setting);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _enable() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      for (final step in ['notifications', 'exactAlarms', 'background']) {
        final status = await _refresh();
        if (!mounted || status == null) return;
        final enabled = switch (step) {
          'notifications' => status.notifications,
          'exactAlarms' => status.exactAlarms,
          _ => status.background,
        };
        if (enabled) continue;
        if (!await _open(step) || !mounted) return;
        final after = await _refresh();
        if (!mounted) return;
        final granted = switch (step) {
          'notifications' => after?.notifications == true,
          'exactAlarms' => after?.exactAlarms == true,
          _ => after?.background == true,
        };
        if (!granted) {
          return; // Declining a permission does not open more prompts.
        }
      }
      if (mounted &&
          _status?.autoStartAvailable == true &&
          _status?.autoStart != true) {
        if (!await _open('autoStart') || !mounted) return;
      }
      if (mounted && widget.firstVisit) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.watch<Store>().t;
    Widget row(String setting, String title, String hint, bool? granted) =>
        ListTile(
          key: ValueKey('reminder-setting-$setting'),
          contentPadding: EdgeInsets.zero,
          title: Text(title),
          subtitle: Text(hint),
          trailing: granted == true
              ? const Icon(Icons.check_circle_outline)
              : const Icon(Icons.chevron_right),
          onTap: _busy
              ? null
              : () => _single(
                  setting == 'notifications' ? 'notificationSettings' : setting,
                ),
        );
    return Scaffold(
      appBar: AppBar(title: Text(t['reminderGuide']!)),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(t['reminderSetupIntro']!),
              if (!_reading && _status == null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(t['reminderSettingsReadFailed']!),
                ),
              const SizedBox(height: 16),
              row(
                'notifications',
                t['reminderNotifications']!,
                t['reminderNotificationsHint']!,
                _status?.notifications,
              ),
              row(
                'exactAlarms',
                t['reminderExactAlarms']!,
                t['reminderExactAlarmsHint']!,
                _status?.exactAlarms,
              ),
              row(
                'background',
                t['reminderBackground']!,
                t['reminderBackgroundHint']!,
                _status?.background,
              ),
              if (_status?.autoStartAvailable == true)
                row(
                  'autoStart',
                  t['reminderAutoStart']!,
                  t['reminderAutoStartHint']!,
                  _status?.autoStart,
                ),
              ExpansionTile(
                title: Text(t['reminderSettingsHelp']!),
                tilePadding: EdgeInsets.zero,
                children: [
                  for (final brand in ['Xiaomi', 'Huawei', 'OppoVivo', 'Other'])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t['guide${brand}Title']!,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 6),
                          Text(t['guide${brand}Steps']!),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              if (widget.firstVisit)
                TextButton(
                  key: const ValueKey('reminder-setup-skip'),
                  onPressed: () => Navigator.pop(context),
                  child: Text(t['reminderSetupSkip']!),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  key: const ValueKey('reminder-setup-enable'),
                  onPressed: _busy || _reading
                      ? null
                      : _status == null
                      ? _refresh
                      : _enable,
                  child: Text(
                    _busy
                        ? t['reminderSetupOpening']!
                        : _status == null && !_reading
                        ? t['retry']!
                        : t['reminderSetupEnable']!,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
