import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../storage.dart';

/// Shown before the main app so no edits can overwrite unresolved source data.
class StartupRecoveryScreen extends StatefulWidget {
  const StartupRecoveryScreen({super.key});

  @override
  State<StartupRecoveryScreen> createState() => _StartupRecoveryScreenState();
}

class _StartupRecoveryScreenState extends State<StartupRecoveryScreen> {
  bool _busy = false;

  Future<void> _saveCopy(Store store) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final bytes = Uint8List.fromList(utf8.encode(store.recoveryCopyJson()));
      final path = await FilePicker.platform.saveFile(
        fileName: 'matrixflow_recovery.json',
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: bytes,
      );
      if (path == null) return;
      if (!Platform.isAndroid && !Platform.isIOS) {
        await File(path).writeAsBytes(bytes, flush: true);
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(store.t['recoverySaved']!)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(store.t['recoverySaveFailed']!)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _discard(Store store) async {
    if (_busy) return;
    final approved = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: Text(store.t['recoveryDiscard']!),
            content: Text(store.t['recoveryConfirm']!),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(store.t['cancel']!),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(store.t['recoveryDiscard']!),
              ),
            ],
          ),
    );
    if (approved != true || !mounted) return;
    setState(() => _busy = true);
    try {
      if (!await store.discardDamagedStartupData() && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(store.t['recoveryDiscardFailed']!)),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(store.t['recoveryDiscardFailed']!)),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<Store>();
    final t = store.t;
    const labels = {
      'matrixflow-tasks': 'recoveryTasks',
      'matrixflow-boards': 'recoveryBoards',
      'matrixflow-config': 'recoveryConfig',
      'matrixflow-settings': 'recoverySettings',
      'matrixflow-active-board': 'recoveryActiveBoard',
      'matrixflow-has-seen-onboarding': 'recoveryOnboarding',
      'matrixflow-save-pointer': 'recoverySaveBatch',
      'matrixflow-save-a': 'recoverySaveBatch',
      'matrixflow-save-b': 'recoverySaveBatch',
    };
    return Scaffold(
      appBar: AppBar(title: Text(t['recoveryTitle']!)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(24),
            children: [
              Text(t['recoveryDescription']!),
              const SizedBox(height: 16),
              Text(
                store.recoveryKeys.map((key) => t[labels[key]!]!).join(' · '),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              Text(t['recoverySecretWarning']!),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _busy ? null : () => _saveCopy(store),
                icon: const Icon(Icons.save_alt),
                label: Text(t['recoverySave']!),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _busy ? null : () => _discard(store),
                child: Text(t['recoveryDiscard']!),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
