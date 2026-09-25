# OS18 记录 — 单次字号缩放与文本测量

> main 集成补记（2026-09-25）：OS23 的 `quadrant_transition_layout.dart` 标题测量 painter 已在集成修正中释放；本文件第 6 节记录的是独立分支当时的跨包缺口。

## 1. 接手与边界

- 基线：`main / 0f5e4f62b4d4fc6a7dcb2440dd12e540dcd4196d`，接手时主工作区干净。独立 worktree `D:\Dev_project\martix-wt-os18`，分支 `codex/os18`。
- 固定 SDK `D:\Dev_SDKs\Flutter_3.32.8`（Flutter 3.32.8 / Dart 3.8.1）。未新增依赖，未改打包配置。
- `flutter pub get` 使 `matrixflow-native/windows/flutter/generated_plugin_registrant.{cc,h}` 与 `generated_plugins.cmake` 只出现行尾差异（`git diff --ignore-cr-at-eol --numstat` 内容为空），**未纳入提交、未清理**，与 OS17/OS19 同一处理。
- 本包只改：`lib/screens/settings_screen.dart`（字号预览 + 主题色选择动效）、`lib/widgets/animated_task_title.dart`（测量缓存身份 + 临时 painter 释放），以及两个测试文件与本记录。
- **未改**：`lib/theme.dart`（见第 2 节）、`task_card.dart`、`storage.dart`、`ui/motion_policy.dart`、`widgets/anim.dart`、`task_exit.dart`、`quadrant_pane.dart`、`quadrant_transition_layout.dart`、`task_list_view.dart`、`onboarding_screen.dart`（后七项属 OS23）。公共 `AGENTS.md`、`HANDOFF.md`、`ARCHITECTURE.md`、`CHANGELOG.md` 与开源准备计划留给集成人。**未开始 OS20/OS21/OS22/OS23/OS27。**
- 冻结的 React / Tauri / Capacitor 未动；WP10/WP29/UI 实验继续暂停。

## 2. 修前实测：两处 F15 缺陷都成立（OS-R09）

探针在 `matrixflow-native/test/review/os18_review_probe.dart`，在未改动的基线 lib 上运行，两条全部失败；随后在最终 fixture 上复跑一次确认仍是修前红、修后绿。

| 探针 | 基线实测 | 期望 |
| --- | --- | --- |
| OS-R09a 预览重复缩放 | 选 large 后预览标题宽度 **1.3413×** 标准态 | **1.16×**（应用倍率只作用一次） |
| OS-R09b 测量缓存陈旧 | 换非线性 scaler 后划线仍停在旧几何（`boxes` 与渲染段落不再一致，宽度 162.6 对 226.6） | 划线跟随重排后的行片段 |

- **缺陷 1（预览二次缩放）**：`main.dart:94-103` 已在 `MaterialApp.builder` 装好唯一的 `CombinedTextScaler`，设置页预览却又把同一个偏好乘进 `fontSize`（`16 * scale`、`14 * scale` ×2），于是应用倍率作用两次：`16 × 系统倍率 × 应用倍率²`。修后预览的基础字号保持未缩放的 16/14，缩放只有 MediaQuery 一处。
  - 复现过程有一个值得记的坑：第一版探针的 harness 把 `MaterialApp` 直接 pump 一次、没有像 `main.dart` 那样用 `Consumer<Store>` 重建，改字号时 `CombinedTextScaler` 里的 `appScale` 根本没更新，于是**基线的 bug 被测量成了正确值、探针假绿**。改成与 `main.dart` 同形的 shell（`Consumer<Store>` + `MaterialApp.builder`）后，基线才如实报出 1.3413×。
