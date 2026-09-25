// Bench seams: in-memory prefs and a listener-only rebuild. Not product code.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/storage.dart';
import 'package:matrixflow_native/task_query.dart';
import 'package:matrixflow_native/widgets/quadrant_transition_layout.dart';
import 'package:matrixflow_native/widgets/task_card.dart';
import 'package:matrixflow_native/widgets/task_list_view.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Profile/release frame and memory bench for the matrix and list surfaces.
///
/// Synthetic tasks only. SharedPreferences is replaced with an in-memory
/// store before [Store.init], and reminders/credentials are in-memory fakes,
/// so this process does not read or write the user task profile.
///
/// Run from matrixflow-native with the pinned SDK:
///
/// flutter run -d windows --profile -t tool/os22_perf_bench.dart --no-pub
///
/// Set MATRIXFLOW_OS22_PERF_RESULT to the JSON output path. Debug-mode runs
/// still write a report, but the report marks them as not device frame data.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final timings = _Timings();
  WidgetsBinding.instance.addTimingsCallback(timings.add);
  runApp(_BenchApp(timings: timings));
}

class _BenchApp extends StatefulWidget {
  const _BenchApp({required this.timings});

  final _Timings timings;

  @override
  State<_BenchApp> createState() => _BenchAppState();
}

