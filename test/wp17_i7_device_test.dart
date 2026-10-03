// Opt-in device test. Native OCR, production preview and Store.
// Linux uses the unmodified production picker and a second application process.
// Save failure and empty credentials are test seams; OCR is never injected.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:matrixflow_native/import_preview/draft_preview.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/ocr/ocr_assets.dart';
import 'package:matrixflow_native/screenshot_import/screenshot_capture.dart';
import 'package:matrixflow_native/screenshot_import/screenshot_backend.dart';
import 'package:matrixflow_native/screenshot_import/screenshot_import_page.dart';
import 'package:matrixflow_native/storage.dart';
import 'support/wp17_i6_reference_drafts.dart';

class _ObservedBackend implements ScreenshotBackend {
  _ObservedBackend(this.inner);
  final ScreenshotBackend inner;
  @override
  Future<String?> availability() => inner.availability();
  @override
  Future<ScreenshotCaptureResult> capture(
    void Function(int, int) progress,
  ) async {
    final result = await inner.capture((done, total) {
      debugPrint('WP17_I7_PROGRESS=$done/$total');
      progress(done, total);
    });
    debugPrint(
      'WP17_I7_CAPTURE error=${result.error} images=${result.batch?.images.length} cancelled=${result.cancelled}',
    );
    return result;
  }

  @override
  void cancel() => inner.cancel();
  @override
  Future<void> dispose() => inner.dispose();
}

class _EmptyCredentials implements CredentialStore {
  @override
  Future<String?> read() async => null;
  @override
  Future<void> delete() async {}
  @override
  Future<void> write(String value) async =>
      throw StateError('No credentials in this synthetic run');
}

class _DiskWriter {
  bool armed = false, fail = false;
  int pointers = 0;
  int successfulPointers = 0;
  int writes = 0;
  List<String> attemptedIds = [];

  Future<bool> write(String key, String value) async {
    if (armed) writes++;
    if (armed &&
        fail &&
        (key == 'matrixflow-save-a' || key == 'matrixflow-save-b')) {
      final values = (jsonDecode(value) as Map)['values'] as Map;
      final tasks = jsonDecode(values['matrixflow-tasks'] as String) as List;
      if (tasks.isNotEmpty) {
        attemptedIds = [
          for (final t in tasks) t['id'] as String,
          for (final t in tasks)
            for (final sub in t['subtasks'] as List) sub['id'] as String,
        ];
      }
    }
    if (armed && key == SaveProtocol.pointerKey) {
      pointers++;
      debugPrint('WP17_I7_POINTER_ATTEMPT=$pointers fail=$fail');
      if (fail) return false;
      successfulPointers++;
    }
    return (await SharedPreferences.getInstance()).setString(key, value);
  }
}

Future<void> _wait(
  WidgetTester tester,
  bool Function() ready,
  String label,
) async {
  final limit = DateTime.now().add(const Duration(minutes: 4));
  while (!ready()) {
    if (DateTime.now().isAfter(limit)) fail('Timed out: $label');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    final error = tester.takeException();
    if (error != null) throw error;
  }
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  if (key == 'screenshot-choose') {
    await tester.pump();
    return;
  }
  await tester.pumpAndSettle();
}

Widget _app(Store store) => ChangeNotifierProvider.value(
  value: store,
  child: MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          key: const ValueKey('i7-open'),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ScreenshotImportPage(
                backend: _ObservedBackend(LocalScreenshotBackend()),
              ),
            ),
          ),
          child: const Text('WP17-I7 synthetic import'),
        ),
      ),
    ),
  ),
);

Future<void> _open(WidgetTester tester) async {
  await _tap(tester, 'i7-open');
  await _wait(tester, () {
    final f = find.byKey(const ValueKey('screenshot-choose'));
    return f.evaluate().isNotEmpty &&
        tester.widget<FilledButton>(f).onPressed != null;
  }, 'official component availability');
}

Future<DraftPreview> _pick(WidgetTester tester, String marker) async {
  debugPrint(marker);
  // Starts the production OS picker, followed by real native OCR.
  final started = DateTime.now();
  await _tap(tester, 'screenshot-choose');
  await _wait(
    tester,
    () => find.byType(DraftPreview).evaluate().isNotEmpty,
    'native OCR and preview',
  );
  debugPrint(
    'WP17_I7_BATCH_MS=${DateTime.now().difference(started).inMilliseconds}',
  );
  return tester.widget<DraftPreview>(find.byType(DraftPreview));
}

Future<void> _cleanCache(WidgetTester tester) async {
  await tester.runAsync(() async {
    final cache = await getTemporaryDirectory();
    final owned = Directory('${cache.path}/wp17-screenshot-import');
    if (await owned.exists()) expect(await owned.list().toList(), isEmpty);
  });
}

