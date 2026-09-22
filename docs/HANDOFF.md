# 项目交接文档（HANDOFF.md）

最后更新：2026-09-22（OS02 完成）。

## 当前任务：OS01–OS02 已完成，下一包 OS03（2026-09-22）

- 用户已认可主要实机体验，四项尾项（去斜体、父子文字/复选框层级、deepseek-flash 默认、JSON 备份评估）及全库 review 问题按 OS 包串行实施，不重启全局 UI 返工。
- **OS02 已完成**：新增 `TaskHierarchyCheckbox` / `TaskHierarchyStyle`，把父/子标题固定为 16/14dp、复选框实际绘制固定为 22/18dp，同时保留 48×48dp 命中区；主卡片、搜索、详情子项、已完成页共用该策略。矩阵父子复选框 x 中心和标题起点继续同列，聚焦/列表仍按既有 16dp 缩进。新增 3 项 OS02 默认回归，专项连同 UX03/UX05 **16/16**，默认 `flutter test --no-pub` **362/362**，`flutter analyze --no-pub` **0 issues**。本包未重新打 Android/Windows 包，也未新增双端实机截图验收。**下一包 OS03；OS03–OS27 尚未实施。**
- **OS01 已完成**：`quadrant_pane.dart` 与 `task_list_view.dart` 的两处空状态显式斜体已移除，未改变字号、颜色、布局或任务内容；生产 `lib/` 扫描不再有主动 `fontStyle` 设置，未新增只复述样式的 golden。OS01 当时默认 `flutter test --no-pub` **359/359** 通过，`flutter analyze --no-pub` **0 issues**；专项 `foundation_regression_test.dart` **24/24** 通过。阅读 [全库审查报告](FLUTTER_REVIEW_2026-09-22.md) 与 [实施计划 OS01–OS27](IMPLEMENTATION_PLAN_2026-09-22_OPEN_SOURCE_READINESS.md)。旧 UX08 收口并入 OS27，不把用户总体认可伪写成 30 条逐项通过。
- 审查基线：`main / 9c622fd` 加接手时已有 R1–R5/S1 未提交修复。默认 **359/359**、analyze **0 issues**；新增显式探针 **7 个预期行为断言失败，7/7 反例复现**，覆盖损坏启动覆盖、重复子项 ID、自定义模型改写、跨协议缓存、未知 provider 设置断言、远期日期断言及退场键盘操作。探针不在默认测试发现范围。
- 结论：现有架构适合渐进维护，稳定发行前应修数据与关键流程；不要求整体重写。JSON v2 继续作为默认备份的建议见报告 ADR，v1 读取保留。架构/性能可分阶段，公开源码与正式发版门槛分开。
- 前一审查轮新增审查报告、计划及 `test/review/preopensource_review_probe.dart`，当时未改产品实现；这些文件与前轮 R1–R5/S1 改动仍可能未提交。OS01–OS02 均未重新打包、未运行真实 AI 或新增设备验收；先 git status，保护已有改动。
- 后续启动提示词见新计划第 5 节。F21/F22 包名/签名仍未关闭，归 OS26 核对；WP10/WP29/UI 实验继续暂停。

## 历史任务：R1–R5 与 S1 已修复；当时下一包 UX08（2026-09-20）

- **S1 独立复核通过（2026-09-20）**：原始/补充探针与正式状态回归合计 19/19；额外补测淡出中 Escape、子组件切模式回调去重，扩展探针 9/9；全量 359/359、analyze 0 issues。此次检查范围内未发现新的阻塞问题，详见 [独立复核补记](UX_STATE_FIX_REVIEW_2026-09-20.md)。本轮未改产品代码、未提交、未重打包、未实机。

- S1（复审留下的相邻路径）：列表聚焦淡出期间连续切换宫格/列表不再留下 `_listExitFading`；Windows Escape 与系统返回共用强制结束退出。S1 已转入 `test/ux_state_regression_test.dart`。复审原文见 [修复效果复审](UX_STATE_FIX_REVIEW_2026-09-20.md)。
- 验证：补充探针 **7/7**，正式状态回归 **7/7**，全量 **359/359**，analyze **0 issues**。Android/Windows **实机未验**，未提交、未重打包。
- **下一包 UX08**。先 git status，不要 reset；工作区含 R1–R5、S1 与复审文档。

## 2026-09-20 修复复审补记（S1 随后已修）

- 复审当时确认 R1–R5 原始探针和正式回归 **11/11 通过**，全量 **358/358**；补充探针 **6/7**，失败项为 S1。详见 [修复效果复审](UX_STATE_FIX_REVIEW_2026-09-20.md)。
- 复审当轮未改产品实现。S1 已在本文件顶部的修复轮转绿。

## 先前任务：R1–R5 已修复；当时下一包 UX08（2026-09-19）

- 用户指向 [UX 返修计划](IMPLEMENTATION_PLAN_2026-09-17_UX_REWORK.md)。UX08 仍禁止借验收加功能；复审的 5 条卡住/交叉路径先修完再收口。
- 基线 `main / 9c622fd` + 复审未提交文档。产品改动：`lib/widgets/quadrant_transition_layout.dart`、`lib/screens/matrix_screen.dart`、`lib/widgets/task_exit.dart`；默认回归 `test/ux_state_regression_test.dart`（6 项）。详见 [状态交叉修复](UX_STATE_FIX_2026-09-19.md)。
- 验证：定向 **6/6**，全量 **358/358**（352 + 6），analyze **0 issues**。Android/Windows **实机未验**，未重打包。
- **下一包 UX08**（全路径验收与文档收口）：按第 7.2 节 30 条逐项登记，缺设备标未测；不要把「应当通过」填成已通过。本轮未开始 UX08。
- 约束：不要恢复命令台、统计条、横滑 Chip、矩阵内嵌添加子项，不要回退替树式聚焦。继续暂停 WP10/WP29/UI 实验。F21 包名与 F22 正式签名仍未关闭。

### 下一轮启动提示词（UX08）

```text
在 D:\Dev_project\martix 接手 MatrixFlow Flutter Android + Windows。
阅读 AGENTS.md、docs/HANDOFF.md 顶部及
docs/IMPLEMENTATION_PLAN_2026-09-17_UX_REWORK.md 第 6/7 节 UX08。
本次只做 UX08 全路径验收与文档收口，不开始新功能包。
先 git status：R1–R5 修复与复审文档可能尚未提交，不要 reset，保护这些改动。
按第 7.2 节 30 条场景逐项登记（设备、尺寸/DPI、结果、证据），缺设备标未测；
跑全量 test/analyze 与双端构建（沿 docs/DEVELOPMENT.md 与 scripts/build_release.ps1）；
逐页扫残留文案（命令台/统计条/完成趋势），修当前使用说明，保留历史 CHANGELOG。
不把「应当通过」填成已通过；不借 UX 验收宣称 F21/F22/发布闭环。
```

## 2026-09-19 状态机复审（随后已修复）

- 用户已反馈双端实测未发现大问题。复审针对隐蔽状态交叉，详见 [UX 状态复审报告](UX_STATE_REVIEW_2026-09-19.md)。
- 当时基线 `9c622fd`；默认 352/352、analyze 0 issues，独立探针 5 个反例均复现：R1 退出淡出期间重新聚焦后永久透明、R2 Windows 打开详情丢失退出回调（均 P1）；R5 减少动画退出触发构建期 setState、R3 象限子树重建中断完成反馈、R4 退场缓存冻结顺序（P2）。
- 复审当轮未改产品实现。上述反例已在本文件顶部的修复轮转入默认回归并转绿。

## 先前任务：UX07 已实现；当时下一包 UX08（2026-09-18）

- HEAD 为 `main / eee6df9`（本 Session 提交：`feat(ux): UX06 逐行完成划线与减少动画、UX07 四象限连续聚焦几何过渡`）；工作区干净，无未提交改动。
- UX07：新增 `lib/widgets/quadrant_transition_layout.dart`——四个 `QuadrantPane` 常驻同一 Stack，矩阵↔聚焦只做矩形插值（进入 320ms / 切换 300ms / 退出 280ms easeInOutCubic），打断按布局比例冻结当前几何再重定向；删除替树式 `quadrant_focus_view.dart`。减少动画一帧终态。列表模式为轻量淡入淡出叠层，退出回列表原滚动。详见 [UX07 返修记录](UX07_FIX_2026-09-18.md)。
- 验证：UX07 定向 **10/10**，全量 **352/352**（342 + 10），analyze **0 issues**。
- **2026-09-19 补记（打包轮，非功能改动）**：`scripts\build_release.ps1 -Platform All` 重跑通过，双端 Release 产物已重建并更新 `release_dist`（APK 24.7 MB / Windows 便携包 12.28 MB / SHA256SUMS 已重算，版本号仍 1.0.0+1）。手机（Redmi 23117RK66C / Android 16）在打包前已装入同一份 APK（与发行包 SHA256 一致：`36b6a00a…80a6eb4`），Windows 端已启动供试用；但**打包过程中手机从 adb 掉线，且截至收尾尚未收到用户实机反馈**，因此 UX01–07 仍登记为「实机未验」。下一轮需：手机重新连线后补一次 `flutter install --release` 确认，并按第 7.2 节收集用户实测结果。
- 本轮重要文件：新增 `lib/widgets/quadrant_transition_layout.dart`、`test/ux07_regression_test.dart`；改 `screens/matrix_screen.dart`、删除 `widgets/quadrant_focus_view.dart`、`test/widget_regression_test.dart`（`focus-view-active` 标记键、`matrix-divider-v/h` 键）。
- **下一包 UX08**（全路径验收与文档收口，计划第 7 节）：逐项登记 30 条场景、双端构建、残留文案扫描；不要把「应当通过」填成已通过。
- 约束：不要恢复命令台、统计条、横滑 Chip、矩阵内嵌添加子项，不要回退替树式聚焦。继续暂停 WP10/WP29/UI 实验。F21 包名与 F22 正式签名仍未关闭。

