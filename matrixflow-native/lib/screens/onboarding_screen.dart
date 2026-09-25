import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../quadrant.dart';
import '../storage.dart';
import '../ui/motion_policy.dart';
import '../ui/platform_ui_policy.dart';

class OnboardingScreen extends StatefulWidget {
  final bool isReviewMode;

  const OnboardingScreen({super.key, this.isReviewMode = false});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  /// Target of an in-flight programmatic page turn, so toggling reduce motion
  /// on mid-slide can jump straight to the intended slide instead of waiting
  /// for the ~300ms turn to finish.
  int? _turnTarget;
  int _turnGeneration = 0;
  static const int _pageCount = 5;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _finish() {
    if (!widget.isReviewMode) {
      context.read<Store>().completeOnboarding();
    }
    Navigator.of(context).pop();
  }

  void _goToPage(int target) {
    final generation = ++_turnGeneration;
    _turnTarget = target;
    // Under reduced motion the tutorial flips to the slide instead of sliding
    // across it; both the Next button and arrow keys share this path.
    if (MotionPolicy.reduceMotionNow(context)) {
      setState(() => _currentPage = target);
      _pageController.jumpToPage(target);
      _turnTarget = null;
    } else {
      _pageController.animateToPage(
        target,
        duration: MotionPolicy.pageTurn,
        curve: Curves.easeInOut,
      ).whenComplete(() {
        if (generation == _turnGeneration) _turnTarget = null;
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reduce motion switched on while a programmatic page turn is still
    // sliding: jump to the intended slide on the next frame.
    final target = _turnTarget;
    if (target != null && MotionPolicy.reduceMotionOf(context)) {
      final generation = _turnGeneration;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            generation != _turnGeneration ||
            _turnTarget != target ||
            !MotionPolicy.reduceMotionNow(context)) {
          return;
        }
        _turnGeneration++;
        _pageController.jumpToPage(target);
        _turnTarget = null;
      });
    }
  }

  void _nextPage() {
    if (_currentPage < _pageCount - 1) {
      _goToPage(_currentPage + 1);
    } else {
      _finish();
    }
  }

