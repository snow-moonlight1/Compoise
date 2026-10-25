/// Synthetic data for the WP19-R prototype.
///
/// The ids, titles and timestamps are fixed literals: the session must render
/// and export identically on every machine, and no real library is ever read.
library;

import '../../models.dart';
import 'wp19_dev_model.dart';

const int _dayMs = 24 * 60 * 60 * 1000;

/// Civil-midnight style epoch, fixed so exports are byte-stable.
final int _baseMs = DateTime.utc(2026, 10, 1).millisecondsSinceEpoch;

/// Session clock start; each intent advances it by one minute.
final int wp19StartClockMs = _baseMs + 9 * _dayMs;

class DevSessionFixture {
  final List<Board> boards;
  final List<Task> tasks;
  final Map<String, DevFields> fields;

  const DevSessionFixture({
    required this.boards,
    required this.tasks,
    required this.fields,
  });

  DevExperiment toExperiment() => DevExperiment(
    boards: boards,
    tasks: tasks,
    fields: fields,
    startClockMs: wp19StartClockMs,
  );
}

Task _task({
  required String id,
  required String boardId,
  required String title,
  required int quadrant,
  List<String> tags = const [],
  List<SubTask> subtasks = const [],
  bool completed = false,
  int? deadlineDay,
  int? plannedDay,
  String? notes,
}) => Task(
  id: id,
  boardId: boardId,
  title: title,
  quadrant: quadrant,
  completed: completed,
  createdAt: _baseMs,
  deadline: deadlineDay == null ? null : _baseMs + deadlineDay * _dayMs,
  plannedDate: plannedDay == null ? null : _baseMs + plannedDay * _dayMs,
  tags: tags,
  subtasks: subtasks,
  notesMarkdown: notes,
);

const String releaseBoardId = 'p-release';
const String dailyBoardId = 'p-daily';

DevSessionFixture buildWp19Session() {
  final boards = [
    Board(id: releaseBoardId, name: 'Compoise 发布', createdAt: _baseMs),
    Board(id: dailyBoardId, name: '日常', createdAt: _baseMs),
  ];

  final tasks = [
    // ---- release project: the development-shaped work
    _task(
      id: 'r-scope',
      boardId: releaseBoardId,
      title: '定稿发行清单',
      quadrant: qDo,
      tags: const ['发行'],
      completed: true,
      notes: '确认三平台产物与版本号写法',
    ),
    _task(
      id: 'r-upgrade-doc',
      boardId: releaseBoardId,
      title: '写清数据升级与回退步骤',
      quadrant: qPlan,
      tags: const ['发行', '文档'],
      subtasks: [
        SubTask(id: 'r-upgrade-doc-1', title: '旧目录保留说明'),
        SubTask(id: 'r-upgrade-doc-2', title: '凭据未迁移提示'),
      ],
    ),
    _task(
      id: 'r-pipeline',
      boardId: releaseBoardId,
      title: '候选产物校验接到 CI',
      quadrant: qDo,
      tags: const ['CI'],
      deadlineDay: 5,
    ),
    _task(
      id: 'r-changelog',
      boardId: releaseBoardId,
      title: '版本号与三语更新说明',
      quadrant: qDelegate,
      tags: const ['发行', '文档'],
      plannedDay: 6,
    ),
    _task(
      id: 'r-clean-install',
      boardId: releaseBoardId,
      title: '干净安装验收',
      quadrant: qDo,
      tags: const ['验收'],
    ),
    _task(
      id: 'r-in-place',
      boardId: releaseBoardId,
      title: '原位升级保留任务',
      quadrant: qDo,
      tags: const ['验收'],
      deadlineDay: 7,
    ),
    _task(
      id: 'r-backup',
      boardId: releaseBoardId,
      title: '备份导出与导入往返',
      quadrant: qPlan,
      tags: const ['验收', '备份'],
    ),
    _task(
      id: 'r-tag',
      boardId: releaseBoardId,
      title: '打 tag 并发布 Release',
      quadrant: qDo,
      tags: const ['发行'],
      plannedDay: 9,
    ),
    _task(
      id: 'r-website',
      boardId: releaseBoardId,
      title: '更新下载页文案',
      quadrant: qEliminate,
    ),
    // ---- daily board: the ordinary-todo-shaped work the app already serves
    _task(
      id: 'd-refactor',
      boardId: dailyBoardId,
      title: '重构保存路径',
      quadrant: qPlan,
      tags: const ['实验'],
    ),
    _task(
      id: 'd-tests',
      boardId: dailyBoardId,
      title: '补保存并发用例',
      quadrant: qPlan,
      tags: const ['实验'],
    ),
    _task(
      id: 'd-water',
      boardId: dailyBoardId,
      title: '买牛奶',
      quadrant: qDelegate,
      plannedDay: 3,
    ),
    _task(
      id: 'd-renew',
      boardId: dailyBoardId,
      title: '续域名',
      quadrant: qDo,
      deadlineDay: 2,
      completed: true,
    ),
  ];

  final fields = {
    'r-scope': const DevFields(
      phase: DevPhase.design,
      acceptance: '清单条目都有对应产物',
    ),
    'r-upgrade-doc': const DevFields(
      phase: DevPhase.design,
      blockedBy: ['r-scope'],
    ),
    'r-pipeline': const DevFields(
      phase: DevPhase.build,
      blockedBy: ['r-upgrade-doc'],
    ),
    'r-changelog': const DevFields(
      phase: DevPhase.build,
      blockedBy: ['r-upgrade-doc'],
      acceptance: '三语说明与版本号一致',
    ),
    'r-clean-install': const DevFields(
      phase: DevPhase.verify,
      blockedBy: ['r-pipeline'],
      acceptance: '首次安装能建任务、重启后仍在',
    ),
    'r-in-place': const DevFields(
      phase: DevPhase.verify,
      blockedBy: ['r-pipeline', 'r-changelog'],
      acceptance: '旧库任务数与升级后一致，日程不丢',
    ),
    'r-backup': const DevFields(
      phase: DevPhase.verify,
      blockedBy: ['r-in-place'],
    ),
    'r-tag': const DevFields(
      phase: DevPhase.ship,
      blockedBy: ['r-clean-install', 'r-backup'],
      acceptance: 'Release 页可见 v1.0.0+1 与安装包摘要',
    ),
    'r-website': const DevFields(
      phase: DevPhase.ship,
      // Cross-board pointer: the lens must call this out, not link projects.
      blockedBy: ['d-water'],
    ),
    'd-water': const DevFields(),
    // Two-way wait: nothing in this pair can ever start.
    'd-refactor': const DevFields(
      phase: DevPhase.build,
      blockedBy: ['d-tests'],
    ),
    'd-tests': const DevFields(
      phase: DevPhase.verify,
      blockedBy: ['d-refactor'],
    ),
    'd-renew': const DevFields(
      phase: DevPhase.ship,
      acceptance: '旧格式仍能导入',
    ),
  };

  return DevSessionFixture(boards: boards, tasks: tasks, fields: fields);
}
