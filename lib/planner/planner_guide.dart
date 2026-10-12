import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ui/platform_ui_policy.dart';

import 'planner_guide_flag.dart';

const _icons = [
  Icons.inbox_outlined,
  Icons.touch_app_outlined,
  Icons.ads_click,
  Icons.open_with,
  Icons.calendar_view_week_outlined,
  Icons.pinch,
];

/// First-visit tour of the planner. Skippable, shown once, and re-openable
/// from Settings. [markSeen] is false when it is reopened on purpose.
Future<void> showPlannerGuide(
  BuildContext context,
  Map<String, String> t, {
  bool markSeen = true,
}) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    // Esc does what Skip does (keyboard users on desktop).
    builder: (dialogContext) => CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.pop(dialogContext),
      },
      child: Focus(autofocus: true, child: _PlannerGuide(t: t)),
    ),
  );
  if (markSeen) await PlannerGuideFlags.mark(PlannerGuideFlags.guideKey);
}

class _PlannerGuide extends StatefulWidget {
  const _PlannerGuide({required this.t});
  final Map<String, String> t;

  @override
  State<_PlannerGuide> createState() => _PlannerGuideState();
}

class _PlannerGuideState extends State<_PlannerGuide> {
  final _pages = PageController();
  int _index = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final theme = Theme.of(context);
    final last = _index == _icons.length - 1;
    final reduce = MediaQuery.disableAnimationsOf(context);
    // Mouse and keyboard wording where it differs from touch.
    final desktop = PlatformUiPolicy.of(context).isDesktop;
    return Dialog(
      key: const ValueKey('schedule-guide'),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440, maxHeight: 360),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Expanded(
                child: PageView(
                  controller: _pages,
                  onPageChanged: (i) => setState(() => _index = i),
                  children: [
                    // Centred in the page, so short steps do not leave a
                    // block of empty space under the text.
                    for (var i = 0; i < _icons.length; i++)
                      Center(
                        key: ValueKey('schedule-guide-page-$i'),
                        child: SingleChildScrollView(
                          child: Column(
                            children: [
                              Icon(
                                _icons[i],
                                size: 56,
                                color: theme.colorScheme.primary,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                t['scheduleGuide${i + 1}Title']!,
                                style: theme.textTheme.titleLarge,
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                (desktop
                                        ? t['scheduleGuide${i + 1}BodyDesktop']
                                        : null) ??
                                    t['scheduleGuide${i + 1}Body']!,
                                style: theme.textTheme.bodyLarge,
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < _icons.length; i++)
                    Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i == _index
                            ? theme.colorScheme.primary
                            : theme.colorScheme.outlineVariant,
                      ),
                    ),
                ],
              ),
              Row(
                children: [
                  TextButton(
                    key: const ValueKey('schedule-guide-skip'),
                    onPressed: () => Navigator.pop(context),
                    child: Text(t['scheduleGuideSkip']!),
                  ),
                  const Spacer(),
                  FilledButton(
                    key: const ValueKey('schedule-guide-next'),
                    onPressed: () {
                      if (last) {
                        Navigator.pop(context);
                      } else if (reduce) {
                        _pages.jumpToPage(_index + 1);
                      } else {
                        _pages.nextPage(
                          duration: const Duration(milliseconds: 240),
                          curve: Curves.easeOut,
                        );
                      }
                    },
                    child: Text(
                      t[last ? 'scheduleGuideDone' : 'scheduleGuideNext']!,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
