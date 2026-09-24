# 架构

> **2026-09-24 当前覆盖：** OS01–OS14 和 OS24 已集成 main。OS24 固定 Flutter 3.32.8 stable / Dart 3.8.1（`D:\Dev_SDKs\Flutter_3.32.8`），原 `D:\Dev_SDKs\Flutter_SDK` 保留回退。OS12 日期/提醒、OS13 焦点和 OS14 桌面运行态见下方章节；OS10/11 真实厂商调用与双端实机仍未测。旧 Web/v1 与旧包状态是历史说明。继续暂停 WP10/WP29/UI 实验。

> 2026-09-20 更新：UX01–07 已实现。列表聚焦退出交叉（R1–R5）及淡出中切换视图卡住（S1）已修。自动化 359 项通过，双端实机未验；下一包 UX08（全路径验收）。下文旧包进度为历史，现状以 HANDOFF 与 UX 返修计划为准。

## 当前 Flutter 日期与提醒（OS12）

`lib/calendar_dates.dart` 是新建任务、父详情和子项日期/提醒选择器的共同窗口。截止日期可选本地日历日 1900-01-01 至 2200-12-31。提醒可选本地今天至同一月日的五年后；2 月 29 日加五年且目标年没有该日时，落到该月最后一天。对话框初值优先用已有提醒的日历日，否则用截止日期，再否则用今天，并钳进窗口。这个初值只供选择器打开，取消或未确认时不写回任务。因此导入或原有的远期 deadline，即使晚于提醒上界或晚于 2200-12-31，仍保持原来的毫秒值。

“明天”和筛选里的“本周”按本地年月日计算。本周是包含今天的周一至周日，周日 23:59:59 仍属于本周，下周一不属于本周。计算不把一天当成固定 24 小时。`reminderAt` 继续是一次性绝对时刻，设置提醒不会生成重复规则，也不会改写未改动的 deadline。

## 当前 Flutter Windows shell（OS14）

`DesktopShellService` 通过 `DesktopShellHost` 与 Windows host 隔离；`applySettings` 返回托盘、热键、期望关闭策略和实际生效状态。启动、设置页修改和设置导入后都应用当前设置，连续修改按代际串行，旧异步结果不会公布。托盘初始化失败时 `isTrayInitialized=false`，关闭按钮不隐藏窗口；隐藏系统调用失败也保留可见状态。热键失败或冲突及注销失败向设置页报告并提供重试，不能把期望配置当成已注册状态。Windows runner 直接检查 `RegisterHotKey` 返回值，窗口显示/隐藏通过 runner 通道并回读可见性。Android 不调用桌面 host。独立 Windows Debug 测试窗口验证初始化、隐藏、托盘回调召回、保留快捷键冲突和重试；Windows Release 已编译，正式安装及人工鼠标操作未测。真正退出的幂等性与保存协调仍由 OS15 处理。

## 当前 Flutter 密钥边界（OS08/OS09）

`Store` 的普通配置快照、两个 OS06 保存槽和旧 `matrixflow-config` 镜像省略 `customApiKey`。启动时先读 `CredentialStore`；若只有旧明文，则写入系统存储并读回后清理所有旧副本。失败保持恢复来源、显示重试，并暂停普通保存。`SystemCredentialStore` 使用 `flutter_secure_storage 10.3.4`：Android Keystore 包装加密密钥和 AES-GCM；Windows Credential Manager 保存加密密钥，应用目录保存 AES-GCM 文件。Android 禁用应用自动备份/设备转移以避免恢复密文但缺设备密钥；手动备份可跨设备导入。Windows 系统凭据与加密文件的单独复制不作为恢复契约。`ExportData` 默认省略 key，显式包含从凭据接口读取；旧 v1/v2 含 key 文件可读，覆盖时默认保留本机 key，明确选择才替换。OS05 恢复专用副本若在旧版本生成仍可能含明文；用户须自行妥善处理。

## 当前 Flutter 模型发现与协议能力（OS10/OS11）

