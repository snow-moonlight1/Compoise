# 更新日志

> 本项目在开发期间未维护变更日志。以下内容于 2026-08-30 依据 Git 提交历史（`git log`）与代码现状重建整理，格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)。
>
> 开发周期：2025-11-22 至 2025-11-25，共 7 个提交，均为 `main` 分支直线历史（无标签、无远端仓库）。
>
> 2026-09-03 起进入修复与打磨阶段，新增条目按日期追加在下方。
## 2026-09-12 · V0.3-A (WP26-A-N, WP26-B-N-Windows, WP27-A-N) 命令面板、快捷键、桌面托盘与统计进度

- **应用内命令面板与快捷键体系（WP26-A-N: shortcuts.dart & widgets/command_palette.dart）**：
  - 全局快捷键与意图体系：`matrixShortcuts` 映射 Ctrl+K 呼起命令面板、Esc 关闭/返回、Ctrl+N 新建任务、Ctrl+F 本地搜索、Ctrl+Shift+C 查看已完成、Ctrl+M 切换视图模式、Ctrl+, 设置面板、Ctrl+/ 快捷键帮助对话框。
  - 原生输入法与文本框焦点保护：在文本输入框获得焦点时（`_isTextEditingFocused()` 判定 `primaryFocus` 为 `EditableText`），快捷键自动让位，不拦截单键及原生文本操作（撤销/复制/剪切/粘贴），确保中文 IME 组词与正文编辑不受任何干扰。
  - 命令面板模态框（`CommandPaletteDialog`）：支持关键字即时模糊搜索应用内置核心命令以及跨看板的待办任务（复用 `queryTasks`）；支持键盘上下箭头高亮导航、Enter 执行与鼠标/触摸点击；命令覆盖导航、视图模式切换、设置与帮助，所有快捷操作均在界面有对应按钮替代，不强迫记忆快捷键；跨看板任务直接跳转原看板并打开详情面板高亮显示。
- **Windows 桌面壳集成与托盘（WP26-B-N-Windows: services/desktop_shell_service.dart & screens/settings_screen.dart）**：
  - 跨平台桌面抽象服务 `DesktopShellService`：在非桌面平台（Android / Web）采用安全空实现（no-op），无任何崩溃或平台通道异常；在 Windows 桌面抽象托盘生命周期、系统托盘右键菜单（显示主窗口、快速新建、本地搜索、退出应用）。
  - 关闭到托盘选项：`AppSettings` 扩展 `closeToTray`（默认 `false`）与 `globalShortcut`（默认 `'Ctrl+Alt+M'`）；设置页新增“桌面与系统设置”（`desktopSettings`）小节，提供关闭到托盘 Switch 开关与首次启用退出说明 SnackBar；支持窗口关闭拦截与托盘隐藏；全局热键支持冲突安全处理，冲突时不阻断应用正常启动与运行。
- **当前进度与完成统计条（WP27-A-N: task_stats.dart & widgets/task_stats_bar.dart）**：
  - 纯计算模型 `computeTaskStats`：精准计算父任务总数、已完成数、未完成数、完成百分比（针对空任务列表安全兜底 0%，彻底杜绝 100% 虚假显示）；父任务与子任务计数严格独立，杜绝父子双重计量；逾期统计（`overdueTasks`）仅对已超期且未完成的任务生效，已完成任务不计入逾期；统计计算不受 `hideCompleted` 偏好影响。
  - 统计条组件 `TaskStatsBar`：在主界面四象限/列表顶部呈现紧凑统计条；展示完成度百分比（如 `完成率: 50%`）、未完成徽章、逾期徽章（如有）、子项进度（如 `子项: 1/2`）以及看板范围切换按钮（当前看板 vs 全部看板）；采用 `Wrap` 弹性流式布局，彻底避免超窄屏及大字号缩放下的 RenderFlex 溢出；在已完成任务页（`CompletedScreen`）同步集成完成率状态。
- **中英日多语言扩充（l10n.dart）**：补齐 `commandPalette`、`shortcutsHelp`、`desktopSettings`、`closeToTray`、`statsCompletionRate`、`statsOverdue`、`statsSubtasks`、`statsScopeCurrent`、`statsScopeAll` 等三语字典词条。
- **验证**：`D:\Dev_SDKs\Flutter_SDK\bin\flutter.bat test --no-pub` **182/182**（全套测试 100% 通过，新增 16 项涵盖命令面板与快捷键、桌面抽象服务、任务统计计算与 TaskStatsBar UI 组件测试）；`analyze --no-pub` **0 issues**。未做 Android/Windows 实机，未改 React。

## 2026-09-12 · WP24-N Flutter 滑动操作、撤销与轻量反馈

- **撤销架构与命令快照（task_commands.dart & storage.dart）**：新增 `TaskUndoSnapshot` 与 `TaskUndoType`（complete 完成、restore 恢复、delete 删除）快照模型；保存单任务深拷贝、子项状态、看板 ID、象限与原始数组索引位置；`Store` 新增 `deleteTaskWithUndo(id)` 与 `toggleCompleteWithUndo(task)`，在删除或切换完成时原子捕获快照并返回；新增 `canApplyUndo(snapshot)` 与 `applyUndo(snapshot)`，在撤销窗口内支持原位置、原顺序精确恢复父子任务及级联状态；撤销只针对当前命令操作的数据，不保留整板回滚副本。
- **严格撤销失效契约与代数隔离（storage.dart）**：`Store` 建立看板代数（`_boardEpoch`）；在整板清空（`clearBoard`）、单象限清空（`clearQuadrant`）、删除看板（`deleteBoard`）以及覆盖导入（`importData(mode: 'overwrite')`）时自增看板代数；若任务已被后续编辑修改、目标看板已被删除或看板代数发生改变，撤销立即判定失效并提示（`undoUnavailable`），严防幽灵任务复活或覆盖最新状态。
- **卡片滑动交互与轻触觉反馈（widgets/task_card.dart）**：`TaskCard` 在普通模式下包裹 `Dismissible`（右滑标记完成/恢复、左滑删除）；多选模式自动关闭滑动（`DismissDirection.none`）；右滑完成平滑回弹并弹出带「撤销」动作的 5 秒浮动 SnackBar；左滑删除立即移除任务并弹出 5 秒「撤销」SnackBar；操作触发轻触觉反馈（`HapticFeedback.lightImpact`，Windows 平静降级）；右键次级菜单提供对等的一键完成/恢复、移动象限与删除动作及 5 秒撤销；预先捕获 `ScaffoldMessengerState`，杜绝卡片移除后 context 卸载导致的查找异常。
- **中英日多语言扩充（l10n.dart）**：补齐 `undo`、`complete`、`taskCompleted`、`taskDeleted`、`actionUndone`、`undoUnavailable` 三语字典词条。
- **验证**：`D:\Dev_SDKs\Flutter_SDK\bin\flutter.bat test --no-pub` **166/166**（新增 8 项 task_commands 单元测试与 4 项 task_card 滑动/右键/多选禁用/撤销端到端 Widget 回归测试，全套 166 项测试 100% 通过）；`analyze --no-pub` 0 issues。未做 Android/Windows 实机，未改 React。

