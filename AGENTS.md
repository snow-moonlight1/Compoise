# AGENTS.md — MatrixFlow AI（四象限待办）

AI 驱动的艾森豪威尔矩阵任务管理应用，现包含 Web/混合端（React 19 + Vite 6 + Tauri v2 + Capacitor）与原生跨平台端（Flutter 3 + Dart，位于 `matrixflow-native/`，自绘引擎，Android + Windows）。两者数据模型与 AI 三协议完全互通。完整文档索引见 [README.md](README.md)，当前交接与下轮任务见 [docs/HANDOFF.md](docs/HANDOFF.md)。

## 运行与验证

- **Web 端**：`npm install` → `npm run dev`（http://localhost:3000，端口被系统保留时加 `-- --port 3456`）；改动后用 `npm run build` + `npx tsc --noEmit` 验证。
- **原生端（`matrixflow-native/`）**：`flutter test`（74 项单元/Widget 测试）+ `flutter analyze`（0 警告）；Flutter SDK 位于 `D:\Dev_SDKs\Flutter_SDK`。设备集成测试需单独运行。
- AI 密钥由用户在设置面板填写（存 localStorage / SharedPreferences）；不要把任何密钥值写死进代码、文档或日志。项目已无 `.env` 依赖。
- 主分支 `main`，无远端；提交遵循现有风格 `feat(模块): 描述`。

## 技术栈

- **Web / 混合端**：React 19 · TypeScript 5.8 · Vite 6 · Tailwind CSS（CDN 版，配置内联在 index.html）· 自定义 AI 三协议（OpenAI Compatible / OpenAI Responses / Anthropic Messages，Gemini 已按用户决定移除）· localStorage 持久化，无后端。桌面打包用 Tauri v2（`src-tauri/`），安卓打包用 Capacitor（`android/`）。
- **原生跨平台端**：Flutter 3 · Dart · Impeller / Skia 自绘引擎 · SharedPreferences 持久化 · HTTP AI 三协议客户端 · Android APK + Windows 桌面原生应用。

## 目录与约定

- `App.tsx` 是 Web 端唯一状态中心（约 1672 行）：全部 state 与业务处理函数都在这里，组件经 props 接收回调。
- `matrixflow-native/` 是原生端独立工程（lib/main.dart、storage.dart 为状态中心，models.dart 与 types.ts 同构）。
- `types.ts` 集中定义 Web 全部类型；`translations.ts` 是 Web 三语字典（en / zh / ja）；原生端分别对应 `models.dart` 与 `l10n.dart`。
- `services/aiService.ts` 是 Web 端唯一网络模块（原生端为 `ai_service.dart`）：支持三协议（OpenAI 兼容 / OpenAI Responses / Anthropic Messages）。
- 本地存储键统一为：`matrixflow-tasks` / `matrixflow-boards` / `matrixflow-config` / `matrixflow-settings`；读取处必须做缺省兜底。
- 新增 `AppSettings` 字段时三处同步：App.tsx 默认值与加载兜底、导入合并字段白名单（约 789 行）、translations.ts 三语文案（原生端同步 models.dart、storage.dart 与 l10n.dart）。

## 当前状态（代码基线 2026-09-07；路线更新 2026-09-09）

- 功能完整的本地应用：双轨架构（Web/混合打包 + Flutter 原生），共享 ExportData v1 数据备份格式与 AI 三协议。Web 端构建体积已瘦身至 288 KB。演进史见 docs/CHANGELOG.md。
- 已知技术债清单在 docs/ARCHITECTURE.md「已知问题」；本机打包要点在 docs/DEVELOPMENT.md「打包」。
- 验证命令：Web 端 `npm run build` + `npx tsc --noEmit`；原生端 `cd matrixflow-native && flutter test && flutter analyze`。
- 当前计划见 [Implementation Plan](docs/IMPLEMENTATION_PLAN_2026-09-08.md)：独立开发 MatrixFlow，参考交互但不 fork/复制 Focus、不跟进其 issue/PR，不组织几十人试用。WP20-N 已完成（Flutter 完成/多选分离、子项展开、逐行删除线；`flutter test` 74/74）。下一实施包 WP20-W。保留多 Board、父子任务、AI 与备份互通。Android debug/release（B01 已关闭）和 Windows release 曾通过；新场景须自行验证，历史通过不是新功能验收。
- 目标路线为开源客户端、GitHub Release/商店发行、BYOK 和后续可选 ¥9/月有额度托管 AI；本轮仅完善文档，未发布或实现服务。各实施助手只领取一个子批次，按 HANDOFF 接手。

## 边界

- 不要引入后端、数据库或云同步，除非用户明确要求——本项目的设计前提是纯前端 + 本地存储。
- 2026-09-09 用户已将可选托管 AI 纳入产品路线，对应 WP29；只有该工作包实施时才增加独立账号/订阅/额度服务，不把任务库迁到服务器、不让普通待办或 BYOK 依赖登录。云同步仍是独立的 WP18，不能混入托管服务。
- 不要把备份 JSON 的内容（含自定义 API 密钥）写入文档、提交或日志。
- docs/CHANGELOG.md 依据 Git 历史重建：新增条目追加在顶部，不要改写既有条目；新功能合并后同步更新。
- docs/ARCHITECTURE.md 的「已知问题」修复后应从清单移除，保持文档与代码一致。
