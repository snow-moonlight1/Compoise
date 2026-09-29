# 今天待办与计划日（WP14）

状态：已集成。范围只有今天待办页与 `plannedDate` 语义。
Planner / Schedule（WP15）与今日完成庆祝（WP16）不在本包，本包只交出它们依赖的数据契约。

## 两个字段的区别（WP15、WP16 读这一节）

| | `plannedDate` 计划日 | `deadline` 截止日期 |
|---|---|---|
| 含义 | 打算哪天开始做 | 最晚可以拖到哪天 |
| 存储 | Unix 毫秒，本地日历日**零点** | Unix 毫秒，本地日历日 23:59:59 |
| 缺省 | 字段不写出，等于「没有安排」 | 字段不写出，等于「没有期限」 |
| 归属 | 只有父任务 | 父任务和子项都有 |
| 后果 | 只决定今天待办页的分组，**不改变象限** | 临近时按既有规则把任务推入紧急一侧 |

- 两者互相独立：设置其中一个从不改写另一个，也不改写提醒。
- 判读日历日用同一个 `isSameCivilDay`（已移到 [calendar_dates.dart](../lib/calendar_dates.dart)），所以零点存的计划和 23:59 存的期限在同一天时会被认成同一天。
- v2 独有字段：`Store.exportJson(version: 1)` 不写出它；缺该字段的旧库、旧备份照常读取为「未安排」。文件契约见 [备份格式](BACKUP_FORMAT.md)。

判读逻辑集中在 [planned_policy.dart](../lib/planned_policy.dart)，它是本包交给后续包的唯一入口：
`plannedDayMs`、`plannedDaysLeft`、`todaySectionOf`、`groupForToday`、`completedOnDay`、`compareTodayTasks`。
Store 侧的读写口：`todayGroups({allBoards, now})`、`completedTodayCount({allBoards})`、
`setPlannedDay(taskId, day?)`（写入统一在此规范化为零点）、`newTask(..., plannedDate:)`。

## 今天待办页

[today_screen.dart](../lib/screens/today_screen.dart) 从首页「更多」进入，按**日**而不是按象限聚合：

1. `todaySectionCarriedOver`：计划日已过且未完成，即拖过来的任务。
2. `todaySectionPlannedToday`：计划在今天。
3. `todaySectionDueNow`：今天没有安排，但截止日已到或已过。

- 一个任务只出现在一个分组里，计划优先于期限；计划在未来某天但期限已到的任务，仍会因期限出现在第 3 组。
- 分组内按「最近的期限 → 最早的计划 → 最早创建」排序，保证跨象限的顺序稳定可解释。
- 每行自带象限与看板标记：聚合按日，不掩盖任务原本的归属。看板标记只在跨看板范围或任务不属于当前看板时出现。
- 行内动作只有勾选完成、「安排到今天」和「取消计划」。完成只累加今日计数并以文字摘要呈现，没有动画。
- 已完成的任务不进入任何分组，`hideCompleted` 不影响这一页。
- 时间面板按 WP13 的既有位置扩到三行：截止日期、提醒时间、计划日。只有父任务的编辑器给出计划行，子项编辑器保持原样。
  计划行**放在最后**，且两行说明与各自标题同行显示：390×844 上这个对话框已经接近撑满，把新增内容插在截止日期与提醒预设之间
  会把 `reminder-quick-*` 推出可点区域，`test/widget_regression_test.dart` 的 WP25 提醒用例随之失败（点不到 → 提醒没写进去）。
- 矩阵卡片上计划日单独标记（不同图标、强调色，永不用告警色），与截止标记并列。

## 边界

未做，留给后续包：明天及未来视图、拖拽排期、按周/月的 Planner 与 Schedule（WP15）；今日完成的庆祝反馈（WP16）；
把 `plannedDate` 接入搜索筛选维度；计划与提醒的联动；批量改计划日（与 WP10 重叠）；
今天页的行退出动效（刻意不引入 `ExitRetention`，本包不做动画）。

## 验收证据

在 `D:/Dev_project/martix-wp14-today` 上，Flutter 3.32.8（`D:/Dev_SDKs/Flutter_3.32.8`）：

- `flutter analyze --no-pub` → No issues found（exit 0）。
- `flutter test --no-pub test/wp14_planned_date_model_test.dart test/wp14_planned_date_policy_test.dart test/wp14_today_screen_test.dart` → **42 通过，0 失败**（exit 0）。
- `flutter test --no-pub` 默认全量套件 → **958 通过，0 失败**（exit 0）；主线基线为 916，本包净增 42。
- 覆盖点：字段缺省/往返/v1 有损导出/旧备份导入/非法值拒绝；导入预检白名单与「同 ID 只差计划日算冲突」；
  分组归属与顺序；计划不改象限、不触发紧急性提升、重复写入同一计划不算变更（不 bump 修订号）；
  跨看板与跨象限聚合渲染；勾选完成、安排到今天、取消计划；子项时间面板没有计划行；从首页「更多」进入与返回。
- 中途一次真实回归及修法：把计划行插在截止日期与提醒预设之间会让 390×844 上 `reminder-quick-*` 出界，
  `widget_regression_test.dart` 的 WP25 提醒用例失败（点不中 → 提醒没保存）。计划行改为排在提醒之后、
  说明文字与标题同行，该用例连同全量套件恢复通过；`widget_regression_test.dart` 本身未改动。

## 未验证

- 未在真机与真实窗口渲染：Android 360/412 dp、软键盘展开、200% 字号、明暗主题、屏幕阅读器朗读今天页；
  Windows 窄/宽窗与 Linux 预览同样未做设备检查。以上仅由 1200×900 与 390×844 的 widget 测试覆盖布局存在性，
  不构成溢出或可达性的设备证据。
- 未运行 `integration_test`，未跑打包与 CI 门禁。
- 提醒投递不受本包影响，也未在本包验证。
