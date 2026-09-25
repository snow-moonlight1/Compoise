# OS21 实施记录：页面只编排展示与用户输入

> main 集成补记（2026-09-25）：已将 `quadrant_pane.dart`、`task_list_view.dart`、`matrix_screen.dart` 的路由改为直接导入所属模块，删除 `input_sheet.dart` 的过渡再导出。备份流程在页面关闭后不再继续选择导出文件；导入异步完成后只在页面仍在时刷新输入框。新增关闭流程回归。下文第 7 节记录的是独立分支当时留给集成的事项。

日期：2026-09-25。包号：**OS21**（对应审查报告 F18、开源准备计划「OS21 — 页面只编排展示与用户输入」）。状态：**已实施**。Android 与 Windows 设备未测。

## 1. 接手与边界

- 基线：`main / 77d81f13f6972fe0b9237e09f03a846e05712b09`（OS18/OS20/OS23 集成收口之后）。接手时主工作区干净。
- 独立 worktree `D:\Dev_project\martix-wt-os21`，分支 `os21-page-coordination`，从上述同一提交新建；先确认没有同名 worktree/分支，本包全部改动都不在 main 工作区。未 reset、未 amend、未推送、无远端。
- 固定 SDK `D:\Dev_SDKs\Flutter_3.32.8`（Flutter 3.32.8 / Dart 3.8.1）。未改依赖与 `pubspec.lock`。新建 worktree 后先执行 `flutter pub get` 生成本地包配置；它只让三个 Windows 插件生成文件出现行尾差异（`windows/flutter/generated_plugin_registrant.{cc,h}`、`generated_plugins.cmake`），保留在工作树未提交。
- 本包文件：`settings_screen.dart`、`input_sheet.dart`、`task_detail_panel.dart`、`search_screen.dart`、`completed_screen.dart`、必要的 `matrix_screen.dart` 编排，以及本包新增模块与 `test/os21_page_coordination_test.dart`。
- **未改 OS22 独占文件**：`storage.dart`、`task_query.dart`、`quadrant_pane.dart`、`task_list_view.dart`，也没有新增性能工具。**未新增任何 Store 接口**：全部沿用现有 `copyAIConfig`/`updateAIConfig`/`updateTask`/`addTasks`/`newTask`/`previewImport`/`applyImport`/`exportJson`/`exportJsonWithCredential`/`boardEpoch`。
- **未改** `AGENTS.md`、`HANDOFF.md`、`ARCHITECTURE.md`、`CHANGELOG.md`、开源准备计划；本文件由本 Agent 单独撰写。**未改 `l10n.dart`**：所有抽离都复用既有英/中/日文案，没有新句子需要翻译。
- 冻结 React/Tauri/Capacitor 未动；继续暂停 WP10/WP29/UI 实验。只用合成任务与假 HTTP 网关，没有真实密钥、用户备份或设备。

## 2. 归位结果

| 新模块 | 负责 | 原来的位置 |
| --- | --- | --- |
| `widgets/batch_decompose_sheet.dart` | 批量/单任务拆解弹窗与其 AI 取消 | `input_sheet.dart` 尾部 |
| `widgets/reminder_access.dart` | 提醒权限结果反馈 | `task_detail_panel.dart` 头部 |
| `widgets/date_edit_fields.dart` | 民事日规则、日期与提醒选择流程、日期 chip 行 | 输入面板 + 详情 + 子项弹窗各一份 |
| `widgets/task_edit_draft.dart` | 草稿字段、脏值判定、子项合并、写回构造、`hasPendingImeComposition` | `_TaskDetailPanelState` 的十个字段与 `build` |
| `widgets/subtask_edit_dialog.dart` | 子项编辑对话框与其两个 controller | `_editSubtask` 内的临时 controller + `StatefulBuilder` |
| `screens/settings_model_request.dart` | 模型列表请求会话（身份、代际、取消、`dispose`）与连接测试面板 | `_SettingsScreenState` + 文件内私有 widget |
| `screens/settings_backup_flow.dart` | 导出与导入协调，按结果类型返回 | `_export`/`_import` 两个 Widget 方法 |
| `screens/settings_desktop.dart` | 桌面设置应用与状态文案（设置区与导入流程共用） | `_applyDesktopSettings`/`_desktopStatusText` |
| `TaskDetailSession`/`DetailSideBySide`（在 `task_detail_panel.dart` 内） | 当前详情任务、草稿标记、切换/关闭/离开判定；并列布局与宽度来源 | 主界面、搜索、完成页各写一遍 |

