# OS23 实施记录：动效时长统一与减少动画运行时即时终态

> main 集成补记（2026-09-25）：运行中切换减少动画时，只对正在自动回顶的列表执行 `jumpTo(0)`，手动滚动位置保持；引导页目标会保持到 `animateToPage` 完成，滑动过半时打开减少动画也能立即跳到目标。两条集成回归已加入 `os23_motion_policy_test.dart`；象限标题的临时 `TextPainter` 已释放。本文件下文是独立分支的原始记录，提到 `onPageChanged` 清目标及任意列表回顶的描述以本补记为准。

日期：2026-09-25。包号：**OS23**（对应审查报告 F20）。状态：**已实施**；双端真机的动效手感人工验收**未做**。

## 1. 接手与边界

- 基线：`main / 0f5e4f62b4d4fc6a7dcb2440dd12e540dcd4196d`（接手时主工作区干净，HEAD 即基线）。独立 worktree `D:\Dev_project\martix-wt-os23`，分支 `codex/os23`（worktree 已由集成分支预建在同一基线）。
- 固定 SDK `D:\Dev_SDKs\Flutter_3.32.8`（Flutter 3.32.8 / Dart 3.8.1）。未新增依赖，未改打包配置。新 worktree 首次跑了一次 `flutter pub get`，使 `matrixflow-native/windows/flutter/generated_plugin_registrant.{cc,h}` 与 `generated_plugins.cmake` 只出现行尾差异（`git diff` 无内容变化），已 `git checkout` 还原，**不纳入提交**。
- 只动本包清单：`lib/ui/motion_policy.dart`、`lib/widgets/anim.dart`、`task_exit.dart`、`quadrant_transition_layout.dart`、`quadrant_pane.dart`、`task_list_view.dart`、`task_card.dart`、`lib/screens/onboarding_screen.dart`，加专项测试与本记录。
- **未改**（按指令）：`settings_screen.dart`（主题色动效归 OS18）、`animated_task_title.dart`、`storage.dart`、`matrix_screen.dart`。公共 `AGENTS.md`/`HANDOFF.md`/`ARCHITECTURE.md`/`CHANGELOG.md`/开源准备计划一律不动，只写本文件。React/Tauri/Capacitor 保持冻结，未碰 WP10/WP29/UI 实验。

## 2. 修前盘点：五类动效的时长来源与减少动画路径

按 F20 要求逐处读源码，不看常量名猜。

| 类别 | 位置 | 修前时长来源 | 修前减少动画行为 |
| --- | --- | --- | --- |
| 入场（行淡入+上滑） | `anim.dart` `StaggerIn` | controller 写死 **260ms**；行间延迟已用 `MotionPolicy.entranceStep`(45ms) | 首帧 `didChangeDependencies` 检测后直落 value=1；但**运行中开关**只在下次新元素才生效，进行中的淡入不中断 |
| 引导（onboarding 翻页） | `onboarding_screen.dart` `_nextPage/_prevPage` | `nextPage/previousPage` 写死 **300ms** easeInOut | **完全不看 reduceMotion**，开了减少动画仍整段滑动 300ms |
| scrollToTop | `quadrant_pane.dart` `_scrollToTopIfNeeded` | `animateTo` 写死 **250ms** easeOut | **完全不看 reduceMotion**，拖放落位后仍滚动 250ms |
| 布局 fallback（几何连续过渡） | `quadrant_transition_layout.dart` | `enterDuration`/`switchDuration`/`exitDuration`/`listFadeDuration` 四个 static const（320/300/280/220）挂在 widget 上 | 几何 `_geometry` 已在 build 里 watch reduceMotion 并 snap 到 1；但**列表模式遮罩 `_listFade` 运行中开关不 snap**，会再淡 220ms |
| 退出（完成/隐藏后行折叠） | `task_exit.dart` `ExitRetention`/`ExitingRow` | 已统一读 `MotionPolicy.exitHold`(220)+`exitCollapse`(120) | 已正确：reduceMotion 下 `sync` 直接 `clear()`，退出行不驻留；运行中开关时 pane 重建调用 `sync(reduceMotion:true)` 把在途退出行整棵移除 |
| 完成反馈（删除线） | `animated_task_title.dart`（不属本包） | 已用 `MotionPolicy.strikethrough`(220) | reduceMotion 下零时长（既有行为，未改） |
| 滑动 dismiss | `task_card.dart` Dismissible | 写死 **200ms**，但已 `reduceMotion ? zero : 200` | 已正确，仅缺统一命名 |
| 拖拽 hover 高亮 | `quadrant_pane.dart`/`task_list_view.dart` AnimatedContainer | 写死 **180ms** | 未接 reduceMotion（见 §4 延期） |

SnackBar 的 1400/1800/5000ms 是**展示时长**（用户可撤销窗口），不是动画，全部保留原值。

## 3. 实现方式