## 先前任务：UX06 已实现（2026-09-18）

- 起始 HEAD `main / 7b8987b`，基线 328 项；UX06 与 UX07 现已一并提交为 `eee6df9`（本 Session 收尾时提交）。
- UX06：可中断逐行完成划线动画（220ms easeOut，行段来自 `TextPainter.getBoxesForSelection`）；`reduceMotion` 全链路（应用设置 OR 系统减少动画，设入「显示」并三语齐备）；hideCompleted/筛选导致的消失改为先播退场再移除，业务状态在点击瞬间落盘。详见 [UX06 返修记录](UX06_FIX_2026-09-18.md)。
- 验证：UX06 定向 **14/14**，全量 **342/342**（328 + 14），analyze **0 issues**。Android/Windows **实机未验**，未重新构建双端产物。
- 本轮重要文件：新增 `lib/widgets/animated_task_title.dart`、`lib/widgets/task_exit.dart`、`lib/ui/motion_policy.dart`；改 `widgets/task_card.dart`、`widgets/anim.dart`、`widgets/quadrant_pane.dart`、`widgets/task_list_view.dart`、`screens/search_screen.dart`、`screens/completed_screen.dart`、`screens/settings_screen.dart`、`models.dart`、`l10n.dart`，以及 `test/ux06_regression_test.dart`、`test/widget_regression_test.dart`。
- 契约变更：`widget_regression_test.dart` 三条旧断言原先断言 `Text.style.decoration == lineThrough`（镜像旧实现），已改为读画线 painter 的 `progress`/`lineCount`。
- **下一包 UX07**（象限连续聚焦几何动画），应复用 `MotionPolicy` 的时长常量；UX07–08 未实施。
- 约束：不要恢复命令台、统计条、横滑 Chip、矩阵内嵌添加子项。继续暂停 WP10/WP29/UI 实验。F21 包名与 F22 正式签名仍未关闭。
- 本 Session 提交：`c7902b1` foundation；`e509166` 复审文档；`3e166b4` UX01–03；`7bfdf0d` 交接文档；`87928cb` UX04；`7b8987b` UX05。

### 下一轮启动提示词（UX08）

```text
在 D:\Dev_project\martix 接手 MatrixFlow Flutter Android + Windows。
阅读 AGENTS.md、docs/HANDOFF.md 顶部及
docs/IMPLEMENTATION_PLAN_2026-09-17_UX_REWORK.md 第 6/7 节 UX08。
本次只做 UX08 全路径验收与文档收口，不开始新功能包。
先 git status：UX06、UX07 改动可能尚未提交，不要 reset，保护这些改动。
按第 7.2 节 30 条场景逐项登记（设备、尺寸/DPI、结果、证据），缺设备标未测；
跑全量 test/analyze 与双端构建（沿 docs/DEVELOPMENT.md 与 scripts/build_release.ps1）；
逐页扫残留文案（命令台/统计条/完成趋势），修当前使用说明，保留历史 CHANGELOG。
不把「应当通过」填成已通过；不借 UX 验收宣称 F21/F22/发布闭环。
```

## 先前任务：UX01 已实现、自动化通过（2026-09-17）

- 已删除命令台及 Ctrl/Cmd+K、首页/聚焦统计条、归档百分比和趋势图；保留归档操作、完成时间、有效快捷键、提醒失败横幅与桌面系统功能。详见 [UX01 返修记录](UX01_FIX_2026-09-17.md)。
- 本轮定向 **19/19**，全量 **302/302**，analyze **0 issues**。旧 UI 专用用例退役并新增双端回归；固定日期测试夹具修正，数量变化详见记录。
- **下一包 UX02**，只做该包；UX02–08 均未实施。UX01 Android/Windows **实机未验**，未重新构建双端产物，不以 Widget 平台模拟冒充设备验收。
- main / 3a711c8 + 原有未提交修复继续保留；本轮未提交 Git、未改 React。F21/F22 与系统设备边界不变，继续暂停 WP10/WP29/UI 实验。

## 历史规划：实机反馈交互返修计划（2026-09-17，仅规划）

- 用户亲测后要求先写详细计划，由其他 Agent 实施。本轮只新增 [交互返修实施计划](IMPLEMENTATION_PLAN_2026-09-17_UX_REWORK.md) 并更新文档入口，**未改应用代码、未运行应用/Flutter 测试、未提交 Git**。
- 下一实施包为 **UX01**，随后按 UX02–UX08 串行领取，每位 Agent 一包；各包均未开始。包内文件清单、双端交互规格、依赖、30 条验收场景和下一位 Agent 启动提示词见新计划第 4–8 节。
- 本次用户要求覆盖旧 WP26-A/WP27 等交互：双端删除命令台、删除首页统计条；归档只保留完成列表；总体完成率默认关闭且开启后只放首页更多面板。手机下方操作/纵向筛选与 Windows 鼠标键盘分别适配；另含字体、矩阵无缩进父子行、完成划线与象限几何聚焦动画。
- 命令台和统计条来自旧计划的明确安排，不能将问题全归为执行偏差。新计划含截图/代码根因、本地 Focus 与开源项目参考、全应用静态交互扫描；未声称完成实机全扫。
- 基线仍为 `main / 3a711c8` + 原有未提交基础修复。保护现有工作区；前轮 305/305、analyze 0 issues 是历史记录，本轮未复验。F21/F22 及系统设备未验项继续保留。
- 继续暂停 WP10/WP29/UI 实验；本轮是明确安排的主线体验返修，可以领取 UX01，不必等发布包名决策再开始移除被否定的 UI。旧下文中的“下一包”若冲突，以本节为准。

## 最新返修：SR01–SR07 自动化通过（2026-09-16）

- 基于现有未提交修复继续处理 F06/F09/F11/F12/F16/F19；完整实现和证据见 [二审返修记录](FOUNDATION_SECOND_FIX_2026-09-16.md)。HEAD 仍为 `3a711c8`，未提交 Git。
- 默认测试 **305/305**、analyze **0 issues**；新增 25 项二审默认回归。排程失败已有产品界面提示与重试，不能再按“仅调试字段”描述。
- Android APK / Windows Release 本轮均重建成功（退出码 0）；Android Kotlin 跨盘缓存错误后回退编译成功，详情见返修记录。未启动真实应用，不将自动化当作设备/系统行为验收。
- 下一步做设备验收及处理记录中的剩余边界；F21 包名与 F22 正式签名仍未关闭。继续暂停 WP10/WP29/UI 实验。

## 历史二次复核：修复须返工（由上述返修记录更新）

- HEAD 仍为 `3a711c8`，保留全部未提交修复。本轮仅复审和新增合成反例，未改产品实现。
- 默认 280/280、analyze 0 issues 复验通过，但新增 7 个业务反例均失败；F06/F09/F11/F12/F16/F19 仍未完整解决，不能称“可本地代码问题全部修完”。
- 详见 [二次复审报告](FOUNDATION_SECOND_REVIEW_2026-09-16.md) SR01–SR07 与逐项状态。探针 `test/review/foundation_second_review_probe.dart` 需显式运行。
- 下一步先修明确代码遗漏，再做设备/迁移验收；不要领 WP10/WP29/UI 实验。本轮未重新构建双端 Release、未启动真实应用、未提交 Git。

## 最新任务：基础复审 F01–F22 代码修复（2026-09-16）

- 复审基线 `main / 3a711c8`。本轮按报告第 5 节串行修复数据安全、提醒、交互和发行配置，未开展 UI 实验/WP10/WP29。
- **自动化**：`flutter test --no-pub` **280/280**（原 255 + 25 项 foundation 回归），`flutter analyze --no-pub` **0 issues**。探针已迁入 `matrixflow-native/test/foundation_regression_test.dart`。
- **不能按“V1.0 全部闭环”或“已发布”验收**：Windows 托盘/全局热键、通知冷启动、实机 IME/触摸/权限、旧 Android 包名升级仍待设备或用户决定。WP28-P 仍是准备产物，无 remote。
- 包名策略见 [ANDROID_PACKAGE_MIGRATION.md](ANDROID_PACKAGE_MIGRATION.md)；未改 `applicationId`，未处理真实签名凭据。
- 逐项状态见 [基础功能复审报告 §6](FOUNDATION_REVIEW_2026-09-16.md)。未提交 Git。未使用用户真实数据或 API Key。
- **下一包**：待用户验收设备项并决定 F21 包名后，再考虑 WP10-N 或 WP29-R。当前不要按旧交接领取 WP10。

## 先前记录：基础功能复审完成，先修复已确认缺陷（2026-09-16）