- **互引已解除**：`input_sheet.dart` 与 `task_detail_panel.dart` 不再互相 import，`import 'input_sheet.dart'` 从详情面板消失。行数只是副产物：`settings_screen.dart` 2312→1702、`input_sheet.dart` 755→443、`task_detail_panel.dart` 1498→1054（其中详情会话与并列布局约 130 行留在同一模块，因为它属于同一所有权）。
- `input_sheet.dart` 保留两条 `export`：`quadrant_pane.dart:9` 与 `task_list_view.dart:9` 仍通过本库取 `showTaskEditSheet`/`showBatchDecomposeSheet`。见第 7 节越界事项。

## 3. 草稿、提交与释放规则

- 草稿由 `TaskDetailPanel` 的 State 创建、在 `dispose()` 里 `TaskEditDraft.dispose()` 一次性释放三个 controller；切换任务走 `load()` 重用同一批 controller，与原来的 GlobalKey/身份行为一致。
- 脏值判定、"哪些字段真的被改过"、子项合并（未动的行跟随 live 任务、动过的行保留编辑并捡回别人改过的其它字段）全部集中在 `TaskEditDraft`。写回仍由详情面板调用 `Store.updateTask(draft.applyTo(current))` 完成，草稿对象本身不碰 Store。
- 所有提交路径先看 IME 组字：详情保存（按钮与 Ctrl/Cmd+Enter）、新建输入面板提交、添加子项、子项对话框确认。中文输入过程中的 Ctrl+Enter 只结束组字，不会半截入库。
- 子项对话框改为独立 widget：controller 在其 State 的 `dispose()` 释放；结果以 `SubTaskEditResult` 返回，取消不改草稿。
- 异步释放规则统一为「代际 + 显式 `dispose()`/`close()`」：`ModelRequestSession.dispose()` 递增代际并取消在途请求后拒绝任何迟到回包；`SettingsBackupFlow.close()` 后不再开始也不再回报；拆解弹窗沿用 `_closed` + `AICancellation.cancel()`。

## 4. 页面一致性

- 搜索页与完成页的侧栏判定改为 `PlatformUiPolicy.canShowSideDetail(...)`，面板宽度取 `PlatformUiPolicy.sideDetailWidth`，与主界面同源（原先两处硬编码 `>= 900` 与 `width: 350`）。
  - 数值影响：350 与 `sideDetailWidth` 相同，面板宽度不变；断点由 900 变 924（=350+14+560），窗口宽度落在 900–924 之间时搜索/完成页由「并列侧栏」变为与主界面一致的「整页编辑器」。这是本包唯一可观察的行为变化，属于统一要求。
  - 分隔物保持各自原样：主界面仍是 14px 间距，搜索/完成页仍是原来的 1px `VerticalDivider`（`DetailSideBySide` 允许传入分隔件并保留各自的交叉轴对齐），未借统一之名重画。
- 草稿退出规则统一为 `TaskDetailSession`：打开与切换前确认、面板自行关闭时结算、Escape 与离开页面都走 `confirmLeave`；窄布局的模态编辑器由会话记录脏标记并在关闭时清零。
- **返回拦截仍在详情面板自身的 `PopScope`**：三个页面共用同一份实现，页面不再各自加一层 `PopScope`。集成过程中验证过一次：给搜索/完成页再加页面级 `PopScope` 会让 `SR03 *back guards draft*` 出现两层确认对话框（`Expected: <1> Actual: <2>`），该加法已撤回。

## 5. 设置页请求与备份

- 模型列表的身份/代际/在途判定、`commit` 去重、迟到回包丢弃、provider 切换与 URL/协议/密钥变化后的失效，全部搬到 `ModelRequestSession`；`build` 里那段「按 live config 重算是否过期」的内联状态机改为一次 `syncWithLiveConfig(store)`。
- 连接测试面板独立成 `TestConnectionButton` 并补上 `dispose()`（递增代际，退场后不接受回包）。生成前仍需用户确认、GET /models 成功不称为生成可用、诊断不含密钥等既有约束未改。
- 导出/导入改为 `SettingsBackupFlow`：密钥选择、4 MiB 上限与流式读取、merge/overwrite 选择、预览摘要与 warning 文案、冲突禁用确认、`applyImport` 失败提示、桌面设置应用与告警，逐条沿用原逻辑；`import` 结束后仍同步三个 AI 输入框（通过 `syncAiFields` 回调，由页面持有 controller）。
- 结果类型 `BackupResult(outcome, message)`：`cancelled` 不提示，`succeeded`/`failed` 携带已本地化的文案，SnackBars 只由页面显示。取消、冲突、写入失败与成功路径文案不变。

## 6. 验证

固定 SDK `D:\Dev_SDKs\Flutter_3.32.8`：