### 3.1 时长统一收口到 `MotionPolicy`

`lib/ui/motion_policy.dart` 在既有 `strikethrough/exitHold/exitCollapse/entranceStep` 之后新增具名常量，**数值与修前逐字一致**（不改手感）：

- `entranceFade`=260（StaggerIn controller，原写死）
- `geometryEnter`=320 / `geometrySwitch`=300 / `geometryExit`=280 / `listFade`=220（原 `QuadrantTransitionLayout` 的四个 static const，已删除并改读 MotionPolicy）
- `scrollToTop`=250、`pageTurn`=300、`dismissible`=200、`hoverHighlight`=180

`quadrant_transition_layout.dart` 删除了四个 static const；`_durationFor` 与 `_listFade` 初始化改读 MotionPolicy。`task_card.dart` Dismissible、两处 hover `AnimatedContainer` 同步引用。这不是机械替换：每个常量都带注释说明用途与为何保留动画。

### 3.2 运行中开启减少动画 → 立即到可交互终态

- **入场 `StaggerIn`**：build 里 `MotionPolicy.reduceMotionOf(context)`（watch）一旦为真且 controller 未完成，直接 `_controller.value = 1`。这样减少动画在淡入/交错延迟中途被打开时，行立即完全可见、可点击；已完成的行不受影响，"每元素只播一次"语义不变（不会重播）。
- **引导翻页**：抽 `_goToPage(target)`。reduceMotion 时 `setState(_currentPage=target)` + `jumpToPage(target)`（同步翻页，不再滑动）；否则 `animateToPage(target, duration: pageTurn)`。Next 按钮与左/右箭头快捷键同走此路。**运行中切换**：新增字段 `_turnTarget` 记录在途翻页目标，`didChangeDependencies` 监听 reduceMotion，开关在滑动中途打开时，下一帧 `jumpToPage(_turnTarget)`，不等 300ms 滑完；`onPageChanged` 与跳转后都会清掉目标，避免陈旧值。
- **scrollToTop**：在落位（DragTarget accept）那一刻读 `reduceMotionNow`，为真则 `jumpTo(0)`，否则 `animateTo(0, scrollToTop)`。**运行中切换**：pane 的 `didChangeDependencies` 监听 reduceMotion，开关在 250ms 回滚动画中途打开时，下一帧 `jumpTo(0)` 立即到顶。
- **布局遮罩 `_listFade`**：build 的 reduceMotion 分支在原有 `_geometry` snap 之外，把列表模式遮罩也归位终态——`fadeOutOnly` 时 snap 到 0 并 `_scheduleFadeOutDone()`（与 `didChangeDependencies` 既有写法一致，有 generation 防重），否则 snap 到 1。补齐了原"几何 snap 但列表遮罩还在淡"的缺口。
- **退出**：`task_exit.dart` 经盘点**无需改动**。reduceMotion 运行中打开时，pane 的 build 调 `_exitRetention.sync(reduceMotion:true)` → `clear()`，在途退出行（含仍在 exitHold 等待折叠的）整棵从列表移除，立即终态。

### 3.3 刻意保持不变

- UX07 连续几何的曲线、`FrozenPane` 冻结合成、blend、panes 交叉淡化逻辑一行未动；只把时长常量搬了家、把 reduce snap 补全到 `_listFade`。
- 完成反馈（删除线、Dismissible 完成/撤销、5s undo）路径未改。
- StaggerIn 的 14dp 上滑幅度是几何量不是时长，保留原值；hover 高亮的 e curve 保留。

## 4. 证据表明无需修改 / 延期项

- **拖拽 hover 高亮 180ms（两处 AnimatedContainer）**：已收口为 `MotionPolicy.hoverHighlight`，但**不接 reduceMotion→zero**。测量：它只是 pointer 悬停/拖入时的底色与描边淡入，从不遮挡命中、不挡焦点、不构成"中间不可交互状态"；F20 点名的五类（入场/引导/scrollToTop/布局 fallback/退出）均不含它。按"不机械替换常量、不破坏既有手感"保留动画，并在常量注释里写明理由。若后续要做全局减少动画审计，可再收口。
- **`anim.dart` 里的静态 `StrikeThrough`（非 AnimatedStrikeThroughText）**：它本来就是立即切换 `TextDecoration`、无动画，`completed_screen.dart` 在用，无需处理。
- **退出折叠时序**：修前已正确，仅确认记录，未改 `task_exit.dart`。
- **SnackBar 展示时长**：不是动效，保留。
- **Dismissible 在途滑动/折叠（≤200ms）**：`task_card.dart` 的 Dismissible 在新动作发起时已按 reduceMotion 给 `Duration.zero`，但 Flutter SDK 的 `Dismissible` 不重写 `didUpdateWidget`，move/resize 控制器的时长只在创建时写入（SDK `dismissible.dart` 中控制器构造处），运行中翻转开关不会加速已经在途的回弹/折叠。不能用改 key 重建 Dismissible 来修：删除路径的 resize 一旦被重建打断，`onDismissed` 不再触发，**删除会丢失**。该在途窗口最长 200ms，且完成/删除的功能状态在手势确认时就已提交（删除线本身也会在 reduce 下立即到终态），不构成"不可交互"状态，故保留并记录，等未来替换/封装 Dismissible 时再处理。

