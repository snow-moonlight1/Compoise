import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../storage.dart';

/// Central policy for custom animations: durations and the "reduce motion"
/// switch that is the logical OR of the app setting and the platform request.
///
/// Only this app's own setting is testable through widget tests; the platform
/// signal ([MediaQueryData.disableAnimations]) is injected in tests and is not
/// evidence that a real device setting was exercised.
class MotionPolicy {
  const MotionPolicy._();

  /// Strikethrough draw duration for a completed title (~220ms, easeOut).
  static const Duration strikethrough = Duration(milliseconds: 220);

  /// Hold between a finished strikethrough and the row collapsing.
  static const Duration exitHold = Duration(milliseconds: 220);

  /// Collapse duration of a row that is leaving a list (~120ms).
  static const Duration exitCollapse = Duration(milliseconds: 120);

  /// Entrance stagger step used by [StaggerIn].
  static const Duration entranceStep = Duration(milliseconds: 45);

  /// Fade + slide-up duration of one [StaggerIn] row (the stagger delay
  /// between rows is [entranceStep]).
  static const Duration entranceFade = Duration(milliseconds: 260);

  /// UX07 continuous-geometry transition: matrix -> focused quadrant.
  static const Duration geometryEnter = Duration(milliseconds: 320);

  /// UX07 continuous-geometry transition: retargeting to another quadrant.
  static const Duration geometrySwitch = Duration(milliseconds: 300);

  /// UX07 continuous-geometry transition: focused quadrant -> matrix.
  static const Duration geometryExit = Duration(milliseconds: 280);

  /// Fade of the list-mode focus overlay enter/exit.
  static const Duration listFade = Duration(milliseconds: 220);

  /// Animated scroll-to-top after a task is dropped into a quadrant.
  static const Duration scrollToTop = Duration(milliseconds: 250);

  /// Onboarding page turn between tutorial slides.
  static const Duration pageTurn = Duration(milliseconds: 300);

  /// Dismissible swipe movement / resize when completing or deleting a card.
  static const Duration dismissible = Duration(milliseconds: 200);

  /// Drag-target hover tint on a quadrant/list section. Deliberately kept
  /// animated even under reduce motion: it is a local pointer affordance that
  /// never gates hit testing or focus, and is outside the OS23 transition set.
  static const Duration hoverHighlight = Duration(milliseconds: 180);

  /// Reads the policy and rebuilds the caller when the app setting changes.
  static bool reduceMotionOf(BuildContext context) {
    if (_systemRequestsReducedMotion(context)) return true;
    try {
      return context.watch<Store>().settings.reduceMotion;
    } on ProviderNotFoundException {
      return false;
    }
  }

  /// Reads the policy without registering a rebuild dependency, so it is safe
  /// from [State.initState] and from animation callbacks.
  static bool reduceMotionNow(BuildContext context) {
    if (_systemRequestsReducedMotion(context)) return true;
    try {
      return Provider.of<Store>(context, listen: false).settings.reduceMotion;
    } on ProviderNotFoundException {
      return false;
    }
  }

  static bool _systemRequestsReducedMotion(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;
}