## 2026-09-12 · WP08-T-N Flutter 字号与字体偏好

- **显示偏好模型与持久化（models.dart & storage.dart）**：新增 `FontSizePref` 枚举（`small` 0.88x、`standard` 1.0x、`large` 1.15x）与 `FontFamilyPref` 枚举（`system` 默认系统字体、`sansSerif` 无衬线体、`serif` 衬线体、`monospace` 等宽字体）；`AppSettings` 扩展 `fontSize` 与 `fontFamily` 字段，`fromJson` 支持反序列化与缺省安全兜底，`toJson` 输出显示偏好配置；`Store` 增加 `setFontSize(size)`、`setFontFamily(family)` 与 `resetDisplayPreferences()`（一键恢复默认主题、字号、字体与视图模式），变更时自动持久化到本地存储并触发通知。
- **动态排版体系与 TextScaler 适配（theme.dart & main.dart）**：`theme.dart` 增加 `fontScaleFactor`、`fontFamilyFor` 与 `fontFamilyFallback` 跨平台字体映射；实现 `CombinedTextScaler` 自定义 `TextScaler`，遵循 Flutter 3.16+ 规范，继承自 `TextScaler`，通过乘积复合应用系统无障碍字体缩放（`systemScaler.scale(fontSize) * appFontScale`），实现非弃用的 `scale(double fontSize)` 与 `double get textScaleFactor => scale(1.0)`，既不破坏用户系统的辅助功能字体缩放，又精准响应应用内小/标准/大字号偏好；在 `MaterialApp.builder` 与 `ThemeData` 中注入字体家族与文字缩放。
- **设置页偏好控制与即时预览（screens/settings_screen.dart & l10n.dart）**：设置页新增“字体与显示”（`fontAndDisplay`）小节；提供字号（小、标准、大）ChoiceChip 单选与字体系列（系统默认、无衬线、衬线、等宽）ChoiceChip 单选；下方提供即时排版预览卡片（`font-preview-card`），内含标题、正文与代表性象限任务预览，支持所见即所得动态刷新；提供“恢复默认显示”（`reset-display-btn`）按钮，一键还原显示偏好；补充中英日三语多语言词条。
- **验证**：`D:\Dev_SDKs\Flutter_SDK\bin\flutter.bat test --no-pub` **154/154**（新增 3 项 FontSize/FontFamily 单元测试与 2 项 SettingsScreen 端到端 Widget 回归测试，全套 154 项测试 100% 通过）；`analyze --no-pub` 0 issues。未做 Android/Windows 实机，未改 React。

## 2026-09-12 · WP08-V-N Flutter 宫格/列表视图切换

- **显示偏好模型与持久化（models.dart & storage.dart）**：新增 `ViewMode` 枚举（`grid` 宫格四象限模式、`list` 纵向分节列表模式）；`AppSettings` 扩展 `viewMode` 字段（默认 `ViewMode.grid`），`fromJson` 支持反序列化与缺省兜底，`toJson` 输出显示偏好；`Store` 增加 `setViewMode(mode)` 与 `toggleViewMode()`，两视图模式纯粹作为显示偏好，底层使用完全相同的 `tasks`、`visibleTasks` 与 `tasksIn(q)`，不复制、不重排、不篡改原始数据与 `createdAt`；支持本地设置持久化。
- **纵向四象限列表视图组件（widgets/task_list_view.dart）**：新增 `TaskListView` 组件；按紧急/重要四象限纵向分节排列；每个象限小节均展示象限代表色圆点、完整维度名称、当前象限任务数量角标；支持空态友好文字提示；无缝复用 `TaskCard` 组件，保持完成勾选、逐行删除线、子任务展开与折叠、多选高亮与编辑操作完全一致；每个象限整体包裹 `DragTarget<Task>` 并提供悬停高亮边框反馈与轻触震动，在列表模式下完全支持跨象限长按拖拽置顶移动与移动提示 SnackBar；象限头部提供点击进入单象限聚焦视图。
- **主界面与操作栏无缝集成（screens/matrix_screen.dart）**：`activeCenter` 依据 `store.settings.viewMode` 智能切换展示十字无框四象限宫格（`_grid`）与纵向列表（`TaskListView`）；单象限聚焦时平滑进入聚焦视图，退出聚焦无缝保留原视图模式；头部操作栏新增视图模式切换按钮（`ValueKey('view-mode-toggle-btn')`），支持一键在宫格（`Icons.grid_view`）与列表（`Icons.view_agenda_outlined`）间切换并展示多语言 Tooltip；将头部操作栏包裹于紧凑 `IconButtonTheme` 并微调水平边距，彻底解决 320px 超窄屏及系统 1.5x 文字缩放下 6 个操作图标按钮导致的水平溢出问题。
- **中英日多语言扩充（l10n.dart）**：补齐 `viewMode`、`viewModeGrid`、`viewModeList`、`noTasksInQuadrant` 三语字典词条。
- **验证**：`D:\Dev_SDKs\Flutter_SDK\bin\flutter.bat test --no-pub` **149/149**（新增 3 项 ViewMode 单元测试与 2 项 TaskListView/ViewMode 切换端到端 Widget 回归测试，全套 149 项测试 100% 通过）；`analyze --no-pub` 0 issues。未做 Android/Windows 实机，未改 React。

## 2026-09-12 · WP07-N Flutter 已完成任务集中查看

- **存储层直接查询与恢复机制（storage.dart）**：`Store` 新增 `completedTasks({boardId})` 与 `completedTaskCount({boardId})`；直接从底层 `tasks` 查询 `completed == true` 记录，不受 `settings.hideCompleted` 偏好影响，不复制任务对象，不伪造历史完成时间；新增 `restoreTask(task)` 与 `restoreTaskById(id)`，调用既有父/子级联规则 `setParentCompleted(task, false)` 将父任务及所有子任务重置为未完成，防止 `settings.autoCompleteParent` 因“子项全满”立即将父任务重新标完；恢复后任务立即在原看板、原象限中重新可见并持久化。
- **已完成任务集中视图（screens/completed_screen.dart）**：新增 `CompletedScreen` 页面；顶部提供返回键、标题与已完成数量副标题；支持范围过滤 Chip（当前看板 vs 全部看板，默认当前看板）；空数据时呈现友好空态图文；任务列表展示任务标题（带逐行删除线）、来源看板名称（跨看板或全部看板模式下展示）、来源象限（Q1–Q4 完整维度名及彩色圆点）；支持展开查看各子任务标题与完成状态；提供恢复勾选框与恢复图标按钮，点击触发任务恢复并弹出 SnackBar 提示；支持单任务安全永久删除，带二次确认弹窗，严格按 ID 作用，跨看板查看时不误删其他看板数据。
- **主界面入口接线（screens/matrix_screen.dart）**：在主界面头部操作栏新增“已完成”（`ValueKey('completed-btn')`）图标按钮（`Icons.task_alt`），点击无缝跳转至 `CompletedScreen(initialBoardId: store.activeBoardId)`。
- **中英日多语言扩充（l10n.dart）**：补齐 `completedTasks`、`noCompletedTasks`、`restoreTask`、`taskRestored`、`completedCount`、`deleteCompletedTask`、`confirmDeleteCompletedTask` 三语字典词条。
- **验证**：`D:\Dev_SDKs\Flutter_SDK\bin\flutter.bat test --no-pub` **144/144**（新增 3 项 Store 单元测试与 2 项 CompletedScreen 端到端 Widget 回归测试，全套 144 项测试 100% 通过）；`analyze --no-pub` 0 issues。未做 Android/Windows 实机，未改 React。

