# OS22 实施记录：列表性能测量与惰性构建

> main 集成补记（2026-09-25）：列表路由现直接导入 `task_detail_panel.dart` 与 `batch_decompose_sheet.dart`，不再经 `input_sheet.dart` 再导出；惰性构建与测量数据保持本文件所述。双端合并态测试见 HANDOFF。

日期：2026-09-25。包号：**OS22**（对应审查报告 F19）。状态：**已实施列表惰性构建**。Android 未测。Windows profile 有同条件前后数据，Windows release 测了修复后的同一套合成场景。

## 1. 接手与边界

- 基线：`main / 77d81f13f6972fe0b9237e09f03a846e05712b09`。独立 worktree `D:\Dev_project\martix-wt-os22`，分支 `codex/os22`。主工作区保持在该基线，本包不在主工作区改文件。
- 固定 SDK `D:\Dev_SDKs\Flutter_3.32.8`（Flutter 3.32.8 / Dart 3.8.1，framework `edada7c56edf4a183c1735310e123c7f923584f1`）。未改依赖，也未改 `pubspec.lock`。
- 本包改了 `task_list_view.dart`、合成性能工具和列表回归。`storage.dart`、`task_query.dart`、`quadrant_pane.dart` 测完后保持原样。
- 未改 `settings_screen.dart`、`input_sheet.dart`、`task_detail_panel.dart`、搜索/完成页、`matrix_screen.dart`、共享日期 UI、三语文案、引导页。
- 未改 `AGENTS.md`、`HANDOFF.md`、`ARCHITECTURE.md`、`CHANGELOG.md` 和开源准备计划。冻结 React/Tauri/Capacitor。暂停 WP10/WP29/UI 实验。
- 只用合成任务。内存替换 SharedPreferences，凭据和提醒都是内存假实现。用户文件 `%APPDATA%\com.matrixflow\MatrixFlow AI\shared_preferences.json` 在 profile 与 release 两次运行前后的 SHA256 都是 `31CDA939E8C0EFFCDCE5C7B8B51A206B3B5AF69F5071306F09090875C63B10C8`，mtime 仍为 2026-09-19 23:02:43。

## 2. 设备与测量方法

| 项 | 值 |
|---|---|
| 机器 | Windows 11 企业版 10.0 Build 26200；AMD Ryzen 7 8845H（8 核 / 16 线程，最高 3801 MHz）；内存 27.81 GB；AMD Radeon 780M |
| 窗口 | 默认 runner 客户区逻辑尺寸 1267×684.5，devicePixelRatio 2.0，物理像素 2534×1369 |
| 刷新率 | Flutter 视图报告 143.99 Hz。该刷新率与当时的 OrayIddDriver 虚拟显示器 144 Hz 一致。同机 AMD 面板报告为 120 Hz。帧预算按视图的 6945 µs 计算 |
| Android | `adb devices` 无连接设备。Android 未测，不用 widget 测试冒充 |
| 模式 | 修复前、修复后各一次 Windows **profile**（`kProfileMode=true`，`kDebugMode=false`）。修复后再跑同一工具的 Windows **release**（`kReleaseMode=true`）。debug 单测耗时不作为帧数据 |

工具：`matrixflow-native/tool/os22_perf_bench.dart`。

```text
flutter run -d windows --profile -t tool/os22_perf_bench.dart --no-pub
flutter run -d windows --release -t tool/os22_perf_bench.dart --no-pub
```

环境变量 `MATRIXFLOW_OS22_PERF_RESULT` 或 `--dart-define=OS22_OUT=` 指定 JSON。

测量的是生产 `QuadrantTransitionLayout`（宫格）和 `TaskListView`（列表），不是完整 `MatrixScreen` 顶栏。任务均匀分到四个象限，只有标题，没有备注、截止日期、提醒和子任务。64 条宫格和 200 条列表先做预热，预热不进入下表。滚动样本是先回到偏移 0，再以线性 1200 ms 滚动 2400 逻辑像素（内容更短时滚到末尾）。挂载数量是当时树上的 `TaskCard` 与元素个数。原始 JSON：

