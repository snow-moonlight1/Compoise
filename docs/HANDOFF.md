# 项目交接文档（HANDOFF.md）

最后更新：2026-09-09。

## 最新任务：WP21-N 已完成（自动化），下一包 WP03-N

- Flutter Android/Windows 为唯一持续开发客户端；React/Tauri/Capacitor 冻结保留。依据见 [已采纳 ADR](ADR_FLUTTER_PRIMARY_2026-09-09.md)。旧 W 是 React Web，不是 Windows。WP20-W 未开工、已取消。
- **本轮实施 WP21-N**：界面与编辑选项使用完整紧急/重要名称；分类提示词去掉 Do First/Schedule/Delegate/Don't Do 行动括号。未改 React、未做十字布局/日期/服务商/后端，未重做 WP20-N。
- 中文：Q1 紧急且重要、Q2 不紧急但重要、Q3 紧急但不重要、Q4 不紧急也不重要；英文/日文同一对维度。wire=1/2/3/4 与左上/右上/左下/右下位置未改。
- 验证：`D:\Dev_SDKs\Flutter_SDK\bin\flutter.bat test --no-pub` **77/77**；`analyze --no-pub` **0 issues**。未做 Android/Windows 实机，未调用真实模型。
- **下一助手只做 WP03-N**：十字无框矩阵与紧凑任务行。完成后交接 **WP04-N**。
- WP20-N 继续保留：完成方框、多选高亮、子项展开、逐行删除线不能退化。
- 全部 42 项需求 / 29 个工作包保留，客户端实现统一 Flutter。新 Flutter 继续读取旧 ExportData v1，后续字段按 WP11 演进，不要求冻结 React 理解未来新格式；Android/Windows 备份一致不等于云同步。
- 路线仍为独立 MatrixFlow：不 fork/复制 Focus，不追踪其 issue/PR，不组织几十人试用。保留多 Board、父子任务、三协议/思考、无说教、BYOK；后期 GitHub Release/商店及可选 ¥9/月有额度托管服务，本轮未发布或搭建服务。
- [早期方向研究](STRATEGY_REVIEW_2026-09-08.md) 与 [交互复核](UI_INTERACTION_REVIEW_2026-09-08.md) 仅作历史依据，其旧 Web 派单和 fork 比较不再执行。Focus 克隆保留在 `D:\Dev_project\martix-research\Focus`，无需重新研究。

## 历史需求评估（当时记录，已被新版计划覆盖）

- 2026-09-08 首组截图 31 条去重为 28 项，第二组实机反馈再补 7 项，当时为 **35 项、22 个工作包**；现已扩展至 42 项、29 包，见 [执行计划](IMPLEMENTATION_PLAN_2026-09-08.md)。父任务自动完成、换行批量添加是已有能力，新交互仍需回归。
- 该次历史规划基于 `6e30502`，仅写文档、未运行构建/测试。此后 WP20-N 已落地到 `747eb35`；当前基线与下一包以本文件顶部为准。
- 用户明确 **custom API 目前没有故障**；真实需求是内置服务商 Base URL，用户选服务商、填写 Key 后实时获取模型列表，参考 Cherry Studio / Chatbox，不能硬编码候选模型清单。默认 DeepSeek，候选包括火山引擎和阿里云百炼；每家模型发现 API 单独核验。
- “一键清除”是从主界面一次删除四象限全部任务，不是完成/归档；计划按当前 board 处理，包含已完成任务，保留其他 board 和配置。系统待办导入以厂商系统笔记为目标，先验证小米 `com.miui.notes` 的公开接口/分享/导出路径。
- 早期优先级以 WP20-N 完成/选择混淆、子任务展开和多行删除线起步；现在由新版计划第 3 节统一派单，新增聚焦/搜索等已有明确位置。
- 静态根因：`task_card.dart` 的方框在 `selected` 与 `completed` 间复用；删除线和隐藏读取 completed；子项仅在 `!selecting` 时渲染。用户对模式的理解与内部 selecting 含义相反也符合截图，不能要求用户先搞懂代码的模式。解决方案是三个状态/入口独立。
- UI 已定方向：无框十字矩阵、复选框与标题首行对齐、子项有进度/展开入口；手机全宽底部详情，宽屏右侧详情，批量操作集中工具栏；不再每张卡铺满编辑控件。研究依据与线框见 [交互复核](UI_INTERACTION_REVIEW_2026-09-08.md)。
- 四象限用用户指定的紧急/重要完整名称；旧行动短名可追溯到 Web 初始化提交，并非最近才改。日期新增入口与 Native 子项编辑要补齐，阈值/颜色/自动移动口径和人工调整优先级见 WP22。
- B01 已关闭，VS C++ 工具链可用；不再优先做旧提示词中的 B01、发布签名/图标或无关重构。
- 本交接曾引用 `real_device_test_plan.md`，当前工作区未找到该文件；既有实机通过结论来自前轮交接和用户确认，不要求接手 Agent 反复寻找或伪造历史报告。