模型发现的缓存身份是 provider、规范化 base URL、protocol 和 credential。规范化会小写 scheme/host、去掉默认端口和末尾斜杠，并拒绝带 query、fragment 或 userinfo 的地址。设置页与 `AIService.fetchModels` 使用同一身份：协议、URL 或密钥变化会立刻清掉已显示的模型列表并取消旧请求，迟到结果不写入缓存；相同身份复用缓存，刷新按钮绕过缓存。失败响应不进缓存。诊断文本只包含 `credential:redacted`。

三协议仍是 OpenAI Compatible、OpenAI Responses、Anthropic Messages。普通兼容请求默认只有 `model`、`messages` 和需要 JSON 时的 `response_format`。DeepSeek 的 `thinking.type` 只发给 DeepSeek 接口或 DeepSeek 模型 id；火山引擎和百炼不附带该字段。Responses 的 `reasoning.effort` 只在 o1/o3/o4 与 gpt-5 标识上发送。Anthropic 按模型 id 选择手动 `budget_tokens` 或自适应 `thinking.type=adaptive` 与 `output_config.effort`；始终思考且拒绝 disabled 的模型不会收到关闭字段。设置页在能力不足时显示可操作说明。

连接测试分成三行：端点与鉴权、模型发现、所选模型生成。发现成功不会写成生成可用。生成测试会先说明可能计费，只有用户确认后才发送一次短请求；应用启动和输入失焦不会生成。分类、分组、拆解、无说教和取消契约保持不变。本轮只用合成配置和 HTTP mock，没有真实 API key，也没有 Android/Windows 实机或真实厂商验收。

## Flutter 焦点与退场（OS13）

`ExitingRow` 仍保留任务卡元素供划线和收起动画使用，但退场时同时排除命中、语义和焦点。`QuadrantTransitionLayout` 的四个 `QuadrantPane` 仍以稳定键常驻；动画期间或透明度低于半数时，任务象限排除焦点，下方卡片在可见后重新可聚焦。焦点从被排除子树移到 Flutter 外层作用域；任务行恢复或象限再次可见时只恢复键盘遍历资格，不自动夺回旧焦点。此规则不重建象限，也不重置滚动位置或编辑草稿。列表聚焦淡出仍允许现有 R1/R2 交互，完成退场的任务快照本身始终不可操作。

## 当前 Flutter AI 配置（OS03，历史基线）

`lib/ai_presets.dart` 保存服务商 URL、协议与模型缺省；DeepSeek 新安装默认 `deepseek-flash`。`AIConfig.fromJson` 对旧配置只用解析后的准确 host 推断提供商；未知 `providerId` 回退 custom 并保留 URL/模型。只有明确指向 DeepSeek 预设、其 OpenAI 协议和准确 DeepSeek host 的旧 `deepseek-v4-flash` 默认名会迁移；自定义模型不改写。空模型仅在匹配已知预设协议时填厂商缺省，其他配置在发请求前报告缺少模型。三协议仍通过同一配置传递所选模型，密钥在 OS09 后由 `CredentialStore` 单独保存；旧 `matrixflow-config` 仅用于升级迁移。OS03 使用合成配置与 mock HTTP 验证，未做真实服务或双端设备调用。

## 当前 Flutter 备份（OS04）

Flutter 使用 `ExportData` v2 JSON 默认导出，并通过 `DataMigrator` 读取 v1/v2；备份结构及 OS07 已实施的导入语义见 [BACKUP_FORMAT.md](BACKUP_FORMAT.md)。当前默认导出省略 `aiConfig.customApiKey`；每次显式选择包含时告知 JSON 为明文。备份交换格式与 SharedPreferences 的保存协议分开演进。

## 当前 Flutter 启动恢复（OS05）

`Store.init` 为本机核心键和 UI 元数据键记录缺失、正常、归一化或损坏状态。若任一源损坏（包括局部记录无法解析和错误的 onboarding primitive），启动不再自动写回任何键；主界面前的恢复页只显示受影响类别，可将所有原始本机值保存为恢复专用 JSON（可能包含 API 密钥），或经二次确认丢弃损坏值后继续。取消和重启保留源值。该恢复文件不是 `ExportData`，不能通过普通导入使用。正常缺省/可迁移数据仍按既有加载逻辑处理。OS06 随后加入批次提交；OS05 本身不保证掉电原子性。