## 2026-09-12 · WP01-N Flutter 服务商预设与动态模型发现

- **服务商预设架构（ai_presets.dart & docs/AI_PROVIDER_PRESETS.md）**：建立主流服务商预设模型与配置（DeepSeek、火山引擎方舟/豆包、阿里云百炼 DashScope/通义千问、自定义 Custom）；遵循“只预设 Base URL 与必要协议元数据，不硬编码静态模型清单”原则，记录在新增规范文档中；支持针对特定服务商的智能首选模型算法（`pickPreferredModel`）。
- **模型数据与平滑迁移（models.dart）**：`AIConfig` 抽离 `provider` 服务商标识与通信协议 `protocol`；`fromJson` 完美向下兼容旧配置（旧 DeepSeek 配置自动归入 `deepseek` 预设，自定义端点归入 `custom`，火山/百炼链接精准识别），`toJson` 同步输出 `providerId` 与 `protocol`；测试与覆盖导入完美向前向后兼容。
- **动态模型发现与缓存服务（ai_service.dart）**：`AIService.fetchModels` 实现跨服务商安全模型发现；支持标准 `/models`、Anthropic `/v1/models` 解析；自动提取去重去空 `data[].id` 或 `models[].id`；状态码 401/403 映射为 `aiUnauthorized`，其他 HTTP 错误安全映射，不泄露响应体；基于 `${provider}|${baseUrl}|${apiKey}` 内存缓存，避免重复网络开销，支持 `forceRefresh` 与 `clearModelCache`；绑定 `AICancellation` 支持快速取消。
- **差异化思考参数适配（ai_service.dart）**：DeepSeek 原生专属 `thinking: {"type": "enabled"|"disabled"}` 控制参数精准绑定 DeepSeek 与自建代理；火山引擎与阿里云百炼等严格 OpenAI 兼容端点绝不附加 `thinking` 参数，彻底避免百炼等平台上 400 Bad Request 异常。
- **Key-only 快速配置交互与安全隔离（settings_screen.dart & l10n.dart）**：设置页新增服务商下拉选择；用户输入 API Key 失焦或提交后自动触发模型发现，严禁逐字符请求；模型列表动态展示并提供手动手填/推理接入点兜底；切换服务商立即取消旧请求、清空输入框 API Key 绝不跨端点泄露密钥并清除过期模型；高级 URL/协议配置针对预设折叠收敛、针对自定义完全展开；补充中英日三语多语言词条。
- **验证**：`D:\Dev_SDKs\Flutter_SDK\bin\flutter.bat test --no-pub` **139/139**（新增 4 项 dynamic discovery 与 provider adaptation 单元测试，2 项 SettingsScreen 端到端 Widget 回归测试，全套 139 项测试 100% 通过）；`analyze --no-pub` 0 issues。未做 Android/Windows 实机，未改 React。

## 2026-09-11 · WP02-N Flutter 一键清空当前任务板四个象限

- **看板菜单清空入口（matrix_screen.dart）**：主界面看板下拉菜单新增“清空此任务板”（`clearBoard`）操作项；当当前看板任务总数为 0 时，菜单项自动置灰禁用（`enabled: false`）；支持快捷呼起二次确认对话框。
- **确认弹窗与目标捕获（matrix_screen.dart）**：二次确认对话框标题为“清空任务板”（`clearBoardTitle`），正文明确提示目标看板名称与将被清空的任务总数（含已完成与隐藏任务，`clearBoardConfirm`）；在呼起弹窗时捕获目标 `boardId`，防止确认期间看板漂移误清其他看板；取消操作完全无害保留所有任务；确认操作执行单次原子清空并弹出 SnackBar（`boardCleared`）反馈。
- **原子状态更新与持久化（storage.dart）**：`Store.clearBoard(boardId)` 实现单次原子状态更新；一键删除目标看板下四个象限的所有任务（包括主任务及子任务，无论已完成或隐藏）；严格保留看板实体本身、其他看板及其任务、应用设置（`matrixflow-settings`）与 AI 配置（`matrixflow-config`）；清空后自动持久化到本地存储并触发通知；操作具备幂等性（空看板再次清空返回 0，无副作用）。
- **界面瞬态重置与在途 AI 结果作废**：清空操作同时重置多选模式（`_selecting = false`、清空选中集）、关闭活动任务详情抽屉/侧边栏（`_activeDetailTaskId = null`）以及象限聚焦状态（`_focusedQuadrant = null`）；引入 `_boardEpoch` 代数追踪机制，清空时自增看板代数；在途异步 AI 分析提交（`InputSheet`）检查代数，若目标看板已被清空则安全丢弃解析任务、提示友好错误并保留输入草稿，严防幽灵任务复活。
- **中英日多语言支持（l10n.dart）**：补充 `clear`、`clearBoard`、`clearBoardTitle`、`clearBoardConfirm`、`boardCleared`、`emptyBoard` 三语完整字典条目。
- **验证**：`D:\Dev_SDKs\Flutter_SDK\bin\flutter.bat test --no-pub` **133/133**（新增 1 项 Store 单元测试与 4 项针对空看板置灰禁用、取消保留任务、确认删除四象限/完成/隐藏/重置选择/跨看板隔离/重启保留、在途 AI 快照代数隔离防止复活的端到端回归测试）；`analyze --no-pub` 0 issues。未做 Android/Windows 实机，未改 React。

## 2026-09-11 · WP06-N Flutter 首次启动自动选择设备语言

