# RF08 — 提醒重试边界（源码包交接）

- 分支 `codex/rf08-reminder-retry`，worktree `D:\Dev_project\martix-rf08`，起点 `main / ac732b13b4488fd8751ebcf5bcb8c4736f882340`。未 push，未切换 main，未改冻结的 React/Tauri/Capacitor，未改 AGENTS/HANDOFF/CHANGELOG/返修计划。固定 SDK `D:\Dev_SDKs\Flutter_3.32.8`。
- 改动文件：`lib/services/reminder_service.dart`、`lib/storage.dart`、`lib/screens/matrix_screen.dart`、`test/rf08_reminder_retry_test.dart`（新增默认回归）、`test/review/rf08_reminder_retry_probe.dart`（新增反例探针）、`test/os17_reminder_test.dart`（一条契约更新，见下）。

## 根因

审查记录的三条源码风险都成立，且互相叠加：

1. **启动重试会重置预算。** `recordScheduleOutcome` 在重排失败时用 `attempts: 0` 新建记录，`updatedAtMs` 直接取当前时间。Store 启动顺序是 `rescheduleAllFuture` → `reconcilePending`，所以每次启动都先写一条全新记录（`attempts=0`），随后 reconcile 再 `withAttempt` 变成 1。`maxAutomaticRetries`（5）永远达不到，持续失败会在每次启动重获完整预算；`firstFailedAtMs` 这个概念当时也不存在，TTL 只有 `updatedAtMs`，等于"第一次失败时间"被每次重试刷新。
2. **账本落地是无声且未被等待的。** `_persistPendingJobs` 是 fire-and-forget 链，`SharedPreferencesReminderLedgerStore.read/write` 各自 `catch (_) {}` 吞掉异常；读失败被当成"没有待办"，写失败没有任何完成结果。退出屏障（`flush`）不知道账本是否落盘，因此可以在提醒重试记录丢失后报告"已保存"。
3. **满额与清空都不可解释。** 64 项满额时 `trackPendingJob` 直接 `return`，调用方无法区分"已记录"和"被丢弃"；`clearPendingJob` / `clearPendingForNotification` 只清内存，若此时启动读取还在飞行中，合并会把记录复活。

## 修复

**预算与世代（reminder_service.dart）**

- `ReminderPendingJob` 新增 `firstFailedAtMs`（该世代第一次失败的时间）与 `exhausted`，并持久化。`withAttempt` 现在把 `attempts + 1`、`firstFailedAtMs`（首次写入后保持不变）、`updatedAtMs`（最近一次）一起更新。
- 世代判定 `coversSameReminder`：同一任务/子任务且 `triggerAtMs` 相同即为同一世代。`failedScheduleJob` / `failedCancelJob` 在同一世代内累加次数并保留 `firstFailedAtMs`；只有**触发时间真正改变**或**用户显式请求**（新增 `userInitiated`）才开新世代、重置次数与首败时间。
- TTL 改从 `firstFailedAtMs` 计算，重试不再延寿；旧版本账本缺该字段时回落到 `updatedAtMs`，`attempts >= maxAutomaticRetries` 的旧记录读入即视为 `exhausted`。
- 预算耗尽不再静默丢弃：`reconcilePending` 标记 `exhausted` 并保留记录（继续出现在 `scheduleFailures` / `cancelFailures` 横幅里），`spentBudgetSchedule` / `spentBudgetCancel` 让耗尽世代不再打扰平台，但账本不动，等用户改提醒或点重试。
- 每轮重建只计一次尝试：`beginReminderRebuild` 先读账本再清 `_attemptedInFreshPass` 并置 `_rebuildPass`；`recordScheduleOutcome` 只在重建轮内登记，`reconcilePending` 消费该集合，普通编辑/重试不会被误判为"本轮已试"。报告新增 `exhausted` / `skipped` / `rejected` 与 `needsAttention`。

**账本完成结果（reminder_service.dart）**

- 新增 `ReminderLedgerWriteResult`（`flushPendingLedger()` 返回，含 `writes`/`success`/`errorKind`）与 `ReminderLedgerUpdate`（`recorded` / `refreshed` / `rejected`，`trackPendingJob` 返回）。`SharedPreferencesReminderLedgerStore` 不再吞异常。
- 读失败不再等于"没有待办"：发布 `ledgerIssue`（`read`/`write`/`overflow`/`damaged`）、不置 `_pendingLoaded`，后续调用会重试。写失败记录 `_lastWriteError` 并可由 `retryPendingLedger()` 重发。
- 满额时先尝试挤掉一条 `exhausted` 记录给新工作腾位；没有可挤的才返回 `rejected`、累加 `refusedRecords` 并发布 `overflow`。读入超过上限的旧账本保留最新记录并报告差额；损坏条目计入 `damaged`。
- 清空与异步 load 相交：`_clearEpoch` 让飞行中的读取知道整表清空已发生，`_clearedWhileLoading` / `_clearedSuffixesWhileLoading` 在合并后重新应用，保证清空同时到达内存与磁盘。

