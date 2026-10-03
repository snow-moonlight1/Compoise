// Opt-in standalone Flutter process. Uses real PNG decoding/native OCR and the
// production DraftPreview. Selection is an explicit file seam; no picker claim.
// Confirmation is a harness action; submit uses the production Store protocol
// inside an explicitly checked fresh XDG application-data directory.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:matrixflow_native/import_preview/draft_model.dart';
import 'package:matrixflow_native/import_preview/draft_preview.dart';
import 'package:matrixflow_native/ocr/ocr_runtime.dart';
import 'package:matrixflow_native/screenshot_import/screenshot_capture.dart';
import 'package:matrixflow_native/screenshot_import/screenshot_submission.dart';
import 'package:matrixflow_native/storage.dart';

class _BenchmarkCredentials implements CredentialStore {
  @override
  Future<String?> read() async => null;
  @override
  Future<void> delete() async {}
  @override
  Future<void> write(String value) async =>
      throw StateError('No benchmark credentials');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final env = Platform.environment;
  final root = env['WP17_Q1_REPO']!;
  final report = File(env['WP17_Q1_REPORT']!);
  final records = <Map<String, Object?>>[];
  final watch = Stopwatch()..start();
  var samples = 0;
  final sampledPeaks = <String, int>{};
  Map<String, int?> memory() {
    final result = <String, int?>{
      'rss_kib': null,
      'hwm_kib': null,
      'pss_kib': null,
    };
    if (Platform.isLinux) {
      for (final line in File('/proc/$pid/status').readAsLinesSync()) {
        if (line.startsWith('VmRSS:')) {
          result['rss_kib'] = int.parse(line.trim().split(RegExp(r'\s+'))[1]);
        }
        if (line.startsWith('VmHWM:')) {
          result['hwm_kib'] = int.parse(line.trim().split(RegExp(r'\s+'))[1]);
        }
      }
      for (final line in File('/proc/$pid/smaps_rollup').readAsLinesSync()) {
        if (line.startsWith('Pss:')) {
          result['pss_kib'] = int.parse(line.trim().split(RegExp(r'\s+'))[1]);
        }
      }
    }
    return result;
  }

  void event(String phase, [Map<String, Object?> fields = const {}]) {
    records.add({
      'phase': phase,
      'pid': pid,
      'elapsed_ms': watch.elapsedMilliseconds,
      ...memory(),
      ...fields,
    });
  }

  Future<void> show(Widget child) async {
    runApp(MaterialApp(home: Scaffold(body: child)));
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }

  final timer = Timer.periodic(const Duration(milliseconds: 20), (_) {
    samples++;
    for (final entry in memory().entries) {
      if (entry.value != null &&
          entry.value! > (sampledPeaks[entry.key] ?? 0)) {
        sampledPeaks[entry.key] = entry.value!;
      }
    }
  });
  var code = 0;
  Store? activeStore;
  final quality = <Map<String, Object?>>[];
  try {
    await show(const Text('WP17 Q1 synthetic benchmark'));
    final sandbox = env['XDG_DATA_HOME'];
    final support = await getApplicationSupportDirectory();
    if (sandbox == null || !support.path.startsWith('$sandbox/')) {
      throw StateError('Fresh dedicated XDG application directory required');
    }
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getKeys().isNotEmpty) {
      throw StateError('Benchmark storage is not fresh');
    }
    final store = Store(credentialStore: _BenchmarkCredentials());
    activeStore = store;
    await store.init();
    final board = store.boards.first;
    event('idle');
    final runtime = OcrRuntime(
      assetsRoot: env['WP17_Q1_ASSETS']!,
      libraryPath: env['WP17_Q1_LIBRARY']!,
    );
    var image = 0;
    ScreenshotCapture newCapture({void Function()? onNativeStart}) =>
        ScreenshotCapture.withRecognizer(
          recognize: (path, token) async {
            event('decoded-before-ocr', {'image': image++});
            onNativeStart?.call();
            final raw = (await runtime.recognizeFiles([
              path,
            ], cancellation: token)).single;
            event('after-ocr', {'lines': raw.lines.length});
            return raw;
          },
        );
    PlatformFile picked(File file) => PlatformFile(
      name: file.uri.pathSegments.last,
      path: file.path,
      size: file.lengthSync(),
    );
    final specs =
        jsonDecode(
              File('$root/native/ocr/tools/q1_cases.json').readAsStringSync(),
            )
            as Map;
    final files = [
      for (final id in specs['batch'] as List)
        picked(File('$root/docs/evidence/wp17r2/samples/images/$id.png')),
    ];
    if (files.length != 10) throw StateError('expected ten inputs');
    final capture = newCapture();
    final onlyLimits = env['WP17_Q1_ONLY_LIMITS'] == 'true';
    final batchCount = onlyLimits
        ? 0
        : int.parse(env['WP17_Q1_BATCHES'] ?? '5');
    if ((!onlyLimits && batchCount < 1) || batchCount > 50) {
      throw StateError('Use 1..50 benchmark batches');
    }
    for (var batchIndex = 0; batchIndex < batchCount; batchIndex++) {
      event('selected', {'batch': batchIndex, 'images': files.length});
      final started = watch.elapsedMilliseconds;
      var result = await capture.captureFiles(files);
      var batch = result.batch!;
      final submission = ScreenshotSubmission(batch);
      final tasksBefore = store.tasks.length;
      if (batch.images.any((i) => i.failed) || batch.canSubmit) {
        throw StateError('all images must produce unconfirmed drafts');
      }
      event('draft', {
        'batch': batchIndex,
        'duration_ms': watch.elapsedMilliseconds - started,
        'tasks': batch.activeTasks.length,
        'duplicates': batch.duplicates.length,
      });
      await show(
        DraftPreview(
          batch: batch,
          boards: [ImportBoardChoice(board.id, 'Synthetic')],
          onSubmit: (snapshot) => submission.commit(store, snapshot),
          onCancel: () {},
        ),
      );
      event('review', {'batch': batchIndex});
      // Keep all drafts through review; release only at the actual workflow
      // boundary. Confirmed submit uses the production snapshot validation.
      if (batchIndex.isOdd) {
        batch.boardId = board.id;
        batch.quadrant = 1;
        for (final task in batch.activeTasks) {
          task.confirmed = true;
        }
        for (final hint in batch.duplicates) {
          hint.acknowledged = true;
        }
        final submitted = batch.snapshot();
        await submission.commit(store, submitted);
        await store.flush();
        if (store.tasks.length !=
            tasksBefore +
                submitted.tasks.where((t) => t.parentId == null).length) {
          throw StateError('Confirmed Store import count changed');
        }
        event('submit-callback', {'tasks': submitted.tasks.length});
      } else {
        capture.cancel();
        submission.cancel();
        if (store.tasks.length != tasksBefore) {
          throw StateError('Cancelled review wrote tasks');
        }
        event('review-cancel', {'batch': batchIndex});
      }
      await show(const Text('Batch released'));
      result = const ScreenshotCaptureResult();
      batch = DraftBatch(images: []);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      event('released', {'batch': batchIndex});
    }
    capture.dispose();
    final limits = env['WP17_Q1_LIMITS'];
    if (onlyLimits && limits == null) {
      throw StateError('Limits directory required');
    }
    if (limits != null) {
      final cases = {
        'near-pixel-cap': [
          'max-pixels',
          'near-max-pixels',
          ...List.filled(8, 'tiny'),
        ],
        'near-byte-cap': [
          ...List.filled(3, 'near-max-bytes'),
          ...List.filled(7, 'tiny'),
        ],
      };
      for (final entry in cases.entries) {
        final inputs = [
          for (final name in entry.value) picked(File('$limits/$name.png')),
        ];
        var pixels = 0;
        final bytes = inputs.fold<int>(0, (n, f) => n + f.size);
        for (final input in inputs) {
          final handle = await File(input.path!).open();
          try {
            final header = ByteData.sublistView(await handle.read(33));
            pixels += header.getUint32(16) * header.getUint32(20);
          } finally {
            await handle.close();
          }
        }
        if (inputs.length != 10 ||
            bytes > ScreenshotLimits.maxBatchBytes ||
            pixels > ScreenshotLimits.maxBatchPixels) {
          throw StateError('Illegal boundary fixture batch');
        }
        event('boundary-selected', {
          'case': entry.key,
          'bytes': bytes,
          'pixels': pixels,
        });
        final started = watch.elapsedMilliseconds;
        final bounded = newCapture();
        final result = await bounded.captureFiles(inputs);
        bounded.dispose();
        event('boundary-result', {
          'case': entry.key,
          'error': result.error,
          'images': [
            for (final image in result.batch?.images ?? <DraftImage>[])
              {'error': image.error, 'tasks': image.tasks.length},
          ],
        });
        if (result.batch?.images.length != 10 ||
            result.batch!.images.any((i) => i.failed)) {
          throw StateError('Boundary capture failed: ${entry.key}');
        }
        event('boundary-draft', {
          'case': entry.key,
          'images': result.batch!.images.length,
          'bytes': bytes,
          'pixels': pixels,
          'tasks': result.batch!.activeTasks.length,
          'duration_ms': watch.elapsedMilliseconds - started,
        });
      }
    }
    // Cancellation during a real native call finishes that image, prevents
    // later native images, and releases staged sources in finally.
    late final ScreenshotCapture cancelling;
    Timer? cancelTimer;
    cancelling = newCapture(
      onNativeStart: () {
        cancelTimer ??= Timer(
          const Duration(milliseconds: 30),
          cancelling.cancel,
        );
      },
    );
    final cancelled = await cancelling.captureFiles(files);
    cancelTimer?.cancel();
    cancelling.dispose();
    if (!cancelled.cancelled) throw StateError('pending capture not cancelled');
    event('ocr-cancelled');
    final fixtures = env['WP17_Q1_FIXTURES'];
    if (fixtures != null) {
      final labels =
          jsonDecode(File('$fixtures/labels.json').readAsStringSync()) as Map;
      final reopened = newCapture();
      for (final spec in labels['cases'] as List) {
        final file = File('$fixtures/${spec['id']}.png');
        final result = await reopened.captureFiles([picked(file)]);
        final tasks = result.batch!.activeTasks;
        quality.add({
          'id': spec['id'],
          'failed': result.batch!.images.single.failed,
          'tasks': [
            for (final task in tasks)
              {
                'id': task.id,
                'title': task.title,
                'checked': task.checked,
                'parentId': task.parentId,
              },
          ],
        });
      }
      reopened.dispose();
      final bad = File('$fixtures/corrupt.png');
      final afterException = newCapture();
      final failed = await afterException.captureFiles([picked(bad)]);
      if (!failed.batch!.images.single.failed) {
        throw StateError('bad PNG accepted');
      }
      final recovered = await afterException.captureFiles([files.first]);
      if (recovered.batch!.images.single.failed) {
        throw StateError('recovery failed');
      }
      afterException.dispose();
      event('exception-recovery');
    }
    event('finished');
  } catch (error, stack) {
    code = 1;
    records.add({'error': error.toString(), 'stack': stack.toString()});
  } finally {
    timer.cancel();
    activeStore?.dispose();
    await report.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'exit': code,
        'pid': pid,
        'build': const bool.fromEnvironment('dart.vm.product')
            ? 'Release'
            : 'Debug',
        'threads': 4,
        'selection': 'explicit synthetic file seam',
        'submission':
            'harness confirmation, production ScreenshotSubmission + Store in fresh XDG',
        'sample_interval_ms': 20,
        'samples': samples,
        'sampled_peaks': sampledPeaks,
        'records': records,
        'quality': quality,
      }),
    );
  }
  exit(code);
}
