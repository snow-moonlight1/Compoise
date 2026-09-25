import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/desktop_shell_service.dart';
import '../storage.dart';
import 'settings_desktop.dart';

/// How a backup file operation ended. The screen only reports the outcome; it
/// never has to know which step stopped.
enum BackupOutcome { cancelled, succeeded, failed }

@immutable
class BackupResult {
  const BackupResult(this.outcome, [this.message]);

  final BackupOutcome outcome;

  /// Text meant for the user, already localized.
  final String? message;
}

/// Coordinates the settings screen's backup files: an export with its explicit
/// credential choice, and an import that picks, decodes within the size limit,
/// asks for a mode, previews the plan and only then applies it. One operation
/// runs at a time, and a screen that is already gone stops being told about it.
class SettingsBackupFlow {
  SettingsBackupFlow({required this.onBusyChanged});

  final ValueChanged<bool> onBusyChanged;

  bool _busy = false;
  bool _closed = false;

  bool get busy => _busy;

  /// Called from the host's dispose: nothing that is still on its way reports
  /// back, and no further operation starts.
  void close() => _closed = true;

  Future<BackupResult> export(BuildContext context, Store store) async {
    if (!_start()) return const BackupResult(BackupOutcome.cancelled);
    final t = store.t;
    try {
      final includeCredential = await showDialog<bool>(
        context: context,
        builder:
            (dialogContext) => AlertDialog(
              title: Text(t['exportCredentialTitle']!),
              content: Text(t['exportCredentialWarning']!),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(t['cancel']!),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: Text(t['exportWithoutCredential']!),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: Text(t['exportWithCredential']!),
                ),
              ],
            ),
      );
      if (includeCredential == null || _closed || !context.mounted) {
        return const BackupResult(BackupOutcome.cancelled);
      }
      final json =
          includeCredential
              ? await store.exportJsonWithCredential()
              : store.exportJson();
      if (_closed || !context.mounted) {
        return const BackupResult(BackupOutcome.cancelled);
      }
      final bytes = Uint8List.fromList(utf8.encode(json));
      final path = await FilePicker.platform.saveFile(
        fileName:
            'matrixflow_backup_${DateTime.now().toIso8601String().split('T').first}.json',
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: bytes,
      );
      if (path == null) return const BackupResult(BackupOutcome.cancelled);
      // Android's Storage Access Framework writes the bytes itself. Its return
      // value may be a content URI, not a Dart File path.
      if (!Platform.isAndroid && !Platform.isIOS) {
        await File(path).writeAsBytes(bytes, flush: true);
      }
      return BackupResult(BackupOutcome.succeeded, t['exportSuccess']!);
    } catch (_) {
      return BackupResult(BackupOutcome.failed, t['exportError']!);
    } finally {
      _finish();
    }
  }

  Future<BackupResult> importBackup(
    BuildContext context,
    Store store, {
    required VoidCallback syncAiFields,
  }) async {
    if (!_start()) return const BackupResult(BackupOutcome.cancelled);
    final t = store.t;
    var applying = false;
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: false,
      );
      if (_closed || !context.mounted || picked == null) {
        return const BackupResult(BackupOutcome.cancelled);
      }
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

      if (_closed || !context.mounted) {
        return const BackupResult(BackupOutcome.cancelled);
      }
      final mode = await _askMode(context, t);
      if (mode == null || _closed || !context.mounted) {
        return const BackupResult(BackupOutcome.cancelled);
      }
      final plan = store.previewImport(json, mode);
      final choice = await _confirmPlan(context, t, plan, mode);
      if (choice == null || _closed || !context.mounted) {
        return const BackupResult(BackupOutcome.cancelled);
      }

      applying = true;
      final result = await store.applyImport(
        plan,
        importCredential: choice == 'replace',
      );
      if (!result.success) {
        throw StateError('Import save failed');
      }
      final desktopResult = await applyDesktopSettings(store);
      if (!_closed && context.mounted) syncAiFields();
      final shell = DesktopShellService.instance;
      final desktopWarning =
          shell.isDesktopSupported && desktopResult.hasFailure
          ? '\n${desktopStatusText(store.t, shell)}'
          : '';
      return BackupResult(BackupOutcome.succeeded,
        '${t['importSuccess']} (${plan.addedTasks})$desktopWarning',
      );
    } on FormatException catch (error) {
      return BackupResult(BackupOutcome.failed,
        error.message.startsWith('Conflicting')
            ? t['importConflictBlocked']!
            : t['importError']!,
      );
    } catch (_) {
      return BackupResult(BackupOutcome.failed,
        t[applying ? 'importSaveError' : 'importError']!,
      );
    } finally {
      _finish();
    }
  }

  Future<String?> _askMode(BuildContext context, Map<String, String> t) =>
      showDialog<String>(
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

  Future<String?> _confirmPlan(
    BuildContext context,
    Map<String, String> t,
    ImportPlan plan,
    String mode,
  ) => showDialog<String>(
    context: context,
    builder:
        (dialogContext) => AlertDialog(
          title: Text(t['importPreview']!),
          content: SingleChildScrollView(
            child: Text(
              '${mode == 'overwrite' ? t['confirmImport'] : t['importModeMergeDesc']}\n\n${_summary(t, plan)}\n\n${plan.hasCredential ? t['importCredentialPresent'] : ''}\n\n${_warningDetails(t, plan)}\n\n${plan.conflicts > 0 ? t['importConflictBlocked'] : ''}',
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

  String _summary(Map<String, String> t, ImportPlan plan) =>
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

  String _warningDetails(Map<String, String> t, ImportPlan plan) {
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

    return plan.warnings.take(8).map(warningText).join('\n');
  }

  bool _start() {
    if (_busy || _closed) return false;
    _busy = true;
    onBusyChanged(true);
    return true;
  }

  void _finish() {
    _busy = false;
    if (!_closed) onBusyChanged(false);
  }
}
