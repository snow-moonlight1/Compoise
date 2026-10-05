import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../storage.dart';
import '../theme.dart';
import '../ui/motion_policy.dart';
import 'quadrant_pane.dart';
import 'task_card.dart';

/// Continuous geometric transition between the 2x2 matrix and a focused
/// single-quadrant layout.
///
/// All four [QuadrantPane]s live permanently inside one bounded [Stack] with
/// stable keys; entering, switching and exiting focus only retarget the
/// interpolation between rect layouts — the trees are never swapped, so pane
/// state, scroll offsets and animations survive every transition.
///
/// Contract (UX07, plan 5.3):
/// * Geometry is computed from the *content area* constraints, never from
///   absolute screen coordinates, so resizes / opening the detail panel
///   re-layout both endpoints.
/// * Interrupting an animation (back, another focus target, view change)
///   bakes the current geometry as the new source — it never snaps back to
///   the first frame.
/// * With reduced motion the layout jumps straight to the target state.
/// * Collapsed panes/cards are excluded from hit testing, focus and
///   semantics; during the transition the task rows are inert while the
///   bottom cards stay tappable to retarget.
class QuadrantTransitionLayout extends StatefulWidget {
  const QuadrantTransitionLayout({
    super.key,
    required this.focusedQuadrant,
    required this.viewMode,
    this.selecting = false,
    this.selectedIds = const {},
    this.expandedIds = const {},
    this.onSelect,
    this.onToggleExpand,
    this.onEnsureExpanded,
    required this.onFocusQuadrant,
    required this.onExitFocus,
    this.onEdit,
    this.onEditSubtask,
    this.fadeOutOnly = false,
    this.onFadeOutDone,
  });

  /// The quadrant currently focused, or null for the 2x2 matrix.
  final int? focusedQuadrant;

  /// The source presentation mode; in list mode the overlay only fades in
  /// and out, while matrix mode uses the full four-region geometry.
  final ViewMode viewMode;

  final bool selecting;
  final Set<String> selectedIds;
  final Set<String> expandedIds;
  final ValueChanged<String>? onSelect;
  final ValueChanged<String>? onToggleExpand;
  final ValueChanged<String>? onEnsureExpanded;

  /// Matrix header tap or bottom-card tap: focus (or switch to) a quadrant.
  final ValueChanged<int> onFocusQuadrant;

  /// Focused header tap: return to the previous mode.
  final VoidCallback onExitFocus;

  final ValueChanged<Task>? onEdit;
  final void Function(Task task, String subtaskId)? onEditSubtask;

  /// List mode only: the focus overlay is fading out and will be unmounted
  /// by the parent once [onFadeOutDone] fires.
  final bool fadeOutOnly;
  final VoidCallback? onFadeOutDone;

  @override
  State<QuadrantTransitionLayout> createState() =>
      _QuadrantTransitionLayoutState();
}