**Store 启动协调与退出屏障（storage.dart / matrix_screen.dart）**

- `reconcileReminders()` 改为：先 `loadPendingJobs()`（预算必须先读入），再 `rescheduleAllFuture`，再 `reconcilePending`，最后 `flushPendingLedger()`，并把结果存入 `lastReminderReport`（返回值也变成 `ReminderReconcileReport`）。
- `updateTask` 仅在 `reminderAt` 真正变化时传 `userInitiated: true`；改标题、改象限等无关编辑继续消耗原预算。`retryReminder` / `retryReminderCancellation` 是用户请求，开启新世代。
- `flush({includeReminderLedger})` / `retrySave({includeReminderLedger})`：只有显式开启且确有未落盘写入（`hasUnlandedLedgerWrites`）时才等待账本屏障，失败返回 `SaveResult(false, …)`。`matrix_screen` 的退出协调器开启该开关，于是"账本写失败"会走既有的保存失败/重试/放弃选择，而不是报告干净退出。备份导出等数据流保持纯数据契约不变。
- **收口时补的缺口**：`retrySave` 在账本重试仍失败时 `return flush()`，把 `includeReminderLedger` 丢了，于是"永久写不进去"退化成"库本身保存成功"，正好违反本包要守的"失败不得静默报成功"。现改为返回带账本屏障的结果，末尾的 `flush` 同样传递该开关（凭据重试期间可能新入队账本写入）。
- **收口时补的顺序**：`reconcilePending` 原先在判断"当前任务数据是否仍背书这条记录"之前就短路 `exhausted`，于是本包把"耗尽即静默丢弃"改成"耗尽即保留并持续上报"之后，一个用户已经删除/完成的提醒会被耗尽记录永久留在账本里继续弹横幅——是本次设计改动带回来的新问题。现改为先判定过期重排/被替换的幽灵取消并丢弃，再考虑预算；取消类记录的"数据不再背书"仍是"该 id 被重新排程"，幽灵通知本身未确认前不能丢。

## 反例：修前 vs 修后

探针 `test/review/rf08_reminder_retry_probe.dart`（合成任务、内存账本、假插件，无凭据、无真机）。**修前结果已在 `main / ac732b1` 的独立 detached worktree 里重新实测**（`flutter test --no-pub test/review/rf08_reminder_retry_probe.dart` → `+0 -2: Some tests failed.`），不是引用报告结论：

- `RF-R08a` 六次"加载→重排失败→reconcile→持久化→重启"：期望 `attemptsPerStart = [1,2,3,4,5,5]`，**实测 `[1,1,1,1,1,1]`**（`Which: at location [1] is <1> instead of <2>`）；`schedulesPerStart` 每轮都是 1，说明预算每次启动被清零且仍在反复打扰平台。
- `RF-R08b` 七次启动后期望 `attempts = 5`（预算耗尽），**实测 `1`**；因此"有界重试已闭环"的说法在源码上不成立。

同一文件在修复后：`00:00 +2: All tests passed!`，`attemptsPerStart = [1,2,3,4,5,5]`，第六次启动 `schedulesPerStart = 0`（耗尽后不再打扰平台），`firstFailedAtMs` 全程不变。

收口时新发现的两个缺口都用默认回归自身复现，先红后绿：

- `a retry that still cannot land the ledger is not a clean save`：改 `retrySave` 前实测 `Expected: false / Actual: <true>`（账本永久写失败仍报保存成功）。
- `a spent budget does not keep a reminder the data no longer backs`：改 `reconcilePending` 顺序前实测 `report.dropped` `Expected: <1> / Actual: <0>`（任务已完成，耗尽记录仍留在账本与横幅里）。

## 覆盖矩阵（默认回归 `test/rf08_reminder_retry_test.dart`，20 项）

