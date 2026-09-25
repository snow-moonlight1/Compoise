# OS26 — 发行身份、构建清单与公开前审计

日期：2026-09-25。只实施 OS26。未改 Windows 单实例逻辑、Store、设置页、任务 widget 或提醒业务代码，也未改 `AGENTS.md`、`docs/HANDOFF.md`、`docs/ARCHITECTURE.md`、`docs/CHANGELOG.md` 和开源准备计划（公共文档留给集成人）。冻结的 React / Tauri / Capacitor 未改动。未发布任何 Release、未改 `applicationId`、未生成或提交任何秘密、未推送。

## 基线

- 独立 worktree：`D:\Dev_project\martix-wt-os26`
- 分支：`os26-release`，从 `0aec23f176a15eae398dbf292086e6827cea74da` 创建
- 工具链：OS24 固定的 Flutter 3.32.8 stable / Dart 3.8.1（framework `edada7c56edf4a183c1735310e123c7f923584f1`，engine `ef0cd000916d64fa0c5d09cc809fa7ad244a5767`），本机 `D:\Dev_SDKs\Flutter_3.32.8`
- 仓库当前无 remote。本地无法代替 GitHub 托管 runner，故 workflow 的远端执行一律标为未测。

## 1. 现状核对（发行身份、签名、升级路径）

### Android

- `matrixflow-native/android/app/build.gradle.kts`：`applicationId = "com.matrixflow.app"`，`namespace = "com.matrixflow.matrixflow_native"`。`MainActivity` 位于 `android/app/src/main/kotlin/com/matrixflow/matrixflow_native/MainActivity.kt`。Android 只把 `applicationId` 当作应用身份，`namespace` 只影响 R 类与清单合并，不改变安装身份。
- 冻结的旧壳同样用 `com.matrixflow.app`（根目录 `android/app/build.gradle` 与 `capacitor.config.ts`）。更早的 Flutter 工程值是 `com.matrixflow.matrixflow_native`，见 [ANDROID_PACKAGE_MIGRATION.md](ANDROID_PACKAGE_MIGRATION.md)。
- 升级保留数据：只有 **同 applicationId + 同签名证书** 才是原位升级。`com.matrixflow.app` 与 `com.matrixflow.matrixflow_native` 各自有独立沙箱；卸载旧版会删除旧沙箱里的任务、设置和密钥。当前唯一受支持的旧数据路径仍是设置页 JSON 导出/导入（本包未改）。
- 签名门槛：`verifyFormalReleaseSigning` 只在 `REQUIRE_RELEASE_SIGNING=true` 且 release keystore 不存在时失败（OS25 实施；本包只把错误文案补上模板与文档指引，门槛逻辑、任务挂载点和 `CI` 环境变量处理未改）。
- 本机风险实证：工作区遗留的 `build/app/outputs/flutter-apk/app-release.apk` 用 `apksigner verify --print-certs` 读取，证书是 `CN=Android Debug`。也就是说"release 构建成功"本身不代表可发行，旧脚本会把这种包复制进发行目录。本包用签名门槛 + 证书校验堵住它。

### Windows

- `windows/CMakeLists.txt`：`BINARY_NAME matrixflow_native`，产物 `matrixflow_native.exe`。
- `windows/runner/Runner.rc`：`CompanyName=com.matrixflow`、`ProductName`/`FileDescription`=`MatrixFlow AI`、`OriginalFilename=matrixflow_native.exe`、`LegalCopyright=Copyright (C) 2026 com.matrixflow. All rights reserved.`。数值 `FILEVERSION` 由 Flutter 传入的 `FLUTTER_VERSION_MAJOR/MINOR/PATCH/BUILD` 生成（例如 `1.0.0.1`），版本字符串沿用 `FLUTTER_VERSION`（`1.0.0+1`），细节见第 6 节。
- Windows 侧没有任何代码签名（无 Authenticode），发行时必须如实披露；`RELEASE_MANIFEST.txt` 与 Release 说明都会写明。

### 版本与 CI

