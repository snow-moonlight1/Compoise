# OS17 实施记录：提醒的真实失败与取消重试

日期：2026-09-25。包号：**OS17**（对应审查报告 F14）。状态：**已实施**；Android 与 Windows 真实通知**均未实测**。

## 1. 接手与边界

- 基线：`main / cc9ce2765dc90211d58cfc487c8b9c2bfc442124`，独立 worktree `D:\Dev_project\martix-wt-os17`，分支 `os17-reminders`。工作区在接手时干净；`matrixflow-native/windows/flutter/generated_*` 仅因 `flutter pub get` 出现行尾差异，内容未变且未提交。
- 按计划第 5 节使用固定 SDK `D:\Dev_SDKs\Flutter_3.32.8`（Flutter 3.32.8 / Dart 3.8.1）。未新增或改变依赖：`shared_preferences` 已是现有依赖。
- 只改本包文件：`lib/services/reminder_service.dart`、`lib/storage.dart` 的提醒调用与重试入口、`lib/widgets/reminder_failure_banner.dart`、`lib/screens/settings_screen.dart` 的提醒测试区、`lib/l10n.dart`，以及测试与本记录。未修改桌面退出、`matrix_screen.dart`、`AGENTS.md`、`HANDOFF.md`、`ARCHITECTURE.md`、`CHANGELOG.md` 和开源准备计划（公共文档留给集成人统一收口）。未开始 OS20。

## 2. 三类结果被分开表达

### 权限：查不到就说查不到

- `ReminderPermissionStatus` 新增 `unknown`。
- Android：`resolvePlatformSpecificImplementation` 为 `null` → `unsupported`；`areNotificationsEnabled()` 或 `canScheduleExactNotifications()` 返回 `null` → `unknown`；查询抛异常 → `unknown`。原来异常会返回 `granted`，这是 F14 的掩盖点，已删除。
- Windows：插件没有可查询用户通知设置与专注助手状态的接口，因此返回 `unknown`；只有 `initialize` 明确返回 `false` 时才是 `unsupported`。原代码在 Windows 直接返回 `granted`，并在设置页显示“Windows 桌面 Toast 通知正常可用”。
- `requestPermission()` 从 `Future<bool>` 改为返回真实的 `ReminderPermissionStatus`（请求后重新探测），不再把“无法判断”写成成功。`checkPermission()` 现在缓存到 `observedPermission`，供横幅与提示复用；未探测过时是 `null`，不编造状态。
- `docs/REMINDERS_DESIGN.md` 的权限语义不变：被拒绝仍然保存提醒，只是如实提示。

### 排程失败

`scheduleReminder` 返回 `ReminderScheduleResult`，状态区分 `scheduled`、`scheduledInApp`、`displayed`、`superseded`、`expired`、`unavailable`、`failed`，并带 `notificationId` 与 `errorKind`。

- `scheduledInApp` 是 Windows 的既有降级路径：系统拒绝 `zonedSchedule` 时仍会武装一个应用内定时器。它不是失败也不是可持久重试的记录，因此**不写重试账本**，避免“系统排程 + 进程内定时器”两条路各发一次。定时器触发时若 `show` 失败，则按真实失败入账。
- 只有 `failed` / `unavailable` 进入可重试账本；`superseded`（更新一代的编辑或取消已接管）与 `expired`（超出 5 分钟宽限）会清掉同一条记录，不会既补发又残留。
- 原有的代际（`_revision`）与串行队列保护保留：入队前和系统调用返回后都检查代际，被接管时补偿一次 `cancel` 再让下一条操作开始。

### 取消失败

`cancelReminder` 返回 `ReminderCancelResult`（`cancelled` / `unavailable` / `failed`）。以前取消异常只 `debugPrint`，任务已从库里删除而系统通知可能还在，这就是“幽灵提醒”。现在：

