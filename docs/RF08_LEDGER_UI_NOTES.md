# RF08 账本可见性（UI 包交接）

- 分支 `codex/rf08-ledger-ui`，worktree `D:\Dev_project\martix-rf08-ledger-ui`，起点 `main / 22aa43d6f88bcbbb9efd778aef23e023454975e0`。未 push，未切 main，未改冻结的 React/Tauri/Capacitor，未改 AGENTS/HANDOFF/CHANGELOG/返修计划。固定 SDK `D:\Dev_SDKs\Flutter_3.32.8`（Flutter 3.32.8）。
- 改动文件：`matrixflow-native/lib/widgets/reminder_failure_banner.dart`、`matrixflow-native/lib/l10n.dart`、`matrixflow-native/test/rf08_ledger_ui_test.dart`（新增，8 项）。**未改** `lib/services/reminder_service.dart`、`lib/storage.dart` 及任何其他并发包文件，也未改既有测试与共享探针。
- 起点干净。新 worktree 的 `flutter pub get` 只改 `windows/flutter/` 三个生成文件的行尾，已 `git checkout` 还原，未纳入提交。

## 目标

RF08 源码包留下的是明确缺口（原记录：`ledgerIssue` 与 `refusedRecords` 只有 API 与测试消费，`reminder_failure_banner.dart` 只读 `scheduleFailures`/`cancelFailures`）：账本读失败、写失败、64 项满额、损坏条目都不会出现在界面上。本包只补这层用户可见的提示与恢复路径，不重开服务层设计。

## 实现

**横幅接入（reminder_failure_banner.dart）**

- `build` 增加最外层 `ValueListenableBuilder<ReminderLedgerIssue?>`（`store.reminderService.ledgerIssue`），并把原三条链（`scheduleFailures` → `cancelFailures` → `observedPermission`）移入同一 State 的 `_failures(store, ledgerIssue)`，行为与渲染顺序不变。
- 四个状态各有一行，行 key 分别 `reminder-ledger-read` / `-write` / `-overflow` / `-damaged`，由 `_ledgerKey` 显式映射（不依赖枚举名，避免改名后测试静默失配）。
- 文案由 `_ledgerMessage` 从三语字典取值：读失败、写失败为整句；满额与损坏按 `{count}` 填充，满额另按 `{cap}` 填充 `ReminderService.maxPendingJobs`（当前 64），所以界面上的数字来自常量而不是复制品。
- `_ledgerRetry` 只给可操作的状态配按钮：`read` → `service.loadPendingJobs()`（服务只会在读成功后清除该 issue），`write` → `service.retryPendingLedger()`（写落地即清除）。`overflow` / `damaged` 返回 null，`_row` 随之不渲染按钮——账本已满、磁盘上已有损坏字节都是事实，给一个改变不了结果的“重试”只会误导。
- `_row` 的 `names` 与 `onRetry`/`buttonKey` 改为可选，原有排程/取消两行与权限提示的调用点与语义未变。

**文案（l10n.dart）**

- 新增 `reminderLedgerUnreadable`、`reminderLedgerWriteFailed`、`reminderLedgerFull`、`reminderLedgerDamaged`，en/zh/ja 三语齐全，占位符一致（`reminderLedgerFull` 用 `{count}`+`{cap}`，`reminderLedgerDamaged` 只用 `{count}`），沿用 `os27_copy_test.dart` 的键对齐与占位符对齐检查。
- 措辞只描述本机“提醒重试记录”的读写与排队结果，例如读失败写“仍未再次尝试的提醒可能不在这个列表里”、写失败写“应用关闭后可能丢失”。**没有任何句子承诺系统会送达通知**；新增测试另设禁词检查（`100%`/`绝对`/`絶対`/`必ず届`/`一定送达`/`guaranteed`/`保証します`）。

## 恢复语义（重要）

- 读失败：`ReminderService._readPendingJobs` 在读取成功后清 `read` issue；下一次成功读取即让横幅消失。测试走真实路径（修好账本后点“重试”）。
- 写失败：`_writeLedger` 写成功后清 `write` issue；测试同样走真实路径，并额外断言写失败期间 `store.flush(includeReminderLedger: true).success == false` —— 退出保存结果没有被这次 UI 改动放松。
- 满额 / 损坏：服务端当前**没有**清除路径（`_noteRefused` 与损坏上报一旦发布，只有读/写成功会按 kind 清除，这两种 kind 不匹配）。本包文件所有权不含 `reminder_service.dart`，因此 UI 不自造“已读/忽略”状态，也不伪造清除；测试改为直接撤回 `ledgerIssue`，证明控件本身只跟随 notifier、不缓存上一次的行。这是本包的**残余限制**，如需“满额后可确认消失”应另开服务层包。
- 横幅始终由 notifier 驱动，没有本地计时器、没有一次性标志：任何来源把 issue 变为 null 都会立即清行。

## 先红后绿

新增回归在**未接入账本横幅的旧实现**（`git stash` 单独还原 `reminder_failure_banner.dart`，l10n 键保留）上实测：