- `pubspec.yaml` 现在是 `version: 1.0.0+1`。本包定义的 tag 约定：`vX.Y.Z`，也接受 `vX.Y.Z+N`；tag 与 pubspec 不一致时打包脚本直接拒绝。
- `pr.yml`（OS25）：无密钥 PR/push 检查，权限 `contents: read`，四个 job 固定 3.32.8，未在本包修改。
- `release.yml`（本包修改前）：tag/manual 触发；问题点 —— 权限是**整个 workflow** 的 `contents: write`；`${{ secrets.* }}` 直接插进 shell 文本；Android、Windows 都在自己的 job 里各自写 `release_artifacts`，`publish` 用 `sha256sum *` 重算校验和，因此单平台重跑会保留旧产物、清单只覆盖当次 glob 且不含 build number；缺签名的门槛只在 Gradle 侧，脚本层没有拦截。

## 2. 本包改动

| 文件 | 改动 |
|---|---|
| `scripts/build_release.ps1` | 重写。只做"一次一个版本"的干净 staging：解析 pubspec 的 `X.Y.Z+N`、校验 `-ExpectedTag`、重建 `release_dist/matrixflow-v<ver>+<build>/`、签署前置门槛（本地缺签名直接拒绝，不落到 debug 签名）、APK 证书与包名/versionCode/versionName 校验、Windows FileVersion 与 Authenticode 状态核对、只对本轮产物生成 `SHA256SUMS.txt` 与 `RELEASE_MANIFEST.txt`、目录内出现未预期文件即失败；新增 `-ValidateOnly`（只核对版本/标签/计划，不构建、不写文件）。密码值从不回显，只报告凭据来源路径。 |
| `.github/workflows/release.yml` | 权限收敛为 workflow 级 `contents: read`，只有 `publish-release` job 有 `contents: write`；新增 `preflight` job 用脚本 `-ValidateOnly` 核对 tag 与 pubspec；Android 密钥改经 `env:` 传入并在构建后 `if: always()` 删除 `key.properties`/`release.jks`；新增 `apksigner` 反 debug 证书校验；Windows job 核对 ProductName/FileVersion 并断言 Authenticode 仍为 NotSigned；`publish` job 校验产物集合（必须正好一个 APK + 一个 ZIP）后生成 `SHA256SUMS.txt`，写入披露签名状态的 Release 说明，保持 `draft: true`。 |
| `matrixflow-native/android/app/build.gradle.kts` | 只扩展 `verifyFormalReleaseSigning` 的错误文案（指向模板与本文件）。门槛条件、任务挂载点、签名配置逻辑未改，`applicationId`/`namespace` 未改。 |
| `matrixflow-native/android/key.properties.example` | 新增签名模板（占位值，无真实凭据）。`.gitignore` 已忽略 `key.properties`/`keystore.properties`/`*.jks`/`*.keystore`/`*.pfx`/`*.p12`，模板文件名不在忽略列表内。 |
| `matrixflow-native/test/os26_release_test.dart` | 新增 5 项契约：workflow 权限与秘密不进入 shell 文本、单平台 staging 与签名披露、脚本的干净 staging/签名门槛/校验和来源、模板与 Gradle 门槛一致、Windows 元数据与 pubspec 版本一致。 |
| `docs/OS26_NOTES.md` | 本文件。 |

### 发行清单契约（可复核）

- 目录：`release_dist/matrixflow-v1.0.0+1/`（同一目录每次运行先删除再重建，Android-only、Windows-only、All 和重跑互不叠加）。
- 产物名：`matrixflow-v<version>+<build>-android.apk`、`matrixflow-v<version>+<build>-windows-portable.zip`（文件名带 build number，避免同一 SemVer 的两次构建互相覆盖）。
- `SHA256SUMS.txt`：只列本轮实际产出的文件，格式 `<小写 sha256>␠␠<文件名>`（GNU `sha256sum` 标准输出，`sha256sum -c` 可直接校验），不包含其它平台或历史文件。
- `RELEASE_MANIFEST.txt`：版本、build、tag、平台、UTC 时间、git 提交/分支/是否脏、Flutter 与 Dart 版本、`toolchainPinMatches`、签名来源、Android 侧 `applicationId`/`namespace`/`apkSignatureDN`/`apkPackage`/`apkVersionCode`/`apkVersionName`、Windows 侧 `productName`/`fileVersion`/`legalCopyright`/`authenticode`/`zipEntries`，以及本轮产物哈希。

## 3. 构建清单与验收证据

### 3.1 实测通过（Windows-only 全流程，两次运行）