class _QuadrantTransitionLayoutState extends State<QuadrantTransitionLayout>
    with TickerProviderStateMixin {
  late final AnimationController _geometry = AnimationController(
    vsync: this,
    value: 1,
  )..addStatusListener(_onGeometryStatus);
  late final AnimationController _listFade = AnimationController(
    vsync: this,
    duration: MotionPolicy.listFade,
    value:
        _inListMode && widget.focusedQuadrant != null && !widget.fadeOutOnly
            ? 0
            : 1,
  )..addStatusListener(_onListFadeStatus);

  /// Bumped on every list fade-out start or cancel so a stale dismissed
  /// callback cannot complete a newer focus session (R1/R2/R5).
  int _listFadeGeneration = 0;
  int _listFadeNotifiedGeneration = -1;

  int? _fromState;
  int? _toState;

  /// Current geometry baked when a transition is interrupted, stored as
  /// fractions of the layout size so resizes still recompute both endpoints.
  List<Rect>? _frozenRelFrom;
  double? _frozenFromBlend;
  List<double>? _frozenPaneOpacity;

  Size? _lastSize;
  bool _depsResolved = false;

  bool get _inListMode => widget.viewMode == ViewMode.list;

  @override
  void initState() {
    super.initState();
    _fromState = null;
    _toState = widget.focusedQuadrant;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_depsResolved) return;
    _depsResolved = true;
    if (widget.fadeOutOnly) {
      // Recreated mid-exit (sidebar reparent without a stable key): finish
      // immediately. Replaying an enter/exit from this new State would stick
      // at opacity 0 because reverse() from 0 never fires dismissed again.
      _listFadeGeneration++;
      _listFade
        ..stop()
        ..value = 0;
      _scheduleFadeOutDone();
      return;
    }
    if (MotionPolicy.reduceMotionNow(context)) {
      _geometry.value = 1;
      _listFade.value = 1;
    } else if (_inListMode && widget.focusedQuadrant != null) {
      _listFade.forward();
    }
  }

  @override
  void didUpdateWidget(covariant QuadrantTransitionLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewMode != widget.viewMode) {
      // Mode swaps snap the geometry to a consistent final state.
      _geometry
        ..stop()
        ..value = 1;
      _frozenRelFrom = null;
      _frozenFromBlend = null;
      _frozenPaneOpacity = null;
      _fromState = _toState;
      // Invalidate any in-flight list fade. Restoring opacity to 1 while
      // fadeOutOnly is still true would stop reverse() and never dismiss.
      _listFadeGeneration++;
      if (widget.fadeOutOnly) {
        _listFade
          ..stop()
          ..value = 0;
        _scheduleFadeOutDone();
      } else if (_inListMode && widget.focusedQuadrant != null) {
        _listFade.value = 1;
      }
    }
    if (widget.focusedQuadrant != oldWidget.focusedQuadrant) {
      _retarget(widget.focusedQuadrant);
    }
    if (widget.fadeOutOnly != oldWidget.fadeOutOnly) {
      if (widget.fadeOutOnly) {
        _beginListFadeOut();
      } else {
        // Re-focus (or any new session) must reverse the outgoing fade from
        // the current opacity; a stale dismissed callback is invalidated.
        _cancelListFadeOut();
      }
    }
  }

  @override
  void dispose() {
    _geometry.dispose();
    _listFade.dispose();
    super.dispose();
  }

  void _beginListFadeOut() {
    _listFadeGeneration++;
    if (MotionPolicy.reduceMotionNow(context) || _listFade.value == 0) {
      _listFade
        ..stop()
        ..value = 0;
      _scheduleFadeOutDone();
      return;
    }
    _listFade.reverse();
  }

  void _cancelListFadeOut() {
    _listFadeGeneration++;
    if (MotionPolicy.reduceMotionNow(context)) {
      _listFade
        ..stop()
        ..value = 1;
      return;
    }
    _listFade.forward();
  }

  void _scheduleFadeOutDone() {
    final generation = _listFadeGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (generation != _listFadeGeneration) return;
      if (generation == _listFadeNotifiedGeneration) return;
      if (!widget.fadeOutOnly) return;
      _listFadeNotifiedGeneration = generation;
      widget.onFadeOutDone?.call();
    });
  }

  void _onListFadeStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed && widget.fadeOutOnly) {
      _scheduleFadeOutDone();
    }
  }

  void _onGeometryStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _frozenRelFrom = null;
      _frozenFromBlend = null;
      _frozenPaneOpacity = null;
      _fromState = _toState;
    }
  }

  Duration _durationFor(int? from, int? to) {
    if (to == null) return MotionPolicy.geometryExit;
    if (from == null) return MotionPolicy.geometryEnter;
    return MotionPolicy.geometrySwitch;
  }

  double _paneOpacityFor(int? state, int q) =>
      (state == null || q == state) ? 1.0 : 0.0;

  double _blendOf(int? state) => state == null ? 0.0 : 1.0;

  void _retarget(int? newFocus) {
    final previous = _toState;
    if (newFocus == previous && _frozenRelFrom == null) return;
    if (MotionPolicy.reduceMotionNow(context)) {
      _geometry
        ..stop()
        ..value = 1;
      _frozenRelFrom = null;
      _frozenFromBlend = null;
      _frozenPaneOpacity = null;
      _fromState = newFocus;
      _toState = newFocus;
      setState(() {});
      return;
    }

    final t = Curves.easeInOutCubic.transform(_geometry.value);
    final size = _lastSize;
    if (size != null && size.width > 0 && size.height > 0) {
      final current = _currentRects(size, t);
      _frozenRelFrom = [
        for (final rect in current) _relativize(rect, size),
      ];
      final fromBlend = _frozenFromBlend ?? _blendOf(_fromState);
      _frozenFromBlend =
          fromBlend + (_blendOf(_toState) - fromBlend) * t;
      _frozenPaneOpacity = [
        for (final q in allQuadrants) _paneOpacityAt(q, t),
      ];
    } else {
      _frozenRelFrom = null;
      _frozenFromBlend = null;
      _frozenPaneOpacity = null;
    }
    // Approximate the source state for opacity interpolation after an
    // interruption; the frozen values above carry the exact geometry.
    if (_frozenRelFrom == null || _geometry.value >= 0.5) {
      _fromState = previous;
    }
    _toState = newFocus;
    _geometry
      ..value = 0
      ..animateTo(
        1,
        duration: _durationFor(previous, newFocus),
        curve: Curves.easeInOutCubic,
      );
  }

  double _paneOpacityAt(int q, double t) {
    if (_frozenPaneOpacity != null) {
      final frozen = _frozenPaneOpacity![allQuadrants.indexOf(q)];
      return frozen + (_paneOpacityFor(_toState, q) - frozen) * t;
    }
    final from = _paneOpacityFor(_fromState, q);
    return from + (_paneOpacityFor(_toState, q) - from) * t;
  }

  static Rect _relativize(Rect rect, Size size) => Rect.fromLTWH(
    rect.left / size.width,
    rect.top / size.height,
    rect.width / size.width,
    rect.height / size.height,
  );

  static Rect _absolutize(Rect rect, Size size) => Rect.fromLTWH(
    rect.left * size.width,
    rect.top * size.height,
    rect.width * size.width,
    rect.height * size.height,
  );

  List<Rect> _currentRects(Size size, double t) {
    final from =
        _frozenRelFrom != null
            ? [for (final rect in _frozenRelFrom!) _absolutize(rect, size)]
            : _layoutFor(size, _fromState).rects;
    final to = _layoutFor(size, _toState).rects;
    return [for (var i = 0; i < 4; i++) Rect.lerp(from[i], to[i], t)!];
  }

  ({List<Rect> rects, double cardsTop}) _layoutFor(Size size, int? focus) {
    if (focus == null) {
      final qw = size.width / 2;
      final qh = size.height / 2;
      return (
        rects: [
          Rect.fromLTWH(0, 0, qw, qh),
          Rect.fromLTWH(qw, 0, qw, qh),
          Rect.fromLTWH(0, qh, qw, qh),
          Rect.fromLTWH(qw, qh, qw, qh),
        ],
        cardsTop: size.height,
      );
    }

    final theme = Theme.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final store = context.read<Store>();
    final others = allQuadrants.where((q) => q != focus).toList();
    final titleStyle = theme.textTheme.labelSmall!.copyWith(
      fontWeight: FontWeight.w600,
      height: 1.15,
    );
    // Three columns normally; stacked rows on very narrow widths or huge
    // text scale so every card keeps a >=48dp touch target.
    final stackCards = size.width / 3 < 100;
    final cardH = _cardHeight(size, titleStyle, scaler, [
      for (final q in others) store.t['q$q'] ?? 'Q$q',
    ], stackCards);
    const gap = 8.0;
    final cardsH = stackCards ? cardH * 3 + 8 : cardH + 6;
    final mainH = (size.height - cardsH - gap).clamp(120.0, size.height);
    final cardsTop = mainH + gap;

    final rects = List<Rect>.filled(allQuadrants.length, Rect.zero);
    rects[allQuadrants.indexOf(focus)] = Rect.fromLTWH(
      0,
      0,
      size.width,
      mainH,
    );
    for (var i = 0; i < others.length; i++) {
      final idx = allQuadrants.indexOf(others[i]);
      if (stackCards) {
        rects[idx] = Rect.fromLTWH(
          6,
          cardsTop + i * (cardH + 2),
          size.width - 12,
          cardH,
        );
      } else {
        final cardW = (size.width - 12 - 12) / 3;
        rects[idx] = Rect.fromLTWH(6 + i * (cardW + 6), cardsTop, cardW, cardH);
      }
    }
    return (rects: rects, cardsTop: cardsTop);
  }

  double _cardHeight(
    Size size,
    TextStyle titleStyle,
    TextScaler scaler,
    List<String> titles,
    bool stackCards,
  ) {
    final cardW =
        stackCards ? size.width - 12 : (size.width - 12 - 12) / 3;
    final titleW = math.max(24.0, cardW - 16);
    var maxTitleH = 0.0;
    for (final title in titles) {
      final painter = TextPainter(
        text: TextSpan(text: title, style: titleStyle),
        maxLines: 2,
        textDirection: TextDirection.ltr,
        textScaler: scaler,
      );
      try {
        painter.layout(maxWidth: titleW);
        maxTitleH = math.max(maxTitleH, painter.height);
      } finally {
        painter.dispose();
      }
    }
    // dot/count row (16) + gap (3) + title + vertical padding (12).
    return math.max(48.0, 31.0 + maxTitleH);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<Store>();
    final t = store.t;
    final theme = Theme.of(context);
    final comic = theme.extension<ComicOutline>();
    final hairline = theme.brightness == Brightness.light
        ? const Color(0xFFD5DAE1)
        : theme.colorScheme.outlineVariant;
    final crossColor = comic?.edge ?? hairline;
    final cross = comic == null ? 1.0 : 2.0;

    final reduceMotion = MotionPolicy.reduceMotionOf(context);
    if (reduceMotion) {
      // Reduce motion switched on mid-transition: bake the geometry terminal
      // immediately instead of letting the retarget animation finish.
      if (_geometry.isAnimating) {
        _geometry
          ..stop()
          ..value = 1;
        _frozenRelFrom = null;
        _frozenFromBlend = null;
        _frozenPaneOpacity = null;
        _fromState = _toState;
      }
      // The list-mode overlay fades on its own controller; reconcile it too so
      // a runtime toggle does not leave the overlay fading for another ~220ms.
      final listTerminal = widget.fadeOutOnly ? 0.0 : 1.0;
      if (_listFade.value != listTerminal) {
        _listFade
          ..stop()
          ..value = listTerminal;
        if (widget.fadeOutOnly) _scheduleFadeOutDone();
      }
    }

    return AnimatedBuilder(
      animation: _geometry,
      builder:
          (context, _) => LayoutBuilder(
            builder: (context, constraints) {
        final boundedH =
            constraints.maxHeight.isFinite ? constraints.maxHeight : 440.0;
        final needsScroll = boundedH < 440;
        final size = Size(
          constraints.maxWidth,
          needsScroll ? 440.0 : boundedH,
        );
        _lastSize = size;

        final progress = Curves.easeInOutCubic.transform(_geometry.value);
        final rects = _currentRects(size, progress);
        final toLayout = _layoutFor(size, _toState);
        final animating = _geometry.isAnimating;

        final fromBlend = _frozenFromBlend ?? _blendOf(_fromState);
        final focusBlend =
            fromBlend + (_blendOf(_toState) - fromBlend) * progress;

        final topQuadrant = _toState ?? allQuadrants.first;
        final orderedQuadrants = [
          for (final q in allQuadrants)
            if (q != topQuadrant) q,
          topQuadrant,
        ];

        final children = <Widget>[
          // Cross divider of the matrix, fading out with focus; and the
          // divider above the collapsed cards, fading in.
          Positioned(
            key: const ValueKey('matrix-divider-v'),
            left: size.width / 2 - cross / 2,
            top: 0,
            width: cross,
            height: size.height,
            child: Opacity(
              opacity: 1 - focusBlend,
              child: ColoredBox(color: crossColor),
            ),
          ),
          Positioned(
            key: const ValueKey('matrix-divider-h'),
            top: size.height / 2 - cross / 2,
            left: 0,
            height: cross,
            width: size.width,
            child: Opacity(
              opacity: 1 - focusBlend,
              child: ColoredBox(color: crossColor),
            ),
          ),
          Positioned(
            top: toLayout.cardsTop - 5,
            left: 0,
            height: 1,
            width: size.width,
            child: Opacity(
              opacity: focusBlend,
              child: ColoredBox(color: hairline),
            ),
          ),
          if (_toState != null && !widget.fadeOutOnly)
            const Positioned(
              left: 0,
              top: 0,
              child: SizedBox.shrink(key: ValueKey('focus-view-active')),
            ),
          for (final q in orderedQuadrants)
            _buildRegion(
              q: q,
              rect: rects[allQuadrants.indexOf(q)],
              progress: progress,
              animating: animating,
              store: store,
              t: t,
            ),
        ];

        Widget content = SizedBox(
          width: size.width,
          height: size.height,
          child: Stack(children: children),
        );

        if (_inListMode) {
          content = FadeTransition(
            opacity: _listFade,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.03),
                end: Offset.zero,
              ).animate(
                CurvedAnimation(parent: _listFade, curve: Curves.easeOut),
              ),
              child: content,
            ),
          );
        }

        return needsScroll ? SingleChildScrollView(child: content) : content;
            },
          ),
    );
  }

  Widget _buildRegion({
    required int q,
    required Rect rect,
    required double progress,
    required bool animating,
    required Store store,
    required Map<String, String> t,
  }) {
    final paneOpacity = _paneOpacityAt(q, progress);
    final cardOpacity = 1 - paneOpacity;
    final buildCard =
        _paneOpacityFor(_fromState, q) < 1 || _paneOpacityFor(_toState, q) < 1;
    final isMain =
        (_toState == q && progress >= 0.5) ||
        (_toState != q && _fromState == q && progress < 0.5);

    return Positioned.fromRect(
      key: ValueKey('q-region-$q'),
      rect: rect,
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Offstage(
              offstage: paneOpacity <= 0,
              child: ExcludeFocus(
                // Offstage and IgnorePointer do not clear keyboard focus.
                excluding: animating || paneOpacity < 0.5,
                child: IgnorePointer(
                ignoring: animating || paneOpacity < 0.5,
                child: ExcludeSemantics(
                  excluding: animating || paneOpacity < 0.5,
                  child: Opacity(
                    opacity: paneOpacity,
                    child: QuadrantPane(
                      key: ValueKey('q-pane-$q'),
                      quadrant: q,
                      selecting: widget.selecting,
                      selectedIds: widget.selectedIds,
                      expandedIds: widget.expandedIds,
                      onSelect: widget.onSelect,
                      onToggleExpand: widget.onToggleExpand,
                      onEnsureExpanded: widget.onEnsureExpanded,
                      isFocused: isMain,
                      rowLayout:
                          isMain
                              ? TaskRowLayout.hierarchical
                              : TaskRowLayout.matrixCompact,
                      onQuadrantTap: () {
                        if (_toState == null) {
                          widget.onFocusQuadrant(q);
                        } else if (_toState == q) {
                          widget.onExitFocus();
                        } else {
                          widget.onFocusQuadrant(q);
                        }
                      },
                      onEdit: widget.onEdit,
                      onEditSubtask: widget.onEditSubtask,
                    ),
                  ),
                ),
                ),
              ),
            ),
            if (buildCard)
              Offstage(
                offstage: cardOpacity <= 0,
                child: ExcludeFocus(
                  excluding: cardOpacity < 0.5,
                  child: IgnorePointer(
                  // Tappable as soon as visible so a mid-animation tap can
                  // retarget to another quadrant; drops stay gated below.
                  ignoring: cardOpacity <= 0,
                  child: ExcludeSemantics(
                    excluding: cardOpacity < 0.5,
                    child: Opacity(
                      opacity: cardOpacity,
                      child: _CollapsedQuadrantCard(
                        key: ValueKey('focus-card-$q'),
                        quadrant: q,
                        title: t['q$q'] ?? 'Q$q',
                        count: store.tasksIn(q).length,
                        accent: Color(quadrantColors[q]!),
                        selecting: widget.selecting,
                        enabled: !animating,
                        onTap: () => widget.onFocusQuadrant(q),
                        onDropTask: (task) => store.moveTask(task.id, q),
                      ),
                    ),
                  ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Bottom card for a collapsed quadrant: dot, count, full name (wraps to two
/// lines), chevron. Tap focuses the quadrant; tasks can be dropped onto it.
class _CollapsedQuadrantCard extends StatefulWidget {
  final int quadrant;
  final String title;
  final int count;
  final Color accent;
  final bool selecting;
  final bool enabled;
  final VoidCallback onTap;
  final ValueChanged<Task>? onDropTask;

  const _CollapsedQuadrantCard({
    super.key,
    required this.quadrant,
    required this.title,
    required this.count,
    required this.accent,
    required this.selecting,
    required this.enabled,
    required this.onTap,
    this.onDropTask,
  });

  @override
  State<_CollapsedQuadrantCard> createState() => _CollapsedQuadrantCardState();
}

class _CollapsedQuadrantCardState extends State<_CollapsedQuadrantCard> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final store = context.read<Store>();

    return DragTarget<Task>(
      onWillAcceptWithDetails:
          (details) =>
              widget.enabled &&
              !widget.selecting &&
              details.data.boardId == store.activeBoardId,
      onMove: (_) {
        if (!_hovering) setState(() => _hovering = true);
      },
      onLeave: (_) {
        if (_hovering) setState(() => _hovering = false);
      },
      onAcceptWithDetails: (details) {
        setState(() => _hovering = false);
        widget.onDropTask?.call(details.data);
      },
      builder: (context, candidate, _) {
        final isHovered = _hovering || candidate.isNotEmpty;
        final borderColor = isHovered
            ? widget.accent
            : (theme.brightness == Brightness.light
                  ? const Color(0xFFD5DAE1)
                  : theme.colorScheme.outlineVariant);
        final corner = BorderRadius.circular(8);
        final bgColor = isHovered
            ? widget.accent.withValues(alpha: 0.12)
            : theme.colorScheme.surface;

        // Loose height: while the rect collapses the content keeps its
        // natural size and is clipped by the region ClipRect instead of
        // overflowing a tight Column.
        return OverflowBox(
          minHeight: 0,
          maxHeight: double.infinity,
          alignment: Alignment.topLeft,
          child: Material(
          color: bgColor,
          borderRadius: corner,
          child: InkWell(
            borderRadius: corner,
            onTap: widget.onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: corner,
                border: Border.all(
                  color: borderColor,
                  width: isHovered ? 1.5 : 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: widget.accent,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '${widget.count}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: widget.accent,
                        ),
                      ),
                      const Spacer(),
                      Icon(
                        Icons.chevron_right,
                        size: 14,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.35,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    widget.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      height: 1.15,
                    ),
                  ),
                ],
              ),
            ),
          ),
          ),
        );
      },
    );
  }
}
