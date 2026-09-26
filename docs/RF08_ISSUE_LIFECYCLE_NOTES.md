# RF08 账本问题生命周期（满额/损坏提示的清除时机）

- 分支 `codex/rf08-issue-lifecycle`，worktree `D:\Dev_project\martix-rf08-issue-lifecycle`，起点 `main / 76a8201f460293f46abc52d32e50165e1670bce2`。未 push，未切 main，未改冻结的 React/Tauri/Capacitor，未改 AGENTS/HANDOFF/CHANGELOG/返修计划，未改备份、保存协议、凭据与 Android SAF。固定 SDK `D:\Dev_SDKs\Flutter_3.32.8`（Flutter 3.32.8 / Dart 3.8.1）。
- 改动文件：`matrixflow-native/lib/services/reminder_service.dart`、`matrixflow-native/lib/widgets/reminder_failure_banner.dart`、`matrixflow-native/lib/l10n.dart`、`matrixflow-native/test/rf08_issue_lifecycle_test.dart`（新增默认回归 11 项）。文档只新增本文件。
- 起点干净。新 worktree 的 `flutter pub get` 只改 `windows/flutter/` 三个生成文件的行尾，已 `git checkout` 还原，未纳入提交。

## 残余问题（本包要收口的东西）

RF08 提示包 `78aeaf9` 把 `ledgerIssue` 接进横幅时留下明确缺口：**满额（overflow）与损坏（damaged）两类 issue 一旦发布，服务端没有任何清除路径。** 三种现象同时在：

1. **满额只加不减。** `_noteRefused` 把 `overflow` 按累积的 `refusedRecords` 发布；容量释放之后（`clearPendingJob`、退出重排丢弃记录、挤占耗尽记录）既不重算、也不清除。被拒绝的记录本身已经不在内存也不在磁盘，提示里只留下一个只增不减的数字，而"这条提醒没有被追踪"这一事实没有任何补偿。
2. **损坏在进程内永久停留。** `damaged` 由 `_readPendingJobs` 发布，而清除分支只处理 `kind == read`；`_pendingLoaded` 又保证进程内不再读第二次，所以损坏提示一旦出现就不会消失，即使磁盘上的字节已经被重写干净。
3. **单槽通知会吞掉事实。** `_publishLedgerIssue` 是"最后写入者胜出"：写失败会覆盖 `overflow`/`damaged`，写成功又把通知置空，于是"账本曾拒绝/曾跳过记录"可能在一次写成功后被静默抹掉。

## 生命周期：每种状态的恢复或确认条件

服务不再把 ledger issue 当一次性事件发布，而是用 `_refreshLedgerIssue()` 从**当前状态**推导（优先级 `read > write > overflow > damaged`）。瞬时存储故障优先显示，故障清除后低优先级事实会被重新推导出来，因此不会被更高优先级的行永久吞掉。

- **read（读失败）**：读取成功即清除。沿用原行为，横幅的"重试"调用 `loadPendingJobs()`。
- **write（写失败）**：有一次写落地即清除。沿用原行为。
- **overflow（满额拒绝）**：条件二选一——**拒绝的工作被重新追踪**，或**它所属的提醒已不再被任务数据背书**。
  - 拒绝时不再只累加计数：`_rememberRefused` 把 `ReminderPendingJob` 本体（kind / notificationId / taskId / subtaskId / triggerAtMs / attempts）记进 `_refusedJobs`。身份是恢复的前提。
  - 容量一旦释放（`clearPendingJob`、`clearPendingForNotification`、reconcile 丢弃记录、`_evictExhaustedRecord` 腾位）就调用 `_drainRefusedJobs()`，把拒绝的工作按 64 项上限放回账本；`reconcilePending` 在轮首（先清"不再背书"的拒绝）和轮尾各 drain 一次，所以**一轮里被释放的槽位会交回被拒绝的提醒**，而不会留到"没人再管"。
  - `reconcilePending` 用 `_noLongerBacks()` 剔除数据不再背书的拒绝；该函数就是原有 `outdatedSchedule` / `replacedGhost` 规则本身（已抽成同一函数，主循环与拒绝清理共用，避免两处规则漂移）。
  - 整表清空 `clearAllPendingJobs()` 是用户显式全清，拒绝集合一并丢弃。
  - overflow 行**仍然没有按钮**：容量是事实，服务会在槽位释放时自行收敛，按钮改变不了它。