class _BenchAppState extends State<_BenchApp> {
  final _boundaryKey = GlobalKey();
  Widget _body = const ColoredBox(color: Color(0xFF101418));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_run());
    });
  }

  Future<void> _run() async {
    const fromDefine = String.fromEnvironment('OS22_OUT');
    final resultPath =
        Platform.environment['MATRIXFLOW_OS22_PERF_RESULT'] ??
        (fromDefine.isEmpty ? null : fromDefine);
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    final refreshHz = view.display.refreshRate;
    final report = <String, Object?>{
      'complete': false,
      'syntheticOnly': true,
      'prefs': 'in-memory SharedPreferences.setMockInitialValues',
      'credentials': 'memory',
      'reminders': 'NoopReminderService',
      'mode': <String, Object>{
        'debug': kDebugMode,
        'profile': kProfileMode,
        'release': kReleaseMode,
        'frameDataCredible': kProfileMode || kReleaseMode,
      },
      'device': <String, Object?>{
        'os': Platform.operatingSystem,
        'osVersion': Platform.operatingSystemVersion,
        'processors': Platform.numberOfProcessors,
        'refreshHz': refreshHz,
        'physicalSize': [view.physicalSize.width, view.physicalSize.height],
        'devicePixelRatio': view.devicePixelRatio,
      },
      'method':
          'Mounts production QuadrantTransitionLayout (grid) or TaskListView '
          '(list) in the default 1280x720 Windows runner window. '
          'Does not mount MatrixScreen chrome. '
          'Tasks are even across quadrants, titles only, no notes, deadlines, '
          'reminders, or subtasks. '
          'A 64-task grid warmup and a 200-task list warmup are discarded. '
          'Frame samples come from FrameTiming after that warmup.',
      'scenarios': <Object>[],
    };

    var exitCode = 0;
    try {
      for (final spec in const [
        _Spec('warmup-grid-64', 64, _Surface.grid, recorded: false),
        _Spec('warmup-list-200', 200, _Surface.list, recorded: false),
        _Spec('grid-1k', 1000, _Surface.grid),
        _Spec('list-1k', 1000, _Surface.list),
        _Spec('grid-10k', 10000, _Surface.grid),
        _Spec('list-10k', 10000, _Surface.list),
      ]) {
        await _scenario(report, resultPath, spec);
      }
      report['complete'] = true;
      _write(resultPath, report);
      debugPrint('OS22 perf bench complete');
    } catch (error, stackTrace) {
      exitCode = 1;
      report['complete'] = true;
      report['error'] = '$error\n$stackTrace';
      _write(resultPath, report);
      debugPrint('OS22 perf bench failed: $error');
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
    exit(exitCode);
  }

  Future<void> _scenario(
    Map<String, Object?> report,
    String? resultPath,
    _Spec spec,
  ) async {
    debugPrint('Measuring ${spec.name}');
    final timings = widget.timings;
    final scenario = <String, Object?>{
      'name': spec.name,
      'taskCount': spec.taskCount,
      'surface': spec.surface.name,
      'recorded': spec.recorded,
    };
    Store? store;
    try {
      final prepared = await _openStore(spec);
      store = prepared.store;
      scenario['generateMs'] = prepared.generateMs;
      scenario['initMs'] = prepared.initMs;
      scenario['flushMs'] = prepared.flushMs;
      scenario['taskBytesJson'] = prepared.taskBytes;
      scenario['query'] = _queryCpu(store);
      scenario['rssBeforeMount'] = _rss();

      timings.clear();
      final mountWatch = Stopwatch()..start();
      setState(() => _body = _surface(store!));
      await _waitForFrames(timings, quiet: const Duration(milliseconds: 350));
      mountWatch.stop();
      final mounted = _census();
      scenario['mount'] = <String, Object?>{
        'wallMs': mountWatch.elapsedMilliseconds,
        'timeToFirstFrameMs': timings.timeToFirstFrameMs,
        'frames': timings.summary(),
        'mountedTaskCards': mounted.taskCards,
        'mountedElements': mounted.elements,
        'bodySize': mounted.size,
        'rssAfter': _rss(),
      };

      timings.clear();
      final rebuildWatch = Stopwatch()..start();
      // Rebuild the production Store listeners without a task mutation.
      store.notifyListeners();
      await _waitForFrames(
        timings,
        quiet: const Duration(milliseconds: 200),
        cap: const Duration(seconds: 15),
      );
      rebuildWatch.stop();
      final rebuilt = _census();
      scenario['rebuild'] = <String, Object?>{
        'wallMs': rebuildWatch.elapsedMilliseconds,
        'timeToFirstFrameMs': timings.timeToFirstFrameMs,
        'frames': timings.summary(),
        'mountedTaskCards': rebuilt.taskCards,
        'mountedElements': rebuilt.elements,
        'rssAfter': _rss(),
      };

      scenario['scroll'] = await _scroll(store, timings);
      scenario['rssAfterScroll'] = _rss();
    } catch (error, stackTrace) {
      scenario['error'] = '$error\n$stackTrace';
    } finally {
      if (mounted) {
        setState(() => _body = const ColoredBox(color: Color(0xFF101418)));
      }
      await _nextFrame();
      store?.dispose();
      (report['scenarios'] as List<Object>).add(scenario);
      _write(resultPath, report);
    }
  }

  Future<_Prepared> _openStore(_Spec spec) async {
    final generate = Stopwatch()..start();
    final tasks = <Map<String, Object?>>[];
    for (var i = 0; i < spec.taskCount; i++) {
      tasks.add({
        'id': 'syn-${i.toString().padLeft(6, '0')}',
        'boardId': 'board-synth',
        'title': '合成任务 $i',
        'quadrant': allQuadrants[i % allQuadrants.length],
        'isLongTerm': false,
        'completed': false,
        'createdAt': 1700000000000 + i,
        'subtasks': const <Object>[],
        'urgencyMode': 'auto',
      });
    }
    final taskJson = jsonEncode(tasks);
    final settings = AppSettings(
      language: Language.zh,
      viewMode: spec.surface == _Surface.list ? ViewMode.list : ViewMode.grid,
      reduceMotion: false,
    );
    final backend = <String, Object>{
      'matrixflow-boards': jsonEncode([
        {'id': 'board-synth', 'name': '合成看板', 'createdAt': 1700000000000},
      ]),
      'matrixflow-tasks': taskJson,
      'matrixflow-settings': jsonEncode(settings.toJson()),
      'matrixflow-config': jsonEncode(
        AIConfig().toJson(includeCredential: false),
      ),
      'matrixflow-active-board': 'board-synth',
      'matrixflow-has-seen-onboarding': true,
    };
    generate.stop();
    SharedPreferences.setMockInitialValues(backend);
    final store = Store(
      deviceLocales: const [Locale('zh')],
      credentialStore: _MemoryCredentialStore(),
      reminders: NoopReminderService(),
    );
    final init = Stopwatch()..start();
    await store.init();
    init.stop();
    final flush = Stopwatch()..start();
    await store.flush();
    flush.stop();
    return _Prepared(
      store: store,
      generateMs: generate.elapsedMilliseconds,
      initMs: init.elapsedMilliseconds,
      flushMs: flush.elapsedMilliseconds,
      taskBytes: taskJson.length,
    );
  }

  Map<String, Object> _queryCpu(Store store) {
    int micros(void Function() body, int iterations) {
      final watch = Stopwatch()..start();
      for (var i = 0; i < iterations; i++) {
        body();
      }
      return watch.elapsedMicroseconds;
    }

    const iterations = 20;
    final tasksInUs = micros(() {
      for (final quadrant in allQuadrants) {
        store.tasksIn(quadrant);
      }
    }, iterations);
    final visibleUs = micros(() => store.visibleTasks, iterations);
    final missUs = micros(
      () => queryTasks(
        tasks: store.tasks,
        boards: store.boards,
        activeBoardId: store.activeBoardId,
        query: 'zzz-nomatch',
      ),
      iterations,
    );
    return {
      'label': 'dart-cpu-not-frame-time',
      'iterations': iterations,
      'tasksInAllQuadrantsMeanUs': tasksInUs / iterations,
      'visibleTasksMeanUs': visibleUs / iterations,
      'queryMissMeanUs': missUs / iterations,
    };
  }

  Widget _surface(Store store) {
    return ChangeNotifierProvider<Store>.value(
      value: store,
      child: specSurface(store),
    );
  }

  Widget specSurface(Store store) {
    final list = store.settings.viewMode == ViewMode.list;
    if (list) {
      return TaskListView(
        onQuadrantTap: (_) {},
        onEdit: (_) {},
        onEditSubtask: (_, __) {},
      );
    }
    return QuadrantTransitionLayout(
      focusedQuadrant: null,
      viewMode: ViewMode.grid,
      onFocusQuadrant: (_) {},
      onExitFocus: () {},
      onEdit: (_) {},
      onEditSubtask: (_, __) {},
    );
  }

  Future<Map<String, Object?>> _scroll(Store store, _Timings timings) async {
    final scrollables = _scrollables();
    final extents = [
      for (final state in scrollables)
        {
          'pixels': state.position.pixels,
          'maxScrollExtent': state.position.maxScrollExtent,
          'viewport': state.position.viewportDimension,
        },
    ];
    if (scrollables.isEmpty) {
      return {'scrollables': extents, 'skipped': 'no scrollable'};
    }
    final primary = scrollables.reduce(
      (a, b) =>
          a.position.maxScrollExtent >= b.position.maxScrollExtent ? a : b,
    );
    final position = primary.position;
    if (!position.hasContentDimensions || position.maxScrollExtent < 50) {
      return {'scrollables': extents, 'skipped': 'extent below 50'};
    }
    if (position.pixels != 0) {
      position.jumpTo(0);
      await _nextFrame();
    }
    final distance = math.min(2400.0, position.maxScrollExtent);
    final durationMs = math.max(400, (distance / 2400 * 1200).round());
    timings.clear();
    final watch = Stopwatch()..start();
    await position.animateTo(
      distance,
      duration: Duration(milliseconds: durationMs),
      curve: Curves.linear,
    );
    await _waitForFrames(
      timings,
      quiet: const Duration(milliseconds: 200),
      cap: const Duration(seconds: 8),
    );
    watch.stop();
    final census = _census();
    return {
      'scrollables': extents,
      'distance': distance,
      'durationMs': durationMs,
      'wallMs': watch.elapsedMilliseconds,
      'endPixels': position.pixels,
      'frames': timings.summary(),
      'mountedTaskCards': census.taskCards,
      'mountedElements': census.elements,
    };
  }

  List<ScrollableState> _scrollables() {
    final root = _boundaryKey.currentContext;
    if (root == null) return const [];
    final found = <ScrollableState>[];
    void walk(Element element) {
      if (element is StatefulElement && element.state is ScrollableState) {
        final state = element.state as ScrollableState;
        if (state.position.hasContentDimensions) found.add(state);
      }
      element.visitChildren(walk);
    }

    walk(root as Element);
    return found;
  }

  _Census _census() {
    final context = _boundaryKey.currentContext;
    if (context == null) {
      return const _Census(taskCards: -1, elements: -1, size: []);
    }
    var cards = 0;
    var elements = 0;
    void walk(Element element) {
      elements++;
      if (element.widget is TaskCard) cards++;
      element.visitChildren(walk);
    }

    walk(context as Element);
    final box = context.findRenderObject();
    final size = box is RenderBox && box.hasSize
        ? [box.size.width, box.size.height]
        : const <double>[];
    return _Census(taskCards: cards, elements: elements, size: size);
  }

  Future<void> _waitForFrames(
    _Timings timings, {
    Duration quiet = const Duration(milliseconds: 300),
    Duration cap = const Duration(seconds: 45),
  }) async {
    final started = DateTime.now();
    var lastCount = timings.count;
    var lastChange = DateTime.now();
    while (true) {
      await Future<void>.delayed(const Duration(milliseconds: 40));
      if (timings.count != lastCount) {
        lastCount = timings.count;
        lastChange = DateTime.now();
      }
      final now = DateTime.now();
      if (timings.count > 0 && now.difference(lastChange) >= quiet) return;
      if (now.difference(started) >= cap) return;
    }
  }

  Future<void> _nextFrame() {
    final completer = Completer<void>();
    WidgetsBinding.instance.addPostFrameCallback((_) => completer.complete());
    WidgetsBinding.instance.scheduleFrame();
    return completer.future;
  }

  Map<String, Object?> _rss() {
    try {
      return {
        'currentRss': ProcessInfo.currentRss,
        'maxRss': ProcessInfo.maxRss,
      };
    } catch (error) {
      return {'error': error.toString()};
    }
  }

  void _write(String? path, Map<String, Object?> report) {
    if (path == null || path.isEmpty) return;
    final file = File(path);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
      home: Scaffold(
        body: KeyedSubtree(key: _boundaryKey, child: _body),
      ),
    );
  }
}