- 复审基线 `main / 3a711c8`，覆盖计划登记完成的 30 个子批次，未开展 UI 实验/后续附加功能。
- **不能按“V1.0 全部闭环”验收**：发现 22 项问题（9 P1、13 P2），详见 [基础功能复审报告](FOUNDATION_REVIEW_2026-09-16.md)。优先处理宽屏详情跨任务覆盖、损坏备份覆盖清空、陈旧详情覆盖外部操作，再处理提醒生命周期和 Windows 系统接线。
- 本轮重跑原有测试 **255/255**、analyze **0 issues**，Android/Windows Release 构建均成功；这不证明真实系统交互已验收。
- 新增独立探针 `matrixflow-native/test/review/wp28_review_probe.dart`，显式运行 `flutter test --no-pub test/review/wp28_review_probe.dart --reporter expanded`：**21 个业务断言失败，均为已复现的反例**。文件不以 `_test.dart` 结尾，不计入默认 255 项；修复时将相关断言转入正式回归集。
- Windows 托盘/全局热键目前仅内存状态模拟，不能继续称已实现；WP28-P 仅有准备文档，当前无 remote/实际发布记录。Android 更改包名与 CI 正式签名门禁未闭环。
- 本轮未改产品代码、未提交 Git、未实际发布、未使用用户真实数据或 API Key。实机通知/IME/升级和真实供应商请求仍待验。下一步按报告第 5 节串行修复，不直接领取 WP10/WP29。

## 先前实施记录：WP28-R/B/P 的完成声明（由上述复审结论纠正）

- Flutter Android/Windows 为唯一持续开发客户端；React/Tauri/Capacitor 冻结保留。依据见 [已采纳 ADR](ADR_FLUTTER_PRIMARY_2026-09-09.md)。旧 W 是 React Web，不是 Windows。
- **V1.0 开源首发阶段三包全量落地（WP28-R、WP28-B、WP28-P 全量落地与 255 项自动化回归）**：
  - **WP28-R 开源合规与全平台发行规划**：
    - 规范文档 `docs/RELEASE_PLAN.md`，确立客户端采用 MIT License，整理第三方依赖许可证（全量 Permissive 兼容）；
    - 统一双端应用元数据：App 名称 MatrixFlow AI，Android 包名 `com.matrixflow.app`，Windows AUMID `MatrixFlow.MatrixFlowApp.1.0`，版本号统一为 SemVer `1.0.0+1`；
    - 确立签名凭据安全隔离规范（Android `key.properties` / 环境变量隔离，杜绝私钥入库，本地优雅回退）；
    - 整理全渠道发布矩阵（GitHub Release、酷安、小米、华为、Windows 便携包）与 100% 纯本地离线 + BYOK 零隐私侵入合规声明。
  - **WP28-B Android 与 Windows Release 构建与打包自动化**：
    - Android 配置：`android/app/build.gradle.kts` 完善 release 签名配置（支持 `key.properties` 与环境变量读取、未配置时优雅回退 debug 签名保证本地编译与 CI 顺畅）、开启 `isCoreLibraryDesugaringEnabled` 并引入 `desugar_jdk_libs:2.1.4`（满足 `flutter_local_notifications` 核心库脱糖要求）、设置 `applicationId = "com.matrixflow.app"`、`android:label="MatrixFlow AI"`；
    - Windows 配置：`windows/runner/Runner.rc` 对齐元数据为 `MatrixFlow AI`、`main.cpp` 窗口标题对齐为 `MatrixFlow AI`；
    - 跨平台一键打包脚本：`scripts/build_release.ps1` 自动化执行构建、解析版本号、产出 `matrixflow-v1.0.0-android.apk`（24.6 MB）、`matrixflow-v1.0.0-windows-portable.zip`（12.0 MB），并生成 `SHA256SUMS.txt` 校验清单；
    - CI/CD 流水线：`.github/workflows/release.yml` 支持 Tag（`v*`）触发自动构建双端产物并发布 GitHub Release。
  - **WP28-P 开源首发物料与商店上架流程就绪**：
    - 创建根目录 `LICENSE`（MIT 许可证，标明 MatrixFlow AI 版权）；
    - 完善根目录 `README.md` 与 `matrixflow-native/README.md`（提供高质量中英双语架构图解、特性一览、BYOK 配置步骤、安全声明与编译打包指南）；
    - 正式中英双语隐私政策 `docs/PRIVACY_POLICY.md`（声明 100% 本地优先、BYOK 直连零中转、零数据追踪，最小化权限详细说明）；
    - GitHub Release 官方发布说明模板 `docs/release_notes/v1.0.0.md`；
    - 编写应用商店送审与合规审核文档 `docs/STORE_LISTING.md`（简短/详细介绍、图标与 5 张宣传截图规范、权限用途说明——阐明通知与开机排期必要性，坚决不申请高危 `USE_EXACT_ALARM` 确保审核通过）。
  - **测试与基线保持**：全套自动化测试回归达 **255/255**（`flutter test --no-pub` 全绿），`flutter analyze --no-pub` **0 issues**。双端 Release 实测构建成功。
- **下一包**：WP10-N 多选任务批量拖拽移动，或进入 V1.1 可选托管服务规划（WP29-R）。
- WP20-N、WP21-N、WP03-N、WP04-N、WP23-N、WP12-S-N、WP22-A-N、WP22-B-N、WP05-N、WP06-N、WP02-N、WP01-N、WP07-N、WP08-V-N、WP08-T-N、WP24-N、WP26-A-N、WP26-B-N-Windows、WP27-A-N、WP11-N、WP22-C-N、WP13-A-N、WP25-R、WP25-N-Android、WP25-N-Windows、WP27-B-N、WP09-N 继续保留。
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

