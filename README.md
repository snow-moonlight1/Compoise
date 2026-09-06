# MatrixFlow AI（四象限待办）

AI 驱动的艾森豪威尔矩阵任务管理应用：输入任务后由 AI 自动分类到四象限、合并同类项、拆解长期目标。支持多任务板、截止日期自动升级象限、数据导入导出与三语界面。

> 本项目由 Google AI Studio 生成起步，后在本地持续开发（2025-11-22 ~ 2025-11-25）。[AI Studio 应用链接](https://ai.studio/apps/drive/1PXJSykdaNlZGF_E7oxwtLKexWzfowZnW)

## 功能特性

- **四象限矩阵**：立即做 / 计划做 / 授权做 / 消除，任务卡片支持拖拽换象限，象限可一键清空
- **AI 智能分类**：单条输入或「头脑风暴」批量输入，AI 自动判定象限并给出理由
- **AI 自动分组**：多条零散输入自动合并为一个任务（如「买牛奶 + 买鸡蛋 → 购物」），合并前弹窗确认
- **AI 长期目标拆解**：识别长期任务并打标记，可自动或手动拆解为 3–5 个可执行子任务
- **截止日期自动升级**：临近截止的任务自动从「计划做」升到「立即做」、从「消除」升到「授权做」（阈值默认 3 天，每小时检查，可在设置调整，按本地时区计算）
- **多任务板**：创建 / 重命名 / 删除多个独立任务板
- **任务编辑**：行内编辑、批量编辑模态框、子任务与截止日期管理、象限选择器；全部子任务完成时自动勾选父任务（可设置）
- **数据备份**：导出 / 导入 JSON（导入支持合并自动去重或覆盖需二次确认，导入前可逐项勾选预览）
- **个性化**：亮 / 暗 / 跟随系统主题 × 5 种主题色；英文 / 简体中文 / 日文界面；隐藏已完成任务开关
- **AI 配置健康度**：设置页一键测试连接；所有请求 30 秒超时保护

## 技术栈

React 19 · TypeScript 5.8 · Vite 6 · Tailwind CSS（CDN 版）· OpenAI 兼容 / OpenAI Responses / Anthropic Messages 三协议 AI 调用 · localStorage 本地持久化（无后端）

## 快速开始

前置要求：Node.js（建议 ≥ 20）。

1. 安装依赖：

   ```bash
   npm install
   ```

2. 启动开发服务器，访问 http://localhost:3000（若端口被系统保留，加 `-- --port 3456`）：

   ```bash
   npm run dev
   ```

3. 在设置面板选择 AI 协议并填入 API 地址、模型名与密钥（如 DeepSeek：`https://api.deepseek.com` + 模型名 + key），点「测试连接」验证。

构建与预览：

```bash
npm run build     # 产物输出到 dist/
npm run preview
```

## AI 配置

应用支持三种 AI 调用协议，在设置面板切换，统一配置三要素（API 地址、模型名、密钥），密钥存于浏览器 localStorage：

| 协议 | 端点 | 适用 |
|---|---|---|
| OpenAI 兼容 | `{baseUrl}/chat/completions` | DeepSeek、Moonshot、SiliconFlow 等兼容服务商 |
| OpenAI Responses | `{baseUrl}/responses` | 支持 Responses 新接口的服务 |
| Anthropic Messages | `{baseUrl}/v1/messages` | Claude 及兼容代理 |

地址只填站点根（如 `https://api.deepseek.com`），服务商要求 `/v1` 时自行补上。设置面板的「测试连接」按协议自动探测。所有请求 30 秒超时保护。打包版应用中 Gemini 协议不可用（无构建期密钥），请使用自定义协议。

## 打包

同一份 Web 产物支持三种形态：

```bash
npm run build            # Web 产物 → dist/
npm run tauri build      # Windows 桌面（Tauri v2，需 Rust）→ src-tauri/target/release/bundle/
npx cap sync && cd android && ./gradlew.bat assembleDebug   # 安卓 APK → android/app/build/outputs/apk/debug/
```

> ⚠️ 导出的备份 JSON 与应用设置中包含自定义 API 密钥，请妥善保管，不要公开分发。

## 文档索引

| 文档 | 内容 |
|---|---|
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | 架构、数据模型、状态管理、AI 服务与关键流程 |
| [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) | 开发环境、命令、代码约定与常见扩展任务 |
| [CHANGELOG.md](CHANGELOG.md) | 依据 Git 历史重建的版本演进记录 |
| [AGENTS.md](AGENTS.md) | AI 协作会话的规则与边界 |