- 修复前 profile：`matrixflow-native/tool/os22_perf_before.json`
- 修复后 profile：`matrixflow-native/tool/os22_perf_after.json`
- 修复后 release：`matrixflow-native/tool/os22_perf_release.json`

列表的 `PageStorageKey` 在场景之间会恢复上一次滚动偏移，所以挂载阶段可能不是从 0 开始。滚动帧是 `jumpTo(0)` 之后重新采样的。

## 3. 修复前 profile

查询耗时是 Dart CPU，不是帧。1 万条时四次 `tasksIn` 平均 4.3 ms，`visibleTasks` 0.9 ms，一次未命中 `queryTasks` 1.7 ms。滚动期间构建 p50 在 1 ms 以内，查询不在滚动热路径上。

| 场景 | 挂起卡片 | 挂载首帧 / 分布 | 一次 `notifyListeners` | 滚动 total（144 Hz 预算 6.9 ms） | 工作集 |
|---|---|---|---|---|---|
| 宫格 1k | 45 | 首帧 total 6.5 ms；p90 4.0 ms；1/118 超预算 | 构建 8.6 ms | p90 3.6 ms；0/294 | 约 163 MB 附近 |
| 列表 1k | 250 | 构建最大 154 ms；total p90 11.3 ms；18/80 超预算 | 构建 64.5 ms / total 68.4 ms | p90 3.4 ms；0/173 | 158 MB → 190 MB |
| 宫格 10k | 45 | 首帧 total 11.6 ms；p90 4.2 ms；2/116 超预算 | 构建 13.1 ms / total 15.2 ms | p90 3.3 ms；1/299，最大 15.5 ms | 约 155–166 MB |
| 列表 10k | 2500 / 元素 282609 | 构建最大 **1594 ms**，total 最大 **1597 ms** | 构建最大 **711 ms**；**11/11** 超预算 | p50 9.4 ms，p90 11.6 ms，最大 29.1 ms；**66/67** 超预算，1.2 s 内只有 67 帧 | 180 MB → **718 MB**，峰值 864 MB |

列表 1 万条时，外层视口大约 685 逻辑像素，内层 `shrinkWrap` 列表的视口高度是 150000。首个象限的 2500 行被一次性建出，后面的象限还没进入缓存。宫格 1 万条仍只挂 45 张卡片，滚动留在预算内。

## 4. 修改

只改列表。四个 `shrinkWrap: true` 且 `NeverScrollableScrollPhysics` 的内层 `ListView` 换成一个 `CustomScrollView`：每个象限是标题 `SliverToBoxAdapter` 加 `SliverList.builder`。`PageStorageKey('${activeBoardId}-task-list-view')`、`ExitingRow`、退场保留和卡片 key 仍在。

拖放从“整段一个 DragTarget”改成标题和每一可见行各一个。`DragTarget` 先离开再进入下一块，悬停清除延后一帧，避免指针跨行时高亮闪烁。标题在悬停时保留原来的描边和底色；可见行只有同样的底色，不再各自描边。空象限的标题和空文案仍在同一个投放目标里。

`quadrant_pane.dart` 已经是惰性 `ListView.builder`，宫格滚动没有超预算的持续掉帧，所以没有改。四次 `tasksIn` 的 4 ms 不在滚动路径上，没有加查询索引，也没有改 `storage.dart`。

## 5. 修复后 profile（同一台机器、同一工具、同一 profile）

| 场景 | 挂起卡片 | 挂载 | 一次 `notifyListeners` | 滚动 total | 工作集 |
|---|---|---|---|---|---|
| 宫格 1k | 45 | 首帧 total 4.6 ms；p90 5.1 ms；1/114 | 构建 9.6 ms / total 12.9 ms | p90 4.2 ms；0/293 | 约 146–150 MB |
| 列表 1k | 24 / 元素 3104 | 首帧 total 4.1 ms；p90 3.8 ms；1/81 | 构建 6.4 ms / total 8.8 ms | p90 3.1 ms；1/307，最大 15.9 ms | 157 MB → 146 MB |
| 宫格 10k | 45 | 首帧 total 2.9 ms；p90 4.4 ms；1/113 | 构建 15.2 ms / total 17.6 ms | p90 3.6 ms；1/291，最大 15.1 ms | 166 MB → 162 MB |
| 列表 10k | **24** / 元素 **3104** | 首帧 total **4.9 ms**；p90 3.6 ms；最大 43.0 ms；1/81 | 构建 **9.9 ms** / total **11.4 ms**（1 帧，低于 16.7 ms） | p50 **2.0 ms**，p90 **3.1 ms**，p99 3.7 ms；**1/306**，最大 13.5 ms，306 帧 | 166 MB → **156 MB**，峰值 193 MB |

