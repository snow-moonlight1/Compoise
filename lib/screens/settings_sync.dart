/// Settings → Sync: choosing a location, joining, status, devices, the sync
/// password and disconnecting.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../storage.dart';
import '../sync/sync_controller.dart';
import '../sync/sync_engine.dart';
import '../sync/sync_provider.dart';
import '../sync/sync_remote.dart';
import '../sync/webdav_remote.dart';
import '../ui/danger_button_style.dart';
import '../widgets/app_notice.dart';

String _fill(String template, Map<String, Object> values) {
  var text = template;
  values.forEach((key, value) => text = text.replaceAll('{$key}', '$value'));
  return text;
}

/// "just now", "5 min ago", or a date and time.
String syncRelativeTime(
  BuildContext context,
  Map<String, String> t,
  int epochMs, {
  DateTime? now,
}) {
  final at = DateTime.fromMillisecondsSinceEpoch(epochMs);
  final elapsed = (now ?? DateTime.now()).difference(at);
  if (elapsed < const Duration(minutes: 1)) return t['syncJustNow']!;
  if (elapsed < const Duration(hours: 1)) {
    return _fill(t['syncMinutesAgo']!, {'count': elapsed.inMinutes});
  }
  if (elapsed < const Duration(hours: 24)) {
    return _fill(t['syncHoursAgo']!, {'count': elapsed.inHours});
  }
  final material = MaterialLocalizations.of(context);
  return '${material.formatShortDate(at)} '
      '${material.formatTimeOfDay(TimeOfDay.fromDateTime(at))}';
}

String? _issueText(SyncIssue? issue, Map<String, String> t) => switch (issue) {
  null => null,
  SyncIssue.vaultMissing => t['syncIssueVaultMissing'],
  SyncIssue.vaultReplaced => t['syncIssueVaultReplaced'],
  SyncIssue.passwordChanged => t['syncIssuePasswordChanged'],
  SyncIssue.encryptionRemoved => t['syncIssueEncryptionRemoved'],
  SyncIssue.vaultUnreadable => t['syncErrorUnreadable'],
  SyncIssue.newerFormat => t['syncErrorNewerFormat'],
  SyncIssue.pendingRestore => t['syncIssuePendingRestore'],
  SyncIssue.busy => t['syncIssueBusy'],
  SyncIssue.localWrite => t['syncIssueLocalWrite'],
  SyncIssue.network => t['syncErrorNetwork'],
  SyncIssue.auth => t['syncIssueAuth'],
  SyncIssue.forbidden => t['syncErrorForbidden'],
  SyncIssue.quota => t['syncErrorQuota'],
  SyncIssue.rateLimited => t['syncErrorRateLimited'],
  SyncIssue.server => t['syncErrorServer'],
  SyncIssue.protocol => t['syncErrorProtocol'],
};

String? _problemText(SyncConnectionProblem? problem, Map<String, String> t) =>
    switch (problem) {
      null => null,
      SyncConnectionProblem.missingSettings => t['syncProblemSettings'],
      SyncConnectionProblem.missingSecret => t['syncProblemSignIn'],
      SyncConnectionProblem.secureStorage => t['syncErrorSecureStorage'],
      SyncConnectionProblem.unsupportedProvider => t['syncProblemUnsupported'],
    };

/// The status line under the settings row and on the sync page.
String syncStatusText(
  BuildContext context,
  SyncController sync,
  Map<String, String> t,
) {
  if (!sync.joined) return t['syncOff']!;
  final problem = _problemText(sync.problem, t);
  if (problem != null) return problem;
  final status = sync.status;
  switch (status.phase) {
    case SyncPhase.off:
      return t['syncOff']!;
    case SyncPhase.syncing:
      return t['syncStatusSyncing']!;
    case SyncPhase.needsPassword:
      return t['syncStatusNeedsPassword']!;
    case SyncPhase.needsAttention:
      return _issueText(status.issue, t) ?? t['syncErrorGeneric']!;
    case SyncPhase.error:
      final issue = _issueText(status.issue, t) ?? t['syncErrorGeneric']!;
      return '$issue · ${t['syncStatusRetry']}';
    case SyncPhase.idle:
      final issue = _issueText(status.issue, t);
      if (issue != null) return issue;
      final last = status.lastSuccessAt;
      if (last == null) return t['syncStatusWaiting']!;
      return _fill(t['syncStatusDone']!, {
        'time': syncRelativeTime(context, t, last),
      });
  }
}