void main() {
  if (!const bool.fromEnvironment('WP17_I7_DEVICE')) {
    test(
      'official import device acceptance requires WP17_I7_DEVICE',
      () {},
      skip: true,
    );
    return;
  }
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Observe the integration binding's suite result, including teardown failures.
  // Direct execution lets the host waitpid the actual app, without flutter
  // drive terminating it and losing the application's own exit status.
  unawaited(_finishProcess(binding));
  if (Platform.environment['WP17_I7_PHASE'] == 'reopen') {
    _registerReopen(binding);
    return;
  }
  testWidgets(
    'production picker -> native -> review -> failed save -> retry',
    (tester) async {
      expect(Platform.isLinux, isTrue);
      final writer = _DiskWriter();
      late Store store;
      late SharedPreferences prefs;
      final batches = <Map<String, Object?>>[];
      await tester.runAsync(() async {
        final support = await getApplicationSupportDirectory();
        _assertIsolation(support);
        prefs = await SharedPreferences.getInstance();
        expect(
          prefs.getKeys().where((k) => k.startsWith('matrixflow')),
          isEmpty,
          reason: 'Use a fresh dedicated application identity / XDG root',
        );
        store = Store(
          credentialStore: _EmptyCredentials(),
          saveWriter: writer.write,
        );
        await store.init();
        store.updateSettings((s) => s..language = Language.en);
        store.createBoard('WP17-I7 destination');
        await store.flush();
        writer.armed = true;
        final root = await resolveOcrAssetsRoot();
        expect(await missingOcrModelFiles(root), isEmpty);
        final manifest =
            jsonDecode(await File('$root/bundle-manifest.json').readAsString())
                as Map;
        expect(manifest['modelSource'], 'official');
      });
      addTearDown(store.dispose);
      await tester.pumpWidget(_app(store));
      await tester.pumpAndSettle();

      // Cancel the actual system dialog; no selected-file seam exists here.
      await _open(tester);
      final beforeCancel = prefs.getString(SaveProtocol.pointerKey);
      debugPrint('WP17_I7_CANCEL_READY');
      await _tap(tester, 'screenshot-choose');
      await _wait(tester, () {
        final f = find.byKey(const ValueKey('screenshot-choose'));
        return f.evaluate().isNotEmpty &&
            tester.widget<FilledButton>(f).onPressed != null;
      }, 'picker cancellation');
      expect(store.tasks, isEmpty);
      expect(writer.pointers, 0);
      expect(writer.writes, 0);
      expect(prefs.getString(SaveProtocol.pointerKey), beforeCancel);
      batches.add({
        'case': 'picker-cancel',
        'items': 0,
        'pointer_writes': 0,
        'store_writer_calls': 0,
        'pointer_unchanged': true,
      });
      await _cleanCache(tester);
      await _tap(tester, 'screenshot-cancel');

      // A complete native batch may still be cancelled before confirmation.
      await _open(tester);
      var preview = await _pick(tester, 'WP17_I7_REVIEW_CANCEL_READY');
      expect(preview.batch.images.length, 5);
      expect(preview.batch.images.where((i) => i.failed).length, 1);
      expect(preview.batch.duplicates, isNotEmpty);
      expect(preview.batch.activeTasks.every((t) => !t.confirmed), isTrue);
      expect(preview.batch.canSubmit, isFalse);
      batches.add({
        'case': 'review-cancel',
        'images': 5,
        'tasks': preview.batch.activeTasks.length,
        'failed_images': 1,
        'unconfirmed_submit_disabled': true,
        'pointer_writes': 0,
      });
      await _tap(tester, 'import-cancel');
      expect(store.tasks, isEmpty);
      expect(writer.pointers, 0);
      expect(writer.writes, 0);
      await _cleanCache(tester);

      // Second continuous native batch. Check the original recognition, then
      // exercise explicit human review through the actual controls.
      await _open(tester);
      preview = await _pick(tester, 'WP17_I7_SAVE_READY');
      final batch = preview.batch;
      expect(batch.images.length, 5);
      expect(batch.images.where((i) => i.failed).length, 1);
      expect(batch.duplicates, isNotEmpty);
      final successful = batch.images.where((image) => !image.failed).toList();
      const names = [
        'zh_light_base',
        'en_light_base',
        'ja_light_base',
        'zh_light_base',
      ];
      for (var index = 0; index < names.length; index++) {
        final image = successful[index];
        final expected = i6ReferenceDrafts[names[index]]!;
        final tasks = image.tasks.where((task) => !task.excluded).toList();
        expect(tasks.map((t) => t.title), expected.map((t) => t['title']));
        expect(tasks.map((t) => t.checked), expected.map((t) => t['checked']));
        expect(tasks.map((t) => t.dueText), expected.map((t) => t['due']));
        expect(
          tasks.map((t) => t.parentId),
          expected.map(
            (t) => t['parent'] == null ? null : '${image.id}:${t['parent']}',
          ),
        );
      }
      expect(batch.activeTasks.where((t) => t.parentId != null), isNotEmpty);
      expect(batch.activeTasks.where((t) => t.checked), isNotEmpty);
      expect(batch.activeTasks.where((t) => t.dueText != null), isNotEmpty);
      expect(batch.canSubmit, isFalse);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('import-submit')))
            .onPressed,
        isNull,
      );
      expect(store.tasks, isEmpty);
      await _cleanCache(tester);
      // Skip the duplicate image explicitly. Its warning still requires an acknowledgement.
      final good = batch.images.where((i) => !i.failed).toList();
      final duplicate = good
          .where(
            (i) =>
                i.tasks.map((t) => t.title).join('|') ==
                good.first.tasks.map((t) => t.title).join('|'),
          )
          .last;
      expect(duplicate, isNot(same(good.first)));
      await _tap(tester, 'image-skip-${duplicate.id}');
      final dateTask = batch.activeTasks.firstWhere((t) => t.dueText != null);
      await _tap(tester, 'keep-due-${dateTask.id}');
      final corrected = batch.activeTasks.first;
      final titleField = find.byKey(ValueKey('title-${corrected.id}'));
      await tester.ensureVisible(titleField);
      await tester.enterText(titleField, '${corrected.title} 路 reviewed');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      // Tap every confirmation; no draft or OCR result is injected or pre-confirmed.
      for (final task in batch.activeTasks.toList()) {
        await _tap(tester, 'confirm-${task.id}');
      }
      for (var i = 0; i < batch.duplicates.length; i++) {
        await _tap(tester, 'duplicate-$i');
      }
      await _tap(tester, 'import-board');
      await tester.tap(find.text('WP17-I7 destination').last);
      await tester.pumpAndSettle();
      await _tap(tester, 'import-quadrant');
      await tester.tap(find.textContaining('Quadrant 1').last);
      await tester.pumpAndSettle();
      expect(batch.canSubmit, isTrue);
      final expectedCount = batch.activeTasks.length;
      final expectedRoots = batch.activeTasks
          .where((t) => t.parentId == null)
          .length;
      final expectedCompleted = batch.activeTasks
          .where((t) => t.checked)
          .length;
      final oldPointer = prefs.getString(SaveProtocol.pointerKey);
      final reviewedBeforeFailure = _reviewState(batch.activeTasks);
      writer.fail = true;
      await _tap(tester, 'import-submit');
      expect(
        writer.pointers,
        greaterThanOrEqualTo(1),
        reason: 'failure must exercise disk pointer writes',
      );
      expect(writer.successfulPointers, 0);
      expect(find.byType(DraftPreview), findsOneWidget);
      expect(batch.canSubmit, isTrue);
      expect(_reviewState(batch.activeTasks), reviewedBeforeFailure);
      expect(store.tasks, isEmpty);
      expect(prefs.getString(SaveProtocol.pointerKey), oldPointer);
      final failedIds = writer.attemptedIds;
      expect(failedIds, hasLength(expectedCount));
      writer.fail = false;
      await _tap(tester, 'import-submit');
      await _wait(
        tester,
        () => find.byType(ScreenshotImportPage).evaluate().isEmpty,
        'retry commit',
      );
      expect(
        writer.successfulPointers,
        1,
        reason:
            'exactly one successful batch pointer after the failed attempts',
      );
      await tester.runAsync(() async {
        await store.flush();
        await prefs.reload(); // Actual platform disk read, no mock preferences.
        final count =
            store.tasks.length +
            store.tasks.fold<int>(0, (n, t) => n + t.subtasks.length);
        expect(store.tasks.length, expectedRoots);
        expect(count, expectedCount);
        expect(_ids(store).toSet().length, expectedCount);
        expect(_ids(store), failedIds);
        expect(
          store.tasks.every(
            (t) => t.boardId == store.activeBoardId && t.quadrant == 1,
          ),
          isTrue,
        );
        var completed = 0;
        for (final task in store.tasks) {
          if (task.completed) completed++;
          expect(task.deadline, isNull);
          expect(task.plannedDate, isNull);
          expect(task.reminderAt, isNull);
          expect(task.completedAt, isNull);
          for (final sub in task.subtasks) {
            if (sub.completed) completed++;
            expect(sub.deadline, isNull);
            expect(sub.reminderAt, isNull);
            expect(sub.completedAt, isNull);
          }
        }
        expect(completed, expectedCompleted);
        expect(
          store.tasks.any(
            (t) => t.notesMarkdown?.contains(dateTask.dueText!) ?? false,
          ),
          isTrue,
        );
        await File(Platform.environment['WP17_I7_EXPECTED']!).writeAsString(
          jsonEncode({
            'snapshot': _snapshot(store),
            'pointer': prefs.getString(SaveProtocol.pointerKey),
          }),
          flush: true,
        );
        batches.add({
          'case': 'failed-save-retry',
          'images': 5,
          'items': count,
          'roots': expectedRoots,
          'completed': completed,
          'pointer_attempts': writer.pointers,
          'successful_pointers': writer.successfulPointers,
          'retry_stable_ids': true,
          'failed_save_preserved_review': true,
          'date_text_only_in_notes': true,
        });
      });
      await _cleanCache(tester);
      binding.reportData = {
        'platform': Platform.operatingSystem,
        'cases': batches,
        'picker': 'production pickScreenshotPngFiles/file_picker/zenity',
        'real_picker': true,
        'real_ocr': true,
        'native': 'packaged official PP-OCRv5',
        'save_fault':
            'test saveWriter refuses SaveProtocol.pointerKey; slot writes remain real',
        'snapshot': _snapshot(store),
        'temporary_pngs': 0,
      };
      debugPrint('WP17_I7_FLOW_PASSED');
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
}