enum _Surface { grid, list }

class _Spec {
  const _Spec(this.name, this.taskCount, this.surface, {this.recorded = true});

  final String name;
  final int taskCount;
  final _Surface surface;
  final bool recorded;
}

class _Prepared {
  const _Prepared({
    required this.store,
    required this.generateMs,
    required this.initMs,
    required this.flushMs,
    required this.taskBytes,
  });

  final Store store;
  final int generateMs;
  final int initMs;
  final int flushMs;
  final int taskBytes;
}

class _Census {
  const _Census({
    required this.taskCards,
    required this.elements,
    required this.size,
  });

  final int taskCards;
  final int elements;
  final List<double> size;
}

class _MemoryCredentialStore implements CredentialStore {
  @override
  Future<void> delete() async {}

  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String value) async {}
}

class _Timings {
  final List<FrameTiming> frames = [];
  int? _firstMicros;

  void add(List<FrameTiming> batch) {
    _firstMicros ??= DateTime.now().microsecondsSinceEpoch;
    frames.addAll(batch);
  }

  void clear() {
    frames.clear();
    _firstMicros = null;
    _clearedAt = DateTime.now().microsecondsSinceEpoch;
  }

  int _clearedAt = DateTime.now().microsecondsSinceEpoch;

  int get count => frames.length;

