import 'dart:async';

import '../save_protocol.dart';

enum DesktopExitSaveProblem { failed, timedOut }

enum DesktopExitSaveChoice { retry, exitWithoutSaving, cancel }

typedef DesktopExitSavePrompt =
    Future<DesktopExitSaveChoice> Function(DesktopExitSaveProblem problem);

/// Waits for the latest Store batch before exit and requires an explicit
/// decision whenever persistence fails or exceeds the bounded wait.
class DesktopExitSaveCoordinator {
  final Future<SaveResult> Function() flush;
  final Future<SaveResult> Function() retrySave;
  final DesktopExitSavePrompt chooseAfterProblem;
  final Duration timeout;

  const DesktopExitSaveCoordinator({
    required this.flush,
    required this.retrySave,
    required this.chooseAfterProblem,
    required this.timeout,
  });

  Future<bool> prepareToExit() async {
    var save = flush;
    while (true) {
      DesktopExitSaveProblem? problem;
      try {
        final result = await save().timeout(timeout);
        if (result.success) return true;
        problem = DesktopExitSaveProblem.failed;
      } on TimeoutException {
        problem = DesktopExitSaveProblem.timedOut;
      } catch (_) {
        problem = DesktopExitSaveProblem.failed;
      }

      switch (await chooseAfterProblem(problem)) {
        case DesktopExitSaveChoice.retry:
          save = retrySave;
        case DesktopExitSaveChoice.exitWithoutSaving:
          return true;
        case DesktopExitSaveChoice.cancel:
          return false;
      }
    }
  }
}
