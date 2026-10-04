/// WP19-R prototype screen: the same synthetic project data shown twice — once
/// the way the product organises it today, once through a development lens.
///
/// Every control here mutates [DevExperiment] in memory. There is no Store, no
/// persistence, no settings write and no reminder; that is the point of the
/// session line at the top of the screen.
library;

import 'package:flutter/material.dart';

import '../../models.dart';
import '../../theme.dart';
import 'wp19_dev_data.dart';
import 'wp19_dev_labels.dart';
import 'wp19_dev_model.dart';

enum _ViewMode { normal, dev }

class Wp19DevModeApp extends StatefulWidget {
  final TargetPlatform? platform;

  const Wp19DevModeApp({super.key, this.platform});

  @override
  State<Wp19DevModeApp> createState() => _Wp19DevModeAppState();
}

class _Wp19DevModeAppState extends State<Wp19DevModeApp> {
  DevExperiment _session = buildWp19Session().toExperiment();

  _ViewMode _mode = _ViewMode.dev;
  bool _dark = false;
  bool _largeText = false;
  String? _boardFilter;
  final Set<DevPhase?> _phaseFilter = {};
  final Set<String> _selection = {};
  final Set<String> _expanded = {};
  String _status = '';

  int _leftIntents = 0;
  int _leftTouched = 0;
  bool _left = false;

  static const List<(int, String)> _quadrantLabels = [
    (qDo, '重要且紧急'),
    (qPlan, '重要不紧急'),
    (qDelegate, '紧急不重要'),
    (qEliminate, '不重要不紧急'),
  ];

  String _phaseLabel(DevPhase? phase) => switch (phase) {
    DevPhase.design => Wp19Labels.phaseDesign,
    DevPhase.build => Wp19Labels.phaseBuild,
    DevPhase.verify => Wp19Labels.phaseVerify,
    DevPhase.ship => Wp19Labels.phaseShip,
    null => Wp19Labels.phaseNone,
  };

  Iterable<DevTaskView> get _visible => _session.tasks.where(
    (view) => _boardFilter == null || view.source.boardId == _boardFilter,
  );

  bool _matchesPhase(DevTaskView view) =>
      _phaseFilter.isEmpty || _phaseFilter.contains(view.phase);

  void _record(String message) => setState(() => _status = message);

  void _toggleComplete(String id) {
    _session.toggleComplete(id);
    _record('已记录 1 条意图，产品库未写入');
  }

  void _undo() {
    if (!_session.undoLast()) {
      _record(Wp19Labels.nothingToUndo);
      return;
    }
    _selection.removeWhere((id) => _session.view(id) == null);
    _expanded.removeWhere((id) => _session.view(id) == null);
    _record('已撤销 1 步');
  }