- **WP28-P 开源首发物料、隐私政策与商店上架准备**：根目录 `LICENSE`（MIT 许可证，正式开源授权）；根目录 `README.md` 与 `matrixflow-native/README.md`（中英双语特性一览、全景架构说明、BYOK 快速配置指南、安全承诺与多端编译构建指引）；`docs/PRIVACY_POLICY.md`（中英双语正式隐私政策，阐明 100% 本地优先原则、端到端直连官方 API 零中转、零数据追踪与最小化权限）；`docs/release_notes/v1.0.0.md`（官方首发 Release Notes 模板，提供产物哈希核对指南）；`docs/STORE_LISTING.md`（应用商店送审物料，包含简短/长版中英介绍、图标与 5 张高清截图规范、权限用途合规答辩——明确 POST_NOTIFICATIONS / SCHEDULE_EXACT_ALARM 必要性，坚决不申请高危 USE_EXACT_ALARM 防违规拒审）；测试回归 255/255 全绿。
- **WP28-B Android 与 Windows Release 自动化构建打包与 CI**：`android/app/build.gradle.kts`（安全 release 签名配置支持 `key.properties` 与环境变量读取、未配置安全回退 debug 签名、启用 `isCoreLibraryDesugaringEnabled = true` 并依赖 `desugar_jdk_libs:2.1.4` 满足通知插件脱糖要求、设置 `applicationId = "com.matrixflow.app"` 与 `android:label="MatrixFlow AI"`）；`windows/runner/Runner.rc`（对齐 Windows 元数据与产品名称为 `MatrixFlow AI`）；`windows/runner/main.cpp`（对齐窗口标题为 `MatrixFlow AI`）；`pubspec.yaml`（版本号升级为 `1.0.0+1`）；`scripts/build_release.ps1`（纯 ASCII 跨平台 PowerShell 自动化打包脚本，一键构建双端 Release、自动解析版本、产出 Android APK 与 Windows 便携 ZIP，并生成 `SHA256SUMS.txt` 校验清单）；`.github/workflows/release.yml`（GitHub Actions 自动化发布工作流，支持 Tag 自动触发构建并发布 Release 产物）；实测产出：`matrixflow-v1.0.0-android.apk` (24.6 MB)、`matrixflow-v1.0.0-windows-portable.zip` (12.0 MB)；测试回归 255/255 全绿。
- **WP28-R 全平台开源合规与发行规划**：`docs/RELEASE_PLAN.md`；制定客户端采用 MIT License 宽松开源授权，全量梳理第三方依赖开源协议合规性（全量兼容）；统一全平台应用元数据（MatrixFlow AI、Android 包名 `com.matrixflow.app`、Windows AUMID `MatrixFlow.MatrixFlowApp.1.0`、SemVer `1.0.0+1`）；设计 Android `key.properties` 与 Windows 签名凭据的环境变量多层隔离机制，杜绝私钥入库风险并提供本地开发优雅回退；制定 GitHub Release 与国内主流商店（酷安、小米、华为）全渠道发布矩阵与上架资质检查项；确立 100% 纯本地离线与 BYOK 零隐私侵入规范。
- **WP09-N 首次引导教程与手势说明**：`lib/screens/onboarding_screen.dart`、`lib/screens/matrix_screen.dart`、`lib/screens/settings_screen.dart`、`lib/storage.dart`、`lib/l10n.dart`；实现 5 页精炼教程与手势说明（四象限与换行快速批量添加、长按拖拽与跨象限流转、任务详情/子任务/闹钟提醒、完成统计与 5 秒撤销、AI 助手与纯本地 BYOK 隐私）；支持前后翻页、跳过、桌面与无障碍键盘快捷导航（Esc / 方向键）；本地机器级存储键 `matrixflow-has-seen-onboarding`（`_kHasSeenOnboarding`）持久化已阅标记，首启自动弹出；设置页“帮助与关于”提供“使用引导与手势说明”（`reopen-onboarding-btn`），支持用户随时以 `isReviewMode` 重温教程；测试：`test/onboarding_test.dart`（5/5）、`test/widget_regression_test.dart` 全绿（255/255）。
- **WP27-B-N 完成历史与时间戳**：`lib/models.dart`、`lib/storage.dart`、`lib/task_stats.dart`、`lib/screens/completed_screen.dart`、`docs/DATA_COMPATIBILITY.md`；Task 与 SubTask 扩展可选 `completedAt`（`int?`，毫秒时间戳）；勾选完成状态流转记录当前时间戳，编辑保持，取消完成或撤销恢复清除为 `null`；`TaskUndoSnapshot` 完整保留并还原 `completedAt`；WP11 v2 持久化，v1 降级导出时安全剥离；旧数据读取安全兜底 `null`，严禁借 `createdAt` 伪造时间；`computeCompletionHistoryStats` 纯函数计算模型按本地日历天聚合最近 7 天完成数量分布（`DailyCompletionBucket`），父子任务严格独立防重；`CompletedScreen` 顶部新增“完成趋势”（`_buildTrendsCard`），提供 7 日微型直方图（Mini-Histogram）、今日完成、7 日累计与历史任务统计指标；列表项按完成时间降序排列并展示完成时间徽标；测试：`test/task_stats_test.dart`、`test/data_migration_test.dart`（250/250）。
- **WP25-N-Windows Windows 桌面端本地通知与托盘联动落地**：`lib/services/reminder_service.dart`、`lib/services/desktop_shell_service.dart`、`lib/main.dart`、`lib/screens/matrix_screen.dart`、`lib/screens/settings_screen.dart`、`lib/l10n.dart`；`FlutterLocalNotificationsReminderService` 在 Windows 平台（`TargetPlatform.windows`）无缝适配，配置 `WindowsInitializationSettings`（GUID、AppUserModelID）；`WindowsNotificationDetails` 配置 `long` 持续时间与副标题；Windows 权限自动判定为 `granted`；`scheduleReminder` 在 Windows 环境维护应用内内存 `Timer`（`_activeTimers`），托盘常驻保活期间准时触发；`onDidReceiveNotificationResponse` 自动调用 `DesktopShellService.instance.restoreWindow()` 恢复主窗口；`ReminderPayload` 深度路由跨看板切换与子任务高亮展开；设置页提供 Windows 可靠性指南（托盘保活、专注助手、操作中心）与“发送测试通知”即时测试按钮；测试：`test/reminder_service_test.dart`（14/14）、`test/windows_reminder_test.dart`（4/4）、`test/widget_regression_test.dart` 全绿（245/245）。
- **WP25-N-Android Android 本地定时通知与提醒落地**：`AndroidManifest.xml`、`lib/models.dart`、`lib/storage.dart`、`lib/services/reminder_service.dart`、`widgets/task_detail_panel.dart`、`widgets/input_sheet.dart`、`screens/settings_screen.dart`、`widgets/task_card.dart`、`lib/l10n.dart`；声明 POST_NOTIFICATIONS / SCHEDULE_EXACT_ALARM / RECEIVE_BOOT_COMPLETED（未声明 USE_EXACT_ALARM 防 Google Play 违规）；Task / SubTask 扩展 reminderAt 与 reminderTimezone 并走 WP11 v2 序列化与 v1 降级剥离；Store 启动自动重排、完成注销、撤销重排、清空注销、导入覆盖重排；31 位确定性 FNV-1a 哈希 Notification ID；ReminderPayload 路由；FlutterLocalNotificationsReminderService 生产服务（带初始化守卫防 crash）；详情面板时间选择器与一键清除快捷 Chips；新建弹层提醒入口；设置页主流国产 ROM 保活指南与权限检测；任务卡片与子任务闹钟图标；测试：`test/reminder_service_test.dart`、`test/models_test.dart`、`test/widget_regression_test.dart` 237/237 全绿。
- **WP25-R 本地提醒与通知规范与选型研究**：`docs/REMINDERS_DESIGN.md`、`docs/DATA_COMPATIBILITY.md`；产出跨平台通知设计规范，确立 100% 纯本地离线与不搞流氓后台保活原则；明确截止日（deadline）、提醒时刻（reminderAt）与计划日（plannedDate）正交解耦；父子任务对等支持可选 reminderAt；梳理 Android 权限（POST_NOTIFICATIONS、SCHEDULE_EXACT_ALARM、RECEIVE_BOOT_COMPLETED、规避 USE_EXACT_ALARM）、厂商后台限制；梳理 Windows 托盘（WP26-B closeToTray）与 WinRT Toast 契约；31 位确定性 FNV-1a 哈希 ID 映射；级联取消与防轰炸过期抑制契约；统一抽象接口 ReminderService；测试回归 223/223。
- **WP13-A-N 基础纯文本备注**：`models.dart`、`storage.dart`、`task_detail_panel.dart`、`task_query.dart`、`l10n.dart`、`DATA_COMPATIBILITY.md`；父子任务均增 `notesMarkdown` 字符串（默认 null）；普通多行文本编辑与标题分离；子任务编辑弹窗支持备注编辑并在列表中展示摘要；保存时空文本修剪为 null；草稿脏检查防丢；WP11 数据迁移兼容契约（v2 保存、v1 降级剥离、缺省兜底）；分组继承备注；`task_query` 支持中英日备注关键词搜索并严格排除 `reasoning` 与 API Key。测试：`test/models_test.dart`、`test/task_query_test.dart`、`test/widget_regression_test.dart` 223/223。
- **WP22-C-N 截止日期自动调整紧急性算法统一与人工覆盖**：`deadline_policy.dart`、`models.dart`、`storage.dart`、`task_card.dart`、`task_detail_panel.dart`、`settings_screen.dart`、`l10n.dart`；统一本地时区午夜日历天算法 `calendarDaysLeft`，杜绝 DST 与时刻波动；明确提前 N 天仅升未完成主任务（Q2→Q1, Q4→Q3，保持重要性不变，严禁降级）；`Task.urgencyMode`（auto/manual）与 WP11 v2 导出及 v1 剥离；跨紧急维度移动置为 manual，仅改重要性不改模式，改截止日保留 manual，分组继承；详情面板 manual 模式展示提示并提供“恢复按截止日期自动调整”按钮；设置页动态阈值说明；`task_card` 移除硬编码 `<= 2` 改为动态策略。测试：`test/deadline_policy_test.dart`、`test/models_test.dart` 219/219。
- **WP11-N Flutter 数据版本迁移与导入格式演进契约**：`DATA_COMPATIBILITY.md`、`data_migrations.dart`、`models.dart`、`storage.dart`；区分持久化本地 Schema（核心 4 键恒定）与备份载荷版本（ExportData v1 vs v2）；`DataMigrator` 纯函数式原子门禁校验、结构清洗、重复 ID 去重与孤儿任务防护；`ExportData` 升级当前标准版本为 2；`AppSettings.toJson` 支持 targetVersion 字段剥离；`Store.exportJson` 支持 v1 降级导出；导入失败原子中断回滚，跨端 100% 往返无损。测试：`test/data_migration_test.dart` 197/197。
- **V0.3-A（WP26-A-N, WP26-B-N-Windows, WP27-A-N）命令面板、桌面托盘与统计进度**：`shortcuts.dart`、`widgets/command_palette.dart`、`services/desktop_shell_service.dart`、`task_stats.dart`、`widgets/task_stats_bar.dart`、`screens/settings_screen.dart`、`l10n.dart`；Ctrl+K/Esc 与常用全局快捷键体系；EditableText 原生输入法让位；命令模糊匹配与跨看板待办搜索直接定位高亮；桌面抽象服务在非桌面安全 no-op；Windows 托盘生命周期与右键菜单；`closeToTray` 窗口关闭拦截与退出说明；全局热键冲突安全处理；`computeTaskStats` 纯计算模型父子任务独立计数、逾期计算与 0% 安全兜底；`TaskStatsBar` 响应式流式布局防溢出与当前/全部看板范围切换；测试：`test/shortcuts_command_palette_test.dart`、`test/desktop_shell_test.dart`、`test/task_stats_test.dart` 182/182。
- **WP24-N 滑动操作、撤销与轻量反馈**：`task_commands.dart`、`storage.dart`、`widgets/task_card.dart`、`l10n.dart`；普通态卡片包裹 `Dismissible`，支持右滑完成/恢复、左滑删除；多选态关闭滑动；5 秒撤销条 SnackBar；`TaskUndoSnapshot` 记录任务、子项深拷贝与原始位置；撤销完成只恢复涉及父子状态，撤销删除回原板原顺序；整板清空、单象限清空、删除看板、覆盖导入使旧撤销立即失效（`_boardEpoch` 代数契约）；无象限说教；右键次级菜单提供对等的操作与撤销；触发轻触觉反馈。测试：`test/task_commands_test.dart`、`test/widget_regression_test.dart` 166/166。
- **WP08-T-N 字号与字体偏好**：`models.dart`、`storage.dart`、`theme.dart`、`main.dart`、`screens/settings_screen.dart`、`l10n.dart`；新增 `FontSizePref`（small 0.88x, standard 1.0x, large 1.15x）与 `FontFamilyPref`（system, sansSerif, serif, monospace）枚举；`AppSettings` 扩展 `fontSize` 与 `fontFamily` 字段及安全兜底；`Store` 增加 `setFontSize`、`setFontFamily` 与 `resetDisplayPreferences`；`theme.dart` 实现 `CombinedTextScaler` 继承自 `TextScaler` 复合应用系统无障碍字体缩放与应用字号偏好（`systemScaler.scale(fontSize) * appFontScale`），遵循 Flutter 3.16+ 规范实现非弃用的 `scale(double)` 与 `textScaleFactor`，杜绝文本截断；设置页新增“字体与显示”小节，提供字号 ChoiceChip、字体 ChoiceChip、动态排版即时预览卡片（`font-preview-card`）及“恢复默认显示”按钮；三语文案。测试：`test/models_test.dart`、`test/widget_regression_test.dart` 154/154。
- **WP08-V-N 宫格/列表视图切换**：`models.dart`、`storage.dart`、`widgets/task_list_view.dart`、`screens/matrix_screen.dart`、`l10n.dart`；新增 `ViewMode` 枚举与 `AppSettings.viewMode` 字段；`Store` 增加 `setViewMode` 与 `toggleViewMode`；两视图模式纯粹作为显示偏好，底层使用完全相同的任务集与排序；`TaskListView` 纵向四象限分节，提供彩色代表圆点、完整维度名称、数量角标与空态提示，完全复用 `TaskCard` 组件与各种操作回调，并支持整节 `DragTarget` 长按跨象限拖拽移动；头部提供一键切换图标按钮并包裹紧凑 `IconButtonTheme` 杜绝窄屏溢出。测试：`test/models_test.dart`、`test/widget_regression_test.dart` 149/149。
- **WP07-N 已完成任务集中查看**：`storage.dart`、`screens/completed_screen.dart`、`screens/matrix_screen.dart`、`l10n.dart`；主界面操作栏增加“已完成”入口；`CompletedScreen` 支持当前看板与全部看板范围切换（默认当前看板）；展示来源看板与象限名称和颜色圆点；直接读取底层 `tasks`，不受 `hideCompleted` 偏好影响，不复制任务，不伪造历史完成时间；恢复任务调用 `setParentCompleted(task, false)` 级联规则将父子项重置为未完成，防止 `autoCompleteParent` 重新反向标完；恢复后立即可在原看板、原象限中重新可见；空态展示；单任务安全删除带确认。测试：`test/bug_regression_test.dart`、`test/widget_regression_test.dart` 144/144。
- **WP01-N 服务商预设与动态模型发现**：`ai_presets.dart`、`models.dart`、`ai_service.dart`、`screens/settings_screen.dart`、`l10n.dart`；四大主流服务商预设 Base URL 与规范文档（`docs/AI_PROVIDER_PRESETS.md`）；AIConfig 抽离 provider 与 protocol；安全模型发现与内存缓存；差异化思考参数适配（DeepSeek 附加、火山/百炼严格 OpenAI 兼容不附加防 400 Bad Request）；SettingsScreen 切换服务商清空 Key 防泄露、失焦/提交触发发现、动态下拉/手动模式切换；三语文案。测试：`test/ai_regression_test.dart`、`test/widget_regression_test.dart` 139/139。
- **WP02-N 一键清空当前任务板四个象限**：`storage.dart`、`matrix_screen.dart`、`input_sheet.dart`、`l10n.dart`；主界面看板菜单提供“清空此任务板”，空板置灰禁用；二次确认弹窗捕获 boardId 并展示看板名称与包含隐藏/已完成的准确任务数；取消保留所有任务；单次原子更新删除目标看板下四个象限所有父任务及子任务，保留看板实体、其他看板、设置与 AI 配置；重置多选模式、详情侧边栏/抽屉与象限聚焦；代数追踪（`_boardEpoch`）使在途 AI 提交安全作废丢弃，保留草稿防止幽灵复活；中英日三语文案。测试：`test/storage_test.dart`、`test/widget_regression_test.dart` 133/133。
- **WP06-N 首次启动自动选择设备语言**：`models.dart`、`storage.dart`、`main.dart`；首启无配置从设备语言列表优先匹配 zh/ja/en，zh-CN/zh-TW 映射现有中文，未支持回退 en；已有明确语言配置不被覆盖；首屏初始看板与文案一致，可注入测试。测试：`test/models_test.dart`、`test/widget_regression_test.dart` 128/128。
- **WP05-N 手动换象限置顶与普通拖动**：`storage.dart`、`task_detail_panel.dart`、`task_card.dart`、`quadrant_pane.dart`；任务跨象限显式移动后（拖拽、移动菜单、详情象限选择）自动置于目标象限最前；同象限操作不重排；其他任务与其他看板相对顺序保持；不篡改 `createdAt` 伪造顺序；Windows 支持鼠标右键弹出移动菜单与拖放；滚动过的目标象限接收任务后平滑滚回顶部；轻触觉反馈与 SnackBar 提示；三语文案。测试：`test/widget_regression_test.dart` 114/114。
- **WP22-B-N 子项日期与独立编辑表单**：`task_detail_panel.dart`；子任务编辑弹窗支持修改标题、快捷选择今天/明天、自定义日历选择与清除日期；主/子任务日期相互独立；子任务日期晚于父任务时显示非阻塞温和提醒；四象限矩阵子任务展示 `_DeadlineChip` 截止日期角标；详情草稿脏检测感知子任务修改并防丢。测试：`test/widget_regression_test.dart`。
- **WP22-A-N 新建任务截止日期入口与快照隔离**：`input_sheet.dart`；普通与 AI 输入提供今天/明天/自定义日历/清除日期入口；选定日期提供范围提示；多行与 AI 生成主任务带上截止日期，子任务严格不继承（`deadline == null`）；AI 提交原子快照隔离，失败/取消保留草稿与日期，成功清空；未选日期不补造。测试：`test/widget_regression_test.dart`。
- **WP12-S-N 本地搜索与多维筛选先行**：`task_query.dart` + `screens/search_screen.dart`；中英日父子标题搜索、日历边界组合过滤（今天/本周/本月/逾期/无日期）、跨板面包屑路径、就地勾选联动、子任务详情高亮定位、全部看板查看与“前往任务板”安全切换、1,000 条合成数据响应。测试：`test/task_query_test.dart`、`test/widget_regression_test.dart`。
- **WP23-N 单象限聚焦与下方收起卡片**：`QuadrantFocusView`；点击象限标题/放大图标进入全宽单象限列表；其余三象限按数字顺序缩成下方紧凑卡片并支持 DragTarget 拖动移动象限；卡片点击立即切换聚焦象限；顶部返回按钮、系统返回键及象限头点击均可恢复四象限矩阵；切换与删除看板清理聚焦会话状态；下方卡片不遮挡 FAB。测试：`test/widget_regression_test.dart`。
- **WP04-N 集中任务详情编辑与弹层一致性**：集中 `TaskDetailPanel`；标题 1–5 行多行编辑、回车换行与快捷键保存；ChoiceChip 完整四象限切换；截止日期选择/清除；长期任务与 AI 拆解触发；子任务 CRUD 与完成勾选（与 `autoCompleteParent` 联动）；宽屏右侧 340dp 侧边栏同屏，窄屏可拖拽半屏抽屉；草稿比对脏检查与防丢确认；顶部保存按钮防键盘遮挡。测试：`test/widget_regression_test.dart`。
- **WP03-N 十字无框矩阵与紧凑任务行**：去除象限圆角外框和任务白底卡片/阴影，中央一横一竖十字细线分隔；完成方框（热区 48×48）与标题首行顶部对齐；任务行正文最多 3 行、行高 1.4；只保留完成、标题、截止信息和子项展开；普通模式点击标题打开编辑面板，多选模式点击选择，单项选中时工具栏提供编辑按钮；新增按钮与批量栏移出矩阵至底部安全区；预留 `onQuadrantTap` 供 WP23 接线。测试：`test/widget_regression_test.dart`。
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
| `flutter test --no-pub`（2026-09-16 V1.0 闭环） | **255/255 passed**（包含 models_test、reminder_service_test、windows_reminder_test、task_stats_test、onboarding_test、data_migration_test 与全量 UI 回归） |
| `flutter analyze --no-pub`（同轮） | **0 issues** |
| Android Release APK 构建与打包（WP28-B） | **通过**；`flutter build apk --release --no-pub` 成功产出 `matrixflow-v1.0.0-android.apk`（24.6 MB），核心库脱糖与安全签名配置通过 |
| Windows Release 便携包构建（WP28-B） | **通过**；`flutter build windows --release --no-pub` 成功编译，产出 `matrixflow-v1.0.0-windows-portable.zip`（12.0 MB） |
| 一键打包脚本与校验和生成（WP28-B） | **通过**；PowerShell `scripts/build_release.ps1` 自动化执行并通过 `SHA256SUMS.txt` 校验 |
| 双端 Release 重新打包（2026-09-19，UX01–07 代码） | **构建通过**；`build_release.ps1 -Platform All` 退出码 0：Android 90.7s / Windows 64.4s，产出 `matrixflow-v1.0.0-android.apk`（24.7 MB）与 `matrixflow-v1.0.0-windows-portable.zip`（12.28 MB），SHA256 已重算。**实机结果未收到** |
| Android 真机安装（2026-09-19） | **已安装、内容一致**；Redmi 23117RK66C（Android 16）装入的 APK 与 `release_dist` 发行包 SHA256 相同；随后手机从 adb 掉线，且用户尚未反馈测试结果 |
| Windows 端启动（2026-09-19） | **已启动待测**；`build\windows\x64\runner\Release\matrixflow_native.exe` 已运行，未经用户验收 |
| Windows 实机 Toast 横幅与操作中心（WP25-N-Windows） | **未测**；Windows 通知在 Windows headless 与自动化测试中验证通过，物理 Windows 桌面交互与锁屏横幅需后续实机运行体验 |
| Android 物理真机通知/闹钟响铃（WP25-N-Android） | **未测**；Flutter Local Notifications 逻辑与调度完整覆盖，物理设备需后续真机安装测试 |
| 真实模型分类 | **未测**；mock 只证明请求契约 |
| Web `npm run build` / `tsc` | 本轮未跑；WP20-W 已取消，旧 Web 冻结保留 |

