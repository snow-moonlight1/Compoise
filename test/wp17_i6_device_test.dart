// Opt-in device test. Native OCR, production preview and Store.
// Android uses real SAF. Linux can explicitly use driver-selected real files.
// Save failure and empty credentials are test seams; OCR is never injected.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:matrixflow_native/import_preview/draft_preview.dart';
import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/ocr/ocr_assets.dart';
import 'package:matrixflow_native/ocr/ocr_runtime.dart';
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
      debugPrint('WP17_I6_PROGRESS=$done/$total');
      progress(done, total);
    });
    debugPrint(
      'WP17_I6_CAPTURE error=${result.error} images=${result.batch?.images.length} cancelled=${result.cancelled}',
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
  Future<bool> write(String key, String value) async {
    if (armed && key == SaveProtocol.pointerKey) {
      pointers++;
      debugPrint('WP17_I6_POINTER_ATTEMPT=$pointers fail=$fail');
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

int _fileSelections = 0;
bool get _fileEntry =>
    Platform.isLinux && Platform.environment['WP17_I6_FILE_ENTRY'] == 'true';

Future<List<PlatformFile>?> _linuxFiles() async {
  final fixtures = Platform.environment['WP17_I6_FIXTURES']!;
  if (!_fileEntry) {
    return (await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['png'],
      allowMultiple: true,
      initialDirectory: '$fixtures/',
    ))?.files;
  }
  // Selection/cancellation only is injected in this explicit Linux mode.
  // Production capture still reads, decodes and recognizes actual disk bytes.
  if (_fileSelections++ == 0) return null;
  final directory = await Directory(fixtures).resolveSymbolicLinks();
  expect(directory, startsWith('${Platform.environment['WP17_I6_ROOT']}/'));
  final files = <PlatformFile>[];
  for (final name in const [
    '01-zh.png',
    '02-en.png',
    '03-ja.png',
    '04-zh-duplicate.png',
    '05-corrupt.png',
  ]) {
    final file = File('$directory/$name');
    expect(await file.resolveSymbolicLinks(), '$directory/$name');
    files.add(
      PlatformFile(name: name, path: file.path, size: await file.length()),
    );
  }
  return files;
}

ScreenshotBackend _linuxBackend(String root) {
  final runtime = OcrRuntime(assetsRoot: root);
  return _ObservedBackend(
    LocalScreenshotBackend(
      runtime: runtime,
      capture: ScreenshotCapture(runtime: runtime, picker: _linuxFiles),
    ),
  );
}

Widget _app(Store store, String root) => ChangeNotifierProvider.value(
  value: store,
  child: MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          key: const ValueKey('i6-open'),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ScreenshotImportPage(
                backend: Platform.isLinux ? _linuxBackend(root) : null,
              ),
            ),
          ),
          child: const Text('WP17-I6 synthetic import'),
        ),
      ),
    ),
  ),
);

Future<void> _open(WidgetTester tester) async {
  await _tap(tester, 'i6-open');
  await _wait(tester, () {
    final f = find.byKey(const ValueKey('screenshot-choose'));
    return f.evaluate().isNotEmpty &&
        tester.widget<FilledButton>(f).onPressed != null;
  }, 'official component availability');
}

