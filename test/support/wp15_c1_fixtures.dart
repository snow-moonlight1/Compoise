import 'package:matrixflow_native/models.dart';
import 'package:matrixflow_native/schedule_item.dart';
import 'package:matrixflow_native/schedule_time.dart';
import 'package:matrixflow_native/storage.dart';

const c1Zone = 'Asia/Shanghai';

int c1At(int day, int hour, {int minute = 0}) => resolveWallTime(
  ScheduleWallTime(ScheduleCivilDate(2026, 9, day), hour: hour, minute: minute),
  c1Zone,
);

List<Board> c1Boards() => [
  Board(id: 'work', name: 'Work board', createdAt: 1),
  Board(id: 'home', name: 'Home board', createdAt: 1),
];

List<Task> c1Tasks() => [
  Task(
    id: 'outline',
    boardId: 'work',
    title: 'Draft outline',
    quadrant: 2,
    createdAt: 1,
    urgencyMode: UrgencyMode.manual,
    plannedDate: c1At(29, 0),
    deadline: c1At(30, 23),
    reminderAt: c1At(30, 8),
  ),
  Task(
    id: 'done',
    boardId: 'home',
    title: 'Completed parent',
    quadrant: 3,
    createdAt: 2,
    completed: true,
    urgencyMode: UrgencyMode.manual,
  ),
];

ScheduleItem c1Event(
  String id,
  int start,
  int end, {
  String? taskId,
  String? boardId,
  String zone = c1Zone,
}) => ScheduleItem.event(
  id: id,
  title: 'Event $id',
  taskId: taskId,
  boardId: taskId == null ? boardId ?? 'home' : null,
  startAt: start,
  endAt: end,
  timeZoneId: zone,
);

List<ScheduleItem> c1Items() => [
  ScheduleItem.timeBlock(
    id: 'block',
    taskId: 'outline',
    startAt: c1At(30, 0, minute: 30),
    endAt: c1At(30, 2),
    timeZoneId: c1Zone,
  ),
  c1Event('linked', c1At(30, 0, minute: 45), c1At(30, 2), taskId: 'outline'),
  c1Event('independent', c1At(30, 1), c1At(30, 2)),
  c1Event('done', c1At(30, 3), c1At(30, 4), taskId: 'done'),
];

StoreSnapshot c1Snapshot({
  List<ScheduleItem>? items,
  List<Task>? tasks,
  List<Board>? boards,
  Language language = Language.en,
}) => StoreSnapshot(
  boards: boards ?? c1Boards(),
  tasks: tasks ?? c1Tasks(),
  scheduleItems: items ?? c1Items(),
  aiConfig: AIConfig(),
  settings: AppSettings(language: language),
  activeBoardId: 'work',
  taskRevisions: const {},
  scheduleRevisions: const {},
);
