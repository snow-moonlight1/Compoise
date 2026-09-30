import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models.dart' show ScheduleExportLossException;
import '../services/desktop_shell_service.dart';
import '../storage.dart';
import 'settings_backup_messages.dart';
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

/// Writes a backup file the platform picker handed a path for. Android and
/// iOS Storage Access Framework already wrote the bytes themselves and return
/// a content URI rather than a Dart file path, so only the desktop shells
/// still have to write.
typedef BackupFileWriter = Future<void> Function(String path, Uint8List bytes);

Future<void> _writeBackupFile(String path, Uint8List bytes) async {
  if (Platform.isAndroid || Platform.isIOS) return;
  await File(path).writeAsBytes(bytes, flush: true);
}

/// Coordinates the settings screen's backup files: an export with its explicit
/// credential choice, and an import that picks, decodes within the size limit,
/// asks for a mode, previews the plan and only then applies it. One operation
/// runs at a time, and a screen that is already gone stops being told about it.
class SettingsBackupFlow {
  SettingsBackupFlow({required this.onBusyChanged, BackupFileWriter? writeFile})
    : _writeFile = writeFile ?? _writeBackupFile;

  final ValueChanged<bool> onBusyChanged;
  final BackupFileWriter _writeFile;

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
        builder: (dialogContext) => AlertDialog(
          title: Text(t['exportCredentialTitle']!),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t['backupVersionInfo']!),
                const SizedBox(height: 12),
                Text(t['exportCredentialWarning']!),
              ],
            ),
          ),
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
      final bundle = await store.exportBackup(
        includeCredential: includeCredential,
      );
      if (_closed || !context.mounted) {
        return const BackupResult(BackupOutcome.cancelled);
      }
      // A library no file format can carry must not report a saved backup:
      // the user learns the limit here, on the device that has the data,
      // instead of on the device they try to restore on.
      if (!bundle.recoverable) {
        return BackupResult(
          BackupOutcome.failed,
          t[switch (bundle.status) {
            BackupStatus.libraryTooLarge => 'exportErrorTooManyRecords',
            BackupStatus.incomplete => 'exportErrorIncomplete',
            _ => 'exportErrorTooLarge',
          }]!,
        );
      }
      final date = DateTime.now().toIso8601String().split('T').first;
      for (final part in bundle.parts) {
        final bytes = utf8.encode(part.json);
        final path = await FilePicker.platform.saveFile(
          fileName: backupFileName(date, part),
          type: FileType.custom,
          allowedExtensions: ['json'],
          bytes: bytes,
        );
        if (path == null) return const BackupResult(BackupOutcome.cancelled);
        await _writeFile(path, bytes);
        if (_closed || !context.mounted) {
          return const BackupResult(BackupOutcome.cancelled);
        }
      }
      if (bundle.parts.length == 1) {
        return BackupResult(BackupOutcome.succeeded, t['exportSuccess']!);
      }
      return BackupResult(
        BackupOutcome.succeeded,
        '${t['exportPartsSuccess']!.replaceAll('{n}', '${bundle.parts.length}')}'
        '\n${t['exportPartsHint']}',
      );
    } on ScheduleExportLossException catch (error) {
      return BackupResult(
        BackupOutcome.failed,
        t['exportScheduleLossBlocked']!.replaceAll(
          '{n}',
          '${error.lostScheduleItems}',
        ),
      );
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
      if (file.size > ImportPreflight.maxFileBytes) {
        throw const BackupRejectedException(
          'importErrorTooLarge',
          'Backup exceeds the supported size limit',
        );
      }
      if (bytes == null && file.path != null) {
        final source = File(file.path!);
        if (await source.length() > ImportPreflight.maxFileBytes) {
          throw const BackupRejectedException(
            'importErrorTooLarge',
            'Backup exceeds the supported size limit',
          );
        }
        final collected = <int>[];
        await for (final chunk in source.openRead(
          0,
          ImportPreflight.maxFileBytes + 1,
        )) {
          collected.addAll(chunk);
          if (collected.length > ImportPreflight.maxFileBytes) {
            throw const BackupRejectedException(
              'importErrorTooLarge',
              'Backup exceeds the supported size limit',
            );
          }
        }
        bytes = Uint8List.fromList(collected);
      }
      if (bytes == null) throw const FormatException('No file data');
      final json = ImportPreflight.decode(bytes);

      if (_closed || !context.mounted) {
        return const BackupResult(BackupOutcome.cancelled);
      }
      final selectedMode = await _askMode(context, t);
      if (selectedMode == null || _closed || !context.mounted) {
        return const BackupResult(BackupOutcome.cancelled);
      }
      final targetBoardId = selectedMode == 'merge-existing'
          ? await _askTargetBoard(context, t, store)
          : null;
      if (_closed ||
          !context.mounted ||
          (selectedMode == 'merge-existing' && targetBoardId == null)) {
        return const BackupResult(BackupOutcome.cancelled);
      }
      final mode = selectedMode == 'merge-existing' ? 'merge' : selectedMode;
      final plan = store.previewImport(
        json,
        mode,
        targetBoardId: targetBoardId,
      );
      final targetBoardName = targetBoardId == null
          ? null
          : store.boards
                .where((board) => board.id == targetBoardId)
                .firstOrNull
                ?.name;
      final choice = await _confirmPlan(
        context,
        t,
        plan,
        targetBoardName: targetBoardName,
      );
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
      return BackupResult(
        BackupOutcome.succeeded,
        '${t['importSuccess']} (${plan.addedTasks})'
        '${backupImportResultNotice(t, plan)}$desktopWarning',
      );
    } on BackupRejectedException catch (error) {
      return BackupResult(
        BackupOutcome.failed,
        t[error.copy] ?? t['importError']!,
      );
    } on FormatException catch (error) {
      return BackupResult(
        BackupOutcome.failed,
        backupImportFormatError(t, error),
      );
    } catch (_) {
      return BackupResult(
        BackupOutcome.failed,
        t[applying ? 'importSaveError' : 'importError']!,
      );
    } finally {
      _finish();
    }
  }

  Future<String?> _askMode(BuildContext context, Map<String, String> t) =>
      showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(t['importOptions']!),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t['importPrompt']!),
                const SizedBox(height: 8),
                Text(t['backupVersionInfo']!),
                const SizedBox(height: 8),
                for (final option in [
                  ('merge', 'importModeMerge', 'importModeMergeDesc'),
                  (
                    'merge-existing',
                    'importModeMergeInto',
                    'importModeMergeIntoDesc',
                  ),
                  (
                    'overwrite',
                    'importModeOverwrite',
                    'importModeOverwriteDesc',
                  ),
                ])
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(t[option.$2]!),
                    subtitle: Text(t[option.$3]!),
                    onTap: () => Navigator.pop(dialogContext, option.$1),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(t['cancel']!),
            ),
          ],
        ),
      );

  Future<String?> _askTargetBoard(
    BuildContext context,
    Map<String, String> t,
    Store store,
  ) {
    final boards = List.of(store.boards);
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(t['importSelectBoard']!),
        content: SizedBox(
          width: double.maxFinite,
          height: 320,
          child: ListView.builder(
            itemCount: boards.length,
            itemBuilder: (context, index) {
              final board = boards[index];
              return ListTile(
                title: Text(board.name),
                subtitle: Text(
                  board.id == store.activeBoardId
                      ? t['importCurrentBoard']!
                      : board.id,
                ),
                onTap: () => Navigator.pop(dialogContext, board.id),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(t['cancel']!),
          ),
        ],
      ),
    );
  }

  Future<String?> _confirmPlan(
    BuildContext context,
    Map<String, String> t,
    ImportPlan plan, {
    String? targetBoardName,
  }) => showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(t['importPreview']!),
      content: SingleChildScrollView(
        child: Text(
          '${backupImportVersionDescription(t, plan)}\n\n'
          '${_importDescription(t, plan, targetBoardName)}\n\n'
          '${backupImportSummary(t, plan)}\n\n'
          '${plan.hasCredential ? t['importCredentialPresent'] : ''}\n\n'
          '${backupImportWarningDetails(t, plan)}\n\n'
          '${plan.conflictingScheduleItems > 0 ? t['importScheduleConflictBlocked'] : ''}\n'
          '${plan.conflicts > 0 ? t['importConflictBlocked'] : ''}',
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
          onPressed: plan.conflicts > 0
              ? null
              : () => Navigator.pop(dialogContext, 'keep'),
          child: Text(
            plan.hasCredential ? t['importKeepCredential']! : t['confirm']!,
          ),
        ),
        if (plan.hasCredential)
          TextButton(
            onPressed: plan.conflicts > 0
                ? null
                : () => Navigator.pop(dialogContext, 'replace'),
            child: Text(t['importReplaceCredential']!),
          ),
      ],
    ),
  );

  String _importDescription(
    Map<String, String> t,
    ImportPlan plan,
    String? targetBoardName,
  ) {
    if (plan.mode == 'overwrite') return t['confirmImport']!;
    if (targetBoardName == null) return t['importModeMergeDesc']!;
    return '${t['importTargetBoard']}: $targetBoardName\n'
        '${t['importModeMergeIntoDesc']}';
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