- **damaged（跳过不可解析记录）**：**显式的账本重写落地**（`retryPendingLedger()`，横幅上叫"修复列表"）或**之后一次读到干净字节**即清除；**后台偶然写入不清除**。
  - 理由：损坏条目无法重建，唯一诚实的"确认"是用户按下修复——把可读记录写回、放弃不可读条目。若让任意后台写入清除它，应用启动时的第一次重写会让提示在用户看到之前就消失。
  - 重启语义可验证：期间发生过重写 → 重启读到的字节干净 → 不再报告；没有重写 → 再次读到损坏 → 提示重新出现（两个方向都有测试）。

## 反例：修前 vs 修后

回归文件 `matrixflow-native/test/rf08_issue_lifecycle_test.dart`（合成任务、内存/种子账本替身、内存提醒服务；无凭据、无真机、不声称送达）。

**修前实测方式**：同一个 worktree 里用 `git stash` 收起 `lib/` 改动（保留新增测试文件）后分别跑定向与全量，跑完 `git stash pop` 复原。最终版测试只使用修前已存在的 API，所以修前能正常编译并给出**断言失败**，不是编译错误。

修前（`76a8201` 的 lib）：`flutter test --no-pub test/rf08_issue_lifecycle_test.dart` → **`+3 -8: Some tests failed.`**，8 条反例：

1. 容量释放后再次协调：`Expected: null / Actual: <ReminderLedgerIssue(overflow, errorKind: null, count: 1)>` —— 满额横幅不反映"槽位已经回来了"。
2. 协调轮自己释放槽位：`Expected: true / Actual: <false>` —— 被拒绝的提醒没有被交回账本。
3. 提醒已完成、数据不再背书：`Expected: null / Actual: overflow count 1` —— 拒绝提示挂在已经不存在的提醒上。
4. 整表清空：`Expected: null / Actual: overflow count 1` —— 清空后拒绝提示仍在。
5. 显式重写账本：`Expected: null / Actual: damaged count 1` —— 修好字节也不清除。
6. 横幅损坏行：`Expected: exactly one matching candidate / Actual: Found 0 widgets with key [<'repair-reminder-ledger'>]` —— 损坏状态没有任何可执行入口。
7. 横幅满额行：`Expected: no matching candidates / Actual: Found 1 widget with key [<'reminder-ledger-overflow'>]` —— 服务收敛后行不消失。
8. `Expected: not null / Actual: <null>`，`en is missing the repair label` —— 新按钮文案缺键。

修前另有 3 条已经通过，故意保留为护栏，防止本包把既有行为改坏：损坏账本未修复则重启后再次报告；损坏提示不因偶然写入消失；修复写不进去时报告 `write` 而不是假装成功。

修后：同一文件 **`+11: All tests passed!`**。

## 覆盖矩阵（`test/rf08_issue_lifecycle_test.dart`，11 项）

- **满额→容量释放→再次协调**：显式释放一个槽位后 `reconcilePending`，溢出提示消失、被拒绝的提醒重新出现在 `pendingJobs` / `scheduleFailures` 并被 `retried`；通道恢复后同一条记录被 `recovered` 并清空；`refusedRecords` 仍只计一次。
- **协调轮自己释放槽位**：一轮 reconcile 丢弃 64 条无数据背书的填充记录，被拒绝的提醒在这一轮就被交回账本，下一轮被 `recovered`。
- **数据不再背书**：提醒完成 → 拒绝提示消失、`retried` 为 0、不产生幽灵排程。
- **整表清空**：内存、拒绝集合、提示三者一致为空。
- **损坏生命周期**：显式重写 → 提示清除、落盘字节不再包含不可解析项、重启后不再报告且可读记录仍在；偶然写入 → 提示保留（字节已经干净）、重启后不再报告；未修复 → 重启后再次报告 `count = 1`；重写失败 → 按优先级报告 `write`，修复成功后归零。
- **横幅**：损坏行有独立 key 的修复按钮（不是 `retry-reminder-ledger`）且真的清除该行；满额行没有任何按钮、在服务收敛后行消失、同时既有的"排程失败"行如实呈现（未影响既有语义）。
- **文案**：`reminderLedgerRepair` 在 en/zh/ja 均非空、不含送达承诺禁词（`os27_copy_test` 另检查三语键与占位符对齐）。