- 服务记住本进程认为系统仍持有的通知（`trackedReminders`，上限 512）。
- 取消失败 → 记录 `cancel` 类待办；`cancelAll()` 整体失败 → 退化为逐个 `_cancelNow()`，每个失败各自入账，可跨重启重试。
- 取消成功后同时清掉该通知 id 的排程与取消记录；重新排同一个 id 会取代旧通知，因此也一并清掉待取消记录。

## 3. 可重试记录、重启补偿与边界

- 新增本地键 `matrixflow-reminder-pending`（`SharedPreferencesReminderLedgerStore`）保存待办账本：`reschedule` 与 `cancel` 两类，按 `kind:notificationId` 唯一，只含 board/task/subtask id、触发时刻、尝试次数、最后更新时间与错误类别。它不是用户数据，不进备份、导入白名单或 OS05 恢复副本；JSON 读坏了只会被忽略。
- 启动协调：`Store.reconcileReminders()` 先按任务数据 `rescheduleAllFuture`，再 `reconcilePending`。`init`、`discardDamagedStartupData`、凭据迁移恢复和覆盖式导入（先 `cancelAll`）都走这条路径，因此上一次运行留下的失败能在下一次启动补做。
- 有界：自动重试最多 5 次（`maxAutomaticRetries`），记录超过 7 天或时间戳异常即丢弃；账本条目上限 64。用户点“重试”或再次编辑会重置预算，不受历史失败次数卡死。
- 不重复排程：账本按通知 id 唯一；重试与启动排程都经过同一个 `scheduleReminder`，同一 id 在系统侧互相取代；代际检查防止迟到的旧请求覆盖新状态。
- 不复活已删除的提醒：补偿前用当前任务数据校验来源，任务不存在/已完成/提醒被改走/提醒已删除/时刻已过，一律丢弃记录而不是补发；被重新加回的提醒会取代幽灵通知而不是先取消。
- 快速编辑与删除保持串行：每次 `scheduleReminder`/`cancelReminder` 都推进代际，迟到的系统答复会被补偿取消。
- 日志与错误类别只写异常类型或 `PlatformException/<code>`（去空白），不再打印 `toString()`；持久记录不含任务标题与备注，专项测试对此做了断言。
- 账本落盘是“触发后不等待”：内存状态与 UI 通知同步更新，磁盘写排队进行。因此提醒结果不依赖存储是否完成，也不声称 SharedPreferences 提供掉电原子性。
- 集成修正：首次账本读取期间的其他调用等待同一 Future，避免新失败先写入并覆盖旧记录；全量取消等待在途读取后再清空。新增延迟读取回归测试。

## 4. 设置页与横幅

- 测试提醒（Windows 与新增的 Android 入口）共用 `_sendTestReminder`：先真实探测权限，再发送并**按平台返回值**反馈——接受、仅应用内武装、被拒绝分别给不同文案；权限非“已授予”时把状态一并说明。以前无论结果都弹“测试通知已发送”。测试提醒使用 `recordRetry: false`，不会在账本里留下指向合成任务的记录。
- 权限对话框改用 `_permissionReport`，五种状态全覆盖；“请求权限”之后显示重新探测到的真实状态，而不是无条件认为成功。删除了不再成立的 `windowsPermissionActive` 文案。
- `ReminderFailureBanner` 拆成三块互不掩盖的提示：排程失败（重试=重新排程）、取消失败（重试=重新取消），以及只有在本进程真探测到 `unknown` / `unsupported` 且存在待办时才出现的权限说明。旧的单一横幅会把取消失败显示成“任务已保存，但排程失败”。
- 三语字典同步：新增 `permissionUnknown`、`permissionUnsupported`、`reminderCancelFailed`、`reminderTestInAppOnly`、`reminderTestFailed`、`reminderTestBody`，移除 `windowsPermissionActive`。

## 5. 验证

