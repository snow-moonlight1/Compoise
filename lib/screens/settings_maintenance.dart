import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_version.dart';
import '../diagnostics/app_log.dart';
import '../diagnostics/diagnostics_report.dart';
import '../services/device_prefs.dart';
import '../services/update_check.dart';
import '../storage.dart';
import '../widgets/app_notice.dart';

/// Writes the diagnostics file after the save dialog. On Android and iOS the
/// picker has already written the bytes it was given.
typedef DiagnosticsFileWriter = Future<void> Function(String path, List<int>);

Future<void> _writeDiagnosticsFile(String path, List<int> bytes) async {
  if (Platform.isAndroid || Platform.isIOS) return;
  await File(path).writeAsBytes(bytes, flush: true);
}

/// Shows the newer version and its release page. The app has no browser
/// launcher, so the link is offered for copying.
Future<void> showUpdateAvailableDialog(
  BuildContext context,
  Map<String, String> t,
  UpdateCheckResult result,
) {
  final url = result.url ?? latestReleasePage;
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(t['updateAvailableTitle']!),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t['updateAvailableBody']!
                .replaceAll('{latest}', result.latest ?? '')
                .replaceAll('{current}', appVersion),
          ),
          const SizedBox(height: 12),
          SelectableText(
            url,
            style: Theme.of(dialogContext).textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(t['close']!),
        ),
        FilledButton(
          key: const ValueKey('update-copy-link'),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: url));
            if (dialogContext.mounted) Navigator.of(dialogContext).pop();
            if (context.mounted) showAppNotice(context, t['linkCopied']!);
          },
          child: Text(t['copyLink']!),
        ),
      ],
    ),
  );
}

/// Help & About rows for keeping the app healthy: the opt-in update check, a
/// manual check, the diagnostics export and the version.
class SettingsMaintenanceTiles extends StatefulWidget {
  const SettingsMaintenanceTiles({
    super.key,
    required this.t,
    required this.store,
    this.prefs,
    this.checker,
    this.writeFile,
  });

  final Map<String, String> t;
  final Store store;
  final DevicePrefs? prefs;
  final UpdateChecker? checker;
  final DiagnosticsFileWriter? writeFile;

  @override
  State<SettingsMaintenanceTiles> createState() =>
      _SettingsMaintenanceTilesState();
}

class _SettingsMaintenanceTilesState extends State<SettingsMaintenanceTiles> {
  bool _checking = false;
  bool _exporting = false;

  DevicePrefs get _prefs => widget.prefs ?? DevicePrefs.instance;

  Future<void> _checkNow() async {
    if (_checking) return;
    setState(() => _checking = true);
    final checker = widget.checker ?? UpdateChecker(prefs: _prefs);
    final result = await checker.check();
    await _prefs.setLastUpdateCheck(DateTime.now());
    if (!mounted) return;
    setState(() => _checking = false);
    final t = widget.t;
    switch (result.status) {
      case UpdateCheckStatus.available:
        await showUpdateAvailableDialog(context, t, result);
      case UpdateCheckStatus.upToDate:
        showAppNotice(context, t['updateUpToDate']!);
      case UpdateCheckStatus.failed:
        showAppNotice(context, t['updateCheckFailed']!);
    }
  }

  Future<void> _exportDiagnostics() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    final t = widget.t;
    try {
      final now = DateTime.now();
      final text = buildDiagnosticsReport(
        facts: diagnosticsFacts(widget.store, prefs: _prefs),
        log: await AppLog.instance.readRecent(),
        now: now,
      );
      final bytes = utf8.encode(text);
      final path = await FilePicker.platform.saveFile(
        fileName: diagnosticsFileName(now),
        type: FileType.custom,
        allowedExtensions: ['txt'],
        bytes: bytes,
      );
      if (path == null) return;
      await (widget.writeFile ?? _writeDiagnosticsFile)(path, bytes);
      if (mounted) showAppNotice(context, t['diagnosticsSaved']!);
    } catch (e, stack) {
      AppLog.instance.error('diagnostics', e, stack);
      if (mounted) showAppNotice(context, t['diagnosticsFailed']!);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final theme = Theme.of(context);
    final subtle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
    );
    Widget progress() => const SizedBox(
      width: 20,
      height: 20,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          key: const ValueKey('update-check-toggle'),
          contentPadding: EdgeInsets.zero,
          dense: true,
          secondary: Icon(
            Icons.system_update_outlined,
            color: theme.colorScheme.primary,
          ),
          title: Text(t['updateCheckTitle']!),
          subtitle: Text(t['updateCheckDesc']!, style: subtle),
          value: _prefs.updateCheckEnabled,
          onChanged: (value) {
            setState(() {});
            _prefs.setUpdateCheckEnabled(value).then((_) {
              if (mounted) setState(() {});
            });
          },
        ),
        ListTile(
          key: const ValueKey('update-check-now'),
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.update, color: theme.colorScheme.primary),
          title: Text(t['checkUpdateNow']!),
          subtitle: Text(
            t['appVersionLabel']!.replaceAll('{version}', appVersion),
            style: subtle,
          ),
          trailing: _checking ? progress() : const Icon(Icons.chevron_right),
          onTap: _checking ? null : _checkNow,
        ),
        ListTile(
          key: const ValueKey('export-diagnostics'),
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            Icons.bug_report_outlined,
            color: theme.colorScheme.primary,
          ),
          title: Text(t['exportDiagnostics']!),
          subtitle: Text(t['exportDiagnosticsDesc']!, style: subtle),
          trailing: _exporting ? progress() : const Icon(Icons.chevron_right),
          onTap: _exporting ? null : _exportDiagnostics,
        ),
      ],
    );
  }
}