- **系统设备语言解析（models.dart）**：新增 `resolveDeviceLanguage(Iterable<Locale>? locales)` 函数；在首次启动且无保存语言配置时，从 Android / Windows 系统语言优先列表优先匹配 `zh`、`ja` 与 `en`；`zh-CN`、`zh-TW`、`zh-HK`、`zh-Hans`、`zh-Hant` 等各中文区域及变体均映射至现有中文（`Language.zh`）；未支持的系统语言或空列表回退至 `Language.en`。
- **持久化与已有选择保护（storage.dart）**：`Store` 构造函数与 `init({List<Locale>? deviceLocales})` 支持注入设备语言（默认查询系统 `WidgetsBinding.instance.platformDispatcher.locales`）；仅在 `matrixflow-settings` 不存在或未配置有效语言时采用设备语言；若用户此前已明确选择语言（包括在中文设备上显式选用英文 `en`），读取时严格遵循用户已选值，决不覆盖篡改；首次无配置启动时初始默认看板名称（`defaultBoardName`）按系统语言自然生成（如中文系统为“我的任务”、日文系统为“マイタスク”）。
- **原生入口与测试注入（main.dart & helpers.dart）**：`MatrixFlowApp` 支持外部注入 `deviceLocales`；测试工具 `makeStore` 与 `setup` 支持自定义系统语言列表，无需 mock 整个底层引擎即可进行确定性多语言测试。
- **验证**：`D:\Dev_SDKs\Flutter_SDK\bin\flutter.bat test --no-pub` **128/128**（新增 7 项 models 单元测试与 7 项针对新装 zh/ja/en/不支持语言、明确旧档 en 保护、手动改语言跨重启保持、覆盖导入语言保留以及 `MatrixFlowApp` 注入的端到端回归测试）；`analyze --no-pub` 0 issues。未做 Android/Windows 实机，未改 React。

## 2026-09-11 · WP05-N Flutter 手动换象限置顶与普通拖动

- **跨象限显式移动置顶（storage.dart）**：在 `Store.moveTask` 与 `Store.updateTask` 中统一实现显式跨象限置顶规则；当任务跨象限移动后，自动插入到目标象限最前面（`_insertAtFrontOfQuadrant`），目标象限其他任务保持相对顺序；同象限操作不重排；其他象限任务和其他看板任务保持相对顺序；不篡改或伪造 `createdAt` 时间戳；保持截止日期自动升级原有规则不变；数据重启与导入导出后次序一致。
- **详情面板跨象限置顶（TaskDetailPanel）**：在详情面板修改象限 ChoiceChip 保存时，通过构建克隆副本调用 `store.updateTask`，准确感知象限变更并触发目标象限置顶。
- **Windows 鼠标右键移动菜单（TaskCard）**：`TaskCard` 支持鼠标右键/次级点击（`onSecondaryTapDown`）弹出原生“移动到”（`moveTo`）上下文菜单，清晰列出其余 3 个象限及其主题颜色圆点；点击即可触发移动、轻触觉反馈与短暂 SnackBar 反馈提示。
- **拖放与手势体验优化（QuadrantPane）**：保留普通轻滑滚动与 `LongPressDraggable` 长按拖动；增强拖拽悬停视觉高亮（主题色背景强调与半透明边框）；拖拽开始与结束触发轻触觉反馈（`HapticFeedback`）；目标象限若处于滚动状态，接收任务后平滑滚回顶部，确保新置顶的任务立即可见。
- **中英日多语言支持（l10n.dart）**：补充 `moveTo`（Move to / 移动到 / 移動先）与 `taskMoved`（Moved to {quadrant} / 已移动至 {quadrant} / {quadrant} に移動しました）三语字典条目。
- **验证**：`D:\Dev_SDKs\Flutter_SDK\bin\flutter.bat test --no-pub` **114/114**（在基线 110 基础上新增 4 项涵盖跨象限置顶、相对顺序与 createdAt 保持、详情面板换象限置顶、右键移动菜单与拖放已滚动目标回滚顶部的回归测试）；`analyze --no-pub` 0 issues。未做 Android/Windows 实机，未改 React。

## 2026-09-11 · WP22-B-N Flutter 子任务截止日期与独立编辑

- **子项独立截止日期与编辑表单（TaskDetailPanel）**：将详情面板中的子任务简单单行输入升级为完整编辑对话框（`_editSubtask`）；支持直接修改子任务标题、选择今天（`subtask-deadline-today`）、明天（`subtask-deadline-tomorrow`）、自定义系统日期选择（`subtask-deadline-custom`）以及清除日期（`subtask-deadline-clear`）；子任务列表行同步展示标题、日历小图标与格式化截止日期。
- **日期完全独立与超期温和提醒**：子任务截止日期与父任务截止日期完全独立，父任务日期的修改或清除不连带变更子任务日期，反之亦然；子任务截止日期晚于父任务时，展示非阻塞温和提醒（`subtaskDeadlineAfterParent`：“子任务截止日期晚于主任务”），不截断或篡改用户输入。
- **矩阵卡片角标与草稿保护联动**：在四象限矩阵展开子任务时，带有截止日期的子任务直观渲染 `_DeadlineChip` 胶囊角标展示剩余日历天数及今天/明天状态；详情面板草稿脏检测（`_isDirty`）完整对比子任务 JSON（包含日期变更），未保存退出时弹窗确认，防止误触丢弃修改。
- **验证**：`D:\Dev_SDKs\Flutter_SDK\bin\flutter.bat test --no-pub` **110/110**（新增 3 项针对子任务日期设置/清除/草稿跟踪、父子日期独立性与超期提醒、矩阵卡片子项日期徽章的回归测试）；`analyze --no-pub` 0 issues。未做 Android/Windows 实机，未调用真实模型，未改 React。

## 2026-09-11 · WP22-A-N Flutter 新建任务截止日期入口与快照隔离

- **新建任务截止日期选择器（InputSheet）**：普通添加与 AI 脑暴输入界面均提供直观的可选截止日期选择入口；支持今天（`deadline-today`）、明天（`deadline-tomorrow`）、自定义日历选择（`deadline-custom`，呼起系统 DatePicker）以及一键清除日期（`deadline-clear`）；未选择日期时不补造虚假截止日期，选择日期后以当天本地结束时刻（23:59:59）精准落库。
- **公共日期范围说明与子任务不继承**：选定截止日期时界面明确提示范围说明（`deadlineBatchScope`：“应用于主任务，子任务不默认继承”）；多行手动录入或 AI 分组生成时，公共日期完整赋予本次生成的主任务，而生成的子任务严格保持 `subtask.deadline == null`。
- **AI 提交时快照隔离与草稿保留**：AI 分类提交时原子捕获截止日期快照（`deadlineSnapshot`）、看板 ID 及输入文本；异步请求在途期间界面的后续改动不污染正在生成的任务结果；AI 执行失败或取消时完整保留用户输入草稿及选定的截止日期，任务落库成功后自动清空草稿与日期状态。
- **验证**：`D:\Dev_SDKs\Flutter_SDK\bin\flutter.bat test --no-pub` **107/107**（新增 3 项针对新建快捷日期、子任务不继承、AI 失败保留草稿的回归测试）；`analyze --no-pub` 0 issues。未做 Android/Windows 实机，未调用真实模型，未改 React。

