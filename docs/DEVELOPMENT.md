# 开发指南

当前只开发 `matrixflow-native/` 的 Flutter Android 与 Windows。React、Tauri、Capacitor 冻结保留。本文后部的 Web 命令只在有人另行安排旧版维护时使用，Flutter 功能包不跑这组检查。

架构见 [ARCHITECTURE.md](ARCHITECTURE.md)。文档地图见 [README.md](README.md)。当前交接见 [HANDOFF.md](HANDOFF.md) 顶部。早期工作包步骤表在 [Implementation Plan](IMPLEMENTATION_PLAN_2026-09-08.md)，其中的「下一包」字样是历史派单。WP10、WP29 和界面实验继续暂停。

## 主线事实

- 任务、看板、不含密钥的 AI 配置和设置在本机 SharedPreferences。核心键是 `matrixflow-tasks`、`matrixflow-boards`、`matrixflow-config`、`matrixflow-settings`。
- API 密钥在系统凭据中。默认 JSON 备份省略 `customApiKey`；设置里明确选择包含时，文件中是明文。
- 分类、分组和拆解把当次任务标题发到用户配置的端点。预设与自定义地址见 [AI 预设](AI_PROVIDER_PRESETS.md)。
- 默认备份是 ExportData v2，并继续读取 v1。v1 降级有损。契约见 [备份格式](BACKUP_FORMAT.md)。
- 源码在本仓库。没有 remote，因此没有已配置的托管测试版或稳定发行。

项目不读取 `.env`。地址、模型名和密钥由用户在设置里填写。

## 固定 SDK

OS24 固定 Flutter **3.32.8** stable / Dart **3.8.1**（framework `edada7c56edf4a183c1735310e123c7f923584f1`，engine `ef0cd000916d64fa0c5d09cc809fa7ad244a5767`）。本机安装在 `D:\Dev_SDKs\Flutter_3.32.8`。不要把该目录覆盖到回退安装 `D:\Dev_SDKs\Flutter_SDK`（Flutter 3.31.0-1.0.pre.88 / Dart 3.8.0-197.0.dev / revision `082a761570e89f67a56f50de1c4cb843a2e452af`）。`pubspec.yaml` 的 Dart 下限留在这个 dev 版本，只为让回退 SDK 仍能解析依赖。机器可读声明见 `matrixflow-native/toolchain.json`。

2026-09-25 在基线上执行 `powershell -File scripts\build_release.ps1 -ValidateOnly -ExpectedTag v1.0.0+1`，输出的 Flutter 与 Dart 版本和上述修订号一致，并写明与 `toolchain.json` 匹配。该命令没有构建，也没有写产物。

下文的 `flutter.bat` 指这套固定 SDK。PATH 上的 `flutter` 只有在 `flutter --version` 给出同一修订号时才是同一工具链。

## Flutter 命令

工作目录是 `matrixflow-native/`，除非某条命令写明在仓库根目录执行。

| 命令 | 作用 |
|---|---|
| `& "D:\Dev_SDKs\Flutter_3.32.8\bin\flutter.bat" pub get` | 按现有 lockfile 获取依赖。工具链包不升级依赖。 |
| `& "D:\Dev_SDKs\Flutter_3.32.8\bin\flutter.bat" analyze --no-pub` | 静态分析。 |
| `& "D:\Dev_SDKs\Flutter_3.32.8\bin\flutter.bat" test --no-pub` | 默认单元与 Widget 测试。数量看当次输出。 |
| `& "D:\Dev_SDKs\Flutter_3.32.8\bin\flutter.bat" test --no-pub integration_test/app_test.dart` | mock 集成入口。workflow 在 Windows debug job 里使用同一条命令。它不代替真机操作。 |
| `& "D:\Dev_SDKs\Flutter_3.32.8\bin\flutter.bat" build apk --debug` | Android 调试包。`.github/workflows/pr.yml` 使用这条命令，并设置 `REQUIRE_RELEASE_SIGNING=false`。 |
| `& "D:\Dev_SDKs\Flutter_3.32.8\bin\flutter.bat" build windows --debug` | Windows 调试构建。同一 workflow 在此之前会执行 `flutter config --enable-windows-desktop`。 |
| `& "D:\Dev_SDKs\Flutter_3.32.8\bin\flutter.bat" run -d windows` | 在本机 Windows 桌面启动调试会话。 |

代码改动的最低本地检查是 `analyze --no-pub` 与 `test --no-pub`。只改文档时核对链接和命令，不把未重跑的历史测试数字写成新的验收。

`flutter build apk --release` 在未设置 `REQUIRE_RELEASE_SIGNING=true` 时，Gradle 会在缺少正式证书的情况下使用 debug 签名。那种 APK 不是正式发行物。

## 发行脚本

在仓库根目录执行。脚本自身会选择 `D:\Dev_SDKs\Flutter_3.32.8`。