## 已实现功能（历史实现事实）

- **WP21-N 四象限名称与分类描述**：`l10n.dart` 的 q1–q4 与 q1Short–q4Short 均为完整维度名；`quadrant_pane.dart` / `input_sheet.dart` 不再展示行动短名；`ai_service.dart` 分类定义按紧急/重要，无行动括号。测试：`test/models_test.dart`、`test/ai_regression_test.dart`、`test/widget_regression_test.dart`。
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
| `flutter test --no-pub`（2026-09-09 WP21-N） | **77/77**，含三语维度名、提示词无行动括号、360dp 中文「不」、WP20 回归 |
| `flutter analyze --no-pub`（同轮） | 0 issues |
| Android / Windows 实机（WP21-N 名称与 WP20-N 交互） | **未测** |
| 真实模型分类 | **未测**；mock 只证明请求契约 |
| Web `npm run build` / `tsc` | 本轮未跑；WP20-W 已取消 |
| 历史 Android release / Redmi K70 E2E | 前轮通过，不能代替本轮验收 |

## 下一轮启动提示词

```text
接手 D:\Dev_project\martix，只实施 docs/IMPLEMENTATION_PLAN_2026-09-08.md 的 WP03-N。先读 AGENTS.md、本 HANDOFF、计划第 1/3/5 节和 WP03-N，以及 docs/UI_INTERACTION_REVIEW_2026-09-08.md 第 3 节。

Flutter Android/Windows 是唯一持续开发客户端；旧 W 指 React Web。先 git status 保护未提交文档。不改 React，不重做 WP20-N/WP21-N。

本包只做十字无框矩阵与紧凑任务行：去象限圆角框和任务白底卡片，中央十字，完成方框与标题首行对齐，任务行只留完成/标题/日期/子项展开。继承完成/多选/展开契约和完整维度名。不为 WP23 造假按钮，详情留给 WP04。

用 D:\Dev_SDKs\Flutter_SDK\bin\flutter.bat 在 matrixflow-native/ 跑 test --no-pub 与 analyze --no-pub。77/77 是 WP21-N 基线。未测实机写明。完成后交接 WP04-N，停止。
```

## 本轮收尾（WP21-N）

- Flutter 字典、矩阵标题、编辑象限选项、分类提示词与对应测试已改；未改 React，未建 UI 实验分支。
- 未测：Android/Windows 实机上的两行标题与「不」字可见性、真实模型分类。
- Pre-existing 未跟踪文档仍在：`docs/STRATEGY_REVIEW_2026-09-08.md`、`docs/UI_INTERACTION_REVIEW_2026-09-08.md`、`docs/AI_UNIT_ECONOMICS_2026-09-08.csv`、`docs/ADR_FLUTTER_PRIMARY_2026-09-09.md`。

## 历史收尾（WP20-N）

- 本轮修改：Flutter 任务卡/矩阵/删除线/三语文案与对应测试，以及计划/交接/CHANGELOG/测试数量同步。
- Pre-existing 未提交文档仍在工作区：`docs/STRATEGY_REVIEW_2026-09-08.md`、`docs/UI_INTERACTION_REVIEW_2026-09-08.md`、`docs/AI_UNIT_ECONOMICS_2026-09-08.csv`（本轮未改）。
- 未测：Android/Windows 实机上的完成/多选/展开/删除线、读屏实际播报、进程级冷启动（Widget 仅重建 `MatrixHome`）；当时未测 Web，后续 WP20-W 已取消。
- 没有删除文件，没有改 Web 应用代码，没有引入后端。

## 历史收尾记录（原生审查轮）

- 会话最初工作区干净，无 pre-existing 用户改动；仅显式暂存本轮原生代码、回归测试和受影响文档。
- 本次 closeout 只更新交接任务及提交状态，没有继续修 B01，没有删除文件，没有重跑已经通过且代码未改变的测试。
- 重要文件：`lib/storage.dart`、`lib/ai_service.dart`、`lib/widgets/input_sheet.dart`、`lib/screens/`、三份新增 `test/*regression_test.dart` 及审查报告。
- APK、Windows Release 整目录及 `docs/native-*.log` 属于本地产物/忽略文件，不提交。它们保留用于复测与排查，不是删除候选。