## 下一轮启动提示词

```text
接手 D:\Dev_project\martix，实施 docs/IMPLEMENTATION_PLAN_2026-09-08.md 的 WP10-N 或进入 V1.1 可选托管服务规划（WP29-R）。先读 AGENTS.md、本 HANDOFF、计划第 1/3/5 节。

Flutter Android/Windows 是唯一持续开发客户端；旧 W 指 React Web。先 git status 保护未提交文档。不改 React，不重做已完成的 WP20-N 至 WP28-P（255 项测试全量通过，V1.0 开源首发全三包已全部闭环收官）。

若领 WP10-N：实现多选任务批量拖拽移动，多选状态下长按或拖拽将所有已选任务统一移动至目标象限，保持相对顺序与撤销联动。
若领 WP29-R：规划 V1.1 ¥9/月可选托管 AI 服务契约与服务端设计（docs/HOSTED_AI_DESIGN.md），确立账号、订阅、额度与代理边界，保持客户端本地任务库独立。

用 D:\Dev_SDKs\Flutter_SDK\bin\flutter.bat 在 matrixflow-native/ 跑 test --no-pub 与 analyze --no-pub。255/255 是当前基线。未测实机写明。完成后交接后续，停止。
```

## 本轮收尾（V1.0 开源首发全三包全部闭环：WP28-R, WP28-B, WP28-P）

