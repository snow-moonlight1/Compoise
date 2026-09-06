# 开发指南

最后核对：2026-08-30。架构与数据模型见 [ARCHITECTURE.md](ARCHITECTURE.md)，历史演进见 [../CHANGELOG.md](../CHANGELOG.md)。

## 环境与命令

| 命令 | 说明 |
|---|---|
| `npm install` | 安装依赖 |
| `npm run dev` | 开发服务器，http://localhost:3000（host `0.0.0.0`，局域网可访问） |
| `npm run build` | 生产构建，产物输出到 `dist/`（约 494 KB，gzip 121 KB） |
| `npm run preview` | 本地预览构建产物 |
| `npx tsc --noEmit` | 类型检查（构建脚本不含 tsc，需手动运行；当前通过） |

无测试框架、无 lint 配置。改动后的最低验证组合：`npm run build` + `npx tsc --noEmit`。注意 `@types/react` / `@types/react-dom`（2026-09-03 补装）是 tsc 真实生效的前提，勿删。

## 环境变量

无。2026-09-06 移除 Gemini 协议后，项目不再依赖任何环境变量或 `.env` 文件；AI 的地址 / 模型名 / 密钥全部由用户在设置面板填写并存于 localStorage。

## 代码约定（从现有代码归纳）

- 函数组件 + React.FC，props 用 interface 声明；事件回调以 `on` 前缀命名，由 App.tsx 下传。
- 业务逻辑集中在 App.tsx：新增功能一般先加 state（或复用既有 state）+ 处理函数，再经 props 接入组件。
- 所有用户可见文案走 `translations.ts` 的 `t` 对象，三种语言（en / zh / ja）必须同步补充。
- 类型集中定义在 `types.ts`；组件不自定义任务 / 设置相关类型。
- 样式用 Tailwind 工具类；主题色经 `--primary` CSS 变量注入，自定义动画曲线与关键帧在 index.html 内联配置中。

## 常见扩展任务

### 新增一种界面语言

1. `types.ts` 的 `Language` 联合类型增加值；`translations.ts` 增加对应完整字典。
2. App.tsx 语言选择 UI 增加选项。
3. `services/aiService.ts` 的 `getLanguagePromptSuffix` 与两处提示词里的语言映射增加分支。

### 新增一个 AI 提供商

1. `types.ts` 的 `AIProvider` 枚举增加值，`AIConfig` 按需扩展字段。
2. `aiService.ts` 两条管线（`analyzeTasks`、`decomposeTasksBatch`）各增加一个实现分支。
3. 设置界面（App.tsx + SettingsControls.tsx）增加配置输入；注意自定义密钥会随备份 JSON 导出。

### 新增一个设置项

1. `types.ts` 的 `AppSettings` 增加字段。
2. App.tsx 补默认值与**加载兜底**（读取处有 `?? 缺省` 合并，旧 localStorage 数据才不会报错）。
3. SettingsControls.tsx 增加控件；`translations.ts` 补三语文案。
4. 若该设置需要随导入保留：确认 App.tsx 导入合并的字段白名单（约 789 行）已包含新字段。

### 新增一个任务字段

1. `types.ts` 对应类型增加可选字段（Task / SubTask）。
2. localStorage 旧数据无该字段 → 所有读取处做可选链 / 缺省处理。
3. 备份兼容：`ExportData` 中的 Task 结构随之变化，但 `version` 仍为 1——若做破坏性变更应升级 version 并在导入处做迁移分支。

## 打包

同一份 `dist/` 产物，三种形态（详见 README「打包」）：

| 形态 | 工具 | 命令 |
|---|---|---|
| 桌面（Windows） | Tauri v2（`src-tauri/`，需 Rust） | `npm run tauri build` → `src-tauri/target/release/bundle/{msi,nsis}/` |
| 安卓 | Capacitor（`android/`） | `npx cap sync` → `cd android && ./gradlew.bat assembleDebug` |
| Web | Vite | `npm run build` → `dist/` |

本机环境要点（2026-09-06 实测）：

- **项目路径含中文**：AGP 先是直接拒绝（已加 `android.overridePathCheck=true` 绕过检查），依赖解析阶段仍会报「文件名、目录名或卷标语法不正确」。可靠做法是映射 ASCII 盘符后构建：`subst M: "D:\Dev_project\四象限待办"`，然后在 `M:/android` 下执行 gradle。
- **Android SDK** 在 `D:\Dev_SDKs\Android_studio_SDK`（未设 ANDROID_HOME 环境变量），**JDK 21** 在 `D:\Dev_SDKs\jdk-21.0.12.1+1`（Capacitor 8 要求 Java 21，机器上的 JDK 17 会报「无效的源发行版：21」；已补装）。gradle 命令前需 `export JAVA_HOME`（指 JDK 21）与 `ANDROID_HOME`；`android/local.properties` 的 `sdk.dir` 必须用**正斜杠**（properties 文件里反斜杠是转义符，会被吞掉导致路径非法）。
- **端口 3000 / 3100 落在 Windows 动态排除段**（2945-3044、3079-3178，`netsh interface ipv4 show excludedportrange` 可查），dev server 用 `npm run dev -- --port 3456` 或其他未排除端口。
- **Maven 依赖走阿里云镜像**：`android/build.gradle` 的 buildscript 与 allprojects 仓库列表已把 `maven.aliyun.com`（google/central/public）放在 `google()`、`mavenCentral()` 之前——直连 `dl.google.com` 会 TLS 握手失败（Remote host terminated the handshake）。
- Capacitor 8：`npx cap init/add/sync` 生成并同步 `android/`；WebView 默认 `https://localhost` 源（安全上下文，`crypto.randomUUID` 可用）。
- Tauri 2：`npx tauri init` 生成 `src-tauri/`；窗口与标识配置在 `src-tauri/tauri.conf.json`（identifier `com.matrixflow.ai`）。

## Git 工作流现状

`main` 单分支直线历史，无远端、无标签、无分支保护。建议后续：功能改动开分支或至少保持现有 conventional commits 风格（`feat(模块): 描述`，正文列要点），并在每个可交付节点打 tag；每合并一批功能就更新 CHANGELOG.md 顶部新增条目（不要改写历史条目）。
