# OS20 实施记录：Store 命令边界与修订号

日期：2026-09-25。包号：**OS20**（对应审查报告 F17）。状态：**已实施**。Android 与 Windows 设备未测。

## 1. 接手与边界

- 基线：`main / 0f5e4f62b4d4fc6a7dcb2440dd12e540dcd4196d`。独立 worktree `D:\Dev_project\martix-wt-os20`，分支 `codex/os20`。接手时主工作区干净，本包不在主工作区改文件。
- 固定 SDK `D:\Dev_SDKs\Flutter_3.32.8`（Flutter 3.32.8 / Dart 3.8.1）。未改依赖，也未改 `pubspec.lock`。worktree 首次测试前执行了 `flutter pub get` 以生成本地包配置；`pub get` 只让三个 Windows 插件生成文件出现行尾差异，已还原，未提交。
- 未改 `settings_screen.dart`、`theme.dart`、`animated_task_title.dart`、`task_card.dart`、`motion_policy.dart`，也未改 OS23 的 `anim.dart`、`task_exit.dart`、`quadrant_transition_layout.dart`、`quadrant_pane.dart`、`task_list_view.dart`、`onboarding_screen.dart`。
- 未改 `AGENTS.md`、`HANDOFF.md`、`ARCHITECTURE.md`、`CHANGELOG.md` 和开源准备计划。未开始 OS21。冻结 React/Tauri/Capacitor。暂停 WP10/WP29/UI 实验。
- 只用合成任务和假提醒服务。没有真实密钥、用户备份或设备。

## 2. 修订号与撤销规则

先核对了现有契约，再补缺口。

`canApplyUndo` 原来就拒绝：板不存在、板 epoch 变化、非 0 的 `commandSeq` 与当前任务修订不一致、完成/恢复撤销的标题或象限已变、删除撤销时任务又出现。`updateTask`、`deleteTask` 和带撤销的完成/删除会推进 `_taskSeq`。`moveTask` 和 `resetTaskUrgencyMode` 不会。

因此「移走再移回」会把象限变回快照里的值，修订号却不变，旧的完成撤销重新变为可应用，并覆盖完成状态。紧急模式重置只改 `urgencyMode`（没有截止日期时象限也不变），标题和象限检查同样放行。

现在的规则：

- 改变该任务的命令推进该任务的修订：父项或子项编辑、完成、删除、象限移动（含移回原象限）、确实改变了模式的紧急重置，以及把象限改掉的截止日期自动提升。
- 撤销快照记录的是这条可撤销命令自己执行之后的修订。之后任一相关命令让修订对不上，整张快照拒绝，不会把旧完成状态写回。
- 移到同一象限不是编辑，不推进修订，也不重排。
- 紧急重置若模式和象限都没变（已经是 auto，提升也不移动），不推进修订，旧撤销仍可应用。
- 象限被自动提升改掉时，提升本身推进修订；重置只在「模式变了但象限没变」时再推进一次，避免同一次重置算两次。
- `commandSeq == 0` 仍表示旧快照没有记录修订，只走板、epoch、标题、象限和存在性检查。当前完成/删除撤销都会写入非 0 修订。
- 修订号只在进程内。撤销条本身也不跨重启，所以不写入备份或 OS06 批次。

## 3. 命令与只读快照

- `tasks` / `boards` 改为不可修改的列表视图。列表增删仍只在 Store 命令里进行。测试里原先的 `store.tasks.add` 改为 `addTasks`；需要跳过提醒排程的夹具改用 `debugReplaceTasks`。
- `captureSnapshot()` 返回板、任务、配置、设置、当前板和任务修订的深拷贝。改快照不会写回 Store。
- `Task` / `SubTask` / `AIConfig` 仍是可变对象，没有一次改成不可变模型，也没有引入新的状态管理框架。查询列表里的任务实例仍是 Store 持有的对象；生产路径通过命令提交，不先改这份对象再调用 `updateTask`。
- `setParentCompleted` 和 `setSubtaskCompleted` 改为先拷贝再交给 `updateTask`，这样旧值比较、完成时间和提醒差异仍然可靠。矩阵卡片继续用级联的 `setParentCompleted`。
- 搜索页原先直接写 `task.completed` / `subtask.completed` 再 `updateTask`。现改为 `setTaskCompleted`（只改父项，不级联子项，保持搜索原语义）和 `setSubtaskCompleted`。
- 详情页编辑的是草稿拷贝，保存仍走 `updateTask`。输入表在调用 `addTasks` 之前组装新任务。这些不是对库内对象的直接写。
- 移动和紧急重置会 `_saveTasks`。它们不改 `reminderAt`，因此不重新排程；已有提醒保持。内容、完成、删除、添加和撤销仍按原约定调用提醒端口。
- 同步 `importData` 仍保留给现有测试：先预检，再改内存并排队保存。产品文件导入继续只用 `applyImport`（先提交 OS06 批次再改内存）。旧 v1/v2 备份、凭据迁移和 OS17 提醒重试入口没有改契约。