列表 1 万条相对修复前：挂起卡片 2500 → 24，首帧构建从 1.6 s 降到约 5 ms，滚动从 66/67 超预算降到 1/306，工作集不再增加约 540 MB。宫格前后仍是约 45 张卡片，滚动 p90 仍在 4 ms 左右。

## 6. 修复后 release

同一工具、同一窗口、`kReleaseMode=true`。这是修复后的额外样本，没有修复前的 release 对照。

| 场景 | 挂起卡片 | 挂载 total | 滚动 total |
|---|---|---|---|
| 宫格 1k | 45 | 首帧 5.1 ms；p90 6.9 ms；12/120 超预算 | p90 5.5 ms；2/133 |
| 列表 1k | 24 | 首帧 6.6 ms；p90 5.7 ms；3/107 | p90 3.7 ms；2/143，最大 19.9 ms |
| 宫格 10k | 45 | 首帧 2.0 ms；p90 3.6 ms；**0/65** | p90 5.0 ms；1/143，最大 23.4 ms |
| 列表 10k | 24 | 首帧 **3.8 ms**；p90 **4.8 ms**；最大 5.5 ms；**0/48** | p50 2.6 ms，p90 **3.7 ms**；2/141，最大 19.8 ms |

Release 的“一次 notify”阶段收到了几十到上百帧，和 profile 里孤立的 1 帧不是同一种样本，所以不用它比较重建。列表 1 万条的挂载和滚动在 release 里仍然只建约 24 张卡片，滚动 p90 3.7 ms。

## 7. 正确性回归

`test/os22_list_regression_test.dart` **4/4**：

- 80 条同一象限时，挂起的 `TaskCard` 多于 3 且少于 30。这是结构守卫，不是帧时间。
- 滚到 480 后拆掉并重建 `TaskListView`，`PageStorageKey` 把偏移恢复到约 480。
- `hideCompleted` 下完成一条可见任务，`ExitingRow.exiting` 为真，经过 `exitHold + exitCollapse` 后该行消失。
- 展开父任务后滚出再滚回，子任务标题仍在。

`test/ux07_regression_test.dart` 的列表聚焦来回仍断言滚动偏移。懒列表在恢复偏移时会新建行，`StaggerIn` 的 540 ms `Future.delayed` 不会随元素销毁取消，测试结束前多 `pump` 了 600 ms，避免绑定把未触发的定时器当成失败。

默认 `flutter test --no-pub` **548/548**。`flutter analyze --no-pub` **0 issues**。

## 8. 留给集成人

- `lib/widgets/anim.dart` 的 `StaggerIn` 用 `Future.delayed` 排队入场，`dispose` 不取消。宫格原本就会这样；列表改成惰性之后，滚进新行再马上离开会留下最多约 540 ms 的一次性定时器，回调里会检查 `mounted`。若要消掉这个定时器，改 `anim.dart`，本包没有动它。
- 宫格 1 万条的单次 `notifyListeners` 在 profile 里约 15–18 ms，其中四次 `tasksIn` 约 4 ms。滚动不付这笔成本。若以后要做象限索引，从 `task_query.dart` / `storage.dart` 的只读查询入手，不要为这一笔单独引入数据库。
- Android 触摸和真机帧仍未测。本包的帧数据只覆盖上述 Windows 窗口。
- 公共 AGENTS、HANDOFF、ARCHITECTURE、CHANGELOG、实施计划留给集成人。OS27 仍等 OS21 与本包一起收口。