- 专项新增 `test/os21_page_coordination_test.dart` **11/11**：草稿脏值/回退/子项合并/已决定关闭不再算草稿/子项 composer 交接；组字中 Ctrl+Enter 与保存按钮都不入库、组字结束后保存生效；子项对话框连续开关三轮后两个 controller 确已释放；子项编辑结果在下一次打开时可见；主界面/搜索/完成页在 1400 与 900 两档下的侧栏判定与宽度一致；搜索页切换行的草稿保护（保留后仍在原位、放弃后切到新任务）；设置页退场后迟到回包不改变界面。
- 修前红证据（临时反向改动，随后已还原）：去掉 `hasPendingImeComposition` 守卫后，专项用例把 `输入中` 写进 Store（`Expected: 'Alpha' Actual: '输入中'`）；去掉子项对话框的 `dispose()` 后，controller 释放断言失败。两项恢复后转绿。
- 合并态默认 `flutter test --no-pub` **555/555**（接手基线 544/544 + 本包 11），`flutter analyze --no-pub` **0 issues**。
- 相邻回归未改即通过：`os12_date_reminder_test`（日期/提醒选择窗口与取消语义，含子项与 composer）、`foundation_second_regression_test` 的 `SR03` 草稿保护、`foundation_regression_test` 的 `F01/F12` 切换保护与 `F03/R11` 子项反向合并、`os15_desktop_exit_test` 的组字退场、`os10/os11` 模型发现与协议能力、`os20_store_boundary_test`。
- Windows Debug 目标设备集成测试 `flutter test --no-pub integration_test/app_test.dart` **2/2**；`flutter build windows --debug` 与 `flutter build apk --debug` 均构建成功。三者都跑在集成测试的 mock 平台边界与编译器上，不是真实设备操作。
- 审查探针：`test/review/preopensource_review_probe.dart`（OS-R01…R07）**7/7** 与接手基线一致。`test/review/wp28_review_probe.dart` + `foundation_second_review_probe.dart` 在**接手基线上同样 13 红**（两次运行都是 `+14 -13`）——这些是不在默认套件里的历史反例探针，登记的事项属于其他/后续工作包，本包既没修好也没弄坏它们。

## 7. 留给集成人的越界事项

1. `quadrant_pane.dart` 与 `task_list_view.dart`（OS22 独占）仍 `import 'input_sheet.dart'` 取 `showTaskEditSheet`/`showBatchDecomposeSheet`，因此 `input_sheet.dart` 保留两条 `export`（文件顶部有注释）。OS22 落地或下一轮集成时把这两处 import 改为 `task_detail_panel.dart`/`batch_decompose_sheet.dart`，然后删除那两行 `export`；届时 `matrix_screen.dart` 需要直接 import `batch_decompose_sheet.dart`（现在经 `input_sheet.dart` 的再导出可见，直接 import 会被 `unnecessary_import` 判为多余，故本包未加）。
2. 本包**不需要**任何新 Store 接口。若后续要把详情会话从 Widget 里再往外挪，需要先有「按 id 只读取任务快照」的入口，届时另立工作包讨论。
3. `docs/FLUTTER_REVIEW_2026-09-22.md` 的 F18 与开源准备计划第 204 节的「未开始」状态需要由集成人按实际结果更新；`AGENTS.md`/`HANDOFF.md`/`ARCHITECTURE.md`/`CHANGELOG.md` 同理。CHANGELOG 建议条目：详情/子项编辑在 IME 组字期间不再提交、子项对话框 controller 释放、搜索与完成页侧栏断点与主界面统一（900→924）。
4. 工具链提醒：本 SDK 的 `dart format` 与仓库既有排版不一致（对未改动文件也会重排，例如把 `onSelected:\n    _busy\n        ? null` 折成一行）。本包全部按周围排版手工书写，未运行 `dart format`，以免与其他 worktree 冲突。

## 8. 未测与限制

- Android 与 Windows **设备/窗口人工验收未做**：快速切换详情、缩窄窗口、中文输入法 Ctrl+Enter、子项弹窗反复开关、设置页快速切换请求与导入向导，都只有 widget/mock 证据，不能代替真机触摸与真实 IME 行为。`adb devices` 本轮未接设备。
- 真实 AI 厂商调用未测（无密钥，专项使用 gated `MockClient`）。导入/导出仍依赖 `file_picker` 平台通道，`SettingsBackupFlow` 的取消/失败路径未在真机上驱动，本包只测到结果类型与 Store 交互层。
- `DetailSideBySide` 保留各页面原有分隔件与交叉轴对齐，因此「统一」限于宽度与断点，不包含视觉归一；如需彻底统一分隔表现，需要另外的 UI 决定（当前 UI 实验仍暂停）。
- 分支 `os21-page-coordination` 上共 6 个提交，与五个抽离步骤一一对应，逐步可审：拆除互引 → 共享日期 UI → 草稿与子项会话 → 页面详情会话 → 设置请求与备份协调 → 专项测试与本记录。哈希见本轮交接回复。