## 4. 组合根注入

- `Store` 增加 `reminders` 和 `persistence`。`main` 把 `ReminderService.instance` 和 `SharedPreferencesStorePersistence` 传进去。未传入时提醒仍回落到 `ReminderService.instance`，持久化仍打开 `SharedPreferences.getInstance()`，所以现有测试不用改构造。
- 保存协议仍是 OS06 的 `SaveProtocol` 加既有 `saveWriter`。提醒调用走注入的服务，复用 OS17 的 `scheduleReminder` / `cancelReminder` / `reconcileReminders` / `resetAllReminders`。
- 矩阵页把通知点击绑到 `store.reminderService`，不再直接绑单例。失败横幅的三个 `ValueNotifier` 同样改听 `store.reminderService`。生产里它就是 `main` 注入的那个实例。

## 5. 验证

- 专项 `test/os20_store_boundary_test.dart`：**12/12**。覆盖移走再移回、同象限移动、紧急重置、空操作重置、父项编辑、子项改名、子项删除、子项完成、任务删除、移动与重置后重新打开、注入的提醒服务、搜索式父项完成不级联、快照隔离、不可修改列表、注入的持久化端口，以及设置页仍依赖的「先改 live config 再 `updateAIConfig`」。
- 默认 `flutter test --no-pub`：**526/526**（基线 514，加上本包 12 项）。其中包含 `test/ux_state_regression_test.dart` 的 R1–R5/S1。`flutter analyze --no-pub`：**No issues found**。
- **未测**：Android 与 Windows 设备上的移动、撤销、保存和提醒。没有启动应用，没有真通知。单元测试不能代替这些。

## 6. 交给集成人的最小接口

本包不能改设置页。`settings_screen.dart` 仍直接改 live `aiConfig` 再调用 `updateAIConfig`，包括：

- 切换 provider 时连续赋值 `provider`、`apiKey`、`baseUrl`、`protocol`、`model`，然后 `updateAIConfig(store.aiConfig)`。
- `store.updateAIConfig(store.aiConfig..apiKey = v)`，以及同样的 `model`、`protocol`、`baseUrl`、`enableThinking` 级联赋值。
- 发现模型后 `store.aiConfig.model = best` 再 `updateAIConfig(store.aiConfig)`。

这些调用今天仍然有效，因为 `aiConfig` 还是 live 对象，`updateAIConfig` 会拷贝传入的配置。集成时不要把 `aiConfig` 改成每次返回新拷贝，除非同时改设置页。目标写法：

```dart
final next = store.captureSnapshot().aiConfig;
next.model = value;
await store.updateAIConfig(next);
```

设置页和提醒测试按钮仍使用 `ReminderService.instance`。生产组合根注入的就是这个单例，所以和 Store 是同一个对象。若以后注入另一个实现，设置页应改为 `store.reminderService`。

OS23 文件已经通过命令改任务，本包没有改它们：`task_card.dart` 调用 `setParentCompleted`、`setSubtaskCompleted`、`moveTask`；`quadrant_pane.dart`、`task_list_view.dart`、`quadrant_transition_layout.dart` 调用 `moveTask`。它们拿到的仍是 `store.tasks` 里的 live 实例。

## 7. 改动文件

- 产品代码：`matrixflow-native/lib/storage.dart`、`lib/main.dart`、`lib/screens/matrix_screen.dart`、`lib/screens/search_screen.dart`、`lib/widgets/reminder_failure_banner.dart`。
- 测试：新增 `test/os20_store_boundary_test.dart`；调整 `test/foundation_second_regression_test.dart`、`test/ux03_regression_test.dart`、`test/widget_regression_test.dart` 里对任务列表的直接添加。
- 文档：仅本文件 `docs/OS20_NOTES.md`。

## 8. 下一位

- 可领取：OS21（页面只编排展示与输入，依赖本包的命令和 `captureSnapshot`）。OS22 也可以开始测量，但不依赖本包的 UI 拆分。
- 公共文档由集成人更新。设置页的 config 直接写入见第 6 节，不要在 OS18 里顺手把 `aiConfig` 改成拷贝。
