# 架构

> 2026-09-17 更新：UX01–03 已提交；UX04 为 Windows CJK 字体策略与预览。自动化 324 项通过，双端实机未验；下一包 UX05（父子行对齐）。下文旧包进度为历史，现状以 HANDOFF 与 UX 返修计划为准。

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