  void _prevPage() {
    if (_currentPage > 0) {
      _goToPage(_currentPage - 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<Store>();
    final t = store.t;
    final theme = Theme.of(context);
    final policy = PlatformUiPolicy.of(context);
    final step1Desc =
        '${t['onboardingStep1Desc']!} ${policy.isTouchLayout ? t['onboardingNavAndroid']! : t['onboardingNavWindows']!}'
            .trim();
    final step2Desc =
        policy.isTouchLayout
            ? t['onboardingStep2DescAndroid']!
            : t['onboardingStep2Desc']!;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): _finish,
            const SingleActivator(LogicalKeyboardKey.arrowRight): _nextPage,
            const SingleActivator(LogicalKeyboardKey.arrowLeft): _prevPage,
          },
          child: Focus(
            autofocus: true,
            child: Column(
              children: [
                // Top App Bar: Skip or Close button
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (widget.isReviewMode)
                        Text(
                          t['onboarding']!,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        )
                      else
                        const SizedBox.shrink(),
                      TextButton(
                        key: const ValueKey('onboarding-skip-btn'),
                        onPressed: _finish,
                        child: Text(
                          widget.isReviewMode
                              ? t['onboardingClose']!
                              : t['onboardingSkip']!,
                          style: TextStyle(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Main PageView with 5 slides
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    onPageChanged: (index) =>
                        setState(() => _currentPage = index),
                    children: [
                      _buildSlide(
                        context,
                        step: 1,
                        icon: Icons.grid_view,
                        iconColor: const Color(0xFFE53935),
                        title: t['onboardingStep1Title']!,
                        description: step1Desc,
                        mockup: _buildMatrixMockup(theme, t),
                      ),
                      _buildSlide(
                        context,
                        step: 2,
                        icon: Icons.open_with,
                        iconColor: const Color(0xFF1E88E5),
                        title: t['onboardingStep2Title']!,
                        description: step2Desc,
                        mockup: _buildDragMockup(theme, t),
                      ),
                      _buildSlide(
                        context,
                        step: 3,
                        icon: Icons.checklist,
                        iconColor: const Color(0xFF43A047),
                        title: t['onboardingStep3Title']!,
                        description: t['onboardingStep3Desc']!,
                        mockup: _buildDetailsMockup(theme, t),
                      ),
                      _buildSlide(
                        context,
                        step: 4,
                        icon: Icons.history,
                        iconColor: const Color(0xFFFB8C00),
                        title: t['onboardingStep4Title']!,
                        description: t['onboardingStep4Desc']!,
                        mockup: _buildCompletedMockup(theme, t),
                      ),
                      _buildSlide(
                        context,
                        step: 5,
                        icon: Icons.auto_awesome,
                        iconColor: const Color(0xFF8E24AA),
                        title: t['onboardingStep5Title']!,
                        description: t['onboardingStep5Desc']!,
                        mockup: _buildAiMockup(theme, t),
                      ),
                    ],
                  ),
                ),

                // Bottom Navigation: Indicator Dots & Action Buttons
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  child: Row(
                    children: [
                      // Back button
                      if (_currentPage > 0)
                        OutlinedButton(
                          key: const ValueKey('onboarding-prev-btn'),
                          onPressed: _prevPage,
                          child: Text(t['onboardingPrev']!),
                        )
                      else
                        const SizedBox(width: 80),

                      const Spacer(),

                      // Dots indicator
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: List.generate(
                          _pageCount,
                          (index) => Container(
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            width: _currentPage == index ? 20 : 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: _currentPage == index
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ),

                      const Spacer(),

                      // Next / Start button
                      FilledButton(
                        key: const ValueKey('onboarding-next-btn'),
                        onPressed: _nextPage,
                        child: Text(
                          _currentPage == _pageCount - 1
                              ? (widget.isReviewMode
                                  ? t['onboardingClose']!
                                  : t['onboardingStart']!)
                              : t['onboardingNext']!,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSlide(
    BuildContext context, {
    required int step,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String description,
    required Widget mockup,
  }) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580),
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 40, color: iconColor),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              description,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 24),
            mockup,
          ],
        ),
      ),
    );
  }

  Widget _buildMatrixMockup(ThemeData theme, Map<String, String> t) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _mockQuadrantCard(
                  title: t['q1']!,
                  color: Color(quadrantColors[1]!),
                  items: t['onboardingSampleQ1']!.split('\n'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _mockQuadrantCard(
                  title: t['q2']!,
                  color: Color(quadrantColors[2]!),
                  items: t['onboardingSampleQ2']!.split('\n'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _mockQuadrantCard(
                  title: t['q3']!,
                  color: Color(quadrantColors[3]!),
                  items: t['onboardingSampleQ3']!.split('\n'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _mockQuadrantCard(
                  title: t['q4']!,
                  color: Color(quadrantColors[4]!),
                  items: t['onboardingSampleQ4']!.split('\n'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _mockQuadrantCard({
    required String title,
    required Color color,
    required List<String> items,
  }) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                '• $item',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDragMockup(ThemeData theme, Map<String, String> t) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                  border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.5)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.drag_indicator, size: 16, color: theme.colorScheme.primary),
                    const SizedBox(width: 6),
                    Text(
                      t['onboardingSampleDragTask']!,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Icon(Icons.arrow_forward, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E88E5).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF1E88E5)),
                ),
                child: Text(
                  t['q2']!,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF1E88E5)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            t['onboardingDragHint']!,
            style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsMockup(ThemeData theme, Map<String, String> t) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_box_outlined, size: 16),
              const SizedBox(width: 6),
              Text(
                t['onboardingSampleDetailTask']!,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    Icon(Icons.alarm, size: 12, color: theme.colorScheme.primary),
                    const SizedBox(width: 3),
                    Text('09:00', style: TextStyle(fontSize: 10, color: theme.colorScheme.primary)),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 16),
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(Icons.check_circle, size: 14, color: theme.colorScheme.primary),
                    const SizedBox(width: 6),
                    Text(
                      '1. ${t['onboardingSampleSubtask1']!}',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.radio_button_unchecked, size: 14, color: theme.colorScheme.outline),
                    const SizedBox(width: 6),
                    Text(
                      '2. ${t['onboardingSampleSubtask2']!}',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompletedMockup(ThemeData theme, Map<String, String> t) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.task_alt),
            title: Text(t['completedTasks']!),
            subtitle: Text(t['completedAtTime']!.replaceAll('{time}', '12:30')),
          ),
          Wrap(
            spacing: 16,
            children: [Text(t['restoreTask']!), Text(t['deleteCompletedTask']!)],
          ),
        ],
      ),
    );
  }

  Widget _buildAiMockup(ThemeData theme, Map<String, String> t) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _providerChip('DeepSeek', theme),
              const SizedBox(width: 6),
              _providerChip('Qwen', theme),
              const SizedBox(width: 6),
              _providerChip('Doubao', theme),
              const SizedBox(width: 6),
              _providerChip('OpenAI', theme),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.shield_outlined, size: 16, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Text(
                t['onboardingLocalBadge']!,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: theme.colorScheme.primary),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _providerChip(String label, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
    );
  }
}
