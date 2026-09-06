# 架构

本文档描述 MatrixFlow AI 的代码结构与运行机制。最后核对：2026-09-03（基于 `main` 工作区，含当日修复批次）。

## 总体结构

纯前端单页应用，**无后端、无数据库**：全部状态在 React 内存中，持久化到浏览器 localStorage；AI 调用由浏览器/WebView 直接发起。同一份 `dist/` 产物以三种形态交付：浏览器（`npm run dev` / 静态托管）、桌面（Tauri v2，`src-tauri/`）、安卓（Capacitor，`android/`）。

```
index.html            HTML 壳：Tailwind CDN、内联 tailwind.config 与主题 CSS 变量、
                      Nunito 字体、custom-scrollbar 样式
index.tsx             React 入口（ReactDOM.createRoot）
App.tsx               唯一状态中心：全部 state、业务处理函数与页面布局（约 1850 行）
├─ components/        功能组件
│  ├─ Quadrant.tsx          单个象限列：任务列表、拖放目标（含拖拽高亮）、一键清空
│  ├─ TaskCard.tsx          任务卡片：复选框、子任务、截止日期、AI 理由、象限色条
│  ├─ InputArea.tsx         底部输入区：单条 / 头脑风暴两种输入模式
│  ├─ SettingsControls.tsx  设置面板控件
│  ├─ ImportReview.tsx      导入预览（逐项勾选）
│  ├─ Icons.tsx             内联 SVG 图标集
│  ├─ ErrorBoundary.tsx     渲染崩溃兜底（附清除本地数据逃生入口）
│  └─ ui/                   基础 UI：Modal（Esc/遮罩关闭/焦点圈）、Toast、Checkbox、ToggleSwitch
├─ services/
│  └─ aiService.ts          AI 四协议服务（全项目唯一与网络交互的模块，30s 超时）
├─ types.ts                 全部数据类型定义
└─ translations.ts          三语字典（en / zh / ja），组件经 `t` 对象取词
src-tauri/             Tauri v2 桌面壳（Rust；tauri.conf.json 指向 ../dist）
android/               Capacitor 安卓壳（WebView 加载 dist/；gradle 工程）
```

## 数据模型（types.ts）

| 类型 | 说明 |
|---|---|
| `QuadrantType` | 四象限枚举：1=Do（紧急重要）、2=Plan（不紧急重要）、3=Delegate（紧急不重要）、4=Eliminate（不紧急不重要） |
| `Board` | 任务板：id、名称、创建时间 |
| `Task` | 任务：标题、所属任务板、象限、是否长期（isLongTerm）、完成状态、截止日期（deadline 时间戳）、子任务数组 |
| `SubTask` | 子任务：标题、完成状态、可选截止日期 |
| `AIAnalysisResult` | AI 返回的单条分析结果：标题、象限、是否长期、理由、子任务列表 |
| `AIProvider` | AI 协议枚举：openai / openai-responses / anthropic（旧值 custom、gemini 加载时迁移为 openai） |
| `AIConfig` | AI 配置：提供商 + 自定义接口的 baseUrl / apiKey / model |
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

导出：`handleExport` 把 boards + tasks + settings + aiConfig 序列化为带版本号的 JSON 下载。导入：选择文件 → 校验 → 选择模式（合并 / 覆盖）→ 覆盖需经确认弹窗 → 逐项勾选设置预览 → 执行导入。合并模式按 id 去重任务并过滤孤儿任务；设置合并走字段白名单（App.tsx `importSelection` 默认集），新增设置字段时需同步该白名单。

## 已知问题 / 技术债

- Tailwind 通过 CDN 运行时编译（index.html:7），官方不建议生产使用；构建产物约 507 KB（gzip 125 KB），已越过 Rollup 500 KB 分包警告线。
- App.tsx 仍承担全部业务逻辑（约 1850 行），是维护热点；50c70cc 与 2026-09-03 批次分别做过组件与渲染优化（React.memo + useCallback），但状态层未拆。
- 无测试、无 lint 配置；`vite build` 不运行 tsc，类型检查需手动 `npx tsc --noEmit`（2026-09-03 起带真实 @types/react，检查真实有效）。
- 备份 JSON 明文包含自定义 AI 的 API 密钥（`aiConfig.customApiKey`）。
- localStorage 读写无 schema 版本号（`ExportData.version` 存在但未用于本地迁移；字段级兜底 + safeParse 已覆盖常见损坏场景）。