/// Plain-language text for a failed setup or sync action.
String syncErrorText(Object error, Map<String, String> t) {
  if (error is SyncSecureStorageException) return t['syncErrorSecureStorage']!;
  if (error is SyncRemoteException) {
    return switch (error.kind) {
      SyncRemoteFailure.network => t['syncErrorNetwork']!,
      SyncRemoteFailure.auth => t['syncErrorAuth']!,
      SyncRemoteFailure.forbidden => t['syncErrorForbidden']!,
      SyncRemoteFailure.notFound => t['syncErrorNotFound']!,
      SyncRemoteFailure.quota => t['syncErrorQuota']!,
      SyncRemoteFailure.rateLimited => t['syncErrorRateLimited']!,
      SyncRemoteFailure.server => t['syncErrorServer']!,
      SyncRemoteFailure.conflict ||
      SyncRemoteFailure.protocol => t['syncErrorProtocol']!,
    };
  }
  if (error is SyncSetupException) {
    return switch (error.kind) {
      SyncSetupError.wrongPassword => t['syncErrorWrongPassword']!,
      SyncSetupError.passwordRequired => t['syncErrorPasswordRequired']!,
      SyncSetupError.vaultUnreadable => t['syncErrorUnreadable']!,
      SyncSetupError.newerFormat => t['syncErrorNewerFormat']!,
      SyncSetupError.vaultMissing => t['syncIssueVaultMissing']!,
      SyncSetupError.syncFailed => t['syncPasswordChangeFailed']!,
      SyncSetupError.vaultExists ||
      SyncSetupError.alreadyJoined ||
      SyncSetupError.notJoined => t['syncErrorGeneric']!,
    };
  }
  return t['syncErrorGeneric']!;
}

/// Checks a new sync password; null when it is acceptable.
String? syncPasswordProblem(
  String password,
  String confirm,
  Map<String, String> t,
) {
  if (password.length < 8) return t['syncPasswordTooShort'];
  if (password != confirm) return t['syncPasswordMismatch'];
  return null;
}

class SyncSettingsScreen extends StatelessWidget {
  const SyncSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.watch<Store>().t;
    // Provided as nullable: builds without sync (tests, recovery) have none.
    final sync = context.watch<SyncController?>()!;
    return Scaffold(
      appBar: AppBar(title: Text(t['syncTitle']!)),
      body: SafeArea(
        top: false,
        child: sync.joined
            ? _SyncDashboard(sync: sync, t: t)
            : _SyncIntro(t: t),
      ),
    );
  }
}

class _SyncIntro extends StatelessWidget {
  const _SyncIntro({required this.t});