| # | 命令 | 结果 |
|---|---|---|
| 1 | `scripts\build_release.ps1 -Platform Windows -ExpectedTag v1.0.0`（干净 worktree，先 `flutter pub get`） | 退出码 0。Windows release 构建 159.2s 成功；产物 `release_dist/matrixflow-v1.0.0+1/matrixflow-v1.0.0+1-windows-portable.zip`（13,072,810 字节）；`SHA256SUMS.txt` 只列这一个文件；`RELEASE_MANIFEST.txt` 记录 `productName=MatrixFlow AI`、`fileVersionString=1.0.0+1`、`fileVersionNumeric=1.0.0.1`、`legalCopyright=Copyright (C) 2026 com.matrixflow. All rights reserved.`、`authenticode=NotSigned`、`zipEntries=17`、`gitCommit=0aec23f1…`、`toolchainPinMatches=True` |
| 2 | 重跑前在 staging 目录放入两个诱饵（`matrixflow-v1.0.0+1-android.apk`、`stale-extra-file.txt`），再跑 `-Platform Windows -ExpectedTag v1.0.0` | 退出码 0。日志先出现 `Cleaning previous staging directory`；结束后 staging 内只有 ZIP、`SHA256SUMS.txt`、`RELEASE_MANIFEST.txt`，**诱饵既未被复制也未被写进校验和**，即"重跑不混旧产物"成立 |
| 3 | `-ValidateOnly -ExpectedTag v1.0.0`（All 与 Windows 两种形态） | 退出码 0，只打印版本/标签/平台/签名前置状态，不创建 `release_dist` 内容（发出即退出） |

### 3.2 拒绝路径（实测）

| # | 命令 | 结果 |
|---|---|---|
| 4 | `-Platform Android -ExpectedTag v1.0.0`（本机无 keystore） | 退出码 1，`Formal release signing credentials are required … Refusing to build a debug-signed release APK.`，失败发生在**任何构建之前** |
| 5 | `-Platform All`（本机无 keystore） | 退出码 1，同样在构建前失败；不会"先偷偷产出 Windows 包"再失败 |
| 6 | `-ExpectedTag v1.1.0` | 退出码 1：`-ExpectedTag points at v1.1.0 but pubspec.yaml declares 1.0.0+1` |
| 7 | `-ExpectedTag v1.0.0+1` | 通过（接受带 build number 的 tag 形态） |
| 8 | `apksigner verify --print-certs` 读取本机遗留的 `app-release.apk` | 证书 DN 实测 `C=US, O=Android, CN=Android Debug`。说明"release 构建成功"并不等于可发行，脚本的这条判定因此在真实 APK 上验证过（正式签名 APK 未测） |

### 3.3 未测（本包内无法完成，见第 6 节）

| 场景 | 原因 |
|---|---|
| Android-only 产出 APK 并生成完整 SHA256SUMS | 无正式 keystore（属持有人秘密，本包不生成） |
| All 产出 APK + ZIP 的完整清单 | 同上 |
| 正式签名 APK 通过 `apksigner`/`aapt2` 校验的正向路径 | 同上（只验证了解析逻辑与 debug 包判定） |
| GitHub Actions 的任何 job（preflight / android / windows / publish） | 仓库无 remote，托管 runner 未执行 |
| Windows Authenticode 签名与时间戳 | 无证书 |
| 设备上覆盖安装保留数据 | 无 Android 设备 |

### 3.4 workflow 与脚本的本地功能验证（仓库无 remote 时的替代证据）

