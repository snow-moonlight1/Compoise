# RF10 退出状态防护（exit guard）实施记录

日期：2026-09-26。
基线：`main / 22aa43d6f88bcbbb9efd778aef23e023454975e0`。
分支：`codex/rf10-exit-guard`；工作树：`D:\Dev_project\martix-rf10-exit-guard`。
固定 SDK：`D:\Dev_SDKs\Flutter_3.32.8`（Flutter 3.32.8 / Dart 3.8.1）。

## 1. 背景与范围

`RF10_PLATFORM_EVIDENCE.md` W8 在真实 Windows Release 上实测了三种 applySettings/退出交错，均未在 destroy 后重建托盘或热键，但同时记录了两项源码告警：

1. `_applySettingsNow` 只比较 `generation`，从不检查退出状态；`_performExit` 在 `destroy()` 前把 `_host` 置空，而 `_host ??= _hostFactory()` 会在 host 为空时**新建实例**。实测不出问题仅依赖“窗口销毁即进程终止”的时序，而非显式防护。
2. race2（挂起的 start 续体跨过 destroy）中退出完成后 `isApplyingSettings` 残留为 `true`。

返修计划 RF10 明确要求：“额外验证桌面 applySettings 未完成时退出不重新创建托盘/热键”。

**本包所有权**：`lib/services/desktop_shell_service.dart`、新增 `test/rf10_exit_guard_test.dart`，以及为对齐新语义而拆分的 `test/os14_desktop_shell_test.dart` 中一个既有测试。未改 `storage.dart`、提醒服务、备份或其他并发包文件；除本文件外未改任何共享文档（AGENTS/HANDOFF/CHANGELOG/返修计划/证据文档）。全部测试使用可控异步合成 host，未接管用户桌面鼠标键盘，未触碰真实资料或密钥。

## 2. 修前默认反例（先红后绿）

新增 `test/rf10_exit_guard_test.dart`，用可挂起的 `_ScriptedHost`（start/register/unregister/destroy 各阶段均可用 `Completer` 挂起，destroy 可注入失败）与 `forTestFactory` 工厂接缝建立反例。修前 9 项中 **6 项失败**：

| # | 交错 / 场景 | 修前错误行为 |
|---|---|---|
| 1 | race：第二代 apply 的 `start()` 挂起，退出 destroy 进行中才释放 | destroy 期间/之后继续调用 `registerHotkey`，并发布成功结果（`aborted` 为 false） |
| 2 | race2：destroy 进行中请求第三代 apply | `_host ??= _hostFactory()` 新建第二个 host（hosts 长度 2） |
| 3 | completed：挂起的 register 结果在退出完成后才返回 | 迟到结果被 publish，退出后状态“复活”，且 `isApplyingSettings` 残留 true |
| 4 | failed：destroy 失败 | 等待中的 apply 不会自动重建托盘/热键（startCalls 停在 1） |
| 5 | concurrent：退出在途时迟到的 apply | 迟到 apply 未被 abort，继续操作 host |
| 6 | 直接热键 API：退出 pending 时调用 `registerGlobalHotkey` | 立即返回 success 而非等待退出结果 |

其余 3 项修前即绿（baseline 回归锚点、同步取消退出、guard pending 期间排队后取消），用于锁定既有正确行为。

## 3. 修复设计（desktop_shell_service.dart）

### 3.1 退出结果与 apply 同步原语

- 新增 `_awaitExitSettled()`：循环等待当前 `_exitInFlight`（若有退出在取消/失败后立即重启，会跨 attempt 链接）。`_hasExited` 为真时立即返回 `completed`；无 attempt 时返回上一次结果（可能为 null）。
- `_applySettingsNow` 在**三个检查点**调用它：host 创建前、tray start 之后、hotkey 操作之后。
  - `completed` → 返回 `_abortedResult`（tray/hotkey 均为 disabled，新字段 `aborted: true`），不再创建/注册任何东西；
  - `failed` → host 已由退出路径恢复，以**相同 generation 递归重跑**整个 apply（tray + hotkey 重新建立）；
  - `cancelled` → 一切仍存活，继续执行。
- 新增 `_settleApplyFlag(generation)`：仅当 generation 仍是最新时把 `_isApplyingSettings` 置 false 并 notify；更新的排队 apply 已自行取得 flag 所有权，不被旧一代误清。
- `_publish` 加固：开头若 `_hasExited || _exitInFlight != null`，只 settle flag、不发布，防止退出后 shell 状态复活。
- 直接 API `registerGlobalHotkey` / `unregisterGlobalHotkey`：开头先 await 退出 settled（completed → 返回 disabled），操作完成后再复查一次，覆盖“操作途中退出完成”。
- `_performExit` 重构：用局部 `detachedHost` 跟踪被摘出的 host，统一 catch 中若 host 已摘出则恢复 `_host` 并返回 `failed`；guard 否决仍在 try 内提前返回 `cancelled`。消除了原先“只有 destroy 抛错才恢复、其他摘出后异常不恢复”的不一致。

### 3.2 测试接缝

- 新增 `@visibleForTesting DesktopShellService.forTestFactory(DesktopShellHost Function() hostFactory)` 构造，用于断言“host 置空后工厂是否被再次调用”。
- `DesktopShellSettingsResult` 新增 `final bool aborted`（默认 false），与既有 `superseded` 区分：superseded 表示被更新一代设置取代，aborted 表示因退出完成而中止。