- **缺陷 2（缓存身份不足）**：`animated_task_title.dart` 的 `_layoutKey` 用 `scaler.scale(1.0)` 代表缩放器。非线性缩放（平台按字号分档）下两个 scaler 可以在 1 dp 处同值、在 16 dp 处不同值，缓存于是永久陈旧。修后键里放 `TextScaler` 对象本身：Flutter 3.32.8 的具体实现 `_LinearTextScaler`/`_ClampedTextScaler` 与本项目的 `CombinedTextScaler` 都定义了值相等，因此既不会陈旧，也不会因每次 build 新建实例而退化成每帧重测（这一条由新增回归“未变布局必须复用同一 List 实例”钉住）。
- **缺陷 3（临时 painter 未释放）**：`_lineBoxes` 里 `TextPainter` 测完即丢。修后按 SDK 自身 `calculateTextWidth` 的写法在 `finally` 中 `dispose()`。
- **`lib/theme.dart` 未改**：审查确认 `CombinedTextScaler` 的 `scale`/`==`/`hashCode` 与 `fontScaleFactor` 都是正确的单点，二次缩放完全发生在设置页预览侧；为不制造无谓 diff，本包不动该文件。
- **附带（派单指定的 OS23 归属协调）**：`_ColorDot` 的 `AnimatedContainer` 写死 200ms，不认已有的 reduceMotion 策略。现按 `MotionPolicy.reduceMotionOf(context)` 取 `Duration.zero`，即系统"减少动画"或应用内开关打开时主题色选择**一帧到终态**。只调用现成接口，未修改 `ui/motion_policy.dart`。

## 3. 修改清单

- `matrixflow-native/lib/screens/settings_screen.dart`：预览三行基础字号去掉 `* scale`（并留一行说明缩放唯一入口）；`_ColorDot` 选择动效时长随 reduceMotion。
- `matrixflow-native/lib/widgets/animated_task_title.dart`：`_layoutKey` 末位由 `double` 改为 `TextScaler`；测量 `TextPainter` 在 `finally` 中释放。
- 测试：新增 `matrixflow-native/test/os18_text_scaling_test.dart`（10 项默认回归）、`test/review/os18_review_probe.dart`（OS-R09a/b，有意不带 `_test.dart` 后缀，不进默认套件）。未修改任何既有测试文件。
- 文档：仅本文件。

## 4. 验收覆盖与结果

新增回归（默认套件可发现）：

- 系统 × 应用倍率组合：`{small 0.88, standard 1.0, large 1.16} × {1.0, 1.25, 2.0}` 共 9 组，逐组量预览标题宽度对基线的比值，容差 3%（字形步进按字号取整，实测偏离 ≤1%；二次缩放会偏 12–16%，区分度足够）。
- 预览与正文一致：预览标题（16/`height:1.35`）与同 MediaQuery 下的普通 16 dp `Text` 行盒高度相等（±0.5 px）；标题与样例行高度比保持 `(16×1.35)/(14×1.4)`。
- 长中/英/日/混排 × 宽度 240/360/720 × 缩放 `noScaling`/1.25/2.0/非线性 1.4：逐行划线片段与 `RenderParagraph.getBoxesForSelection` 完全相等（两条独立测量路径互校），240 dp 下确认确实换行。
- 截断：`maxLines: 2` + ellipsis 时只划可见两行，且与渲染片段一致。
- 非线性 scaler 变更必须重测；未变参数必须复用缓存（`identical` 判 List 实例）；宽度变化必须失效。
- OS02 父子层级：`FontSizePref.large` × 系统 1.25 下，父任务与两个子任务行的划线各自匹配本行渲染片段（父为英文多行、子为中文/日文），放大未使行间串用几何。
- 主题色动效：允许动效时时长 200ms 且 100ms 处仍在途中；reduceMotion 开启时时长为 `Duration.zero`、一帧即 34 dp 终态；两种模式下 OS19 的 48 dp 热区都保持（`width/height ≥ 48`）。OS19 提示的设置页主题色 `8 + 48 + 10 = 66` 高度不变量未触碰——只改了 duration，尺寸逻辑与 `AccessibleTapTarget` 结构一字未动。

