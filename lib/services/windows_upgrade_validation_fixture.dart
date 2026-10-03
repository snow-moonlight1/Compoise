// Synthetic R2 data only. Referenced by the compile-gated Windows diagnostics.
import 'dart:convert';

import '../import_preview/draft_model.dart';
import '../models.dart';
import '../schedule_item.dart';
import '../storage.dart';

const r2DateText = '**明天** 2026-11-01 01:30 [原文] <未解析> +08:00';
const r2ChildDateText = '2026-03-08 02:30 America/New_York（日期原文）';
const r2DateNotes = r'\*\*明天\*\* 2026\-11\-01 01:30 \[原文\] \<未解析\> \+08:00';
const r2ChildDateNotes = r'2026\-03\-08 02:30 America/New\_York（日期原文）';
final r2LongNote = List.filled(
  160,
  'Synthetic plain text / 合成纯文本 / no links or credentials.\n',
).join();

Map<String, String> r2SyntheticValues({bool schedule = true}) => {
  'matrixflow-tasks': jsonEncode([
    Task(
      id: 'synthetic-task',
      boardId: 'synthetic-board',
      title: 'Synthetic parent',
      quadrant: 2,
      createdAt: 1,
      plannedDate: 1790812800000,
      deadline: 2000000000000,
      reminderAt: 1999996400000,
      reminderTimezone: 'Asia/Shanghai',
      urgencyMode: UrgencyMode.manual,
      notesMarkdown: r2LongNote,
      reasoning: 'Synthetic reasoning',
      tags: ['Upgrade', '合成'],
      subtasks: [
        SubTask(
          id: 'synthetic-subtask',
          title: 'Synthetic completed child',
          completed: true,
          completedAt: 1790812900000,
          deadline: 2000000000000,
          reminderAt: 1999992800000,
          notesMarkdown: 'Child plain text\nSecond line',
        ),
        SubTask(id: 'synthetic-open-child', title: 'Synthetic open child'),
      ],
    ).toJson(),
    Task(
      id: 'synthetic-completed',
      boardId: 'synthetic-second-board',
      title: 'Synthetic completed parent',
      quadrant: 4,
      createdAt: 2,
      isLongTerm: true,
      completed: true,
      completedAt: 1790813000000,
      plannedDate: 1790899200000,
      deadline: 2000086400000,
      reminderAt: 2000082800000,
      reminderTimezone: 'America/New_York',
      urgencyMode: UrgencyMode.manual,
      notesMarkdown: 'Completed task note',
    ).toJson(),
  ]),
  'matrixflow-boards': jsonEncode([
    Board(
      id: 'synthetic-board',
      name: 'Synthetic first board',
      createdAt: 1,
    ).toJson(),
    Board(
      id: 'synthetic-second-board',
      name: 'Synthetic second board',
      createdAt: 2,
    ).toJson(),
    Board(
      id: 'synthetic-empty-board',
      name: 'Empty board',
      createdAt: 3,
    ).toJson(),
  ]),
  'matrixflow-config': jsonEncode(
    AIConfig(model: 'synthetic-model').toJson(includeCredential: false),
  ),
  'matrixflow-settings': jsonEncode(
    AppSettings(language: Language.en, globalShortcut: '').toJson(),
  ),
  'matrixflow-active-board': 'synthetic-second-board',
  'matrixflow-has-seen-onboarding': 'true',
  if (schedule)
    SaveProtocol.scheduleKey: jsonEncode([
      ScheduleItem.timeBlock(
        id: 'synthetic-block',
        taskId: 'synthetic-task',
        // 23:30 -> 01:30 Shanghai, across midnight.
        startAt: DateTime.utc(2026, 10, 1, 15, 30).millisecondsSinceEpoch,
        endAt: DateTime.utc(2026, 10, 1, 17, 30).millisecondsSinceEpoch,
        timeZoneId: 'Asia/Shanghai',
      ).toJson(),
      ScheduleItem.event(
        id: 'synthetic-linked-event',
        title: 'Overlapping linked meeting',
        taskId: 'synthetic-task',
        startAt: DateTime.utc(2026, 10, 1, 16).millisecondsSinceEpoch,
        endAt: DateTime.utc(2026, 10, 1, 17).millisecondsSinceEpoch,
        timeZoneId: 'Asia/Shanghai',
      ).toJson(),
      ScheduleItem.event(
        id: 'synthetic-board-event',
        title: 'Board-wide independent meeting',
        boardId: 'synthetic-second-board',
        // A real 1-hour interval across the spring gap, 01:30 -> 03:30.
        startAt: DateTime.utc(2026, 3, 8, 6, 30).millisecondsSinceEpoch,
        endAt: DateTime.utc(2026, 3, 8, 7, 30).millisecondsSinceEpoch,
        timeZoneId: 'America/New_York',
      ).toJson(),
      ScheduleItem.timeBlock(
        id: 'synthetic-fold-block',
        taskId: 'synthetic-completed',
        // First 01:30 EDT -> second 01:30 EST, distinct absolute instants.
        startAt: DateTime.utc(2026, 11, 1, 5, 30).millisecondsSinceEpoch,
        endAt: DateTime.utc(2026, 11, 1, 6, 30).millisecondsSinceEpoch,
        timeZoneId: 'America/New_York',
      ).toJson(),
    ]),
};

DraftBatch r2ScreenshotBatch(String boardId) {
  final root = DraftTask(
    id: 'r2-draft-root',
    imageId: 'synthetic-image',
    sourceRow: 0,
    title: 'Synthetic screenshot parent',
    checked: false,
    dueText: r2DateText,
    keepDueText: true,
  )..confirmed = true;
  final child = DraftTask(
    id: 'r2-draft-child',
    imageId: 'synthetic-image',
    sourceRow: 1,
    title: 'Synthetic screenshot child',
    checked: true,
    parentId: root.id,
    dueText: r2ChildDateText,
    keepDueText: true,
  )..confirmed = true;
  return DraftBatch(
      images: [
        DraftImage(id: root.imageId, tasks: [root, child]),
      ],
    )
    ..boardId = boardId
    ..quadrant = 3;
}

Map<String, Object?> r2Library(Store store) => {
  'tasks': store.tasks.map((t) => t.toJson()).toList(),
  'boards': store.boards.map((b) => b.toJson()).toList(),
  'schedule': store.scheduleItems.map((s) => s.toJson()).toList(),
  'config': store.aiConfig.toJson(includeCredential: false),
  'settings': store.settings.toJson(),
  'activeBoard': store.activeBoardId,
  'onboarding': store.hasSeenOnboarding,
};

Map<String, Object?> r2LibraryFromValues(Map<String, String> values) => {
  'tasks': jsonDecode(values['matrixflow-tasks']!),
  'boards': jsonDecode(values['matrixflow-boards']!),
  'schedule': jsonDecode(values[SaveProtocol.scheduleKey] ?? '[]'),
  'config': jsonDecode(values['matrixflow-config']!),
  'settings': jsonDecode(values['matrixflow-settings']!),
  'activeBoard': values['matrixflow-active-board'],
  'onboarding': values['matrixflow-has-seen-onboarding'] == 'true',
};

// Seed generation has no platform credential IO and cannot accept a secret.
class R2SeedCredentials implements CredentialStore {
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String value) async => throw StateError('No seed secrets');
  @override
  Future<void> delete() async {}
}
