# 更新日志

> 本项目在开发期间未维护变更日志。以下内容于 2026-08-30 依据 Git 提交历史（`git log`）与代码现状重建整理，格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)。
>
> 开发周期：2025-11-22 至 2025-11-25，共 7 个提交，均为 `main` 分支直线历史（无标签、无远端仓库）。
>
> 2026-09-03 起进入修复与打磨阶段，新增条目按日期追加在下方。

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