| 检查 | 方法 | 结果 |
|---|---|---|
| YAML 结构 | 本机 PyYAML 6.0.2 解析两个 workflow | 解析通过；`release.yml` 的 jobs 为 `preflight` → `build-android`/`build-windows` → `publish-release`；顶层 `permissions: contents: read`，只有 `publish-release` 是 `contents: write` |
| bash 语法 | 本机 Git Bash 对提取出的 **9 段** `shell: bash` 脚本跑 `bash -n`（`pr.yml` 的 5 段一并跑） | 14/14 通过 |
| 发行说明步骤 | 在临时目录真实执行 publish job 的 `Write release notes…`（`RELEASE_TAG=v1.0.0`） | 退出 0，生成的 Markdown 首行无缩进，包含 tag 与“not code-signed”披露 |
| 产物集合与校验和 | 真实执行 `Verify the artifact set and generate SHA256SUMS`：1 个 APK + 1 个 ZIP + 说明文件 | 退出 0，`SHA256SUMS.txt` 2 行，哈希与 Python `hashlib` 独立计算一致 |
| 拒绝多余产物 | 同一步，额外放入 `notes-backup.txt` | 退出 1：`Refusing to publish: expected exactly one APK and one Windows ZIP, nothing else.` |
| 拒绝缺平台 | 同一步，只留 APK | 退出 1 |
| 拒绝不带 build number 的旧命名 | 同一步，额外放入 `matrixflow-v1.0.0-android.apk` | 退出 1（文件名不匹配 `v<版本>+<build>` 命名） |
| CI 签名注入机制 | 真实执行 `Require release signing credentials`（四个**占位**环境变量，非真实凭据） | 退出 0，写出的 `release.jks` 与 `key.properties` 内容与占位值一致；**stdout 中不出现任何占位口令** |
| CI 签名缺失拦截 | 同一步，去掉 `ANDROID_KEY_ALIAS` | 退出 1，出现 `Refusing to publish a debug-signed APK.`，且 stdout 不泄露其它占位口令 |
| CI 清理 | 真实执行 `Remove release signing material` | 退出 0，两个临时文件都被删除 |

说明：本机 Git Bash 的 `sha256sum` 输出 `<哈希> *<文件名>`（二进制模式标记），GitHub 的 ubuntu runner 输出 `<哈希>  <文件名>`；两种都是 GNU 标准格式，`sha256sum -c` 都能校验。本地 PowerShell 打包脚本固定输出两空格格式，与 runner 一致。

### 3.5 测试与静态分析（固定 SDK `D:\Dev_SDKs\Flutter_3.32.8`）

| 命令 | 结果 |
|---|---|
| `flutter test --no-pub test/os26_release_test.dart` | **5/5**（本包新增契约） |
| `flutter test --no-pub test/os24_toolchain_test.dart test/os25_ci_test.dart` | **7/7**，证明改过的 `release.yml` 与 `build_release.ps1` 没有破坏 OS24 工具链契约和 OS25 无密钥/签名门槛契约 |
| `flutter test --no-pub test/os26_release_test.dart test/os24_toolchain_test.dart test/os25_ci_test.dart`（提交前对暂存内容的最终复跑） | **12/12** |
| `flutter test --no-pub` | **500/500**（基线 495 + 本包 5） |
| `flutter analyze --no-pub` | **No issues found** |
| 本机 PyYAML 解析 workflow、Git Bash `bash -n` 校验 14 段脚本、9 项 workflow 步骤功能验证 | 见 3.4，全部通过 |
| `gradlew.bat --no-daemon :app:verifyFormalReleaseSigning`（`REQUIRE_RELEASE_SIGNING=true` / `false`） | **1 / 0**，见 3.6 |

### 3.6 Android 签名门槛（Gradle 直连，OS26 worktree）

工作区的 `gradlew` / `gradle-wrapper.jar` / `local.properties` 被 `matrixflow-native/android/.gitignore` 忽略，新 worktree 不含这些机器本地文件；从主工作区复制了这四个忽略文件后执行（复制内容未被 Git 跟踪，未进入提交）。

| 命令（`matrixflow-native/android/`，`JAVA_HOME=D:\Dev_SDKs\jdk-21.0.12.1+1`） | 结果 |
|---|---|
| `gradlew.bat --no-daemon :app:verifyFormalReleaseSigning`，`REQUIRE_RELEASE_SIGNING=true` | **BUILD FAILED，退出码 1**，2m34s；失败信息含新版文案：`Formal release signing credentials are required. Refusing to publish a debug-signed APK. Provide android/key.properties (template: android/key.properties.example) … See docs/OS26_NOTES.md.` |
| 同上，`REQUIRE_RELEASE_SIGNING=false` | **BUILD SUCCESSFUL，退出码 0**（keyless debug/PR 路径未被误阻） |

两次运行都说明改过的 `build.gradle.kts` 能配置、编译并按门槛工作；未改 `CI` 环境变量相关逻辑，`CI=true` 不再在配置阶段抛错的 OS25 行为保持不变（`System.getenv("CI")` 仍不出现在该文件，见 3.5 的契约测试）。