  final Map<String, String> t;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      key: const ValueKey('sync-intro'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Text(t['syncIntro']!, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 20),
        Text(t['syncChooseLocation']!, style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        ListTile(
          key: const ValueKey('sync-choose-webdav'),
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.dns_outlined),
          title: const Text('WebDAV'),
          subtitle: Text(t['syncWebdavDesc']!),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const WebDavSetupScreen()),
          ),
        ),
        const SizedBox(height: 16),
        Text(t['syncWhatSyncs']!, style: theme.textTheme.bodySmall),
        const SizedBox(height: 8),
        Text(t['syncConflictNote']!, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

/// Address, account and the first round for a WebDAV folder.
class WebDavSetupScreen extends StatefulWidget {
  const WebDavSetupScreen({super.key});

  @override
  State<WebDavSetupScreen> createState() => _WebDavSetupScreenState();
}

class _WebDavSetupScreenState extends State<WebDavSetupScreen> {
  final _url = TextEditingController();
  final _user = TextEditingController();
  final _secret = TextEditingController();
  final _device = TextEditingController(text: defaultSyncDeviceName());
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  RemoteVaultInfo? _info;
  SyncProviderConfig? _probed;
  String? _error;
  bool _busy = false;
  bool _usePassword = false;

  @override
  void dispose() {
    for (final controller in [
      _url,
      _user,
      _secret,
      _device,
      _password,
      _confirm,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _edited(String _) {
    if (_info == null && _error == null) return;
    setState(() {
      _info = null;
      _probed = null;
      _error = null;
    });
  }

  SyncProviderConfig? _config(Map<String, String> t) {
    final url = normalizeWebDavUrl(_url.text);
    if (url == null) {
      setState(() => _error = t['syncWebdavUrlInvalid']);
      return null;
    }
    final name = _device.text.trim();
    return SyncProviderConfig(
      kind: SyncProviderKind.webdav,
      deviceName: name.isEmpty ? defaultSyncDeviceName() : name,
      webdav: WebDavSettings(url: url.toString(), username: _user.text.trim()),
    );
  }

  Future<void> _probe(SyncController sync, Map<String, String> t) async {
    final config = _config(t);
    if (config == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final info = await sync.probe(config, _secret.text);
      if (!mounted) return;
      setState(() {
        _info = info;
        _probed = config;
      });
    } catch (error) {
      if (mounted) setState(() => _error = syncErrorText(error, t));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _start(SyncController sync, Map<String, String> t) async {
    final info = _info!;
    String? password;
    if (info.vault == null) {
      if (_usePassword) {
        final problem = syncPasswordProblem(_password.text, _confirm.text, t);
        if (problem != null) {
          setState(() => _error = problem);
          return;
        }
        password = _password.text;
      }
    } else if (info.vault!.encrypted) {
      if (_password.text.isEmpty) {
        setState(() => _error = t['syncErrorPasswordRequired']);
        return;
      }
      password = _password.text;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await sync.connect(_probed!, _secret.text, password: password);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) setState(() => _error = syncErrorText(error, t));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.watch<Store>().t;
    final sync = context.read<SyncController?>()!;
    final theme = Theme.of(context);
    final url = normalizeWebDavUrl(_url.text);
    final insecure = url != null && isInsecureWebDavUrl(url);
    final info = _info;
    return Scaffold(
      appBar: AppBar(title: const Text('WebDAV')),
      body: SafeArea(
        top: false,
        child: AutofillGroup(
          child: ListView(
            key: const ValueKey('sync-webdav-setup'),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              TextField(
                key: const ValueKey('sync-webdav-url'),
                controller: _url,
                enabled: !_busy,
                keyboardType: TextInputType.url,
                autocorrect: false,
                autofillHints: const [AutofillHints.url],
                decoration: InputDecoration(
                  labelText: t['syncWebdavUrl'],
                  hintText: 'https://dav.jianguoyun.com/dav/',
                ),
                onChanged: (value) {
                  _edited(value);
                  setState(() {});
                },
              ),
              if (insecure) ...[
                const SizedBox(height: 6),
                Text(
                  t['syncWebdavInsecure']!,
                  key: const ValueKey('sync-webdav-insecure'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('sync-webdav-user'),
                controller: _user,
                enabled: !_busy,
                autocorrect: false,
                autofillHints: const [AutofillHints.username],
                decoration: InputDecoration(labelText: t['syncWebdavUser']),
                onChanged: _edited,
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('sync-webdav-password'),
                controller: _secret,
                enabled: !_busy,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                autofillHints: const [AutofillHints.password],
                decoration: InputDecoration(
                  labelText: t['syncWebdavPassword'],
                  helperText: t['syncWebdavPasswordHint'],
                  helperMaxLines: 3,
                ),
                onChanged: _edited,
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('sync-device-name'),
                controller: _device,
                enabled: !_busy,
                maxLength: 64,
                decoration: InputDecoration(
                  labelText: t['syncDeviceName'],
                  helperText: t['syncDeviceNameHint'],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                t['syncWebdavFolderNote']!,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              if (info == null)
                FilledButton(
                  key: const ValueKey('sync-webdav-connect'),
                  onPressed: _busy ? null : () => _probe(sync, t),
                  child: Text(_busy ? t['syncWorking']! : t['syncConnect']!),
                )
              else
                ..._joinStep(info, sync, t, theme),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  key: const ValueKey('sync-setup-error'),
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _joinStep(
    RemoteVaultInfo info,
    SyncController sync,
    Map<String, String> t,
    ThemeData theme,
  ) {
    final vault = info.vault;
    final passwordFields = [
      TextField(
        key: const ValueKey('sync-password'),
        controller: _password,
        enabled: !_busy,
        obscureText: true,
        autocorrect: false,
        enableSuggestions: false,
        decoration: InputDecoration(labelText: t['syncPassword']),
      ),
    ];
    return [
      const Divider(height: 24),
      if (vault == null) ...[
        Text(t['syncNewVault']!, key: const ValueKey('sync-new-vault')),
        SwitchListTile(
          key: const ValueKey('sync-use-password'),
          contentPadding: EdgeInsets.zero,
          value: _usePassword,
          title: Text(t['syncUsePassword']!),
          subtitle: Text(t['syncPasswordDesc']!),
          onChanged: _busy
              ? null
              : (value) => setState(() {
                  _usePassword = value;
                  _error = null;
                }),
        ),
        if (_usePassword) ...[
          ...passwordFields,
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('sync-password-confirm'),
            controller: _confirm,
            enabled: !_busy,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(labelText: t['syncPasswordConfirm']),
          ),
        ],
      ] else ...[
        Text(
          _fill(t['syncFoundVault']!, {'count': info.deviceFiles}),
          key: const ValueKey('sync-found-vault'),
        ),
        if (vault.encrypted) ...[
          const SizedBox(height: 8),
          Text(t['syncFoundEncrypted']!),
          const SizedBox(height: 8),
          ...passwordFields,
        ],
        const SizedBox(height: 8),
        Text(t['syncJoinMerge']!, style: theme.textTheme.bodySmall),
      ],
      const SizedBox(height: 16),
      FilledButton(
        key: const ValueKey('sync-start'),
        onPressed: _busy ? null : () => _start(sync, t),
        child: Text(_busy ? t['syncWorking']! : t['syncStart']!),
      ),
    ];
  }
}

class _SyncDashboard extends StatefulWidget {
  const _SyncDashboard({required this.sync, required this.t});

  final SyncController sync;
  final Map<String, String> t;

  @override
  State<_SyncDashboard> createState() => _SyncDashboardState();
}

class _SyncDashboardState extends State<_SyncDashboard> {
  final _input = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Map<String, String> get t => widget.t;
  SyncController get sync => widget.sync;

  Future<void> _run(Future<Object?> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      _input.clear();
    } catch (error) {
      if (mounted) showAppNotice(context, syncErrorText(error, t));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// What the user has to do, if anything.
  Widget? _action() {
    final status = sync.status;
    final problem = sync.problem;
    Widget field(String label, String button, Future<Object?> Function() go) =>
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const ValueKey('sync-action-input'),
              controller: _input,
              enabled: !_busy,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(labelText: label),
              onSubmitted: (_) => _run(go),
            ),
            const SizedBox(height: 8),
            FilledButton(
              key: const ValueKey('sync-action-submit'),
              onPressed: _busy ? null : () => _run(go),
              child: Text(button),
            ),
          ],
        );
    if (problem == SyncConnectionProblem.missingSecret ||
        problem == SyncConnectionProblem.secureStorage ||
        status.issue == SyncIssue.auth) {
      return field(
        t['syncWebdavPassword']!,
        t['syncUpdatePassword']!,
        () => sync.updateSecret(_input.text),
      );
    }
    if (problem != null) return Text(t['syncReconnectHint']!);
    if (status.phase == SyncPhase.needsPassword ||
        status.issue == SyncIssue.passwordChanged) {
      return field(
        t['syncPassword']!,
        t['syncUnlock']!,
        () => sync.unlock(_input.text),
      );
    }
    if (status.issue == SyncIssue.encryptionRemoved) {
      return OutlinedButton(
        key: const ValueKey('sync-continue-plain'),
        onPressed: _busy ? null : () => _run(sync.acceptPlainVault),
        child: Text(t['syncContinuePlain']!),
      );
    }
    if (status.phase == SyncPhase.needsAttention &&
        status.issue != SyncIssue.forbidden) {
      return Text(t['syncReconnectHint']!);
    }
    return null;
  }

  Future<void> _changePassword({required bool remove}) async {
    if (remove) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: Text(t['syncRemovePassword']!),
          content: Text(t['syncRemovePasswordConfirm']!),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: Text(t['cancel']!),
            ),
            FilledButton(
              style: dangerButtonStyle(dialog),
              onPressed: () => Navigator.pop(dialog, true),
              child: Text(t['syncRemovePassword']!),
            ),
          ],
        ),
      );
      if (ok == true) await _run(() => sync.changePassword(null));
      return;
    }
    final password = await showDialog<String>(
      context: context,
      builder: (_) => _PasswordDialog(t: t, encrypted: sync.engine.encrypted),
    );
    if (password != null) await _run(() => sync.changePassword(password));
  }

  Future<void> _rename() async {
    final controller = TextEditingController(text: sync.config?.deviceName);
    final name = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(t['syncRenameDevice']!),
        content: TextField(
          key: const ValueKey('sync-rename-input'),
          controller: controller,
          autofocus: true,
          maxLength: 64,
          decoration: InputDecoration(labelText: t['syncDeviceName']),
          onSubmitted: (value) => Navigator.pop(dialog, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: Text(t['cancel']!),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, controller.text),
            child: Text(t['save']!),
          ),
        ],
      ),
    );
    controller.dispose();
    final trimmed = name?.trim() ?? '';
    if (trimmed.isNotEmpty) await _run(() => sync.renameDevice(trimmed));
  }

  Future<void> _removeDevice(SyncDeviceView device) async {
    final name = device.info?.name ?? device.id;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        content: Text(_fill(t['syncRemoveDeviceConfirm']!, {'name': name})),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: Text(t['cancel']!),
          ),
          FilledButton(
            style: dangerButtonStyle(dialog),
            onPressed: () => Navigator.pop(dialog, true),
            child: Text(t['syncRemoveDevice']!),
          ),
        ],
      ),
    );
    if (ok == true) await _run(() => sync.removeDevice(device.id));
  }

  Future<void> _disconnect() async {
    var deleteFile = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, setDialog) => AlertDialog(
          title: Text(t['syncDisconnect']!),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t['syncDisconnectConfirm']!),
              const SizedBox(height: 8),
              CheckboxListTile(
                key: const ValueKey('sync-disconnect-delete'),
                contentPadding: EdgeInsets.zero,
                value: deleteFile,
                title: Text(t['syncDisconnectDeleteFile']!),
                onChanged: (value) =>
                    setDialog(() => deleteFile = value ?? false),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: Text(t['cancel']!),
            ),
            FilledButton(
              key: const ValueKey('sync-disconnect-confirm'),
              style: dangerButtonStyle(dialog),
              onPressed: () => Navigator.pop(dialog, true),
              child: Text(t['syncDisconnect']!),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      await _run(() => sync.disconnect(deleteOwnFile: deleteFile));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final config = sync.config;
    final status = sync.status;
    final action = _action();
    final location = config?.webdav == null
        ? null
        : '${config!.webdav!.username} · ${config.webdav!.url}';
    final syncing = status.phase == SyncPhase.syncing;
    final encrypted = sync.engine.encrypted;
    return ListView(
      key: const ValueKey('sync-dashboard'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(switch (status.phase) {
            SyncPhase.syncing => Icons.sync,
            SyncPhase.idle when status.issue == null => Icons.cloud_done,
            _ => Icons.sync_problem,
          }, color: theme.colorScheme.primary),
          title: Text(switch (config?.kind) {
            SyncProviderKind.webdav || null => 'WebDAV',
            SyncProviderKind.onedrive => 'OneDrive',
            SyncProviderKind.huawei => 'Huawei Cloud',
          }),
          subtitle: location == null
              ? null
              : Text(location, maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
        Text(
          syncStatusText(context, sync, t),
          key: const ValueKey('sync-status-text'),
          style: theme.textTheme.bodyMedium,
        ),
        if (status.unreadablePeers > 0) ...[
          const SizedBox(height: 4),
          Text(
            _fill(t['syncUnreadablePeers']!, {'count': status.unreadablePeers}),
            style: theme.textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 12),
        if (action != null) ...[action, const SizedBox(height: 12)],
        OutlinedButton.icon(
          key: const ValueKey('sync-now'),
          icon: const Icon(Icons.sync, size: 18),
          label: Text(t['syncNow']!),
          onPressed: _busy || syncing || sync.problem != null
              ? null
              : () => _run(sync.syncNow),
        ),
        const SizedBox(height: 24),
        Text(t['syncDevices']!, style: theme.textTheme.titleSmall),
        for (final device in sync.devices) _deviceTile(context, device),
        const SizedBox(height: 24),
        Text(t['syncEncryption']!, style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          encrypted ? t['syncEncryptedOn']! : t['syncEncryptedOff']!,
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton(
              key: const ValueKey('sync-set-password'),
              onPressed: _busy || sync.problem != null
                  ? null
                  : () => _changePassword(remove: false),
              child: Text(
                encrypted ? t['syncChangePassword']! : t['syncSetPassword']!,
              ),
            ),
            if (encrypted)
              OutlinedButton(
                key: const ValueKey('sync-remove-password'),
                onPressed: _busy || sync.problem != null
                    ? null
                    : () => _changePassword(remove: true),
                child: Text(t['syncRemovePassword']!),
              ),
          ],
        ),
        const SizedBox(height: 24),
        Text(t['syncWhatSyncs']!, style: theme.textTheme.bodySmall),
        const SizedBox(height: 8),
        Text(t['syncConflictNote']!, style: theme.textTheme.bodySmall),
        const SizedBox(height: 24),
        OutlinedButton(
          key: const ValueKey('sync-disconnect'),
          style: OutlinedButton.styleFrom(
            foregroundColor: theme.colorScheme.error,
          ),
          onPressed: _busy ? null : _disconnect,
          child: Text(t['syncDisconnect']!),
        ),
      ],
    );
  }

  Widget _deviceTile(BuildContext context, SyncDeviceView device) {
    final info = device.info;
    final name = device.isThisDevice
        ? (sync.config?.deviceName ?? info?.name ?? device.id)
        : (info?.name.isNotEmpty == true ? info!.name : device.id);
    final details = <String>[
      if (device.isThisDevice) t['syncThisDevice']!,
      if (info != null && info.platform.isNotEmpty)
        syncPlatformLabel(info.platform),
      if (device.unreadable)
        t['syncDeviceUnreadable']!
      else if (device.writtenAt != null)
        syncRelativeTime(context, t, device.writtenAt!),
    ];
    return ListTile(
      key: ValueKey('sync-device-${device.id}'),
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        device.isThisDevice ? Icons.smartphone : Icons.devices_other,
      ),
      title: Text(name),
      subtitle: Text(details.join(' · ')),
      trailing: device.isThisDevice
          ? IconButton(
              tooltip: t['syncRenameDevice'],
              icon: const Icon(Icons.edit_outlined),
              onPressed: _busy ? null : _rename,
            )
          : IconButton(
              tooltip: t['syncRemoveDevice'],
              icon: const Icon(Icons.delete_outline),
              onPressed: _busy ? null : () => _removeDevice(device),
            ),
    );
  }
}

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({required this.t, required this.encrypted});

  final Map<String, String> t;
  final bool encrypted;

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _submit() {
    final problem = syncPasswordProblem(
      _password.text,
      _confirm.text,
      widget.t,
    );
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    Navigator.pop(context, _password.text);
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    return AlertDialog(
      title: Text(
        widget.encrypted ? t['syncChangePassword']! : t['syncSetPassword']!,
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t['syncPasswordDesc']!),
            const SizedBox(height: 8),
            Text(t['syncChangePasswordNote']!),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('sync-new-password'),
              controller: _password,
              obscureText: true,
              autofocus: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(labelText: t['syncPassword']),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('sync-new-password-confirm'),
              controller: _confirm,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: t['syncPasswordConfirm'],
                errorText: _error,
              ),
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t['cancel']!),
        ),
        FilledButton(
          key: const ValueKey('sync-new-password-save'),
          onPressed: _submit,
          child: Text(t['save']!),
        ),
      ],
    );
  }
}
