# OS19 实施记录：小控件热区、读屏语义与键盘可达性

日期：2026-09-25。包号：**OS19**（对应审查报告 F16）。状态：**已实施**；Android 触摸与 Windows 真窗口的键盘操作**均未实测**。

## 1. 接手与边界

- 基线：`main / 0aec23f176a15eae398dbf292086e6827cea74da`，接手时主工作区干净。独立 worktree `D:\Dev_project\martix-wt-os19`，分支 `os19-accessibility`。
- 与 OS17 一样，`flutter pub get` 使 `matrixflow-native/windows/flutter/generated_plugin_registrant.{cc,h}` 与 `generated_plugins.cmake` 只出现行尾差异（`git diff --stat` 不含内容变化），**未纳入提交、未清理**。
- 固定 SDK `D:\Dev_SDKs\Flutter_3.32.8`（Flutter 3.32.8 / Dart 3.8.1）。未新增依赖，未改打包配置。
- 只改本包范围：任务交互 widget（`task_card.dart`、`task_hierarchy_checkbox.dart`、`task_detail_panel.dart`）、设置页颜色控件、搜索页与已完成页的同类控件、`l10n.dart`，以及测试与本记录。新增 `lib/widgets/accessible_tap_target.dart`。未修改 `storage.dart`、Windows runner/桌面 host、发行 workflow。公共 `AGENTS.md`、`HANDOFF.md`、`ARCHITECTURE.md`、`CHANGELOG.md` 与开源准备计划留给集成人。**未开始 OS18**。

## 2. 修前实测：四个反例都成立（OS-R08）

按 F16 要求用实际 hit test / semantics / focus 检查，不看外框常量。探针在 `test/review/os19_review_probe.dart`，在未改动的基线 worktree 上运行，四条全部失败：

| 探针 | 基线实测 | 结论 |
| --- | --- | --- |
| OS-R08a 展开控件热区与状态 | 命中框高度 **24.0dp**；语义节点无 `hasExpandedState` | 展开/收起只有一行小图标加少量 padding，且读屏听不出“可展开” |
| OS-R08b 父子标签 | 父框与两个子框都读作 **`Mark task complete`** | 同卡片三个控件无法区分，也没有任务名 |
| OS-R08c 键盘操作复选框 | Tab 六步内按 Space **从未完成过任务** | 见下条：真正的原因是一个幻影焦点停靠点 |
| OS-R08d 颜色选择 | 圆心上方 20dp 处的点击**不改变主题色**（绘制与命中都是 28dp）；键盘根本停不到颜色 | 颜色选择只能靠鼠标 |

**新发现的缺陷（F16 未点名，但同源）**：基线的复选框是 `SizedBox(48) > GestureDetector > ... > IgnorePointer(Checkbox)`。`IgnorePointer` 只屏蔽指针，**不屏蔽焦点**，所以里面那个只用于绘制的 Material `Checkbox` 自带一个可聚焦节点。结果是每张卡片的复选框有**两个 Tab 停靠点**：第一个属于外层装饰容器（无键盘动作），第二个属于内部 `Checkbox`，而它的 `onChanged` 是空函数 —— 按 Space 只会切换它自己的内部状态，永远不会调用 `setParentCompleted`。这正是 OS-R08c 失败的原因。已用 `ExcludeFocus` 把绘制用的 `Checkbox` 移出焦点遍历，一张卡片只留一个停靠点。

另外发现同一控件在不同页面有三种不同 label（矩阵卡 `markTaskComplete`、已完成页 `restoreTask`、搜索页 `toggleComplete`/`completed`），一并统一。

## 3. 实现方式

### 热区与绘制尺寸分开

新增 `AccessibleTapTarget`：`SizedBox.square(minSide: 48)` + `Center` 包住原样绘制的子控件，外层 `GestureDetector(behavior: opaque)` 承担命中。复选框（4 处调用共用）和设置页颜色点走这一层，因此 **22/18dp 的复选框与 28/34dp 的颜色点像素尺寸完全不变**。48 这个数继续只有 `PlatformUiPolicy.minActionSize` 一个来源（`TaskHierarchyStyle.hitTargetSize` 改为引用它）。

两个子任务展开行保留原有 `InkWell`（涟漪、hover、Material 自带焦点高亮都不变），只在外面加 `ConstrainedBox(minHeight: 48)` 与语义节点，不改成自绘控件。