  void _batchComplete(BuildContext context) {
    final ids = _selection.toList()..sort();
    if (ids.isEmpty) {
      _record(Wp19Labels.batchNeedsSelection);
      return;
    }
    final unlocked = _session.unlockedBy(ids);
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(Wp19Labels.batchComplete),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('选中 ${ids.length} ${Wp19Labels.countSuffix}'),
              const SizedBox(height: 4),
              Text(
                unlocked.isEmpty
                    ? '本批不会解锁其他任务'
                    : '${Wp19Labels.unlocks} ${unlocked.length} ${Wp19Labels.countSuffix}：'
                        '${_titlesOf(unlocked)}',
              ),
              const SizedBox(height: 8),
              const Text('批量操作记为一条意图，撤销一次即整批回退。'),
            ],
          ),
        ),
        actions: [
          TextButton(
            key: const Key('wp19r-batch-cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text(Wp19Labels.leaveCancel),
          ),
          FilledButton(
            key: const Key('wp19r-batch-confirm'),
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _session.completeBatch(ids);
              setState(_selection.clear);
              _record('批量完成记为 1 条意图');
            },
            child: const Text(Wp19Labels.batchComplete),
          ),
        ],
      ),
    );
  }

  String _titlesOf(List<String> ids) => [
    for (final id in ids)
      _session.view(id)?.source.title ?? id,
  ].join('、');

  Future<void> _export(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(Wp19Labels.exportTitle),
        content: SizedBox(
          width: 520,
          height: 360,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                Wp19Labels.exportNote,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Expanded(
                child: SingleChildScrollView(
                  child: SelectableText(
                    _session.exportJson(),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            key: const Key('wp19r-export-close'),
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text(Wp19Labels.close),
          ),
        ],
      ),
    );
  }

  void _leave(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(Wp19Labels.leaveTitle),
        content: Text(
          '${Wp19Labels.leaveBody}\n\n'
          '将丢弃：意图 ${_session.intentCount} 条 · 触及任务 '
          '${_session.touchedTaskCount} 个',
        ),
        actions: [
          TextButton(
            key: const Key('wp19r-leave-cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text(Wp19Labels.leaveCancel),
          ),
          FilledButton(
            key: const Key('wp19r-leave-confirm'),
            onPressed: () {
              Navigator.of(dialogContext).pop();
              setState(() {
                _leftIntents = _session.intentCount;
                _leftTouched = _session.touchedTaskCount;
                _left = true;
                _selection.clear();
                _status = '';
              });
            },
            child: const Text(Wp19Labels.leaveConfirm),
          ),
        ],
      ),
    );
  }

  void _reload() => setState(() {
    _session = buildWp19Session().toExperiment();
    _phaseFilter.clear();
    _selection.clear();
    _expanded.clear();
    _boardFilter = null;
    _left = false;
    _status = '已重新载入同一份合成数据';
  });

  @override
  Widget build(BuildContext context) {
    final platform = widget.platform ?? TargetPlatform.android;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: Wp19Labels.appTitle,
      theme: buildTheme(Brightness.light, ThemeColor.blue, platform: platform),
      darkTheme: buildTheme(Brightness.dark, ThemeColor.blue, platform: platform),
      themeMode: _dark ? ThemeMode.dark : ThemeMode.light,
      home: Builder(builder: _scaffold),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(_largeText ? 2.0 : 1.0)),
        child: child!,
      ),
    );
  }

  /// [context] here is below [MaterialApp], so the dialogs this screen opens
  /// find their Navigator and MaterialLocalizations.
  Widget _scaffold(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          Wp19Labels.appTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            key: const Key('wp19r-export'),
            tooltip: Wp19Labels.exportState,
            onPressed: _left ? null : () => _export(context),
            icon: const Icon(Icons.download),
          ),
          IconButton(
            key: const Key('wp19r-leave'),
            tooltip: Wp19Labels.leaveExperiment,
            onPressed: _left ? null : () => _leave(context),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: _left ? _closed() : _working(context),
    );
  }

  Widget _closed() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle_outline, size: 40),
            const SizedBox(height: 12),
            Text(
              Wp19Labels.leftReceipt,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              '${Wp19Labels.leftDetail}\n'
              '丢弃意图 $_leftIntents 条 · 触及任务 $_leftTouched 个 · '
              '${Wp19Labels.libraryWrites} 0 次',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const Key('wp19r-reload'),
              onPressed: _reload,
              icon: const Icon(Icons.refresh),
              label: const Text(Wp19Labels.restartSession),
            ),
          ],
        ),
      ),
    );
  }

  Widget _working(BuildContext context) {
    // One scrollable page: the control block and the rows scroll together, so
    // 200% text on a 360 dp screen never has to fit a fixed header.
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(),
                _note(),
                ..._groups(context),
              ],
            ),
          ),
        ),
        if (_selection.isNotEmpty) _batchBar(context),
      ],
    );
  }

  DevBlockReason readinessOf(DevTaskView view) =>
      _session.readiness(view).reason;

  Widget _note() {
    final blockedCount = _session.openTasks
        .where((view) => readinessOf(view) != DevBlockReason.ready)
        .length;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Text(
        _mode == _ViewMode.dev
            ? Wp19Labels.devNote
            : '${Wp19Labels.normalNote}\n'
              '${Wp19Labels.hiddenBlockedHint}：$blockedCount '
              '${Wp19Labels.countSuffix}',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }

  Widget _header() {
    final theme = Theme.of(context);
    return Material(
      type: MaterialType.card,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(Wp19Labels.appSubtitle, style: theme.textTheme.labelLarge),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SegmentedButton<_ViewMode>(
                  key: const Key('wp19r-mode'),
                  segments: const [
                    ButtonSegment(
                      value: _ViewMode.normal,
                      label: Text(Wp19Labels.modeNormal),
                    ),
                    ButtonSegment(
                      value: _ViewMode.dev,
                      label: Text(Wp19Labels.modeDev),
                    ),
                  ],
                  selected: {_mode},
                  showSelectedIcon: false,
                  onSelectionChanged: (selection) =>
                      setState(() => _mode = selection.first),
                ),
                IconButton(
                  key: const Key('wp19r-theme'),
                  tooltip: Wp19Labels.themeToggle,
                  isSelected: _dark,
                  onPressed: () => setState(() => _dark = !_dark),
                  icon: Icon(_dark ? Icons.dark_mode : Icons.light_mode),
                ),
                IconButton(
                  key: const Key('wp19r-font'),
                  tooltip: Wp19Labels.fontToggle,
                  isSelected: _largeText,
                  onPressed: () => setState(() => _largeText = !_largeText),
                  icon: const Icon(Icons.text_fields),
                ),
                OutlinedButton.icon(
                  key: const Key('wp19r-undo'),
                  onPressed: _undo,
                  icon: const Icon(Icons.undo),
                  label: const Text(Wp19Labels.undoLast),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                FilterChip(
                  label: const Text(Wp19Labels.allProjects),
                  selected: _boardFilter == null,
                  onSelected: (_) => setState(() => _boardFilter = null),
                ),
                for (final board in _session.boards)
                  FilterChip(
                    key: Key('wp19r-board-${board.id}'),
                    label: Text(board.name),
                    selected: _boardFilter == board.id,
                    onSelected: (selected) => setState(
                      () => _boardFilter = selected ? board.id : null,
                    ),
                  ),
              ],
            ),
            if (_mode == _ViewMode.dev) ...[
              const SizedBox(height: 6),
              // The phase row is fixed rather than derived, so switching
              // project never makes the chips jump under a keyboard.
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final phase in <DevPhase?>[...devPhaseOrder, null])
                    FilterChip(
                      key: Key('wp19r-phase-${phase?.name ?? 'none'}'),
                      label: Text(_phaseLabel(phase)),
                      selected: _phaseFilter.contains(phase),
                      onSelected: (selected) => setState(() {
                        if (selected) {
                          _phaseFilter.add(phase);
                        } else {
                          _phaseFilter.remove(phase);
                        }
                      }),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Text(
              '${Wp19Labels.sessionLine}：${Wp19Labels.intentsOf} '
              '${_session.intentCount} · ${Wp19Labels.touchedOf} '
              '${_session.touchedTaskCount} · ${Wp19Labels.libraryWrites} 0',
              style: theme.textTheme.bodySmall,
            ),
            if (_status.isNotEmpty)
              Text(_status, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  /// The session is 13 synthetic tasks, so rows are built eagerly: every one
  /// is mounted for keyboard traversal and for the rendered screenshots.
  /// Promoting dev mode would need the product's virtualized list instead.
  List<Widget> _groups(BuildContext context) {
    if (_mode == _ViewMode.normal) {
      final views = _visible.toList();
      if (views.isEmpty) return [_emptyNotice()];
      return [
        for (final (quadrant, label) in _quadrantLabels) ...[
          _groupHeader(
            label,
            _normalSummary(
              views.where((view) => view.source.quadrant == quadrant).toList(),
            ),
          ),
          for (final view in views.where(
            (view) => view.source.quadrant == quadrant,
          ))
            _normalRow(view),
        ],
      ];
    }

    final rows = _visible.where(_matchesPhase).toList();
    if (rows.isEmpty) return [_emptyNotice()];
    final phases = <DevPhase?>[
      for (final phase in _session.phasesPresent(boardId: _boardFilter))
        if (_phaseFilter.isEmpty || _phaseFilter.contains(phase)) phase,
    ];
    return [
      for (final phase in phases) ...[
        _groupHeader(
          _phaseLabel(phase),
          _devSummary(rows.where((view) => view.phase == phase).toList()),
        ),
        for (final view in rows.where((view) => view.phase == phase))
          _devRow(context, view),
      ],
    ];
  }

  Widget _emptyNotice() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Text(Wp19Labels.emptyList, textAlign: TextAlign.center),
    );
  }

  String _devSummary(List<DevTaskView> views) {
    var ready = 0, waiting = 0, done = 0;
    for (final view in views) {
      switch (readinessOf(view)) {
        case DevBlockReason.ready:
          ready++;
        case DevBlockReason.done:
          done++;
        case DevBlockReason.inCycle:
        case DevBlockReason.waitingOnBlockers:
          waiting++;
      }
    }
    return '可开始 $ready · 等待 $waiting · 完成 $done';
  }

  String _normalSummary(List<DevTaskView> views) =>
      '共 ${views.length} · 完成 ${views.where((view) => view.done).length}';

  Widget _groupHeader(String title, String detail) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          Text(detail, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }

  Widget _normalRow(DevTaskView view) {
    final source = view.source;
    return Card(
      key: Key('wp19r-row-${source.id}'),
      margin: const EdgeInsets.only(bottom: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              key: Key('wp19r-normal-toggle-${source.id}'),
              value: view.done,
              onChanged: (_) => _toggleComplete(source.id),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    source.title,
                    style: TextStyle(
                      decoration: view.done ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final tag in source.tags) _chip(tag),
                      if (source.hasSubtasks)
                        _chip(
                          '${source.subtasks.length} ${Wp19Labels.subtasksOf}',
                        ),
                      if (source.deadline != null)
                        _chip('${Wp19Labels.deadline} ${_day(source.deadline!)}'),
                      if (source.plannedDate != null)
                        _chip('${Wp19Labels.planned} ${_day(source.plannedDate!)}'),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _devRow(BuildContext context, DevTaskView view) {
    final readiness = _session.readiness(view);
    final unlocked = _session.unlockedBy([view.id]);
    final source = view.source;
    return Card(
      key: Key('wp19r-row-${source.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 8, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  key: Key('wp19r-select-${source.id}'),
                  value: _selection.contains(source.id),
                  onChanged: view.done
                      ? null
                      : (checked) => setState(() {
                        if (checked == true) {
                          _selection.add(source.id);
                        } else {
                          _selection.remove(source.id);
                        }
                      }),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        source.title,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          decoration: view.done
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          _statusBadge(readiness),
                          if (readiness.unresolved.isNotEmpty)
                            _chip(Wp19Labels.unresolvedBlocker, warn: true),
                        ],
                      ),
                      if (readiness.reason == DevBlockReason.waitingOnBlockers ||
                          readiness.reason == DevBlockReason.inCycle)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '${Wp19Labels.waitingPrefix}：${_titlesOf(readiness.waitingOn)}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          view.acceptance == null
                              ? Wp19Labels.noAcceptance
                              : '${Wp19Labels.acceptance}：${view.acceptance}',
                          style: TextStyle(
                            color: view.acceptance == null
                                ? Theme.of(context).hintColor
                                : null,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      if (unlocked.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '${Wp19Labels.unlocks} ${unlocked.length} '
                            '${Wp19Labels.countSuffix}：${_titlesOf(unlocked)}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                OutlinedButton.icon(
                  key: Key('wp19r-toggle-${source.id}'),
                  onPressed: () => _toggleComplete(source.id),
                  icon: Icon(
                    view.done ? Icons.undo : Icons.check_circle_outline,
                    size: 18,
                  ),
                  label: Text(view.done ? Wp19Labels.restore : Wp19Labels.complete),
                ),
                OutlinedButton.icon(
                  key: Key('wp19r-more-${source.id}'),
                  onPressed: () => setState(() {
                    if (!_expanded.add(source.id)) _expanded.remove(source.id);
                  }),
                  icon: Icon(
                    _expanded.contains(source.id)
                        ? Icons.expand_less
                        : Icons.expand_more,
                    size: 18,
                  ),
                  label: const Text(Wp19Labels.moreActions),
                ),
              ],
            ),
            // Inline rather than an overlay menu: the destructive actions stay
            // reachable by keyboard and cannot outlive the row they anchor to.
            if (_expanded.contains(source.id))
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      Wp19Labels.removeHint,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        OutlinedButton(
                          key: Key('wp19r-reset-${source.id}'),
                          onPressed: () {
                            _session.resetFields(source.id);
                            _record('已清除该任务的实验字段');
                          },
                          child: const Text(Wp19Labels.resetFields),
                        ),
                        OutlinedButton(
                          key: Key('wp19r-remove-${source.id}'),
                          onPressed: () {
                            _session.removeTask(source.id);
                            _selection.remove(source.id);
                            _expanded.remove(source.id);
                            _record('已从原型会话移除该任务');
                          },
                          child: const Text(Wp19Labels.removeTask),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _statusBadge(DevReadiness readiness) {
    final (label, color) = switch (readiness.reason) {
      DevBlockReason.ready => (
        Wp19Labels.ready,
        Theme.of(context).colorScheme.primary,
      ),
      DevBlockReason.done => (Wp19Labels.done, Theme.of(context).hintColor),
      DevBlockReason.inCycle => (
        Wp19Labels.cycle,
        Theme.of(context).colorScheme.error,
      ),
      DevBlockReason.waitingOnBlockers => (
        '${Wp19Labels.waitingPrefix} ${readiness.waitingOn.length}',
        Theme.of(context).colorScheme.error,
      ),
    };
    return _chip(label, color: color);
  }

  Widget _chip(String text, {bool warn = false, Color? color}) {
    final theme = Theme.of(context);
    final tint = warn ? theme.colorScheme.error : color;
    final fillAlpha = theme.brightness == Brightness.dark ? 0.22 : 0.12;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: tint?.withValues(alpha: fillAlpha),
        border: Border.all(color: tint ?? theme.dividerColor),
      ),
      child: Text(text, style: theme.textTheme.bodySmall),
    );
  }

  Widget _batchBar(BuildContext context) {
    return Material(
      type: MaterialType.card,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              '${Wp19Labels.selectedCount} ${_selection.length} '
              '${Wp19Labels.countSuffix}',
            ),
            FilledButton(
              key: const Key('wp19r-batch'),
              onPressed: () => _batchComplete(context),
              child: const Text(Wp19Labels.batchComplete),
            ),
            TextButton(
              key: const Key('wp19r-clear-selection'),
              onPressed: () => setState(_selection.clear),
              child: const Text(Wp19Labels.clearSelection),
            ),
          ],
        ),
      ),
    );
  }

  String _day(int epochMs) {
    final date = DateTime.fromMillisecondsSinceEpoch(epochMs);
    return '${date.month}/${date.day}';
  }
}