### 3.3 保留的语义

- **并发退出只执行一次**：`exitApplication` 仍以 `_exitInFlight` 合并所有并发调用（窗口关闭回调、托盘退出项、直接调用），guard 与 destroy 各只执行一次；`completed` 之后的所有退出调用直接返回 `completed`，无额外 destroy。
- 代际（generation）串行链 `_applyTail` 与“迟到结果不启用旧策略”语义不变。
- 刻意**不**让 `_performExit` 去等待 `_applyTail`：在 host 创建前就 join 退出的 apply 若再被退出等待会形成互等死锁；方向固定为“apply 单向 join 退出”。

## 4. 三种退出结果下的状态矩阵

| 退出结果 | 在途 apply（挂起在 start/register） | 退出在途时新排队的 apply | 退出 settle 后的 retrySettings | isApplyingSettings |
|---|---|---|---|---|
| completed | abort：返回 disabled/aborted，destroy 后无任何 host 调用 | 等待退出结果后 abort；不触发 hostFactory | 惰性 abort，不新建 host、不注册 | 收口为 false（最新一代由 `_settleApplyFlag` 复位） |
| cancelled | guard 返回 false 后继续执行并正常发布 | guard pending 期间排队者在取消后继续；旧一代 superseded、新一代成功 | 正常 apply（无退出时行为不变） | 最终由各自结果发布复位为 false |
| failed | 在途操作结果丢弃，以同代递归重跑：tray 重新 start、hotkey 重新 register | 等待失败结果后同样递归重跑 | host 已恢复，正常 apply | 重跑期间保持 true，重跑发布后为 false；失败本身不残留 true |

实测计数（failed 场景）：startCalls=2；registerCalls=3（M、被丢弃的在途 N、重试的 N）；随后一次健康退出 destroyCalls=2。

## 5. 对既有测试的调整

`test/os14_desktop_shell_test.dart` 原测试 `tray init failure disables close-to-tray and retry can recover` 把两个场景混在同一服务实例上：先让 `handleWindowCloseRequest` 因托盘不可用触发一次**已批准并完成**的退出（destroy 已执行、`_hasExited=true`），随后又调用 `retrySettings()` 期望重建 host。旧代码允许“退出完成后重建”，该测试因此通过——它依赖的正是本包修复的旧行为。

按新语义拆分为两个独立测试：

1. `tray init failure disables close-to-tray and a window close runs true exit`：断言托盘失败时关闭不走隐藏（hideCalls=0）、触发真退出，并 join 在途退出确认 `completed`、destroy 恰好 1 次。
2. `tray init failure can be recovered by retrySettings without an exit`：不触发退出，第二次 start 成功，retry 恢复托盘与 close-to-tray（startCalls=2、destroyCalls=0）。

两个测试各自的意图现在都与退出契约一致。

## 6. 验证命令与结果（固定 SDK，matrixflow-native/）

| 检查 | 命令 | 结果 |
|---|---|---|
| 本包定向 | `flutter test --no-pub test\rf10_exit_guard_test.dart` | **9/9 通过** |
| 桌面相邻回归 | `flutter test --no-pub test\os14_desktop_shell_test.dart test\os15_desktop_exit_test.dart test\desktop_shell_test.dart test\rf10_exit_guard_test.dart` | **35/35 通过** |
| 全量测试 | `flutter test --no-pub` | **732/732 通过**（基线 722 + 新增 9 + os14 拆分净增 1） |
| 静态分析 | `flutter analyze --no-pub` | **No issues found** |

说明：全量测试中 `widget_regression_test.dart` 有一处既有的 “missed tap” 警告（非致命、测试通过、不在本包文件内），与本次改动无关。`flutter pub get` 造成的 `windows/flutter/` 生成文件行尾差异按既往惯例不纳入提交。

## 7. 剩余人工验收项

本包证据全部来自合成 host 的单元层交错，**不代替真机/真桌面验收**：

1. **Windows Release 定向（RF10 本项）**：切换托盘/热键开关的同时点关闭，确认无残留托盘图标、无残留热键（可用其他程序尝试注册同一组合键，能注册即说明旧热键已释放）；再验证 destroy 失败路径的真实表现（真实 host 通常不抛错，可能需要故障注入）。
2. Windows 真实 IME 组字、原生文件对话框逐卷保存、聚焦/键盘手感：仍未测（证据文档 W9）。
3. Android SAF 导入导出、凭据跨重启、真实 IME 组字、未提交子项草稿：仍未测（证据文档 A6–A9）。
4. 超计数历史库（10,599 条）无法按逐卷流程完整恢复（仅恢复 7066），属待决策的产品限制（证据文档 W7）。
5. OS26 正式签名、托管发布渠道与完整升级验收仍独立未完成。

## 8. 边界声明

未切换 `main`、未 push、无远端操作；未改冻结的 React/Tauri/Capacitor 代码；未使用真实密钥或用户数据。提交仅包含：`lib/services/desktop_shell_service.dart`、`test/rf10_exit_guard_test.dart`、`test/os14_desktop_shell_test.dart`（拆分）与本文件。
