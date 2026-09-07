# MatrixFlow AI（四象限待办）

AI 驱动的艾森豪威尔矩阵任务管理应用：输入任务后由 AI 自动分类到四象限、合并同类项、拆解长期目标。支持多任务板、截止日期自动升级象限、数据导入导出与三语界面。

提供两种端实现，数据备份格式与 AI 三协议完全互通：
1. **Web / 混合端**：React 19 + Vite 6 + TypeScript，支持浏览器、Tauri v2 桌面壳与 Capacitor 安卓壳。
2. **原生跨平台端**（`matrixflow-native/`）：Flutter 3 + Dart，Impeller / Skia 自绘引擎，无需 WebView，直接编译为 Android APK 与 Windows 原生桌面应用。

> 本项目起步于 Google AI Studio 生成原型，后在本地持续演进（2025-11-22 ~ 至今）。

## 功能特性

- **四象限矩阵**：立即做 / 计划做 / 授权做 / 消除，任务卡片支持拖拽换象限，象限可一键清空
- **AI 智能分类**：单条输入或「头脑风暴」批量输入，AI 自动判定象限并给出理由
- **AI 自动分组**：多条零散输入自动合并为一个任务（如「买牛奶 + 买鸡蛋 → 购物」），合并前弹窗确认
- **AI 长期目标拆解**：识别长期任务并打标记，可自动或手动拆解为 3–5 个可执行子任务
- **截止日期自动升级**：临近截止的任务自动从「计划做」升到「立即做」、从「消除」升到「授权做」（阈值默认 3 天，每小时检查，可在设置调整，按本地时区计算）
- **多任务板**：创建 / 重命名 / 删除多个独立任务板
- **任务编辑**：行内编辑、批量编辑模态框、子任务与截止日期管理、象限选择器；全部子任务完成时自动勾选父任务（可设置）
- **数据备份**：导出 / 导入 JSON（导入支持合并自动去重或覆盖需二次确认，导入前可逐项勾选预览；Web 与 Native 版备份文件互通）
- **个性化**：亮 / 暗 / 跟随系统主题 × 5 种主题色；英文 / 简体中文 / 日文界面；隐藏已完成任务开关
- **AI 配置健康度**：设置页一键测试连接；所有请求 30 秒超时保护

## 技术栈

- **Web / 混合端**：React 19 · TypeScript 5.8 · Vite 6 · Tailwind CSS（CDN 版）· OpenAI 兼容 / OpenAI Responses / Anthropic Messages 三协议 AI 调用 · localStorage 本地持久化（无后端）
- **原生跨平台端**：Flutter 3 · Dart · Impeller / Skia 自绘引擎 · Material 3 · SharedPreferences 本地持久化 · 原生 HTTP 三协议客户端

## 快速开始

前置要求：
- **Web 端**：Node.js（建议 ≥ 20）。
- **原生跨平台端**：Flutter SDK 3.x，Android SDK / VS C++ 构建套件（按需）。

### Web 端

1. 安装依赖：
   ```bash
   npm install
   ```

2. 启动开发服务器，访问 http://localhost:3000（若端口被系统保留，加 `-- --port 3456`）：
   ```bash
   npm run dev
   ```

3. 构建与预览：
   ```bash
   npm run build     # 产物输出到 dist/（约 288 KB）
   npm run preview
   ```

### 原生跨平台端（Flutter）

```bash
cd matrixflow-native
flutter pub get
flutter test     # 运行 20 项自动化测试
flutter run      # 启动应用（按提示选择 Android 设备或 Windows 桌面）
```

## AI 配置

应用支持三种 AI 调用协议，在设置面板切换，统一配置三要素（API 地址、模型名、密钥），密钥存于本地（浏览器 localStorage 或原生 SharedPreferences）：

| 协议 | 端点 | 适用 |
|---|---|---|
| OpenAI 兼容 | `{baseUrl}/chat/completions` | DeepSeek、Moonshot、SiliconFlow 等兼容服务商 |
| OpenAI Responses | `{baseUrl}/responses` | 支持 Responses 新接口的服务 |
| Anthropic Messages | `{baseUrl}/v1/messages` | Claude 及兼容代理 |

地址只填站点根（如 `https://api.deepseek.com`），服务商要求 `/v1` 时自行补上。设置面板的「测试连接」按协议自动探测。所有请求 30 秒超时保护。

## 打包

支持多种形态产物构建：

```bash
# 1. Web 产物与混合打包壳
npm run build            # Web 产物 → dist/
npm run tauri build      # Windows 桌面壳（Tauri v2，需 Rust）→ src-tauri/target/release/bundle/
npx cap sync && cd android && ./gradlew.bat assembleDebug   # 安卓 APK 壳（Capacitor WebView）

# 2. 原生跨平台端（Flutter，不依赖 WebView）
cd matrixflow-native
flutter build apk --debug     # Android APK → build/app/outputs/flutter-apk/app-debug.apk
flutter build windows         # Windows 桌面应用 → build/windows/x64/runner/
```

> ⚠️ 导出的备份 JSON 与应用设置中包含自定义 API 密钥，请妥善保管，不要公开分发。

## 文档索引

| 文档 | 内容 |
|---|---|
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | 架构、数据模型、状态管理、AI 服务与关键流程 |
| [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) | 开发环境、命令、代码约定与常见扩展任务 |
| [matrixflow-native/README.md](matrixflow-native/README.md) | Flutter 原生跨平台版架构、开发与构建指南 |
| [CHANGELOG.md](CHANGELOG.md) | 依据 Git 历史重建的版本演进记录 |
| [AGENTS.md](AGENTS.md) | AI 协作会话的规则与边界 |