## 4. 公开前审计

### 4.1 Git 全历史秘密扫描（脱敏）

方法（可复现，只在本机 `%TEMP%` 运行，不写入仓库）：导出 `git log --all --no-color --format='COMMIT %H %s' -p`（73 个提交、全部本地 ref，含已合入 main 的独立分支历史，112,145 行），再用一次性脚本按 11 类模式扫描，**只输出“模式 + 文件路径 + 命中数”**，不打印也不保存任何命中原文。扫描全文临时文件在本包收尾时删除。

| 模式 | 命中 | 位置 | 结论 |
|---|---|---|---|
| 私钥块（`-----BEGIN ... PRIVATE KEY-----`） | 0 | — | 未出现 |
| AWS / GitHub / Slack / Google / OpenAI / Anthropic 形态密钥 | 0 | — | 未出现 |
| JWT 形态串 | 0 | — | 未出现 |
| 长 base64 块（≥400 字符，可能为 keystore 内容） | 0 | — | 未出现 |
| `.env` 文件 | 0 | — | 仓库从未提交 |
| `key.properties` / `keystore.properties` / `*.jks` / `*.keystore` / `*.p12` / `*.pfx` 文件 | 0 | — | `git rev-list --objects --all` 中无此类路径 |
| 证书/密钥关键字引用 | 15 | 旧版 `.github/workflows/release.yml`、`docs/RELEASE_PLAN.md`、根壳与 native 的 `.gitignore` | 全是忽略规则、文档示例和 CI 变量名，无凭据值 |
| `api_key` / `secret` / `token` / `password` 形式的赋值且值 ≥16 字符 | 11 | 7 个测试/探针文件（`foundation_regression_test.dart`、`os08_os09_credential_test.dart`、`os10_model_discovery_test.dart`、`os11_protocol_capability_test.dart`、`widget_regression_test.dart`、`test/review/preopensource_review_probe.dart`、`test/review/wp28_review_probe.dart`） | 11/11 均为 `syn…` 开头的合成占位串（长度 18–29），无真实密钥 |

结论：本包覆盖范围内**没有需要在公开前清理的凭据**，也没有重写任何 Git 历史。残余未决见第 6 节（托管侧 secret scanning 只能在有 remote 后执行）。

### 4.2 依赖许可证

方法：读 `pubspec.lock` 的 88 个解析版本，逐个打开 pub 缓存中对应包的 `LICENSE` 首部并分类。

| 直接依赖（锁定版本） | 许可证 |
|---|---|
| provider 6.1.5+1 | MIT |
| http 1.6.0 | BSD-3-Clause |
| shared_preferences 2.5.3 | BSD-3-Clause |
| flutter_secure_storage 10.3.4 | BSD-3-Clause |
| path_provider 2.1.5 | BSD-3-Clause |
| file_picker 8.3.7 | MIT |
| flutter_local_notifications 19.5.0 | BSD-3-Clause |
| timezone 0.10.1 | BSD-2-Clause |
| window_manager 0.5.2 | MIT |
| tray_manager 0.5.3 | MIT |
| flutter_lints 5.0.0（dev） | BSD-3-Clause |

传递依赖同为宽松许可（Apache-2.0 / MIT / BSD 族），唯一例外是 `dbus 0.7.12` = **MPL-2.0**。

- `dbus` 只被 `flutter_local_notifications_linux` 使用。`.flutter-plugins-dependencies` 与两端生成的 `GeneratedPluginRegistrant.java` / `generated_plugins.cmake` 显示 Android 与 Windows 都没有注册 dbus 或任何 Linux 实现，因此它不进入这两个平台的产物；但它仍会因 Flutter 的许可证聚合出现在 APK 的 `assets/flutter_assets/NOTICES.Z`（解开约 1.72 MB）中，其中包含 `dbus` 与 `fallback_root_certificates` 的 MPL-2.0 条文。MPL-2.0 是文件级 copyleft，保留许可文本即可，且本项目整体以 MIT 开源，不构成阻塞。
- 项目自身：根目录 `LICENSE` 为 MIT（`Copyright (c) 2026 MatrixFlow AI Contributors`），`matrixflow-native/` 下没有独立 LICENSE。
- 发行物附带声明：APK 内含 Flutter 生成的 `NOTICES.Z`，覆盖 pub 依赖许可证；Windows 绿色包由 Flutter 的同样机制携带。尚未生成 distribution 级 `THIRD_PARTY_NOTICES` 汇总文件（列入第 6 节未决）。

