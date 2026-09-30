import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../import_preview/draft_model.dart';
import '../import_preview/draft_preview.dart';
import '../storage.dart';
import 'screenshot_backend.dart';
import 'screenshot_submission.dart';

class ScreenshotImportPage extends StatefulWidget {
  const ScreenshotImportPage({super.key, this.backend});
  final ScreenshotBackend? backend;
  @override
  State<ScreenshotImportPage> createState() => _ScreenshotImportPageState();
}

class _ScreenshotImportPageState extends State<ScreenshotImportPage> {
  late final ScreenshotBackend _backend =
      widget.backend ?? LocalScreenshotBackend();
  DraftBatch? _batch;
  ScreenshotSubmission? _submission;
  String? _problem;
  bool _checking = true, _processing = false, _saving = false;
  int _done = 0, _total = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_check());
  }

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _problem = null;
    });
    String? problem;
    try {
      problem = await _backend.availability();
    } catch (_) {
      problem = 'Unavailable';
    }
    if (mounted) {
      setState(() {
        _checking = false;
        _problem = problem == null ? null : 'screenshotImport$problem';
      });
    }
  }

  @override
  void dispose() {
    _submission?.cancel();
    unawaited(_backend.dispose().catchError((Object _) {}));
    super.dispose();
  }

  void _cancel() {
    if (_saving) return;
    _submission?.cancel();
    _backend.cancel();
    Navigator.of(context).pop();
  }

  Future<void> _choose() async {
    if (_processing || _checking || _problem != null) return;
    setState(() {
      _processing = true;
      _done = 0;
      _total = 0;
    });
    try {
      final result = await _backend.capture((done, total) {
        if (mounted) {
          setState(() {
            _done = done;
            _total = total;
          });
        }
      });
      if (!mounted) return;
      final t = context.read<Store>().t;
      setState(() {
        _processing = false;
        if (result.error != null) {
          _problem = _failureKey(result.error!);
        } else if (!result.cancelled && result.batch != null) {
          final source = result.batch!;
          _batch =
              DraftBatch(
                  images: [
                    for (final image in source.images)
                      DraftImage(
                        id: image.id,
                        width: image.width,
                        height: image.height,
                        engine: image.engine,
                        tasks: image.tasks,
                        notes: image.notes,
                        error: image.error == null
                            ? null
                            : t[_failureKey(image.error!)],
                      )..skipped = image.skipped,
                  ],
                  duplicates: source.duplicates,
                )
                ..boardId =
                    source.boardId ?? context.read<Store>().activeBoardId
                ..quadrant = source.quadrant;
          _submission = ScreenshotSubmission(_batch!);
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _processing = false;
          _problem = 'screenshotImportCleanupFailed';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<Store>();
    final t = store.t;
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(
          title: Text(t['screenshotImportTitle']!),
          automaticallyImplyLeading: !_saving,
        ),
        body: SafeArea(
          child: _batch != null
              ? DraftPreview(
                  batch: _batch!,
                  language: store.settings.language,
                  boards: [
                    for (final board in store.boards)
                      ImportBoardChoice(board.id, board.name),
                  ],
                  onCancel: _cancel,
                  onSubmit: (submitted) async {
                    setState(() => _saving = true);
                    try {
                      await _submission!.commit(store, submitted);
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            t['screenshotImportSuccess']!.replaceAll(
                              '{count}',
                              '${submitted.tasks.length}',
                            ),
                          ),
                        ),
                      );
                      Navigator.of(context).pop();
                    } finally {
                      if (mounted) setState(() => _saving = false);
                    }
                  },
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(t['screenshotImportHint']!),
                      const SizedBox(height: 20),
                      if (_checking || _processing) ...[
                        const LinearProgressIndicator(),
                        const SizedBox(height: 12),
                        Text(
                          _checking
                              ? t['screenshotImportChecking']!
                              : t['screenshotImportProgress']!
                                    .replaceAll('{done}', '$_done')
                                    .replaceAll('{total}', '$_total'),
                        ),
                      ],
                      if (_problem != null)
                        Text(
                          t[_problem] ?? t['screenshotImportReadFailed']!,
                          key: const ValueKey('screenshot-problem'),
                        ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        key: const ValueKey('screenshot-choose'),
                        onPressed: _checking || _processing || _problem != null
                            ? null
                            : _choose,
                        icon: const Icon(Icons.add_photo_alternate_outlined),
                        label: Text(t['screenshotImportChoose']!),
                      ),
                      if (_problem != null)
                        TextButton(
                          key: const ValueKey('screenshot-retry'),
                          onPressed: _checking || _processing ? null : _check,
                          child: Text(t['screenshotImportRetry']!),
                        ),
                      TextButton(
                        key: const ValueKey('screenshot-cancel'),
                        onPressed: _cancel,
                        child: Text(t['cancel']!),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

String _failureKey(String message) {
  if (message.startsWith('screenshotImport')) return message;
  if (message.contains('model')) return 'screenshotImportModelsMissing';
  if (message.contains('runtime')) return 'screenshotImportNativeMissing';
  if (message.contains('16 MiB')) return 'screenshotImportSafFileLimit';
  if (message.contains('48 MiB')) return 'screenshotImportSafBatchLimit';
  if (message.contains('24 Mi-pixel')) return 'screenshotImportSafPixelLimit';
  if (message.contains('10 PNG')) return 'screenshotImportSafCountLimit';
  if (message.contains('PNG') || message.contains('format')) {
    return 'screenshotImportSafPng';
  }
  return 'screenshotImportReadFailed';
}