## 当前 Flutter 保存与导入（OS06/OS07）

`lib/save_protocol.dart` 将任务、板、AI 配置、设置、活跃板与 onboarding 状态合成带 revision/Adler-32 校验的完整快照，在两个 SharedPreferences 槽之间轮换，以指针为提交点。启动优先读取指针所指快照；旧键继续作为兼容镜像。提交前失败重启读取旧批次，提交后镜像失败重启读取新批次；指针或已提交槽损坏交 OS05 恢复页。`Store.flush` 返回 `SaveResult`，失败横幅可重试，成功清除错误。当前快照与镜像省略 API 密钥；升级前的旧槽须完成 OS09 迁移清理。SharedPreferences 返回成功并不等于抗强杀/掉电持久化，未验证平台文件系统或多实例竞争。

`lib/import_preflight.dart` 统一设置页的 v1/v2 预检，文件最大 4 MiB、嵌套深度 12、最多 500 板/10000 任务/50000 子项。板/任务在各自域唯一，子项在同父任务唯一；相同记录可跳过，内容冲突拒绝或阻断；孤儿、空备份及缺省修复有预检结果。设置页预览新增/跳过/冲突/修复/警告与覆盖影响，确认后 `Store.applyImport` 先提交完整保存批次，再改内存并重排提醒；失败保留旧库。现存同步 `Store.importData` 只供内部兼容调用，虽共用预检仍是先更新内存后排队保存，产品文件导入不再调用它，待 OS20 移除。普通导出默认省略密钥；显式包含及导入凭据选择见 OS08/OS09 当前章节。

本文档描述 MatrixFlow AI 的代码结构与运行机制。当前代码基线：`main / 747eb35` + WP21-N + WP03-N + WP04-N + WP23-N + WP12-S-N + WP22-A-N + WP22-B-N + WP05-N + WP06-N + WP02-N + WP01-N + WP07-N + WP08-V-N + WP08-T-N + WP24-N + WP26-A-N + WP26-B-N-Windows + WP27-A-N。2026-09-09 路线已切换为 **Flutter Android/Windows 唯一持续开发客户端**，React/Tauri/Capacitor 冻结保留。本文的 React 结构与流程作为历史参考，不构成新增功能的双端同步要求。

WP20-N、WP21-N、WP03-N、WP04-N、WP23-N、WP12-S-N、WP22-A-N、WP22-B-N、WP05-N、WP06-N、WP02-N、WP01-N、WP07-N、WP08-V-N、WP08-T-N、WP24-N、WP26-A-N、WP26-B-N-Windows、WP27-A-N 已完成；下一包 WP11-N，WP20-W 未开工并取消。执行步骤以 [Implementation Plan](IMPLEMENTATION_PLAN_2026-09-08.md) 与 [HANDOFF](HANDOFF.md) 为准；集中详情、单象限聚焦、本地搜索、新建任务与子项截止日期独立编辑、跨象限置顶、多语言优先匹配、一键清空看板、服务商预设与动态发现、已完成集中查看、宫格/列表视图切换、字号与字体偏好、滑动操作/5秒撤销/失效契约、快捷键体系（命令面板已由 UX01 删除）、Windows 桌面壳与托盘、任务统计纯计算已实现（常驻统计 UI 已由 UX01 删除）。新 Flutter 保持旧 v1 导入，新字段走 WP11；不再要求冻结 React 理解新字段。

## 总体结构

仓库现存两套实现，历史基线共享 ExportData v1 与 AI 三协议，**当前无后端、无数据库**；今后只演进 Flutter，WP29 独立托管服务仍在计划中：
1. **Web / 混合端（冻结）**：纯前端单页应用，全部状态在 React 内存中，持久化到浏览器 localStorage；AI 调用由浏览器/WebView 直接发起。同一份 `dist/` 产物以三种形态交付：浏览器（`npm run dev` / 静态托管）、桌面（Tauri v2，`src-tauri/`）、安卓（Capacitor，`android/`）。
2. **原生跨平台端（唯一开发主线）**（`matrixflow-native/`）：Flutter 3 原生渲染应用，不经过 WebView，采用自绘引擎（Impeller/Skia）直接编译为 Android APK 与 Windows 桌面应用，通过 SharedPreferences 本地持久化，与 Web 端备份数据互通。