## 2026-09-11 · WP12-S-N Flutter 本地搜索与多维筛选先行

- **本地查询模块（task_query.dart）**：新增纯 Dart 任务搜索与过滤模块，提供中英日大小写不敏感关键词匹配；支持父任务标题与子任务标题深度搜索；支持本地日历边界日期计算（今天、本周周一到下周一、本月1号到下月1号、逾期未完成、无日期）；1,000 条合成任务检索响应低于 50ms；按 ID 去重，不依赖后端，不预造 tags/notes 字段。
- **搜索与筛选界面（SearchScreen）**：新增 `screens/search_screen.dart`，AppBar 增加搜索入口按钮（`search-btn`）；提供当前看板与全部看板（`TaskScopeFilter`）切换、四象限单选/全选、完成状态（全部/未完成/已完成）以及日期范围过滤芯片；搜索命中子任务时清晰展示 `看板名 / 父任务标题` 面包屑路径与象限指示；支持就地切换完成状态并实时刷新；针对跨看板任务提供“前往任务板”（`goToBoard`）显式切换动作，常规退出安全保留主界面看板、视图与滚动状态。
- **详情面板定位高亮联动**：`TaskDetailPanel` 与 `showTaskDetailSheet` 增加 `highlightSubtaskId`，从搜索结果点击命中子项直达父任务详情并自动展开高亮对应子项；宽屏桌面支持同屏右侧详情侧边栏。
- **验证**：`D:\Dev_SDKs\Flutter_SDK\bin\flutter.bat test --no-pub` **104/104**（新增 10 项 task_query 单元测试与 4 项 search_screen 回归测试）；`analyze --no-pub` 0 issues。未做 Android/Windows 实机，未调用真实模型，未改 React。

## 2026-09-11 · WP23-N Flutter 单象限聚焦与下方收起卡片

- **单象限聚焦视图（QuadrantFocusView）**：新增 `quadrant_focus_view.dart`，用户点击四象限标题（或全屏图标）进入单象限聚焦模式；主工作区全宽呈现选中象限任务列表，支持完整的任务完成、展开、多选与编辑交互。
- **下方三象限收起卡片与直接切换**：未聚焦的其余三个象限按原始数字顺序在下方以精简卡片同屏展示，显示完整维度名称、对应象限主题色指示点以及任务计数（即使空象限也保留展示为 0）；点击任意收起卡片立即平滑切换主聚焦象限；下方卡片支持作为拖拽目标（DragTarget），拖动任务到下方卡片直接移动象限。
- **返回恢复矩阵与缓存保护**：主 AppBar 呈现直观返回按钮（`focus-back-btn`），点击或按系统返回键（PopScope）、或点击聚焦象限头部均可退出聚焦并恢复四象限十字矩阵及原始滚动位置；切换看板时自动重置聚焦状态并清理会话滚动缓存；卡片置于矩阵区域内部底部，不与底部安全区新增按钮（FAB）重合或遮挡。
- **验证**：`D:\Dev_SDKs\Flutter_SDK\bin\flutter.bat test --no-pub` **90/90**（涵盖进入聚焦视图、三张收起卡片按序排列、卡片点击切换聚焦、返回按钮与头部点击双重恢复矩阵、聚焦内任务勾选/编辑/隐藏联动、看板切换自动重置退出等）；`analyze --no-pub` 0 issues。未做 Android/Windows 实机，未调用真实模型，未改 React。

## 2026-09-11 · WP04-N Flutter 任务详情编辑、多行输入与弹层一致性

- **统一任务详情编辑面板（TaskDetailPanel）**：将分散的编辑逻辑集中为统一的 `TaskDetailPanel`。标题支持 1–5 行自适应多行输入，回车换行，Ctrl+Enter / ⌘+Enter 快捷键保存；提供完整四象限完整名称 ChoiceChip 单选、截止日期选择与清除、长期任务切换、直接触发 AI 智能拆解抽屉。
- **子任务就地完整管理与联动**：详情面板内直观展示子任务进度（已完成/总数），支持单行添加新子任务、就地点击重命名、快捷删除以及复选框切换完成状态；保存时与 Store 的 `autoCompleteParent` 设置双向自动级联。
- **自适应响应式布局**：宽屏桌面（宽度 ≥ 900dp）以 340dp 侧边栏（Right Sidebar）同屏展示，完全不遮挡四象限十字矩阵；窄屏移动端（宽度 < 900dp）以可拖拽底部半屏抽屉（Modal Bottom Sheet）呈现，界面在窗口动态缩放跨越 900dp 阈值时自动平滑转换。
- **草稿保护与弹层一致性**：点击遮罩/关闭按钮时对比初始草稿，无改动直接静默退出；存在未保存修改时弹出二次确认对话框（`discardChangesTitle` / `discardChangesConfirm`），防止意外丢失；面板内空白处点击仅收起软键盘不退出面板；顶部常驻保存按钮防止软键盘遮挡；删除任务带二次确认并防止已删除任务被保存复活。
- **验证**：`D:\Dev_SDKs\Flutter_SDK\bin\flutter.bat test --no-pub` **86/86**（涵盖多行输入/超长折行/快捷键保存、子任务 CRUD 与父级级联、草稿未修改静默关闭与修改确认丢弃、宽屏侧边栏同屏与窄屏抽屉转换、删除任务防复活、MF23 空行手动录入测试）；`analyze --no-pub` 0 issues。未做 Android/Windows 实机，未调用真实模型，未改 React。

## 2026-09-11 · WP03-N Flutter 十字无框矩阵与紧凑任务行

- **十字无框矩阵**：去除象限圆角外框（`QuadrantPane`），仅保留悬停/拖放局部浅色高亮；矩阵中央由 1px 细线构成横竖十字分割线，四象限独立滚动；任务行彻底去除 `Card` 白底、圆角与阴影，采用无框轻量容器；去除子任务左侧竖线。
- **紧凑任务行与首行对齐**：完成方框（约 20–22 dp，热区 48×48 dp）与正文标题首行精确对齐；正文 16sp/1.4 行高，字重 500，矩阵内最多显示 3 行；普通态点击正文打开现有任务编辑面板（`showTaskEditSheet`），复选框仅切换完成，箭头仅展开/收起，互不冒泡；任务行移除常驻编辑/删除/添加子项操作行，子项展开后保留子项复选框与标题。
- **安全区工具栏与多选编辑**：新增待办按钮（`FloatingActionButton.extended`）与批量工具栏移至矩阵外底部安全区，杜绝遮盖 Q4 底部任务；多选模式下仅选 1 项时工具栏提供「编辑任务」按钮，选 2 项及以上提供「编组」按钮，支持取消退出多选。为 WP23 保留象限标题点击回调（`onQuadrantTap`），未添加未接线的虚假按钮。
- **验证**：`D:\Dev_SDKs\Flutter_SDK\bin\flutter.bat test --no-pub` **80/80**（涵盖十字分割线、无白底卡片、多选单选编辑按钮、复选框点击不冒泡编辑、子项去竖线及 320px 1.5x 缩放）；`analyze --no-pub` 0 issues。未做 Android/Windows 实机，未改 React。

