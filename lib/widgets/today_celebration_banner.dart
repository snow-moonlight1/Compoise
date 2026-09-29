import 'package:flutter/material.dart';

import '../ui/motion_policy.dart';

/// Settled confirmation that the Today list in view was just cleared.
///
/// Motion plays a single fade. App or system reduce-motion shows this same
/// card on the first frame, with the close action already available.
class TodayCelebrationBanner extends StatefulWidget {
  const TodayCelebrationBanner({
    super.key,
    required this.title,
    required this.body,
    required this.closeLabel,
    required this.onClose,
  });

  final String title;
  final String body;
  final String closeLabel;
  final VoidCallback onClose;

  @override
  State<TodayCelebrationBanner> createState() => _TodayCelebrationBannerState();
}

class _TodayCelebrationBannerState extends State<TodayCelebrationBanner>
    with SingleTickerProviderStateMixin {
  AnimationController? _motion;
  CurvedAnimation? _fade;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
  }

  void _syncMotion() {
    if (MotionPolicy.reduceMotionNow(context)) {
      // Stop without disposing: this frame's child may still reference the
      // controller until build replaces it with the static card.
      _motion?.stop();
      return;
    }
    if (_motion == null) {
      final motion = AnimationController(
        vsync: this,
        duration: MotionPolicy.celebration,
      );
      _motion = motion;
      _fade = CurvedAnimation(parent: motion, curve: Curves.easeOut);
      motion.forward();
      return;
    }
    if (!_motion!.isCompleted && !_motion!.isAnimating) {
      _motion!.forward();
    }
  }

  @override
  void dispose() {
    _fade?.dispose();
    _motion?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final card = _card(context);
    final fade = _fade;
    if (MotionPolicy.reduceMotionOf(context) || fade == null) {
      return KeyedSubtree(
        key: const ValueKey('today-celebration-static'),
        child: card,
      );
    }
    return FadeTransition(
      key: const ValueKey('today-celebration-motion'),
      opacity: fade,
      child: card,
    );
  }

  Widget _card(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      liveRegion: true,
      child: Material(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.check_circle,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      key: const ValueKey('today-celebration-title'),
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.body,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        key: const ValueKey('today-celebration-close'),
                        onPressed: widget.onClose,
                        child: Text(widget.closeLabel),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