```
├── (Web / 混合端)
│   ├── index.html            HTML 壳：Tailwind CDN、内联 tailwind.config 与主题 CSS 变量、
│   │                         Nunito 字体、custom-scrollbar 样式
│   ├── index.tsx             React 入口（ReactDOM.createRoot）
│   ├── App.tsx               Web 唯一状态中心：全部 state、业务处理函数与页面布局（约 1672 行）
│   ├── components/           功能组件（Quadrant, TaskCard, InputArea, SettingsControls, ImportReview 等）
│   ├── services/
│   │   └── aiService.ts      AI 三协议服务（旧 Web 唯一与网络交互的模块，30s 超时）
│   ├── types.ts              全部数据类型定义
│   ├── translations.ts       Web 三语字典（en / zh / ja）
│   ├── src-tauri/            Tauri v2 桌面壳（Rust；tauri.conf.json 指向 ../dist）
│   └── android/              Capacitor 安卓壳（WebView 加载 dist/；gradle 工程）
│
└── matrixflow-native/        (Flutter 原生跨平台端)
    ├── lib/
    │   ├── main.dart         原生入口：Provider 依赖注入与主题/语言接线
    │   ├── storage.dart      原生状态中心（ChangeNotifier）+ SharedPreferences 持久化
    │   ├── models.dart       Flutter 演进模型（兼容旧 ExportData v1，不再与 types.ts 同步新字段）
    │   ├── shortcuts.dart    快捷键映射与意图管理（Ctrl+N/F/H、Ctrl+Shift+L 切视图、Esc；无 Ctrl+K）
    │   ├── task_query.dart   纯 Dart 任务搜索与过滤模块（中英日关键词、日历边界、去重）
    │   ├── task_commands.dart 任务撤销快照与命令模型（深拷贝、位置索引、代数失效）
    │   ├── task_stats.dart   当前任务进度与完成统计纯计算模型（父子独立、逾期、0%兜底）
    │   ├── quadrant.dart     四象限常量、颜色与字符串容错
    │   ├── ai_service.dart   Dart 原生三协议 HTTP 客户端 + 多级 JSON 兜底解析
    │   ├── l10n.dart         原生端三语本地化字典
    │   ├── theme.dart        Material 3 动态取色主题系统
    │   ├── services/         桌面抽象服务（DesktopShellService 托盘/热键/平台隔离）
    │   ├── screens/          矩阵主屏、已完成任务集中查看屏、搜索筛选屏、设置面板
    │   └── widgets/          任务卡、象限容器、单象限聚焦、任务详情面板、提醒失败横幅、输入弹层
    ├── test/                 182 项单元/Widget 测试（模型、协议、存储、完成/多选、展开、象限名称、十字矩阵、集中详情面板、单象限聚焦与下方卡片、本地搜索与筛选、新建/子任务截止日期与草稿保护、子任务CRUD与级联、键盘/返回/拖拽/文件选择、已完成集中查看与级联恢复、宫格/列表切换、字号与字体偏好、滑动操作与5秒撤销、快捷键、桌面壳抽象与托盘、任务统计计算等；此处 182 为旧基线数量）
    ├── android/              Flutter Android 工程（原生 Gradle）
    └── windows/              Flutter Windows 工程（原生 CMake/Runner）
```

## 数据模型（当前 v1；旧 types.ts / Flutter models.dart）