## 2026-09-09 · WP21-N Flutter 四象限完整维度名与 AI 分类描述

- **界面名称**：矩阵标题与编辑象限选项统一为 Q1 紧急且重要 / Q2 不紧急但重要 / Q3 紧急但不重要 / Q4 不紧急也不重要；英文、日文表达同一对维度。不再用马上做/计划做/授权做/不要做。窄屏标题最多两行，不省略“不”。内部 `qDo` 等枚举与 wire=1/2/3/4、象限位置未改。
- **分类提示词**：去掉 `(Do First)/(Schedule)/(Delegate)/(Don't Do/Delete)`；保留紧急/重要定义、JSON/wire 契约、三协议、思考、分组/拆解与无说教。生活/娱乐任务不先验为不值得做，Q4 不是删除指令。
- **验证**：`D:\Dev_SDKs\Flutter_SDK\bin\flutter.bat test --no-pub` **77/77**；`analyze --no-pub` 0 issues。未做 Android/Windows 实机，未调用真实模型，未改 React。

## 2026-09-09 · WP20-N Flutter 完成/多选分离、独立子项展开、逐行删除线

- **完成方框只表示 completed**：原生 `TaskCard` 不再用 `selecting ? selected : completed`。多选改为行高亮、「已选」标记和「多选任务 · 已选 N 项」；切多选/退出只改会话选择，不改完成数据。父子完成级联沿用 `setParentCompleted`。
- **子项独立展开**：删除「非 selecting 才渲染子项」门禁；显示「子任务 已完成数/总数」入口，按 `boardId/taskId` 保存本会话展开状态，默认收起，切模式/切板/重排按 ID 保留；新增子项自动展开该父任务。
- **逐行删除线**：`StrikeThrough` 改为文字自身 `TextDecoration.lineThrough`，不再在文本块垂直中线叠一条横条。
- **验证**：`D:\Dev_SDKs\Flutter_SDK\bin\flutter.bat test --no-pub` **74/74**；`analyze --no-pub` 0 issues。未做 Android/Windows 实机，未改 Web（WP20-W）。

## 2026-09-08 · 待办说教评语移除、设置可见性与文案精简、设置自动化与 4 组模型思考模式真机实测闭环

- **AI 提示词与卡片视觉纯净化**：
  - 彻底剥离任务卡片（Web 端 `TaskCard.tsx` 与原生端 `task_card.dart`）上的 `reasoning` 理由展示，杜绝冒犯用户的说教、道德批评或评价性言论。
  - 调整 Web 与原生端的 AI 系统提示词（`services/aiService.ts` 与 `matrixflow-native/lib/ai_service.dart`）：明确严禁输出观点、建议、说教或建议删除任务的言论，AI 输出模型纯粹归纳任务标题与必要子任务，任务卡片恢复极简清爽。
- **设置界面占位符与文案打磨**：
  - 原生端与 Web 端 Base URL、API 密钥与模型名称输入框均配置常驻浮动标签（`FloatingLabelBehavior.always`）与默认占位符，彻底解决默认占位不显示的问题。
  - 精简思考模式副标题说明文案，移除冗余的括号举例。
- **设置自动化 4 项核心功能实机（Redmi K70）全量实测**：
  - ① **AI 自动拆解隐藏拆解提示**（`suppressLongTermPrompt`）：关闭时弹出确认底部抽屉，开启后静默直接入象限，实测通过。
  - ② **AI 自动分组隐藏分组提示**（`suppressGroupPrompt`）：批量输入购物项等同类任务时，直接合并生成分类父任务与子项，无需二次弹窗确认，实测通过。
  - ③ **父任务自动完成**（`autoCompleteParent`）：子任务全部勾选时父任务自动勾选打叉；反选任意子任务时父任务自动恢复未完成状态，双向联动实测通过。
  - ④ **导出与导入待办**（`exportData` / `importData`）：完美适配 Android 16 SAF 系统文件选择器，生成标准 `matrixflow_backup_...json` 备份并支持完整还原。
- **4 组模型与思考模式组合实机（Redmi K70）对比实测**：
  - 测试用例覆盖长期/短期/重要/不重要/紧急/不紧急等多维复杂任务集合。
  - 组合 1：`deepseek-v4-pro` + 开启思考（耗时 ~12s，分类命中率 100%，卡片干净无说教）。
  - 组合 2：`deepseek-v4-pro` + 关闭思考（耗时 ~6s，分类命中率 100%，卡片干净无说教）。
  - 组合 3：`deepseek-v4-flash` + 开启思考（耗时 ~8s，分类命中率 100%，卡片干净无说教）。
  - 组合 4：`deepseek-v4-flash` + 关闭思考（耗时 ~3s，分类命中率 100%，响应最快且分类极准）。
- **自动化验证**：66 项 Flutter 单元/组件测试全部通过，`flutter analyze` 0 issues，Web Vite 构建成功（290.6 kB），TypeScript 0 错误。

## 2026-09-07 · Web 与 Native 双端新增 AI 思考模式控制、DeepSeek 默认配置与 Android 真机全流程验证闭环

- **AI 思考模式支持**：
  - Web 与 Flutter 原生端均增加「思考模式」开关（`enableThinking`），默认关闭，支持持久化。
  - 三协议完整适配：OpenAI 兼容协议支持 `thinking: {type: 'enabled'/'disabled'}`；OpenAI Responses 协议支持 `reasoning: {effort: 'high'/'none'}`；Anthropic Messages 协议支持 `thinking: {type: 'disabled'}` 或 `output_config: {effort: 'high'}`。
- **默认 AI 厂商与模型优化**：
  - 默认 Base URL 切换为 `https://api.deepseek.com`，默认占位与模型切换为 `deepseek-v4-flash`。
  - Web 与 Native 双端设置界面均加入高亮建议提示卡片：「建议：推荐使用 deepseek-v4-flash 并关闭思考模式，响应最快且分类准确率最高。」，三语同步适配。
- **Android 实机端到端全量验证（Redmi K70 - Android 16 / HyperOS）**：
  - 通过 ADB 在真实手机上安装 `app-release.apk` 并执行自动化 UI 与功能复测。
  - 涵盖 T01~T10 全部 10 项核心测试：安装与冷启动、设置默认配置、思考开关与提示卡片、三语切换与界面排版、DeepSeek 真实 API 连通性测试（绿色 SnackBar 提示）、手动任务与子任务录入流转、任务勾选完成/划线/隐藏/删除二次确认、8 个真实任务 AI 批量四象限分类（命中率 100%）、长期任务识别与多步子任务拆解、多看板创建与隔离切换。
  - 66 项 Flutter 单元/组件测试通过，静态分析 0 警告，Web 构建 290.7 kB 通过。