Map<String, Object?> _snapshot(Store store) => {
  'boards': store.boards.map((b) => b.toJson()).toList(),
  'activeBoardId': store.activeBoardId,
  'tasks': store.tasks.map((t) => t.toJson()).toList(),
  'settings': store.settings.toJson(),
  'schedule': store.scheduleItems.map((s) => s.toJson()).toList(),
};

List<String> _ids(Store store) => [
  for (final t in store.tasks) t.id,
  for (final t in store.tasks)
    for (final s in t.subtasks) s.id,
];

String _reviewState(Iterable<dynamic> tasks) => jsonEncode([
  for (final t in tasks)
    [t.id, t.title, t.checked, t.parentId, t.dueText, t.confirmed],
]);

void _assertIsolation(Directory support) {
  expect(Platform.isLinux, isTrue);
  final root = Platform.environment['WP17_I7_ROOT']!;
  expect(root, endsWith('/wp17i7-private'));
  final data = Platform.environment['XDG_DATA_HOME']!;
  expect(data, startsWith('$root/runs/'));
  expect(support.path, startsWith('$data/'));
  expect(
    Platform.environment['WP17_LINUX_PRIVATE_DISPLAY'],
    Platform.environment['DISPLAY'],
  );
  expect(Platform.environment['WP17_I7_PHASE'], anyOf('import', 'reopen'));
}