## 5. 验证

- 专项 `test/os23_motion_policy_test.dart`：**6/6**。
  - 常量单测锁死 13 个时长的单一来源与数值。
  - reduceMotion=真时点 Next，**一帧内** Previous 按钮与第二页标题即出现（证明走 `jumpToPage`，而非旧 300ms 滑动）。
  - 对照：reduceMotion=假时点 Next 后 50ms 仍在第 1 页（证明动画路径未被误改成瞬时），`pumpAndSettle` 后正常到第 2 页。
  - **翻页中途打开 reduceMotion**：300ms 滑动到 120ms 时翻转开关，下一帧跳到目标 slide（运行中切换）。
  - **reduceMotion=真时拖放**：目标 pane 已滚动（offset>100），落位后两帧内 `jumpTo(0)`，无 250ms 滚动。
  - **滚动中途打开 reduceMotion**：250ms 回滚动画到 100ms 时翻转开关，下一帧 `jumpTo(0)` 立即到顶（运行中切换）。
- 默认全量 `flutter test --no-pub`：**520/520**（基线同命令 514/514，差值为本包新增 6 项；未删改既有用例）。`flutter analyze --no-pub`：**No issues found**。
- 复跑既有用例 `ux06_regression`（含 reduceMotion 直达终态）、`ux07`、`ux_state`、`onboarding_test`、`widget_regression` 随全量绿。
- **未做（widget/mock 无法代替，按双端人工验收挂起）**：
  - Android 触摸：拖放落位后减少动画下是否立即到顶、无滚动残影；onboarding 手指滑动与按钮翻页手感；四象限聚焦/退出几何在减少动画下是否瞬切且无残影。
  - Windows：鼠标/键盘聚焦象限、运行中在设置里翻转"减少动画"开关的瞬间，列表遮罩 `_listFade` 是否立即归位、几何是否瞬切、无残留 220ms 淡入；窗口缩放不变。
  - 真机上重复快速聚焦/切象限/完成任务是否出现中间不可交互帧（widget 测试用合成视口，复现不了手势连打时序）。
- 测试全部使用合成任务与无密钥数据。

## 6. 残余限制

- StaggerIn 的 build-side snap 遵循本仓库既有"build 里 `_controller.value=`"写法（与 `quadrant_transition_layout` 一致），只在 reduceMotion 由假变真那一帧触发；真机观感以人工验收为准。
- onboarding 在 reduceMotion 下 `jumpToPage` 后显式 `setState(_currentPage)`，双保险驱动指示点；`onPageChanged` 是否再回调不影响结果。
- 未触碰 `settings_screen.dart` 的主题色动效（OS18 范围），本包不判断它的减少动画路径。

## 7. 改动文件

- 产品代码：`lib/ui/motion_policy.dart`、`lib/widgets/anim.dart`、`lib/widgets/quadrant_transition_layout.dart`、`lib/widgets/quadrant_pane.dart`、`lib/widgets/task_list_view.dart`、`lib/widgets/task_card.dart`、`lib/screens/onboarding_screen.dart`。
- `lib/widgets/task_exit.dart`：**仅盘点确认，未改动**。
- 测试：新增 `matrixflow-native/test/os23_motion_policy_test.dart`。
- 文档：仅本文件 `docs/OS23_NOTES.md`。

## 8. 下一位接手者 / 集成人需要知道

- 落到公共文档的内容：开源准备计划第 3 节 OS23 状态改已实施；可在 `ARCHITECTURE.md` 记一句"动效时长统一在 `lib/ui/motion_policy.dart`，入场/引导/scrollToTop/几何/退出均读它，reduceMotion 运行中切换 snap 到终态"。
- **跨界最小接口**（本包未实现，交给对应包）：
  - OS18 在 `settings_screen.dart` 翻转减少动画时，`motion_policy` 的 watch 端（pane/layout/onboarding/StaggerIn）已能自动重建并 snap，OS18 无需为本包补接口；但若 OS18 给主题色/字体预览加动画，应同样读 `MotionPolicy` 而非新写 `Duration(milliseconds:…)`。
  - hover 高亮（`hoverHighlight`）目前故意保持动画；若后续要求全局 reduceMotion 一刀切，只需在两处 `AnimatedContainer` 的 `duration` 旁加 `reduceMotion ? Duration.zero : MotionPolicy.hoverHighlight`，本包已把值收口，改动点明确。
- 未 amend、未推送；提交仅含本包文件（见 §7）。generated Windows 文件已还原，不在提交内。
