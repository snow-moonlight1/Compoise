import 'package:flutter/material.dart';

import '../models.dart';
import '../services/desktop_exit_coordinator.dart';

class DesktopExitStrings {
  final String saveFailedTitle;
  final String saveFailedMessage;
  final String saveTimedOutTitle;
  final String saveTimedOutMessage;
  final String retry;
  final String exitWithoutSaving;
  final String cancelExit;

  const DesktopExitStrings({
    required this.saveFailedTitle,
    required this.saveFailedMessage,
    required this.saveTimedOutTitle,
    required this.saveTimedOutMessage,
    required this.retry,
    required this.exitWithoutSaving,
    required this.cancelExit,
  });

  static DesktopExitStrings forLanguage(
    Language language,
  ) => switch (language) {
    Language.zh => const DesktopExitStrings(
      saveFailedTitle: '无法保存更改',
      saveFailedMessage: '最新更改尚未保存。你可以重试、不保存并退出，或取消退出。',
      saveTimedOutTitle: '保存耗时过长',
      saveTimedOutMessage: '尚未确认最新更改已保存。你可以重试、不保存并退出，或取消退出。',
      retry: '重试',
      exitWithoutSaving: '不保存并退出',
      cancelExit: '取消退出',
    ),
    Language.ja => const DesktopExitStrings(
      saveFailedTitle: '変更を保存できません',
      saveFailedMessage: '最新の変更は保存されていません。再試行、保存せずに終了、または終了のキャンセルを選択してください。',
      saveTimedOutTitle: '保存に時間がかかっています',
      saveTimedOutMessage:
          '最新の変更が保存されたことを確認できません。再試行、保存せずに終了、または終了のキャンセルを選択してください。',
      retry: '再試行',
      exitWithoutSaving: '保存せずに終了',
      cancelExit: '終了をキャンセル',
    ),
    Language.en => const DesktopExitStrings(
      saveFailedTitle: "Couldn't save changes",
      saveFailedMessage:
          'The latest changes were not saved. Retry, exit without saving, or cancel exit.',
      saveTimedOutTitle: 'Saving is taking too long',
      saveTimedOutMessage:
          'The latest changes are not confirmed saved. Retry, exit without saving, or cancel exit.',
      retry: 'Retry',
      exitWithoutSaving: 'Exit without saving',
      cancelExit: 'Cancel exit',
    ),
  };
}

Future<DesktopExitSaveChoice> showDesktopExitSaveProblem(
  BuildContext context,
  DesktopExitSaveProblem problem,
  Language language,
) async {
  final strings = DesktopExitStrings.forLanguage(language);
  final choice = await showDialog<DesktopExitSaveChoice>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      title: Text(
        problem == DesktopExitSaveProblem.timedOut
            ? strings.saveTimedOutTitle
            : strings.saveFailedTitle,
      ),
      content: Text(
        problem == DesktopExitSaveProblem.timedOut
            ? strings.saveTimedOutMessage
            : strings.saveFailedMessage,
      ),
      actions: [
        TextButton(
          key: const ValueKey('exit-save-cancel'),
          onPressed: () =>
              Navigator.pop(dialogContext, DesktopExitSaveChoice.cancel),
          child: Text(strings.cancelExit),
        ),
        TextButton(
          key: const ValueKey('exit-save-retry'),
          onPressed: () =>
              Navigator.pop(dialogContext, DesktopExitSaveChoice.retry),
          child: Text(strings.retry),
        ),
        FilledButton(
          key: const ValueKey('exit-without-saving'),
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(dialogContext).colorScheme.error,
          ),
          onPressed: () => Navigator.pop(
            dialogContext,
            DesktopExitSaveChoice.exitWithoutSaving,
          ),
          child: Text(strings.exitWithoutSaving),
        ),
      ],
    ),
  );
  return choice ?? DesktopExitSaveChoice.cancel;
}
