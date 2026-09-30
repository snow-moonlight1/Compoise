import '../import_preview/draft_model.dart';
import '../models.dart';
import '../storage.dart';

/// One flow owns one mapping. Failed retries reuse both ids and timestamps.
/// Only detached, explicitly confirmed ImportSubmission fields cross to Store.
final class ScreenshotSubmission {
  ScreenshotSubmission(this.batch, {String Function()? idFactory})
    : _idFactory = idFactory ?? newId;

  final DraftBatch batch;
  final String Function() _idFactory;
  final Map<String, String> _ids = {};
  final int _createdAt = DateTime.now().millisecondsSinceEpoch;
  bool _busy = false;
  bool _done = false;
  bool _cancelled = false;

  void cancel() => _cancelled = true;

  bool _matches(ImportSubmission submitted) {
    if (_cancelled || !batch.canSubmit) return false;
    final now = batch.snapshot();
    if (now.boardId != submitted.boardId ||
        now.quadrant != submitted.quadrant ||
        now.skippedCount != submitted.skippedCount ||
        now.tasks.length != submitted.tasks.length) {
      return false;
    }
    for (var i = 0; i < now.tasks.length; i++) {
      final a = now.tasks[i], b = submitted.tasks[i];
      if (a.id != b.id ||
          a.imageId != b.imageId ||
          a.title != b.title ||
          a.checked != b.checked ||
          a.parentId != b.parentId ||
          a.dueText != b.dueText) {
        return false;
      }
    }
    return true;
  }

  Future<void> commit(Store store, ImportSubmission submitted) async {
    if (_done) return;
    if (_busy || !_matches(submitted)) throw StateError('Review required');
    final roots = <String, Task>{};
    final seen = <String>{};
    final images = <String, String>{};
    for (final item in submitted.tasks) {
      if (!seen.add(item.id) ||
          item.id.isEmpty ||
          item.imageId.isEmpty ||
          item.title.trim().isEmpty ||
          item.title.length > 8192 ||
          (item.dueText?.length ?? 0) > 8192) {
        throw StateError('Invalid confirmed task');
      }
      final id = _ids.putIfAbsent(item.id, _idFactory);
      final notes = item.dueText == null ? null : _plainNotes(item.dueText!);
      if (item.parentId == null) {
        roots[item.id] = Task(
          id: id,
          boardId: submitted.boardId,
          title: item.title,
          quadrant: submitted.quadrant,
          createdAt: _createdAt,
          completed: item.checked,
          notesMarkdown: notes,
        );
        images[item.id] = item.imageId;
      } else {
        final parent = roots[item.parentId];
        if (parent == null || images[item.parentId] != item.imageId) {
          throw StateError('Parent must be an earlier root in the same image');
        }
        parent.subtasks.add(
          SubTask(
            id: id,
            title: item.title,
            completed: item.checked,
            notesMarkdown: notes,
          ),
        );
      }
    }
    final epoch = store.boardEpoch(submitted.boardId);
    bool guard() =>
        _matches(submitted) &&
        store.boardEpoch(submitted.boardId) == epoch &&
        store.boards.any((b) => b.id == submitted.boardId);
    if (!guard()) throw StateError('Destination unavailable');
    _busy = true;
    try {
      final result = await store.applyScreenshotImport(
        {
          'version': 2,
          'boards': [
            {'id': submitted.boardId, 'name': '', 'createdAt': 0},
          ],
          'tasks': roots.values.map((task) => task.toJson()).toList(),
        },
        boardId: submitted.boardId,
        stillConfirmed: guard,
      );
      if (!result.success) throw StateError('Import was not saved');
      _done = true;
    } finally {
      _busy = false;
    }
  }
}

// Keep opted-in date text literal in the app's Markdown notes renderer.
String _plainNotes(String text) => text.replaceAllMapped(
  RegExp(r'[\\`*_{}\[\]()<>#+.!|~-]'),
  (match) => '\\${match[0]}',
);