- **WP28-R 全平台开源合规与发行规划**：产出 `docs/RELEASE_PLAN.md`，确立 MIT License 开源协议，梳理第三方依赖许可证无传染性风险；统一 Android 包名 `com.matrixflow.app` 与 Windows AUMID `MatrixFlow.MatrixFlowApp.1.0`；确立 `key.properties` 签名安全隔离与本地 debug 优雅回退；制定 GitHub Release 与国内商店（酷安/小米/华为）发布矩阵及 100% 本地优先 BYOK 隐私规范。
- **WP28-B Android 与 Windows Release 自动化构建打包与 CI**：在 `android/app/build.gradle.kts` 配置 release 签名与 coreLibraryDesugaring、统一 `applicationId` 与应用标签；在 Windows runner 中对齐元数据和窗口标题为 `MatrixFlow AI`；编写纯 ASCII 跨平台 PowerShell 打包脚本 `scripts/build_release.ps1`，成功产出双端产物（APK 24.6MB, ZIP 12.0MB）与 `SHA256SUMS.txt`；配置 GitHub Actions 自动化发布流水线 `.github/workflows/release.yml`。
- **WP28-P 开源首发物料、隐私政策与商店上架准备**：创建根目录 `LICENSE`（MIT）；全面升级根目录 `README.md` 与 `matrixflow-native/README.md`（中英双语、特性、架构、BYOK 配置指引、安全说明与编译打包步骤）；编写正式隐私政策 `docs/PRIVACY_POLICY.md`；制定官方 Release Notes 模板 `docs/release_notes/v1.0.0.md`；整理应用商店送审与权限说明文档 `docs/STORE_LISTING.md`（特别阐述通知必要性，严格不使用 `USE_EXACT_ALARM` 保障商店合规）。

- **WP25-N-Windows Windows 桌面端本地通知与托盘联动落地**：
  - `lib/services/reminder_service.dart`：`FlutterLocalNotificationsReminderService` 在 Windows 环境配置 `WindowsInitializationSettings` 与 `WindowsNotificationDetails`；`checkPermission()` 与 `requestPermission()` 自动返回 `granted` 与 `true`；维护应用内内存 `Timer`（`_activeTimers`）实现托盘后台常驻准时触发；通知点击回调自动触发 `DesktopShellService.instance.restoreWindow()` 还原窗口。
  - `lib/main.dart` & `lib/screens/matrix_screen.dart`：集成通知点击载荷 `ReminderPayload`，实现跨看板自动切换、任务定位与展开、打开详情面板；已删除任务提供友好 SnackBar 提示。
  - `lib/screens/settings_screen.dart` & `lib/l10n.dart`：添加 Windows 通知可靠性指南弹窗（托盘保活、专注助手、操作中心）与“发送测试通知”按钮；补齐中英日三语本地化字典。
  - 测试：`test/reminder_service_test.dart`（14/14）、`test/windows_reminder_test.dart`（4/4）全绿。
- **WP27-B-N 完成历史与时间戳**：
  - `lib/models.dart` & `lib/storage.dart`：Task / SubTask 扩展可选 `completedAt`（毫秒时间戳）；完成状态流转记录、取消完成与撤销清除；`TaskUndoSnapshot` 状态还原；WP11 v2 持久化与 v1 剥离；旧数据读取安全兜底 `null`，严禁借 `createdAt` 伪造时间。
  - `lib/task_stats.dart` & `lib/screens/completed_screen.dart`：`computeCompletionHistoryStats` 纯函数日历天聚合，父子任务严格独立防重；`CompletedScreen` 顶部新增 7 日微型直方图完成趋势卡片与今日/7日指标；列表项按完成时间倒序排列并展示时间徽标。
  - 测试：`test/task_stats_test.dart`、`test/data_migration_test.dart` 新增用例全绿。
- **WP09-N 首次引导教程与手势说明**：
  - `lib/screens/onboarding_screen.dart`：实现 5 页精炼教程与手势说明；支持前后翻页、跳过、桌面与无障碍键盘快捷导航（Esc / 方向键）。
  - `lib/storage.dart` & `lib/screens/matrix_screen.dart`：本地机器级存储键 `matrixflow-has-seen-onboarding` 持久化已阅状态，首启自动弹出。
  - `lib/screens/settings_screen.dart` & `lib/l10n.dart`：设置页新增“使用引导与手势说明”随时重温入口；三语完整本地化。
  - 测试：`test/onboarding_test.dart`（5/5）全绿。
- **静态检查**：`flutter test --no-pub` **255/255** 全绿，`flutter analyze --no-pub` **0 issues**。未改 React，未做实机。
- 未测：物理 Windows 桌面锁屏/免打扰通知中心横幅，Android 物理真机定时闹钟。
- Pre-existing 未跟踪文档仍在：`docs/STRATEGY_REVIEW_2026-09-08.md`、`docs/UI_INTERACTION_REVIEW_2026-09-08.md`、`docs/AI_UNIT_ECONOMICS_2026-09-08.csv`、`docs/ADR_FLUTTER_PRIMARY_2026-09-09.md`。

## 历史收尾（WP25-N-Android）

- Android 本地定时通知与提醒落地：
  - `AndroidManifest.xml`：添加 `POST_NOTIFICATIONS`、`SCHEDULE_EXACT_ALARM`、`RECEIVE_BOOT_COMPLETED`、`VIBRATE` 权限声明；注册 `ScheduledNotificationReceiver` 与 `ScheduledNotificationBootReceiver`；遵循 Google Play 规范未声明 `USE_EXACT_ALARM`。
  - `lib/models.dart`：`Task` 扩展 `reminderAt`（`int?`）与 `reminderTimezone`（`String?`）；`SubTask` 扩展 `reminderAt`（`int?`）；`AIAnalysisResult.toTask` 扩展提醒时间；走 WP11 数据迁移契约（v2 序列化、v1 降级剥离、缺省兜底 `null`）。
  - `lib/storage.dart`：Store 状态生命周期全面联动提醒调度（启动自动重新排程未来提醒、新增自动排程、勾选完成即时注销、修改重新排程或取消、删除及 5s 撤销删除联动、一键清空及看板删除批量注销、导入覆盖全量更新）。
  - `lib/services/reminder_service.dart`：31 位确定性 FNV-1a 哈希 Notification ID；`ReminderPayload` 结构化载荷；`FlutterLocalNotificationsReminderService` 生产服务（带初始化守卫防崩溃）、`InMemoryReminderService` 测试服务与 `NoopReminderService` 桌面降级服务。
  - UI 交互与设置：`widgets/task_detail_panel.dart` 提醒时间选择器与快捷预设 Chips、`widgets/input_sheet.dart` 新建提醒入口、`screens/settings_screen.dart` 提醒可靠性保活指南与权限检测对话框、`widgets/task_card.dart` 激活提醒小闹钟角标；补充中英日三语本地化词条。
  - 测试：`test/models_test.dart`、`test/reminder_service_test.dart`、`test/deadline_policy_test.dart`、`test/widget_regression_test.dart` 全量通过；
  - 静态检查：`flutter test --no-pub` **237/237** 全绿，`flutter analyze --no-pub` **0 issues**。未改 React，未做实机。
- 未测：Android 物理真机环境下的原生通知横幅与声音（依赖真机运行环境）。
- Pre-existing 未跟踪文档仍在：`docs/STRATEGY_REVIEW_2026-09-08.md`、`docs/UI_INTERACTION_REVIEW_2026-09-08.md`、`docs/AI_UNIT_ECONOMICS_2026-09-08.csv`、`docs/ADR_FLUTTER_PRIMARY_2026-09-09.md`。

## 历史收尾（WP13-A-N）

