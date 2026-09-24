# 开发指南

命令历史核对：2026-09-07；平台范围更新：2026-09-09。架构与数据模型见 [ARCHITECTURE.md](ARCHITECTURE.md)，历史演进见 [CHANGELOG.md](CHANGELOG.md)。

**当前只开发 `matrixflow-native/` 的 Flutter Android/Windows。** React/Tauri/Capacitor 冻结保留；本文 Web 命令、类型和扩展示例只用于旧版维护，不要求 Flutter 新功能同步修改或构建 Web。最新步骤以 [Implementation Plan](IMPLEMENTATION_PLAN_2026-09-08.md) 第 5 节为准，下一包 WP03-N，WP21-N 已完成，WP20-W 已取消。新设置只接 Flutter 模型/Store/导入白名单/字典；新任务字段走 WP11，保留旧 v1 迁入。

## 环境与命令

### Web / 混合端（冻结版本）

| 命令 | 说明 |
|---|---|
| `npm install` | 安装 Node.js 依赖 |
| `npm run dev` | 开发服务器，http://localhost:3000（端口冲突时加 `-- --port 3456`） |
| `npm run build` | 生产构建，产物输出到 `dist/`（约 288 KB，gzip 87 KB，已消除分包警告） |
| `npm run preview` | 本地预览构建产物 |
| `npx tsc --noEmit` | 类型检查（构建脚本不含 tsc，需手动运行；当前通过） |

仅另行安排旧 Web 改动时的最低验证组合：`npm run build` + `npx tsc --noEmit`。

### 原生跨平台端（`matrixflow-native/`）

OS24 固定工具链是 Flutter **3.32.8** stable / Dart **3.8.1**（framework `edada7c56edf4a183c1735310e123c7f923584f1`，engine `ef0cd000916d64fa0c5d09cc809fa7ad244a5767`）。本机安装在 `D:\Dev_SDKs\Flutter_3.32.8`。不要把该目录写入系统 PATH，也不要覆盖回退安装 `D:\Dev_SDKs\Flutter_SDK`（Flutter 3.31.0-1.0.pre.88 / Dart 3.8.0-197.0.dev / revision `082a761570e89f67a56f50de1c4cb843a2e452af`）。`pubspec.yaml` 的 Dart 下限留在这个 dev 版本，只为让回退 SDK 仍能解析依赖；这不是 Flutter 3.16+ 或中间未测版本都可用的声明。机器可读声明见 `matrixflow-native/toolchain.json`。

```powershell
& "D:\Dev_SDKs\Flutter_3.32.8\bin\flutter.bat" test --no-pub
& "D:\Dev_SDKs\Flutter_3.32.8\bin\flutter.bat" analyze --no-pub
```

| 命令 | 说明 |
|---|---|
| `flutter pub get` | 按现有 lockfile 获取依赖。OS24 不升级依赖。 |
| `flutter test --no-pub` | 默认单元/Widget 测试。数量以当次输出和 HANDOFF 为准。设备集成测试另行 `flutter test integration_test/app_test.dart -d <device>`。 |
| `flutter analyze --no-pub` | 静态分析。 |
| `flutter build apk --debug` | Android 调试包。正式签名 release 使用打包脚本。 |
| `flutter build windows` | Windows 桌面构建。 |

原生端改动后的最低验证组合：`flutter test --no-pub` + `flutter analyze --no-pub`。下文命令里的 `flutter` 指 3.32.8 这套 SDK。

2026-09-07 原生审查与构建修复：Android debug、Android release（22.8MB APK）及 Windows release 构建全部通过（B01 已解决关闭，见 [报告 B01](NATIVE_BUG_REVIEW_2026-09-07.md)）。Flutter 构建和测试会重生成平台插件文件，建议同一工作区内顺序运行。

## 环境变量

无。2026-09-06 移除 Gemini 协议后，项目不再依赖任何环境变量或 `.env` 文件；AI 的地址 / 模型名 / 密钥全部由用户在设置面板填写并存于 Flutter SharedPreferences（旧 Web 为 localStorage）。

## 旧 Web 代码约定（冻结，仅供历史维护）

- 函数组件 + React.FC，props 用 interface 声明；事件回调以 `on` 前缀命名，由 App.tsx 下传。
- 业务逻辑集中在 App.tsx：新增功能一般先加 state（或复用既有 state）+ 处理函数，再经 props 接入组件。
- 所有用户可见文案走 `translations.ts` 的 `t` 对象，三种语言（en / zh / ja）必须同步补充。
- 类型集中定义在 `types.ts`；组件不自定义任务 / 设置相关类型。
- 样式用 Tailwind 工具类；主题色经 `--primary` CSS 变量注入，自定义动画曲线与关键帧在 index.html 内联配置中。

## Flutter 主线的常见扩展任务

以下文件均在 `matrixflow-native/lib/`，实际实施前按 Implementation Plan 领取一个子批次。

### 语言与文案