计数（固定 SDK）：

- OS18 专项 + 探针：`flutter test --no-pub test/os18_text_scaling_test.dart test/review/os18_review_probe.dart` **12/12**。
- 默认全量：`flutter test --no-pub` **524/524**（基线 514 + 本包新增 10，无回归）。
- `flutter analyze --no-pub` **0 issues**。
- 全部使用合成数据与 mock 持久化，未使用真实任务库、真实备份、任何 API 密钥，未发起网络请求。

## 5. 未测与残余限制

- **双端人工验收未做**（无 Android 设备、本轮未启动 Windows 应用）：放大后设置页预览与列表正文的**观感**一致性、逐行划线的视觉贴合、系统"减少动画"开启时主题色切换是否真的无中间帧，都只有 widget 测试证据，不是设备证据。
- **平台真实非线性缩放未测**：测试里的非线性 scaler 是按平台分档行为构造的合成模型；Android 厂商字体缩放与 Windows 显示缩放的真实曲线未采集。修后的缓存身份对任意 `TextScaler` 实现都成立，但"真实设备曲线下的观感"仍待人工确认。
- **painter 释放无红/绿探针**：Flutter 3.32.8 未提供 `TextPainter` 创建/释放计数，仓库默认未启用 `LeakTesting`（`test/flutter_test_config.dart` 未 `LeakTesting.enable()`），因此这条是代码级修复（`finally` 中 `dispose()`），只能由"测量结果不变 + 释放后不再使用该 painter"的回归间接保证，不宣称有独立反例。若要把它变成可验证项，需要全仓启用泄漏跟踪，属公共测试配置改动，未在本包做。
- 本包不触碰 Store、保存协议与 OS20 的命令边界；`search_screen.dart` 里 `subtask.completed = val` 这类直接写仍留给 OS20。

## 6. 跨包需求（不改对方文件，交集成人处理）

- **OS23 同类隐患**：`lib/widgets/quadrant_transition_layout.dart:398-420` 的 `_cardHeight()` 为每个象限标题 `TextPainter(...)..layout(...)`，读完 `painter.height` 即丢弃，同样未 `dispose()`（F15 的另一处同源问题）。它把 `MediaQuery.textScalerOf(context)` 传给 painter 的参数是对的，无二次缩放、无缓存身份问题，所以不影响 OS18 验收。
  - 最小接口建议：OS23 侧把该处改成 `try { ... } finally { painter.dispose(); }`，或后续两边共用一个"测量并释放"的 helper（届时可放 `lib/ui/` 或 `lib/widgets/` 的公共处，本包不预先建抽象）。
- **动效常量归属**：主题色点的 200ms 目前仍是 `settings_screen.dart` 内联字面量。OS23 统一动效策略时若把这类时长收进 `MotionPolicy`，本包的 `reduceMotion ? Duration.zero : 200ms` 判断可以直接被其吸收，替换点仅 `_ColorDot.build` 一处。

## 7. 集成时需要落到公共文档的内容

- 开源准备计划第 5 节：OS18 状态改为**已实施（2026-09-25；双端人工验收未测）**，并登记探针编号 **OS-R09**（现有 OS-R 只到 R08）。
- `ARCHITECTURE.md` 可记一句：字号缩放唯一入口是 `main.dart` 的 `MaterialApp.builder` + `CombinedTextScaler`，任何 widget/预览都不得再把 `fontScaleFactor` 乘进 `fontSize`；文本测量缓存以 `TextScaler` 对象本身为身份，临时 `TextPainter` 必须释放。
- `CHANGELOG.md` 顶部条目建议：设置页字号预览不再重复应用应用内字号倍率，放大预览与正文一致；逐行删除线在非线性系统缩放下不再错位。
- `AGENTS.md`/`HANDOFF.md`：本波 A 包（OS18）已收口，与 B=OS20、C=OS23 无文件重叠；OS23 落地时请一并处理第 6 节那条 painter 释放。