- 专项 `test/os17_reminder_test.dart`：**23/23** 通过，全部使用合成数据与假插件，覆盖：权限 null/异常/无实现/Windows 未初始化与明确拒绝、Android 各权限组合、请求后的真实状态、排程失败与重试清错、取消失败与独立记录、`cancelAll` 退化为逐条、测试提醒不入账、重启后补偿、二次补偿不重复排程、已删除与已完成不复活、改时刻只留一条新记录、有界重试并在越界后停止尝试、取消记录跨重启补做、Store 启动协调接线、删除时取消失败留记录、横幅两类行分开与重试清错、权限未知提示。
- 默认全量 `flutter test --no-pub`：**479/479** 通过（接手基线为 456/456，新增本包 23 项）。`flutter analyze --no-pub`：**0 issues**。
- 既有回归按要求调整的地方只有两类：`test/reminder_service_test.dart` 与 `test/windows_reminder_test.dart` 中对 Windows “granted / 正常可用”的旧断言改为 `unknown`（正是要修的掩盖行为），以及签名变更后的两处测试替身（`Future<bool> requestPermission` → 返回状态）；`windows_reminder_test.dart` 的测试通知断言改为 `textContaining`，因为诚实文案现在会附带权限状态。`test/foundation_second_regression_test.dart` 的 SR07（排程失败显示与重试清错）与 S01（取消与在途排程竞争）未改断言即通过；S01 曾在实现过程中因等待账本磁盘写而挂起，已改为提醒结果不依赖存储后恢复。
- **未测**：Android 真机通知、精确闹钟与重启后的系统排程；Windows 真实托盘/通知横幅与专注助手行为；双端构建（本包未新增依赖与平台配置，仅使用已有 `shared_preferences`）；真实断电/强杀场景。这些不能由单元测试代替，仍按未验收处理。测试没有使用用户备份、真实密钥或真实任务数据。

## 6. 残余限制

- 权限“未知”仍是能力缺口而非缺陷修完：插件不提供 Windows 通知设置查询，因此只能显示未知并让用户用测试提醒验证。
- Windows 的 `scheduledInApp` 降级依赖应用仍在运行；进程退出即不会触发。这是既有设计，本包只把它与失败区分开，未改成新的后台保活手段。
- 账本记录本身仍靠 SharedPreferences 落盘：写盘失败或系统在写入窗口内崩溃，最多是下一次启动无法补偿，不会破坏任务数据；OS06 的双槽保存协议未参与该键。
- 多实例竞争（OS16）和退出时的保存协调（OS15）不在本包范围：两个实例仍可能各自操作同一批通知 id。
- Store 对提醒服务的直接调用（`ReminderService.instance`）保持不变，命令边界与只读快照收口留给 OS20；`reconcileReminders()` / `resetAllReminders()` 已可作为那一层的注入点。

## 7. 改动文件

- 产品代码：`matrixflow-native/lib/services/reminder_service.dart`、`matrixflow-native/lib/storage.dart`、`matrixflow-native/lib/widgets/reminder_failure_banner.dart`、`matrixflow-native/lib/screens/settings_screen.dart`、`matrixflow-native/lib/l10n.dart`。
- 测试：新增 `matrixflow-native/test/os17_reminder_test.dart`；调整 `test/reminder_service_test.dart`、`test/windows_reminder_test.dart`、`test/foundation_regression_test.dart`、`test/review/wp28_review_probe.dart`。
- 文档：仅本文件 `docs/OS17_NOTES.md`。

## 8. 下一位接手者需要知道的

- 可领取：OS20（Store 命令边界与修订号一致性，依赖本包的提醒结果类型与 `reconcileReminders()` 注入点）；OS19 可在使用设置页提醒区之外继续（设置页本包只动提醒段）。
- 公共文档已在 2026-09-25 集成时更新：计划状态、`HANDOFF.md`、`ARCHITECTURE.md` 的提醒契约、`CHANGELOG.md` 顶部条目和 `docs/REMINDERS_DESIGN.md` 的历史 API 说明。新增本地键为 `matrixflow-reminder-pending`，旧 `windowsPermissionActive` 文案已移除。
- 若要关闭“未测”项：需要 Android 真机（通知权限、精确闹钟、重启后台排程）与 Windows 实机（横幅、专注助手、托盘保活下 `scheduledInApp` 行为）各一轮人工验证，并记录设备与系统版本。