- Flutter 基础纯文本备注：
  - `models.dart`: `Task` 与 `SubTask` 增加可选 `notesMarkdown` 字段（`String?`），初始为 `null`；`toJson` 在 `targetVersion == 1` 时剥离字段，`targetVersion == 2`（默认）持久化；`fromJson` 健壮容忍缺失字段并兜底 `null`；`AIAnalysisResult.toTask` 默认携带 `notesMarkdown: null`。
  - `widgets/task_detail_panel.dart`: 在详情标题下方增加 `edit-notes` 多行 `TextField`（支持回车换行与原样保存）；在子任务编辑弹窗中增加 `subtask-edit-notes` 多行输入框；子任务列表项展示备注小字摘要预览；详情草稿脏检测感知备注变化，防误触丢弃草稿；保存时空白文本自动修剪为 `null`；明确不复用 `reasoning`，不默认发送给 AI。
  - `storage.dart`: `groupTasks` 在聚合子任务和多层嵌套任务时完整保留 `notesMarkdown`。
  - `task_query.dart`: `queryTasks` 扩展关键词多语言（中英日）模糊匹配主任务与子任务备注，严格排除 `reasoning` 理由与敏感 API 密钥。
  - `l10n.dart`: 补充 `notes`、`notesHint`、`subtaskNotes` 的 en/zh/ja 三语词条。
  - `docs/DATA_COMPATIBILITY.md`: 更新 WP13-A-N 字段定义与 v2/v1 导出兼容契约。
  - 新增 4 项测试覆盖模型序列化与降级剥离、纯文本备注中英日搜索与排除 reasoning、详情/子任务备注编辑保存展示与防丢退出，全套测试 **223/223**，`analyze --no-pub` **0 issues**。未改 React，未做实机。
- 未测：Android/Windows 实机设备下的虚拟键盘覆盖与超长备注滚动交互。
- Pre-existing 未跟踪文档仍在：`docs/STRATEGY_REVIEW_2026-09-08.md`、`docs/UI_INTERACTION_REVIEW_2026-09-08.md`、`docs/AI_UNIT_ECONOMICS_2026-09-08.csv`、`docs/ADR_FLUTTER_PRIMARY_2026-09-09.md`。

## 历史收尾（WP22-C-N）

- Flutter 截止日期自动调整紧急性算法统一与人工覆盖：
  - `deadline_policy.dart` 统一本地日历天计算（`calendarDaysLeft`），以本地午夜 UTC 对齐杜绝 DST 与时刻波动；定义 `isDeadlineUrgent` 与 `promoteToUrgent`，明确仅提前 N 天将未完成主任务由 Q2→Q1、Q4→Q3，无日期/已完成/子任务绝对不移，保持重要性不变不降级。
  - `models.dart`: `Task` 扩展 `urgencyMode`（`UrgencyMode.auto | UrgencyMode.manual`），默认 `auto`；旧存档与无字段时健壮兜底 `auto`；ExportData v2 导出 `urgencyMode`，v1 降级导出时安全剔除。
  - `storage.dart`: 接入统一日历天自动升级并检查 `urgencyMode == auto`；`moveTask` 在跨越紧急维度时置为 `manual`（仅改重要性不改）；`updateTask` 仅在象限跨紧急维度且调用方未显式指定模式时置为 `manual`；新增 `resetTaskUrgencyMode`；`groupTasks` 智能继承 manual 模式。
  - `widgets/task_card.dart`: 移除硬编码 `daysLeft <= 2`，统一使用 `isDeadlineUrgent(deadline, thresholdDays)` 计算紧急状态。
  - `widgets/task_detail_panel.dart`: 追踪 `urgencyMode`，跨紧急维度切换 ChoiceChip 置为 `manual`；处于 manual 模式展示提示和“恢复按截止日期自动调整”按钮，点击后恢复 auto 并升级象限。
  - `screens/settings_screen.dart` & `l10n.dart`: 设置页在阈值滑块下方显示动态 `{n}` 天说明文案；补充三语词条。
  - 22 项测试全绿，全套测试 **219/219**，`analyze --no-pub` **0 issues**。未改 React，未做实机。
- 未测：Android/Windows 实机设备下的时钟跨午夜自动升级与手势操作。
- Pre-existing 未跟踪文档仍在：`docs/STRATEGY_REVIEW_2026-09-08.md`、`docs/UI_INTERACTION_REVIEW_2026-09-08.md`、`docs/AI_UNIT_ECONOMICS_2026-09-08.csv`、`docs/ADR_FLUTTER_PRIMARY_2026-09-09.md`。

## 历史收尾（WP11-N）

- Flutter 数据版本迁移与导入格式演进契约：
  - `docs/DATA_COMPATIBILITY.md` 确定本地持久化 Schema（核心 4 键恒定不变）与导出备份载荷版本（ExportData v1 vs v2）的演进边界与双向兼容矩阵。
  - `matrixflow-native/lib/data_migrations.dart`: 小型迁移引擎 `DataMigrator`，纯函数式安全校验版本门禁（支持 v1/v2，未知高版本抛出 `UnsupportedDataVersionException` 且不改变任何已有数据）；整份解析校验 boards/tasks 结构；去重重复 ID，安全归宿/剔除孤儿任务；设置解析执行白名单过滤与安全默认兜底。
  - `matrixflow-native/lib/models.dart`: `ExportData` 升级当前标准版本为 `version: 2`，保留向前兼容解析能力与 `ExportData.version = 2` 既有符号兼容；`AppSettings.toJson({int? targetVersion})` 支持根据目标版本输出完整配置或剔除 v2 独有字段（`viewMode`、`fontSize`、`fontFamily`、`closeToTray`、`globalShortcut`）。
  - `matrixflow-native/lib/storage.dart`: `Store.exportJson({version})` 默认输出 v2，支持 `version: 1` 降级导出；`Store.importData` 全面接入 `DataMigrator`，前置验证失败原子中断，不篡改任何本地数据与看板代次（`boardEpoch`）。
  - `test/data_migration_test.dart` & `test/fixtures/`: 14 项新增测试，测试集达到 **197/197**；`analyze --no-pub` **0 issues**。未改 React，未做实机。
- 未测：Android/Windows 实机系统下的真实文件选择器拾取与写入外部 JSON 文件。
- Pre-existing 未跟踪文档仍在：`docs/STRATEGY_REVIEW_2026-09-08.md`、`docs/UI_INTERACTION_REVIEW_2026-09-08.md`、`docs/AI_UNIT_ECONOMICS_2026-09-08.csv`、`docs/ADR_FLUTTER_PRIMARY_2026-09-09.md`。

## 历史收尾（V0.3-A: WP26-A-N, WP26-B-N-Windows, WP27-A-N）

- Flutter 命令面板、快捷键、桌面托盘与统计进度：
  - `shortcuts.dart`、`widgets/command_palette.dart`（Ctrl+K、Esc、EditableText 输入焦点让位、命令与任务跨板模糊搜索定位、快捷键帮助）。
  - `services/desktop_shell_service.dart`、`screens/settings_screen.dart`、`models.dart`（桌面抽象服务在非桌面安全 no-op、Windows 托盘菜单、`closeToTray` 窗口关闭拦截与退出说明、热键冲突安全处理）。
  - `task_stats.dart`、`widgets/task_stats_bar.dart`、`screens/matrix_screen.dart`、`screens/completed_screen.dart`（`computeTaskStats` 纯计算模型、父子任务计数独立、逾期计算、空列表 0% 兜底、`TaskStatsBar` 响应式流式布局防溢出、范围切换）。
  - 补充中英日三语完整字典词条。
  - 16 项单元与 Widget 回归测试（`test/shortcuts_command_palette_test.dart`、`test/desktop_shell_test.dart`、`test/task_stats_test.dart`）全量通过，总测试集达 182/182，`analyze --no-pub` 0 issues；未改 React，未建 UI 实验分支。
- 未测：Android/Windows 实机系统下的物理 Ctrl+K 按键弹层动画、托盘图标悬停点击与关闭到托盘最小化动画。
- Pre-existing 未跟踪文档仍在：`docs/STRATEGY_REVIEW_2026-09-08.md`、`docs/UI_INTERACTION_REVIEW_2026-09-08.md`、`docs/AI_UNIT_ECONOMICS_2026-09-08.csv`、`docs/ADR_FLUTTER_PRIMARY_2026-09-09.md`。

## 历史收尾（WP24-N）

- Flutter 滑动操作、撤销与轻量反馈：`task_commands.dart`、`storage.dart`、`widgets/task_card.dart`、`l10n.dart`；普通态卡片包裹 `Dismissible`，支持右滑完成/恢复、左滑删除；多选态关闭滑动；5 秒撤销条 SnackBar；`TaskUndoSnapshot` 记录任务、子项深拷贝与原始位置；撤销完成只恢复涉及父子状态，撤销删除回原板原顺序；整板清空、单象限清空、删除看板、覆盖导入使旧撤销立即失效（`_boardEpoch` 代数契约）；无象限说教；右键次级菜单提供对等的操作与撤销；触发轻触觉反馈。测试：`test/task_commands_test.dart`、`test/widget_regression_test.dart` 166/166。