### 语义：状态用 trait，标签只说“是什么”

- 复选框：`checked` + 带角色和任务名的标签，例如 `Mark parent task "Ship release notes" complete` / `Mark subtask "Draft changelog" incomplete`。已完成页的“恢复”不再另起一个词，而由 `value == true` 自然得到 `... incomplete`，三页统一。
- 展开行：`expanded` trait 表达展开状态，标签**保持稳定**（`Subtasks of "…", 0 of 2 done`）。若仍用 `expandSubtasks`/`collapseSubtasks` 作标签，就和 trait 重复表达同一件事 —— 正是计划禁止的“无意义重复 semantics”。这两个键与 `markTaskComplete` 已随之删除。
- 颜色点：`selected` + `inMutuallyExclusiveGroup`，标签 `Theme color: Blue` 不随选择变化；`Tooltip` 的文本节点被 `excludeSemantics` 排除，避免同一句念两遍。
- 三个控件的外层节点都设 `excludeSemantics: true` 并显式给出 `onTap`，保证一个控件一个节点，同时保留读屏的“双击激活”动作。

### 键盘

`AccessibleTapTarget` 用 `FocusableActionDetector` 注册 `ActivateIntent` / `ButtonActivateIntent`（`WidgetsApp` 已把 Enter、小键盘 Enter、Space 映射到 `ActivateIntent`），并跟踪焦点状态：绘制焦点环（`CustomPaint` 前景画笔，仅在 traditional 高亮模式下出现，不占布局）同时把 `focusable` / `focused` trait 报给读屏。展开行走 `InkWell` 自带的同一套 intent 机制，实测 Enter/Space 均能触发。

## 4. 布局影响与一处刻意保持的不变量

- 矩阵卡的展开行：**24dp → 48dp**，即可展开卡片每张高约 24dp。卡片在该处只有 `top:4, bottom:2` 共 6dp 可回收，不足以吸收 24dp，这是本包唯一可测量的布局增高；绘制的图标与文字尺寸未变。
- 设置页主题色一节：原本 `12 + 34 + 20 = 66`，改为 `8 + 48 + 10 = 66`，**总高度与改前完全一致**。这不是审美调整：48dp 目标会让该节自然多出 14dp，而 `test/os14_desktop_shell_test.dart` 用 `dragUntilVisible` 后立刻 `tap()` 全局快捷键按钮，多出的 14dp 会把该按钮中心推到 800×600 测试视口之外，导致“编辑快捷键”用例点空。**通过还原本节高度避免去改 OS14 的测试文件**（那不是本包拥有的文件），修好后该文件 8/8 原样通过。
- 未做全局重画，未改象限布局、父子缩进与 `hierarchicalIndent`。

## 5. 验证

- 专项 `test/os19_affordance_test.dart`：**8/8**。覆盖：复选框四角与中心 1/46/24 等坐标的真实边缘点击、父子框各自独立生效且不误触发父任务、绘制边界仍为 22/18dp；Tab 落到复选框、焦点环出现、`isFocused` trait、Space 与 Enter 各切换一次、Shift+Tab 后环消失；父/子/兄弟三个标签互不相同且含任务名、`checked` 随状态翻转、标签不与其他文本合并；展开行高度 ≥48 而图标仍为 18dp、`expanded` 随状态变化且标签不变、上边缘 1dp 内点击生效；Tab 顺序精确为 复选框 → 标题 → 展开行且 Enter 能展开；颜色点 48dp 命中框而绘制仍 28/34、`selected` 与互斥组 trait、纯 Tab 走到绿点并按 Space/Enter 改主题色、边缘点击也能选中；已完成页恢复框标签与 `checked`、展开行状态、边缘点击、恢复生效；三语 × 200% 文本下三个热区仍 ≥48、父子标签仍互不混淆、无渲染异常。
- OS-R08 探针：**修前 0/4，修后 4/4**（同一文件在基线 worktree 与本分支分别运行）。
- 默认全量 `flutter test --no-pub`：**503/503**（接手基线同一命令为 495/495，差值正好是本包新增 8 项；未删改任何既有用例）。`flutter analyze --no-pub`：**0 issues**。
- 定向复跑：`os02_hierarchy`、`os13_focus`、`os14_desktop_shell`、`ux03`、`ux05`、`ux07`、`foundation_regression`、`foundation_second_regression`、`widget_regression` 全绿；既有用例中“`>= 48`”“在 `rect.topLeft + (2,2)` 点击”一类断言无需改动即通过。
- Windows：`flutter build windows --debug` 成功产出 `matrixflow_native.exe`（仅构建验证）。
- **未测**：Android 触摸（`flutter devices` 无 Android 设备/模拟器），以及双端真窗口里 TalkBack / Narrator 的实际朗读文本、物理密度下的触摸尺寸、肉眼可见的焦点环与 Tab 顺序。这些不能由 widget 测试代替，按未验收处理。测试全部使用合成任务与无密钥数据。

