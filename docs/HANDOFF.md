# 项目交接文档（HANDOFF.md）

最后更新：2026-09-16。

## 最新任务：WP25-N-Android 已完成，下一包 WP25-N-Windows

- Flutter Android/Windows 为唯一持续开发客户端；React/Tauri/Capacitor 冻结保留。依据见 [已采纳 ADR](ADR_FLUTTER_PRIMARY_2026-09-09.md)。旧 W 是 React Web，不是 Windows。
- **本轮实施 WP25-N-Android Android 本地定时通知与提醒落地（功能闭环与全量回归）**：
  - **Android 清单与系统广播接收器配置（AndroidManifest.xml）**：
    - 声明 `POST_NOTIFICATIONS`（Android 13+ 通知运行时权限）、`SCHEDULE_EXACT_ALARM`（精确闹钟排程）、`RECEIVE_BOOT_COMPLETED`（开机恢复）与 `VIBRATE`；
    - 严格遵循 Google Play 策略，未声明 `USE_EXACT_ALARM`，杜绝任务类应用审核被驳回风险；
    - 配置 `ScheduledNotificationReceiver` 与 `ScheduledNotificationBootReceiver`，支持系统重启与后台电源管理唤起。
  - **数据模型与存储生命周期联动（lib/models.dart & lib/storage.dart & docs/DATA_COMPATIBILITY.md）**：
    - `Task` 扩展 `reminderAt`（`int?`）与 `reminderTimezone`（`String?`）；`SubTask` 扩展 `reminderAt`（`int?`）；
    - `AIAnalysisResult.toTask` 扩展 `reminderAt` 与 `reminderTimezone`，新建草稿与 AI 分类结果无缝承载提醒时间；
    - 严格践行 WP11-N 数据迁移契约：`ExportData v2` 导出完整序列化提醒字段，`version: 1` 降级导出时安全剥离字段，`fromJson` 对缺失字段默认回退 `null`；
    - `Store` 状态机联动：
      - `Store.init()` 启动时自动重新排程未来未完成提醒（`rescheduleAllFuture`）；
      - `addTasks` 自动为新增含未来 `reminderAt` 任务排程；
      - `updateTask` 任务勾选完成即时注销提醒，未完成时根据 `reminderAt` 动态重排或取消；
      - `deleteTask` 与 `deleteTaskWithUndo` 级联取消父任务与子任务通知；
      - `applyUndo` 撤销删除恢复时自动重排未完成任务提醒；
      - `clearBoard`、`clearQuadrant`、`deleteBoard` 批量注销关联看板所有通知；
      - `importData` 覆盖导入全量清理并重排新备份，合并导入只排程新增任务。
  - **通知抽象与本地通知服务实现（lib/services/reminder_service.dart）**：
    - 实现 31 位确定性 FNV-1a 字符串哈希算法 `generateNotificationId(taskId, {subtaskId})`，生成 31 位正整数 Notification ID，杜绝跨任务与父子任务哈希冲突；
    - `ReminderPayload` 结构化载荷（`taskId`、`subtaskId`、`boardId`），支撑通知点击深度路由唤醒；
    - `FlutterLocalNotificationsReminderService` 完整实现 Android 通知通道、精确闹钟（`exactAllowWhileIdle`）调度、通道配置，内置 `if (!_initialized) return;` 防崩保护守卫，在测试环境或桌面静默安全降级；同时提供 `InMemoryReminderService` 与 `NoopReminderService`。
  - **UI 交互、快速预设与保活指南（task_detail_panel.dart, input_sheet.dart, settings_screen.dart, task_card.dart, l10n.dart）**：
    - 任务详情面板集成提醒时间选择器与一键清除按钮（`edit-reminder-btn` / `clear-reminder-btn`），提供快速预设 Quick Chips（截止日当天 09:00、今天 18:00、明天 09:00、自定义时刻）；子任务支持独立提醒选择；
    - 新建任务弹层（`InputSheet`）集成可选提醒入口（`input-reminder-btn`），与截止日期互不干扰；
    - 设置页新增“提醒可靠性指南”弹层（`reminder-guide-tile`），向用户介绍主流国产 ROM（小米、华为、OPPO、vivo）后台电池保活与自启动配置，并提供“检查提醒与通知权限”（`check-permissions-btn`）实时状态检测弹窗；
    - 四象限矩阵卡片与子任务展示激活提醒小闹钟角标（`Icons.notifications_active_outlined`）；
    - 完整补齐中、英、日三语本地化字典。
  - **测试与基线保持**：全套自动化测试回归达 **237/237**（`flutter test --no-pub` 全绿），`flutter analyze --no-pub` **0 issues**。未改 React，Android 实机与物理闹钟未做实测（写明待验）。
