import 'dart:async';

import 'package:flutter/material.dart';

/// How long every in-app notice stays up, with or without an action.
const Duration kNoticeDuration = Duration(seconds: 4);

/// Shows a short message that always goes away on its own.
///
/// Only failures and notices the user needs (such as delete with Undo) should
/// use this; routine successes stay silent. Flutter keeps a SnackBar with an
/// action on screen when accessibility navigation is on, so a timer closes it
/// regardless.
void showAppNotice(
  BuildContext context,
  String message, {
  String? actionLabel,
  VoidCallback? onAction,
  Key? key,
  Key? actionKey,
  EdgeInsetsGeometry? margin,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  showAppNoticeOn(
    messenger,
    message,
    actionLabel: actionLabel,
    onAction: onAction,
    key: key,
    actionKey: actionKey,
    margin: margin,
  );
}

/// [showAppNotice] for callers that already hold the messenger (for example
/// an Undo handler whose row may be gone by the time it runs).
void showAppNoticeOn(
  ScaffoldMessengerState messenger,
  String message, {
  String? actionLabel,
  VoidCallback? onAction,
  Key? key,
  Key? actionKey,
  EdgeInsetsGeometry? margin,
}) {
  messenger.clearSnackBars();
  late final ScaffoldFeatureController<SnackBar, SnackBarClosedReason>
  controller;
  var closed = false;
  controller = messenger.showSnackBar(
    SnackBar(
      key: key,
      content: _AutoClose(
        // Delete notices share a SnackBar key. Give each timer its own state
        // when accessibility makes replacement happen within the same frame.
        key: UniqueKey(),
        onTimeout: () {
          if (!closed) controller.close();
        },
        child: Text(message),
      ),
      duration: kNoticeDuration,
      behavior: SnackBarBehavior.floating,
      dismissDirection: DismissDirection.horizontal,
      margin: margin,
      showCloseIcon: actionLabel == null,
      action: actionLabel == null
          ? null
          : SnackBarAction(
              key: actionKey,
              label: actionLabel,
              onPressed: onAction ?? () {},
            ),
    ),
  );
  controller.closed.whenComplete(() => closed = true);
}

/// Closes its SnackBar after [kNoticeDuration] even where Flutter would keep
/// it (an action under accessibility navigation, or a dialog covering the
/// page). The timer lives with the widget, so nothing outlives the screen.
class _AutoClose extends StatefulWidget {
  const _AutoClose({super.key, required this.onTimeout, required this.child});

  final VoidCallback onTimeout;
  final Widget child;

  @override
  State<_AutoClose> createState() => _AutoCloseState();
}

class _AutoCloseState extends State<_AutoClose> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(kNoticeDuration, widget.onTimeout);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