`l10n.dart` 补齐 en/zh/ja 字典，界面通过既有本地化入口读取；新增支持语言时同步模型/Store 默认解析与设置选项，以及 AI 提示词语言映射。WP21-N 已将已有三语象限名统一为完整紧急/重要维度，不增加语言种类。

### AI 服务商

按 WP01-N 建立预设与模型发现适配，服务商 ID 与三协议类型分开，不为每家兼容服务商增加一个协议枚举。复用 `ai_service.dart`、`models.dart` 与设置页，不改旧 Web。实时模型列表与 Key-only 可行性须逐家核验。

### 设置与任务字段

设置字段接 `models.dart`、`storage.dart` 默认/加载/导入白名单、设置页和 `l10n.dart`；缺省回退保护已有数据。可忽略的可选显示偏好可保留当前版本。任务信息新增字段必须按 WP11 的 schema/导出版本契约和整份导入校验处理，验证旧 v1 迁入与新 Flutter Android/Windows 往返；不要只加字段就承诺旧 Web 无损理解。

### 平台适配与验证

共享业务命令放 Store/服务；布局按窗口宽度，触摸与鼠标/键盘都需可用。平台插件调用做能力隔离，Windows 插件不得在 Android 启动时调用。通常运行 Flutter test/analyze；涉及平台插件或基础闭环验收时按计划构建 Android/Windows。不要为了 Flutter 包运行 Web build/tsc。

## 打包

正式主线只发行 Flutter Android/Windows；表中 Web、Tauri、Capacitor 命令保留给冻结旧版：

| 形态 | 工具 | 命令 |
|---|---|---|
| Web | Vite | `npm run build` → `dist/` |
| 桌面混合壳（Windows） | Tauri v2（`src-tauri/`，需 Rust） | `npm run tauri build` → `src-tauri/target/release/bundle/{msi,nsis}/` |
| 安卓混合壳 | Capacitor（`android/`） | `npx cap sync` → `cd android && ./gradlew.bat assembleDebug` |
| 安卓原生应用（自绘） | Flutter（`matrixflow-native/`） | `cd matrixflow-native && flutter build apk --debug` |
| Windows 原生桌面（自绘） | Flutter（`matrixflow-native/`） | `cd matrixflow-native && flutter build windows` |

本机环境要点（2026-09-24 OS24 用 Flutter 3.32.8 复核；2026-09-07 的路径记录保留在后）：

- **Flutter SDK**：固定 3.32.8 stable / Dart 3.8.1，位于 `D:\Dev_SDKs\Flutter_3.32.8`。回退目录 `D:\Dev_SDKs\Flutter_SDK` 不要升级。PowerShell 调用 `& "D:\Dev_SDKs\Flutter_3.32.8\bin\flutter.bat"`。
- **Android SDK 与 JDK**：Android SDK 在 `D:\Dev_SDKs\Android_studio_SDK`（platform android-36，build-tools 36.0.0，NDK 28.0.12433566）。本地验证的 `JAVA_HOME` 是 JDK 21 `D:\Dev_SDKs\jdk-21.0.12.1+1`。CI release workflow 使用 Temurin 17。工程为 AGP 8.7.3、Gradle 8.12、Kotlin 2.1.0，compileSdk 36，minSdk 23。`android/local.properties` 的 `sdk.dir` 必须用**正斜杠**。Visual Studio Community 2022 17.14.36（17.14.37502.11），Windows 10 SDK 10.0.26100.0。Android Studio 未安装；SDK 与 JDK 足够完成本地 doctor 和构建。
- **项目路径若含非 ASCII 字符或空格**：AGP 依赖解析可能异常，可靠做法是映射 ASCII 盘符后构建：`subst M: "D:\Dev_project\martix"`，然后在 `M:/android` 下执行 gradle。
- **端口 3000 / 3100 落在 Windows 动态排除段**（2945-3044、3079-3178，`netsh interface ipv4 show excludedportrange` 可查），dev server 用 `npm run dev -- --port 3456` 或其他未排除端口。
- **Maven 依赖走阿里云镜像**：`android/build.gradle` 的 buildscript 与 allprojects 仓库列表已把 `maven.aliyun.com`（google/central/public）放在 `google()`、`mavenCentral()` 之前——直连 `dl.google.com` 会 TLS 握手失败。
- **共享 Flutter 约定**：Android/Windows 共用 `models.dart`、`l10n.dart`、`storage.dart` 的演进实现。新 Flutter 继续读取旧 v1；不再给 React 派同功能包。任务备份格式按 WP11 演进，自动同步另属 WP18。

## Git 工作流现状

`main` 单分支直线历史，无远端、无标签、无分支保护。建议后续：功能改动开分支或至少保持现有 conventional commits 风格（`feat(模块): 描述`，正文列要点），并在每个可交付节点打 tag；每合并一批功能就更新 docs/CHANGELOG.md 顶部新增条目（不要改写历史条目）。