- **下一包 WP25-N-Windows**：Windows 桌面端通知与提醒落地（联动 WP26-B DesktopShellService 托盘机制，实现 Windows Toast 本地通知、桌面后台保活或托盘静默期间的准时触发与点击唤醒、Windows 平台无侵入降级）。
- WP20-N、WP21-N、WP03-N、WP04-N、WP23-N、WP12-S-N、WP22-A-N、WP22-B-N、WP05-N、WP06-N、WP02-N、WP01-N、WP07-N、WP08-V-N、WP08-T-N、WP24-N、WP26-A-N、WP26-B-N-Windows、WP27-A-N、WP11-N、WP22-C-N、WP13-A-N、WP25-R、WP25-N-Android 继续保留。
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
| `flutter test --no-pub`（2026-09-16 WP25-N-Android） | **237/237**，含 WP25 提醒/WP13-A-N 备注/WP22-C 日历天人工紧急性/WP11 迁移/WP26 命令面板/桌面壳/WP27 统计条/WP24 滑动撤销/WP08 列表字号/WP07 已完成/WP01 服务商预设/WP02 清空看板/WP06 语言/WP05 移动/WP22 日期/WP12 搜索/WP23 聚焦/WP04 详情/WP03 十字/WP21/WP20 全量回归 |
| `flutter test --no-pub` | **237/237 passed**（包含 models_test、reminder_service_test、deadline_policy_test 与全量 UI 回归） |
| `flutter analyze --no-pub`（同轮） | **0 issues** |
| Android 物理真机通知/闹钟响铃（WP25-N-Android） | **未测**；Flutter Local Notifications 逻辑与调度完整覆盖，物理设备需后续真机安装测试 |
| Windows 实机（WP25-N-Android） | **未测**；Windows 通知在下一包 WP25-N-Windows 落地 |
| 真实模型分类 | **未测**；mock 只证明请求契约 |
| Web `npm run build` / `tsc` | 本轮未跑；WP20-W 已取消 |
| 历史 Android release / Redmi K70 E2E | 前轮通过，不能代替本轮验收 |

## 下一轮启动提示词

```text
接手 D:\Dev_project\martix，只实施 docs/IMPLEMENTATION_PLAN_2026-09-08.md 的 WP25-N-Windows。先读 AGENTS.md、本 HANDOFF、计划第 1/3/5 节、WP25-N-Windows 与 docs/REMINDERS_DESIGN.md。

Flutter Android/Windows 是唯一持续开发客户端；旧 W 指 React Web。先 git status 保护未提交文档。不改 React，不重做 WP20-N/WP21-N/WP03-N/WP04-N/WP23-N/WP12-S-N/WP22-A-N/WP22-B-N/WP05-N/WP06-N/WP02-N/WP01-N/WP07-N/WP08-V-N/WP08-T-N/WP24-N/WP26-A-N/WP26-B-N-Windows/WP27-A-N/WP11-N/WP22-C-N/WP13-A-N/WP25-R/WP25-N-Android。

本包只做 Windows 端本地通知落地接线：联动 WP26-B DesktopShellService 托盘与后台保活机制，实现 Windows Toast 本地通知、桌面后台保活或托盘静默期间的准时触发与点击唤醒、Windows 平台无侵入降级。

用 D:\Dev_SDKs\Flutter_SDK\bin\flutter.bat 在 matrixflow-native/ 跑 test --no-pub 与 analyze --no-pub。237/237 是 WP25-N-Android 基线。未测实机写明。完成后交接后续，停止。
```

## 本轮收尾（WP25-N-Android）

  - 测试：`test/models_test.dart`、`test/reminder_service_test.dart`、`test/deadline_policy_test.dart`、`test/widget_regression_test.dart` 全量通过；
  - 静态检查：`flutter test --no-pub` **237/237** 全绿，`flutter analyze --no-pub` **0 issues**。未改 React，未做实机。
- 未测：Android / Windows 物理真机环境下的原生通知横幅与声音（写明待后续实机验收）。
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
