# AGENTS.md — MatrixFlow AI（四象限待办）

AI 驱动的艾森豪威尔矩阵任务管理纯前端应用（React 19 + Vite 6 + TypeScript）。完整文档索引见 [README.md](README.md)。

> 原生跨平台版（Flutter，Android + Windows）在 `D:\Dev_project\matrixflow-native`（独立仓库），数据备份格式与本仓库互通。

## 运行与验证

- `npm install` → `npm run dev`（http://localhost:3000，端口被系统保留时加 `-- --port 3456`）；改动后用 `npm run build` + `npx tsc --noEmit` 做最低验证（无测试框架）。
- AI 密钥由用户在设置面板填写（存 localStorage）；不要把任何密钥值写死进代码、文档或日志。项目已无 `.env` 依赖。
- 主分支 `main`，无远端；提交遵循现有风格 `feat(模块): 描述`。

## 技术栈

React 19 · TypeScript · Vite 6 · Tailwind CSS（CDN 版，配置内联在 index.html）· 自定义 AI 三协议（OpenAI Compatible / OpenAI Responses / Anthropic Messages，Gemini 已按用户决定移除）· localStorage 持久化，无后端。桌面打包用 Tauri v2（`src-tauri/`），安卓打包用 Capacitor（`android/`），本机构建要点见 docs/DEVELOPMENT.md「打包」。

## 目录与约定

- `App.tsx` 是唯一状态中心（约 1630 行）：全部 state 与业务处理函数都在这里，组件经 props 接收回调。大改动优先考虑继续拆分，而不是继续往里堆。
- `types.ts` 集中定义全部类型；`translations.ts` 是三语字典（en / zh / ja），任何用户可见文案必须三语同步。
- `services/aiService.ts` 是全项目唯一网络模块：两条管线（`analyzeTasks` 分类/分组/即时拆解、`decomposeTasksBatch` 批量拆解），三协议（OpenAI 兼容 / OpenAI Responses / Anthropic Messages）。
- localStorage 键：`matrixflow-tasks` / `matrixflow-boards` / `matrixflow-config` / `matrixflow-settings`；读取处必须做缺省兜底（旧数据无新字段）。
- 新增 `AppSettings` 字段时三处同步：App.tsx 默认值与加载兜底、导入合并字段白名单（约 789 行）、translations.ts 三语文案。

## 当前状态（2026-09-06）

- 功能完整的本地个人应用：四象限 + AI 三协议（OpenAI 兼容 / OpenAI Responses / Anthropic Messages，实测 DeepSeek；Gemini 已移除）+ 导入导出 + 三语 + 多主题 + 桌面/安卓打包。演进史见 CHANGELOG.md。
- 已知技术债清单在 docs/ARCHITECTURE.md「已知问题」；本机打包要点（subst 盘符、JDK 21、阿里镜像、端口排除段）在 docs/DEVELOPMENT.md「打包」。
- 验证命令：`npm run build` + `npx tsc --noEmit`（@types/react 已装，检查真实有效——不要移除）。
- 下一步候选：安卓 release 签名与应用图标、App.tsx 状态层拆分、引入测试、localStorage 数据版本迁移。

## 边界

- 不要引入后端、数据库或云同步，除非用户明确要求——本项目的设计前提是纯前端 + 本地存储。
- 不要把备份 JSON 的内容（含自定义 API 密钥）写入文档、提交或日志。
- CHANGELOG.md 依据 Git 历史重建：新增条目追加在顶部，不要改写既有条目；新功能合并后同步更新。
- docs/ARCHITECTURE.md 的「已知问题」修复后应从清单移除，保持文档与代码一致。