| 类型 | 说明 |
|---|---|
| `QuadrantType` | 四象限：1 紧急且重要、2 不紧急但重要、3 紧急但不重要、4 不紧急也不重要（内部枚举名 qDo/qPlan/qDelegate/qEliminate 仍保留） |
| `Board` | 任务板：id、名称、创建时间 |
| `Task` | 任务：标题、所属任务板、象限、是否长期（isLongTerm）、完成状态、截止日期（deadline 时间戳）、子任务数组 |
| `SubTask` | 子任务：标题、完成状态、可选截止日期 |
| `AIAnalysisResult` | AI 返回的单条分析结果：标题、象限、是否长期、子任务列表 |
| `AIProvider` | AI 协议枚举：openai / openai-responses / anthropic（旧值 custom、gemini 加载时迁移为 openai） |
| `AIConfig` | AI 配置：提供商 + 自定义接口的 baseUrl / apiKey / model / enableThinking（思考模式开关） |
| `AppSettings` | 应用设置：语言、主题、主题色、默认输入模式、5 个 AI 行为开关、紧急阈值天数（默认 3） |
| `ExportData` | 备份文件格式：version（当前 1）、时间戳、任务板、任务、设置、AI 配置 |

## 状态管理与持久化

App.tsx 持有全部 state，无全局状态库。四个 localStorage 键：

| 键 | 内容 |
|---|---|
| `matrixflow-tasks` | 全部任务（跨任务板） |
| `matrixflow-boards` | 任务板列表 |
| `matrixflow-config` | AI 配置（含自定义 API 密钥） |
| `matrixflow-settings` | 应用设置 |

- **加载**：首屏 useEffect 经 `safeParse` 读取（损坏数据重置该项并弹 Toast 提示），所有字段做缺省兜底；读取完成后置 `hydrated` 标志。
- **写回**：对应 state 变化即整体写回，但仅在 `hydrated` 之后生效——空列表也会持久化，删光任务后刷新不再复活旧数据，加载完成前的初始空 state 也不会覆盖存档。
- **截止日期自动升级**（App.tsx `checkDeadlines`）：加载时立即检查 + 每小时定时检查；未完成任务若距截止时间 ≤ `urgencyThresholdDays` 天，Q2（计划）→ Q1（立即），Q4（消除）→ Q3（授权）。日期输入按本地时区解析（`parseDateInput`）。

## 主题机制

- `appSettings.themeColor` → useEffect 将对应色值写入根元素 `--primary` CSS 变量（App.tsx:228）；Tailwind 配置把 `primary` 色映射到 `var(--primary)`。
- `appSettings.theme`（system / light / dark）→ 切换根元素 `dark` class，配合 Tailwind `darkMode: 'class'`。
- 象限固定色、背景色、弹簧动画曲线等在 index.html 内联 `tailwind.config` 中定义。

## AI 服务（services/aiService.ts）

两条管线，均支持三种协议（统一「baseUrl + model + apiKey」三要素，密钥存于 localStorage）：

| 协议 | 端点 | 鉴权 | JSON 约束 |
|---|---|---|---|
| `openai`（兼容） | `{baseUrl}/chat/completions` | `Authorization: Bearer` | `response_format: json_object` |
| `openai-responses` | `{baseUrl}/responses` | `Authorization: Bearer` | `text.format: json_object`，文本从 `output[].content[].text` 提取 |
| `anthropic` | `{baseUrl}/v1/messages` | `x-api-key` + `anthropic-version`（附带 Bearer 兼容代理） | 提示词强约束 + 围栏剥离兜底，`max_tokens: 8192` |

1. **`analyzeTasks(inputs[])`** — 分类主管线：判定象限 + 识别长期任务 + 分组合并 +（当 `autoDecomposeAI` 开启时）即时拆解出 3–5 个子任务。
2. **`decomposeTasksBatch(titles[])`** — 拆解主管线：对长期任务批量生成「2 小时内可完成」的子步骤。

- **容错**：`validateQuadrant` 兼容整数与 "Q1" 式字符串，非法值归到 4（消除）；`extractJsonArray` 依次尝试直接解析、剥 markdown 围栏、正则提取数组/对象；旧配置 `provider: 'custom'` 与 `'gemini'` 加载时自动迁移为 `openai`。
- **测试连接**：`testAIConnection` 按协议探测（OpenAI 系 `GET /models`；Anthropic `GET /v1/models`，404/405 时降级为 1-token messages 探活）。
- **超时**：所有请求 30 秒 AbortController 中止。

