# OS27 文案子批次（B）记录

本文件记录 B 分支提交时的状态；托盘随语言变化的接口已由集成人补齐，最终结果见 [HANDOFF 顶部](HANDOFF.md)。

基线：`main / 1625c1767b1893847ff4650218aba0e41a2886d4`，独立 worktree `D:/Dev_project/martix-wt-os27b`（分支 `os27-copy-review`）。
独占文件：`matrixflow-native/lib/l10n.dart`、`lib/screens/onboarding_screen.dart`、`lib/services/desktop_shell_windows.dart`、`test/os27_copy_test.dart` 与本文件。
未改：README、ARCHITECTURE、DEVELOPMENT、CONTRIBUTING、SECURITY、`pubspec.yaml`、AGENTS/HANDOFF/CHANGELOG/实施计划；未触碰冻结的 React/Tauri/Capacitor；未开始下一包。

## 1. 已核对的代码事实（文案据此改写）

- 网络出口：`lib/` 内只有 `ai_service.dart` 构造请求 URI（`{base}/chat/completions`、`{base}/responses`、`{base}/messages`、`GET` 模型列表），`base` 来自用户在设置里填写的地址；其余目录检索 `Uri.parse|http.|Socket|analytics|telemetry` 无命中。⇒ 文案改成“AI 请求把相关任务文本发送到你配置的端点”，不再声称数据 100% 留在本机。
- 拖拽与移动菜单：`widgets/quadrant_pane.dart:301` 用 `LongPressDraggable`（鼠标按住同样触发）；`widgets/task_card.dart:219` 的 `onSecondaryTapDown` 打开 `task_card.dart:596` 的右键菜单，菜单项为完成 / `moveTo` 四象限 / 删除。⇒ 桌面引导句改为“按住拖动，或右键使用‘移动到’”，删除并不存在的“长按菜单”和含义错误的 “secondary tap”。
- 5 秒撤销：`widgets/task_card.dart:559` `Duration(seconds: 5)`（`storage.dart:988` 同注释）。⇒ 引导第 4 步的 “5s Undo” 保留。
- 多行批量添加：`widgets/input_sheet.dart:301` 按 `\n` 拆分，`single` 模式逐行 `addTasks`。⇒ 引导第 1 步的多行说明保留。
- `shortcutHint` / `shortcutHintWindows` 的真实用途是输入面板提示（`input_sheet.dart:109,115`），原引导第 2 步误用 `shortcutHint`，显示的是“Ctrl+Enter 提交”。⇒ 新增专用 key，未改这两个 key 的值。
- 托盘：`desktop_shell_windows.dart` 原本硬写 `'Show MatrixFlow'/'Quick Add'/'Search'/'Exit'`，而字典里 `trayShowWindow/trayQuickAdd/traySearch/trayExit` 三语齐全且英文值为 `'Show MatrixFlow'/'Quick Add Task'/'Search Tasks'/'Exit Application'`——即托盘文案与字典已经漂移，且完全不随语言变化。

## 2. 本包改动

**准确性（三语同步，`l10n.dart`）**
1. `onboardingStep5Title` / `onboardingStep5Desc`：删除英中日各自的“100% 本地保存 / stays 100% locally / 100%端末内に保存”和“Privacy/プライバシー優先”式承诺，改为说明任务默认保存在本机、发起 AI 请求时相关任务文本发送给用户配置的端点、无密钥仍可用全部手动功能。
2. `aiNote`（AI 输入框下方就地提示）：补充“AI 会把你输入的文本发送到设置中填写的端点”，保留额度说明。
3. `importModeMergeDesc`：删除 “No data lost / 不丢失数据” 式无损承诺，改为“添加到现有任务板，保留当前数据”（合并仍会跳过孤儿记录、归一化字段，见 `BACKUP_FORMAT.md`）。
4. `windowsReminderGuideIntro`：删除 “never miss a reminder / 确保不错过任何” 的绝对承诺，与同页已有的“系统可能延迟或静音通知”一致。
5. `onboardingStep2Desc`（仅桌面布局使用）：三种语言都改为“按住拖动 / 右键‘移动到’”，去掉不存在的长按菜单表述。

**清理引导硬编码（`onboarding_screen.dart`）**
6. 移除全部 `?? 'English'` 兜底字面量（步骤标题、描述、Skip/Next/Previous/Get Started/Close、象限样例、已完成样例），改为字典取值；页面结构、5 页布局、按钮、快捷键与动画路径未动。
7. 样例任务文本改由字典提供，新增 10 个三语 key：`onboardingDragHint`、`onboardingLocalBadge`（替换硬写的 `100% Local Storage · Pure Client · BYOK`）、`onboardingSampleQ1..Q4`（四象限清单，`\n` 分隔）、`onboardingSampleDragTask`、`onboardingSampleDetailTask`、`onboardingSampleSubtask1/2`。第 2 步图示的提示改用 `onboardingDragHint`。
8. 保留未译：品牌字面量 `DeepSeek/Qwen/Doubao/OpenAI`、图示时间 `09:00`、`12:30`。

