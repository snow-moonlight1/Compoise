# AGENTS.md — MatrixFlow AI（四象限待办）

AI 驱动的艾森豪威尔矩阵任务管理应用。**持续开发的客户端仅为 Flutter Android + Windows，位于 `matrixflow-native/`；根目录 React / Tauri / Capacitor 冻结保留。** 文档索引见 [README.md](README.md)，当前任务见 [docs/HANDOFF.md](docs/HANDOFF.md)，可执行范围见 [Implementation Plan](docs/IMPLEMENTATION_PLAN_2026-09-08.md)。

> **2026-09-23 当前派单覆盖：** 用户本轮连续授权 OS10、OS11；两包实施后下一包 OS12，本轮不开始 OS12/OS13。OS10 统一模型发现身份并让缓存与设置页一起失效；OS11 以三协议为边界发送思考参数，并把端点/鉴权、模型发现和可能计费的生成测试分开。OS01–OS09 历史成果保留。继续暂停 WP10/WP29/UI 实验；下文旧包进度为历史，以本段和 HANDOFF 顶部优先。

## 运行与验证

- **Flutter 主线**：在 `matrixflow-native/` 运行 `flutter test --no-pub` + `flutter analyze --no-pub`。SDK：`D:\Dev_SDKs\Flutter_SDK`；新增或未解析依赖先 `flutter pub get`。WP21-N 后为 77 项通过、analyze 0 issues，设备集成测试需单独运行，不能当作新包验收。
- Android 与 Windows 共用业务实现，分别验收触摸/软键盘与鼠标/键盘/焦点/窗口缩放；Windows 工程和 VS C++ 工具链已存在，不从零移植。
- **冻结的 Web**：仅用户另行安排 legacy 修复时，在根目录 `npm install` → `npm run dev`（端口 3000，冲突用 `-- --port 3456`），用 `npm run build` + `npx tsc --noEmit` 验证。Flutter 功能包不运行这组检查、不追求 Web 功能对齐。
- AI 密钥由用户填写并本地保存；不要把密钥、备份内容或令牌写入代码、文档、日志。项目无 `.env` 依赖。
- 主分支 `main`，无远端；提交遵循现有风格 `feat(模块): 描述`，保护其他助手和用户未提交改动。

## 技术栈与目录约定

- **主线**：Flutter 3 / Dart，自绘引擎 Impeller/Skia，SharedPreferences，本地任务，无已实施后端。Android APK + Windows 原生桌面。
- `matrixflow-native/lib/main.dart` 为入口；`storage.dart` 为状态与持久化中心；`models.dart` 是今后演进的数据模型，`l10n.dart` 为 en/zh/ja 三语字典。通用业务只在 Store/服务中实现一次，平台差异放适配层。
- `matrixflow-native/lib/ai_service.dart` 支持 OpenAI Compatible / OpenAI Responses / Anthropic Messages 三协议及思考控制；保留现有无说教、分类、分组和拆解契约。
- **legacy 只读参考**：React 19 / Vite 6 / TypeScript 5.8 / Tailwind CDN；`App.tsx` 为旧状态中心，`types.ts`、`translations.ts`、`services/aiService.ts` 为旧模型/字典/服务，`src-tauri/` 与根目录 `android/` 为旧壳。不因 Flutter 新字段同步修改这些文件，不移动/删除现有目录。
- 本地核心存储键保持 `matrixflow-tasks` / `matrixflow-boards` / `matrixflow-config` / `matrixflow-settings`；读取处必须做缺省兜底。
- 新增 AppSettings 字段时同步 Flutter 模型、Store 默认/加载/导入白名单、设置页和三语字典；不再要求 React 三处同步。新任务字段先按 WP11 迁移契约演进。
- 新 Flutter 继续读取旧 Web/Native ExportData v1；Android/Windows 备份格式一致。未来新字段不承诺旧 React 无损读回，冻结旧版不为此更新。备份互通不等于自动同步。

## 当前状态（代码基线 main / 747eb35 + WP21-N；路线更新 2026-09-09）

- 独立开发 MatrixFlow，参考 Focus 交互但不 fork/复制、不跟进其 issue/PR，不组织几十人试用；保留多 Board、父子任务、AI、BYOK 与本地数据。
- **WP20-N、WP21-N 已完成（自动化）**：完成/多选/展开/逐行删除线；完整紧急/重要象限名与分类提示词。`flutter test` 77/77。**WP20-W 未开工，已取消；下一实施包 WP03-N。** 每位助手只领取一个子批次，以计划第 3/4/5/9 节与 HANDOFF 为准。
- `docs/ARCHITECTURE.md` 的已知问题修复后及时更新，未实现的 WP03 十字布局/后续 UI 不提前写成完成。
- N 表示共享 Flutter；旧 W 表示 React Web，**不是 Windows**。所有未实施 W 子批次取消，对应功能保留在 Flutter 包中。Flutter Web 暂不纳入；介绍/下载页独立于完整待办应用。
- Android debug/release（B01 已关闭）和 Windows release 曾通过；新场景须自行验证。已知问题见 `docs/ARCHITECTURE.md`，打包见 `docs/DEVELOPMENT.md`。
- 产品路线：开源客户端、GitHub Release/商店发行、BYOK，后续可选 ¥9/月有额度托管 AI；服务和发布均未实施。
- UI 实验分支需待基础包与 Android/Windows 检查完成后另领计划第 10 节；当前不创建分支、不尝试全局拟态重画。

## 边界

- 不引入后端、数据库或云同步，除非进入用户明确安排的对应工作包；普通待办坚持本地保存。
- WP29 是已纳入路线的可选账号/订阅/额度服务，只有实施该包才增加独立后端，不把任务库迁到服务器、不让普通待办或 BYOK 依赖登录。云同步仍是独立 WP18。
- 不把备份 JSON 内容（含自定义 API 密钥）写入文档、提交或日志；测试使用无密钥合成数据。
- `docs/CHANGELOG.md` 新条目追加顶部，不改写既有历史；代码/功能改变后同步，纯计划调整不冒充功能发布。