### 4.3 已知漏洞通告

- 方法：`POST https://api.osv.dev/v1/querybatch`（Pub 生态），提交 `pubspec.lock` 全部 88 个包的名称与锁定版本，2026-09-25 执行。
- 结果：`checked=88 packages_with_advisories=0`。
- 局限：OSV 只覆盖已被报告到该库的公告，不代表“无漏洞”；**Maven/Gradle 侧依赖（AGP、Kotlin、AndroidX、desugar、Gradle 插件及其传递库）与 Visual Studio / Windows SDK 组件未查询**，属第 6 节未决项（建议在有托管仓库后接入 Dependabot 的 `pub` 与 `gradle` 两条生态，或手工跑一次依赖检查工具）。

### 4.4 字体与图标来源

- Android 图标：5 个 `android/app/src/main/res/mipmap-*/ic_launcher.png` 与本机用同一 SDK 3.32.8 运行 `flutter create` 生成的模板文件 **逐字节相同**（SHA256 一致），来源是 Flutter 官方模板（BSD-3-Clause, The Flutter Authors）。当前仍是模板默认图标，没有自定义品牌图标。
- Windows 图标：`windows/runner/resources/app_icon.ico` 同样与模板逐字节相同。
- 托盘图标：`assets/tray_icon.ico` 与上面的 `app_icon.ico` SHA256 相同（`c098d3fc85cacff98b8e69811b48e9f0d852fcee278132d794411d978869cbf8`），即复用 Flutter 模板图标，不含第三方素材。
- 字体：`pubspec.yaml` 未声明自定义字体，应用只通过 `uses-material-design: true` 使用引擎的 Material Icons 矢量字体；APK 中实测打包 `assets/flutter_assets/fonts/MaterialIcons-Regular.otf`（1,645,184 字节）。
- **发现**：Flutter 3.32.8 自带的 `materialicons_license.txt` 通篇是 **CC-BY 4.0（Attribution 4.0 International）**，不是 Apache-2.0；`docs/RELEASE_PLAN.md` 第 31 行“Material Icons | Apache 2.0”与本机 SDK 事实不符。CC-BY 4.0 要求署名，而 APK 的 `NOTICES` 中既没有 “Material Design” 也没有 “Roboto” 字样，说明 Flutter 的许可证聚合未包含该字体署名。处理建议见 5.5。
- 系统字体（Roboto / Segoe UI / Noto）没有打进包体，按平台系统字体渲染；SDK 缓存里的 `roboto_license.txt` 是 Apache-2.0，仅用于说明 SDK 自带资源。

## 5. 需要持有人决定的事项（现状 / 选项 / 迁移影响）

本包不代替持有人决定。以下每一项都给出可直接审查的现状、选项和拟修改文件；**在得到决定前不改 applicationId、不生成或提交秘密、不发布 Release**。

### 5.1 Android applicationId / 包名

- 现状：`applicationId = "com.matrixflow.app"`，`namespace = "com.matrixflow.matrixflow_native"`，`MainActivity` 包路径同上；更早的 Flutter 值是 `com.matrixflow.matrixflow_native`；冻结的旧壳也是 `com.matrixflow.app`。本仓库无 remote、无 tag、无 Release，因此"是否已经分发给真实用户"只有持有人知道。
- 选项 A（保持 `com.matrixflow.app`）：旧 `com.matrixflow.matrixflow_native` 用户导出 JSON 后再导入一次；两个包可以共存；签名可以与旧版不同（不是同一应用）。
- 选项 B（改回 `com.matrixflow.matrixflow_native`）：只有"新包尚未对外分发，且想用旧签名证书原位升级"时才划算。一旦 `com.matrixflow.app` 已发给真实用户，改回去会把那批用户变成另一个沙箱，且必须同时用旧签名与旧 keystore。
- 选项 C（换成持有人自有域名的正式包名）：两个旧包都只能靠 JSON 迁移，商店需要新条目。
- 迁移影响（B/C）：`android/app/build.gradle.kts` 的 `applicationId`（B/C）与 `namespace`、必要时的 Kotlin 源目录；`docs/ANDROID_PACKAGE_MIGRATION.md` 需要同步。**本包一个字节都没改这条路径。**
- 需要持有人回答：新包是否已分发给任何真实用户？最终包名选哪个？旧签名证书是否还在手上？