## 关键流程

### 添加任务（单条 / 头脑风暴）

InputArea 收集输入 → `handleAISort` 调用 `analyzeTasks` → 结果进入 pendingTasks；若 AI 建议分组且未抑制提示，进入 groupingQueue 弹窗确认；长期任务按设置进入批量拆解队列或单任务拆解 → 确认后入库。

### 导入 / 导出

旧 Web 导出：`handleExport` 把 boards + tasks + settings + aiConfig 序列化为带版本号的 JSON 下载。导入：选择文件 → 校验 → 选择模式（合并 / 覆盖）→ 覆盖需经确认弹窗 → 逐项勾选设置预览 → 执行导入。合并模式按 id 去重任务并过滤孤儿任务；旧设置白名单位于 App.tsx。今后新增设置仅接 Flutter 模型、Store 加载/导入白名单和字典，不更新冻结 Web；新任务字段按 WP11 迁移契约处理。

## 原生端本轮修复约定（2026-09-07）

- 原生存储逐记录容错，导入先校验再改变状态，写入排队并提示失败；增加本地 UI 元数据键 `matrixflow-active-board`。核心四键和 ExportData v1 不变，多键写入仍非事务。
- AI 请求可取消，完整响应共享 30 秒超时；Anthropic 自动避免重复 `/v1`；内部 `isGrouped` 区分分组与拆解，不进入备份模型。
- 弹层拥有自己的控制器和异步生命周期，输入结果由主页承接拆解流程；移动端使用长按拖拽。详情见 [原生审查报告](NATIVE_BUG_REVIEW_2026-09-07.md)。

## 已知问题 / 技术债

**2026-09-16 Flutter 基础复审补充：** 当前基线 `3a711c8` 的默认测试及双端构建通过，但不能据此验收全部功能。已复现详情跨任务覆盖、损坏备份覆盖清空、草稿/完成历史/撤销冲突和提醒异步生命周期问题。完整 22 项清单见 [基础功能复审报告](FOUNDATION_REVIEW_2026-09-16.md)。

**同日二审返修追加：** 二审 SR01–SR07 已修并纳入默认 305 项回归，analyze 0 issues；取消/恢复有序生命周期、首帧通知交付、响应式草稿保留、配置快照及可见排程失败重试见 [返修记录](FOUNDATION_SECOND_FIX_2026-09-16.md)。这不表示 F01–F22 所有边界已关闭。Windows 托盘/全局热键/通知系统行为仍待实测；旧 Android `applicationId` 迁移待决定，见 [ANDROID_PACKAGE_MIGRATION.md](ANDROID_PACKAGE_MIGRATION.md)。下文早期 Web/v1/80 项描述不是当前 Flutter 基线。

下列 Web 债务随旧版冻结保留，不自动派发整改；本节列出问题不代表要求恢复双轨开发。

- Tailwind 通过 CDN 运行时编译（index.html:7），官方不建议生产使用；2026-09-06 移除 Gemini 依赖后 Web 构建产物降至约 288 KB（gzip 87 KB），Rollup 500 KB 分包警告已消除。
- App.tsx 仍承担 Web 端全部业务逻辑（约 1672 行），是维护热点；50c70cc 与 2026-09-03 批次分别做过组件与渲染优化（React.memo + useCallback），但状态层未做更深度的模块化拆分。
- Web 端暂无自动化测试与 lint 配置；构建脚本不运行 tsc，类型检查需手动执行 `npx tsc --noEmit`。原生端（matrixflow-native）已配备 80 项单元/Widget 测试；设备集成测试不包含在默认 `flutter test` 中。
- 备份 JSON 明文包含自定义 AI 的 API 密钥（`aiConfig.customApiKey`）。
- 本地存储（localStorage / SharedPreferences）读写无显式 schema 版本迁移机制（`ExportData.version` 存在但未用于本地逐版升级；字段级兜底 + safeParse / 容错解析已覆盖当前绝大多数场景）。
