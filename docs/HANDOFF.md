# 项目交接文档（HANDOFF.md）

最后更新：2026-09-09。

## 最新任务：WP20-N 已完成（自动化），下一包 WP20-W

- 用户决定继续 MatrixFlow 独立开发，只参考 Focus 已有交互；**不 fork、不复制其代码、不再跟踪其 issue/PR、不组织几十人试用**。
- **本轮实施 WP20-N**：Flutter 完成方框与多选分离、独立子项展开、逐行删除线。未做 Web、后端、发布、WP21 或十字布局。
- 契约落地：完成 Checkbox 始终 `task.completed` 并走 `setParentCompleted`；多选用行高亮 +「已选」+ 顶部「多选任务 · 已选 N 项」；展开按 `boardId/taskId` 会话状态，默认收起，切模式/切板保留；`StrikeThrough` 改为 `TextDecoration.lineThrough`。
- 验证：`D:\Dev_SDKs\Flutter_SDK\bin\flutter.bat test --no-pub` **74/74**；`analyze --no-pub` **0 issues**。未做 Android/Windows 实机，未跑 Web build/tsc。
- 下一位实施助手只做 **WP20-W**，对齐上述 Flutter 契约；不因路线已确定而一次执行全部工作包。
- [Implementation Plan](IMPLEMENTATION_PLAN_2026-09-08.md) 为 42 项、29 个工作包。目标形态仍是开源本地客户端 + GitHub Release/商店；保留 BYOK；后期可选 ¥9/月有额度托管 AI。多 Board、父子任务、三协议/思考、无说教、备份互通保留。
- [昨日方向研究](STRATEGY_REVIEW_2026-09-08.md) 保留为历史证据；Focus 本地克隆仍在 `D:\Dev_project\martix-research\Focus`，不需重新克隆或查其 issue。
- 用户 13 项样本：Pro 思考开 11/13、Pro 关 12/13、Flash 开 12/13、Flash 关 13/13。历史 66 项是 WP20-N 之前的基线。

## 历史需求评估（已并入新版计划）

- 完整需求、优先级、代码依据、执行步骤与验收标准见 [执行计划](IMPLEMENTATION_PLAN_2026-09-08.md)。首组截图 31 条去重为 28 项；第二组实机反馈再补 7 项，现为 **35 项、22 个工作包**。父任务自动完成、换行批量添加是已有能力，但新交互仍需回归。
- 本次只写计划，未修改应用代码、未运行构建/测试、未提交；代码基线仍为 `6e30502`。以下“当前交付”和“已验证”为前一实现轮及用户确认的成果。
- 用户明确 **custom API 目前没有故障**；真实需求是内置服务商 Base URL，用户选服务商、填写 Key 后实时获取模型列表，参考 Cherry Studio / Chatbox，不能硬编码候选模型清单。默认 DeepSeek，候选包括火山引擎和阿里云百炼；每家模型发现 API 单独核验。
- “一键清除”是从主界面一次删除四象限全部任务，不是完成/归档；计划按当前 board 处理，包含已完成任务，保留其他 board 和配置。系统待办导入以厂商系统笔记为目标，先验证小米 `com.miui.notes` 的公开接口/分享/导出路径。
- 早期优先级以 WP20-N 完成/选择混淆、子任务展开和多行删除线起步；现在由新版计划第 3 节统一派单，新增聚焦/搜索等已有明确位置。
- 静态根因：`task_card.dart` 的方框在 `selected` 与 `completed` 间复用；删除线和隐藏读取 completed；子项仅在 `!selecting` 时渲染。用户对模式的理解与内部 selecting 含义相反也符合截图，不能要求用户先搞懂代码的模式。解决方案是三个状态/入口独立。
- UI 已定方向：无框十字矩阵、复选框与标题首行对齐、子项有进度/展开入口；手机全宽底部详情，宽屏右侧详情，批量操作集中工具栏；不再每张卡铺满编辑控件。研究依据与线框见 [交互复核](UI_INTERACTION_REVIEW_2026-09-08.md)。
- 四象限用用户指定的紧急/重要完整名称；旧行动短名可追溯到 Web 初始化提交，并非最近才改。日期新增入口与 Native 子项编辑要补齐，阈值/颜色/自动移动口径和人工调整优先级见 WP22。
- B01 已关闭，VS C++ 工具链可用；不再优先做旧提示词中的 B01、发布签名/图标或无关重构。
- 本交接曾引用 `real_device_test_plan.md`，当前工作区未找到该文件；既有实机通过结论来自前轮交接和用户确认，不要求接手 Agent 反复寻找或伪造历史报告。

## 当前交付