## 2026-09-07 · 解决 Android Release 构建 integration_test 插件注册编译阻塞 (B01)

- **定位根因**：Flutter CLI (`flutter_command.dart`) 在执行 `flutter build apk --release --no-pub` 时因 `--no-pub` 抑制了 `regeneratePlatformSpecificTooling`，残留 debug 阶段由 `pub get` / `test` 生成的 `GeneratedPluginRegistrant.java`（包含 `IntegrationTestPlugin`），而 Gradle 的 `flutter.groovy` 在 release 构建中剥离了 `dev_dependencies`，导致 Java 编译找不到类。
- **最小安全修复**：在 `matrixflow-native/android/app/build.gradle.kts` 配置 Gradle 预构建任务 `cleanDevPluginsFromReleaseRegistrant`，在 release 编译前自动清理 `GeneratedPluginRegistrant.java` 中的测试插件注册，不手改生成文件、不把测试依赖移入生产依赖、不修改全局 SDK。
- **发布验证**：Android release APK 成功构建（`app-release.apk` 22.8MB，`--release` 与 `--release --no-pub` 均通过）；Android debug 构建通过；64 项测试通过，`flutter analyze` 0 issues。正式关闭 B01。

## 2026-09-07 · 原生端深度 Bug 审查与集中修复

- 归纳并处理 29 类问题：启动容错、导入原子校验/去重、编组保留子任务、父子完成状态、活动板恢复、唯一 id、截止日期更新、Android 文件导出和 release 网络权限。
- 修复键盘双重 inset、窄屏溢出、拖拽与滚动冲突、未接通的批量选择、弹层返回误退出、控制器释放、桌面连续 AI 提交、跨板异步写入；补充三语 Material 本地化。
- AI 请求增加可取消传输与总超时，区分编组和拆解，拒绝不完整结果并保留输入；规范 Anthropic 地址和 JSON 对象提示词。
- 自动化测试由 20 增至 64，全部通过；`flutter analyze` 0 issues。Android debug、Windows release 构建通过。
- Android release 仍因 integration_test 插件注册不一致编译失败；实机端到端待执行。详见 [深度审查报告](NATIVE_BUG_REVIEW_2026-09-07.md)。
- Session 收尾：同步报告与交接并提交本轮成果；下一轮限定为定位并尝试解决 B01，保留已通过的回归验证和 Windows 构建结果。

## 2026-09-07 · 原生跨平台版集成与文档体系全量对齐

### 新增

- **MatrixFlow Native（Flutter 原生跨平台版）正式集成至主仓库**：
  - 采用 Flutter 3 + Dart 开发，Impeller / Skia 自绘引擎，无需 WebView，提供丝滑的原生系统交互与动效
  - 同一套 Dart 代码直接编译为 **Android APK** 与 **Windows 原生桌面应用**
  - **数据完全互通**：同构数据模型（`models.dart`），与 Web 端共享 `ExportData` v1 格式与 SharedPreferences 本地持久化（键名对齐 `matrixflow-*`），支持去重合并
  - **三协议 AI 客户端**：原生 HTTP 实现 OpenAI Compatible、OpenAI Responses 与 Anthropic Messages 三协议，多级 JSON 容错剥离与探活检测
  - **工程化质量保障**：配备 20 项完备的单元与集成测试（`flutter test`），并通过 `flutter analyze` 零告警静态检查

### 改进

- **文档体系全面核验与对齐**：
  - 修复 `matrixflow-native/README.md` 指向 Web 版的失效相对路径
  - 更新 `README.md`、`AGENTS.md`、`docs/ARCHITECTURE.md` 与 `docs/DEVELOPMENT.md`，完整记录双轨（Web / Native）架构
  - 纠正 `ARCHITECTURE.md` 中历史残留的「AI 四协议」说法为三协议，更新 App.tsx 实际行数（1672 行）
  - 从技术债清单移除已消除的 Rollup 500 KB 分包警告，记录当前 Web 构建产物实际体积为 288.5 KB（gzip 87 KB）
  - `DEVELOPMENT.md` 补齐 Flutter 开发、构建、测试命令与本机 SDK 路径说明，修正 subst 映射路径

## 2026-09-06（二）· 移除 Gemini 协议

### 移除

- **按用户决定移除 Gemini 调用协议**：删除 `@google/genai` 依赖与构建期密钥注入（`vite.config.ts` 的 `define`），AI 配置只剩三种自定义协议，项目不再依赖任何环境变量或 `.env` 文件
- 旧配置中 `provider: 'gemini'` 或 `'custom'` 在加载时自动迁移为 OpenAI 兼容协议，默认提供商改为 OpenAI 兼容

### 改进

- 构建产物从约 507 KB 降至 **288 KB**（gzip 121 KB → 87 KB），Rollup 分包警告随之消失
- tsconfig 补充 exclude（src-tauri / android / dist），避免类型检查扫到打包壳的生成文件

## 2026-09-06 · AI 多协议与跨端打包

### 新增

- **AI 多协议调用**：除 Gemini 外，新增三种自定义调用方式，统一「API 地址 + 模型名 + 密钥」三要素配置：
  - **OpenAI Compatible**（`{baseUrl}/chat/completions`，适用 DeepSeek、Moonshot、SiliconFlow 等兼容服务商）
  - **OpenAI Responses**（`{baseUrl}/responses` 新版接口）
  - **Anthropic Messages**（`{baseUrl}/v1/messages`，`x-api-key` + `anthropic-version` 头）
  - 旧「Custom API」配置自动迁移为 OpenAI Compatible，无需手动处理
- **按协议探测的测试连接**：OpenAI 系走 `GET /models`，Anthropic 走 `GET /v1/models`（代理不支持时自动降级为 1-token 最小请求探活）
- **桌面应用（Windows）**：采用 Tauri v2 打包（WebView2 内核，产物含 NSIS 安装器与便携版），源码在 `src-tauri/`，构建命令 `npm run tauri build`
- **安卓应用**：采用 Capacitor 封装（WebView 加载同一份 `dist/`），源码在 `android/`，构建命令见 README；debug APK 可直接安装

### 改进

- JSON 解析兜底增强：自动剥离 markdown 代码围栏、兼容单对象响应；象限字段兼容 "Q1" 字符串（DeepSeek 实测返回字符串而非整数）
- 协议参考实现来自开源项目（NextChat 的 anthropic/deepseek 适配器等），地址规范化：无协议前缀自动补 https、去除尾部斜杠

## 2026-09-03 · 交互与健壮性专项修复

依据全面审核报告（26 项发现，双重冷复核 + 浏览器实测）完成的集中修复。

