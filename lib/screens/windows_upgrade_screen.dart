import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../l10n.dart';
import '../models.dart';
import '../services/windows_data_upgrade.dart';

/// The startup gate never creates a Store or starts reminder persistence until
/// preparation succeeds. Retry uses fresh disk state, before plugin caching.
class WindowsUpgradeStartup extends StatefulWidget {
  final Future<WindowsUpgradeResult> Function() prepare;
  final Future<Widget> Function() openApplication;
  final List<Locale>? deviceLocales;
  final Future<void> Function()? closeBeforeStore;
  final VoidCallback? onCredentialNoticeConfirmed;

  const WindowsUpgradeStartup({
    super.key,
    required this.prepare,
    required this.openApplication,
    this.deviceLocales,
    this.closeBeforeStore,
    this.onCredentialNoticeConfirmed,
  });

  @override
  State<WindowsUpgradeStartup> createState() => _WindowsUpgradeStartupState();
}

class _WindowsUpgradeStartupState extends State<WindowsUpgradeStartup> {
  WindowsUpgradeResult? _result;
  Widget? _application;
  bool _busy = true;
  bool _showManual = false;

  @override
  void initState() {
    super.initState();
    _attempt();
  }

  Future<void> _attempt() async {
    setState(() {
      _busy = true;
      _showManual = false;
    });
    WindowsUpgradeResult result;
    try {
      result = await widget.prepare();
    } catch (_) {
      result = const WindowsUpgradeResult(WindowsUpgradeStatus.failed);
    }
    if (!mounted) return;
    setState(() => _result = result);
    if (result.canOpen &&
        !result.showCredentialNotice &&
        !result.protocolNeedsRecovery) {
      await _open();
    } else {
      setState(() => _busy = false);
    }
  }

  Future<void> _open() async {
    setState(() => _busy = true);
    try {
      final application = await widget.openApplication();
      if (mounted) setState(() => _application = application);
    } catch (_) {
      if (mounted) {
        setState(() {
          _result = const WindowsUpgradeResult(WindowsUpgradeStatus.failed);
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_application != null) return _application!;
    final language = resolveDeviceLanguage(
      widget.deviceLocales ??
          WidgetsBinding.instance.platformDispatcher.locales,
    );
    final t = dictOf(language);
    final result = _result;
    final message = switch (result?.status) {
      WindowsUpgradeStatus.sourceUnreadable => 'upgradeSourceUnreadable',
      WindowsUpgradeStatus.currentUnreadable => 'upgradeCurrentUnreadable',
      _ => 'upgradeFailed',
    };
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: Locale(language.name),
      supportedLocales: const [Locale('en'), Locale('zh'), Locale('ja')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: Scaffold(
        appBar: AppBar(title: Text(t['upgradeTitle']!)),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(24),
              children: [
                if (_busy) ...[
                  const Center(child: CircularProgressIndicator()),
                  const SizedBox(height: 16),
                  Text(t['upgradePreparing']!),
                ] else ...[
                  if (result?.canOpen != true) Text(t[message]!),
                  if (result?.protocolNeedsRecovery == true)
                    Text(t['upgradeRecovery']!),
                  if (result?.showCredentialNotice == true) ...[
                    const SizedBox(height: 16),
                    Text(t['upgradeCredentials']!),
                  ],
                  const SizedBox(height: 16),
                  Text(t['upgradeSourcePreserved']!),
                  if (result?.sourcePath != null)
                    SelectableText(result!.sourcePath!),
                  if (result?.currentPath != null)
                    SelectableText(result!.currentPath!),
                  const SizedBox(height: 24),
                  if (result?.canOpen == true)
                    FilledButton(
                      onPressed: () {
                        if (result?.showCredentialNotice == true) {
                          widget.onCredentialNoticeConfirmed?.call();
                        }
                        _open();
                      },
                      child: Text(t['upgradeContinue']!),
                    )
                  else ...[
                    FilledButton(
                      onPressed: _attempt,
                      child: Text(t['upgradeRetry']!),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: () => setState(() => _showManual = true),
                      child: Text(t['upgradeManual']!),
                    ),
                    if (_showManual) ...[
                      const SizedBox(height: 16),
                      Text(t['upgradeManualInstructions']!),
                    ],
                  ],
                  if (widget.closeBeforeStore != null) ...[
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: widget.closeBeforeStore,
                      child: Text(t['upgradeClose']!),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