### 5.2 Android 正式签名证书

- 现状：本机与仓库都没有 release keystore。`REQUIRE_RELEASE_SIGNING=true` 时，Gradle 门槛和打包脚本都会拒绝（本包实测退出码 1，且发生在任何构建之前）。
- 选项 A（推荐）：持有人离线用 `keytool` 生成 release keystore，自己保管文件与口令，把 base64 与三项口令填入 GitHub Actions secrets：`ANDROID_KEYSTORE_BASE64`、`ANDROID_STORE_PASSWORD`、`ANDROID_KEY_PASSWORD`、`ANDROID_KEY_ALIAS`（workflow 已在用这四个名字，模板见 `android/key.properties.example`）。
- 选项 B：改用云签名/硬件密钥（例如商店侧代签），需要额外的 Gradle 配置。
- 迁移影响：**Android 只按 `applicationId + 签名证书` 判定升级**，首次公开发布后证书不可更换；签名密钥丢失等于老用户无法升级。因此这一步必须由持有人执行，本包不生成、不保存、不代填任何凭据。
- 拟修改文件：选项 A 无代码改动；选项 B 需要改 `android/app/build.gradle.kts` 的 `signingConfigs`。

### 5.3 Windows 代码签名

- 现状：没有 Authenticode 证书，exe 与绿色包都是未签名，SmartScreen 可能告警。workflow 会断言"仍未签名"，一旦未来加了签名步骤就会失败提醒同步更新披露文案。
- 选项 A（首发）：保持未签名，Release 说明如实披露（本包已实现该说明与 manifest 字段 `windowsCodeSigning=unsigned`）。
- 选项 B：持有人提供 OV/EV 证书（`.pfx`）后加 `signtool` 双重时间戳签名（`docs/RELEASE_PLAN.md` 3.2 节的目标形态），需要在 CI 增加 secrets 与签名步骤。
- 影响：未签名只影响首次下载的 SmartScreen 提示与信誉，不影响功能；EV 证书可更快建立信誉。

### 5.4 托管地址与发布身份

- 现状：仓库无 remote；`Runner.rc` 里 `CompanyName=com.matrixflow`（反向域名形态，不是法律实体名），根 `LICENSE` 署名 `MatrixFlow AI Contributors`，没有任何真实组织 URL 或维护者联系方式。
- 需要持有人决定：GitHub 仓库归属与名称、是否公开、Release 是否由 Actions 发布、Android 商店是否首发、公开后的安全/问题反馈渠道（`SECURITY.md` 属 OS27）。
- 影响：决定后要设置 remote、开启分支保护、开启 Dependabot 与 secret scanning，然后把真实链接写进 README/OS27 文档。本包**没有编造任何 URL**，也没有配置 remote。

### 5.5 Material Icons 字体署名（CC-BY 4.0）

- 现状：APK 打包引擎的 Material Icons 字体；Flutter 3.32.8 的许可文件是 CC-BY 4.0，要求署名；APK 的 `NOTICES` 中没有该字体署名；`docs/RELEASE_PLAN.md` 错写为 Apache 2.0。
- 选项 A（推荐）：在 README、应用内"关于"和发行说明里加一行署名（例如 "Material Icons by Google, licensed under CC-BY 4.0"），并把 RELEASE_PLAN 的表格改对。成本最低，符合 CC-BY 要求。
- 选项 B：替换为自有图标字体或其它许可的图标集，需要改 `pubspec.yaml` 的 `uses-material-design` 与全部图标引用，属 UI 实验范围，当前暂停。
- 拟修改文件（选项 A）：`README.md`、`docs/RELEASE_PLAN.md`、可选的应用内文案（`l10n.dart` 三语）。**均不在本包改动范围内**（`l10n.dart` 属 OS18/OS19 与集成人）。

## 6. 未测与残余风险