## 6. 残余限制

- `FocusableActionDetector` 在 touch 高亮模式下**不绘制**焦点环（Flutter 的既有行为：只有键盘导航后才显示）。测试里用 `alwaysTraditional` 验证了绘制路径，真机上的观感仍需一次人工确认。
- 展开行沿用 `InkWell` 的 Material 焦点高亮，本包没有为它自绘焦点环，因此其可见性依赖主题的 `focusColor`；证据是焦点可达与键盘激活，不是像素级断言。
- 只覆盖 F16 点名的三类控件。任务卡右键菜单、`home_actions.dart` 的 `IconButton`/`ListTile`、筛选面板、输入表单等本来就是 Material 按钮（`PlatformUiPolicy.minActionSize` 已用于头部按钮），未改动；如果后续要做全应用触摸目标审计，那是另一包。
- 象限头部的“聚焦象限”交互仍走 OS13 的 `ExcludeFocus` 规则；本包新增的焦点节点位于同一子树内，因此被隐藏象限依旧不可 Tab 到达（`os13_focus_test` 未改即通过），但没有单独为隐藏子树写过新探针。
- 颜色点仍只有 5 个固定主题色，且没有“当前已选”的非颜色文字提示（读屏靠 `selected`，视觉靠外圈与勾）；对比度与色盲可读性不在本包范围。

## 7. 改动文件

- 产品代码：`matrixflow-native/lib/widgets/accessible_tap_target.dart`（新增）、`lib/widgets/task_hierarchy_checkbox.dart`、`lib/widgets/task_card.dart`、`lib/widgets/task_detail_panel.dart`、`lib/screens/settings_screen.dart`、`lib/screens/completed_screen.dart`、`lib/screens/search_screen.dart`、`lib/l10n.dart`。
- l10n：三语各新增 `a11yRoleParent`、`a11yRoleSubtask`、`a11yMarkComplete`、`a11yMarkIncomplete`、`a11ySubtaskToggle`、`a11yThemeColorOption`；移除已无引用的 `markTaskComplete`、`expandSubtasks`、`collapseSubtasks`。
- 测试：新增 `matrixflow-native/test/os19_affordance_test.dart`、`test/review/os19_review_probe.dart`（OS-R08）。未修改任何既有测试文件。
- 文档：仅本文件 `docs/OS19_NOTES.md`。

## 8. 下一位接手者需要知道的

- 集成时需要落到公共文档的内容：计划第 5 节 OS19 状态改为已实施并登记探针编号 **OS-R08**（现有 OS-R 只到 R07）；`ARCHITECTURE.md` 可记一句“小控件统一走 `AccessibleTapTarget`/`ConstrainedBox(minHeight: 48)`，状态用 semantics trait 而非标签”；`CHANGELOG.md` 顶部条目建议写“小控件触摸热区、读屏状态与键盘可达性”。
- 给 OS18 的提示（**本包未开始 OS18**）：`subtaskProgress` 文案与展开行文本测量都还在原处，展开行现在多了 `ConstrainedBox(minHeight: 48)`；字号预览若继续改 `task_card.dart` / 设置页，请注意设置页主题色一节的 `8 + 48 + 10 = 66` 高度不变量——它的下游用例对滚动位置敏感。
- 可领取：OS18（与本包共享设置页与文字 widget，需在 OS19 合入后再开）、OS20（Store 命令边界，`search_screen.dart` 里 `subtask.completed = val` 这类直接写仍待其收口）。
- 若要关闭“未测”项：需要一台 Android 真机（TalkBack 朗读、拇指边缘点击、放大文本后热区）与 Windows 实机（Tab/Shift+Tab 顺序、焦点环可见性、Narrator 对 `checked`/`expanded`/`selected` 的朗读）各一轮人工验证，并记录设备与系统版本。