  int? get timeToFirstFrameMs {
    final first = _firstMicros;
    if (first == null) return null;
    return ((first - _clearedAt) / 1000).round();
  }

  Map<String, Object> summary() {
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    final refresh = view.display.refreshRate;
    final budgetUs = refresh > 1 ? (1000000 / refresh).round() : 16667;
    final first = frames.isEmpty ? null : frames.first;
    return {
      'count': frames.length,
      'refreshHz': refresh,
      'budgetUs': budgetUs,
      if (first != null)
        'first': {
          'buildUs': first.buildDuration.inMicroseconds,
          'rasterUs': first.rasterDuration.inMicroseconds,
          'totalUs': first.totalSpan.inMicroseconds,
        },
      'build': _dist(frames.map((frame) => frame.buildDuration.inMicroseconds)),
      'raster': _dist(
        frames.map((frame) => frame.rasterDuration.inMicroseconds),
      ),
      'total': _dist(frames.map((frame) => frame.totalSpan.inMicroseconds)),
      'overBudget': frames
          .where((frame) => frame.totalSpan.inMicroseconds > budgetUs)
          .length,
      'buildOverBudget': frames
          .where((frame) => frame.buildDuration.inMicroseconds > budgetUs)
          .length,
      'rasterOverBudget': frames
          .where((frame) => frame.rasterDuration.inMicroseconds > budgetUs)
          .length,
    };
  }
}

Map<String, Object> _dist(Iterable<int> values) {
  final list = values.toList()..sort();
  if (list.isEmpty) {
    return {'count': 0};
  }
  final sum = list.fold<int>(0, (total, value) => total + value);
  int at(double percentile) => list[((list.length - 1) * percentile).round()];
  return {
    'count': list.length,
    'meanUs': sum / list.length,
    'p50Us': at(0.50),
    'p90Us': at(0.90),
    'p99Us': at(0.99),
    'maxUs': list.last,
  };
}