```
00:00 +0 -1: an unreadable ledger is shown and can be read again [E]
00:01 +0 -2: a ledger that cannot be written is shown and blocks a clean save [E]
00:01 +0 -3: a full ledger says how many records it refused and offers no retry [E]
00:01 +0 -4: records skipped as damaged are counted instead of vanishing [E]
00:01 +0 -5: ledger states replace each other and leave nothing cached [E]
00:01 +0 -6: leaving the page drops every reminder subscription [E]
00:01 +0 -7: a ledger problem keeps the schedule and cancel rows working [E]
00:01 +1 -7: Some tests failed.
```

恢复实现后同一文件 `00:01 +8: All tests passed!`（`git stash pop`，工作区只保留本包三个文件）。

## 覆盖矩阵（`test/rf08_ledger_ui_test.dart`，8 项）

1. 读失败：行出现并说明受影响的是“仍在等待再次尝试的提醒”；同时确认另外三个状态的行不出现（状态互不串台）；修好账本点重试后 `ledgerIssue` 为 null、行与按钮一起消失。
2. 写失败：行出现且文案正确；`flush(includeReminderLedger: true)` 仍为失败、`flush()` 纯数据屏障仍成功；修好存储点重试后行消失且账本真的写入了 `reschedule` 记录。
3. 64 项满额：满额但未越界时没有提示；第 65 条返回 `rejected` 后出现满额行，文案里的计数与上限来自 `refusedRecords` 与 `ReminderService.maxPendingJobs`，且**没有**重试按钮。
4. 损坏记录：种入一条合法 + 一条不可解析记录后，出现损坏行且计数为 1，无重试按钮。
5. 多状态切换：同一个横幅内按 读 → （重试恢复）→ 写 → 满额 顺序切换，每次都断言新行出现、旧行消失；最后撤回 issue，四个账本行全部消失，而 64 条待重试记录仍以原有“排程失败”行如实呈现（未影响既有语义）。
6. 监听释放：`pumpWidget(SizedBox)` 销毁页面后，对 `ledgerIssue`/`scheduleFailures`/`cancelFailures`/`observedPermission` 四个 notifier 连续赋值不产生异常（`takeException()` 为 null）；重新挂载后显示的是当前状态（无行），再发布满额 issue 时才出现对应的行——不存在销毁后回写或跨实例残留。
7. 兼容性：账本写失败与排程失败同时出现时两行并存；点原有 `retry-reminders` 后排程行清除，写落地后账本行也一并清除，`ledgerIssue` 回到 null。
8. 三语与措辞：四键在 en/zh/ja 均非空、占位符一致、不含送达承诺禁词。

测试设计备注：横幅没有任何行时渲染 `SizedBox.shrink()`，`ListView` 子项高度为 0，`Finder` 默认会按 offstage 跳过该子树；因此“空状态”断言显式使用 `skipOffstage: false`，而“用户能看到某行”的断言保持默认（onstage）。

## 验证

- 定向：`test/rf08_ledger_ui_test.dart` **8/8**（其中 7 项在旧实现上先红）。
- 相邻回归：`rf08_reminder_retry` + `os17_reminder` + `windows_reminder` + `os27_copy` + `os12_date_reminder` + 本包定向 **91/91**。
- 共享探针（断言未改）：`test/review/rf08_reminder_retry_probe.dart` + `test/review/os_final_review_probe.dart` **9/9**。
- 默认全量 `flutter test --no-pub` **730/730**（基线 `22aa43d` 实测 **722/722** + 本包 8），`flutter analyze --no-pub` **0 issues**。测试串行运行，避免 RF09 墙钟基准受并发争用。

## 未测与限制

- **没有任何真机/模拟器验证。** 本包只改横幅与三语文案，全部证据来自合成任务、内存账本替身与假提醒服务；不声称 Android 未来提醒、Windows 运行中提醒或通知点击回流已验收，也不声称送达率。
- 满额与损坏状态**没有服务端清除路径**（见上），横幅在进程内会一直显示该 issue；这是本包有意不做 UI 侧猜测的结果，也是留给服务层包的缺口。
- 64 项上限与 7 天 TTL 沿用 RF08/OS17 既有常量，未重新评估；满额文案里的数字会随 `ReminderService.maxPendingJobs` 变化而自动变化，但没有为它加“改动常量即改文案”的额外守卫（现有测试会因数字不符而失败）。
- 文案只在单元/widget 层断言存在性、占位符与禁词；三语在真实字号/长文本下的换行、`maxLines: 3` 截断后的可读性未做设备端检查。横幅仍沿用既有的单行截断样式，未新增展开或详情入口。
- `ledgerIssue` 的四态语义（何时读、何时写、满额如何挤占）仍以 RF08 默认回归为准，本包未改动服务层；`storage.dart` 的退出屏障开关与本次 UI 改动无交叉。
- 本包未运行 `npm`/React 构建（冻结端），未做正式签名或发布，未 push。