- **WP20-N Flutter 交互语义**：完成方框、多选高亮、子项展开三者独立；多行标题走逐行删除线。改动文件：`matrixflow-native/lib/widgets/task_card.dart`、`anim.dart`、`quadrant_pane.dart`、`screens/matrix_screen.dart`、`l10n.dart`，以及 `test/widget_regression_test.dart`、`test/bug_regression_test.dart`。
- **纯净化待办卡片与 AI 输出**：移除了卡片上的 `reasoning` 理由展示；提示词严禁道德批评与说教评语，任务卡片纯粹简洁。
- **设置界面占位与文案精简**：输入框常驻浮动标签与占位符（`FloatingLabelBehavior.always`）；思考模式副标题精简，去除多余举例。
- **设置自动化 4 项功能真机实测全量通过**：
  - AI 自动拆解隐藏拆解提示（`suppressLongTermPrompt`）
  - AI 自动分组隐藏分组提示（`suppressGroupPrompt`）
  - 父任务自动完成与反选恢复（`autoCompleteParent`）
  - 待办数据导入与导出（Android SAF 文件选择器与标准 JSON 备份）
- **4 组模型与思考模式真机（Redmi K70）全量对比测试**：
  - `deepseek-v4-pro` / `deepseek-v4-flash` 开启、关闭思考的流程由前轮报告通过，卡片无多余评语。分类准确率采用用户最新样本表：依次为 11/13、12/13、12/13、13/13，不能再表述为四组全都分类 100%。
- 保留纯本地设计及 ExportData v1。未引入外部数据库，未泄露任何敏感 API 密钥。

## 已验证

| 检查 | 结果 |
|---|---|
| `flutter test --no-pub`（2026-09-09 WP20-N） | **74/74** 通过，含完成/多选分离、展开、逐行删除线、多板 hideCompleted 与既有回归 |
| `flutter analyze --no-pub`（同轮） | 0 issues |
| Android / Windows 实机（WP20-N 新交互） | **未测** |
| Web `npm run build` / `tsc` | 本轮未跑；WP20-W 再验 |
| 历史 Android release APK / Redmi K70 E2E | 前轮通过，不能代替本轮交互验收 |
| 历史 Web Vite 构建 | 前轮 `npm run build` 成功（290.6 kB），`npx tsc --noEmit` 0 错误 |

## 下一轮启动提示词（可直接复制）

```text
接手 D:\Dev_project\martix 的 MatrixFlow AI，只实施 docs/IMPLEMENTATION_PLAN_2026-09-08.md 的 WP20-W。先读 AGENTS.md、本 HANDOFF、计划第 1/3/5 节和 WP20、docs/UI_INTERACTION_REVIEW_2026-09-08.md 第 1–2 节，并对齐 Flutter 已落地契约。

路线已定：独立参考交互，不 fork/复制 Focus。本批只修 Web 完成/多选分离、独立子项展开、多行删除线，不做后端、发布、WP21 或十字布局。

WP20-N 已完成：完成方框始终 completed；多选为行高亮+已选标记+顶部计数；展开按 boardId/taskId 会话保存；删除线为 TextDecoration.lineThrough。Web 当前多选时用选择框替换完成方框，子项始终展开，标题用中线横条。先 git status 保护未提交文档。跑 npm run build 与 npx tsc --noEmit，未测项写明。完成后交接 WP21，不自行展开全部 29 包。
```

## 本轮收尾（WP20-N）

- 本轮修改：Flutter 任务卡/矩阵/删除线/三语文案与对应测试，以及计划/交接/CHANGELOG/测试数量同步。
- Pre-existing 未提交文档仍在工作区：`docs/STRATEGY_REVIEW_2026-09-08.md`、`docs/UI_INTERACTION_REVIEW_2026-09-08.md`、`docs/AI_UNIT_ECONOMICS_2026-09-08.csv`（本轮未改）。
- 未测：Android/Windows 实机上的完成/多选/展开/删除线、读屏实际播报、进程级冷启动（Widget 仅重建 `MatrixHome`）、Web 端（WP20-W）。
- 没有删除文件，没有改 Web 应用代码，没有引入后端。

## 历史收尾记录（原生审查轮）

- 会话最初工作区干净，无 pre-existing 用户改动；仅显式暂存本轮原生代码、回归测试和受影响文档。
- 本次 closeout 只更新交接任务及提交状态，没有继续修 B01，没有删除文件，没有重跑已经通过且代码未改变的测试。
- 重要文件：`lib/storage.dart`、`lib/ai_service.dart`、`lib/widgets/input_sheet.dart`、`lib/screens/`、三份新增 `test/*regression_test.dart` 及审查报告。
- APK、Windows Release 整目录及 `docs/native-*.log` 属于本地产物/忽略文件，不提交。它们保留用于复测与排查，不是删除候选。