- Flutter 宫格/列表视图切换：`models.dart`（`ViewMode` 枚举与 `AppSettings.viewMode` 序列化）、`storage.dart`（`setViewMode` 与 `toggleViewMode`）、新增 `widgets/task_list_view.dart`（`TaskListView` 纵向四象限分节、颜色指示圆点、维度全名、任务计数、空态提示、复用 `TaskCard`、支持整节 `DragTarget` 跨象限拖动与轻触反馈 SnackBar）、`screens/matrix_screen.dart`（`activeCenter` 依据模式切换、头部一键切换图标按钮、包裹紧凑 `IconButtonTheme` 彻底防范窄屏 320px 溢出）、`l10n.dart`（三语词条）及 5 项单元与 Widget 回归测试已完成；未改 React，未建 UI 实验分支。
- 未测：Android/Windows 实机系统下的长按拖拽流畅度与不同屏幕 DPI 下的列表滚动视觉。
- Pre-existing 未跟踪文档仍在：`docs/STRATEGY_REVIEW_2026-09-08.md`、`docs/UI_INTERACTION_REVIEW_2026-09-08.md`、`docs/AI_UNIT_ECONOMICS_2026-09-08.csv`、`docs/ADR_FLUTTER_PRIMARY_2026-09-09.md`。

## 历史收尾（WP07-N）

- Flutter 已完成任务集中查看：`storage.dart`（`completedTasks`、`completedTaskCount`、`restoreTask`、`restoreTaskById`）、新增 `screens/completed_screen.dart`（`CompletedScreen` 集中列表、范围过滤 Chip、空态图文、删除线标题、看板/象限标签、子项展开、恢复与安全单删）、`screens/matrix_screen.dart`（头部已完成图标按钮）、`l10n.dart`（三语词条）及 5 项单元与 Widget 回归测试已完成；未改 React，未建 UI 实验分支。
- 未测：Android/Windows 实机系统下的进入已完成列表动画与列表滚动触感。
- Pre-existing 未跟踪文档仍在：`docs/STRATEGY_REVIEW_2026-09-08.md`、`docs/UI_INTERACTION_REVIEW_2026-09-08.md`、`docs/AI_UNIT_ECONOMICS_2026-09-08.csv`、`docs/ADR_FLUTTER_PRIMARY_2026-09-09.md`。

## 历史收尾（WP01-N）

- Flutter 服务商预设与动态模型发现：新增 `docs/AI_PROVIDER_PRESETS.md` 官方规范、`ai_presets.dart`（四大预设、元数据与首选算法）、`models.dart`（`AIConfig` 解耦 provider 与 protocol，兼容旧配置迁移）、`ai_service.dart`（`fetchModels` 动态模型发现、缓存与取消、生成时差异化思考参数适配）、`settings_screen.dart`（服务商下拉切换、切换清空 Key 防泄漏、失焦/提交发现、动态下拉/手动模式、高级折叠）、`l10n.dart`（三语词条）及 6 项单元与 Widget 回归测试已完成；未改 React，未建 UI 实验分支。
- 未测：Android/Windows 实机系统下连接真实商业 AI 服务商（DeepSeek、火山引擎、百炼）网络的真实模型加载流程（依赖真实 API Key）。
- Pre-existing 未跟踪文档仍在：`docs/STRATEGY_REVIEW_2026-09-08.md`、`docs/UI_INTERACTION_REVIEW_2026-09-08.md`、`docs/AI_UNIT_ECONOMICS_2026-09-08.csv`、`docs/ADR_FLUTTER_PRIMARY_2026-09-09.md`。

## 历史收尾（WP02-N）

- Flutter 一键清空当前任务板四个象限：`storage.dart`（`clearBoard`、`_boardEpoch`、`boardEpoch`、`boardTaskCount`）、`matrix_screen.dart`（菜单清空入口、确认弹窗与目标 boardId 捕获、清空选中/详情/聚焦、SnackBar）、`input_sheet.dart`（捕获代数并丢弃在途 AI 提交防复活）、`l10n.dart`（三语字典）及 5 项回归测试已完成；未改 React，未建 UI 实验分支。
- 未测：Android/Windows 实机系统下的弹出菜单点击与对话框动画手感。
- Pre-existing 未跟踪文档仍在：`docs/STRATEGY_REVIEW_2026-09-08.md`、`docs/UI_INTERACTION_REVIEW_2026-09-08.md`、`docs/AI_UNIT_ECONOMICS_2026-09-08.csv`、`docs/ADR_FLUTTER_PRIMARY_2026-09-09.md`。

## 历史收尾（WP06-N）

- Flutter 首次启动自动选择设备语言 `models.dart`（`resolveDeviceLanguage` 与 `AppSettings.fromJson` 缺省回退）、`storage.dart`（`Store.init` 首次检测语言与看板国际化命名）、`main.dart`（`MatrixFlowApp` 可注入设备语言）、测试工具与 14 项回归测试已完成；未改 React，未建 UI 实验分支。
- 未测：Android/Windows 实机系统切换不同语言环境下的真机首次冷启动效果。
- Pre-existing 未跟踪文档仍在：`docs/STRATEGY_REVIEW_2026-09-08.md`、`docs/UI_INTERACTION_REVIEW_2026-09-08.md`、`docs/AI_UNIT_ECONOMICS_2026-09-08.csv`、`docs/ADR_FLUTTER_PRIMARY_2026-09-09.md`。

## 历史收尾（WP05-N）

- Flutter 手动换象限置顶与普通拖动 `Store.moveTask`、`Store.updateTask`、`TaskDetailPanel` 克隆解耦、Windows 鼠标右键移动菜单 `TaskCard`、拖拽目标滚动平滑回顶 `QuadrantPane`、轻触觉反馈与 SnackBar 提示、三语文案及 4 项回归测试已完成；未改 React，未建 UI 实验分支。
- 未测：Android/Windows 实机上的长按拖拽微颤与触摸平滑度、物理鼠标右键菜单弹出。
- Pre-existing 未跟踪文档仍在：`docs/STRATEGY_REVIEW_2026-09-08.md`、`docs/UI_INTERACTION_REVIEW_2026-09-08.md`、`docs/AI_UNIT_ECONOMICS_2026-09-08.csv`、`docs/ADR_FLUTTER_PRIMARY_2026-09-09.md`。

## 历史收尾（WP22-B-N）

- Flutter 子任务截止日期与独立编辑表单 `TaskDetailPanel`、快捷日期与自定义日历选择器、清除日期、父子日期独立性与超期非阻塞提醒、矩阵卡片子项日期徽章、草稿脏检测防丢、三语文案及 3 项回归测试已完成；未改 React，未建 UI 实验分支。
- 未测：Android/Windows 实机上的子任务日期弹窗与点击手感。
- Pre-existing 未跟踪文档仍在：`docs/STRATEGY_REVIEW_2026-09-08.md`、`docs/UI_INTERACTION_REVIEW_2026-09-08.md`、`docs/AI_UNIT_ECONOMICS_2026-09-08.csv`、`docs/ADR_FLUTTER_PRIMARY_2026-09-09.md`。

## 历史收尾（WP22-A-N）

- Flutter 新建任务截止日期入口 `InputSheet`、快捷日期与自定义日历选择器、快照隔离、公共日期范围说明与子任务不继承、草稿保留、三语文案及 3 项回归测试已完成；未改 React，未建 UI 实验分支。
- 未测：Android/Windows 实机上的日期选择对话框弹出与键盘选择流畅度。
- Pre-existing 未跟踪文档仍在：`docs/STRATEGY_REVIEW_2026-09-08.md`、`docs/UI_INTERACTION_REVIEW_2026-09-08.md`、`docs/AI_UNIT_ECONOMICS_2026-09-08.csv`、`docs/ADR_FLUTTER_PRIMARY_2026-09-09.md`。

## 历史收尾（WP23-N）

- Flutter 单象限聚焦与下方收起卡片 `QuadrantFocusView`、AppBar 返回按钮、PopScope 返回拦截、下方三象限卡片排序与切换、拖拽移动象限、看板切换退出聚焦及对应 4 项回归测试已完成；未改 React，未建 UI 实验分支。
- 未测：Android/Windows 实机上的手势与拖放体验、物理键盘 Escape 返回。
- Pre-existing 未跟踪文档仍在：`docs/STRATEGY_REVIEW_2026-09-08.md`、`docs/UI_INTERACTION_REVIEW_2026-09-08.md`、`docs/AI_UNIT_ECONOMICS_2026-09-08.csv`、`docs/ADR_FLUTTER_PRIMARY_2026-09-09.md`。

## 历史收尾（WP04-N）

- Flutter 集中详情面板 `TaskDetailPanel`、宽屏侧边栏与窄屏抽屉、多行输入、快捷键保存、草稿保护与确认、子任务 CRUD 与联动、删除任务确认及对应 6 项回归测试已完成；未改 React，未建 UI 实验分支。
- 未测：Android/Windows 实机上的虚拟键盘弹起交互、桌面物理键盘快捷键以及窗口动态拖拽缩放。
- Pre-existing 未跟踪文档仍在：`docs/STRATEGY_REVIEW_2026-09-08.md`、`docs/UI_INTERACTION_REVIEW_2026-09-08.md`、`docs/AI_UNIT_ECONOMICS_2026-09-08.csv`、`docs/ADR_FLUTTER_PRIMARY_2026-09-09.md`。

## 历史收尾（WP03-N）

- Flutter 十字无框矩阵、紧凑任务行、首行复选框对齐、外部底部安全区按钮/工具栏、单选编辑入口及对应测试已完成；未改 React，未建 UI 实验分支。
- 未测：Android/Windows 实机上的触摸手势、滚动感受与键盘焦点。
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