Future<void> _finishProcess(
  IntegrationTestWidgetsFlutterBinding binding,
) async {
  final passed = await binding.allTestsPassed.future;
  final data = <String, Object?>{
    ...?binding.reportData,
    'passed': passed,
    'phase': Platform.environment['WP17_I7_PHASE'],
    'pid': pid,
    'identity': 'matrixflow_native in private XDG root',
    'data_root': Platform.environment['XDG_DATA_HOME'],
    'failures': binding.failureMethodsDetails.map((f) => f.details).toList(),
  };
  try {
    await File(Platform.environment['WP17_I7_REPORT']!).writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(data)}\n',
      flush: true,
    );
    exit(passed ? 0 : 1);
  } catch (error) {
    debugPrint('WP17_I7_REPORT_FAILED=$error');
    exit(2);
  }
}

void _registerReopen(IntegrationTestWidgetsFlutterBinding binding) {
  testWidgets('second independent process opens production Store from disk', (
    tester,
  ) async {
    final store = Store(credentialStore: _EmptyCredentials());
    addTearDown(store.dispose);
    await tester.runAsync(() async {
      _assertIsolation(await getApplicationSupportDirectory());
      final prefs = await SharedPreferences.getInstance();
      final expected =
          jsonDecode(
                await File(
                  Platform.environment['WP17_I7_EXPECTED']!,
                ).readAsString(),
              )
              as Map;
      // The expected snapshot is comparison-only. It is never supplied to
      // prefs/Store and cannot stand in for the persisted database.
      await store.init();
      expect(_snapshot(store), expected['snapshot']);
      expect(prefs.getString(SaveProtocol.pointerKey), expected['pointer']);
      final ids = _ids(store);
      expect(ids, hasLength(24));
      expect(ids.toSet().length, ids.length);
      expect(store.tasks, hasLength(18));
      expect(store.boards, hasLength(2));
      expect(store.boards.last.name, 'WP17-I7 destination');
      binding.reportData = {
        'independent_disk_reopen': true,
        'snapshot': _snapshot(store),
        'compared': [
          'boards/all fields',
          'activeBoardId',
          'tasks/all fields',
          'parent/subtasks/all fields',
          'IDs',
          'completion',
          'notes',
          'dates',
          'settings',
          'schedule',
        ],
      };
    });
    await _cleanCache(tester);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
