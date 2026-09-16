# MatrixFlow AI — 四象限智能待办清单 / Local-First Eisenhower Matrix

[![Flutter Test](https://img.shields.io/badge/Flutter%20Tests-255%2F255%20Passed-brightgreen)](matrixflow-native/)
[![Analyze](https://img.shields.io/badge/Analyze-0%20Issues-brightgreen)](matrixflow-native/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20Windows-blue)](matrixflow-native/)

MatrixFlow AI 是一款基于经典**艾森豪威尔四象限法则**（Eisenhower Matrix）打造的原生现代化任务管理工具。采用纯本地优先（**Local-First**）设计，并支持 **BYOK（自带 API 密钥）** 端到端直连大语言模型，帮助您聚焦高价值事项，高效拆解复杂目标。

MatrixFlow AI is a modern, local-first task management application built on the classic **Eisenhower Matrix principle**. Powered by Flutter with zero WebView bloat, it supports **BYOK (Bring Your Own Key)** to directly connect to leading AI models for smart classification, grouping, and subtask decomposition.

---

## 🌟 核心特性 / Features

- **极简四象限十字矩阵 (Eisenhower Matrix)**：
  - 紧急且重要 (Q1) / 不紧急但重要 (Q2) / 紧急但不重要 (Q3) / 不紧急也不重要 (Q4)；
  - 极简无框十字布局，首行对齐复选框与多行逐行删除线；
  - 自由长按拖拽跨象限移动与置顶；
  - 单象限聚焦沉浸模式（Focus View）与纵向/宫格双视图一键切换。
- **BYOK 智能 AI 助手 (Bring Your Own Key)**：
  - 预设支持 **DeepSeek 官方**、**火山引擎**、**阿里云百炼**，以及任意 OpenAI 兼容端点和 Anthropic Messages 协议；
  - 支持动态模型发现与思考模式控制（Thinking Mode / Reasoner）；
  - 智能四象限自动归类、3–5 步长期目标拆解与同类任务合并；
  - 端到端直连官方服务商，绝无任何中间代理中转。
- **100% 本地优先与绝对隐私 (Local-First & Privacy-Centric)**：
  - 数据 100% 存储于本机设备沙盒，完全离线运行；
  - 零中央服务器、零广告 SDK、零数据追踪埋点（无 Google/Firebase/友盟分析）。
- **跨平台定时提醒与桌面保活 (Cross-Platform Reminders)**：
  - **Android**：原生定时通知（遵循 `SCHEDULE_EXACT_ALARM` 合规规范，坚决不申请高危 `USE_EXACT_ALARM`），开机重启自动恢复排期；
  - **Windows 桌面端**：WinRT Toast 丰富通知横幅，系统托盘（System Tray）常驻保活，点击通知一键唤起主窗口与目标任务高亮；
  - 全局命令面板（**Ctrl+K / ⌘K**）支持快速定位任务与执行操作。
- **生产力细节与贴心设计**：
  - 手势滑动快速完成与删除，支持 **5 秒浮动撤销（Undo）**；
  - 7 日完成趋势直方图与已完成历史看板；
  - 新手 5 步响应式交互教程（随时可在帮助中重新回顾）；
  - 标准 JSON 数据导入/导出，跨平台 100% 无损往返互通。

---

## 📱 平台架构与状态 / Platform Architecture

本项目代码库主干架构如下：

```
martix/
├── matrixflow-native/         # 【唯一持续开发主线】Flutter 跨平台客户端 (Android + Windows)
│   ├── lib/                  # 状态中心 (storage.dart)、数据模型 (models.dart)、三语字典 (l10n.dart)
│   │   ├── screens/          # 主界面、设置、搜索、完成历史、新手引导
│   │   ├── services/         # 跨平台提醒服务、桌面托盘壳服务、AI 直连服务
│   │   └── widgets/          # 任务卡片、十字象限面板、命令面板、统计条
│   ├── android/              # 原生 Android 工程 (build.gradle.kts, 签名隔离, 权限合规)
│   ├── windows/              # 原生 Windows 桌面工程 (C++ Runner, Win32 窗口, 托盘与图标)
│   └── test/                 # 全量自动化测试套件 (255 项测试 100% 全绿)
├── docs/                     # 架构文档、发行规划、隐私政策、版本交接记录
├── scripts/                  # 自动化构建打包脚本 (build_release.ps1)
├── .github/workflows/        # CI/CD 流水线 (Tag 触发自动构建发布 Release)
├── src/ & src-tauri/         # 【已冻结归档】早期 React 19 / Tauri / Capacitor 原型 (只读参考)
└── LICENSE                   # MIT 开源许可证
```

> ⚠️ **说明**：自 2026-09-09 起，MatrixFlow 客户端全面收敛于 `matrixflow-native/`（Flutter 3 自绘引擎），根目录旧版 React/Tauri 仅保留为历史只读参考，不参与日常开发与发布构建。

---

## 🚀 快速开始与编译指南 / Quick Start & Build

### 环境要求 / Prerequisites
- [Flutter SDK](https://flutter.dev/) (3.16+ / 3.8.0-dev，推荐配置到系统环境变量)
- **Android 构建**：Android Studio & Android SDK (API 34+, Java 17)
- **Windows 构建**：Visual Studio 2022（包含「使用 C++ 的桌面开发」工作负载）

### 1. 运行本地开发与测试 / Run & Test
```bash
cd matrixflow-native

# 1. 获取依赖
flutter pub get

# 2. 静态代码质量检查 (0 issues)
flutter analyze --no-pub

# 3. 运行全量自动化测试 (255/255 passed)
flutter test --no-pub

# 4. 本地启动运行 (自动检测当前连接的设备或 Windows 桌面)
flutter run
```

### 2. 一键自动化构建 Release 发行包 / Automated Release Build
项目提供了跨平台自动化构建脚本，可一键生成已配置版本号、SHA256 校验和的产物：

```powershell
# 在项目根目录下执行 PowerShell 脚本
powershell -ExecutionPolicy Bypass -File scripts\build_release.ps1 -Platform All
```

构建完成后产物将输出在 `release_dist/` 目录下：
- **Android**：`matrixflow-v1.0.0-android.apk`（约 24.6 MB）
- **Windows**：`matrixflow-v1.0.0-windows-portable.zip`（绿色便携解压即用，约 12.0 MB）
- **校验清单**：`SHA256SUMS.txt`

---

## 🔑 BYOK 服务商配置指南 / BYOK Configuration Guide

MatrixFlow 遵循绝对的安全合规原则，API Key 仅保存在本地设备沙盒中。

1. 打开应用右上方进入「**设置**」面板；
2. 选择您的 AI 服务商预设：
   - **DeepSeek 官方**：直连 `https://api.deepseek.com`，填入 Key 后自动拉取 `deepseek-chat` / `deepseek-reasoner` 模型，支持深度思考控制；
   - **火山引擎 (Volcengine)**：填入 Key 后自动适配模型接入点；
   - **阿里云百炼 (Bailian)**：填入 Key 后自动解析兼容通义千问系列端点；
   - **自定义 (Custom)**：支持任意兼容 OpenAI / Anthropic Messages 协议的自定义端点与模型。
3. 点击「**测试连接**」，验证通过后即可在任务主界面畅享 AI 极速分类与拆解。

---

## 📖 相关文档 / Documentation

- [开源合规与发行规划 (RELEASE_PLAN.md)](docs/RELEASE_PLAN.md)
- [隐私政策 (PRIVACY_POLICY.md)](docs/PRIVACY_POLICY.md)
- [应用商店上架送审物料 (STORE_LISTING.md)](docs/STORE_LISTING.md)
- [v1.0.0 发行说明 (v1.0.0.md)](docs/release_notes/v1.0.0.md)
- [技术架构与数据模型 (ARCHITECTURE.md)](docs/ARCHITECTURE.md)
- [数据演进与版本迁移契约 (DATA_COMPATIBILITY.md)](docs/DATA_COMPATIBILITY.md)
- [本地定时提醒设计方案 (REMINDERS_DESIGN.md)](docs/REMINDERS_DESIGN.md)

---

## 📄 开源许可证 / License

MatrixFlow AI 基于 **[MIT License](LICENSE)** 协议开源。商业与个人均可自由使用、分发与修改源码。