**托盘文案（`desktop_shell_windows.dart`）**
9. 托盘 tooltip 与四个菜单项改为读取字典 key（原硬编码英文），使文案单一来源并与设置页措辞一致。宿主仍拿不到语言：见第 4 节跨界请求。

**字典补齐（`l10n.dart`）**
10. ja 缺失的 6 个 key 补齐：`completedAtBadge`、`completedTimeUnknown`、`filterAllTime`、`filterToday`、`filterPast7Days`、`sortRecentCompleted`（此前 en/zh 445、ja 439）。现三语各 455 key，占位符逐 key 一致。

## 3. 验证

- 新增 `test/os27_copy_test.dart` **17/17**：三语 key 集合一致、逐 key 占位符一致、全字典禁用绝对化承诺（`100%|绝对|絶対|不丢失数据|No data lost|never miss|不错过任何|見逃さない`）、AI 文案必须点明端点、引导页源码不再含 `100%` 与英文兜底字面量、托盘源码引用字典 key 且无 `label: '...'` 字面量、zh/ja 五个引导页全部可见文本无非白名单拉丁串（白名单仅品牌名）、第 2 步显示 `onboardingDragHint` 而非提交提示。
- 反向自检：临时把 `onboardingSampleQ1` 改回英文字面量，`zh onboarding slide 1` 立即失败，随后还原，确认该守卫不是空跑。
- 默认 `flutter test --no-pub` **577/577**（基线同 worktree 实测 **560/560**，新增 17 项即本包文案测试）；`flutter analyze --no-pub` **No issues found**。固定 SDK `D:/Dev_SDKs/Flutter_3.32.8`（Flutter 3.32.8 / Dart 3.8.1），未运行 `dart format`（本仓库提交排版与该 SDK 输出不一致，见项目记忆）。
- `flutter pub get` 在该 worktree 只带来三个 Windows 插件生成文件的行尾差异（`windows/flutter/generated_plugin_registrant.{cc,h}`、`generated_plugins.cmake`），保持未暂存、未纳入提交，与前几波一致。
- 未测：Android/Windows 真机与真托盘。本包没有设备（未执行 `flutter run`、未执行 `tool/os14_windows_shell_smoke.dart`/`tool/os25_platform_smoke.dart`），因此“Windows 托盘菜单实际显示字典文案”“引导页在真机字号/软键盘下的排版”标为**未验证**；widget 测试只证明 Flutter 侧渲染取字典值。

## 4. 跨界请求（本包未改，交集成人）

1. **托盘三语化需要接口**：`DesktopShellHostCallbacks`（`lib/services/desktop_shell_host.dart`）目前不带文案，`DesktopShellService._applySettingsNow()`（`lib/services/desktop_shell_service.dart:213`）只在托盘首次成功时调用一次 `host.start()`。要让托盘跟随语言，需要 callbacks 携带 4 个标签 + 语言变化时重设 context menu（服务里已有一次性 `_trayResult` 门槛）。本包只做到“标签取自字典”，语言仍为英文。
2. **设置页缺 AI 数据边界条目**：AI 分区（`lib/screens/settings_screen.dart`）没有“会发出哪些数据”的固定说明，当前边界只出现在引导第 5 步与 `aiNote`。若要在设置页补一行，需要新增 widget 与新 key（`l10n.dart` 侧已可加），属设置页归属包。
3. **测试标题仍含“100% lossless”**：`test/data_migration_test.dart:247` 的用例名 “Flutter Android <-> Windows roundtrip interchangeability is 100% lossless” 与 `BACKUP_FORMAT.md` 记录的 v2→v1 有损降级不一致（同一文件 `:184` 的 “100% intact” 是原子性描述，无碍）。该文件归 OS04/OS07 线，未改。
4. **6 个 ja 补齐 key 目前在 `lib/` 内零引用**（`completedAtBadge`、`completedTimeUnknown`、`filterAllTime`、`filterToday`、`filterPast7Days`、`sortRecentCompleted`）。本包为维持三语集合一致而补齐，若确认属已删除界面残留，请由集成人连同其他死 key 一并处置，不建议在本包删字典项。

## 5. 结论与残余

- 引导与托盘不再有硬编码英文；“绝对隐私 / 100% 本地 / 无损 / 绝不错过”式表述在应用内文案中已清除，AI 数据去向改为按代码事实描述。
- 引导页结构、页数、交互与动效未改；未恢复任何已删除功能（统计、命令台等只保留原字典中未被引用的既有条目）。
- 默认全量 `flutter test --no-pub` 577/577、`flutter analyze --no-pub` 0 issues（数字见第 3 节）。
- 平台层：托盘真实显示、双端实机引导手感未测；OS26 正式签名与托管发布仍待持有人，本包不宣称发行就绪。