### 修复（高优先级）

- **合并导入不再产生重复任务**：导入去重按任务 id 过滤，并丢弃指向不存在任务板的孤儿任务（此前同一备份导入两次会产生连 id 都相同的重复任务，引发 React key 冲突）
- **移动端可以更改任务象限**：编辑模态新增象限选择器（此前移动端既无法拖拽、编辑里也无象限字段，完全没有改分类的途径）
- **AI 请求 30 秒超时**：Gemini 与自定义 API 全部请求经 AbortController 中止，错误提示「请求超时」；单任务拆解弹窗改为可关闭，不再可能被挂起请求锁死界面
- **本地数据损坏不再白屏**：localStorage 读取改为安全解析（损坏时重置该项并提示），新增 ErrorBoundary 兜底（附「清除本地数据并重载」逃生入口）
- **删除全部任务后刷新不再复活旧数据**：持久化改为 hydration 完成后生效，空列表也会写回

### 修复（交互）

- 弹窗支持 **Esc / 点击遮罩关闭**，补齐 `role="dialog"`、`aria-modal`、关闭按钮 aria-label 与焦点圈（focus trap）
- 提交快捷键兼容 **Ctrl（Windows / Linux）与 ⌘（macOS）**，并在输入区显示提示（此前只识别 ⌘，Windows 下快捷键完全无效）
- **7 处原生 alert 全部替换为 Toast 通知**（自动消失、可手动关闭、成功/错误两种样式）
- 移动端任务标题不再被动作按钮挤成一字一行（标题保底 120px，操作按钮换行）
- 子任务的编辑/删除按钮改为常显（此前仅悬停可见，触屏不可达）
- 移动端多行文本手动添加按行拆分为多条任务（与 AI 模式行为一致，此前整段文本含换行符存为一条标题）
- 任务卡不再静默截断子任务（移除 max-h-96 限制）
- **AI 分类理由（reasoning）现在会显示**在任务标题下方（此前字段被完全丢弃）
- 覆盖导入前增加**二次确认弹窗**（复用现有确认系统）
- 新增「**隐藏已完成**」开关（设置项 `hideCompleted`，含导入白名单同步）

### 修复（打磨）

- 移除 viewport 禁止缩放（`user-scalable=no`），恢复用户缩放能力
- 滚动条不再全局隐藏：`custom-scrollbar` 类有了真实样式（6 处滚动区域恢复滚动指示），并移除该死类名的历史遗留
- 可访问性：设置齿轮、移动端 FAB、主题色圆钮、开关滑块、自定义 API 输入框补齐 aria 标注；`<html lang>` 随界面语言实时切换
- 清理 AI Studio 遗留：删除指向 aistudiocdn 的休眠 importmap 与不存在的 `/index.css` 引用（构建警告消除）
- 任务卡左侧增加象限颜色条、象限容器顶部增加彩色细条（此前四象限视觉上完全同色）；启用了 TaskCard 一直未使用的 `colors` 属性
- 截止日期按**本地时区**解析（此前按 UTC 午夜解析，东八区偏差 8 小时）
- 设置页新增 AI「**测试连接**」（自定义 API 走 `{baseUrl}/models` 探测；Gemini 校验注入密钥存在性）
- 拖拽移动任务增加目标象限高亮反馈
- Quadrant / TaskCard 组件 `React.memo` 化，App 处理函数 `useCallback` 化，输入打字不再全树重渲染
- 三语硬编码清理：导入预览 ON/OFF、天数单位 `d`、删除按钮文案键误用等；英文截止日期显示 `3days` → `3d`
- **补装缺失的 `@types/react` / `@types/react-dom`**：此前 `tsc --noEmit` 是在无 React 类型下通过的空验证，现在类型检查真实生效（计入 devDependencies）

### 验证

`npx tsc --noEmit`（真实类型）通过；`npm run build` 通过；浏览器实测通过：多行拆分、象限改分类、Esc/遮罩关窗、Toast 错误反馈与自动消失、隐藏已完成、删空刷新不复活、损坏数据自愈、中文切换联动 `html lang`、移动端标题布局（14px 竖排 → 126px 正常换行）。

## 2025-11-25 · 任务编辑体验打磨

`0e2d51f` **feat(任务编辑): 重构任务编辑功能并添加动画效果**

- 新增专用编辑按钮（铅笔图标）与滑动动画
- 编辑模态框支持批量操作与行内编辑（子任务 / 父任务标题）
- 输入区域支持动态高度调整
- 优化确认模态框动画与状态管理

## 2025-11-24 · 数据安全与代码结构

### 新增

`7a8e0e2` **feat(数据备份): 添加数据导入导出功能及相关UI组件**

- 数据导出为 JSON 备份文件（`ExportData` v1 格式，含任务板、任务、设置与 AI 配置）
- 数据导入：支持「合并」与「覆盖」两种模式，导入前可逐项勾选预览

`63519a2` **feat: 添加自动完成父任务功能及UI改进**

- 新增设置项：全部子任务完成时自动勾选父任务
- 删除操作增加确认模态框；模态框增加淡出 / 滑出动画
- 任务卡片复选框样式与完成动画改进；输入区底部添加版权信息

### 变更

`50c70cc` **refactor: 将组件拆分为独立文件并优化代码结构**

- 将约 1400 行的单文件 App.tsx 拆分为 `components/` 与 `components/ui/` 模块（Quadrant、TaskCard、InputArea、SettingsControls、ImportReview、Modal、Checkbox、ToggleSwitch），功能不变

## 2025-11-22 · 核心功能日

### 新增

`d986fdd` **feat: 初始化 MatrixFlow AI 项目，实现任务管理矩阵和AI智能分类功能**

- 艾森豪威尔四象限矩阵：任务卡片拖拽重分类
- AI 智能分类：自动判定象限并给出理由，支持单条与批量输入
- 多语言界面（英文 / 简体中文 / 日文）
- 主题切换（亮 / 暗 / 跟随系统）与 5 种主题配色
- 多任务板管理
- AI 服务双提供商：Gemini 与 OpenAI 兼容自定义 API
- 响应式设计与移动端适配

`52a7de2` **feat(任务管理): 添加子任务和分组功能**

- 子任务（SubTask）类型与任务卡展开管理
- AI 任务分组：多条同类输入合并为一个任务（如「买牛奶 + 买鸡蛋 → 购物」）
- AI 批量分解：对长期任务批量生成子任务

`7a93d1b` **feat: 新增AI自动拆解功能及相关设置选项**

- 新增设置项：AI 自动拆解（autoDecomposeAI）、抑制分组确认提示（suppressGroupPrompt）、抑制长期任务提示（suppressLongTermPrompt）
- 长期任务标记（FlagIcon）与状态切换
- 象限一键清空功能
- AI 服务支持「即时拆解」：分类阶段直接为长期任务生成子任务