- 六次冷启动预算单调增长、首败时间不前移、单轮只计一次尝试；耗尽后重启仍读回 `attempts=5 / exhausted`，且横幅继续可见。
- 新世代的三个合法入口：无关编辑不重置；`userInitiated` 重试重置；改期替换旧记录而不新增。
- 不复活：删除、完成、改期三种情况 `dropped=1`、`retried=0`、平台零调用；通道恢复后记录被清空、账本写回 `null`；**预算已耗尽的记录同样被丢弃，不留悬挂横幅（收口时补）**。
- 账本落地：延迟写入必须被 `flushPendingLedger` 等待（提前完成即失败）；写失败 → `ledgerIssue=write` 且退出屏障 `success=false`，修复存储后 `retrySave` 成功并清除 issue；**账本永久写失败时 `retrySave` 依旧 `success=false` 并保留 issue（收口时补）**；读失败被报告且下轮重试；损坏条目被报告且可读记录照常载入。
- 64 项满额：第 65 条返回 `rejected`、`refusedRecords=1`、`ledgerIssue=overflow`，内存长度不变；`exhausted` 记录被挤掉为新工作腾位且不产生 overflow。
- 清空与异步 load 相交：单键清空与整表清空都在读取飞行中发生，最终内存、磁盘、重启后三者一致为空。
- 取消重试：重复失败跨重启累积到耗尽，`notificationId` / `taskId` / `boardId` 保持正确身份；耗尽后不自动重试，用户显式重试才清除幽灵通知。
- Store 协调：启动 pass 继续已存预算并产出报告；耗尽后用户改期会真正重新排程；删除任务后不留任何重试工作。

## 验证

- 定向：`test/rf08_reminder_retry_test.dart` **20/20**；`test/review/rf08_reminder_retry_probe.dart` **2/2**（修前红、修后绿，同一文件）。
- 回归：`os15_desktop_exit` + `os08_os09_credential` + `os17_reminder` + `reminder_service` + `windows_reminder` + `rf03_credential_close` **79/79**；共享探针 `test/review/os_final_review_probe.dart` **7/7**（RF-R01…RF-R07 断言未改，本包实测确认）。
- 默认全量 `flutter test --no-pub` **720/720**（基线 `ac732b1` 实测 **700/700** + 本包 20），`flutter analyze --no-pub` **0 issues**。
- 一次全量里 `task_query_test.dart` 的 1,000 任务查询墙钟基准超时失败（实测 638ms / 阈值 200ms）：那是与基线全量并行跑造成的 CPU 争用，单独复跑同一套件 **720/720** 通过。该基准属 RF09 关注面，本包未触碰查询路径。

### 契约变更（需集成人知悉）

`os17_reminder_test.dart` 的 `automatic retries are bounded` 断言已按新契约更新：预算耗尽后 `dropped` 从 1 变为 0、`exhausted` 为 1，记录保留在账本且 `scheduleFailures` 仍可见，后续 pass 不再调用平台。这是本包有意改变的对外行为（"耗尽"从静默丢弃改为显式保留），断言其余部分与理由未动。

## 未测与限制（不夸大）

- **没有任何真机/模拟器验证。** Android 未来排程/取消、精确闹钟降级、Windows 运行中提醒、通知点击回流，全部只在合成插件替身上验证过。本包不声称平台通知可靠，也不声称真实设备上的送达率。
- `hasUnlandedLedgerWrites` 是一个瞬时快照：屏障只在调用瞬间确有未落盘写入时等待。极端情况下"检查后、写入前"新入队的写不会被这一次 `flush` 覆盖，但退出前的 `reconcileReminders` 与后续 flush 仍会补上；这是有意的取舍，避免为不存在的写入拖慢每次退出。
- 账本溢出策略（挤掉最旧 `exhausted`）是本包的设计选择，64 项上限与 7 天 TTL 沿用 OS17 既有常量，未重新评估这些数值是否仍适合真实使用规模。
- `ledgerIssue`（读/写/满额/损坏）与 `refusedRecords` 目前**只有 API 与测试消费，界面上无人监听**：`reminder_failure_banner.dart` 只读 `scheduleFailures` / `cancelFailures`。因此"退出不谎报成功"已成立，但"账本写不进去/满额"还没有面向用户的文案，需要 l10n 三语新键，留给 UI/RF10 处理，本包不顺手扩 UI。
- `retryCredential` 里仍有一处不配对的 `rescheduleAllFuture(tasks)`（没有后续 `reconcilePending`），会把 `_rebuildPass` 留在 true 并累积 `_attemptedInFreshPass`。实测无用户可见影响：Store 的每次启动协调都会先 `beginReminderRebuild()` 清空该集合，所以污染不会被消费；未改动，登记为潜在异味。
- 恢复为 `exhausted` 的记录会留在账本里直到用户动作或数据不再背书，因此一个永久失效的提醒会持续占用一个槽位；上限保护依赖上述挤占策略。
- 新 worktree 的 `flutter pub get` 只改了 `windows/flutter/` 三个生成文件的行尾，已 `git checkout` 还原，未纳入提交。
- 本包未运行 `npm`/React 构建（冻结端），未做正式签名或发布，未 push。