```powershell
powershell -File scripts\build_release.ps1 -ValidateOnly -ExpectedTag v1.0.0+1
powershell -File scripts\build_release.ps1 -Platform Windows -ExpectedTag v1.0.0+1
```

`pubspec.yaml` 的版本必须是 `X.Y.Z+N`。当前是 `1.0.0+1`，所以 `-ExpectedTag` 接受 `v1.0.0` 或 `v1.0.0+1`。

`-ValidateOnly` 只打印计划。2026-09-25 的这次输出是：Android 产物名将是 `matrixflow-v1.0.0+1-android.apk`，签名材料缺失；Windows 产物名将是 `matrixflow-v1.0.0+1-windows-portable.zip`，且没有 Authenticode。因此现在执行 `-Platform Android` 或 `-Platform All` 会在构建前拒绝。Windows 单平台命令可以打出未签名绿色包，该包仍然不是稳定发行。

正式 Android 材料放在 `matrixflow-native/android/key.properties`，模板是 [key.properties.example](../matrixflow-native/android/key.properties.example)。不要把真实口令或 keystore 写入仓库。

产物目录是仓库根下的 `release_dist\matrixflow-v1.0.0+1\`。一次运行只保留这次选择的平台文件和 `SHA256SUMS.txt`。

## 本机 Android 与 Windows 工具

这些路径来自 `toolchain.json` 所记录的 2026-09-24 验证机：

- Android SDK：`D:\Dev_SDKs\Android_studio_SDK`（platform android-36，build-tools 36.0.0，NDK 28.0.12433566）。
- 本地 JDK：`D:\Dev_SDKs\jdk-21.0.12.1+1`。发布 workflow 使用 Temurin 17。
- 工程：AGP 8.7.3、Gradle 8.12、Kotlin 2.1.0，compileSdk 36，minSdk 23。`android/local.properties` 的 `sdk.dir` 使用正斜杠。
- Visual Studio Community 2022 17.14.36，Windows 10 SDK 10.0.26100.0。

Flutter 的 Android 工程使用 `flutter build`，不把 `matrixflow-native/android` 下尚未生成的 `gradlew.bat` 当成日常入口。

## 冻结的 Web / Tauri / Capacitor

根目录 `package.json` 的脚本只有 `dev`、`build`、`preview`。没有 `tauri` 脚本。

| 命令 | 作用 |
|---|---|
| `npm install` | 安装 Node 依赖 |
| `npm run dev` | Vite 开发服务器。`vite.config.ts` 把端口设为 3000 |
| `npm run dev -- --port 3456` | 3000 不可用时改端口 |
| `npm run build` | Vite 生产构建，输出到 `dist/` |
| `npm run preview` | 预览 `dist/` |
| `npx tsc --noEmit` | 类型检查。构建脚本本身不运行 tsc |
| `npx tauri build` | 冻结桌面壳。等价意图的旧写法 `npm run tauri build` 在当前 `package.json` 里没有对应脚本 |
| `npx cap sync` | 冻结 Capacitor 同步。随后在根目录 `android/` 执行 `.\gradlew.bat assembleDebug` |

Windows PowerShell 5.1 不支持 `&&`。进入旧 Android 壳时分两条执行：`Set-Location android`，然后 `.\gradlew.bat assembleDebug`。

本文件这一节的命令与 `package.json`、`vite.config.ts` 和根目录 `android\gradlew.bat` 对照过。OS27 文档子批次没有重新执行 `npm install`、Vite、tsc、Tauri 或 Capacitor。

旧 Web 的代码约定仍然有效，仅供有人维护冻结树时使用：业务集中在 `App.tsx`，文案在 `translations.ts`，类型在 `types.ts`，样式使用 Tailwind。新的 Flutter 设置和任务字段不要再同步这三处。

## 常见 Flutter 扩展

文件都在 `matrixflow-native/lib/`。领取范围以当前交接为准。

- 文案改 `l10n.dart` 的 en/zh/ja。OS27 的文案子批次独占这个文件时，文档子批次不改它。
- AI 服务商沿用 `ai_presets.dart` 与 `ai_service.dart` 的三种协议。新增预设前先核对真实端点，不要为每一家兼容服务商增加一种协议枚举。
- 设置字段同时改模型、Store 默认值与加载、导入白名单、设置页和三语字典。
- 任务新字段保持 v1 可读、v2 可导出，并在 [BACKUP_FORMAT.md](BACKUP_FORMAT.md) 写明 v1 降级会丢失什么。

## Git

本地可以有工作分支和 worktree。`git remote` 为空，也没有 tag。提交说明保持 `feat(模块): 描述` 这一类前缀。变更记录由集成时追加到 `docs/CHANGELOG.md` 顶部，不改写已有条目。作者邮箱不是已经公布的维护者联系方式。
