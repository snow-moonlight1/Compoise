import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../app_version.dart';
import '../services/app_update.dart';
import '../services/desktop_shell_service.dart';
import '../services/update_check.dart';
import 'app_notice.dart';

/// Download-and-install dialog for Android and Windows. One button: update
/// (or install, when the package is already here). Progress is shown inline;
/// failures close the dialog with one sentence.
class UpdateDialog extends StatefulWidget {
  const UpdateDialog({
    super.key,
    required this.t,
    required this.result,
    required this.updater,
    required this.noticeContext,
    this.exitAfterInstall,
  });

  final Map<String, String> t;
  final UpdateCheckResult result;
  final AppUpdater updater;

  /// Where failure notices are shown after the dialog closes.
  final BuildContext noticeContext;

  /// Windows: quits the app once the installer runs. Tests replace it.
  final Future<void> Function()? exitAfterInstall;

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

enum _Phase { idle, working, permission }

class _UpdateDialogState extends State<UpdateDialog>
    with WidgetsBindingObserver {
  _Phase _phase = _Phase.idle;
  bool _ready = false;
  double? _progress;
  File? _file;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final version = widget.result.version;
    if (version != null) {
      widget.updater
          .hasReadyPackage(version)
          .then((ready) {
            if (mounted && ready) setState(() => _ready = true);
          })
          .catchError((_) {});
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from the "install unknown apps" setting.
    if (state == AppLifecycleState.resumed && _phase == _Phase.permission) {
      unawaited(_installIfAllowed());
    }
  }

  void _fail(UpdateFailure failure) {
    final t = widget.t;
    final message = switch (failure) {
      UpdateFailure.network => t['updateFailedNetwork']!,
      UpdateFailure.noSpace => t['updateFailedSpace']!,
      UpdateFailure.damaged => t['updateFailedDamaged']!,
      UpdateFailure.install => t['updateFailedInstall']!,
    };
    if (mounted) Navigator.of(context).pop();
    final notice = widget.noticeContext;
    if (notice.mounted) showAppNotice(notice, message);
  }

  Future<void> _start() async {
    setState(() {
      _phase = _Phase.working;
      _progress = _ready ? null : 0;
    });
    try {
      _file = await widget.updater.prepare(
        tag: widget.result.tag!,
        version: widget.result.version!,
        onProgress: (received, total) {
          if (!mounted) return;
          final p = total == null || total <= 0 ? null : received / total;
          if (p != _progress) setState(() => _progress = p);
        },
      );
    } on UpdateException catch (e) {
      if (mounted) _fail(e.failure);
      return;
    } catch (_) {
      if (mounted) _fail(UpdateFailure.network);
      return;
    }
    if (!mounted) return;
    setState(() => _ready = true);
    await _installIfAllowed();
  }

  Future<void> _installIfAllowed() async {
    final file = _file;
    if (file == null || !mounted) return;
    final installer = widget.updater.installer;
    if (!await installer.canInstall()) {
      if (mounted) setState(() => _phase = _Phase.permission);
      return;
    }
    if (!mounted) return;
    final started = await installer.install(file);
    if (!mounted) return;
    if (!started) {
      _fail(UpdateFailure.install);
      return;
    }
    Navigator.of(context).pop();
    if (widget.updater.target == UpdateTarget.windows) {
      await (widget.exitAfterInstall ??
          () async {
            await DesktopShellService.instance.exitApplication();
          })();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final theme = Theme.of(context);
    final body = switch (_phase) {
      _Phase.permission => t['updateAllowInstall']!,
      _ =>
        t['updateAvailableShort']!
            .replaceAll('{latest}', widget.result.latest ?? '')
            .replaceAll('{current}', appVersion),
    };
    final percent = _progress == null ? null : (_progress! * 100).round();
    return AlertDialog(
      title: Text(t['updateAvailableTitle']!),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(body),
          if (_phase == _Phase.working) ...[
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                key: const ValueKey('update-progress'),
                value: _progress,
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              percent == null
                  ? t['updatePreparing']!
                  : t['updateDownloading']!.replaceAll('{percent}', '$percent'),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t['close']!),
        ),
        if (_phase == _Phase.idle)
          FilledButton(
            key: const ValueKey('update-start'),
            onPressed: _start,
            child: Text(_ready ? t['updateInstall']! : t['updateNow']!),
          ),
        if (_phase == _Phase.permission)
          FilledButton(
            key: const ValueKey('update-open-settings'),
            onPressed: widget.updater.installer.openInstallSettings,
            child: Text(t['updateOpenSettings']!),
          ),
      ],
    );
  }
}