Future<DraftPreview> _pick(WidgetTester tester, String marker) async {
  debugPrint(marker);
  // Starts the OS picker or explicit Linux real-file entry, then real native OCR.
  final started = DateTime.now();
  await _tap(tester, 'screenshot-choose');
  await _wait(
    tester,
    () => find.byType(DraftPreview).evaluate().isNotEmpty,
    'native OCR and preview',
  );
  debugPrint(
    'WP17_I6_BATCH_MS=${DateTime.now().difference(started).inMilliseconds}',
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
  if (!const bool.fromEnvironment('WP17_I6_DEVICE')) {
    test(
      'official import device acceptance requires WP17_I6_DEVICE',
      () {},
      skip: true,
    );
    return;
  }
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'official multi PNG -> native -> review -> one commit -> disk reopen',
    (tester) async {
      expect(Platform.isAndroid || Platform.isLinux, isTrue);
      final writer = _DiskWriter();
      late Store store;
      late SharedPreferences prefs;
      late String assetsRoot;
      final batches = <Map<String, Object?>>[];
      await tester.runAsync(() async {
        final support = await getApplicationSupportDirectory();
        if (Platform.isAndroid) {
          expect(support.path, contains('com.matrixflow.app.wp17i6'));
        } else {
          expect(
            Platform.environment['XDG_DATA_HOME'],
            contains('wp17i6-private'),
          );
          expect(
            support.path,
            startsWith(Platform.environment['XDG_DATA_HOME']!),
          );
        }
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
        await store.flush();
        writer.armed = true;
        final root = await resolveOcrAssetsRoot();
        assetsRoot = root;
        expect(await missingOcrModelFiles(root), isEmpty);
        final manifest =
            jsonDecode(await File('$root/bundle-manifest.json').readAsString())
                as Map;
        expect(manifest['modelSource'], 'official');
      });
      addTearDown(store.dispose);
      await tester.pumpWidget(_app(store, assetsRoot));
      await tester.pumpAndSettle();

      // Cancellation, zero writes and no temporary PNGs. Linux file-entry mode
      // injects a cancelled selection; other modes close the real OS dialog.
      await _open(tester);
      final beforeCancel = prefs.getString(SaveProtocol.pointerKey);
      debugPrint('WP17_I6_CANCEL_READY');
      await _tap(tester, 'screenshot-choose');
      await _wait(tester, () {
        final f = find.byKey(const ValueKey('screenshot-choose'));
        return f.evaluate().isNotEmpty &&
            tester.widget<FilledButton>(f).onPressed != null;
      }, 'picker cancellation');
      expect(store.tasks, isEmpty);
      expect(writer.pointers, 0);
      expect(prefs.getString(SaveProtocol.pointerKey), beforeCancel);
      await _cleanCache(tester);
      await _tap(tester, 'screenshot-cancel');

      // A complete native batch may still be cancelled before confirmation.
      await _open(tester);
      var preview = await _pick(tester, 'WP17_I6_REVIEW_CANCEL_READY');
      expect(preview.batch.images.length, 5);
      expect(preview.batch.images.where((i) => i.failed).length, 1);
      expect(preview.batch.duplicates, isNotEmpty);
      expect(preview.batch.activeTasks.every((t) => !t.confirmed), isTrue);
      expect(preview.batch.canSubmit, isFalse);
      batches.add({
        'case': 'review-cancel',
        'images': 5,
        'tasks': preview.batch.activeTasks.length,
      });
      await _tap(tester, 'import-cancel');
      expect(store.tasks, isEmpty);
      expect(writer.pointers, 0);
      await _cleanCache(tester);

      // Second continuous native batch. Check the original recognition, then
      // exercise explicit human review through the actual controls.
      await _open(tester);
      preview = await _pick(tester, 'WP17_I6_SAVE_READY');
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
      await tester.enterText(titleField, '${corrected.title} · reviewed');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      // Tap every confirmation; no draft or OCR result is injected or pre-confirmed.
      for (final task in batch.activeTasks.toList()) {
        await _tap(tester, 'confirm-${task.id}');
      }
      for (var i = 0; i < batch.duplicates.length; i++) {
        await _tap(tester, 'duplicate-$i');
      }
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
      expect(store.tasks, isEmpty);
      expect(prefs.getString(SaveProtocol.pointerKey), oldPointer);
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
        final reopened = Store(credentialStore: _EmptyCredentials());
        try {
          await reopened.init();
          expect(reopened.tasks.length, expectedRoots);
          final count =
              reopened.tasks.length +
              reopened.tasks.fold<int>(0, (n, t) => n + t.subtasks.length);
          expect(count, expectedCount);
          expect(reopened.tasks.map((t) => t.id).toSet().length, expectedRoots);
          var completed = 0;
          for (final task in reopened.tasks) {
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
            reopened.tasks.any(
              (t) => t.notesMarkdown?.contains(dateTask.dueText!) ?? false,
            ),
            isTrue,
          );
          expect(
            jsonEncode(reopened.tasks.map((t) => t.toJson()).toList()),
            jsonEncode(store.tasks.map((t) => t.toJson()).toList()),
          );
          batches.add({
            'case': 'failed-save-retry-reopen',
            'images': 5,
            'items': count,
            'roots': expectedRoots,
            'completed': completed,
            'pointer_attempts': writer.pointers,
            'successful_pointers': writer.successfulPointers,
          });
        } finally {
          reopened.dispose();
        }
      });
      await _cleanCache(tester);
      binding.reportData = {
        'platform': Platform.operatingSystem,
        'cases': batches,
        'picker': Platform.isAndroid
            ? 'ACTION_OPEN_DOCUMENT/content URI'
            : (_fileEntry
                  ? 'driver-selected real PNG files / native ScreenshotCapture'
                  : 'production file_picker/zenity'),
        'real_picker': !_fileEntry,
        'native': 'packaged official PP-OCRv5',
        'reopened': true,
        'temporary_pngs': 0,
      };
      debugPrint('WP17_I6_FLOW_PASSED');
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