## 契约与实现边界（需集成人知悉）

- `ledgerIssue` 由"最后写入者胜出"改为**从状态推导**，优先级 `read > write > overflow > damaged`。横幅仍是单槽（每种账本问题一行，未改成多行），但低优先级事实不会被高优先级故障永久吞掉。
- 新增**行为**（未增删公开 API）：拒绝时保留 `ReminderPendingJob` 身份；`_drainRefusedJobs` 在槽位释放时把拒绝的工作放回账本；`retryPendingLedger()` 落地时清除 `damaged`；`clearAllPendingJobs()` 丢弃拒绝集合。
- **保留**：64 项上限 `maxPendingJobs`、重试预算（`maxAutomaticRetries = 5`、7 天 TTL、`firstFailedAtMs` 世代语义）、退出账本屏障（`flush` / `retrySave` 的 `includeReminderLedger` 与 `hasUnlandedLedgerWrites`）；既有三语提示文本 `reminderLedgerUnreadable` / `WriteFailed` / `Full` / `Damaged` **一字未改**，只新增按钮文案 `reminderLedgerRepair`。
- `reconcilePending` 的"数据不再背书"判定抽成 `_noLongerBacks()` 后被主循环与拒绝清理共用，规则本身未变（os17 与 RF08 既有断言全部保留通过）。
- 未改共享探针、未改其它包的测试文件、未改备份/保存协议/凭据/Android SAF。

## 验证（固定 Flutter 3.32.8）

- **基线**（同 worktree、`git stash` 收起 lib、临时移出本包测试文件后测量）：`flutter test --no-pub` **776/776**，与 HANDOFF 记录的 76a8201 集成态一致。
- **定向**：`test/rf08_issue_lifecycle_test.dart` **11/11**（修前同一文件 **3/11**）。
- **相邻回归**：`rf08_issue_lifecycle` + `rf08_reminder_retry` + `rf08_ledger_ui` + `os17_reminder` + `windows_reminder` + `os27_copy` + `os12_date_reminder` + `reminder_service` **116/116**。
- **共享探针**（断言未改）：`test/review/rf08_reminder_retry_probe.dart` + `test/review/os_final_review_probe.dart` **9/9**。
- **默认全量**：`flutter test --no-pub` **787/787**（776 + 本包 11），`flutter analyze --no-pub` **0 issues**。测试串行运行，RF09 墙钟基准未与全量并发。

## 未测与限制（不夸大）

- **没有任何真机/模拟器验证。** 本包只改提醒账本的状态与横幅文案，全部证据来自合成任务、内存账本替身与内存提醒服务；不声称 Android 未来提醒、Windows 运行中提醒或通知点击回流已验收，也不声称送达率。
- `_refusedJobs` 在同一进程内保留被拒绝记录的身份，规模受"本次进程中被拒绝的不同提醒条数"限制；账本本身仍严格受 64 项上限约束。`reconcilePending` 每轮会剔除数据不再背书的拒绝，所以长期运行时集合会随提醒生命周期收敛。没有为这个集合另设上限，也没有为它做内存量级测量。
- 拒绝工作被 drain 回账本时按插入顺序回填，而读到的超上限旧账本当初是"保留最新、其余作为拒绝保留"（`stored` 已按 `firstFailedAtMs` 降序排过）。也就是槽位释放后可能先回填较旧的记录；两者都能被原来的重试预算与 TTL 约束，但优先级取舍未再做产品评估。
- 单槽通知意味着同一时刻界面只显示一种账本问题；如果 read/write 故障与 overflow/damaged 同时成立，用户看到的是优先级最高的那一行。本包只保证低优先级事实不会丢，不保证同时呈现。
- `hasUnlandedLedgerWrites` 仍是瞬时快照，退出屏障语义未改。
- 文案只在单元/widget 层断言存在性、占位符与禁词；三语在真实字号、长文本与 `maxLines: 3` 截断下的可读性未做设备端检查，横幅仍沿用既有的单行截断样式。
- 本包未运行 `npm`/React 构建（冻结端），未做正式签名或发布，未 push。