- **正式 Android release APK 未生成**（本机无 keystore，属持有人的秘密）。脚本里 `apksigner`/`aapt2` 的解析与判定逻辑只用本机历史遗留的 debug 签名 APK 验证过（证书 DN 实测为 `CN=Android Debug`）；"正式证书 APK 通过校验"这条路径本身没有端到端跑过，只有"缺签名被拒绝"实测通过。
- **GitHub 托管 runner 全部未执行**（无 remote）。workflow 的 `shell: pwsh` 步骤在 ubuntu-latest 上的可用性没有本机证据（本机只有 Windows PowerShell 5.1，没有 pwsh）；`publish-release` job 从未运行。
- Windows 代码签名未做、未测；Authenticode 状态实测为 `NotSigned`。
- 无 Android 设备：APK 未安装，**没有做"覆盖安装保留数据"的实机升级测试**（本包改了发行脚本与 workflow，但没有改数据路径；升级保留数据依赖 5.1 的包名/证书决定）。
- Maven/Gradle 侧依赖的漏洞通告未查；托管侧 secret scanning（GitHub）未执行，只有本地全历史扫描。
- 没有 distribution 级 `THIRD_PARTY_NOTICES` 汇总文件；Windows 绿色包内的第三方声明未逐条展开核对。
- Windows 版本字符串沿用 Flutter 模板行为：字符串显示为 `1.0.0+1`，数值 `FILEVERSION` 为 `1,0,0,1`。若希望资源管理器显示 `1.0.0.1`，需要改 `windows/runner/Runner.rc` 的 `VERSION_AS_STRING`；本包未改（避免与 OS16 的 Windows runner 工作交叉）。
- `-ValidateOnly` 与 `ExpectedTag` 的失败路径、缺签名拒绝均已实测；`release.yml` 的所有 job 逻辑只做了本地契约测试与静态审查。

## 7. 与现有公共文档的冲突（交给集成人 / OS27）

- `docs/RELEASE_PLAN.md`：Material Icons 写 "Apache 2.0"（实际 CC-BY 4.0）；渠道表写"完全就绪"但没有 remote、tag、签名或托管 runner；产物名 `matrixflow-v1.0.0-android.apk` 与新命名 `matrixflow-v1.0.0+1-android.apk` 不一致；3.2 节与 4 节的 Windows 签名/AUMID/通知 GUID 描述需要持有人核对后再改（本包未核对 AUMID 与通知 GUID 的实际使用）。
- `docs/DEVELOPMENT.md` 的打包表仍只有 `flutter build apk --debug` / `flutter build windows`，未提打包脚本的 staging、清单与签名门槛。
- `docs/ANDROID_PACKAGE_MIGRATION.md` 仍准确（本包未改包名），可补一句"发行脚本在缺签名时拒绝构建"。
- `AGENTS.md`、`docs/HANDOFF.md`、`docs/ARCHITECTURE.md`、`docs/CHANGELOG.md`、开源准备计划：按分工由集成人统一更新，本包未动。

## 8. 下一批依赖建议

- 决定依赖：5.1（包名）、5.2（Android 签名证书）、5.4（托管地址）是"稳定二进制发行"阶段的前置。拿到签名凭据与 remote 之前，任何"已签名/已发布"的说法都不成立。
- OS27（文档与公开入口）依赖本包：需要把第 7 节的冲突改对、补 Material Icons 署名、补 CONTRIBUTING/SECURITY 与真实问题入口。
- 无文件冲突、可并行的包：OS20（Store 命令边界）不与发行脚本/workflow 相交；OS16 独占 Windows runner（本包只读它、未改）；OS18/OS19 与本包无重叠。集成前建议先确认本包提交已并入 main，避免 release.yml 的契约测试与旧版本互相打脸。
- 打完 remote + tag 后建议做的第一件事：跑一次 `workflow_dispatch`（不发布，只观察 preflight 与两个构建 job），再决定是否用 tag 触发完整发布。

## 9. 边界声明（本包没有做的事）

- 未改：`matrixflow-native/lib/**`（Store、设置页、任务 widget、提醒业务代码）、`windows/runner/**`、`integration_test/**`、`test/review/**`、`matrixflow-native/pubspec.yaml`、冻结的 React / Tauri / Capacitor、公共文档（AGENTS / HANDOFF / ARCHITECTURE / CHANGELOG / 实施计划）。
- 未做：未改 `applicationId`、未生成或提交任何秘密、未打 tag、未发布 Release、未推送、未配置 remote、未重写 Git 历史、未开始 OS27。



